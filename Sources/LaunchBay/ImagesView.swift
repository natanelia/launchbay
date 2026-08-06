#if os(macOS)
    import LaunchBayCore
    import SwiftUI

    struct ImagesView: View {
        @EnvironmentObject private var model: AppModel
        @State private var selectedID: String?
        @State private var searchText = ""
        @State private var showingDeleteConfirmation = false
        @State private var pendingContextMenuDeletion: ImageSummary?

        private var filteredImages: [ImageSummary] {
            guard !searchText.trimmed.isEmpty else { return model.images }
            return model.images.filter {
                $0.reference.localizedCaseInsensitiveContains(searchText)
                    || $0.digest.localizedCaseInsensitiveContains(searchText)
            }
        }

        private var selectedImage: ImageSummary? {
            model.images.first { $0.id == selectedID }
        }

        var body: some View {
            HSplitView {
                if filteredImages.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No images" : "No matches",
                        systemImage: "opticaldiscdrive",
                        description: Text(
                            searchText.isEmpty
                                ? "Pull or build an OCI image to get started." : "Try a different search term.")
                    )
                    .frame(minWidth: 360)
                } else {
                    List(filteredImages, selection: $selectedID) { image in
                        ImageRow(image: image)
                            .tag(image.id)
                            .contextMenu {
                                Button("Run") {
                                    model.requestRunContainer(imageReference: image.reference)
                                }
                                Button("Delete", role: .destructive) {
                                    pendingContextMenuDeletion = image
                                }
                                .disabled(model.activeOperation != nil)
                            }
                    }
                    .listStyle(.inset)
                    .frame(minWidth: 380, idealWidth: 470)
                }

                if let selectedImage {
                    ImageDetailView(
                        image: selectedImage, showingDeleteConfirmation: $showingDeleteConfirmation
                    )
                    .frame(minWidth: 430)
                } else {
                    ContentUnavailableView(
                        "Select an image",
                        systemImage: "opticaldiscdrive",
                        description: Text("Inspect its digest, platforms, and size.")
                    )
                    .frame(minWidth: 430)
                }
            }
            .navigationTitle("Images")
            .searchable(text: $searchText, prompt: "Search images")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.presentBuildImage = true
                    } label: {
                        Label("Build", systemImage: "hammer")
                    }
                    .disabled(!model.canManageResources)
                    Button {
                        model.presentPullImage = true
                    } label: {
                        Label("Pull", systemImage: "arrow.down.circle")
                    }
                    .disabled(!model.canManageResources)
                }
            }
            .onChange(of: model.images) { _, images in
                if let selectedID, !images.contains(where: { $0.id == selectedID }) {
                    self.selectedID = nil
                }
            }
            .confirmationDialog(
                pendingContextMenuDeletion.map { "Delete \($0.reference)?" } ?? "Delete image?",
                isPresented: Binding(
                    get: { pendingContextMenuDeletion != nil },
                    set: { if !$0 { pendingContextMenuDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let image = pendingContextMenuDeletion {
                    Button("Delete", role: .destructive) {
                        pendingContextMenuDeletion = nil
                        Task { _ = await model.deleteImage(image) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingContextMenuDeletion = nil
                }
            } message: {
                Text("Containers that depend on this image may prevent its deletion.")
            }
        }
    }

    private struct ImageRow: View {
        let image: ImageSummary

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "opticaldiscdrive")
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(image.reference)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(image.digest.truncatedDigest())
                            .font(.caption.monospaced())
                        if let size = image.totalSizeBytes {
                            Text(size.nativeContainerFileSize)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private struct ImageDetailView: View {
        @EnvironmentObject private var model: AppModel
        let image: ImageSummary
        @Binding var showingDeleteConfirmation: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(image.reference)
                        .font(.title.bold())
                    Text(image.digest)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button {
                        model.requestRunContainer(imageReference: image.reference)
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .disabled(!model.canManageResources)

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Digest").foregroundStyle(.secondary)
                        Text(image.digest).font(.body.monospaced()).textSelection(.enabled)
                    }
                    GridRow {
                        Text("Size").foregroundStyle(.secondary)
                        Text(
                            image.totalSizeBytes.map {
                                $0.nativeContainerFileSize
                            } ?? "Unknown")
                    }
                    if let createdAt = image.createdAt {
                        GridRow {
                            Text("Added").foregroundStyle(.secondary)
                            Text(createdAt.nativeContainerTimestamp)
                        }
                    }
                }

                Text("Platforms")
                    .font(.headline)

                if image.platforms.isEmpty {
                    Text("No platform metadata was returned.")
                        .foregroundStyle(.secondary)
                } else {
                    List(image.platforms) { platform in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(platform.displayName)
                                    .fontWeight(.medium)
                                if let digest = platform.digest {
                                    Text(digest.truncatedDigest())
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let size = platform.sizeBytes {
                                Text(size.nativeContainerFileSize)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.inset)
                }

                Spacer()
            }
            .padding(20)
            .confirmationDialog(
                "Delete \(image.reference)?",
                isPresented: $showingDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) {
                    Task { _ = await model.deleteImage(image) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Containers that depend on this image may prevent its deletion.")
            }
        }
    }
#endif
