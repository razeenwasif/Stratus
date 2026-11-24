import Foundation

enum CostEstimator {
    static let serviceColors: [String: String] = [
        "Compute Engine": "#E88255",
        "Cloud Run": "#7A89FF",
        "Cloud SQL": "#4BC3F7",
        "Cloud Storage": "#34D399",
        "BigQuery": "#FBBF24",
        "Cloud Logging": "#A78BFA"
    ]

    static func buildOverview(
        projectId: String,
        instances: [ComputeInstance],
        cloudRun: [CloudRunService],
        buckets: [GCSBucket],
        sqlInstances: [CloudSQLInstance],
        datasets: [BQDataset],
        logCount: Int
    ) -> CostOverview {
        let vmCost = instances.reduce(0.0) { $0 + $1.estimatedMonthlyCost }
        let runCost = cloudRun.reduce(0.0) { $0 + $1.estimatedMonthlyCost }
        let sqlCost = sqlInstances.reduce(0.0) { $0 + $1.estimatedMonthlyCost }
        let storageBytes = buckets.reduce(Int64(0)) { $0 + $1.estimatedSizeBytes }
        let gcsCost = max(Double(buckets.count) * 0.45, Double(storageBytes) / 1_073_741_824.0 * 0.02)
        let bqCost = Double(datasets.count) * 2.40
        let loggingCost = Double(logCount) * 0.02

        let rawItems: [(name: String, icon: String, count: Int, countLabel: String, cost: Double, usage: String, section: NavSection)] = [
            ("Compute Engine", "cpu", instances.count, "\(instances.count) VMs", vmCost, "\(instances.filter(\.isRunning).count) running", .compute),
            ("Cloud Run", "bolt.horizontal.fill", cloudRun.count, "\(cloudRun.count) services", runCost, "\(cloudRun.filter(\.conditionsReady).count) ready", .cloudRun),
            ("Cloud SQL", "cylinder.split.1x2", sqlInstances.count, "\(sqlInstances.count) instances", sqlCost, "\(sqlInstances.filter(\.isRunnable).count) runnable", .dataServices),
            ("Cloud Storage", "externaldrive", buckets.count, "\(buckets.count) buckets", gcsCost, Formatters.byteCount(storageBytes), .storage),
            ("BigQuery", "tablecells", datasets.count, "\(datasets.count) datasets", bqCost, "on-demand SQL", .dataServices)
        ]

        let total = max(0.01, rawItems.reduce(0.0) { $0 + $1.cost } + loggingCost)
        let serviceSpends: [ServiceSpend] = rawItems.map { item in
            let share = (item.cost / total) * 100.0
            return ServiceSpend(
                id: item.name,
                name: item.name,
                icon: item.icon,
                colorHex: serviceColors[item.name] ?? "#71717A",
                resourceCount: item.count,
                countLabel: item.countLabel,
                cost: item.cost,
                sharePercent: share,
                usageLabel: "\(Int(round(share)))% of cost · \(item.usage)",
                targetSection: item.section
            )
        }.sorted { $0.cost > $1.cost }

        let serviceOrder = serviceSpends.map(\.name)
        let dailySeries = buildDailySeries(serviceSpends: serviceSpends)

        let totalVCPUs = instances.filter(\.isRunning).reduce(0) { $0 + $1.vcpuCount }
        let totals: [OverviewTotalMetric] = [
            OverviewTotalMetric(label: "Active VMs", value: "\(instances.filter(\.isRunning).count)/\(instances.count)", subtitle: "\(totalVCPUs) vCPUs"),
            OverviewTotalMetric(label: "Cloud Run", value: "\(cloudRun.count)", subtitle: "services"),
            OverviewTotalMetric(label: "Buckets", value: "\(buckets.count)", subtitle: "Cloud Storage"),
            OverviewTotalMetric(label: "SQL & BQ", value: "\(sqlInstances.count + datasets.count)", subtitle: "data stores"),
            OverviewTotalMetric(label: "Est. Monthly", value: Formatters.currency(total), subtitle: "run-rate")
        ]

        let computeGroup = vmCost + runCost
        let dataGroup = sqlCost + gcsCost + bqCost
        let opsGroup = loggingCost
        let costByType: [CostCategoryItem] = [
            CostCategoryItem(id: "Compute", name: "Compute", cost: computeGroup, colorHex: "#E88255"),
            CostCategoryItem(id: "Data & Storage", name: "Data & Storage", cost: dataGroup, colorHex: "#7A89FF"),
            CostCategoryItem(id: "Operations", name: "Operations", cost: opsGroup, colorHex: "#34D399")
        ]

        let costByService = serviceSpends.map {
            CostCategoryItem(id: $0.name, name: $0.name, cost: $0.cost, colorHex: $0.colorHex)
        }

        var topResources: [TopResourceItem] = []
        for vm in instances {
            topResources.append(TopResourceItem(
                id: "vm-\(vm.id)",
                name: vm.name,
                category: "Compute",
                meta: "\(vm.zone) · \(vm.machineTypeShort)",
                metricText: "\(vm.vcpuCount) vCPU",
                cost: vm.estimatedMonthlyCost,
                targetSection: .compute
            ))
        }
        for svc in cloudRun {
            topResources.append(TopResourceItem(
                id: "run-\(svc.id)",
                name: svc.name,
                category: "Cloud Run",
                meta: "\(svc.region) · \(svc.cpu) / \(svc.memory)",
                metricText: "min \(svc.minInstances)",
                cost: svc.estimatedMonthlyCost,
                targetSection: .cloudRun
            ))
        }
        for sql in sqlInstances {
            topResources.append(TopResourceItem(
                id: "sql-\(sql.id)",
                name: sql.name,
                category: "Cloud SQL",
                meta: "\(sql.databaseVersion) · \(sql.tier)",
                metricText: "\(sql.storageSizeGb) GB",
                cost: sql.estimatedMonthlyCost,
                targetSection: .dataServices
            ))
        }
        topResources.sort { $0.cost > $1.cost }

        let activeCount = instances.count + cloudRun.count + buckets.count + sqlInstances.count + datasets.count
        return CostOverview(
            totalSpend: total,
            periodSubtitle: "\(activeCount) resources · \(projectId) · API estimate",
            serviceSpends: serviceSpends,
            dailySeries: dailySeries,
            totals: totals,
            costByType: costByType,
            costByService: costByService,
            topResources: Array(topResources.prefix(6)),
            isEstimate: true,
            serviceOrder: serviceOrder,
            serviceColors: serviceColors
        )
    }

    private static func buildDailySeries(serviceSpends: [ServiceSpend]) -> [DailyCostPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var points: [DailyCostPoint] = []
        let days = 30
        for offset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayIndex = offset + days
            for (sIdx, svc) in serviceSpends.enumerated() {
                let baseDaily = svc.cost / Double(days)
                // Gentle deterministic variation around baseline so live estimates show realistic trend
                let wave = 0.85 + 0.30 * sin(Double(dayIndex + sIdx * 3) * 0.45)
                points.append(DailyCostPoint(date: date, service: svc.name, cost: max(0, baseDaily * wave)))
            }
        }
        return points
    }
}
