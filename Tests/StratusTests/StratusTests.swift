import Testing
import Foundation
@testable import Stratus

@Suite("Stratus Core Tests")
struct StratusTests {
    @Test("PKCE generates valid verifier and S256 challenge")
    func pkceGeneration() {
        let pkce = PKCEHelper.generate()
        #expect(!pkce.codeVerifier.isEmpty)
        #expect(!pkce.codeChallenge.isEmpty)
        #expect(pkce.codeVerifier != pkce.codeChallenge)
        #expect(!pkce.codeVerifier.contains("="))
        #expect(!pkce.codeChallenge.contains("="))
        #expect(PKCEHelper.s256Challenge(for: pkce.codeVerifier) == pkce.codeChallenge)
    }

    @Test("GCS object URL encoding converts slashes to %2F")
    func gcsObjectPathEncoding() {
        let encoded = GCPParser.encodeGCSObjectName("releases/v2.14.0/manifest final.json")
        #expect(encoded == "releases%2Fv2.14.0%2Fmanifest%20final.json")
        #expect(!encoded.contains("/"))
    }

    @Test("Projects v3 JSON decoding")
    func decodeProjects() throws {
        let json = """
        {
          "projects": [
            {
              "name": "projects/123456789",
              "projectId": "my-prod-app",
              "displayName": "My Prod App",
              "state": "ACTIVE",
              "createTime": "2026-01-10T12:00:00Z"
            }
          ]
        }
        """
        let projects = try GCPParser.decodeProjects(from: Data(json.utf8))
        #expect(projects.count == 1)
        #expect(projects[0].projectId == "my-prod-app")
        #expect(projects[0].name == "My Prod App")
        #expect(projects[0].projectNumber == "123456789")
    }

    @Test("Compute Engine aggregated instances handles empty zones and valid VMs")
    func decodeComputeAggregated() throws {
        let json = """
        {
          "items": {
            "zones/us-central1-a": {
              "instances": [
                {
                  "id": "998877",
                  "name": "web-node-1",
                  "zone": "https://www.googleapis.com/compute/v1/projects/p/zones/us-central1-a",
                  "machineType": "https://www.googleapis.com/compute/v1/projects/p/zones/us-central1-a/machineTypes/e2-standard-4",
                  "status": "RUNNING",
                  "networkInterfaces": [
                    {
                      "networkIP": "10.128.0.5",
                      "accessConfigs": [{ "natIP": "34.10.20.30" }]
                    }
                  ],
                  "disks": [{ "diskSizeGb": "50" }]
                }
              ]
            },
            "zones/us-east1-b": {}
          }
        }
        """
        let vms = try GCPParser.decodeComputeAggregatedInstances(from: Data(json.utf8))
        #expect(vms.count == 1)
        #expect(vms[0].name == "web-node-1")
        #expect(vms[0].zone == "us-central1-a")
        #expect(vms[0].machineTypeShort == "e2-standard-4")
        #expect(vms[0].vcpuCount == 4)
        #expect(vms[0].internalIP == "10.128.0.5")
        #expect(vms[0].externalIP == "34.10.20.30")
        #expect(vms[0].diskSizeGb == 50)
    }

    @Test("Cloud Run v2 service JSON decoding")
    func decodeCloudRun() throws {
        let json = """
        {
          "services": [
            {
              "name": "projects/p/locations/us-central1/services/billing-api",
              "uri": "https://billing-api-abc.a.run.app",
              "latestReadyRevision": "projects/p/locations/us-central1/services/billing-api/revisions/billing-api-00012-xyz",
              "ingress": "INGRESS_TRAFFIC_ALL",
              "conditions": [{ "type": "Ready", "state": "CONDITION_SUCCEEDED" }],
              "traffic": [{ "type": "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST", "percent": 100 }]
            }
          ]
        }
        """
        let services = try GCPParser.decodeCloudRunServices(from: Data(json.utf8))
        #expect(services.count == 1)
        #expect(services[0].name == "billing-api")
        #expect(services[0].region == "us-central1")
        #expect(services[0].conditionsReady == true)
        #expect(services[0].latestReadyRevision == "billing-api-00012-xyz")
        #expect(services[0].traffic.first?.percent == 100)
    }

