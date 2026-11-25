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
            case "firebase":
                output = try await runFirebaseCLI(rest: rest, projectId: projectId, bridge: bridge, demo: demo)
            case "firestore":
                output = try await runFirestoreCLI(rest: rest, projectId: projectId, bridge: bridge, demo: demo)
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
          firebase project|apps|app-config <appId>
          firebase auth list|create|disable|enable|delete ...
          firebase hosting sites|releases|channels [siteId]
          firebase rules list|get [rulesetName]
          firebase remote-config get|versions|publish <json>
          firebase rtdb instances|get|set|delete [path] [json]
          firestore databases|collections|indexes [parentDocPath]
          firestore list <col> | get <doc> | delete <doc>
          firestore create <col> <json> [--id <docId>] | update <doc> <json>
          firestore query <col> [--field F] [--op OP] [--value V] [--limit N]
          open [section]                  Open Stratus UI (overview|compute|cloudRun|storage|dataServices|firebase|logging|iamAndApis)

        Global Options:
          -p, --project <id>              Target GCP project ID
          --demo                          Use offline Demo Mode data
          --json                          Emit JSON output (default)
          -v, --version                   Print version
          -h, --help                      Show this help
        """)
    }

    private static func runFirebaseCLI(
        rest: [String],
        projectId: String?,
        bridge: AgentBridge,
        demo: Bool
    ) async throws -> AnyCodableValue {
        let sub = rest.first ?? "apps"
        let tail = Array(rest.dropFirst())
        switch sub {
        case "project":
            return try await bridge.firebase(projectId: projectId, action: "project", demo: demo)
        case "apps":
            return try await bridge.firebase(projectId: projectId, action: "apps", demo: demo)
        case "app-config":
            guard let appId = tail.first else { throw AgentBridgeError.missingArgument("firebase app-config <appId>") }
            return try await bridge.firebase(projectId: projectId, action: "app_config", appId: appId, demo: demo)
        case "auth":
            let op = tail.first ?? "list"
            switch op {
            case "list":
                return try await bridge.firebase(projectId: projectId, action: "auth_list", demo: demo)
            case "create":
                guard tail.count >= 3 else { throw AgentBridgeError.missingArgument("firebase auth create <email> <password> [displayName]") }
                let display = tail.count >= 4 ? tail[3] : nil
                return try await bridge.firebase(projectId: projectId, action: "auth_create", email: tail[1], password: tail[2], displayName: display, demo: demo)
            case "disable":
                guard tail.count >= 2 else { throw AgentBridgeError.missingArgument("firebase auth disable <localId>") }
                return try await bridge.firebase(projectId: projectId, action: "auth_disable", localId: tail[1], demo: demo)
            case "enable":
                guard tail.count >= 2 else { throw AgentBridgeError.missingArgument("firebase auth enable <localId>") }
                return try await bridge.firebase(projectId: projectId, action: "auth_enable", localId: tail[1], demo: demo)
            case "delete":
                guard tail.count >= 2 else { throw AgentBridgeError.missingArgument("firebase auth delete <localId>") }
                return try await bridge.firebase(projectId: projectId, action: "auth_delete", localId: tail[1], demo: demo)
            default:
                throw AgentBridgeError.invalidArgument("Unknown firebase auth subcommand: \(op)")
            }
        case "hosting":
            let op = tail.first ?? "sites"
            let siteId = tail.count >= 2 ? tail[1] : nil
            switch op {
            case "sites": return try await bridge.firebase(projectId: projectId, action: "hosting_sites", demo: demo)
            case "releases": return try await bridge.firebase(projectId: projectId, action: "hosting_releases", siteId: siteId, demo: demo)
            case "channels": return try await bridge.firebase(projectId: projectId, action: "hosting_channels", siteId: siteId, demo: demo)
            default: throw AgentBridgeError.invalidArgument("Unknown firebase hosting subcommand: \(op)")
            }
        case "rules":
            let op = tail.first ?? "list"
            if op == "list" {
                return try await bridge.firebase(projectId: projectId, action: "rules_list", demo: demo)
            } else if op == "get" {
                return try await bridge.firebase(projectId: projectId, action: "rules_get", rulesetName: tail.count >= 2 ? tail[1] : nil, demo: demo)
            } else {
                throw AgentBridgeError.invalidArgument("Unknown firebase rules subcommand: \(op)")
            }
        case "remote-config":
            let op = tail.first ?? "get"
            switch op {
            case "get": return try await bridge.firebase(projectId: projectId, action: "remote_config_get", demo: demo)
            case "versions": return try await bridge.firebase(projectId: projectId, action: "remote_config_versions", demo: demo)
            case "publish":
                guard tail.count >= 2 else { throw AgentBridgeError.missingArgument("firebase remote-config publish '<json>'") }
                return try await bridge.firebase(projectId: projectId, action: "remote_config_publish", rawJSON: tail[1], demo: demo)
            default: throw AgentBridgeError.invalidArgument("Unknown remote-config subcommand: \(op)")
            }
        case "rtdb":
            var rtdbArgs = tail
            let shallow = extractFlag("--shallow", from: &rtdbArgs)
            let dbUrl = extractOption("--url", from: &rtdbArgs)
            let op = rtdbArgs.first ?? "instances"
            switch op {
            case "instances":
                return try await bridge.firebase(projectId: projectId, action: "rtdb_instances", demo: demo)
            case "get":
                let p = rtdbArgs.count >= 2 ? rtdbArgs[1] : "/"
                return try await bridge.firebase(projectId: projectId, action: "rtdb_get", databaseUrl: dbUrl, path: p, shallow: shallow, demo: demo)
            case "set":
                guard rtdbArgs.count >= 3 else { throw AgentBridgeError.missingArgument("firebase rtdb set <path> '<json>'") }
                return try await bridge.firebase(projectId: projectId, action: "rtdb_set", rawJSON: rtdbArgs[2], databaseUrl: dbUrl, path: rtdbArgs[1], demo: demo)
            case "delete":
                guard rtdbArgs.count >= 2 else { throw AgentBridgeError.missingArgument("firebase rtdb delete <path>") }
                return try await bridge.firebase(projectId: projectId, action: "rtdb_delete", databaseUrl: dbUrl, path: rtdbArgs[1], demo: demo)
            default:
                throw AgentBridgeError.invalidArgument("Unknown rtdb subcommand: \(op)")
            }
        default:
            throw AgentBridgeError.invalidArgument("Unknown firebase subcommand: \(sub)")
        }
    }

    private static func runFirestoreCLI(
        rest: [String],
        projectId: String?,
        bridge: AgentBridge,
        demo: Bool
    ) async throws -> AnyCodableValue {
        var args = rest
        let dbId = extractOption("--db", from: &args) ?? "(default)"
        let sub = args.first ?? "databases"
        var tail = Array(args.dropFirst())

        switch sub {
        case "databases":
            return try await bridge.firestore(projectId: projectId, databaseId: dbId, action: "databases", demo: demo)
        case "collections":
            return try await bridge.firestore(projectId: projectId, databaseId: dbId, action: "collections", documentPath: tail.first, demo: demo)
        case "list":
            guard let col = tail.first else { throw AgentBridgeError.missingArgument("firestore list <collectionPath>") }
            let limit = extractOption("--limit", from: &tail).flatMap(Int.init) ?? 50
            return try await bridge.firestore(projectId: projectId, databaseId: dbId, action: "list", collectionPath: col, limit: limit, demo: demo)
        case "get":
            guard let doc = tail.first else { throw AgentBridgeError.missingArgument("firestore get <documentPath>") }
            return try await bridge.firestore(projectId: projectId, databaseId: dbId, action: "get", documentPath: doc, demo: demo)
        case "create":
            let docId = extractOption("--id", from: &tail)
            guard tail.count >= 2 else { throw AgentBridgeError.missingArgument("firestore create <collectionPath> '<fieldsJSON>' [--id <docId>]") }
            return try await bridge.firestore(projectId: projectId, databaseId: dbId, action: "create", collectionPath: tail[0], documentId: docId, fieldsJSON: tail[1], demo: demo)
        case "update":
            guard tail.count >= 2 else { throw AgentBridgeError.missingArgument("firestore update <documentPath> '<fieldsJSON>'") }
            return try await bridge.firestore(projectId: projectId, databaseId: dbId, action: "update", documentPath: tail[0], fieldsJSON: tail[1], demo: demo)
        case "delete":
            guard let doc = tail.first else { throw AgentBridgeError.missingArgument("firestore delete <documentPath>") }
            return try await bridge.firestore(projectId: projectId, databaseId: dbId, action: "delete", documentPath: doc, demo: demo)
        case "query":
            let field = extractOption("--field", from: &tail)
            let op = extractOption("--op", from: &tail)
            let value = extractOption("--value", from: &tail)
            let orderBy = extractOption("--order-by", from: &tail)
            let desc = extractFlag("--desc", from: &tail)
            let limit = extractOption("--limit", from: &tail).flatMap(Int.init) ?? 50
            guard let col = tail.first else { throw AgentBridgeError.missingArgument("firestore query <collectionPath>") }
            return try await bridge.firestore(
                projectId: projectId,
                databaseId: dbId,
                action: "query",
                collectionPath: col,
                filterField: field,
                filterOp: op,
                filterValue: value,
                orderBy: orderBy,
                descending: desc,
                limit: limit,
                demo: demo
            )
        case "indexes":
            return try await bridge.firestore(projectId: projectId, databaseId: dbId, action: "indexes", demo: demo)
        default:
            throw AgentBridgeError.invalidArgument("Unknown firestore subcommand: \(sub)")
        }
    }
}
