import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @FocusState private var isFocused: Bool

    struct PaletteEntry: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
        let badge: String
        let action: () -> Void
    }

    private var entries: [PaletteEntry] {
        var list: [PaletteEntry] = []

        // Sections
        for section in NavSection.allCases {
            list.append(PaletteEntry(
                id: "sec-\(section.rawValue)",
                icon: section.icon,
                tint: Color(hexString: section.accentHex),
                title: section.title,
                subtitle: "Navigate to \(section.title)",
                badge: "⌘\(section.shortcutDigit)"
            ) {
                appState.navigate(to: section)
                appState.showCommandPalette = false
            })
        }

        // Projects
        for proj in appState.projects {
            list.append(PaletteEntry(
                id: "proj-\(proj.projectId)",
                icon: "folder.badge.gearshape",
                tint: T3.indigo,
                title: proj.name,
                subtitle: "Switch project → \(proj.projectId)",
                badge: "Project"
            ) {
                appState.showCommandPalette = false
                Task { await appState.selectProject(proj) }
            })
        }

        // VMs
        for vm in appState.instances {
            list.append(PaletteEntry(
                id: "vm-\(vm.id)",
                icon: "cpu",
                tint: vm.isRunning ? T3.mint : T3.slate,
                title: vm.name,
                subtitle: "\(vm.zone) · \(vm.machineTypeShort)",
                badge: "VM"
            ) {
                appState.navigate(to: .compute)
                appState.inspector = .vm(vm)
                appState.showCommandPalette = false
            })
        }

        // Cloud Run
        for svc in appState.cloudRunServices {
            list.append(PaletteEntry(
                id: "run-\(svc.id)",
                icon: "bolt.horizontal.fill",
                tint: T3.indigo,
                title: svc.name,
                subtitle: "\(svc.region) · \(svc.uri)",
                badge: "Cloud Run"
            ) {
                appState.navigate(to: .cloudRun)
                appState.showCommandPalette = false
                Task { await appState.inspectCloudRunService(svc) }
            })
        }

        // Buckets
        for bucket in appState.buckets {
            list.append(PaletteEntry(
                id: "gcs-\(bucket.name)",
                icon: "externaldrive",
                tint: T3.sky,
                title: bucket.name,
                subtitle: "\(bucket.location) · \(bucket.storageClass)",
                badge: "Bucket"
            ) {
                appState.navigate(to: .storage)
                appState.showCommandPalette = false
                Task { await appState.selectBucket(bucket) }
            })
        }

        // Actions
        list.append(PaletteEntry(
            id: "act-auth",
            icon: "person.badge.key",
            tint: T3.coral,
            title: "Authentication & Connection Settings",
            subtitle: "Configure gcloud CLI, Google OAuth 2.0, or Demo Mode",
            badge: "Settings"
        ) {
            appState.showCommandPalette = false
            appState.showAuthSheet = true
        })

        list.append(PaletteEntry(
            id: "act-refresh",
            icon: "arrow.clockwise",
            tint: T3.mint,
            title: "Refresh Active View",
            subtitle: "Reload live data from Google Cloud REST APIs",
            badge: "⌘R"
        ) {
            appState.showCommandPalette = false
            Task { await appState.refreshCurrentSection() }
        })

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(list.prefix(12)) }
        return list.filter {
            $0.title.lowercased().contains(q)
                || $0.subtitle.lowercased().contains(q)
                || $0.badge.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(T3.indigo)
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Jump to projects, VMs, Cloud Run, buckets, actions...").foregroundStyle(T3.textTertiary)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(T3.textPrimary)
                .focused($isFocused)
                .onSubmit {
                    if let first = entries.first {
                        first.action()
                    }
                }

                Text("ESC")
                    .font(T3.mono(10, weight: .semibold))
                    .foregroundStyle(T3.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(T3.surfaceActive, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(entries) { entry in
                        Button(action: entry.action) {
                            HStack(spacing: 12) {
                                Image(systemName: entry.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(entry.tint)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(T3.textPrimary)
                                    Text(entry.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(T3.textTertiary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                TagPill(text: entry.badge, monospaced: true)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 580)
        .background(T3.bgPalette, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.75), radius: 36, y: 14)
        .onAppear {
            isFocused = true
        }
    }
}
