import Foundation

/// Держит локальный whisper-server (whisper.cpp) и шлёт ему WAV на распознавание.
final class WhisperEngine {
    static let port: UInt16 = 25_400
    static let modelName = "ggml-large-v3-turbo.bin"

    static let modelURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!

    /// Папка приложения в ~/Library/Application Support
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("WhisperDictation", isDirectory: true)
    }

    static var modelsDir: URL {
        supportDir.appendingPathComponent("models", isDirectory: true)
    }

    static var installedModel: URL {
        modelsDir.appendingPathComponent(modelName)
    }

    /// Для разработки: путь к уже скачанному файлу модели через переменную
    /// окружения WD_DEV_MODEL. В обычном запуске не используется.
    static var devModel: URL? {
        guard let path = ProcessInfo.processInfo.environment["WD_DEV_MODEL"],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Первый подходящий путь к модели или nil.
    static func findModel() -> URL? {
        let fm = FileManager.default
        var candidates = [installedModel]
        if let dev = devModel { candidates.append(dev) }
        for candidate in candidates {
            if let size = try? fm.attributesOfItem(atPath: candidate.path)[.size] as? Int64,
               size > 100_000_000 {
                return candidate
            }
        }
        return nil
    }

    /// Встроенный whisper-server, иначе системный из Homebrew.
    static var serverBinary: String {
        if let url = Bundle.main.url(forResource: "whisper-server", withExtension: nil, subdirectory: "whisper"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url.path
        }
        return "/opt/homebrew/bin/whisper-server"
    }

    var modelPath: String
    private var process: Process?
    private let logURL = URL(fileURLWithPath: "/tmp/whisper-dictation-server.log")

    init(modelPath: String = WhisperEngine.findModel()?.path ?? "") {
        self.modelPath = modelPath
    }

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(Self.port)")!
    }

    func ensureRunning() async -> Bool {
        if await ping() { return true }
        guard FileManager.default.isExecutableFile(atPath: Self.serverBinary) else { return false }
        guard FileManager.default.fileExists(atPath: modelPath) else { return false }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.serverBinary)
        p.arguments = [
            "-m", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(Self.port)",
            "-t", "6",
            "-l", "ru"
        ]
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            p.standardOutput = handle
            p.standardError = handle
        }
        do {
            try p.run()
            process = p
        } catch {
            return false
        }

        for _ in 0..<240 {
            if await ping() { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func ping() async -> Bool {
        var request = URLRequest(url: baseURL)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }

    func transcribe(wav: URL, language: String = "ru") async throws -> String {
        let audio = try Data(contentsOf: wav)
        let boundary = "----WhisperDictation\(UUID().uuidString)"
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        field("language", language)
        field("response_format", "json")
        field("temperature", "0.0")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appendingPathComponent("inference"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "WhisperEngine", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "whisper-server вернул \(code)"])
        }
        struct Result: Decodable { let text: String }
        let decoded = try JSONDecoder().decode(Result.self, from: data)
        return Self.clean(decoded.text)
    }

    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let junk = ["[BLANK_AUDIO]", "(blank_audio)", "[SILENCE]", "[ Silence ]", "[Music]"]
        for j in junk { text = text.replacingOccurrences(of: j, with: "") }
        text = text.replacingOccurrences(of: "  ", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shutdown() {
        process?.terminate()
        process = nil
    }

    deinit {
        process?.terminate()
    }
}
