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

    private struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private static func snapshot() -> Snapshot {
        let pb = NSPasteboard.general
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            items.append(dict)
        }
        return Snapshot(items: items)
    }

    private static func restore(_ snapshot: Snapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let objects = snapshot.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(objects)
    }

    /// Возвращает false, если нет разрешения Accessibility или текста.
    @discardableResult
    static func insert(_ text: String, activating app: NSRunningApplication? = nil) -> Bool {
        guard !text.isEmpty else { return false }
        guard AXIsProcessTrusted() else {
            requestAccess()
            return false
        }

        let pasteboard = NSPasteboard.general
        let saved = snapshot()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChange = pasteboard.changeCount

        let paste = {
            sendPaste(saved: saved, ourChange: ourChange)
        }

        if let app, !app.isActive, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: paste)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: paste)
        }
        return true
    }

    private static func sendPaste(saved: Snapshot, ourChange: Int) {
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let pb = NSPasteboard.general
                // Не затираем то, что пользователь успел скопировать сам.
                guard pb.changeCount == ourChange else { return }
                restore(saved)
            }
        }
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
