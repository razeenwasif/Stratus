import SwiftUI

struct ComputeView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var statusFilter: VMStatusFilter = .all
    @State private var hoveredId: String?

    enum VMStatusFilter: String, CaseIterable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
    }

    private var filteredInstances: [ComputeInstance] {
        appState.instances.filter { vm in
            let matchesStatus: Bool
            switch statusFilter {
            case .all: matchesStatus = true
            case .running: matchesStatus = vm.isRunning
            case .stopped: matchesStatus = !vm.isRunning
            }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesQuery = q.isEmpty
                || vm.name.lowercased().contains(q)
                || vm.zone.lowercased().contains(q)
                || vm.machineTypeShort.lowercased().contains(q)
                || (vm.externalIP ?? "").contains(q)
            return matchesStatus && matchesQuery
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            statsStrip

            if appState.isLoadingCompute && appState.instances.isEmpty {
                ProgressView("Loading VM instances...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.computeError, appState.instances.isEmpty {
                EmptyStateView(icon: "cpu", title: "Compute Engine unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshCompute() }
                }
            } else if filteredInstances.isEmpty {
                EmptyStateView(
                    icon: "server.rack",
                    title: "No VM instances match",
                    message: appState.instances.isEmpty
                        ? "This project has no Compute Engine virtual machines."
                        : "Clear the active search or status filter."
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredInstances) { vm in
                            vmRow(vm)
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

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Compute Engine")
                    .font(T3.pageTitle())
                    .foregroundStyle(T3.textPrimary)
                Text("\(appState.instances.count) virtual machines · \(appState.selectedProject?.projectId ?? "")")
                    .font(.system(size: 12))
                    .foregroundStyle(T3.textMuted)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(VMStatusFilter.allCases, id: \.self) { filter in
                    FilterPillButton(title: filter.rawValue, isSelected: statusFilter == filter) {
                        statusFilter = filter
                    }
                }
            }

            BorderlessSearchField(text: $searchText, placeholder: "Filter VMs, zones, IPs...", width: 220)

            ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise", isLoading: appState.isLoadingCompute) {
                Task { await appState.refreshCompute() }
            }
        }
    }

    private var statsStrip: some View {
        let running = appState.instances.filter(\.isRunning)
        let totalVCPUs = running.reduce(0) { $0 + $1.vcpuCount }
        let extIPs = appState.instances.compactMap(\.externalIP).count
        let estMonthly = appState.instances.reduce(0.0) { $0 + $1.estimatedMonthlyCost }

        return HStack(spacing: 28) {
            MetricStatColumn(label: "Running VMs", value: "\(running.count) / \(appState.instances.count)")
            MetricStatColumn(label: "Active vCPUs", value: "\(totalVCPUs)")
            MetricStatColumn(label: "External IPs", value: "\(extIPs)")
            MetricStatColumn(label: "Est. Monthly", value: Formatters.currency(estMonthly))
        }
    }

    private func vmRow(_ vm: ComputeInstance) -> some View {
        let isSelected: Bool = {
            if case .vm(let current) = appState.inspector { return current.id == vm.id }
            return false
        }()
        let isHovered = hoveredId == vm.id
        let isBusy = appState.busyInstanceIds.contains(vm.id)

        return HStack(spacing: 14) {
            StatusDot(color: vm.isRunning ? T3.mint : T3.slate, size: 6, pulse: vm.isRunning)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(vm.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                    TagPill(text: vm.zone, monospaced: true)
                    TagPill(text: vm.machineTypeShort, monospaced: true)
                }

                HStack(spacing: 12) {
                    if let internalIP = vm.internalIP {
                        Text("int \(internalIP)")
                            .font(T3.mono(11))
                            .foregroundStyle(T3.textTertiary)
                    }
                    if let externalIP = vm.externalIP {
                        Text("ext \(externalIP)")
                            .font(T3.mono(11))
                            .foregroundStyle(T3.sky)
                    }
                    Text("\(vm.diskSizeGb) GB disk")
                        .font(T3.mono(11))
                        .foregroundStyle(T3.textTertiary)
                }
            }

            Spacer()

            if isHovered || isSelected || isBusy {
                HStack(spacing: 6) {
                    if vm.isRunning {
                        ActionPillButton(title: "Stop", systemImage: "stop.fill", tint: T3.rose, isLoading: isBusy) {
                            Task { await appState.performVMAction(vm, action: "stop") }
                        }
                        ActionPillButton(title: "Reset", systemImage: "arrow.triangle.2.circlepath", tint: T3.amber, isLoading: isBusy) {
                            Task { await appState.performVMAction(vm, action: "reset") }
                        }
                    } else {
                        ActionPillButton(title: "Start", systemImage: "play.fill", tint: T3.mint, isLoading: isBusy) {
                            Task { await appState.performVMAction(vm, action: "start") }
                        }
                    }
                    ActionPillButton(title: "SSH", systemImage: "terminal", tint: T3.textSecondary) {
                        appState.copyToClipboard(vm.sshCommand, label: "SSH command")
                    }
                }
            }

            Text(Formatters.currencyPrecise(vm.estimatedMonthlyCost))
                .font(T3.mono(12.5, weight: .semibold))
                .foregroundStyle(T3.textPrimary)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isSelected ? T3.surfaceActive : (isHovered ? T3.surfaceHover : Color.clear),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hoveredId = $0 ? vm.id : nil }
        .onTapGesture {
            appState.inspector = .vm(vm)
        }
    }
}
