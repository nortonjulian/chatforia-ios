import SwiftUI

struct GIFPickerView: View {
    let onSelect: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GIFPickerItem] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                Group {
                    if isLoading && results.isEmpty {
                        ProgressView("Loading GIFs…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorText, results.isEmpty {
                        ContentUnavailableView(
                            "Couldn’t load GIFs",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorText)
                        )
                    } else if results.isEmpty {
                        ContentUnavailableView(
                            "No GIFs found",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search.")
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(results) { item in
                                    gifCell(item)
                                }
                            }
                            .padding(10)
                        }
                    }
                }
            }
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadFeatured()
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search GIFs", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !query.isEmpty {
                Button {
                    query = ""
                    Task { await loadFeatured() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(10)
    }

    @ViewBuilder
    private func gifCell(_ item: GIFPickerItem) -> some View {
        Button {
            guard let fullURL = item.fullURL ?? item.previewURL else { return }

            Task {
                await GIFService.shared.registerShare(item: item, query: query)
            }

            onSelect(fullURL)
            dismiss()
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))

                if let previewURL = item.previewURL {
                    AsyncImage(url: previewURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 140)

                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 140)
                                .frame(maxWidth: .infinity)
                                .clipped()

                        case .failure:
                            fallbackCell(title: item.title)

                        @unknown default:
                            fallbackCell(title: item.title)
                        }
                    }
                } else {
                    fallbackCell(title: item.title)
                }

                Text("GIF")
                    .font(.caption2.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.72))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fallbackCell(title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
    }

    private func scheduleSearch(for newValue: String) {
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await loadFeatured()
            } else {
                await loadSearch(query: newValue)
            }
        }
    }

    @MainActor
    private func loadFeatured() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            results = try await GIFService.shared.featured()
        } catch {
            results = []
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func loadSearch(query: String) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            results = try await GIFService.shared.search(query: query)
        } catch {
            results = []
            errorText = error.localizedDescription
        }
    }
}
