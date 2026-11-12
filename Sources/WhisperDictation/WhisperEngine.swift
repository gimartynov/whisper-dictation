import Foundation

/// Держит локальный whisper-server (whisper.cpp) и шлёт ему WAV на распознавание.
final class WhisperEngine {
    static let port: UInt16 = 25_400
    static let modelName = "ggml-large-v3-turbo.bin"

    static let modelURL = URL(string:
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!

    /// SHA-256 файла ggml-large-v3-turbo.bin — защита от подмены модели.
    static let modelSHA256 = "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"

    /// Защита от подмены: модель должна быть не меньше этого размера.
    static let modelMinSize: Int64 = 1_500_000_000

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
               size >= Self.modelMinSize {
                return candidate
            }
        }
        return nil
    }

    /// Встроенный статический whisper-server; внешних запасных вариантов нет.
    static var serverBinary: String {
        if let url = Bundle.main.url(forResource: "whisper-server", withExtension: nil, subdirectory: "whisper"),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url.path
        }
        // Только свой бинарник: никаких внешних whisper-server.
        return ""
    }

    var modelPath: String
    private var process: Process?
    private(set) var port: UInt16 = WhisperEngine.defaultPort
    static let defaultPort: UInt16 = 25_400

    /// Лог в ~/Library/Logs (0700/0600), а не в общий /tmp.
    static var logURL: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Logs/WhisperDictation/server.log")
    }

    /// Путь задаётся только после проверки SHA-256 (см. AppDelegate).
    init(modelPath: String = "") {
        self.modelPath = modelPath
    }

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    /// Запускает сервер только на свободном порту и никогда не доверяет
    /// чужому процессу, который уже слушает порт.
    func ensureRunning() async -> Bool {
        if let process, process.isRunning, await ping() { return true }

        process?.terminate()
        process = nil

        guard FileManager.default.isExecutableFile(atPath: Self.serverBinary) else { return false }
        guard FileManager.default.fileExists(atPath: modelPath) else { return false }
        guard let free = Self.freePort() else { return false }
        port = free

        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.serverBinary)
        p.arguments = [
            "-m", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "-t", "6",
            "-l", "ru"
        ]

        let logURL = Self.logURL
        let logDir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: logDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        FileManager.default.createFile(
            atPath: logURL.path, contents: nil,
            attributes: [.posixPermissions: 0o600]
        )
        if let handle = try? FileHandle(forWritingTo: logURL) {
            try? handle.truncate(atOffset: 0)
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
            if !p.isRunning { return false }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    /// Свой сервер отвечает 200 и заголовком Server: whisper.cpp.
    /// Порт выбирается свободный, поэтому чужой процесс на 25400 не используется.
    private func ping() async -> Bool {
        guard let process, process.isRunning else { return false }
        var request = URLRequest(url: baseURL)
        request.timeoutInterval = 1.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            // У своего whisper-server главная страница содержит этот маркер.
            let html = String(decoding: data.prefix(4096), as: UTF8.self)
            return html.contains("Whisper.cpp Server")
        } catch {
            return false
        }
    }

    /// Первый свободный порт в диапазоне 25400...25439.
    static func freePort() -> UInt16? {
        for candidate in defaultPort..<(defaultPort + 40) {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            if fd < 0 { continue }
            defer { close(fd) }
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = candidate.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            if ok { return candidate }
        }
        return nil
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

        guard await ping() else {
            throw NSError(domain: "WhisperEngine", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "whisper-server не запущен"])
        }

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
