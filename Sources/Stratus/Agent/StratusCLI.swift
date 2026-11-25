import Foundation

/// Headless CLI interface (`stratus ...`) for shell scripts, `agy`, and `fairy` agents.
@MainActor
enum StratusCLI {
    static let version = "1.1.0"

    static func run(arguments: [String]) async -> Int32 {
        var args = arguments
        let demo = extractFlag("--demo", from: &args)
        _ = extractFlag("--json", from: &args)
        let projectId = extractOption("--project", from: &args) ?? extractOption("-p", from: &args)

        if args.isEmpty || args.first == "--help" || args.first == "-h" || args.first == "help" {
            printUsage()
            return 0
        }
        if args.first == "--version" || args.first == "-v" {
            print("stratus \(version)")
            return 0
        }

        let bridge = AgentBridge()
        let cmd = args[0]
        let rest = Array(args.dropFirst())

        do {
            let output: AnyCodableValue
            switch cmd {
            case "status":
                output = await bridge.status(demo: demo)
            case "projects":
                output = try await bridge.listProjects(demo: demo)
            case "overview":
                output = try await bridge.overview(projectId: projectId, demo: demo)
            case "vm":
                let sub = rest.first ?? "list"
                if sub == "list" {
                    output = try await bridge.listVMs(projectId: projectId, demo: demo)
                } else if ["start", "stop", "reset"].contains(sub) {
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("vm \(sub) <instance> --zone <zone>") }
                    var subRest = Array(rest.dropFirst(2))
                    let zone = extractOption("--zone", from: &subRest) ?? ""
                    guard !zone.isEmpty else { throw AgentBridgeError.missingArgument("--zone <zone>") }
                    output = try await bridge.vmAction(projectId: projectId, zone: zone, instance: rest[1], action: sub, demo: demo)
                } else {
                    throw AgentBridgeError.invalidArgument("Unknown vm subcommand: \(sub)")
                }
            case "run":
                output = try await bridge.listCloudRun(projectId: projectId, demo: demo)
            case "storage":
                let sub = rest.first ?? "buckets"
                switch sub {
                case "buckets":
                    output = try await bridge.listBuckets(projectId: projectId, demo: demo)
                case "ls":
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("storage ls <bucket> [prefix]") }
                    let prefix = rest.count >= 3 ? rest[2] : ""
                    output = try await bridge.listObjects(bucket: rest[1], prefix: prefix, demo: demo)
                case "cat":
                    guard rest.count >= 3 else { throw AgentBridgeError.missingArgument("storage cat <bucket> <object>") }
                    output = try await bridge.readObject(bucket: rest[1], objectName: rest[2], demo: demo)
                default:
                    throw AgentBridgeError.invalidArgument("Unknown storage subcommand: \(sub)")
                }
            case "logs":
                var logArgs = rest
                let filter = extractOption("--filter", from: &logArgs) ?? ""
                let limit = extractOption("--limit", from: &logArgs).flatMap(Int.init) ?? 50
                output = try await bridge.queryLogs(projectId: projectId, filter: filter, pageSize: limit, demo: demo)
            case "iam":
                output = try await bridge.listIAM(projectId: projectId, demo: demo)
            case "apis":
                let sub = rest.first ?? "list"
                switch sub {
                case "list":
                    output = try await bridge.listAPIs(projectId: projectId, demo: demo)
                case "enable", "disable":
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("apis \(sub) <service.googleapis.com>") }
                    output = try await bridge.toggleAPI(projectId: projectId, serviceName: rest[1], enable: sub == "enable", demo: demo)
                default:
                    throw AgentBridgeError.invalidArgument("Unknown apis subcommand: \(sub)")
                }
            case "bq":
                let sub = rest.first ?? "datasets"
                switch sub {
                case "datasets":
                    output = try await bridge.bigquery(projectId: projectId, demo: demo)
                case "tables":
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("bq tables <datasetId>") }
                    output = try await bridge.bigquery(projectId: projectId, datasetId: rest[1], demo: demo)
                case "query":
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("bq query \"<SQL>\"") }
                    output = try await bridge.bigquery(projectId: projectId, sql: rest.dropFirst().joined(separator: " "), demo: demo)
                default:
                    throw AgentBridgeError.invalidArgument("Unknown bq subcommand: \(sub)")
                }
            case "sql":
                let sub = rest.first ?? "list"
                if sub == "list" {
                    output = try await bridge.cloudSQL(projectId: projectId, demo: demo)
                } else if sub == "restart" {
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("sql restart <instance>") }
                    output = try await bridge.cloudSQL(projectId: projectId, restartInstance: rest[1], demo: demo)
                } else {
                    throw AgentBridgeError.invalidArgument("Unknown sql subcommand: \(sub)")
                }
            case "secrets":
                let sub = rest.first ?? "list"
                switch sub {
                case "list":
                    output = try await bridge.secrets(projectId: projectId, demo: demo)
                case "versions":
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("secrets versions <secretName>") }
                    output = try await bridge.secrets(projectId: projectId, secretName: rest[1], demo: demo)
                case "reveal":
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("secrets reveal <secretName> [version]") }
                    let ver = rest.count >= 3 ? rest[2] : "latest"
                    output = try await bridge.secrets(projectId: projectId, secretName: rest[1], revealVersion: ver, demo: demo)
                default:
                    throw AgentBridgeError.invalidArgument("Unknown secrets subcommand: \(sub)")
                }
            case "gke":
                output = try await bridge.listGKE(projectId: projectId, demo: demo)
            case "functions":
                output = try await bridge.listFunctions(projectId: projectId, demo: demo)
            case "network":
                output = try await bridge.listNetwork(projectId: projectId, demo: demo)
            case "artifacts":
                output = try await bridge.listArtifacts(projectId: projectId, repoFullName: rest.first, demo: demo)
            case "builds":
                output = try await bridge.listBuilds(projectId: projectId, demo: demo)
            case "scheduler":
                if rest.first == "run" {
                    guard rest.count >= 2 else { throw AgentBridgeError.missingArgument("scheduler run <jobFullName>") }
                    output = try await bridge.scheduler(projectId: projectId, runJobFullName: rest[1], demo: demo)
                } else {
                    output = try await bridge.scheduler(projectId: projectId, demo: demo)
                }
            case "pubsub":
                if rest.first == "publish" {
                    guard rest.count >= 3 else { throw AgentBridgeError.missingArgument("pubsub publish <topic> <message>") }
                    output = try await bridge.pubsub(projectId: projectId, publishTopic: rest[1], message: rest.dropFirst(2).joined(separator: " "), demo: demo)
                } else {
                    output = try await bridge.pubsub(projectId: projectId, demo: demo)
                }
            case "db":
                output = try await bridge.databases(projectId: projectId, kind: rest.first ?? "all", demo: demo)
            case "metrics":
                var mArgs = rest
                let hours = extractOption("--hours", from: &mArgs).flatMap(Int.init) ?? 24
                let kind = mArgs.first ?? "computeCPU"
                output = try await bridge.monitoring(projectId: projectId, metricRaw: kind, hours: hours, demo: demo)
            case "open":
                let section = rest.first
                output = try await bridge.openUI(section: section, projectId: projectId)
            default:
                fputs("Unknown command '\(cmd)'. Run `stratus --help` for usage.\n", stderr)
                return 2
            }

            print(output.prettyPrintedJSON)
            return 0
        } catch {
            let errObj = AnyCodableValue.object(["error": .string(error.localizedDescription)])
            fputs(errObj.prettyPrintedJSON + "\n", stderr)
            return 1
        }
    }

    private static func extractFlag(_ flag: String, from args: inout [String]) -> Bool {
        if let idx = args.firstIndex(of: flag) {
            args.remove(at: idx)
            return true
        }
        return false
    }

    private static func extractOption(_ option: String, from args: inout [String]) -> String? {
        if let idx = args.firstIndex(of: option), idx + 1 < args.count {
            let val = args[idx + 1]
            args.remove(at: idx + 1)
            args.remove(at: idx)
            return val
        }
        return nil
    }

    private static func printUsage() {
        print("""
        Stratus \(version) — Google Cloud Desktop & Agent CLI

        Usage:
          stratus                         Launch the Stratus desktop app
          stratus --mcp                   Start JSON-RPC 2.0 MCP stdio server (agy / fairy)
          stratus <command> [options]     Run a headless GCP command returning JSON

        Commands:
          status                          Show auth mode, active account & default project
          projects                        List accessible GCP projects
          overview                        Show cost & resource summary
          vm list                         List Compute Engine VMs
          vm start|stop|reset <name> --zone <zone>
          run list                        List Cloud Run v2 services
          storage buckets                 List Cloud Storage buckets
          storage ls <bucket> [prefix]    List objects/folders in a bucket
          storage cat <bucket> <object>   Read text/JSON object content
          logs [--filter "..."] [--limit N]
          iam                             List project IAM policy bindings
          apis list                       List enabled APIs
          apis enable|disable <service>   Toggle a GCP API
          bq datasets                     List BigQuery datasets
          bq tables <datasetId>           List BigQuery tables
          bq query "<SQL>"                Execute BigQuery Standard SQL
          sql list                        List Cloud SQL instances
          sql restart <instance>          Restart a Cloud SQL instance
          secrets list                    List Secret Manager secrets
          secrets versions <name>         List versions for a secret
          secrets reveal <name> [ver]     Reveal secret payload
          open [section]                  Open Stratus UI (overview|compute|cloudRun|storage|dataServices|logging|iamAndApis)

        Global Options:
          -p, --project <id>              Target GCP project ID
          --demo                          Use offline Demo Mode data
          --json                          Emit JSON output (default)
          -v, --version                   Print version
          -h, --help                      Show this help
        """)
    }
}
