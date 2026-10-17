import AppKit
import Combine
import os.log
import SwiftUI

private let overlayDiagLog = Logger(subsystem: "dev.vantage.preview", category: "overlay-diag")

@MainActor
final class OverlayWindowController: NSObject, ObservableObject {
    private let captureService: WindowCaptureService
    private let settings: SettingsStore
    private var panels: [CGWindowID: OverlayPanel] = [:]
    // Panels whose window vanished stay in limbo (hidden) for a grace window
    // instead of being closed immediately: fullscreen toggles, minimize, and
    // transient empty titles all recreate the window within seconds, and
    // rebinding the same panel preserves its position and drag/hover state.
    private var missingPanels: [CGWindowID: (panel: OverlayPanel, since: Date)] = [:]
    private let missingPanelGrace: TimeInterval = 4.0
    // Windows must be continuously present for this long before earning a
    // panel: focus switches (Alt-Tab) make games spawn brief helper windows
    // that pass all filters, and creating panels for them pops panels in at
    // default slots for a fraction of a second.
    private var pendingNewWindows: [CGWindowID: Date] = [:]
    private let newWindowSettleDelay: TimeInterval = 0.5
    // A changed position key must stay stable this long before the panel
    // migrates to the new key's remembered origin: app switches can make a
    // window's title flip-flop, and without the delay the panel ping-pongs
    // between the two titles' saved positions on every Alt-Tab.
    private let positionKeyStabilityDelay: TimeInterval = 1.0
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingLayout = false
    private var isApplyingMenuSetting = false
    private var isOverlayMenuOpen = false
    private var wasApplicationActiveBeforeMenu = false

    init(captureService: WindowCaptureService, settings: SettingsStore) {
        self.captureService = captureService
        self.settings = settings
        super.init()
    }

    func start() {
        guard cancellables.isEmpty else { return }

        captureService.$windows
            .sink { [weak self] windows in
                self?.syncPanels(with: windows)
            }
            .store(in: &cancellables)

        settings.$showOverlays
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)

        settings.$alwaysOnTop
            .sink { [weak self] _ in self?.applyWindowLevels() }
            .store(in: &cancellables)

        settings.$overlayOpacity
            .sink { [weak self] _ in
                guard let self, !self.isApplyingMenuSetting else { return }
                self.applyAppearance()
            }
            .store(in: &cancellables)

        settings.$previewWidth
            .sink { [weak self] _ in
                guard let self, !self.isApplyingMenuSetting else { return }
                self.resizePanels()
            }
            .store(in: &cancellables)

        settings.$previewLayout
            .dropFirst()
            .sink { [weak self] _ in self?.arrangePanels() }
            .store(in: &cancellables)

        settings.$language
            .sink { [weak self] _ in self?.refreshMenus() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)

