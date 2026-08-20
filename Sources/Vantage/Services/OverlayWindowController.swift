import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController: NSObject, ObservableObject {
    private let captureService: WindowCaptureService
    private let settings: SettingsStore
    private var panels: [CGWindowID: OverlayPanel] = [:]
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

        for (id, panel) in panels where !validIDs.contains(id) {
            panel.close()
            panels[id] = nil
        }

        var newPanels: [OverlayPanel] = []
        for window in windows {
            if let panel = panels[window.id] {
                panel.positionKey = window.overlayPositionKey
            } else {
                let panel = makePanel(for: window)
                panels[window.id] = panel
                newPanels.append(panel)
            }
        }

        applyVisibility()
        if !newPanels.isEmpty {
            restoreOrPlace(newPanels)
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
        panel.delegate = self
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.alphaValue = settings.overlayOpacity
        return panel
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
        DispatchQueue.main.async { [weak self] in
            self?.captureService.select(windowID)
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

    private func beginOverlayMenu(_ menu: NSMenu) {
        wasApplicationActiveBeforeMenu = NSApp.isActive
        isOverlayMenuOpen = true
        updateMenuState(menu)
        applyVisibility()
    }

    private func endOverlayMenu() {
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
        updateMenuState(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        endOverlayMenu()
    }

}

final class OverlayPanel: NSPanel {
    var windowIDValue: CGWindowID = 0
    var positionKey = ""
    var overlayMenu: NSMenu?
    weak var hostingView: OverlayMenuHosting?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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
