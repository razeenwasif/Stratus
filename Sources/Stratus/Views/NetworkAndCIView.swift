import SwiftUI
import AppKit

struct NetworkAndCIView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var hoveredId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Network & CI")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(appState.selectedProject?.projectId ?? "") · VPC, Artifact Registry, Cloud Build & Scheduler")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(NetworkCISubTab.allCases) { tab in
                        FilterPillButton(title: tab.title, isSelected: appState.selectedNetworkCITab == tab) {
                            appState.selectedNetworkCITab = tab
                            Task { await appState.refreshNetworkCISection() }
                        }
                    }
                }

                BorderlessSearchField(text: $searchText, placeholder: "Filter...", width: 200)

                ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise") {
                    Task { await appState.refreshNetworkCISection() }
                }
            }

            switch appState.selectedNetworkCITab {
            case .vpc:
                vpcView
            case .artifacts:
                artifactsView
            case .builds:
                buildsAndSchedulerView
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .background(T3.bg)
    }

    // MARK: - VPC & Firewalls

    private var vpcView: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredRules = appState.firewallRules.filter {
            q.isEmpty || $0.name.lowercased().contains(q) || $0.network.lowercased().contains(q) || $0.protocolsAndPorts.lowercased().contains(q)
        }

        return Group {
            if appState.isLoadingNetwork && appState.vpcNetworks.isEmpty && appState.firewallRules.isEmpty {
                ProgressView("Loading VPC networks & firewall rules...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.networkError, appState.firewallRules.isEmpty {
                EmptyStateView(icon: "network", title: "Networking unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshNetwork() }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        if !appState.vpcNetworks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("VPC NETWORKS")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundStyle(T3.textTertiary)

                                HStack(spacing: 28) {
                                    ForEach(appState.vpcNetworks) { net in
                                        MetricStatColumn(
                                            label: net.name,
                                            value: "\(net.subnetworkCount) subnets",
                                            subtitle: "\(net.routingMode) · \(net.autoCreateSubnetworks ? "auto" : "custom")"
                                        )
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("FIREWALL RULES (\(filteredRules.count))")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(T3.textTertiary)

                            LazyVStack(alignment: .leading, spacing: 5) {
                                ForEach(filteredRules) { rule in
                                    let isHovered = hoveredId == rule.id
                                    HStack(spacing: 12) {
                                        StatusDot(color: rule.disabled ? T3.slate : (rule.action == "ALLOW" ? T3.mint : T3.rose), size: 5.5)

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 8) {
                                                Text(rule.name)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(T3.textPrimary)
                                                TagPill(text: rule.action, color: rule.action == "ALLOW" ? T3.mint : T3.rose, monospaced: true)
                                                TagPill(text: rule.direction, monospaced: true)
                                                TagPill(text: rule.network, monospaced: true)
                                            }
                                            HStack(spacing: 10) {
                                                Text(rule.protocolsAndPorts)
                                                    .font(T3.mono(11))
                                                    .foregroundStyle(T3.sky)
                                                if !rule.sourceRanges.isEmpty {
                                                    Text(rule.sourceRanges.joined(separator: ", "))
                                                        .font(T3.mono(11))
                                                        .foregroundStyle(T3.textTertiary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }

                                        Spacer()

                                        Text("p\(rule.priority)")
                                            .font(T3.mono(11.5))
                                            .foregroundStyle(T3.textSecondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(
                                        isHovered ? T3.surfaceHover : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .contentShape(Rectangle())
                                    .onHover { hoveredId = $0 ? rule.id : nil }
                                    .onTapGesture {
                                        appState.inspector = .firewall(rule)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Artifact Registry

    private var artifactsView: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = appState.artifactRepos.filter {
            q.isEmpty || $0.name.lowercased().contains(q) || $0.format.lowercased().contains(q) || $0.location.lowercased().contains(q)
        }

        return Group {
            if appState.isLoadingArtifacts && appState.artifactRepos.isEmpty {
                ProgressView("Loading Artifact Registry repositories...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.artifactsError, appState.artifactRepos.isEmpty {
                EmptyStateView(icon: "shippingbox", title: "Artifact Registry unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshArtifacts() }
                }
            } else if filtered.isEmpty {
                EmptyStateView(icon: "shippingbox", title: "No repositories", message: "No Artifact Registry repositories found in this project.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { repo in
                            let isHovered = hoveredId == repo.id
                            HStack(spacing: 12) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(T3.sky)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(repo.name)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(T3.textPrimary)
                                        TagPill(text: repo.format, color: T3.indigo, monospaced: true)
                                        TagPill(text: repo.location, monospaced: true)
                                    }
                                    if !repo.description.isEmpty {
                                        Text(repo.description)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(T3.textMuted)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if repo.sizeBytes > 0 {
                                    Text(Formatters.byteCount(repo.sizeBytes))
                                        .font(T3.mono(12))
                                        .foregroundStyle(T3.textSecondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                isHovered ? T3.surfaceHover : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .contentShape(Rectangle())
                            .onHover { hoveredId = $0 ? repo.id : nil }
                            .onTapGesture {
                                Task { await appState.inspectArtifactRepo(repo) }
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Cloud Build & Cloud Scheduler

    private var buildsAndSchedulerView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CLOUD BUILD (\(appState.cloudBuilds.count))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(T3.textTertiary)

                    if appState.cloudBuilds.isEmpty && !appState.isLoadingBuilds {
                        Text("No recent Cloud Build runs found.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(T3.textTertiary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(appState.cloudBuilds) { build in
                                HStack(spacing: 12) {
                                    StatusDot(
                                        color: build.isSuccess ? T3.mint : (build.isFailure ? T3.rose : T3.amber),
                                        size: 6,
                                        pulse: !build.isSuccess && !build.isFailure
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Text(build.sourceSummary)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(T3.textPrimary)
                                            TagPill(text: build.status, monospaced: true)
                                        }
                                        Text(build.id)
                                            .font(T3.mono(11))
                                            .foregroundStyle(T3.textTertiary)
                                    }

                                    Spacer()

                                    if let dur = build.durationSeconds {
                                        Text("\(dur)s")
                                            .font(T3.mono(11.5))
                                            .foregroundStyle(T3.textSecondary)
                                    }
                                    if let created = build.createTime {
                                        Text(Formatters.relativeDate(created))
                                            .font(T3.mono(11))
                                            .foregroundStyle(T3.textTertiary)
                                    }
                                    if let urlStr = build.logUrl, let url = URL(string: urlStr) {
                                        ActionPillButton(title: "Logs", systemImage: "arrow.up.right", tint: T3.sky) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("CLOUD SCHEDULER JOBS (\(appState.schedulerJobs.count))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(T3.textTertiary)

                    if appState.schedulerJobs.isEmpty && !appState.isLoadingBuilds {
                        Text("No Cloud Scheduler jobs found.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(T3.textTertiary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(appState.schedulerJobs) { job in
                                let isBusy = appState.busySchedulerJobs.contains(job.id)
                                HStack(spacing: 12) {
                                    StatusDot(color: job.isEnabled ? T3.mint : T3.slate, size: 6)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(job.name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(T3.textPrimary)
                                            TagPill(text: job.schedule, color: T3.indigo, monospaced: true)
                                            TagPill(text: job.location, monospaced: true)
                                        }
                                        Text("\(job.targetSummary) · \(job.timeZone)")
                                            .font(T3.mono(11))
                                            .foregroundStyle(T3.textTertiary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    ActionPillButton(title: "Run Now", systemImage: "play.fill", tint: T3.mint, isLoading: isBusy) {
                                        Task { await appState.runSchedulerJob(job) }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }
}
