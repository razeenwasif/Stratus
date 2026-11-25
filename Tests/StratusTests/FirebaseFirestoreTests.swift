import Testing
import Foundation
@testable import Stratus

@Suite("Firebase & Firestore REST Tests")
struct FirebaseFirestoreTests {
    @Test("FirestoreValue REST JSON round-trip covers all types including nested maps and arrays")
    func firestoreValueRoundTrip() throws {
        let original: [String: FirestoreValue] = [
            "name": .string("Ada Lovelace"),
            "credits": .integer(4200),
            "ratio": .double(0.75),
            "active": .boolean(true),
            "deletedAt": .null,
            "joined": .timestamp("2026-11-26T00:00:00Z"),
            "location": .geoPoint(latitude: -33.8688, longitude: 151.2093),
            "orgRef": .reference("projects/p/databases/(default)/documents/orgs/stratus"),
            "tags": .array([.string("admin"), .integer(1), .boolean(false)]),
            "meta": .map(["region": .string("us-central1"), "mfa": .boolean(true)])
        ]

        let restDict = FirestoreValue.encodeFieldsREST(original)
        let data = try JSONSerialization.data(withJSONObject: restDict)
        let decodedRaw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let decoded = FirestoreValue.decodeFieldsREST(decodedRaw)

        #expect(decoded["name"] == .string("Ada Lovelace"))
        #expect(decoded["credits"] == .integer(4200))
        #expect(decoded["ratio"] == .double(0.75))
        #expect(decoded["active"] == .boolean(true))
        #expect(decoded["deletedAt"] == .null)
        #expect(decoded["joined"] == .timestamp("2026-11-26T00:00:00Z"))
        #expect(decoded["location"] == .geoPoint(latitude: -33.8688, longitude: 151.2093))
        #expect(decoded["orgRef"] == .reference("projects/p/databases/(default)/documents/orgs/stratus"))
        #expect(decoded["tags"] == .array([.string("admin"), .integer(1), .boolean(false)]))
        #expect(decoded["meta"] == .map(["region": .string("us-central1"), "mfa": .boolean(true)]))
    }

    @Test("FirestoreValue converts plain JSON objects into typed Firestore fields")
    func firestorePlainJSONParsing() throws {
        let json = """
        {
          "email": "ada@stratus.dev",
          "credits": 150,
          "discount": 12.5,
          "verified": true,
          "notes": null,
          "roles": ["admin", "ops"],
          "settings": { "dark": true }
        }
        """
        let fields = try FirestoreValue.fields(fromPlainJSONString: json)
        #expect(fields["email"] == .string("ada@stratus.dev"))
        #expect(fields["credits"] == .integer(150))
        #expect(fields["discount"] == .double(12.5))
        #expect(fields["verified"] == .boolean(true))
        #expect(fields["notes"] == .null)
        #expect(fields["roles"] == .array([.string("admin"), .string("ops")]))
        #expect(fields["settings"] == .map(["dark": .boolean(true)]))
    }

    @Test("FirebaseParser decodes Firestore documents list, runQuery, and indexes")
    func decodeFirestoreRESTPayloads() throws {
        let listJSON = """
        {
          "documents": [
            {
              "name": "projects/my-app/databases/(default)/documents/users/usr_1",
              "fields": {
                "email": { "stringValue": "ada@stratus.dev" },
                "credits": { "integerValue": "500" }
              },
              "createTime": "2026-11-20T10:00:00Z",
              "updateTime": "2026-11-25T12:00:00Z"
            }
          ],
          "nextPageToken": "page-2"
        }
        """
        let listResult = try FirebaseParser.decodeFirestoreDocumentsList(from: Data(listJSON.utf8))
        #expect(listResult.documents.count == 1)
        #expect(listResult.documents[0].documentId == "usr_1")
        #expect(listResult.documents[0].relativePath == "users/usr_1")
        #expect(listResult.documents[0].fields["credits"] == .integer(500))
        #expect(listResult.nextPageToken == "page-2")

        let queryBody = try FirebaseParser.buildStructuredQueryBody(
            collectionId: "users",
            filterField: "credits",
            op: .greaterThanOrEqual,
            filterValueRaw: "500",
            orderByField: "credits",
            descending: true,
            limit: 25
        )
        let queryObj = try JSONSerialization.jsonObject(with: queryBody) as? [String: Any]
        let sq = queryObj?["structuredQuery"] as? [String: Any]
        #expect((sq?["limit"] as? Int) == 25)

        let runQueryJSON = """
        [
          {
            "document": {
              "name": "projects/my-app/databases/(default)/documents/users/usr_1",
              "fields": { "active": { "booleanValue": true } }
            },
            "readTime": "2026-11-26T00:00:00Z"
          },
          {
            "readTime": "2026-11-26T00:00:00Z"
          }
        ]
        """
        let queryDocs = try FirebaseParser.decodeFirestoreRunQuery(from: Data(runQueryJSON.utf8))
        #expect(queryDocs.count == 1)
        #expect(queryDocs[0].fields["active"] == .boolean(true))

        let indexesJSON = """
        {
          "indexes": [
            {
              "name": "projects/my-app/databases/(default)/collectionGroups/users/indexes/CICAg123",
              "queryScope": "COLLECTION",
              "state": "READY",
              "fields": [
                { "fieldPath": "plan", "order": "ASCENDING" },
                { "fieldPath": "credits", "order": "DESCENDING" }
              ]
            }
          ]
        }
        """
        let idxs = try FirebaseParser.decodeFirestoreIndexes(from: Data(indexesJSON.utf8))
        #expect(idxs.count == 1)
        #expect(idxs[0].collectionGroup == "users")
        #expect(idxs[0].fields.count == 2)
    }