    @Test("GCS objects decoding parses string size and folder prefixes")
    func decodeGCSObjects() throws {
        let json = """
        {
          "prefixes": ["configs/"],
          "items": [
            {
              "name": "manifest.json",
              "size": "4096",
              "contentType": "application/json",
              "updated": "2026-11-24T22:10:00Z"
            }
          ]
        }
        """
        let objects = try GCPParser.decodeGCSObjects(from: Data(json.utf8), bucket: "test-bucket")
        #expect(objects.count == 2)
        #expect(objects[0].isPrefix == true)
        #expect(objects[0].displayName == "configs/")
        #expect(objects[1].isPrefix == false)
        #expect(objects[1].sizeBytes == 4096)
        #expect(objects[1].isPreviewableText == true)
    }

    @Test("Cloud Logging decoding handles nested jsonPayload")
    func decodeLogEntries() throws {
        let json = """
        {
          "entries": [
            {
              "insertId": "abc123",
              "timestamp": "2026-11-24T23:55:12.123Z",
              "severity": "ERROR",
              "logName": "projects/p/logs/run.googleapis.com%2Fstderr",
              "resource": {
                "type": "cloud_run_revision",
                "labels": { "service_name": "checkout-api" }
              },
              "jsonPayload": {
                "message": "Database pool exhausted",
                "retries": 3
              }
            }
          ]
        }
        """
        let entries = try GCPParser.decodeLogEntries(from: Data(json.utf8))
        #expect(entries.count == 1)
        #expect(entries[0].severity == .error)
        #expect(entries[0].resourceType == "cloud_run_revision")
        #expect(entries[0].message == "Database pool exhausted")
    }

    @Test("Secret Manager access payload decodes base64 secret")
    func decodeSecretPayload() throws {
        let b64 = Data("super-secret-value".utf8).base64EncodedString()
        let json = """
        { "payload": { "data": "\(b64)" } }
        """
        let decoded = try GCPParser.decodeSecretAccessPayload(from: Data(json.utf8))
        #expect(decoded == "super-secret-value")
    }

    @Test("CostEstimator and DemoDataProvider produce valid non-negative metrics")
    func costOverviewConsistency() {
        let demo = DemoDataProvider.costOverview(for: "prod-platform-core")
        #expect(demo.totalSpend > 0)
        #expect(demo.dailySeries.count == 30 * demo.serviceSpends.count)
        #expect(demo.dailySeries.allSatisfy { $0.cost >= 0 })

        let estimated = CostEstimator.buildOverview(
            projectId: "test-proj",
            instances: DemoDataProvider.instances(for: "prod-platform-core"),
            cloudRun: DemoDataProvider.cloudRunServices(for: "prod-platform-core"),
            buckets: DemoDataProvider.buckets(for: "prod-platform-core"),
            sqlInstances: DemoDataProvider.sqlInstances(for: "prod-platform-core"),
            datasets: DemoDataProvider.datasets(for: "prod-platform-core"),
            logCount: 6
        )
        #expect(estimated.totalSpend > 0)
        #expect(!estimated.topResources.isEmpty)
    }

    @Test("DeepLinkParser resolves section and project query parameters")
    func deepLinkParsing() {
        let url = URL(string: "stratus://navigate?section=compute&project=prod-platform-core")!
        let parsed = DeepLinkParser.parse(url)
        #expect(parsed.section == .compute)
        #expect(parsed.projectId == "prod-platform-core")
    }

    @Test("MCPServer handles initialize, tools/list, and tools/call in demo mode")
    @MainActor
    func mcpServerProtocol() async throws {
        let server = MCPServer()

        let initReply = await server.handleMessage(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        #expect(initReply?.contains("2024-11-05") == true)
        #expect(initReply?.contains("stratus") == true)

        let notifReply = await server.handleMessage(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(notifReply == nil)

        let listReply = await server.handleMessage(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        #expect(listReply?.contains("stratus_list_vms") == true)
        #expect(listReply?.contains("stratus_open_ui") == true)

        let callReply = await server.handleMessage(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"stratus_list_projects","arguments":{"demo":true}}}"#)
        #expect(callReply?.contains("prod-platform-core") == true)
        #expect(callReply?.contains(#""isError":false"#) == true)
    }
}
