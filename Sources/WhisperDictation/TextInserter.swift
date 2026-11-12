import AppKit
import ApplicationServices

/// Вставляет текст в активное приложение через буфер обмена + Cmd+V.
enum TextInserter {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func insert(_ text: String, activating app: NSRunningApplication? = nil) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let paste = {
            sendPaste(pasteboard: pasteboard, previous: previous)
        }

        if let app, !app.isActive, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: paste)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: paste)
        }
    }

    private static func sendPaste(pasteboard: NSPasteboard, previous: String?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            let source = CGEventSource(stateID: .hidSystemState)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)

            if let previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
