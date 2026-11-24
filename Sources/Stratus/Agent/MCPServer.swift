import Foundation

/// Pure Swift JSON-RPC 2.0 MCP stdio server (`stratus --mcp`) for Antigravity (`agy`) and Fairy.
/// Writes strictly single-line JSON-RPC responses to stdout and flushes immediately.
@MainActor
final class MCPServer {
    private let bridge: AgentBridge

    init(bridge: AgentBridge = AgentBridge()) {
        self.bridge = bridge
    }

    static func run() async -> Int32 {
        let server = MCPServer()
        while true {
            let line: String? = await Task.detached(priority: .userInitiated) {
                readLine(strippingNewline: true)
            }.value

            guard let line else { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if let reply = await server.handleMessage(trimmed) {
                if let data = (reply + "\n").data(using: .utf8) {
                    FileHandle.standardOutput.write(data)
                }
                fflush(stdout)
            }
        }
        return 0
    }

    func handleMessage(_ jsonLine: String) async -> String? {
        guard let data = jsonLine.data(using: .utf8),
              let req = try? JSONDecoder().decode(AnyCodableValue.self, from: data),
              case .object(let dict) = req else {
            return encodeResponse(id: nil, result: nil, error: (-32700, "Parse error"))
        }

        let id = dict["id"]
        guard case .string(let method) = dict["method"] else {
            return encodeResponse(id: id, result: nil, error: (-32600, "Invalid Request"))
        }

        // JSON-RPC notifications have no id and expect no reply
        if id == nil || id == .null {
            return nil
        }

        let params: [String: AnyCodableValue]
        if case .object(let p) = dict["params"] {
            params = p
        } else {
            params = [:]
        }

        switch method {
        case "initialize":
            let result: AnyCodableValue = .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(false)])
                ]),
                "serverInfo": .object([
                    "name": .string("stratus"),
                    "version": .string("1.1.0")
                ])
            ])
            return encodeResponse(id: id, result: result, error: nil)

        case "ping":
            return encodeResponse(id: id, result: .object([:]), error: nil)

        case "tools/list":
            return encodeResponse(id: id, result: .object(["tools": .array(Self.toolDefinitions)]), error: nil)

        case "tools/call":
            guard case .string(let toolName) = params["name"] else {
                return encodeResponse(id: id, result: nil, error: (-32602, "Missing tool name"))
            }
            let args: [String: AnyCodableValue]
            if case .object(let a) = params["arguments"] {
                args = a
            } else {
                args = [:]
            }
            let callResult = await executeTool(name: toolName, args: args)
            return encodeResponse(id: id, result: callResult, error: nil)

        default:
            return encodeResponse(id: id, result: nil, error: (-32601, "Method not found: \(method)"))
        }
    }

    private func executeTool(name: String, args: [String: AnyCodableValue]) async -> AnyCodableValue {
        let demo = boolArg("demo", in: args) ?? false
        let projectId = stringArg("projectId", in: args)

        do {
            let payload: AnyCodableValue
            switch name {
            case "stratus_status":
                payload = await bridge.status(demo: demo)
            case "stratus_list_projects":
                payload = try await bridge.listProjects(demo: demo)
            case "stratus_overview":
                payload = try await bridge.overview(projectId: projectId, demo: demo)
            case "stratus_list_vms":
                payload = try await bridge.listVMs(projectId: projectId, demo: demo)
            case "stratus_vm_action":
                payload = try await bridge.vmAction(
                    projectId: projectId,
                    zone: try reqString("zone", in: args),
                    instance: try reqString("instance", in: args),
                    action: try reqString("action", in: args),
                    demo: demo
                )
            case "stratus_list_cloud_run":
                payload = try await bridge.listCloudRun(projectId: projectId, demo: demo)
            case "stratus_list_buckets":
                payload = try await bridge.listBuckets(projectId: projectId, demo: demo)
            case "stratus_list_objects":
                payload = try await bridge.listObjects(
                    bucket: try reqString("bucket", in: args),
                    prefix: stringArg("prefix", in: args) ?? "",
                    demo: demo
                )
            case "stratus_read_object":
                payload = try await bridge.readObject(
                    bucket: try reqString("bucket", in: args),
                    objectName: try reqString("objectName", in: args),
                    demo: demo
                )
            case "stratus_query_logs":
                payload = try await bridge.queryLogs(
                    projectId: projectId,
                    filter: stringArg("filter", in: args) ?? "",
                    pageSize: intArg("pageSize", in: args) ?? 50,
                    demo: demo
                )
            case "stratus_list_iam":
                payload = try await bridge.listIAM(projectId: projectId, demo: demo)
            case "stratus_list_apis":
                payload = try await bridge.listAPIs(projectId: projectId, demo: demo)
            case "stratus_toggle_api":
                payload = try await bridge.toggleAPI(
                    projectId: projectId,
                    serviceName: try reqString("serviceName", in: args),
                    enable: boolArg("enable", in: args) ?? true,
                    demo: demo
                )
            case "stratus_bigquery":
                payload = try await bridge.bigquery(
                    projectId: projectId,
                    datasetId: stringArg("datasetId", in: args),
                    sql: stringArg("sql", in: args),
                    demo: demo
                )
            case "stratus_cloud_sql":
                payload = try await bridge.cloudSQL(
                    projectId: projectId,
                    restartInstance: stringArg("restartInstance", in: args),
                    demo: demo
                )
            case "stratus_secrets":
                payload = try await bridge.secrets(
                    projectId: projectId,
                    secretName: stringArg("secretName", in: args),
                    revealVersion: stringArg("revealVersion", in: args),
                    demo: demo
                )
            case "stratus_open_ui":
                payload = try await bridge.openUI(
                    section: stringArg("section", in: args),
                    projectId: projectId
                )
            default:
                return toolError("Unknown tool: \(name)")
            }

            return .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(payload.prettyPrintedJSON)
                    ])
                ]),
                "isError": .bool(false)
            ])
        } catch {
            return toolError(error.localizedDescription)
        }
    }

    private func toolError(_ message: String) -> AnyCodableValue {
        .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(message)
                ])
            ]),
            "isError": .bool(true)
        ])
    }

    private func stringArg(_ key: String, in dict: [String: AnyCodableValue]) -> String? {
        if case .string(let s) = dict[key] { return s }
        return nil
    }

    private func reqString(_ key: String, in dict: [String: AnyCodableValue]) throws -> String {
        guard let val = stringArg(key, in: dict), !val.isEmpty else {
            throw AgentBridgeError.missingArgument(key)
        }
        return val
    }

    private func boolArg(_ key: String, in dict: [String: AnyCodableValue]) -> Bool? {
        if case .bool(let b) = dict[key] { return b }
        return nil
    }

    private func intArg(_ key: String, in dict: [String: AnyCodableValue]) -> Int? {
        if case .int(let i) = dict[key] { return i }
        return nil
    }

    private func encodeResponse(id: AnyCodableValue?, result: AnyCodableValue?, error: (Int, String)?) -> String {
        var obj: [String: AnyCodableValue] = [
            "jsonrpc": .string("2.0"),
            "id": id ?? .null
        ]
        if let error {
            obj["error"] = .object([
                "code": .int(error.0),
                "message": .string(error.1)
            ])
        } else {
            obj["result"] = result ?? .object([:])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(AnyCodableValue.object(obj)),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Encoding error\"}}"
        }
        return str
    }

    // MARK: - Tool Schemas

    private static func schema(
        _ name: String,
        description: String,
        properties: [String: AnyCodableValue] = [:],
        required: [String] = []
    ) -> AnyCodableValue {
        var props = properties
        props["demo"] = .object([
            "type": .string("boolean"),
            "description": .string("Optional: force offline Demo Mode data")
        ])
        return .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(props),
                "required": .array(required.map(AnyCodableValue.string))
            ])
        ])
    }

    private static let projectIdProp: AnyCodableValue = .object([
        "type": .string("string"),
        "description": .string("GCP Project ID (defaults to active gcloud or first accessible project)")
    ])

    static let toolDefinitions: [AnyCodableValue] = [
        schema("stratus_status", description: "Check Stratus auth mode, active Google Cloud account, default project, and gcloud CLI path."),
        schema("stratus_list_projects", description: "List accessible Google Cloud projects."),
        schema("stratus_overview", description: "Get cost & resource overview across Compute Engine, Cloud Run, Cloud SQL, Cloud Storage, and BigQuery.", properties: ["projectId": projectIdProp]),
        schema("stratus_list_vms", description: "List Compute Engine VMs across all zones with status, IPs, disk size, and SSH command.", properties: ["projectId": projectIdProp]),
        schema(
            "stratus_vm_action",
            description: "Start, stop, or reset a Compute Engine VM instance.",
            properties: [
                "projectId": projectIdProp,
                "zone": .object(["type": .string("string"), "description": .string("GCE zone (e.g. us-central1-a)")]),
                "instance": .object(["type": .string("string"), "description": .string("VM instance name")]),
                "action": .object(["type": .string("string"), "enum": .array([.string("start"), .string("stop"), .string("reset")])])
            ],
            required: ["zone", "instance", "action"]
        ),
        schema("stratus_list_cloud_run", description: "List Cloud Run v2 services, URLs, readiness, CPU/memory, and active revisions.", properties: ["projectId": projectIdProp]),
        schema("stratus_list_buckets", description: "List Cloud Storage buckets in the project.", properties: ["projectId": projectIdProp]),
        schema(
            "stratus_list_objects",
            description: "List objects and folder prefixes inside a Cloud Storage bucket.",
            properties: [
                "bucket": .object(["type": .string("string"), "description": .string("GCS bucket name")]),
                "prefix": .object(["type": .string("string"), "description": .string("Optional folder prefix (e.g. configs/)")])
            ],
            required: ["bucket"]
        ),
        schema(
            "stratus_read_object",
            description: "Read text/JSON/YAML content of a Cloud Storage object (up to 256KB).",
            properties: [
                "bucket": .object(["type": .string("string")]),
                "objectName": .object(["type": .string("string")])
            ],
            required: ["bucket", "objectName"]
        ),
        schema(
            "stratus_query_logs",
            description: "Query Cloud Logging entries for a project with an optional Logging filter expression.",
            properties: [
                "projectId": projectIdProp,
                "filter": .object(["type": .string("string"), "description": .string("e.g. severity>=ERROR")]),
                "pageSize": .object(["type": .string("integer"), "description": .string("Max entries (1-200)")])
            ]
        ),
        schema("stratus_list_iam", description: "List IAM policy role-to-principal bindings for a project.", properties: ["projectId": projectIdProp]),
        schema("stratus_list_apis", description: "List enabled Google Cloud APIs for a project.", properties: ["projectId": projectIdProp]),
        schema(
            "stratus_toggle_api",
            description: "Enable or disable a Google Cloud service API (e.g. pubsub.googleapis.com).",
            properties: [
                "projectId": projectIdProp,
                "serviceName": .object(["type": .string("string")]),
                "enable": .object(["type": .string("boolean")])
            ],
            required: ["serviceName", "enable"]
        ),
        schema(
            "stratus_bigquery",
            description: "List BigQuery datasets, list tables in a dataset, or execute a Standard SQL query.",
            properties: [
                "projectId": projectIdProp,
                "datasetId": .object(["type": .string("string")]),
                "sql": .object(["type": .string("string"), "description": .string("Standard SQL query to execute")])
            ]
        ),
        schema(
            "stratus_cloud_sql",
            description: "List Cloud SQL instances or restart a named Cloud SQL instance.",
            properties: [
                "projectId": projectIdProp,
                "restartInstance": .object(["type": .string("string"), "description": .string("Optional instance name to restart")])
            ]
        ),
        schema(
            "stratus_secrets",
            description: "List Secret Manager secrets, list versions of a secret, or reveal a specific version payload.",
            properties: [
                "projectId": projectIdProp,
                "secretName": .object(["type": .string("string")]),
                "revealVersion": .object(["type": .string("string"), "description": .string("Version number or 'latest' to reveal")])
            ]
        ),
        schema(
            "stratus_open_ui",
            description: "Open or focus the Stratus macOS app window to a specific project and section.",
            properties: [
                "section": .object(["type": .string("string"), "enum": .array(["overview", "compute", "cloudRun", "storage", "dataServices", "logging", "iamAndApis"].map(AnyCodableValue.string))]),
                "projectId": projectIdProp
            ]
        )
    ]
}
