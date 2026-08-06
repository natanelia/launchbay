#if os(macOS)
    import Foundation
    import LaunchBayCore
    import SwiftUI

    struct StatusBadge: View {
        let state: ContainerRuntimeState

        var body: some View {
            Text(state.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
        }

        private var foreground: Color {
            switch state {
            case .running: .green
            case .stopping: .orange
            case .stopped: .secondary
            case .unknown: .secondary
            }
        }

        private var background: Color {
            foreground.opacity(0.12)
        }
    }

    struct MetricCard: View {
        let title: String
        let value: String
        let systemImage: String
        let caption: String?

        init(title: String, value: String, systemImage: String, caption: String? = nil) {
            self.title = title
            self.value = value
            self.systemImage = systemImage
            self.caption = caption
        }

        var body: some View {
            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .frame(width: 34, height: 34)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.title2.weight(.semibold))
                        if let caption {
                            Text(caption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
    }

    struct CodeBlock: View {
        let text: String

        var body: some View {
            ScrollView([.horizontal, .vertical]) {
                Text(text.isEmpty ? "No output." : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
        }
    }

    extension Int64 {
        var nativeContainerFileSize: String {
            ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
        }
    }

    extension Date {
        var nativeContainerTimestamp: String {
            formatted(date: .abbreviated, time: .shortened)
        }
    }
#endif
