import SwiftUI
import AppKit

struct InspectorDrawerView: View {
    @Environment(AppState.self) private var appState
    let selection: InspectorSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(headerTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(T3.textTertiary)
                Spacer()
                Button {
                    appState.inspector = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(T3.textSecondary)
                        .padding(6)
                        .background(T3.surfaceHover, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 34)
            .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selection {
                    case .vm(let vm):
                        vmInspector(vm)
                    case .gke(let cluster):
                        gkeInspector(cluster)
                    case .cloudRun(let svc):
                        cloudRunInspector(svc)
                    case .function(let fn):
                        functionInspector(fn)
                    case .firewall(let rule):
                        firewallInspector(rule)
                    case .artifactRepo(let repo):
                        artifactRepoInspector(repo)
                    case .gcsObject(let obj, let preview):
                        gcsObjectInspector(obj, previewText: preview)
                    case .sql(let sql):
                        sqlInspector(sql)
                    case .redis(let redis):
                        redisInspector(redis)
                    case .secret(let secret):
                        secretInspector(secret)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
            }
        }
        .frame(maxHeight: .infinity)
        .background(T3.bgInspector)
    }

    private var headerTitle: String {
        switch selection {
        case .vm: return "VIRTUAL MACHINE"
        case .gke: return "GKE CLUSTER"
        case .cloudRun: return "CLOUD RUN SERVICE"
        case .function: return "CLOUD FUNCTION"
        case .firewall: return "FIREWALL RULE"
        case .artifactRepo: return "ARTIFACT REPOSITORY"
        case .gcsObject: return "STORAGE OBJECT"
        case .sql: return "CLOUD SQL INSTANCE"
        case .redis: return "MEMORYSTORE REDIS"
        case .secret: return "SECRET MANAGER"
        }
    }

    // MARK: - VM Inspector

    private func vmInspector(_ vm: ComputeInstance) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(color: vm.isRunning ? T3.mint : T3.slate, size: 6)
                    Text(vm.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
                Text(vm.status)
                    .font(T3.mono(11, weight: .semibold))
                    .foregroundStyle(vm.isRunning ? T3.mint : T3.textSecondary)
            }

            HStack(spacing: 8) {
                if vm.isRunning {
                    ActionPillButton(title: "Stop", systemImage: "stop.fill", tint: T3.rose) {
                        Task { await appState.performVMAction(vm, action: "stop") }
                    }
                    ActionPillButton(title: "Reset", systemImage: "arrow.triangle.2.circlepath", tint: T3.amber) {
                        Task { await appState.performVMAction(vm, action: "reset") }
                    }
                } else {
                    ActionPillButton(title: "Start", systemImage: "play.fill", tint: T3.mint) {
                        Task { await appState.performVMAction(vm, action: "start") }
                    }
                }
                ActionPillButton(title: "Copy SSH", systemImage: "terminal", tint: T3.sky) {
                    appState.copyToClipboard(vm.sshCommand, label: "SSH command")
                }
            }

            keyValueBlock([
                ("Zone", vm.zone),
                ("Machine Type", vm.machineTypeShort),
                ("vCPUs", "\(vm.vcpuCount)"),
                ("Internal IP", vm.internalIP ?? "—"),
                ("External IP", vm.externalIP ?? "None"),
                ("CPU Platform", vm.cpuPlatform ?? "—"),
                ("Boot Disk", "\(vm.diskSizeGb) GB"),
                ("Est. Monthly", Formatters.currencyPrecise(vm.estimatedMonthlyCost))
            ])

