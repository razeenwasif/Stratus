import SwiftUI

struct DataServicesView: View {
    @Environment(AppState.self) private var appState
    @State private var sqlQuery: String = """
    SELECT
      service.description AS service_name,
      location.region AS region,
      COUNT(*) AS line_items,
      ROUND(SUM(cost), 2) AS cost_usd
    FROM `billing_export.gcp_billing_export_v1`
    GROUP BY 1, 2
    ORDER BY cost_usd DESC
    LIMIT 25;
    """
    @State private var hoveredDataset: String?
    @State private var hoveredSQL: String?
    @State private var pubSubDrafts: [String: String] = [:]

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Data & Messaging")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(appState.selectedProject?.projectId ?? "") · BigQuery, SQL, Firestore, Spanner, Redis & Pub/Sub")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(DataSubTab.allCases) { tab in
                        FilterPillButton(title: tab.title, isSelected: appState.selectedDataTab == tab) {
                            appState.selectedDataTab = tab
                            Task { await appState.refreshDataServices() }
                        }
                    }
                }

                ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise") {
                    Task { await appState.refreshDataServices() }
                }
            }

            switch appState.selectedDataTab {
            case .bigQuery:
                bigQueryView
            case .cloudSQL:
                cloudSQLView
            case .firestore:
                firestoreView
            case .spanner:
                spannerView
            case .redis:
                redisView
            case .pubSub:
                pubSubView
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .background(T3.bg)
    }

    // MARK: - BigQuery

    private var bigQueryView: some View {
        HStack(alignment: .top, spacing: 32) {
            // Datasets & Tables Sidebar (no visible divider)
            VStack(alignment: .leading, spacing: 14) {
                Text("DATASETS")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(T3.textTertiary)
                    .padding(.horizontal, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.datasets) { ds in
                            let isSelected = appState.selectedDataset?.datasetId == ds.datasetId
                            Button {
                                Task { await appState.selectDataset(ds) }
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(isSelected ? T3.amber : T3.textTertiary)
                                    Text(ds.datasetId)
                                        .font(T3.mono(12, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? T3.textPrimary : T3.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(ds.location)
                                        .font(T3.mono(10))
                                        .foregroundStyle(T3.textTertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ? T3.surfaceActive : (hoveredDataset == ds.id ? T3.surfaceHover : Color.clear),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { hoveredDataset = $0 ? ds.id : nil }
                        }

                        if !appState.tables.isEmpty {
                            Text("TABLES")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(T3.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.top, 14)

                            ForEach(appState.tables) { tbl in
                                Button {
                                    sqlQuery = "SELECT *\nFROM `\(tbl.datasetId).\(tbl.tableId)`\nLIMIT 50;"
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: tbl.type == "VIEW" ? "eye" : "tablecells")
                                            .font(.system(size: 11))
                                            .foregroundStyle(T3.sky)
                                        Text(tbl.tableId)
                                            .font(T3.mono(11.5))
                                            .foregroundStyle(T3.textSecondary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(width: 230)

            // SQL Editor + Results
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $sqlQuery)
                        .font(T3.mono(12.5))
                        .foregroundStyle(T3.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(height: 155)
                        .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 12) {
                        ActionPillButton(
                            title: "Run Query",
                            systemImage: "play.fill",
                            tint: T3.mint,
                            isLoading: appState.isRunningQuery
                        ) {
                            Task { await appState.runBigQuery(sql: sqlQuery) }
                        }

                        if let res = appState.lastQueryResult {
                            Text("\(res.rows.count) rows · \(Formatters.byteCount(res.totalBytesProcessed)) processed · \(res.durationMs)ms")
                                .font(T3.mono(11))
                                .foregroundStyle(T3.textTertiary)
                        }
                        Spacer()
                    }
                }

                if let err = appState.bigQueryError {
                    Text(err)
                        .font(T3.mono(12))
                        .foregroundStyle(T3.rose)
                }

                if let result = appState.lastQueryResult {
                    queryResultsTable(result)
                } else {
                    EmptyStateView(
                        icon: "terminal",
                        title: "BigQuery SQL Workspace",
                        message: "Select a table on the left or write Standard SQL above and press Run Query."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func queryResultsTable(_ result: BQQueryResult) -> some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                // Header Row
                HStack(spacing: 16) {
                    ForEach(result.columns, id: \.self) { col in
                        Text(col)
                            .font(T3.mono(11, weight: .semibold))
                            .foregroundStyle(T3.textSecondary)
                            .frame(width: 140, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                ForEach(Array(result.rows.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 16) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, val in
                            Text(val)
                                .font(T3.mono(12))
                                .foregroundStyle(T3.textPrimary)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        idx % 2 == 0 ? T3.surfaceSubtle : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Cloud SQL

    private var cloudSQLView: some View {
        Group {
            if appState.isLoadingSQL && appState.sqlInstances.isEmpty {
                ProgressView("Loading Cloud SQL instances...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.sqlError, appState.sqlInstances.isEmpty {
                EmptyStateView(icon: "cylinder.split.1x2", title: "Cloud SQL unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshCloudSQL() }
                }
            } else if appState.sqlInstances.isEmpty {
                EmptyStateView(icon: "cylinder", title: "No Cloud SQL instances", message: "This project has no managed database instances.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.sqlInstances) { sql in
                            let isHovered = hoveredSQL == sql.id
                            let isBusy = appState.busySQLNames.contains(sql.name)

                            HStack(spacing: 14) {
                                StatusDot(color: sql.isRunnable ? T3.mint : T3.amber, size: 6, pulse: sql.isRunnable)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(sql.name)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(T3.textPrimary)
                                        TagPill(text: sql.databaseVersion, color: T3.sky, monospaced: true)
                                        TagPill(text: sql.availabilityType, monospaced: true)
                                    }

                                    HStack(spacing: 12) {
                                        Text(sql.region)
                                            .font(T3.mono(11))
                                            .foregroundStyle(T3.textTertiary)
                                        Text(sql.tier)
                                            .font(T3.mono(11))
                                            .foregroundStyle(T3.textTertiary)
                                        if let ip = sql.ipAddress {
                                            Text(ip)
                                                .font(T3.mono(11))
                                                .foregroundStyle(T3.sky)
                                        }
                                        Text("\(sql.storageSizeGb) GB")
                                            .font(T3.mono(11))
                                            .foregroundStyle(T3.textTertiary)
                                    }
                                }

                                Spacer()

                                if isHovered || isBusy {
                                    ActionPillButton(title: "Restart", systemImage: "arrow.triangle.2.circlepath", tint: T3.amber, isLoading: isBusy) {
                                        Task { await appState.restartSQLInstance(sql) }
                                    }
                                }

                                Text(Formatters.currencyPrecise(sql.estimatedMonthlyCost))
                                    .font(T3.mono(12.5, weight: .semibold))
                                    .foregroundStyle(T3.textPrimary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                isHovered ? T3.surfaceHover : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .contentShape(Rectangle())
                            .onHover { hoveredSQL = $0 ? sql.id : nil }
                            .onTapGesture {
                                appState.inspector = .sql(sql)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Firestore, Spanner, Memorystore Redis, Pub/Sub

    private var firestoreView: some View {
        FirestoreExplorerView()
    }

    private var spannerView: some View {
        Group {
            if appState.isLoadingSpanner && appState.spannerInstances.isEmpty {
                ProgressView("Loading Cloud Spanner instances...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.spannerError, appState.spannerInstances.isEmpty {
                EmptyStateView(icon: "globe", title: "Cloud Spanner unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshSpanner() }
                }
            } else if appState.spannerInstances.isEmpty {
                EmptyStateView(icon: "globe", title: "No Cloud Spanner instances", message: "No Cloud Spanner instances provisioned in this project.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.spannerInstances) { inst in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    StatusDot(color: inst.isReady ? T3.mint : T3.amber, size: 6)
                                    Text(inst.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(T3.textPrimary)
                                    TagPill(text: inst.config, color: T3.sky, monospaced: true)
                                    TagPill(text: "\(inst.processingUnits) PU", monospaced: true)
                                    Spacer()
                                    Text(inst.state)
                                        .font(T3.mono(11, weight: .semibold))
                                        .foregroundStyle(inst.isReady ? T3.mint : T3.amber)
                                }

                                if !inst.databases.isEmpty {
                                    FlowWrapLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                                        ForEach(inst.databases, id: \.self) { db in
                                            TagPill(text: db, monospaced: true)
                                        }
                                    }
                                    .padding(.leading, 18)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var redisView: some View {
        Group {
            if appState.isLoadingRedis && appState.redisInstances.isEmpty {
                ProgressView("Loading Memorystore Redis...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.redisError, appState.redisInstances.isEmpty {
                EmptyStateView(icon: "memorychip", title: "Memorystore unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshRedis() }
                }
            } else if appState.redisInstances.isEmpty {
                EmptyStateView(icon: "memorychip", title: "No Redis instances", message: "No Memorystore Redis instances found in this project.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.redisInstances) { redis in
                            HStack(spacing: 14) {
                                StatusDot(color: redis.isReady ? T3.mint : T3.amber, size: 6, pulse: redis.isReady)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(redis.name)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(T3.textPrimary)
                                        TagPill(text: redis.redisVersion, color: T3.coral, monospaced: true)
                                        TagPill(text: "\(redis.memorySizeGb) GB", monospaced: true)
                                        TagPill(text: redis.tier, monospaced: true)
                                    }
                                    Text("\(redis.host):\(redis.port) · \(redis.location)")
                                        .font(T3.mono(11))
                                        .foregroundStyle(T3.sky)
                                }

                                Spacer()

                                ActionPillButton(title: "Copy Host", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                                    appState.copyToClipboard("\(redis.host):\(redis.port)", label: "Redis endpoint")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.inspector = .redis(redis)
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var pubSubView: some View {
        Group {
            if appState.isLoadingPubSub && appState.pubSubTopics.isEmpty {
                ProgressView("Loading Pub/Sub topics & subscriptions...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.pubSubError, appState.pubSubTopics.isEmpty {
                EmptyStateView(icon: "arrow.triangle.branch", title: "Pub/Sub unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshPubSub() }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TOPICS (\(appState.pubSubTopics.count))")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(T3.textTertiary)

                            ForEach(appState.pubSubTopics) { topic in
                                let binding = Binding<String>(
                                    get: { pubSubDrafts[topic.id] ?? "" },
                                    set: { pubSubDrafts[topic.id] = $0 }
                                )
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 12))
                                        .foregroundStyle(T3.mint)
                                    Text(topic.name)
                                        .font(T3.mono(13, weight: .semibold))
                                        .foregroundStyle(T3.textPrimary)
                                    Spacer()
                                    BorderlessSearchField(text: binding, placeholder: "Publish JSON/text message...", width: 250)
                                    ActionPillButton(title: "Publish", systemImage: "paperplane.fill", tint: T3.mint) {
                                        let payload = pubSubDrafts[topic.id] ?? ""
                                        pubSubDrafts[topic.id] = ""
                                        Task { await appState.publishPubSubMessage(topic: topic, payload: payload) }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("SUBSCRIPTIONS (\(appState.pubSubSubscriptions.count))")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(T3.textTertiary)

                            ForEach(appState.pubSubSubscriptions) { sub in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(sub.name)
                                                .font(T3.mono(12.5, weight: .semibold))
                                                .foregroundStyle(T3.textPrimary)
                                            TagPill(text: "topic: \(sub.topicName)", color: T3.indigo, monospaced: true)
                                            TagPill(text: "ack \(sub.ackDeadlineSeconds)s", monospaced: true)
                                        }
                                        if let endpoint = sub.pushEndpoint, !endpoint.isEmpty {
                                            Text("push → \(endpoint)")
                                                .font(T3.mono(11))
                                                .foregroundStyle(T3.sky)
                                                .lineLimit(1)
                                        } else {
                                            Text("pull subscription")
                                                .font(T3.mono(11))
                                                .foregroundStyle(T3.textTertiary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }
}
