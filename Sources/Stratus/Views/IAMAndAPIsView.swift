import SwiftUI

struct IAMAndAPIsView: View {
    @Environment(AppState.self) private var appState
    @State private var activeTab: SubTab = .iam
    @State private var searchText = ""
    @State private var newAPIName = ""
    @State private var hoveredRow: String?

    enum SubTab: String, CaseIterable {
        case iam = "IAM Principals"
        case apis = "Enabled APIs"
    }

    private var filteredBindings: [IAMBinding] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appState.iamBindings }
        return appState.iamBindings.filter {
            $0.role.lowercased().contains(q) || $0.members.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private var filteredAPIs: [EnabledAPI] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appState.enabledAPIs }
        return appState.enabledAPIs.filter {
            $0.title.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("IAM & APIs")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(appState.selectedProject?.projectId ?? "") · Access control & Service Usage")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(SubTab.allCases, id: \.self) { tab in
                        FilterPillButton(title: tab.rawValue, isSelected: activeTab == tab) {
                            activeTab = tab
                        }
                    }
                }

                BorderlessSearchField(
                    text: $searchText,
                    placeholder: activeTab == .iam ? "Filter roles or principals..." : "Filter APIs...",
                    width: 220
                )

                ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise", isLoading: appState.isLoadingIAM) {
                    Task { await appState.refreshIAMAndAPIs() }
                }
            }

            if appState.isLoadingIAM && appState.iamBindings.isEmpty && appState.enabledAPIs.isEmpty {
                ProgressView("Loading IAM policy and enabled APIs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.iamError, appState.iamBindings.isEmpty && appState.enabledAPIs.isEmpty {
                EmptyStateView(icon: "lock.shield", title: "IAM & Service Usage unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshIAMAndAPIs() }
                }
            } else {
                switch activeTab {
                case .iam:
                    iamListView
                case .apis:
                    apisListView
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .background(T3.bg)
    }

    private var iamListView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(filteredBindings) { binding in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            TagPill(text: binding.role, color: T3.violet, textColor: T3.textPrimary, monospaced: true)
                            Text("\(binding.members.count) principal\(binding.members.count == 1 ? "" : "s")")
                                .font(.system(size: 11.5))
                                .foregroundStyle(T3.textTertiary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(binding.members, id: \.self) { member in
                                let parts = member.split(separator: ":", maxSplits: 1).map(String.init)
                                let kind = parts.count == 2 ? parts[0] : "principal"
                                let identity = parts.count == 2 ? parts[1] : member
                                let rowKey = "\(binding.role)-\(member)"

                                HStack(spacing: 10) {
                                    TagPill(text: kind, monospaced: true)
                                    Text(identity)
                                        .font(T3.mono(12))
                                        .foregroundStyle(T3.textPrimary)
                                    Spacer()
                                    if hoveredRow == rowKey {
                                        ActionPillButton(title: "Copy", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                                            appState.copyToClipboard(identity, label: "principal")
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    hoveredRow == rowKey ? T3.surfaceHover : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                                .onHover { hoveredRow = $0 ? rowKey : nil }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    private var apisListView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                BorderlessSearchField(text: $newAPIName, placeholder: "Enable API (e.g. pubsub.googleapis.com)", width: 320)
                ActionPillButton(
                    title: "Enable API",
                    systemImage: "plus",
                    tint: T3.mint,
                    isLoading: appState.busyAPINames.contains(newAPIName)
                ) {
                    let apiName = newAPIName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !apiName.isEmpty else { return }
                    Task {
                        await appState.toggleAPI(serviceName: apiName, enable: true)
                        newAPIName = ""
                    }
                }
                Spacer()
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(filteredAPIs) { api in
                        let isBusy = appState.busyAPINames.contains(api.name)
                        let isHovered = hoveredRow == api.id

                        HStack(spacing: 12) {
                            StatusDot(color: api.isEnabled ? T3.mint : T3.slate, size: 5.5)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(api.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(T3.textPrimary)
                                    Text(api.name)
                                        .font(T3.mono(11))
                                        .foregroundStyle(T3.textTertiary)
                                }
                                Text(api.description)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(T3.textMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isHovered || isBusy {
                                ActionPillButton(
                                    title: api.isEnabled ? "Disable" : "Enable",
                                    tint: api.isEnabled ? T3.rose : T3.mint,
                                    isLoading: isBusy
                                ) {
                                    Task { await appState.toggleAPI(serviceName: api.name, enable: !api.isEnabled) }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            isHovered ? T3.surfaceHover : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .onHover { hoveredRow = $0 ? api.id : nil }
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }
}
