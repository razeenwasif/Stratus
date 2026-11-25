import SwiftUI

struct IAMAndAPIsView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var newAPIName = ""
    @State private var hoveredRow: String?

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
                    Text("Security & IAM")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(appState.selectedProject?.projectId ?? "") · IAM Policy, Service Usage & Secret Manager")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(SecuritySubTab.allCases) { tab in
                        FilterPillButton(title: tab.title, isSelected: appState.selectedSecurityTab == tab) {
                            appState.selectedSecurityTab = tab
                            Task { await appState.refreshSecuritySection() }
                        }
                    }
                }

                BorderlessSearchField(
                    text: $searchText,
                    placeholder: appState.selectedSecurityTab == .iam ? "Filter roles or principals..." : (appState.selectedSecurityTab == .apis ? "Filter APIs..." : "Filter secrets..."),
                    width: 210
                )

                ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise", isLoading: appState.isLoadingIAM || appState.isLoadingSecrets) {
                    Task { await appState.refreshSecuritySection() }
                }
            }

            switch appState.selectedSecurityTab {
            case .iam:
                if appState.isLoadingIAM && appState.iamBindings.isEmpty {
                    ProgressView("Loading IAM policy...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = appState.iamError, appState.iamBindings.isEmpty {
                    EmptyStateView(icon: "lock.shield", title: "IAM unavailable", message: err, actionTitle: "Retry") {
                        Task { await appState.refreshIAMAndAPIs() }
                    }
                } else {
                    iamListView
                }
            case .apis:
                if appState.isLoadingIAM && appState.enabledAPIs.isEmpty {
                    ProgressView("Loading enabled APIs...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = appState.iamError, appState.enabledAPIs.isEmpty {
                    EmptyStateView(icon: "lock.shield", title: "Service Usage unavailable", message: err, actionTitle: "Retry") {
                        Task { await appState.refreshIAMAndAPIs() }
                    }
                } else {
                    apisListView
                }
            case .secrets:
                secretManagerView
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

    private var secretManagerView: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = appState.secrets.filter {
            q.isEmpty || $0.shortName.lowercased().contains(q)
        }
        return Group {
            if appState.isLoadingSecrets && appState.secrets.isEmpty {
                ProgressView("Loading secrets...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.secretsError, appState.secrets.isEmpty {
                EmptyStateView(icon: "key.fill", title: "Secret Manager unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshSecrets() }
                }
            } else if filtered.isEmpty {
                EmptyStateView(icon: "key", title: "No secrets stored", message: "Create secrets in Secret Manager to inspect versions and payloads.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { secret in
                            let isHovered = hoveredRow == secret.id
                            let isSelected: Bool = {
                                if case .secret(let cur) = appState.inspector { return cur.id == secret.id }
                                return false
                            }()

                            HStack(spacing: 12) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(T3.amber)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(secret.shortName)
                                        .font(T3.mono(13, weight: .semibold))
                                        .foregroundStyle(T3.textPrimary)

                                    HStack(spacing: 8) {
                                        TagPill(text: secret.replicationPolicy)
                                        ForEach(secret.labels.keys.sorted(), id: \.self) { k in
                                            TagPill(text: "\(k):\(secret.labels[k] ?? "")", monospaced: true)
                                        }
                                    }
                                }

                                Spacer()

                                if let created = secret.createTime {
                                    Text(Formatters.relativeDate(created))
                                        .font(T3.mono(11))
                                        .foregroundStyle(T3.textTertiary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                isSelected ? T3.surfaceActive : (isHovered ? T3.surfaceHover : Color.clear),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .contentShape(Rectangle())
                            .onHover { hoveredRow = $0 ? secret.id : nil }
                            .onTapGesture {
                                Task { await appState.inspectSecret(secret) }
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }
}
