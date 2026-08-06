#if os(macOS)
    import LaunchBayCore
    import SwiftUI

    struct PullImageSheet: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.dismiss) private var dismiss

        @State private var reference = ""
        @State private var platform = "linux/arm64"

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pull Image")
                        .font(.title2.bold())
                    Text("Download an OCI-compatible image from a standard container registry.")
                        .foregroundStyle(.secondary)
                }

                Form {
                    TextField("Image reference", text: $reference, prompt: Text("nginx:latest"))
                    TextField("Platform", text: $platform, prompt: Text("linux/arm64"))
                    Text(
                        "Registry credentials are managed by Apple’s container CLI; this app does not store them."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Pull") {
                        Task {
                            if await model.pullImage(
                                reference: reference.trimmed, platform: platform.trimmed.nilIfEmpty)
                            {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(reference.trimmed.isEmpty || model.activeOperation != nil)
                }
            }
            .padding(20)
            .frame(width: 520, height: 310)
        }
    }

    extension String {
        fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
    }
#endif
