import SwiftUI

struct StorageView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var hoveredBucket: String?
    @State private var hoveredObject: String?

    private var filteredObjects: [GCSObject] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appState.objects }
        return appState.objects.filter { $0.displayName.lowercased().contains(q) }
    }

    private var prefixBreadcrumbs: [(label: String, prefix: String)] {
        let parts = appState.currentPrefix.split(separator: "/").map(String.init)
        var crumbs: [(String, String)] = []
        var acc = ""
        for part in parts {
            acc += "\(part)/"
            crumbs.append((part, acc))
        }
        return crumbs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cloud Storage")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(appState.buckets.count) buckets · \(appState.selectedProject?.projectId ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                BorderlessSearchField(text: $searchText, placeholder: "Filter objects...", width: 210)

                if appState.selectedBucket != nil {
                    ActionPillButton(
                        title: "Upload",
                        systemImage: "arrow.up.doc",
                        tint: T3.sky,
                        isLoading: appState.isUploadingObject
                    ) {
                        Task { await appState.uploadFileToCurrentBucket() }
                    }
                }

                ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise", isLoading: appState.isLoadingStorage) {
                    Task { await appState.refreshBuckets() }
                }
            }

            // Borderless two-column layout separated solely by whitespace (zero divider line)
            HStack(alignment: .top, spacing: 32) {
                bucketsColumn
                    .frame(width: 240)

                objectsColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .background(T3.bg)
    }

    private var bucketsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BUCKETS")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(T3.textTertiary)
                .padding(.horizontal, 8)

            if appState.buckets.isEmpty && !appState.isLoadingStorage {
                Text("No buckets found")
                    .font(.system(size: 12))
                    .foregroundStyle(T3.textTertiary)
                    .padding(.horizontal, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.buckets) { bucket in
                            let isSelected = appState.selectedBucket?.name == bucket.name
                            let isHovered = hoveredBucket == bucket.name

                            Button {
                                Task { await appState.selectBucket(bucket) }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 7) {
                                        Image(systemName: "externaldrive.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(isSelected ? T3.sky : T3.textTertiary)
                                        Text(bucket.name)
                                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? T3.textPrimary : T3.textSecondary)
                                            .lineLimit(1)
                                    }

                                    HStack(spacing: 8) {
                                        Text(bucket.location)
                                            .font(T3.mono(10))
                                            .foregroundStyle(T3.textTertiary)
                                        Text(bucket.storageClass)
                                            .font(T3.mono(10))
                                            .foregroundStyle(T3.textTertiary)
                                        if bucket.estimatedSizeBytes > 0 {
                                            Text(Formatters.byteCount(bucket.estimatedSizeBytes))
                                                .font(T3.mono(10))
                                                .foregroundStyle(T3.textMuted)
                                        }
                                    }
                                    .padding(.leading, 18)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected ? T3.surfaceActive : (isHovered ? T3.surfaceHover : Color.clear),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { hoveredBucket = $0 ? bucket.name : nil }
                        }
                    }
                }
            }
        }
    }

    private var objectsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bucket = appState.selectedBucket {
                // Clickable Breadcrumbs
                HStack(spacing: 6) {
                    Button {
                        Task { await appState.openPrefix("") }
                    } label: {
                        Text(bucket.name)
                            .font(T3.mono(12, weight: .semibold))
                            .foregroundStyle(appState.currentPrefix.isEmpty ? T3.textPrimary : T3.sky)
                    }
                    .buttonStyle(.plain)

                    ForEach(prefixBreadcrumbs, id: \.prefix) { crumb in
                        Text("/")
                            .font(T3.mono(12))
                            .foregroundStyle(T3.textTertiary)
                        Button {
                            Task { await appState.openPrefix(crumb.prefix) }
                        } label: {
                            Text(crumb.label)
                                .font(T3.mono(12, weight: .medium))
                                .foregroundStyle(crumb.prefix == appState.currentPrefix ? T3.textPrimary : T3.sky)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)

                if let err = appState.storageError {
                    EmptyStateView(icon: "externaldrive.badge.exclamationmark", title: "Storage error", message: err)
                } else if filteredObjects.isEmpty && !appState.isLoadingStorage {
                    EmptyStateView(icon: "folder", title: "Empty prefix", message: "No objects or folders under this path.")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(filteredObjects) { obj in
                                objectRow(obj)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            } else {
                EmptyStateView(
                    icon: "externaldrive",
                    title: "Select a bucket",
                    message: "Choose a Cloud Storage bucket on the left to browse folders and objects."
                )
            }
        }
    }

    private func objectRow(_ obj: GCSObject) -> some View {
        let isHovered = hoveredObject == obj.id
        let isSelected: Bool = {
            if case .gcsObject(let cur, _) = appState.inspector { return cur.id == obj.id }
            return false
        }()

        return HStack(spacing: 12) {
            Image(systemName: obj.isPrefix ? "folder.fill" : "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(obj.isPrefix ? T3.amber : T3.textSecondary)
                .frame(width: 18)

            Text(obj.displayName)
                .font(.system(size: 13, weight: obj.isPrefix ? .medium : .regular))
                .foregroundStyle(T3.textPrimary)
                .lineLimit(1)

            Spacer()

            if !obj.isPrefix {
                if isHovered || isSelected {
                    HStack(spacing: 6) {
                        ActionPillButton(title: "Download", systemImage: "arrow.down.circle", tint: T3.sky) {
                            Task { await appState.downloadObject(obj) }
                        }
                        ActionPillButton(title: "Delete", systemImage: "trash", tint: T3.rose) {
                            Task { await appState.deleteObject(obj) }
                        }
                    }
                }

                Text(Formatters.byteCount(obj.sizeBytes))
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.textSecondary)
                    .frame(width: 82, alignment: .trailing)

                if let updated = obj.updated {
                    Text(Formatters.relativeDate(updated))
                        .font(T3.mono(11))
                        .foregroundStyle(T3.textTertiary)
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ? T3.surfaceActive : (isHovered ? T3.surfaceHover : Color.clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hoveredObject = $0 ? obj.id : nil }
        .onTapGesture {
            Task { await appState.previewObject(obj) }
        }
    }
}
