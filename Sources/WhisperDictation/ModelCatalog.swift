import Foundation

/// Одна модель Whisper: файл, откуда качать, чем проверять и как её называть в UI.
struct WhisperModel: Identifiable, Equatable {
    let id: String
    let title: String
    let fileName: String
    let url: URL
    let sha256: String
    let minSize: Int64
    let sizeLabel: String
    let note: String

    static func == (lhs: WhisperModel, rhs: WhisperModel) -> Bool { lhs.id == rhs.id }
}

/// Каталог моделей и выбор подходящей под железо.
enum ModelCatalog {
    /// large-v3-turbo: лучшее качество, ~1,6 ГБ, комфортно на Apple Silicon.
    static let turbo = WhisperModel(
        id: "turbo",
        title: "Turbo",
        fileName: "ggml-large-v3-turbo.bin",
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
        sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
        minSize: 1_500_000_000,
        sizeLabel: "1,6 ГБ",
        note: "Точнее, но тяжелее"
    )

    /// small: ~466 МБ, в разы быстрее на слабых Intel-маках.
    static let small = WhisperModel(
        id: "small",
        title: "Small",
        fileName: "ggml-small.bin",
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
        sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
        minSize: 400_000_000,
        sizeLabel: "466 МБ",
        note: "Быстрее на слабом железе"
    )

    static var all: [WhisperModel] { [turbo, small] }

    static func model(id: String) -> WhisperModel {
        all.first { $0.id == id } ?? turbo
    }

    /// На Intel рекомендуем small: large-v3-turbo на 4-ядерном i5 работает
    /// в 3–4 раза медленнее. На Apple Silicon — turbo.
    static var recommendedID: String {
        #if arch(x86_64)
        return small.id
        #else
        return turbo.id
        #endif
    }

    static func installedURL(for model: WhisperModel) -> URL? {
        let fm = FileManager.default
        let url = WhisperEngine.modelsDir.appendingPathComponent(model.fileName)
        guard let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64,
              size >= model.minSize else { return nil }
        return url
    }
}
