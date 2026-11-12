import Foundation

/// Скачивает модель Whisper с HuggingFace в Application Support с прогрессом.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var progressHandler: ((Double) -> Void)?
    private var completion: ((Result<URL, Error>) -> Void)?

    func download(progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        self.progressHandler = progress
        self.completion = completion

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.downloadTask(with: WhisperEngine.modelURL)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in self?.progressHandler?(value) }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: WhisperEngine.modelsDir, withIntermediateDirectories: true)
            let dest = WhisperEngine.installedModel
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.moveItem(at: location, to: dest)

            let attrs = try? fm.attributesOfItem(atPath: dest.path)
            let size = (attrs?[.size] as? Int64) ?? 0
            guard size > 1_500_000_000 else {
                throw NSError(domain: "ModelDownloader", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Файл модели скачался не полностью (\(size) байт)"
                ])
            }
            DispatchQueue.main.async { [weak self] in self?.completion?(.success(dest)) }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.completion?(.failure(error)) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async { [weak self] in self?.completion?(.failure(error)) }
    }
}
