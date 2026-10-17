import AppKit
import os.log
import SwiftUI

private let menuDiagLog = Logger(subsystem: "dev.vantage.preview", category: "menu-diag")

/// Retains a closure behind a menu item. NSMenuItem does not retain its
/// target, so the coordinator is kept alive through representedObject.
@MainActor
final class ContextMenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func perform(_ sender: NSMenuItem) {
        menuDiagLog.info("ContextMenuAction fired title='\(sender.title, privacy: .public)'")
        handler()
    }
}

/// Hosts SwiftUI content inside an NSHostingView that serves a native
/// context menu, rebuilt by `makeMenu` at right-click time.
///
/// This mirrors the floating panels' `OverlayHostingView` pattern exactly:
/// the hosting view is an ANCESTOR of the hosted content, so an unhandled
/// rightMouseDown bubbles up the responder chain to it. (A sibling overlay
/// view never receives SwiftUI-dispatched events — that approach left the
/// main grid without a working context menu.) Menu lifetime stays
/// independent from the 4 FPS capture refresh: a SwiftUI .contextMenu is
/// re-evaluated on every thumbnail update and flickers or dismisses an
/// open second-level menu.
struct NativeContextMenu<Content: View>: NSViewRepresentable {
    let makeMenu: () -> NSMenu
    @ViewBuilder let content: () -> Content

    final class MenuHostingView: NSHostingView<Content> {
        var makeMenu: (() -> NSMenu)?

        override func rightMouseDown(with event: NSEvent) {
            guard let menu = makeMenu?() else {
                super.rightMouseDown(with: event)
                return
            }
            menuDiagLog.info("host rightMouseDown popping menu")
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    func makeNSView(context: Context) -> MenuHostingView {
        MenuHostingView(rootView: content())
    }

    func updateNSView(_ view: MenuHostingView, context: Context) {
        view.makeMenu = makeMenu
        view.rootView = content()
    }
}

@MainActor
enum WindowContextMenu {
    /// Per-window context menu shared by main-grid cards and sidebar rows.
    /// Built fresh on every right-click, so hotkey checkmarks always match
    /// the currently resolved slots.
    static func make(
        window: CapturedWindow,
        capture: WindowCaptureService,
        settings: SettingsStore,
        includesOverlayToggle: Bool
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(actionItem(settings.localized("menu.activateWindow")) {
            Task { await capture.select(window.id) }
        })
        menu.addItem(hotKeySubmenu(window: window, capture: capture, settings: settings))

        if includesOverlayToggle {
            menu.addItem(.separator())
            menu.addItem(actionItem(settings.localized("menu.showOverlays")) {
                settings.showOverlays = true
            })
        }
        return menu
    }

    private static func actionItem(
        _ title: String,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let action = ContextMenuAction(handler)
        let item = NSMenuItem(
            title: title,
            action: #selector(ContextMenuAction.perform(_:)),
            keyEquivalent: ""
        )
        item.target = action
        item.representedObject = action
        return item
    }

    private static func hotKeySubmenu(
        window: CapturedWindow,
        capture: WindowCaptureService,
        settings: SettingsStore
    ) -> NSMenuItem {
        let title = settings.localized("menu.assignHotkey")
        let rootItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false

        let currentSlot = capture.hotKeySlot(of: window.id)

        let autoItem = actionItem(settings.localized("hotkey.auto")) {
            settings.setHotKeySlot(nil, for: window.overlayPositionKey)
        }
        autoItem.state = currentSlot == nil ? .on : .off
        submenu.addItem(autoItem)
        submenu.addItem(.separator())

        for slot in 1...HotKeySlotResolver.slotCount {
            let item = actionItem("⌘\(slot)") {
                settings.setHotKeySlot(slot, for: window.overlayPositionKey)
            }
            item.state = currentSlot == slot ? .on : .off
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        return rootItem
    }
}