    @Test("FirebaseParser decodes Project, Apps, SDK Config, Auth, Hosting, Rules, Remote Config, and RTDB")
    func decodeFirebaseRESTPayloads() throws {
        let projJSON = """
        {
          "projectId": "stratus-app",
          "projectNumber": "123456",
          "displayName": "Stratus App",
          "state": "ACTIVE",
          "resources": {
            "hostingSite": "stratus-app",
            "realtimeDatabaseInstance": "stratus-app-default-rtdb",
            "storageBucket": "stratus-app.firebasestorage.app",
            "locationId": "us-central1"
          }
        }
        """
        let proj = try FirebaseParser.decodeFirebaseProject(from: Data(projJSON.utf8))
        #expect(proj.projectId == "stratus-app")
        #expect(proj.defaultHostingSite == "stratus-app")

        let iosAppsJSON = """
        {
          "apps": [
            {
              "appId": "1:123456:ios:abcdef",
              "displayName": "Stratus iOS",
              "bundleId": "dev.stratus.ios",
              "state": "ACTIVE"
            }
          ]
        }
        """
        let iosApps = try FirebaseParser.decodeFirebaseApps(from: Data(iosAppsJSON.utf8), platform: .ios)
        #expect(iosApps.count == 1)
        #expect(iosApps[0].bundleOrPackageId == "dev.stratus.ios")

        let plistB64 = Data("<plist>demo</plist>".utf8).base64EncodedString()
        let iosCfgJSON = """
        {
          "configFilename": "GoogleService-Info.plist",
          "configFileContents": "\(plistB64)"
        }
        """
        let iosCfg = try FirebaseParser.decodeFirebaseAppConfig(from: Data(iosCfgJSON.utf8), app: iosApps[0])
        #expect(iosCfg.filename == "GoogleService-Info.plist")
        #expect(iosCfg.rawContent == "<plist>demo</plist>")

        let authJSON = """
        {
          "users": [
            {
              "localId": "uid_1",
              "email": "ada@stratus.dev",
              "displayName": "Ada",
              "emailVerified": true,
              "disabled": false,
              "createdAt": "1700000000000",
              "lastLoginAt": "1730000000000",
              "providerUserInfo": [{ "providerId": "google.com" }]
            }
          ]
        }
        """
        let users = try FirebaseParser.decodeAuthUsers(from: Data(authJSON.utf8))
        #expect(users.count == 1)
        #expect(users[0].email == "ada@stratus.dev")
        #expect(users[0].providers == ["google.com"])
        #expect(users[0].lastLoginAt != nil)

        let sitesJSON = """
        { "sites": [{ "name": "projects/p/sites/my-site", "defaultUrl": "https://my-site.web.app", "type": "DEFAULT_SITE" }] }
        """
        let sites = try FirebaseParser.decodeHostingSites(from: Data(sitesJSON.utf8))
        #expect(sites.first?.siteId == "my-site")

        let releasesJSON = """
        { "releases": [{ "name": "sites/my-site/releases/r1", "type": "DEPLOY", "message": "v1.0", "releaseTime": "2026-11-25T10:00:00Z", "releaseUser": { "email": "dev@stratus.dev" }, "version": { "name": "sites/my-site/versions/v1", "status": "FINALIZED" } }] }
        """
        let rels = try FirebaseParser.decodeHostingReleases(from: Data(releasesJSON.utf8))
        #expect(rels.first?.versionId == "v1")
        #expect(rels.first?.status == "FINALIZED")

        let channelsJSON = """
        { "channels": [{ "name": "sites/my-site/channels/pr-9", "url": "https://my-site--pr-9.web.app", "retainedReleaseCount": 3 }] }
        """
        let chans = try FirebaseParser.decodeHostingChannels(from: Data(channelsJSON.utf8))
        #expect(chans.first?.channelId == "pr-9")

        let rulesRelJSON = """
        { "releases": [{ "name": "projects/p/releases/cloud.firestore", "rulesetName": "projects/p/rulesets/rs_1" }] }
        """
        let ruleRels = try FirebaseParser.decodeRulesReleases(from: Data(rulesRelJSON.utf8))
        #expect(ruleRels.first?.shortName == "cloud.firestore")

        let rulesetJSON = """
        { "name": "projects/p/rulesets/rs_1", "source": { "files": [{ "name": "firestore.rules", "content": "rules_version = '2';" }] } }
        """
        let ruleset = try FirebaseParser.decodeRuleset(from: Data(rulesetJSON.utf8))
        #expect(ruleset.files.first?.content == "rules_version = '2';")

        let rcJSON = """
        {
          "parameters": {
            "flag_a": { "defaultValue": { "value": "true" }, "valueType": "BOOLEAN", "description": "Flag A" }
          },
          "version": { "versionNumber": "12", "updateUser": { "email": "ops@stratus.dev" } }
        }
        """
        let rc = try FirebaseParser.decodeRemoteConfig(from: Data(rcJSON.utf8), etag: "etag-12")
        #expect(rc.etag == "etag-12")
        #expect(rc.versionNumber == "12")
        #expect(rc.parameters.first?.key == "flag_a")

        let rtdbJSON = """
        { "instances": [{ "name": "projects/p/locations/us-central1/instances/p-default-rtdb", "databaseUrl": "https://p-default-rtdb.firebaseio.com", "type": "DEFAULT_DATABASE", "state": "ACTIVE" }] }
        """
        let rtdb = try FirebaseParser.decodeRealtimeDBInstances(from: Data(rtdbJSON.utf8))
        #expect(rtdb.first?.instanceId == "p-default-rtdb")
    }

