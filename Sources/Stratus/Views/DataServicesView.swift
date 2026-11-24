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
    @State private var hoveredSecret: String?

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Data & Secrets")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(appState.selectedProject?.projectId ?? "") · BigQuery, Cloud SQL & Secret Manager")
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
            case .secretManager:
                secretManagerView
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

    // MARK: - Secret Manager

    private var secretManagerView: some View {
        Group {
            if appState.isLoadingSecrets && appState.secrets.isEmpty {
                ProgressView("Loading secrets...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.secretsError, appState.secrets.isEmpty {
                EmptyStateView(icon: "key.fill", title: "Secret Manager unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshSecrets() }
                }
            } else if appState.secrets.isEmpty {
                EmptyStateView(icon: "key", title: "No secrets stored", message: "Create secrets in Secret Manager to inspect versions and payloads.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.secrets) { secret in
                            let isHovered = hoveredSecret == secret.id
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
                            .onHover { hoveredSecret = $0 ? secret.id : nil }
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
