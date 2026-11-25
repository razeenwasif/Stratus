import SwiftUI
import Charts

struct MonitoringView: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredTime: Date?

    private let seriesPalette: [Color] = [T3.coral, T3.indigo, T3.sky, T3.mint, T3.amber]

    private var seriesNames: [String] {
        var seen: [String] = []
        for p in appState.monitoringPoints where !seen.contains(p.seriesName) {
            seen.append(p.seriesName)
        }
        return seen
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                summaryStrip
                chartSection
            }
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 40)
        }
        .background(T3.bg)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cloud Monitoring")
                    .font(T3.pageTitle())
                    .foregroundStyle(T3.textPrimary)
                Text("\(appState.selectedMetricKind.metricType) · \(appState.selectedProject?.projectId ?? "")")
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.textMuted)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach([1, 6, 24], id: \.self) { hr in
                    FilterPillButton(title: "\(hr)h", isSelected: appState.monitoringHours == hr) {
                        Task { await appState.refreshMonitoring(hours: hr) }
                    }
                }
            }

            ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise", isLoading: appState.isLoadingMonitoring) {
                Task { await appState.refreshMonitoring() }
            }
        }
    }

    private var summaryStrip: some View {
        let values = appState.monitoringPoints.map(\.value)
        let peak = values.max() ?? 0
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let unit = appState.selectedMetricKind.unitSuffix

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(MonitoringMetricKind.allCases) { kind in
                    FilterPillButton(title: kind.title, isSelected: appState.selectedMetricKind == kind) {
                        Task { await appState.refreshMonitoring(metric: kind) }
                    }
                }
            }

            HStack(spacing: 28) {
                MetricStatColumn(label: "Peak", value: String(format: "%.1f %@", peak, unit))
                MetricStatColumn(label: "Average", value: String(format: "%.1f %@", avg, unit))
                MetricStatColumn(label: "Active Series", value: "\(seriesNames.count)")
                MetricStatColumn(label: "Window", value: "\(appState.monitoringHours) hours")
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if appState.isLoadingMonitoring && appState.monitoringPoints.isEmpty {
            ProgressView("Querying Cloud Monitoring time series...")
                .frame(maxWidth: .infinity, minHeight: 300)
        } else if let err = appState.monitoringError, appState.monitoringPoints.isEmpty {
            EmptyStateView(icon: "waveform.path.ecg", title: "Cloud Monitoring unavailable", message: err, actionTitle: "Retry") {
                Task { await appState.refreshMonitoring() }
            }
        } else if appState.monitoringPoints.isEmpty {
            EmptyStateView(icon: "chart.line.uptrend.xyaxis", title: "No metric points", message: "No time-series data recorded in the selected window.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(appState.selectedMetricKind.title)
                        .font(T3.sectionTitle())
                        .foregroundStyle(T3.textPrimary)

                    if let hoveredTime {
                        Text(hoveredSummary(at: hoveredTime))
                            .font(T3.mono(11))
                            .foregroundStyle(T3.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(T3.surfacePill, in: RoundedRectangle(cornerRadius: 5))
                    }

                    Spacer()

                    HStack(spacing: 14) {
                        ForEach(Array(seriesNames.enumerated()), id: \.element) { idx, name in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(seriesPalette[idx % seriesPalette.count])
                                    .frame(width: 6, height: 6)
                                Text(name)
                                    .font(T3.mono(11))
                                    .foregroundStyle(T3.textSecondary)
                            }
                        }
                    }
                }

                Chart {
                    ForEach(Array(seriesNames.enumerated()), id: \.element) { idx, name in
                        let color = seriesPalette[idx % seriesPalette.count]
                        let pts = appState.monitoringPoints.filter { $0.seriesName == name }

                        ForEach(pts) { pt in
                            AreaMark(
                                x: .value("Time", pt.timestamp),
                                y: .value("Value", pt.value),
                                series: .value("Series", name)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [color.opacity(0.26), color.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Time", pt.timestamp),
                                y: .value("Value", pt.value),
                                series: .value("Series", name)
                            )
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(color)
                        }
                    }

                    if let hoveredTime {
                        RuleMark(x: .value("Hover", hoveredTime))
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
                                Text(String(format: "%.0f%@", d, appState.selectedMetricKind.isPercentage ? "%" : ""))
                                    .font(T3.mono(10.5))
                                    .foregroundStyle(T3.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(timeLabel(date))
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
                                case .active(let loc):
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let relX = loc.x - geo[plotFrame].origin.x
                                    if let date: Date = proxy.value(atX: relX) {
                                        hoveredTime = date
                                    }
                                case .ended:
                                    hoveredTime = nil
                                }
                            }
                    }
                }
                .frame(height: 310)
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    private func hoveredSummary(at date: Date) -> String {
        let nearest = appState.monitoringPoints.min {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }
        guard let nearest else { return timeLabel(date) }
        return "\(timeLabel(nearest.timestamp)) · \(nearest.seriesName): \(String(format: "%.1f", nearest.value)) \(appState.selectedMetricKind.unitSuffix)"
    }
}
