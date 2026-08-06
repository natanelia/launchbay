#if os(macOS)
    import LaunchBayCore
    import SwiftUI

    struct RunContainerSheet: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.dismiss) private var dismiss

        @State private var configuration: RunContainerConfiguration
        @State private var customImageReference = ""
        @State private var commandArguments = ""
        @State private var limitCPU = false

        init(initialImageReference: String = "") {
            _configuration = State(
                initialValue: RunContainerConfiguration(
                    imageReference: initialImageReference.trimmed
                )
            )
        }

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Run Container")
                            .font(.title2.bold())
                        Text("Launch an OCI image in its own lightweight Linux virtual machine.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)

                Divider()

                Form {
                    Section("Image") {
                        Picker("Local image", selection: $configuration.imageReference) {
                            Text("Choose an image…").tag("")
                            ForEach(model.images) { image in
                                Text(image.reference).tag(image.reference)
                            }
                        }
                        TextField(
                            "Or enter an image reference, for example nginx:latest", text: $customImageReference
                        )
                        .onChange(of: customImageReference) { _, value in
                            if !value.trimmed.isEmpty { configuration.imageReference = value.trimmed }
                        }
                    }

                    Section("Identity and command") {
                        TextField("Container name (optional)", text: $configuration.name)
                        TextEditor(text: $commandArguments)
                            .font(.body.monospaced())
                            .frame(minHeight: 60)
                        Text("Optional command arguments, one per line. Leave empty to use the image default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Ports") {
                        ForEach($configuration.ports) { $port in
                            HStack {
                                TextField("Host address", text: $port.hostAddress)
                                    .frame(minWidth: 120)
                                TextField("Host", value: $port.hostPort, format: .number)
                                    .frame(width: 70)
                                Image(systemName: "arrow.right")
                                TextField("Container", value: $port.containerPort, format: .number)
                                    .frame(width: 80)
                                Picker("Protocol", selection: $port.transport) {
                                    ForEach(PortMapping.Transport.allCases, id: \.self) { transport in
                                        Text(transport.rawValue.uppercased()).tag(transport)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 80)
                                Button(role: .destructive) {
                                    configuration.ports.removeAll { $0.id == port.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button("Add Port") {
                            configuration.ports.append(PortMapping())
                        }
                    }

                    Section("Volumes") {
                        ForEach($configuration.volumes) { $volume in
                            HStack {
                                TextField("Host path", text: $volume.source)
                                Image(systemName: "arrow.right")
                                TextField("Container path", text: $volume.target)
                                Toggle("Read only", isOn: $volume.readOnly)
                                    .toggleStyle(.checkbox)
                                Button(role: .destructive) {
                                    configuration.volumes.removeAll { $0.id == volume.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button("Add Volume") {
                            configuration.volumes.append(VolumeMapping())
                        }
                    }

                    Section("Environment") {
                        ForEach($configuration.environment) { $variable in
                            HStack {
                                TextField("NAME", text: $variable.key)
                                    .font(.body.monospaced())
                                    .frame(width: 160)
                                TextField("Value", text: $variable.value)
                                Button(role: .destructive) {
                                    configuration.environment.removeAll { $0.id == variable.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button("Add Variable") {
                            configuration.environment.append(EnvironmentVariable())
                        }
                        Text(
                            "Environment values are passed directly to the CLI and redacted in the app’s Activity view."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Section("Resources and isolation") {
                        Toggle("Limit CPU", isOn: $limitCPU)
                        if limitCPU {
                            Stepper(
                                "CPU cores: \(configuration.cpuCount ?? 2)",
                                value: Binding(
                                    get: { configuration.cpuCount ?? 2 },
                                    set: { configuration.cpuCount = $0 }
                                ), in: 1...32)
                        }
                        TextField(
                            "Memory limit, for example 1G (optional)",
                            text: Binding(
                                get: { configuration.memory ?? "" },
                                set: { configuration.memory = $0.isEmpty ? nil : $0 }
                            ))
                        Toggle("Run a minimal init process", isOn: $configuration.useInit)
                        Toggle("Enable Rosetta for x86-64 binaries", isOn: $configuration.enableRosetta)
                        Toggle("Read-only root filesystem", isOn: $configuration.readOnlyRootFilesystem)
                        Toggle("Remove automatically after it stops", isOn: $configuration.removeWhenStopped)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)

                Divider()

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Run") {
                        configuration.command =
                            commandArguments
                            .split(whereSeparator: \.isNewline)
                            .map { String($0).trimmed }
                            .filter { !$0.isEmpty }
                        if !limitCPU { configuration.cpuCount = nil }
                        Task {
                            if await model.runContainer(configuration) {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(configuration.imageReference.trimmed.isEmpty || model.activeOperation != nil)
                }
                .padding(16)
            }
            .frame(width: 760, height: 720)
        }
    }
#endif
