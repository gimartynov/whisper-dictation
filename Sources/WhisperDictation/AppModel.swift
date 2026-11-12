import SwiftUI
import Combine

enum Phase {
    case idle
    case recording
    case transcribing
}

final class AppModel: ObservableObject {
    @Published var phase: Phase = .idle
    @Published var text: String = ""
    @Published var level: Float = 0
    @Published var status: String = "Готов"
    @Published var autoInsert: Bool = true
    @Published var lastError: String?
    @Published var needsAccessibility: Bool = false
    @Published var modelMissing: Bool = false
    @Published var downloadProgress: Double?

    var onToggleRecord: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    var onClear: (() -> Void)?
    var onClose: (() -> Void)?
    var onDownloadModel: (() -> Void)?
}