    @Test("MCPServer exposes and executes stratus_firebase and stratus_firestore in demo mode")
    @MainActor
    func mcpFirebaseAndFirestoreTools() async {
        let server = MCPServer()

        let listReply = await server.handleMessage(#"{"jsonrpc":"2.0","id":10,"method":"tools/list"}"#)
        #expect(listReply?.contains("stratus_firebase") == true)
        #expect(listReply?.contains("stratus_firestore") == true)

        let fbAppsReply = await server.handleMessage(#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"stratus_firebase","arguments":{"action":"apps","demo":true}}}"#)
        #expect(fbAppsReply?.contains(#""isError":false"#) == true)
        #expect(fbAppsReply?.contains("Stratus Web Console") == true)

        let fbAuthReply = await server.handleMessage(#"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"stratus_firebase","arguments":{"action":"auth_list","demo":true}}}"#)
        #expect(fbAuthReply?.contains(#""isError":false"#) == true)
        #expect(fbAuthReply?.contains("ada@stratus.dev") == true)

        let fsListReply = await server.handleMessage(#"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"stratus_firestore","arguments":{"action":"list","collectionPath":"users","demo":true}}}"#)
        #expect(fsListReply?.contains(#""isError":false"#) == true)
        #expect(fsListReply?.contains("usr_ada_01") == true)

        let fsQueryReply = await server.handleMessage(#"{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"stratus_firestore","arguments":{"action":"query","collectionPath":"users","filterField":"plan","filterOp":"EQUAL","filterValue":"pro","demo":true}}}"#)
        #expect(fsQueryReply?.contains(#""isError":false"#) == true)
        #expect(fsQueryReply?.contains("usr_ada_01") == true)
    }
}
