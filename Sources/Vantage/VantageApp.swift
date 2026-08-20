import AppKit
import SwiftUI

@main
struct VantageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var captureService: WindowCaptureService
    @StateObject private var overlayController: OverlayWindowController

    init() {
        let settings = SettingsStore()
        let captureService = WindowCaptureService(settings: settings)
        let overlayController = OverlayWindowController(
            captureService: captureService,
            settings: settings
        )

        _settings = StateObject(wrappedValue: settings)
        _captureService = StateObject(wrappedValue: captureService)
        _overlayController = StateObject(wrappedValue: overlayController)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(settings)
                .environmentObject(captureService)
                .environmentObject(overlayController)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    captureService.start()
                    overlayController.start()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            VantageCommands(
                settings: settings,
                captureService: captureService,
                overlayController: overlayController
            )
        }

        Settings {
            PreferencesView()
                .environmentObject(settings)
                .environmentObject(captureService)
                .preferredColorScheme(.dark)
                .frame(width: 520, height: 360)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct VantageCommands: Commands {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var captureService: WindowCaptureService
    @ObservedObject var overlayController: OverlayWindowController

    var body: some Commands {
        CommandMenu(settings.localized("menu.clients")) {
            ForEach(1...9, id: \.self) { number in
                Button(settings.localized("menu.switchClient", values: ["number": "\(number)"])) {
                    guard captureService.windows.indices.contains(number - 1) else { return }
                    captureService.select(captureService.windows[number - 1].id)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [.command])
            }

            Divider()

            Button(settings.localized("menu.nextClient")) {
                captureService.selectRelative(1)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button(settings.localized("menu.previousClient")) {
                captureService.selectRelative(-1)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Divider()

            Button(settings.localized(settings.isPaused ? "menu.resumeCapture" : "menu.pauseCapture")) {
                settings.isPaused.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button(settings.localized(settings.showOverlays ? "menu.hideOverlays" : "menu.showOverlays")) {
                settings.showOverlays.toggle()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button(settings.localized("menu.arrangeOverlays")) {
                overlayController.arrangePanels()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }
}
