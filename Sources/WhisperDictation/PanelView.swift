import SwiftUI
import AppKit

struct PanelView: View {
    @ObservedObject var model: AppModel

    private var accent: Color {
        switch model.phase {
        case .idle: return .secondary
        case .recording: return .red
        case .transcribing: return .orange
        }
    }

    private var title: String {
        switch model.phase {
        case .idle: return "Готов к записи"
        case .recording: return "Идёт запись…"
        case .transcribing: return "Распознаю…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("⌥ Space")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                Button {
                    model.onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Скрыть панель")
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                if model.text.isEmpty {
                    Text("Нажмите «Записать» или ⌥ Space и говорите…")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(10)
                }
                ScrollView {
                    Text(model.text)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .opacity(model.text.isEmpty ? 0.01 : 1)
            }
            .frame(minHeight: 110)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.18))
            )

            // Индикатор уровня
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, geo.size.width * CGFloat(model.level)))
                }
            }
            .frame(height: 4)

            if model.needsAccessibility {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text("Для автовставки включите Accessibility")
                        .font(.system(size: 11))
                    Spacer()
                    Button("Открыть") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let progress = model.downloadProgress {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Скачиваю модель: \(Int(progress * 100))% из 1,6 ГБ")
                        .font(.system(size: 11))
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
                .padding(8)
                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            } else if model.modelMissing {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 12))
                    Text("Модель не найдена")
                        .font(.system(size: 11))
                    Spacer()
                    Button("Скачать 1,6 ГБ") { model.onDownloadModel?() }
                        .controlSize(.small)
                }
                .padding(8)
                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                Button {
                    model.onToggleRecord?()
                } label: {
                    Label(
                        model.phase == .recording ? "Стоп" : "Записать",
                        systemImage: model.phase == .recording ? "stop.fill" : "mic.fill"
                    )
                    .frame(minWidth: 92)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.phase == .recording ? .red : .accentColor)
                .disabled(model.phase == .transcribing || model.modelMissing || model.downloadProgress != nil)

                Button("Копировать") { model.onCopy?() }
                    .disabled(model.text.isEmpty)
                Button("Вставить") { model.onPaste?() }
                    .disabled(model.text.isEmpty)

                Spacer()

                Toggle("Авто", isOn: $model.autoInsert)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Автоматически вставлять распознанный текст в активное приложение")
            }

            HStack {
                Text(model.status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("@gimartynov")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("Автор приложения")
                    .padding(.trailing, 6)
                Button("Очистить") { model.onClear?() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .disabled(model.text.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 470)
        .background(.regularMaterial)
    }
}