        applyVisibility()
        applyWindowLevels()
        applyAppearance()
        resizePanels()
    }

    func arrangePanels() {
        let visiblePanels = captureService.windows.compactMap { panels[$0.id] }
        guard !visiblePanels.isEmpty, let screen = NSScreen.main else { return }

        let gap = 10.0
        let margin = 18.0
        let frame = screen.visibleFrame
        let availableWidth = max(1, frame.width - margin * 2)
        let availableHeight = max(1, frame.height - margin * 2)
        let count = visiblePanels.count

        let panelSize: NSSize
        let columns: Int

        switch settings.previewLayout {
        case .vertical:
            let widthByHeight = (availableHeight - Double(max(0, count - 1)) * gap)
                / Double(max(1, count)) / 0.625
            let width = min(settings.previewWidth, availableWidth, widthByHeight)
            panelSize = NSSize(width: width, height: width * 0.625)
            columns = 1
        case .horizontal:
            let widthByRow = (availableWidth - Double(max(0, count - 1)) * gap)
                / Double(max(1, count))
            let width = min(settings.previewWidth, widthByRow, availableHeight / 0.625)
            panelSize = NSSize(width: width, height: width * 0.625)
            columns = count
        case .grid:
            let preferredColumns = max(1, Int((availableWidth + gap) / (settings.previewWidth + gap)))
            columns = min(count, preferredColumns)
            let rows = Int(ceil(Double(count) / Double(columns)))
            let widthByColumns = (availableWidth - Double(max(0, columns - 1)) * gap)
                / Double(columns)
            let widthByRows = (availableHeight - Double(max(0, rows - 1)) * gap)
                / Double(rows) / 0.625
            let width = min(settings.previewWidth, widthByColumns, widthByRows)
            panelSize = NSSize(width: width, height: width * 0.625)
        }

        isApplyingLayout = true
        defer { isApplyingLayout = false }

        for (index, panel) in visiblePanels.enumerated() {
            let origin: NSPoint

            switch settings.previewLayout {
            case .vertical:
                origin = NSPoint(
                    x: frame.maxX - panelSize.width - margin,
                    y: frame.maxY - panelSize.height - margin - Double(index) * (panelSize.height + gap)
                )
            case .horizontal:
                origin = NSPoint(
                    x: frame.minX + margin + Double(index) * (panelSize.width + gap),
                    y: frame.minY + margin
                )
            case .grid:
                let column = index % columns
                let row = index / columns
                origin = NSPoint(
                    x: frame.maxX - margin - Double(columns - column) * panelSize.width - Double(columns - column - 1) * gap,
                    y: frame.maxY - margin - panelSize.height - Double(row) * (panelSize.height + gap)
                )
            }

            let frame = NSRect(origin: origin, size: panelSize)
            panel.setFrame(frame, display: true, animate: true)
            savePosition(of: panel, origin: frame.origin)
        }
    }

    func setPreviewWidth(_ width: Double) {
        let clampedWidth = min(max(width, 180), 460)
        isApplyingMenuSetting = true
        settings.previewWidth = clampedWidth
        isApplyingMenuSetting = false
        resizePanels()
    }

    func setOverlayOpacity(_ opacity: Double) {
        let clampedOpacity = min(max(opacity, 0.35), 1)
        isApplyingMenuSetting = true
        settings.overlayOpacity = clampedOpacity
        isApplyingMenuSetting = false
        applyAppearance()
    }

    private func syncPanels(with windows: [CapturedWindow]) {
        let validIDs = Set(windows.map(\.id))
        let now = Date.now

        for id in Array(panels.keys) where !validIDs.contains(id) {
            guard let panel = panels[id] else { continue }
            panel.orderOut(nil)
            missingPanels[id] = (panel, now)
            panels[id] = nil
        }

        for id in Array(missingPanels.keys) {
            guard let entry = missingPanels[id],
                  now.timeIntervalSince(entry.since) >= missingPanelGrace else { continue }
            entry.panel.close()
            missingPanels[id] = nil
        }

        // Windows that vanished before settling never earned a panel.
        pendingNewWindows = pendingNewWindows.filter { validIDs.contains($0.key) }

        var newPanels: [OverlayPanel] = []
        for window in windows {
            if let panel = panels[window.id] {
                let newKey = window.overlayPositionKey
                if panel.positionKey != newKey {
                    if panel.pendingPositionKey != newKey {
                        panel.pendingPositionKey = newKey
                        panel.pendingKeySince = now
                    }
                    if now.timeIntervalSince(panel.pendingKeySince) >= positionKeyStabilityDelay {
                        panel.pendingPositionKey = nil
                        migratePanel(panel, to: newKey)
                    }
                    // Unstable key (title flip-flop on app switch): keep the
                    // panel where it is until the new identity settles.
                } else {
                    panel.pendingPositionKey = nil
                }
            } else if let rebound = takeMissingPanel(for: window) {
                pendingNewWindows[window.id] = nil
                rebind(rebound, to: window)
                panels[window.id] = rebound
            } else if let firstSeen = pendingNewWindows[window.id] {
                if now.timeIntervalSince(firstSeen) >= newWindowSettleDelay {
                    pendingNewWindows[window.id] = nil
                    let panel = makePanel(for: window)
                    panels[window.id] = panel
                    newPanels.append(panel)
                }
            } else {
                pendingNewWindows[window.id] = now
            }
        }

        applyVisibility()
        if !newPanels.isEmpty {
            restoreOrPlace(newPanels)
        }
    }

    /// Finds a limbo panel to revive for a rediscovered window. Exact position-key
    /// match first (window recreated with the same identity, e.g. fullscreen
    /// toggle); otherwise a single unambiguous candidate from the same process,
    /// which covers a title change that happened while the window was gone.
    private func takeMissingPanel(for window: CapturedWindow) -> OverlayPanel? {
        let key = window.overlayPositionKey
        if let exact = missingPanels.first(where: { $0.value.panel.positionKey == key }) {
            missingPanels[exact.key] = nil
            return exact.value.panel
        }

        let identity = window.bundleIdentifier ?? window.ownerName
        let sameOwner = missingPanels.filter {
            $0.value.panel.ownerProcessIdentifier == window.processIdentifier
                && $0.value.panel.ownerIdentity == identity
        }
        guard sameOwner.count == 1, let only = sameOwner.first else { return nil }
        missingPanels[only.key] = nil
        return only.value.panel
    }

    /// Commits a position-key change that has stayed stable long enough:
    /// migrate to the new identity's remembered origin (character name
    /// resolved, per-identity layout), or adopt the current spot when the
    /// identity has never been seen so the panel does not move at all.
    private func migratePanel(_ panel: OverlayPanel, to newKey: String) {
        panel.positionKey = newKey
        guard let origin = settings.savedOverlayOrigin(for: newKey) else {
            savePosition(of: panel, origin: panel.frame.origin)
            return
        }
        guard let screen = screenFor(origin: NSPoint(x: origin.x, y: origin.y)) ?? NSScreen.main else {
            return
        }
        let size = NSSize(width: settings.previewWidth, height: settings.previewWidth * 0.625)
        let targetFrame = clampedFrame(
            origin: NSPoint(x: origin.x, y: origin.y),
            size: size,
            within: screen.visibleFrame
        )
        if hypot(panel.frame.origin.x - targetFrame.origin.x,
                  panel.frame.origin.y - targetFrame.origin.y) > 8 {
            isApplyingLayout = true
            panel.setFrame(targetFrame, display: true, animate: true)
            isApplyingLayout = false
            savePosition(of: panel, origin: targetFrame.origin)
        }
    }

    /// Revives a limbo panel for a new windowID without touching its frame:
    /// the panel reappears exactly where it was instead of flying in from a
    /// default slot. Content and menu are rebuilt because both bind the ID.
    private func rebind(_ panel: OverlayPanel, to window: CapturedWindow) {
        panel.windowIDValue = window.id
        panel.positionKey = window.overlayPositionKey
        panel.pendingPositionKey = nil
        panel.ownerProcessIdentifier = window.processIdentifier
        panel.ownerIdentity = window.bundleIdentifier ?? window.ownerName
        attachContent(to: panel, for: window)
        // First occurrence of the new identity: adopt the kept position so it
        // survives the next launch instead of being resurrected from nothing.
        if settings.savedOverlayOrigin(for: panel.positionKey) == nil {
            savePosition(of: panel, origin: panel.frame.origin)
        }
    }

    private func makePanel(for window: CapturedWindow) -> OverlayPanel {
        let width = settings.previewWidth
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: width * 0.625),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.windowIDValue = window.id
        panel.positionKey = window.overlayPositionKey
        panel.ownerProcessIdentifier = window.processIdentifier
        panel.ownerIdentity = window.bundleIdentifier ?? window.ownerName
        panel.delegate = self
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // macOS 27: automatic background-move is broken for NSHostingView content;
        // OverlayPanel moves itself via PanelDragTracker in sendEvent(_:).
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.alphaValue = settings.overlayOpacity
        attachContent(to: panel, for: window)
        return panel
    }

    private func attachContent(to panel: OverlayPanel, for window: CapturedWindow) {
        let hostingView = OverlayHostingView(
            rootView: OverlayThumbnailView(windowID: window.id)
                .environmentObject(captureService)
                .environmentObject(settings)
        )
        let menu = makeOverlayMenu(for: window.id)
        hostingView.contextMenu = menu
        hostingView.onMenuWillPresent = { [weak self] menu in
            self?.beginOverlayMenu(menu)
        }
        panel.overlayMenu = menu
        panel.hostingView = hostingView
        panel.contentView = hostingView
    }

    private func makeOverlayMenu(for windowID: CGWindowID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let activateItem = NSMenuItem(
            title: settings.localized("menu.activateWindow"),
            action: #selector(activateWindowFromMenu(_:)),
            keyEquivalent: ""
        )
        activateItem.target = self
        activateItem.representedObject = NSNumber(value: windowID)
        menu.addItem(activateItem)

        menu.addItem(hotKeySlotSubmenu(for: windowID))
        menu.addItem(.separator())

        menu.addItem(submenuItem(
            title: settings.localized("menu.size"),
            values: [180.0, 240.0, 300.0, 360.0],
            currentValue: settings.previewWidth,
            formatter: { "\(Int($0))" },
            action: #selector(setPreviewWidthFromMenu(_:))
        ))
        menu.addItem(submenuItem(
            title: settings.localized("menu.opacity"),
            values: [0.50, 0.70, 0.85, 1.0],
            currentValue: settings.overlayOpacity,
            formatter: { "\(Int($0 * 100))%" },
            action: #selector(setOpacityFromMenu(_:))
        ))

        let refreshTitle = settings.localized("menu.refreshRate")
        let refreshItem = NSMenuItem(title: refreshTitle, action: nil, keyEquivalent: "")
        let refreshMenu = NSMenu(title: refreshTitle)
        refreshMenu.autoenablesItems = false
        for rate in PreviewRefreshRate.allCases {
            let item = NSMenuItem(
                title: rate.title(for: settings.language),
                action: #selector(setRefreshRateFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: rate.rawValue)
            item.state = settings.previewRefreshRate == rate ? .on : .off
            refreshMenu.addItem(item)
        }
        refreshItem.submenu = refreshMenu
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let hideItem = NSMenuItem(
            title: settings.localized("menu.hideOverlays"),
            action: #selector(hideOverlaysFromMenu(_:)),
            keyEquivalent: ""
        )
        hideItem.target = self
        menu.addItem(hideItem)
        return menu
    }

    /// "Hotkey" submenu: pins this panel's client to a ⌘1-9 slot or releases
    /// it to auto. State marks reflect the *resolved* slot (what ⌘N does
    /// right now). Unlike the other setting submenus they cannot rely on
    /// menuWillOpen alone: the marks must be correct at BUILD time, because
    /// adding a checkmark to an already-displayed submenu relayouts it (the
    /// state column appears) and the whole submenu visibly flickers.
    private func hotKeySlotSubmenu(for windowID: CGWindowID) -> NSMenuItem {
        overlayDiagLog.info("hotkey submenu built windowID=\(windowID)")
        let title = settings.localized("menu.assignHotkey")
        let rootItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false

        let currentSlot = HotKeySlotResolver.slot(
            of: windowID,
            windows: captureService.windows,
            assignments: settings.hotKeyAssignments
        )

        let autoItem = NSMenuItem(
            title: settings.localized("hotkey.auto"),
            action: #selector(setHotKeySlotFromMenu(_:)),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.representedObject = NSDictionary(dictionary: [
            "windowID": NSNumber(value: windowID),
            "slot": NSNumber(value: 0)
        ])
        autoItem.state = currentSlot == nil ? .on : .off
        submenu.addItem(autoItem)
        submenu.addItem(.separator())

        for slot in 1...HotKeySlotResolver.slotCount {
            let item = NSMenuItem(
                title: "⌘\(slot)",
                action: #selector(setHotKeySlotFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSDictionary(dictionary: [
                "windowID": NSNumber(value: windowID),
                "slot": NSNumber(value: slot)
            ])
            item.state = currentSlot == slot ? .on : .off
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        return rootItem
    }

    private func submenuItem(
        title: String,
        values: [Double],
        currentValue: Double,
        formatter: (Double) -> String,
        action: Selector
    ) -> NSMenuItem {
        let rootItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false

        for value in values {
            let item = NSMenuItem(title: formatter(value), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: value)
            item.state = abs(currentValue - value) < 0.01 ? .on : .off
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        return rootItem
    }

    @objc private func activateWindowFromMenu(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        let windowID = CGWindowID(number.uint32Value)
        Task { [weak self] in
            await self?.captureService.select(windowID)
        }
    }

    @objc private func setHotKeySlotFromMenu(_ sender: NSMenuItem) {
        overlayDiagLog.info("setHotKeySlotFromMenu enter title=\(sender.title, privacy: .public)")
        guard let info = sender.representedObject as? NSDictionary,
              let windowIDNumber = info["windowID"] as? NSNumber,
              let slotNumber = info["slot"] as? NSNumber
        else {
            overlayDiagLog.error("setHotKeySlotFromMenu payload cast failed")
            return
        }
        guard let window = captureService.window(withID: CGWindowID(windowIDNumber.uint32Value)) else {
            overlayDiagLog.error("setHotKeySlotFromMenu window not in list id=\(windowIDNumber.uint32Value)")
            return
        }
        let slot = slotNumber.intValue
        overlayDiagLog.info("setHotKeySlotFromMenu dispatch slot=\(slot) windowID=\(windowIDNumber.uint32Value)")
        DispatchQueue.main.async { [weak self] in
            self?.settings.setHotKeySlot(slot == 0 ? nil : slot, for: window.overlayPositionKey)
        }
    }

    @objc private func setPreviewWidthFromMenu(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        let width = number.doubleValue
        DispatchQueue.main.async { [weak self] in
            self?.setPreviewWidth(width)
        }
    }

    @objc private func setOpacityFromMenu(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        let opacity = number.doubleValue
        DispatchQueue.main.async { [weak self] in
            self?.setOverlayOpacity(opacity)
        }
    }

    @objc private func setRefreshRateFromMenu(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber,
              let rate = PreviewRefreshRate(rawValue: number.intValue) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.captureService.setRefreshRate(rate)
        }
    }

    @objc private func hideOverlaysFromMenu(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showOverlays = false
        }
    }

    private func restoreOrPlace(_ newPanels: [OverlayPanel]) {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: settings.previewWidth, height: settings.previewWidth * 0.625)
        var unpositioned: [OverlayPanel] = []

        isApplyingLayout = true
        for panel in newPanels {
            guard let origin = settings.savedOverlayOrigin(for: panel.positionKey) else {
                unpositioned.append(panel)
                continue
            }

            let savedOrigin = NSPoint(x: origin.x, y: origin.y)
            let targetScreen = screenFor(origin: savedOrigin) ?? screen
            let frame = clampedFrame(origin: savedOrigin, size: size, within: targetScreen.visibleFrame)
            panel.setFrame(frame, display: true)
            savePosition(of: panel, origin: frame.origin)
        }
        isApplyingLayout = false

        guard !unpositioned.isEmpty else { return }
        placeUnpositioned(unpositioned, size: size, within: screen.visibleFrame)
    }

    private func placeUnpositioned(
        _ newPanels: [OverlayPanel],
        size: NSSize,
        within visibleFrame: NSRect
    ) {
        let gap = 10.0
        let margin = 18.0
        let availableWidth = max(1, visibleFrame.width - margin * 2)
        let availableHeight = max(1, visibleFrame.height - margin * 2)
        let columns = max(1, Int((availableWidth + gap) / (size.width + gap)))
        let rows = max(1, Int((availableHeight + gap) / (size.height + gap)))
        var occupied = panels.values
            .filter { panel in !newPanels.contains(where: { $0 === panel }) }
            .map(\.frame)

        isApplyingLayout = true
        defer { isApplyingLayout = false }

        for panel in newPanels {
            var placedFrame: NSRect?
            for slot in 0..<(columns * rows) {
                let column = slot % columns
                let row = slot / columns
                let origin = NSPoint(
                    x: visibleFrame.maxX - margin - size.width - Double(column) * (size.width + gap),
                    y: visibleFrame.maxY - margin - size.height - Double(row) * (size.height + gap)
                )
                let candidate = NSRect(origin: origin, size: size)
                if !occupied.contains(where: { $0.intersects(candidate) }) {
                    placedFrame = candidate
                    break
                }
            }

            let frame = placedFrame ?? clampedFrame(
                origin: NSPoint(x: visibleFrame.maxX - margin - size.width, y: visibleFrame.minY + margin),
                size: size,
                within: visibleFrame
            )
            panel.setFrame(frame, display: true)
            occupied.append(frame)
            savePosition(of: panel, origin: frame.origin)
        }
    }

    private func applyVisibility() {
        let shouldShow = settings.showOverlays && (!NSApp.isActive || isOverlayMenuOpen)
        overlayDiagLog.info("applyVisibility show=\(shouldShow) appActive=\(NSApp.isActive) menuOpen=\(self.isOverlayMenuOpen) panels=\(self.panels.count)")
        for panel in panels.values {
            if shouldShow {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
    }

    private func updateMenuState(_ menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                updateMenuState(submenu)
            }

            guard let number = item.representedObject as? NSNumber else { continue }
            if item.action == #selector(setPreviewWidthFromMenu(_:)) {
                item.state = abs(settings.previewWidth - number.doubleValue) < 0.01 ? .on : .off
            } else if item.action == #selector(setOpacityFromMenu(_:)) {
                item.state = abs(settings.overlayOpacity - number.doubleValue) < 0.01 ? .on : .off
            } else if item.action == #selector(setRefreshRateFromMenu(_:)) {
                item.state = settings.previewRefreshRate.rawValue == number.intValue ? .on : .off
            }
        }
    }

    /// Hotkey submenu items carry windowID + slot in a dictionary rather than
    /// a plain NSNumber, so their state is refreshed separately from the other
    /// setting submenus.
    private func updateHotKeyMenuState(_ menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                updateHotKeyMenuState(submenu)
            }

            guard item.action == #selector(setHotKeySlotFromMenu(_:)),
                  let info = item.representedObject as? NSDictionary,
                  let windowIDNumber = info["windowID"] as? NSNumber,
                  let slotNumber = info["slot"] as? NSNumber
            else { continue }

            let current = HotKeySlotResolver.slot(
                of: CGWindowID(windowIDNumber.uint32Value),
                windows: captureService.windows,
                assignments: settings.hotKeyAssignments
            )
            let slotValue = slotNumber.intValue
            item.state = (slotValue == 0 ? current == nil : current == slotValue) ? .on : .off
        }
    }

    private func beginOverlayMenu(_ menu: NSMenu) {
        overlayDiagLog.info("beginOverlayMenu")
        wasApplicationActiveBeforeMenu = NSApp.isActive
        isOverlayMenuOpen = true
        updateMenuState(menu)
        updateHotKeyMenuState(menu)
        applyVisibility()
    }

    private func endOverlayMenu() {
        overlayDiagLog.info("endOverlayMenu appActive=\(NSApp.isActive) wasActiveBefore=\(self.wasApplicationActiveBeforeMenu)")
        isOverlayMenuOpen = false

        if !wasApplicationActiveBeforeMenu, NSApp.isActive {
            NSApp.deactivate()
        }

        DispatchQueue.main.async { [weak self] in
            self?.applyVisibility()
        }
    }

    private func applyWindowLevels() {
        for panel in panels.values {
            panel.level = settings.alwaysOnTop ? .floating : .normal
        }
    }

    private func applyAppearance() {
        for panel in panels.values {
            panel.alphaValue = settings.overlayOpacity
        }
    }

    private func refreshMenus() {
        for (windowID, panel) in panels {
            let menu = makeOverlayMenu(for: windowID)
            panel.overlayMenu = menu
            panel.hostingView?.contextMenu = menu
        }
    }

    private func resizePanels() {
        let width = settings.previewWidth
        isApplyingLayout = true
        defer { isApplyingLayout = false }

        for panel in panels.values {
            guard let screen = screenFor(frame: panel.frame) ?? NSScreen.main else { continue }
            let frame = clampedFrame(
                origin: panel.frame.origin,
                size: NSSize(width: width, height: width * 0.625),
                within: screen.visibleFrame
            )
            panel.setFrame(frame, display: true)
            savePosition(of: panel, origin: frame.origin)
        }
    }

    private func clampedFrame(origin: NSPoint, size: NSSize, within visibleFrame: NSRect) -> NSRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func screenFor(origin: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.contains(origin) }
    }

    private func screenFor(frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.intersects(frame) }
    }

    private func savePosition(of panel: OverlayPanel, origin: NSPoint) {
        guard !panel.positionKey.isEmpty else { return }
        settings.saveOverlayOrigin(CGPoint(x: origin.x, y: origin.y), for: panel.positionKey)
    }
}

