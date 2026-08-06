#if os(macOS)
    import LaunchBayCore
    import SwiftUI

    struct ContainersView: View {
        @EnvironmentObject private var model: AppModel
        @State private var selectedID: String?
        @State private var searchText = ""
        @State private var pendingContextMenuDeletion: ContainerSummary?

        private var filteredContainers: [ContainerSummary] {
            guard !searchText.trimmed.isEmpty else { return model.containers }
            return model.containers.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.imageReference.localizedCaseInsensitiveContains(searchText)
                    || $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }

        private var selectedContainer: ContainerSummary? {
            model.containers.first { $0.id == selectedID }
        }

        var body: some View {
            HSplitView {
                VStack(spacing: 0) {
                    if filteredContainers.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No containers" : "No matches",
                            systemImage: "shippingbox",
                            description: Text(
                                searchText.isEmpty
                                    ? "Run an image to create your first container." : "Try a different search term.")
                        )
                    } else {
                        List(filteredContainers, selection: $selectedID) { container in
                            ContainerRow(container: container)
                                .tag(container.id)
                                .contextMenu {
                                    contextMenu(for: container)
                                }
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(minWidth: 350, idealWidth: 430)

                if let selectedContainer {
                    ContainerDetailView(container: selectedContainer)
                        .id(selectedContainer.id)
                        .frame(minWidth: 460)
                } else {
                    ContentUnavailableView(
                        "Select a container",
                        systemImage: "shippingbox",
                        description: Text("Inspect configuration, read logs, and control its lifecycle.")
                    )
                    .frame(minWidth: 460)
                }
            }
            .navigationTitle("Containers")
            .searchable(text: $searchText, prompt: "Search containers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.requestRunContainer()
                    } label: {
                        Label("Run Container", systemImage: "plus")
                    }
                    .disabled(!model.canManageResources)
                }
            }
            .onChange(of: model.containers) { _, containers in
                if let selectedID, !containers.contains(where: { $0.id == selectedID }) {
                    self.selectedID = nil
                }
            }
            .confirmationDialog(
                pendingContextMenuDeletion.map { "Delete \($0.name)?" } ?? "Delete container?",
                isPresented: Binding(
                    get: { pendingContextMenuDeletion != nil },
                    set: { if !$0 { pendingContextMenuDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let container = pendingContextMenuDeletion {
                    Button("Delete", role: .destructive) {
                        pendingContextMenuDeletion = nil
                        Task {
                            _ = await model.deleteContainer(
                                container,
                                force: container.state == .running
                            )
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingContextMenuDeletion = nil
                }
            } message: {
                if let container = pendingContextMenuDeletion {
                    Text(
                        container.state == .running
                            ? "The running container will be force-deleted."
                            : "This does not delete its image."
                    )
                }
            }
        }

        @ViewBuilder
        private func contextMenu(for container: ContainerSummary) -> some View {
            if container.state == .running {
                Button("Stop") {
                    Task { _ = await model.stopContainer(container) }
                }
                .disabled(model.activeOperation != nil)
            } else {
                Button("Start") {
                    Task { _ = await model.startContainer(container) }
                }
                .disabled(model.activeOperation != nil)
            }
            Button("Copy Shell Command") {
                model.copyShellCommand(for: container)
            }
            .disabled(container.state != .running)
            Divider()
            Button("Delete", role: .destructive) {
                pendingContextMenuDeletion = container
            }
            .disabled(model.activeOperation != nil)
        }
    }

    private struct ContainerRow: View {
        let container: ContainerSummary

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: container.state == .running ? "shippingbox.fill" : "shippingbox")
                    .foregroundStyle(container.state == .running ? .primary : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(container.name)
                            .fontWeight(.medium)
                        Spacer()
                        StatusBadge(state: container.state)
                    }
                    Text(container.imageReference)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !container.publishedPorts.isEmpty {
                        Text(container.publishedPorts.map(\.displayValue).joined(separator: ", "))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }

    private struct ContainerDetailView: View {
        @EnvironmentObject private var model: AppModel
        let container: ContainerSummary

        @State private var logs = ""
        @State private var isLoadingLogs = false
        @State private var showingDeleteConfirmation = false
        @State private var selectedLogKind = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(container.name)
                            .font(.title.bold())
                        Text(container.imageReference)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    StatusBadge(state: container.state)
                }

                HStack(spacing: 10) {
                    if container.state == .running {
                        Button {
                            Task { _ = await model.stopContainer(container) }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            Task { _ = await model.startContainer(container) }
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        model.copyShellCommand(for: container)
                    } label: {
                        Label("Copy Shell Command", systemImage: "doc.on.doc")
                    }
                    .disabled(container.state != .running)

                    Spacer()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .disabled(model.activeOperation != nil)

                Divider()

                details

                HStack {
                    Picker("Log", selection: $selectedLogKind) {
                        Text("Application log").tag(0)
                        Text("Boot log").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    Spacer()

                    Button {
                        Task { await loadLogs() }
                    } label: {
                        if isLoadingLogs {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Reload Logs", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoadingLogs)
                }

                CodeBlock(text: logs)
                    .frame(maxHeight: .infinity)
            }
            .padding(20)
            .task { await loadLogs() }
            .onChange(of: selectedLogKind) { _, _ in
                Task { await loadLogs() }
            }
            .confirmationDialog(
                "Delete \(container.name)?",
                isPresented: $showingDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) {
                    Task { _ = await model.deleteContainer(container, force: container.state == .running) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    container.state == .running
                        ? "The running container will be force-deleted." : "This does not delete its image.")
            }
        }

        private var details: some View {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                detailRow("ID", container.id)
                detailRow("State", container.state.rawValue)
                detailRow("Command", container.command.joined(separator: " ").nilIfEmpty ?? "Image default")
                detailRow("Addresses", container.addresses.joined(separator: ", ").nilIfEmpty ?? "—")
                detailRow(
                    "Ports",
                    container.publishedPorts.map(\.displayValue).joined(separator: ", ").nilIfEmpty ?? "—")
                detailRow("Resources", resourceText)
                if let createdAt = container.createdAt {
                    detailRow("Created", createdAt.nativeContainerTimestamp)
                }
                if let startedAt = container.startedAt {
                    detailRow("Started", startedAt.nativeContainerTimestamp)
                }
            }
        }

        private var resourceText: String {
            var parts: [String] = []
            if let cpuCount = container.cpuCount { parts.append("\(cpuCount) CPUs") }
            if let memory = container.memoryBytes {
                parts.append(Int64(memory).nativeContainerFileSize)
            }
            return parts.joined(separator: ", ").nilIfEmpty ?? "—"
        }

        private func detailRow(_ label: String, _ value: String) -> some View {
            GridRow {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 82, alignment: .trailing)
                Text(value)
                    .font(label == "ID" || label == "Command" ? .system(.body, design: .monospaced) : .body)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }

        private func loadLogs() async {
            isLoadingLogs = true
            defer { isLoadingLogs = false }
            logs = await model.fetchLogs(for: container, boot: selectedLogKind == 1) ?? logs
        }
    }

    extension String {
        fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
    }
#endif
