import SwiftUI

struct LoggingView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedFilter: SeverityFilter = .all
    @State private var expandedLogId: String?

    enum SeverityFilter: String, CaseIterable {
        case all = "All"
        case errorPlus = "Error+"
        case warning = "Warning"
        case info = "Info"
        case debug = "Debug"
    }

    private var filteredLogs: [LogEntry] {
        appState.logEntries.filter { entry in
            let matchesSev: Bool
            switch selectedFilter {
            case .all: matchesSev = true
            case .errorPlus: matchesSev = entry.severity.isErrorOrHigher
            case .warning: matchesSev = entry.severity == .warning
            case .info: matchesSev = entry.severity == .info || entry.severity == .notice
            case .debug: matchesSev = entry.severity == .debug || entry.severity == .default
            }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesText = q.isEmpty
                || entry.message.lowercased().contains(q)
                || entry.resourceType.lowercased().contains(q)
                || entry.logName.lowercased().contains(q)
            return matchesSev && matchesText
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cloud Logging")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(filteredLogs.count) entries · \(appState.selectedProject?.projectId ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(SeverityFilter.allCases, id: \.self) { filter in
                        FilterPillButton(title: filter.rawValue, isSelected: selectedFilter == filter) {
                            selectedFilter = filter
                        }
                    }
                }

                BorderlessSearchField(text: $searchText, placeholder: "Filter message or resource...", width: 230)

                ActionPillButton(title: "Query", systemImage: "arrow.clockwise", isLoading: appState.isLoadingLogs) {
                    let apiFilter = buildGCPFilter()
                    Task { await appState.refreshLogs(filter: apiFilter) }
                }
            }

            if appState.isLoadingLogs && appState.logEntries.isEmpty {
                ProgressView("Fetching log entries...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.loggingError, appState.logEntries.isEmpty {
                EmptyStateView(icon: "text.alignleft", title: "Cloud Logging unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshLogs(filter: buildGCPFilter()) }
                }
            } else if filteredLogs.isEmpty {
                EmptyStateView(icon: "text.magnifyingglass", title: "No log entries", message: "Adjust severity or search filters to view entries.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLogs) { entry in
                            logRow(entry)
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

    private func logRow(_ entry: LogEntry) -> some View {
        let isExpanded = expandedLogId == entry.id
        let sevColor = Color(hexString: entry.severity.colorHex)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Formatters.shortTime(entry.timestamp))
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.textTertiary)
                    .frame(width: 86, alignment: .leading)

                Text(entry.severity.shortLabel)
                    .font(T3.mono(10.5, weight: .bold))
                    .foregroundStyle(sevColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sevColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(width: 42)

                TagPill(text: entry.resourceType, monospaced: true)

                Text(entry.message)
                    .font(T3.mono(12))
                    .foregroundStyle(T3.textPrimary)
                    .lineLimit(isExpanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !entry.resourceLabels.isEmpty {
                        FlowWrapLayout(horizontalSpacing: 8, verticalSpacing: 4) {
                            ForEach(entry.resourceLabels.keys.sorted(), id: \.self) { key in
                                TagPill(text: "\(key)=\(entry.resourceLabels[key] ?? "")", monospaced: true)
                            }
                        }
                    }

                    if let jsonPayload = entry.jsonPayload {
                        Text(jsonPayload.prettyPrintedJSON)
                            .font(T3.mono(11.5))
                            .foregroundStyle(T3.textSecondary)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    HStack {
                        Spacer()
                        ActionPillButton(title: "Copy JSON", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                            let content = entry.jsonPayload?.prettyPrintedJSON ?? entry.message
                            appState.copyToClipboard(content, label: "log payload")
                        }
                    }
                }
                .padding(.leading, 138)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isExpanded ? T3.surfaceHover : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.14)) {
                expandedLogId = isExpanded ? nil : entry.id
            }
        }
    }

    private func buildGCPFilter() -> String {
        switch selectedFilter {
        case .all: return ""
        case .errorPlus: return "severity>=ERROR"
        case .warning: return "severity=WARNING"
        case .info: return "severity=INFO"
        case .debug: return "severity=DEBUG"
        }
    }
}
