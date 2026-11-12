# Privacy Policy — Whisper Dictation

Last updated: 2026-11-12

Whisper Dictation is a local macOS app. It does not have accounts, analytics,
telemetry, or advertising.

## What is processed on your Mac

- **Audio.** Recorded from the microphone only while you hold a recording
  session (⌥ Space or the Record button). Written to a temporary WAV file in the
  system temporary directory, sent to a whisper.cpp server running on
  `127.0.0.1` (loopback, never exposed to the network), and deleted after
  transcription.
- **Recognized text.** Shown in the panel, copied to the system clipboard, and
  pasted into the app you were using if auto-insert is enabled. The text is not
  stored on disk by the app.
- **Clipboard.** Around a paste, the previous clipboard contents (all items and
  types, including images) are saved and restored afterwards. They are not sent
  anywhere and not logged.
- **Accessibility permission.** Used only to send ⌘V into the app you were
  dictating into. The app cannot read your screen or keystrokes.
- **Settings.** The auto-insert toggle is kept in memory for the session.
- **Logs.** `~/Library/Logs/WhisperDictation/server.log` contains whisper.cpp
  diagnostics (model path, timings, backend names). It does not contain
  recognized text or audio. Access is restricted to your user (0600).

## What is sent over the network

- **Model download.** On first launch the app downloads
  `ggml-large-v3-turbo.bin` (~1.6 GB) from
  `https://huggingface.co/ggerganov/whisper.cpp`. That request exposes your IP
  address and a standard User-Agent to Hugging Face, as any download does. No
  other data is sent.
- **Nothing else.** No audio, text, or usage data leaves the device.

## Data you can delete

- Model: `~/Library/Application Support/WhisperDictation/`
- Logs: `~/Library/Logs/WhisperDictation/`

Removing the app does not remove these folders automatically.

## Third parties

Hugging Face (model hosting) — see https://huggingface.co/privacy.
OpenAI is not involved: the app uses an open-source model under the MIT license
and is not affiliated with, endorsed by, or sponsored by OpenAI.

## Contact

Open an issue in the project repository or contact @gimartynov.
