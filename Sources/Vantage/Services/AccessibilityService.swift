import AppKit
import ApplicationServices

enum WindowActivationResult: Equatable {
    case success
    case permissionRequired
    case processUnavailable
    case targetWindowNotFound
    case activationFailed
}

enum AccessibilityService {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openSettings()
        }
        return trusted
    }

    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]

        for rawURL in candidates {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) { break }
        }
    }

    @MainActor
    @discardableResult
    static func activate(
        processIdentifier: pid_t,
        windowID: CGWindowID,
        windowTitle: String,
        windowFrame: CGRect
    ) -> WindowActivationResult {
        guard let applicationProcess = NSRunningApplication(processIdentifier: processIdentifier) else {
            return .processUnavailable
        }

        guard !applicationProcess.isTerminated else {
            return .activationFailed
        }

        guard AXIsProcessTrusted() else {
            _ = requestPermission()
            return .permissionRequired
        }

        // Bring only the owning process forward. Do not use activateAllWindows,
        // which can expose an unrelated window from the same application.
        _ = applicationProcess.activate(options: [])

        let application = AXUIElementCreateApplication(processIdentifier)

        // Some applications only expose a complete AX window list after they
        // become frontmost. This is a best-effort hint; AXRaise below remains
        // the operation that actually selects the target window.
        _ = AXUIElementSetAttributeValue(
            application,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )

        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard result == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return .targetWindowNotFound
        }

        let target: AXUIElement?
        let windowIDMatches = windows.filter { axWindowID($0) == windowID }
        if windowIDMatches.count == 1 {
            target = windowIDMatches[0]
        } else {
            let exactTitleMatches = windows.filter { exactTitleMatch($0, title: windowTitle) }
            let geometryMatches = windows.filter { exactGeometryMatch($0, frame: windowFrame) }
            let titleAndGeometryMatches = exactTitleMatches.filter {
                exactGeometryMatch($0, frame: windowFrame)
            }

            if titleAndGeometryMatches.count == 1 {
                target = titleAndGeometryMatches[0]
            } else if exactTitleMatches.count == 1 {
                target = exactTitleMatches[0]
            } else if exactTitleMatches.isEmpty, geometryMatches.count == 1 {
                target = geometryMatches[0]
            } else {
                // Duplicate titles or geometry matches without a unique AX
                // window number are ambiguous. Never guess between them.
                target = nil
            }
        }

        guard let target else {
            return .targetWindowNotFound
        }

        guard AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success else {
            return .activationFailed
        }

        // AXRaise is sufficient for apps that do not expose writable Main or
        // Focused attributes (common with Wine and game compatibility layers).
        _ = AXUIElementSetAttributeValue(
            target,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return .success
    }

    private static func exactTitleMatch(_ window: AXUIElement, title: String) -> Bool {
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        return (titleValue as? String) == title
    }

    private static func axWindowID(_ window: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        let attribute = "AXWindowNumber" as CFString
        guard AXUIElementCopyAttributeValue(window, attribute, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }

        return CGWindowID(number.uint32Value)
    }

    private static func exactGeometryMatch(_ window: AXUIElement, frame: CGRect) -> Bool {
        guard let position = pointValue(window, attribute: kAXPositionAttribute as CFString),
              let size = sizeValue(window, attribute: kAXSizeAttribute as CFString)
        else {
            return false
        }

        let candidate = CGRect(origin: position, size: size)
        return abs(candidate.origin.x - frame.origin.x) <= 3
            && abs(candidate.origin.y - frame.origin.y) <= 3
            && abs(candidate.width - frame.width) <= 3
            && abs(candidate.height - frame.height) <= 3
    }

    private static func pointValue(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

}
