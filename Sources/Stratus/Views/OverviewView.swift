import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredDate: Date?
    @State private var hoveredServiceId: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 36) {
                if let overview = appState.costOverview {
                    topHeroGrid(overview)
                    totalsSection(overview)
                    segmentedBarsSection(overview)
                    topResourcesSection(overview)
                } else if appState.isLoadingOverview {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Loading project telemetry...")
                            .font(.system(size: 13))
                            .foregroundStyle(T3.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 420)
                } else if let err = appState.overviewError {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Unable to load project overview",
                        message: err,
                        actionTitle: "Retry"
                    ) {
                        Task { await appState.refreshOverview() }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 44)
        }
        .background(T3.bg)
    }

    // MARK: - Top Row: Hero Spend + Service List (Left) & Daily Cost Spline Chart (Right)

    private func topHeroGrid(_ overview: CostOverview) -> some View {
        HStack(alignment: .top, spacing: 40) {
            // Left Column (~34%)
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Formatters.currency(overview.totalSpend))
                            .font(T3.heroKPI())
                            .foregroundStyle(T3.textPrimary)

                        if appState.isLoadingOverview {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        }
                    }

                    Text(overview.periodSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(T3.textMuted)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(overview.serviceSpends) { svc in
                        serviceRow(svc)
                    }
                }
            }
            .frame(width: 310, alignment: .leading)

            // Right Column (~66%): Daily Cost Chart
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        Text("Daily cost")
                            .font(T3.sectionTitle())
                            .foregroundStyle(T3.textPrimary)

                        if let hoveredDate {
                            Text(hoveredTooltipText(date: hoveredDate, overview: overview))
                                .font(T3.mono(11))
                                .foregroundStyle(T3.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(T3.surfacePill, in: RoundedRectangle(cornerRadius: 5))
                        }
                    }

                    Spacer()

                    // Inline T3 dot legend
                    HStack(spacing: 14) {
                        ForEach(overview.serviceSpends.prefix(4)) { svc in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hexString: svc.colorHex))
                                    .frame(width: 6, height: 6)
                                Text(svc.name.replacingOccurrences(of: "Cloud ", with: "").replacingOccurrences(of: " Engine", with: ""))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(T3.textSecondary)
                            }
                        }

                        Button {
                            Task { await appState.refreshOverview() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(T3.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh overview (⌘R)")
                    }
                }

                dailyCostChart(overview)
                    .frame(height: 255)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func serviceRow(_ svc: ServiceSpend) -> some View {
        let isHovered = hoveredServiceId == svc.id
        let accent = Color(hexString: svc.colorHex)

        return Button {
            appState.navigate(to: svc.targetSection)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)

                    Image(systemName: svc.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(width: 15)

                    Text(svc.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)

                    Text(svc.countLabel)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(T3.textMuted)

                    Spacer()

                    Text(Formatters.currencyPrecise(svc.cost))
                        .font(T3.mono(13, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }

                Text(svc.usageLabel)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(T3.textTertiary)
                    .padding(.leading, 30)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isHovered ? T3.surfaceHover : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredServiceId = $0 ? svc.id : nil }
    }

    private func dailyCostChart(_ overview: CostOverview) -> some View {
        Chart {
            ForEach(overview.serviceOrder, id: \.self) { serviceName in
                let points = overview.dailySeries.filter { $0.service == serviceName }
                let color = Color(hexString: overview.serviceColors[serviceName] ?? "#7A89FF")

                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Cost", point.cost),
                        series: .value("Service", serviceName)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Cost", point.cost),
                        series: .value("Service", serviceName)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
                }
            }

            if let hoveredDate {
                RuleMark(x: .value("Selected", hoveredDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
        }
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(Formatters.currency(d))
                            .font(T3.mono(10.5))
                            .foregroundStyle(T3.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 9)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Formatters.shortDate(date))
                            .font(T3.mono(10.5))
                            .foregroundStyle(T3.textTertiary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let origin = geo[plotFrame].origin
                            let relX = location.x - origin.x
                            if let date: Date = proxy.value(atX: relX) {
                                hoveredDate = Calendar.current.startOfDay(for: date)
                            }
                        case .ended:
                            hoveredDate = nil
                        }
                    }
            }
        }
    }

    private func hoveredTooltipText(date: Date, overview: CostOverview) -> String {
        let cal = Calendar.current
        let matching = overview.dailySeries.filter { cal.isDate($0.date, inSameDayAs: date) }
        let sum = matching.reduce(0.0) { $0 + $1.cost }
        return "\(Formatters.shortDate(date)) · \(Formatters.currencyPrecise(sum))"
    }

    // MARK: - Middle Row: Totals

    private func totalsSection(_ overview: CostOverview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Totals")
                .font(T3.sectionTitle())
                .foregroundStyle(T3.textPrimary)

            HStack(alignment: .top, spacing: 24) {
                ForEach(overview.totals) { metric in
                    MetricStatColumn(label: metric.label, value: metric.value, subtitle: metric.subtitle)
                }
            }
        }
    }

    // MARK: - Lower-Middle Row: Segmented Bars

    private func segmentedBarsSection(_ overview: CostOverview) -> some View {
        HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cost by category")
                    .font(T3.sectionTitle())
                    .foregroundStyle(T3.textPrimary)

                SegmentedBar(
                    segments: overview.costByType.map {
                        BarSegment(
                            id: $0.id,
                            label: $0.name,
                            value: $0.cost,
                            formattedValue: Formatters.currencyPrecise($0.cost),
                            colorHex: $0.colorHex
                        )
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("Cost by service")
                    .font(T3.sectionTitle())
                    .foregroundStyle(T3.textPrimary)

                SegmentedBar(
                    segments: overview.costByService.map {
                        BarSegment(
                            id: $0.id,
                            label: $0.name,
                            value: $0.cost,
                            formattedValue: Formatters.currencyPrecise($0.cost),
                            colorHex: $0.colorHex
                        )
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Bottom Row: Top Resources (2-column borderless grid)

    private func topResourcesSection(_ overview: CostOverview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Top resources")
                    .font(T3.sectionTitle())
                    .foregroundStyle(T3.textPrimary)
                Spacer()
                Text("Highest usage in range")
                    .font(.system(size: 11.5))
                    .foregroundStyle(T3.textTertiary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 36),
                    GridItem(.flexible(), spacing: 36)
                ],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(overview.topResources) { item in
                    TopResourceRowView(item: item) {
                        appState.navigate(to: item.targetSection)
                    }
                }
            }
        }
    }
}

private struct TopResourceRowView: View {
    let item: TopResourceItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        TagPill(text: item.category)
                        Text(item.meta)
                            .font(.system(size: 11.5))
                            .foregroundStyle(T3.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Text(item.metricText)
                        .font(T3.mono(12))
                        .foregroundStyle(T3.textSecondary)
                    Text(Formatters.currencyPrecise(item.cost))
                        .font(T3.mono(13, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isHovered ? T3.surfaceHover : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
