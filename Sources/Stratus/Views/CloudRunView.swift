import SwiftUI
import AppKit

struct CloudRunView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var hoveredId: String?

    private var filteredServices: [CloudRunService] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return appState.cloudRunServices }
        return appState.cloudRunServices.filter {
            $0.name.lowercased().contains(q) || $0.region.lowercased().contains(q) || $0.uri.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cloud Run")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(appState.cloudRunServices.count) serverless containers · \(appState.selectedProject?.projectId ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                BorderlessSearchField(text: $searchText, placeholder: "Filter services or regions...", width: 230)

                ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise", isLoading: appState.isLoadingCloudRun) {
                    Task { await appState.refreshCloudRun() }
                }
            }

            if appState.isLoadingCloudRun && appState.cloudRunServices.isEmpty {
                ProgressView("Loading Cloud Run services...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.cloudRunError, appState.cloudRunServices.isEmpty {
                EmptyStateView(icon: "bolt.horizontal.fill", title: "Cloud Run unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshCloudRun() }
                }
            } else if filteredServices.isEmpty {
                EmptyStateView(
                    icon: "bolt.slash",
                    title: "No Cloud Run services",
                    message: "No matching services deployed in this project."
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredServices) { svc in
                            serviceRow(svc)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .background(T3.bg)
    }

    private func serviceRow(_ svc: CloudRunService) -> some View {
        let isSelected: Bool = {
            if case .cloudRun(let current) = appState.inspector { return current.id == svc.id }
            return false
        }()
        let isHovered = hoveredId == svc.id

        return HStack(spacing: 14) {
            StatusDot(color: svc.conditionsReady ? T3.mint : T3.rose, size: 6, pulse: svc.conditionsReady)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(svc.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                    TagPill(text: svc.region, monospaced: true)
                    TagPill(text: "\(svc.cpu) · \(svc.memory)", monospaced: true)
                    if svc.minInstances > 0 {
                        TagPill(text: "min \(svc.minInstances)", color: T3.indigo)
                    }
                }

                HStack(spacing: 10) {
                    if !svc.uri.isEmpty {
                        Button {
                            if let url = URL(string: svc.uri) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(svc.uri.replacingOccurrences(of: "https://", with: ""))
                                    .font(T3.mono(11))
                                    .foregroundStyle(T3.sky)
                                    .lineLimit(1)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(T3.sky)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Text("rev \(svc.latestReadyRevision)")
                        .font(T3.mono(11))
                        .foregroundStyle(T3.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Compact inline traffic split indicator
            HStack(spacing: 3) {
                ForEach(Array(svc.traffic.enumerated()), id: \.element.id) { idx, target in
                    let barColor = idx == 0 ? T3.indigo : T3.coral
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(barColor)
                        .frame(width: max(8, CGFloat(target.percent) * 0.72), height: 5)
                }
            }
            .help(svc.traffic.map { "\($0.percent)% → \($0.revisionName)" }.joined(separator: "\n"))

            VStack(alignment: .trailing, spacing: 2) {
                if svc.requestCount24h > 0 {
                    Text("\(Formatters.compactNumber(svc.requestCount24h)) req")
                        .font(T3.mono(12, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
                Text(Formatters.currencyPrecise(svc.estimatedMonthlyCost))
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.textSecondary)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? T3.surfaceActive : (isHovered ? T3.surfaceHover : Color.clear),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hoveredId = $0 ? svc.id : nil }
        .onTapGesture {
            Task { await appState.inspectCloudRunService(svc) }
        }
    }
}