extension OverlayWindowController: NSWindowDelegate, NSMenuDelegate {
    func windowDidMove(_ notification: Notification) {
        guard !isApplyingLayout,
              let panel = notification.object as? OverlayPanel else { return }
        savePosition(of: panel, origin: panel.frame.origin)
    }

    func menuWillOpen(_ menu: NSMenu) {
        overlayDiagLog.info("menuWillOpen title='\(menu.title, privacy: .public)' items=\(menu.items.count)")
        updateMenuState(menu)
        updateHotKeyMenuState(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        overlayDiagLog.info("menuDidClose title='\(menu.title, privacy: .public)'")
        endOverlayMenu()
    }

}

final class OverlayPanel: NSPanel {
    var windowIDValue: CGWindowID = 0
    var positionKey = ""
    /// A changed identity being observed for stability before the panel
    /// migrates to its remembered origin (guards against title flip-flop).
    var pendingPositionKey: String?
    var pendingKeySince = Date.distantPast
    var ownerProcessIdentifier: pid_t = 0
    var ownerIdentity = ""
    var overlayMenu: NSMenu?
    weak var hostingView: OverlayMenuHosting?

    // macOS 27: isMovableByWindowBackground no longer moves NSHostingView-backed
    // windows, so the panel moves itself from mouse events (PanelDragTracker).
    // Drag events consumed here never reach the hosting view, so the SwiftUI
    // click-vs-drag guard cannot see the drag; instead the mouse-up that ends
    // a real drag (beyond the click threshold) is swallowed, which keeps the
    // hosted button from firing a window switch after a long-press drag.
    var dragTracker = PanelDragTracker()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragTracker.begin(
                mouseLocationInWindow: event.locationInWindow,
                windowOrigin: frame.origin
            )
        case .leftMouseDragged:
            if let newOrigin = dragTracker.dragged(
                mouseLocationInWindow: event.locationInWindow,
                currentOrigin: frame.origin
            ) {
                setFrameOrigin(newOrigin)
                return
            }
        case .leftMouseUp:
            let wasDrag = dragTracker.movedBeyondClickThreshold
            dragTracker.end()
            if wasDrag { return }
        default:
            break
        }
        super.sendEvent(event)
    }
}

@MainActor
protocol OverlayMenuHosting: AnyObject {
    var contextMenu: NSMenu? { get set }
}

final class OverlayHostingView<Content: View>: NSHostingView<Content>, OverlayMenuHosting {
    var contextMenu: NSMenu?
    var onMenuWillPresent: ((NSMenu) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenu else {
            super.rightMouseDown(with: event)
            return
        }

        onMenuWillPresent?(menu)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