            if !vm.labels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LABELS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(T3.textTertiary)
                    FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(vm.labels.keys.sorted(), id: \.self) { key in
                            TagPill(text: "\(key)=\(vm.labels[key] ?? "")", monospaced: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cloud Run Inspector

    private func cloudRunInspector(_ svc: CloudRunService) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(color: svc.conditionsReady ? T3.mint : T3.rose, size: 6)
                    Text(svc.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
                if !svc.uri.isEmpty {
                    Button {
                        if let url = URL(string: svc.uri) { NSWorkspace.shared.open(url) }
                    } label: {
                        Text(svc.uri)
                            .font(T3.mono(11))
                            .foregroundStyle(T3.sky)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            keyValueBlock([
                ("Region", svc.region),
                ("Ingress", svc.ingress),
                ("CPU / Memory", "\(svc.cpu) / \(svc.memory)"),
                ("Scaling", "\(svc.minInstances) – \(svc.maxInstances) instances"),
                ("Latest Ready", svc.latestReadyRevision)
            ])

            VStack(alignment: .leading, spacing: 8) {
                Text("TRAFFIC SPLIT")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(T3.textTertiary)

                ForEach(svc.traffic) { t in
                    HStack {
                        Text(t.revisionName)
                            .font(T3.mono(11.5))
                            .foregroundStyle(T3.textPrimary)
                        Spacer()
                        Text("\(t.percent)%")
                            .font(T3.mono(11.5, weight: .semibold))
                            .foregroundStyle(T3.indigo)
                    }
                    .padding(8)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 6))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("REVISIONS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(T3.textTertiary)
                    Spacer()
                    if appState.isLoadingRevisions {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    }
                }

                ForEach(appState.cloudRunRevisions) { rev in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            StatusDot(color: rev.ready ? T3.mint : T3.rose, size: 5)
                            Text(rev.name)
                                .font(T3.mono(11.5, weight: .medium))
                                .foregroundStyle(T3.textPrimary)
                        }
                        Text(rev.containerImage)
                            .font(T3.mono(10))
                            .foregroundStyle(T3.textTertiary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - GCS Object Inspector

    private func gcsObjectInspector(_ obj: GCSObject, previewText: String?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(obj.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(T3.textPrimary)
                Text("gs://\(obj.bucket)/\(obj.name)")
                    .font(T3.mono(11))
                    .foregroundStyle(T3.textTertiary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                ActionPillButton(title: "Download", systemImage: "arrow.down.circle", tint: T3.sky) {
                    Task { await appState.downloadObject(obj) }
                }
                ActionPillButton(title: "Copy gs://", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                    appState.copyToClipboard("gs://\(obj.bucket)/\(obj.name)", label: "GCS URI")
                }
                ActionPillButton(title: "Delete", systemImage: "trash", tint: T3.rose) {
                    Task { await appState.deleteObject(obj) }
                }
            }

            keyValueBlock([
                ("Size", Formatters.byteCount(obj.sizeBytes)),
                ("Content-Type", obj.contentType),
                ("Updated", obj.updated.map { Formatters.relativeDate($0) } ?? "—")
            ])

            if let previewText {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PREVIEW")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(T3.textTertiary)

                    Text(previewText)
                        .font(T3.mono(11))
                        .foregroundStyle(T3.textSecondary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Cloud SQL Inspector

    private func sqlInspector(_ sql: CloudSQLInstance) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(color: sql.isRunnable ? T3.mint : T3.amber, size: 6)
                    Text(sql.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
                Text(sql.databaseVersion)
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.sky)
            }

            HStack(spacing: 8) {
                ActionPillButton(title: "Restart", systemImage: "arrow.triangle.2.circlepath", tint: T3.amber) {
                    Task { await appState.restartSQLInstance(sql) }
                }
                if let ip = sql.ipAddress {
                    ActionPillButton(title: "Copy IP", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                        appState.copyToClipboard(ip, label: "SQL IP")
                    }
                }
            }

            keyValueBlock([
                ("State", sql.state),
                ("Region", sql.region),
                ("Tier", sql.tier),
                ("IP Address", sql.ipAddress ?? "Private / none"),
                ("Storage", "\(sql.storageSizeGb) GB"),
                ("Availability", sql.availabilityType),
                ("Est. Monthly", Formatters.currencyPrecise(sql.estimatedMonthlyCost))
            ])
        }
    }

    // MARK: - Secret Manager Inspector

    private func secretInspector(_ secret: SecretItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(secret.shortName)
                    .font(T3.mono(16, weight: .semibold))
                    .foregroundStyle(T3.textPrimary)
                Text("Replication: \(secret.replicationPolicy)")
                    .font(.system(size: 12))
                    .foregroundStyle(T3.textMuted)
            }

            if let revealed = appState.revealedSecretValue {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SECRET PAYLOAD")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(T3.amber)
                        Spacer()
                        Button("Hide") {
                            appState.revealedSecretValue = nil
                            appState.revealedSecretVersionId = nil
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(T3.textSecondary)
                    }

                    Text(revealed)
                        .font(T3.mono(12))
                        .foregroundStyle(T3.textPrimary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))

                    ActionPillButton(title: "Copy Value", systemImage: "doc.on.doc", tint: T3.mint) {
                        appState.copyToClipboard(revealed, label: "secret value")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("VERSIONS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(T3.textTertiary)

                ForEach(appState.secretVersions) { ver in
                    HStack {
                        StatusDot(color: ver.state == "ENABLED" ? T3.mint : T3.slate, size: 5)
                        Text("v\(ver.versionNumber)")
                            .font(T3.mono(12, weight: .semibold))
                            .foregroundStyle(T3.textPrimary)
                        TagPill(text: ver.state, monospaced: true)
                        Spacer()
                        if ver.state == "ENABLED" {
                            ActionPillButton(title: "Reveal", systemImage: "eye", tint: T3.amber) {
                                Task { await appState.revealSecretVersion(ver) }
                            }
                        }
                    }
                    .padding(8)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func gkeInspector(_ cluster: GKECluster) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(color: cluster.isRunning ? T3.mint : T3.amber, size: 6)
                    Text(cluster.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
                Text("Kubernetes v\(cluster.masterVersion)")
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.indigo)
            }

            ActionPillButton(title: "Copy kubectl auth", systemImage: "terminal", tint: T3.sky) {
                let pid = appState.selectedProject?.projectId ?? ""
                appState.copyToClipboard(cluster.getCredentialsCommand(projectId: pid), label: "kubectl auth command")
            }

            keyValueBlock([
                ("Location", cluster.location),
                ("Status", cluster.status),
                ("Total Nodes", "\(cluster.nodeCount)"),
                ("Endpoint", cluster.endpoint.isEmpty ? "Private" : cluster.endpoint),
                ("Network", cluster.network)
            ])

            VStack(alignment: .leading, spacing: 8) {
                Text("NODE POOLS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(T3.textTertiary)
                ForEach(cluster.nodePools) { pool in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pool.name)
                                .font(T3.mono(12, weight: .medium))
                                .foregroundStyle(T3.textPrimary)
                            Text(pool.machineType)
                                .font(T3.mono(10.5))
                                .foregroundStyle(T3.textTertiary)
                        }
                        Spacer()
                        Text("\(pool.nodeCount) nodes")
                            .font(T3.mono(11.5))
                            .foregroundStyle(T3.textSecondary)
                    }
                    .padding(8)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func functionInspector(_ fn: CloudFunctionItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(color: fn.isActive ? T3.mint : T3.amber, size: 6)
                    Text(fn.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
                Text(fn.runtime)
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.coral)
            }

            if !fn.uri.isEmpty {
                ActionPillButton(title: "Open Endpoint", systemImage: "arrow.up.right", tint: T3.sky) {
                    if let url = URL(string: fn.uri) { NSWorkspace.shared.open(url) }
                }
            }

            keyValueBlock([
                ("Region", fn.region),
                ("State", fn.state),
                ("Memory", fn.memory),
                ("Trigger", fn.triggerType),
                ("Updated", fn.updated.map { Formatters.relativeDate($0) } ?? "—")
            ])
        }
    }

    private func firewallInspector(_ rule: FirewallRule) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(color: rule.disabled ? T3.slate : (rule.action == "ALLOW" ? T3.mint : T3.rose), size: 6)
                    Text(rule.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
                Text("\(rule.action) · \(rule.direction) · Priority \(rule.priority)")
                    .font(T3.mono(11.5))
                    .foregroundStyle(rule.action == "ALLOW" ? T3.mint : T3.rose)
            }

            keyValueBlock([
                ("Network", rule.network),
                ("Protocols / Ports", rule.protocolsAndPorts),
                ("Disabled", rule.disabled ? "Yes" : "No")
            ])

            if !rule.sourceRanges.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SOURCE RANGES")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(T3.textTertiary)
                    FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(rule.sourceRanges, id: \.self) { range in
                            TagPill(text: range, monospaced: true)
                        }
                    }
                }
            }

            if !rule.targetTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TARGET TAGS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(T3.textTertiary)
                    FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(rule.targetTags, id: \.self) { tag in
                            TagPill(text: tag, monospaced: true)
                        }
                    }
                }
            }
        }
    }

    private func artifactRepoInspector(_ repo: ArtifactRepo) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(repo.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(T3.textPrimary)
                Text("\(repo.format) · \(repo.location)")
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.sky)
            }

            keyValueBlock([
                ("Location", repo.location),
                ("Format", repo.format),
                ("Size", repo.sizeBytes > 0 ? Formatters.byteCount(repo.sizeBytes) : "—")
            ])

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("IMAGES")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(T3.textTertiary)
                    Spacer()
                    if appState.isLoadingArtifactImages {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    }
                }

                ForEach(appState.artifactImages) { img in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(img.name)
                                .font(T3.mono(12, weight: .semibold))
                                .foregroundStyle(T3.textPrimary)
                            Spacer()
                            Button {
                                appState.copyToClipboard("docker pull \(img.uri)", label: "docker pull command")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(T3.sky)
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 6) {
                            ForEach(img.tags.prefix(3), id: \.self) { t in
                                TagPill(text: t, monospaced: true)
                            }
                            if img.sizeBytes > 0 {
                                Text(Formatters.byteCount(img.sizeBytes))
                                    .font(T3.mono(10))
                                    .foregroundStyle(T3.textTertiary)
                            }
                        }
                    }
                    .padding(8)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private func redisInspector(_ redis: RedisInstance) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(color: redis.isReady ? T3.mint : T3.amber, size: 6)
                    Text(redis.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
                Text(redis.redisVersion)
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.coral)
            }

            ActionPillButton(title: "Copy Endpoint", systemImage: "doc.on.doc", tint: T3.sky) {
                appState.copyToClipboard("\(redis.host):\(redis.port)", label: "Redis endpoint")
            }

            keyValueBlock([
                ("Location", redis.location),
                ("Tier", redis.tier),
                ("Memory", "\(redis.memorySizeGb) GB"),
                ("Host", redis.host),
                ("Port", "\(redis.port)"),
                ("State", redis.state)
            ])
        }
    }

    private func keyValueBlock(_ pairs: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pairs, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textTertiary)
                    Spacer()
                    Text(value)
                        .font(T3.mono(12))
                        .foregroundStyle(T3.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
