import Foundation
import AVFoundation

/// Записывает микрофон, сразу конвертируя в WAV 16 kHz mono Int16 — формат, который любит whisper.cpp.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var pcm = Data()
    private(set) var isRecording = false

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    var onLevel: ((Float) -> Void)?

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start() throws {
        guard !isRecording else { return }
        pcm.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: "AudioRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Микрофон недоступен"])
        }
        converter = AVAudioConverter(from: inFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        isRecording = true
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        // уровень для индикатора
        if let channel = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { let v = channel[i]; sum += v * v }
            let rms = sqrt(sum / Float(max(n, 1)))
            let level = min(1, rms * 12)
            DispatchQueue.main.async { self.onLevel?(level) }
        }

        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            return
        }
        if let data = out.int16ChannelData?[0], out.frameLength > 0 {
            pcm.append(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        }
    }

    /// Удаляет недописанные WAV после падения/завершения во время распознавания.
    static func cleanupTemporaryFiles() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("whisper-dictation-")
            && file.pathExtension == "wav" {
            try? fm.removeItem(at: file)
        }
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        DispatchQueue.main.async { self.onLevel?(0) }
        guard !pcm.isEmpty else { return nil }
        return writeWav()
    }

    private func writeWav() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-dictation-\(UUID().uuidString).wav")
        var data = Data()
        let dataSize = UInt32(pcm.count)
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bits / 8)
        let blockAlign = channels * (bits / 8)

        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))            // PCM
        append(channels)
        append(sampleRate)
        append(byteRate)
        append(blockAlign)
        append(bits)
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        data.append(pcm)

        do {
            try data.write(to: url)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
            return url
        } catch {
            return nil
        }
    }
}
