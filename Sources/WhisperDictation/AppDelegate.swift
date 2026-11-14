import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let recorder = AudioRecorder()
    private let engine = WhisperEngine()
    /// true только после успешной проверки SHA-256 модели.
    private var modelReady = false
    private let hotkey = HotkeyManager()
    private let downloader = ModelDownloader()

    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var isWarmingUp = false
    private var previousApp: NSRunningApplication?
    /// Держим источники сигналов, иначе whisper-server переживёт killall/краш.
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
        AudioRecorder.cleanupTemporaryFiles()
        // Старый лог предыдущих версий (лежал в world-readable /tmp).
        try? FileManager.default.removeItem(atPath: "/tmp/whisper-dictation-server.log")
        setupStatusItem()
        setupPanel()
        wire()

        recorder.onLevel = { [weak self] level in
            self?.model.level = level
        }

        hotkey.onTrigger = { [weak self] in
            self?.toggleRecording()
        }
        hotkey.register()

        validateModelThenStart()

        if !TextInserter.isTrusted() {
            model.needsAccessibility = true
        }

        // Показываем панель при старте, иначе приложение выглядит «не запустилось»:
        // иконки в Dock нет, окна нет — только значок в строке меню.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.positionPanel()
            self?.panel?.orderFrontRegardless()
        }
    }

    /// SIGTERM/SIGINT от killall и SIGKILL-подобных сценариев: без этого
    /// дочерний whisper-server оставался жить после завершения приложения.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.engine.shutdown()
                AudioRecorder.cleanupTemporaryFiles()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Всегда проверяет SHA-256 установленной модели и только потом запускает
    /// сервер: подменённый или битый файл не должен попасть в работу.
    private func validateModelThenStart() {
        modelReady = false
        guard let url = WhisperEngine.findModel() else {
            model.modelMissing = true
            model.status = "Модель не найдена — скачайте 1,6 ГБ"
            return
        }

        model.status = "Проверяю модель…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Ошибку чтения не путаем с подменой: один повтор, и только
            // подтверждённое несовпадение удаляет файл.
            var digest = try? ModelDownloader.sha256(of: url)
            if digest == nil { digest = try? ModelDownloader.sha256(of: url) }
            DispatchQueue.main.async {
                guard let digest else {
                    self.model.status = "Не удалось прочитать модель — проверьте файл"
                    return
                }
                guard digest == WhisperEngine.modelSHA256 else {
                    try? FileManager.default.removeItem(at: url)
                    self.engine.shutdown()
                    self.modelReady = false
                    self.model.modelMissing = true
                    self.model.status = "Модель повреждена — скачайте заново"
                    return
                }
                // Путь в движок попадает только после успешной проверки.
                self.engine.modelPath = url.path
                self.modelReady = true
                self.startEngine(path: url.path)
            }
        }
    }

    private func startEngine(path: String) {
        engine.modelPath = path
        Task { [weak self] in
            guard let self else { return }
            let ready = await self.engine.ensureRunning()
            await MainActor.run {
                self.model.status = ready ? "Модель загружена" : "Не удалось запустить whisper-server"
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
        AudioRecorder.cleanupTemporaryFiles()
    }

    // MARK: - UI

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whisper")
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    private func setupPanel() {
        let view = PanelView(model: model)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 470, height: 300)

        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 300),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = hosting
        p.becomesKeyOnlyIfNeeded = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        panel = p
    }

    private func wire() {
        model.onToggleRecord = { [weak self] in self?.toggleRecording() }
        model.onCopy = { [weak self] in
            guard let self else { return }
            TextInserter.copy(self.model.text)
            self.model.status = "Скопировано в буфер"
        }
        model.onPaste = { [weak self] in
            guard let self else { return }
            let ok = TextInserter.insert(self.model.text)
            self.model.status = ok
                ? "Вставлено в активное приложение"
                : "Нет разрешения Accessibility — включите его в системных настройках"
        }
        model.onClear = { [weak self] in
            self?.model.text = ""
        }
        model.onClose = { [weak self] in
            self?.panel?.orderOut(nil)
        }
        model.onDownloadModel = { [weak self] in self?.downloadModel() }
    }

    private func downloadModel() {
        guard model.downloadProgress == nil else { return }
        model.modelMissing = false
        model.downloadProgress = 0
        model.status = "Скачиваю модель…"

        downloader.download(progress: { [weak self] value in
            self?.model.downloadProgress = value
            self?.model.status = "Скачиваю модель: \(Int(value * 100))%"
        }, completion: { [weak self] result in
            guard let self else { return }
            self.model.downloadProgress = nil
            switch result {
            case .success:
                // ModelDownloader уже проверил SHA-256; прогоняем штатную
                // валидацию, чтобы выставить modelReady и запустить сервер.
                self.model.status = "Модель скачана, проверяю…"
                self.validateModelThenStart()
            case .failure(let error):
                self.model.modelMissing = true
                self.model.status = "Ошибка загрузки: \(error.localizedDescription)"
            }
        })
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Показать панель", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "О программе", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let auto = menu.addItem(withTitle: "Автовставка текста", action: #selector(toggleAutoInsert), keyEquivalent: "")
        auto.target = self
        auto.state = model.autoInsert ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "Диктовка голосом на Mac.\nСделал @gimartynov.\n\nРаботает на whisper.cpp (MIT) и ggml (MIT).\nНе связано с OpenAI; «Whisper» — открытая модель OpenAI.\nРаспознавание может ошибаться — проверяйте текст.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAutoInsert() {
        model.autoInsert.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            rememberFrontmost()
            positionPanel()
            panel.orderFrontRegardless()
        }
    }

    private func rememberFrontmost() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.minY + 24
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Recording

    private func toggleRecording() {
        if model.modelMissing || model.downloadProgress != nil {
            model.status = "Сначала скачайте модель 1,6 ГБ"
            return
        }
        guard modelReady else {
            model.status = "Модель ещё проверяется — секунду"
            return
        }
        switch model.phase {
        case .idle:
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    private func startRecording() {
        model.text = ""
        model.lastError = nil
        recorder.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.model.status = "Нет доступа к микрофону (Системные настройки → Конфиденциальность)"
                return
            }
            do {
                try self.recorder.start()
                self.model.phase = .recording
                self.model.status = "Говорите…"
                self.rememberFrontmost()
                self.positionPanel()
                self.panel?.orderFrontRegardless()
            } catch {
                self.model.status = "Ошибка записи: \(error.localizedDescription)"
            }
        }
    }

    private func stopAndTranscribe() {
        guard modelReady else {
            _ = recorder.stop()
            model.phase = .idle
            model.status = "Модель не готова — проверьте статус"
            return
        }
        guard let url = recorder.stop() else {
            model.phase = .idle
            model.status = "Ничего не записалось"
            return
        }
        model.phase = .transcribing
        model.status = "Распознаю…"

        // На Intel распознавание может идти минуту: показываем, что процесс
        // жив, а не «зависло».
        let started = Date()
        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                let seconds = Int(Date().timeIntervalSince(started))
                await MainActor.run {
                    guard self.model.phase == .transcribing else { return }
                    self.model.status = "Распознаю… \(seconds) с"
                }
            }
        }

        Task { [weak self] in
            defer { ticker.cancel() }
            guard let self else { return }
            guard await self.engine.ensureRunning() else {
                await MainActor.run {
                    self.model.phase = .idle
                    self.model.status = "whisper-server не запустился — лог: ~/Library/Logs/WhisperDictation/server.log"
                }
                try? FileManager.default.removeItem(at: url)
                return
            }
            do {
                let text = try await self.engine.transcribe(wav: url)
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self.model.phase = .idle
                    if text.isEmpty {
                        self.model.status = "Речь не распознана"
                    } else {
                        self.model.text = text
                        self.model.status = "Готово · \(text.count) символов"
                        if self.model.autoInsert {
                            let front = NSWorkspace.shared.frontmostApplication
                            if let target = self.previousApp,
                               front?.processIdentifier == target.processIdentifier,
                               TextInserter.insert(text) {
                                // вставлено туда, где начинали запись
                            } else if !TextInserter.isTrusted() {
                                self.model.needsAccessibility = true
                                self.model.status = "Готово · \(text.count) символов — нужен доступ Accessibility для вставки"
                            } else {
                                self.model.status = "Готово · \(text.count) символов — текст в панели (приложение сменилось)"
                            }
                        }
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                let message: String
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    message = "Сервер не ответил за 15 минут. Перезапустите приложение и попробуйте снова"
                } else {
                    message = error.localizedDescription
                }
                await MainActor.run {
                    self.model.phase = .idle
                    self.model.status = "Ошибка: \(message)"
                }
            }
        }
    }
}

/// Панель-оверлей, которая никогда не забирает клавиатурный фокус.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
