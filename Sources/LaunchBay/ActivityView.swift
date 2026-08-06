#if os(macOS)
    import Foundation
    import LaunchBayCore
    import SwiftUI

    struct ActivityView: View {
        @EnvironmentObject private var model: AppModel
        @State private var selection: UUID?

        private var selectedEntry: AppModel.ActivityEntry? {
            model.activities.first { $0.id == selection }
        }

        var body: some View {
            HSplitView {
                if model.activities.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "terminal",
                        description: Text(
                            "Commands you run from the app appear here with redacted arguments and output.")
                    )
                    .frame(minWidth: 360)
                } else {
                    List(model.activities, selection: $selection) { entry in
                        HStack(spacing: 10) {
                            Image(
                                systemName: entry.outcome == .succeeded
                                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundStyle(entry.outcome == .succeeded ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .fontWeight(.medium)
                                Text(entry.date.nativeContainerTimestamp)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 5)
                        .tag(entry.id)
                    }
                    .frame(minWidth: 360, idealWidth: 420)
                }

                if let entry = selectedEntry {
                    ActivityDetail(entry: entry)
                        .frame(minWidth: 470)
                } else {
                    ContentUnavailableView(
                        "Select an operation",
                        systemImage: "terminal",
                        description: Text("Inspect its exact command, exit status, and output.")
                    )
                    .frame(minWidth: 470)
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear", role: .destructive) {
                        selection = nil
                        model.clearActivity()
                    }
                    .disabled(model.activities.isEmpty)
                }
            }
        }
    }

    private struct ActivityDetail: View {
        let entry: AppModel.ActivityEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.title2.bold())
                        Text(entry.date.nativeContainerTimestamp)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let exitCode = entry.exitCode {
                        Text("Exit \(exitCode)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if !entry.command.isEmpty {
                    Text("Command")
                        .font(.headline)
                    Text(entry.command)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                if let duration = entry.durationSeconds {
                    Text(String(format: "Completed in %.2f seconds", duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Output")
                    .font(.headline)

                CodeBlock(text: combinedOutput)
                    .frame(maxHeight: .infinity)
            }
            .padding(20)
        }

        private var combinedOutput: String {
            var parts: [String] = []
            if !entry.standardOutput.trimmed.isEmpty {
                parts.append(entry.standardOutput.trimmed)
            }
            if !entry.standardError.trimmed.isEmpty {
                parts.append("stderr:\n\(entry.standardError.trimmed)")
            }
            return parts.joined(separator: "\n\n")
        }
    }
#endif
