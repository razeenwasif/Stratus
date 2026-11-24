import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredSection: NavSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Breathing room under macOS window traffic lights
            Spacer().frame(height: 36)

            // Project Switcher (borderless tonal pill)
            projectSwitcher
                .padding(.horizontal, 14)

            // Quick Command Palette Trigger (⌘K)
            Button {
                appState.showCommandPalette = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(T3.textTertiary)
                    Text("Jump to resource...")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textTertiary)
                    Spacer()
                    Text("⌘K")
                        .font(T3.mono(10, weight: .medium))
                        .foregroundStyle(T3.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 18)

            // Navigation Groups (no divider lines, pure spacing & typography)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(NavSection.Group.allCases, id: \.rawValue) { group in
                        let items = NavSection.allCases.filter { $0.group == group }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(T3.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 3)

                            ForEach(items) { section in
                                navItem(section)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            Spacer()

            // Connection Status & Account Footer
            accountFooter
                .padding(14)
        }
        .frame(maxHeight: .infinity)
        .background(T3.bgSidebar)
    }

    private var projectSwitcher: some View {
        Menu {
            if appState.projects.isEmpty {
                Text("No projects loaded")
            } else {
                ForEach(appState.projects) { project in
                    Button {
                        Task { await appState.selectProject(project) }
                    } label: {
                        HStack {
                            Text("\(project.name) (\(project.projectId))")
                            if project.projectId == appState.selectedProject?.projectId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Connection & Auth Settings...") {
                appState.showAuthSheet = true
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(T3.surfaceActive)
                        .frame(width: 26, height: 26)
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(T3.indigo)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.selectedProject?.name ?? "Select Project")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                        .lineLimit(1)
                    Text(appState.selectedProject?.projectId ?? "no-project")
                        .font(T3.mono(10))
                        .foregroundStyle(T3.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(T3.textTertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private func navItem(_ section: NavSection) -> some View {
        let isSelected = appState.selectedSection == section
        let isHovered = hoveredSection == section

        return Button {
            appState.navigate(to: section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(hexString: section.accentHex) : T3.textSecondary)
                    .frame(width: 16)

                Text(section.shortTitle)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? T3.textPrimary : T3.textSecondary)

                Spacer()

                if isSelected {
                    Circle()
                        .fill(Color(hexString: section.accentHex))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected ? T3.surfaceActive : (isHovered ? T3.surfaceHover : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredSection = $0 ? section : nil }
    }

    private var accountFooter: some View {
        Button {
            appState.showAuthSheet = true
        } label: {
            HStack(spacing: 9) {
                StatusDot(
                    color: appState.auth.isDemo ? T3.indigo : T3.mint,
                    size: 6,
                    pulse: !appState.auth.isDemo
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.auth.mode.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(T3.textPrimary)
                        .lineLimit(1)
                    Text(appState.auth.account.email)
                        .font(T3.mono(10))
                        .foregroundStyle(T3.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(T3.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
