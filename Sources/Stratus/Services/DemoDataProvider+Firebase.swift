import Foundation

extension DemoDataProvider {
    // MARK: - Firestore Explorer Demo Data

    static func firestoreRootCollections() -> [String] {
        ["users", "sessions", "feature_flags", "audit_events"]
    }

    static func firestoreSubcollections(for documentRelativePath: String) -> [String] {
        let clean = documentRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if clean.hasPrefix("users/") && !clean.dropFirst("users/".count).contains("/") {
            return ["orders", "devices"]
        }
        return []
    }

    static func firestoreDocuments(projectId: String, databaseId: String = "(default)", collectionPath: String) -> [FirestoreDocument] {
        let now = Date()
        let clean = collectionPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = "projects/\(projectId)/databases/\(databaseId)/documents/\(clean)"

        if clean == "users" {
            return [
                FirestoreDocument(
                    name: "\(base)/usr_ada_01",
                    documentId: "usr_ada_01",
                    relativePath: "users/usr_ada_01",
                    fields: [
                        "email": .string("ada@stratus.dev"),
                        "displayName": .string("Ada Lovelace"),
                        "plan": .string("pro"),
                        "credits": .integer(4200),
                        "active": .boolean(true),
                        "roles": .array([.string("admin"), .string("billing_owner")]),
                        "metadata": .map(["region": .string("us-central1"), "mfa": .boolean(true)]),
                        "lastSeen": .timestamp("2026-11-26T08:40:00Z")
                    ],
                    createTime: now.addingTimeInterval(-86400 * 30),
                    updateTime: now.addingTimeInterval(-1800)
                ),
                FirestoreDocument(
                    name: "\(base)/usr_grace_02",
                    documentId: "usr_grace_02",
                    relativePath: "users/usr_grace_02",
                    fields: [
                        "email": .string("grace@stratus.dev"),
                        "displayName": .string("Grace Hopper"),
                        "plan": .string("enterprise"),
                        "credits": .integer(18500),
                        "active": .boolean(true),
                        "roles": .array([.string("developer"), .string("ops")]),
                        "metadata": .map(["region": .string("europe-west1"), "mfa": .boolean(true)]),
                        "lastSeen": .timestamp("2026-11-26T09:12:00Z")
                    ],
                    createTime: now.addingTimeInterval(-86400 * 14),
                    updateTime: now.addingTimeInterval(-420)
                ),
                FirestoreDocument(
                    name: "\(base)/usr_alan_03",
                    documentId: "usr_alan_03",
                    relativePath: "users/usr_alan_03",
                    fields: [
                        "email": .string("alan@stratus.dev"),
                        "displayName": .string("Alan Turing"),
                        "plan": .string("free"),
                        "credits": .integer(120),
                        "active": .boolean(false),
                        "roles": .array([.string("viewer")]),
                        "lastSeen": .timestamp("2026-11-20T14:22:00Z")
                    ],
                    createTime: now.addingTimeInterval(-86400 * 60),
                    updateTime: now.addingTimeInterval(-86400 * 6)
                )
            ]
        }

        if clean.hasSuffix("/orders") {
            return [
                FirestoreDocument(
                    name: "\(base)/ord_9012",
                    documentId: "ord_9012",
                    relativePath: "\(clean)/ord_9012",
                    fields: [
                        "orderId": .string("ord_9012"),
                        "amountUsd": .double(149.50),
                        "currency": .string("USD"),
                        "status": .string("paid")
                    ],
                    createTime: now.addingTimeInterval(-86400 * 2),
                    updateTime: now.addingTimeInterval(-86400 * 2)
                ),
                FirestoreDocument(
                    name: "\(base)/ord_9044",
                    documentId: "ord_9044",
                    relativePath: "\(clean)/ord_9044",
                    fields: [
                        "orderId": .string("ord_9044"),
                        "amountUsd": .double(49.00),
                        "currency": .string("USD"),
                        "status": .string("pending")
                    ],
                    createTime: now.addingTimeInterval(-3600 * 4),
                    updateTime: now.addingTimeInterval(-3600 * 2)
                )
            ]
        }

        if clean.hasSuffix("/devices") {
            return [
                FirestoreDocument(
                    name: "\(base)/macbook_pro_m4",
                    documentId: "macbook_pro_m4",
                    relativePath: "\(clean)/macbook_pro_m4",
                    fields: [
                        "platform": .string("macOS"),
                        "appVersion": .string("2.4.1"),
                        "pushEnabled": .boolean(true)
                    ],
                    createTime: now.addingTimeInterval(-86400 * 10),
                    updateTime: now.addingTimeInterval(-3600)
                )
            ]
        }

        if clean == "feature_flags" {
            return [
                FirestoreDocument(
                    name: "\(base)/checkout_v3",
                    documentId: "checkout_v3",
                    relativePath: "feature_flags/checkout_v3",
                    fields: [
                        "enabled": .boolean(true),
                        "rolloutPercent": .integer(75),
                        "owner": .string("payments-team")
                    ],
                    createTime: now.addingTimeInterval(-86400 * 7),
                    updateTime: now.addingTimeInterval(-7200)
                ),
                FirestoreDocument(
                    name: "\(base)/ai_assistant_drawer",
                    documentId: "ai_assistant_drawer",
                    relativePath: "feature_flags/ai_assistant_drawer",
                    fields: [
                        "enabled": .boolean(true),
                        "rolloutPercent": .integer(100),
                        "owner": .string("desktop-platform")
                    ],
                    createTime: now.addingTimeInterval(-86400 * 3),
                    updateTime: now.addingTimeInterval(-900)
                )
            ]
        }

        if clean == "sessions" {
            return [
                FirestoreDocument(
                    name: "\(base)/sess_881f2a",
                    documentId: "sess_881f2a",
                    relativePath: "sessions/sess_881f2a",
                    fields: [
                        "userId": .string("usr_ada_01"),
                        "ip": .string("34.120.18.42"),
                        "valid": .boolean(true),
                        "ttlSeconds": .integer(3600)
                    ],
                    createTime: now.addingTimeInterval(-1200),
                    updateTime: now.addingTimeInterval(-300)
                )
            ]
        }

        return [
            FirestoreDocument(
                name: "\(base)/evt_001",
                documentId: "evt_001",
                relativePath: "\(clean)/evt_001",
                fields: [
                    "event": .string("deployment.completed"),
                    "actor": .string("deploy-bot@\(projectId).iam.gserviceaccount.com"),
                    "severity": .string("INFO"),
                    "latencyMs": .integer(142)
                ],
                createTime: now.addingTimeInterval(-3600),
                updateTime: now.addingTimeInterval(-3600)
            )
        ]
    }

    static func firestoreIndexes(projectId: String, databaseId: String = "(default)") -> [FirestoreIndex] {
        let base = "projects/\(projectId)/databases/\(databaseId)/collectionGroups"
        return [
            FirestoreIndex(
                name: "\(base)/users/indexes/CICAgOjXh4EK",
                collectionGroup: "users",
                queryScope: "COLLECTION",
                state: "READY",
                fields: [
                    FirestoreIndexField(fieldPath: "plan", orderOrMode: "ASCENDING"),
                    FirestoreIndexField(fieldPath: "credits", orderOrMode: "DESCENDING")
                ]
            ),
            FirestoreIndex(
                name: "\(base)/orders/indexes/CICAgKiv9YoK",
                collectionGroup: "orders",
                queryScope: "COLLECTION_GROUP",
                state: "READY",
                fields: [
                    FirestoreIndexField(fieldPath: "status", orderOrMode: "ASCENDING"),
                    FirestoreIndexField(fieldPath: "amountUsd", orderOrMode: "DESCENDING")
                ]
            )
        ]
    }

    // MARK: - Firebase Demo Data

    static func firebaseProject(for projectId: String) -> FirebaseProjectInfo {
        FirebaseProjectInfo(
            projectId: projectId,
            projectNumber: "849201746312",
            displayName: "Stratus Cloud (\(projectId))",
            state: "ACTIVE",
            defaultHostingSite: projectId,
            defaultRealtimeDatabaseInstance: "\(projectId)-default-rtdb",
            defaultStorageBucket: "\(projectId).firebasestorage.app",
            locationId: "us-central1"
        )
    }

    static func firebaseApps(for projectId: String) -> [FirebaseAppItem] {
        [
            FirebaseAppItem(
                appId: "1:849201746312:web:9f24c8a10d3b7e12",
                displayName: "Stratus Web Console",
                platform: .web,
                bundleOrPackageId: "\(projectId).web.app",
                state: "ACTIVE",
                apiKeyId: "AIzaSyDemoWebKeyStratus01"
            ),
            FirebaseAppItem(
                appId: "1:849201746312:ios:4c8a19b2e7304f01",
                displayName: "Stratus iOS Companion",
                platform: .ios,
                bundleOrPackageId: "dev.stratus.ios",
                state: "ACTIVE",
                apiKeyId: "AIzaSyDemoIosKeyStratus02"
            ),
            FirebaseAppItem(
                appId: "1:849201746312:android:7d12e4f09a813c55",
                displayName: "Stratus Android Client",
                platform: .android,
                bundleOrPackageId: "dev.stratus.android",
                state: "ACTIVE",
                apiKeyId: "AIzaSyDemoAndroidKeyStratus03"
            )
        ]
    }

    static func firebaseAppConfig(for app: FirebaseAppItem, projectId: String) -> FirebaseAppConfig {
        switch app.platform {
        case .web:
            return FirebaseAppConfig(
                appId: app.appId,
                platform: .web,
                filename: "firebase-config.json",
                rawContent: """
                {
                  "apiKey": "AIzaSyDemoWebKeyStratus01",
                  "appId": "\(app.appId)",
                  "authDomain": "\(projectId).firebaseapp.com",
                  "databaseURL": "https://\(projectId)-default-rtdb.firebaseio.com",
                  "projectId": "\(projectId)",
                  "storageBucket": "\(projectId).firebasestorage.app"
                }
                """
            )
        case .ios:
            return FirebaseAppConfig(
                appId: app.appId,
                platform: .ios,
                filename: "GoogleService-Info.plist",
                rawContent: """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0">
                <dict>
                  <key>BUNDLE_ID</key>
                  <string>\(app.bundleOrPackageId ?? "dev.stratus.ios")</string>
                  <key>GOOGLE_APP_ID</key>
                  <string>\(app.appId)</string>
                  <key>PROJECT_ID</key>
                  <string>\(projectId)</string>
                </dict>
                </plist>
                """
            )
        case .android:
            return FirebaseAppConfig(
                appId: app.appId,
                platform: .android,
                filename: "google-services.json",
                rawContent: """
                {
                  "project_info": {
                    "project_number": "849201746312",
                    "project_id": "\(projectId)"
                  },
                  "client": [
                    {
                      "client_info": {
                        "mobilesdk_app_id": "\(app.appId)",
                        "android_client_info": { "package_name": "\(app.bundleOrPackageId ?? "dev.stratus.android")" }
                      }
                    }
                  ]
                }
                """
            )
        }
    }

    static func firebaseAuthUsers() -> [FirebaseAuthUser] {
        let now = Date()
        return [
            FirebaseAuthUser(localId: "uid_9f10a2b4", email: "ada@stratus.dev", displayName: "Ada Lovelace", phoneNumber: nil, emailVerified: true, disabled: false, providers: ["google.com", "password"], createdAt: now.addingTimeInterval(-86400 * 90), lastLoginAt: now.addingTimeInterval(-900)),
            FirebaseAuthUser(localId: "uid_3c82e1d9", email: "grace@stratus.dev", displayName: "Grace Hopper", phoneNumber: "+14155550101", emailVerified: true, disabled: false, providers: ["github.com"], createdAt: now.addingTimeInterval(-86400 * 60), lastLoginAt: now.addingTimeInterval(-3600 * 2)),
            FirebaseAuthUser(localId: "uid_7a44b018", email: "alan@stratus.dev", displayName: "Alan Turing", phoneNumber: nil, emailVerified: false, disabled: true, providers: ["password"], createdAt: now.addingTimeInterval(-86400 * 45), lastLoginAt: now.addingTimeInterval(-86400 * 12)),
            FirebaseAuthUser(localId: "uid_5d19f8c3", email: "margaret@stratus.dev", displayName: "Margaret Hamilton", phoneNumber: nil, emailVerified: true, disabled: false, providers: ["google.com"], createdAt: now.addingTimeInterval(-86400 * 20), lastLoginAt: now.addingTimeInterval(-3600 * 8)),
            FirebaseAuthUser(localId: "uid_2b77c4e1", email: "linus@stratus.dev", displayName: "Linus Torvalds", phoneNumber: nil, emailVerified: true, disabled: false, providers: ["github.com"], createdAt: now.addingTimeInterval(-86400 * 10), lastLoginAt: now.addingTimeInterval(-86400))
        ]
    }

    static func firebaseHostingSites(for projectId: String) -> [FirebaseHostingSite] {
        [
            FirebaseHostingSite(name: "projects/\(projectId)/sites/\(projectId)", siteId: projectId, defaultUrl: "https://\(projectId).web.app", type: "DEFAULT_SITE"),
            FirebaseHostingSite(name: "projects/\(projectId)/sites/\(projectId)-docs", siteId: "\(projectId)-docs", defaultUrl: "https://\(projectId)-docs.web.app", type: "USER_SITE")
        ]
    }

    static func firebaseHostingReleases(for siteId: String) -> [FirebaseHostingRelease] {
        let now = Date()
        return [
            FirebaseHostingRelease(name: "sites/\(siteId)/releases/rel-412", versionId: "v412-9a1f", status: "FINALIZED", message: "Deploy v2.14.0 checkout edge bundle", releaseTime: now.addingTimeInterval(-3600 * 3), releaseUserEmail: "ci-deploy@stratus.dev"),
            FirebaseHostingRelease(name: "sites/\(siteId)/releases/rel-411", versionId: "v411-7b02", status: "FINALIZED", message: "Fix auth redirect headers in firebase.json", releaseTime: now.addingTimeInterval(-86400 * 2), releaseUserEmail: "ada@stratus.dev"),
            FirebaseHostingRelease(name: "sites/\(siteId)/releases/rel-410", versionId: "v410-1c84", status: "FINALIZED", message: "Upgrade Web SDK to 11.2.0", releaseTime: now.addingTimeInterval(-86400 * 6), releaseUserEmail: "ci-deploy@stratus.dev")
        ]
    }

    static func firebaseHostingChannels(for siteId: String) -> [FirebaseHostingChannel] {
        let now = Date()
        return [
            FirebaseHostingChannel(name: "sites/\(siteId)/channels/live", channelId: "live", url: "https://\(siteId).web.app", expireTime: nil, retainedReleaseCount: 10),
            FirebaseHostingChannel(name: "sites/\(siteId)/channels/pr-184", channelId: "pr-184", url: "https://\(siteId)--pr-184-k9f1a2.web.app", expireTime: now.addingTimeInterval(86400 * 5), retainedReleaseCount: 3)
        ]
    }

    static func firebaseRulesReleases(for projectId: String) -> [FirebaseRulesRelease] {
        let now = Date()
        return [
            FirebaseRulesRelease(name: "projects/\(projectId)/releases/cloud.firestore", shortName: "cloud.firestore", rulesetName: "projects/\(projectId)/rulesets/rs_firestore_84a1", createTime: now.addingTimeInterval(-86400 * 14), updateTime: now.addingTimeInterval(-3600 * 6)),
            FirebaseRulesRelease(name: "projects/\(projectId)/releases/firebase.storage", shortName: "firebase.storage", rulesetName: "projects/\(projectId)/rulesets/rs_storage_39c2", createTime: now.addingTimeInterval(-86400 * 30), updateTime: now.addingTimeInterval(-86400 * 4))
        ]
    }

    static func firebaseRuleset(for rulesetName: String) -> FirebaseRuleset {
        let shortId = rulesetName.split(separator: "/").last.map(String.init) ?? rulesetName
        let isStorage = rulesetName.contains("storage")
        let content: String
        let filename: String
        if isStorage {
            filename = "storage.rules"
            content = """
            rules_version = '2';
            service firebase.storage {
              match /b/{bucket}/o {
                match /users/{userId}/{allPaths=**} {
                  allow read, write: if request.auth != null && request.auth.uid == userId;
                }
                match /public/{allPaths=**} {
                  allow read: if true;
                  allow write: if false;
                }
              }
            }
            """
        } else {
            filename = "firestore.rules"
            content = """
            rules_version = '2';
            service cloud.firestore {
              match /databases/{database}/documents {
                match /users/{userId} {
                  allow read: if request.auth != null;
                  allow write: if request.auth != null && request.auth.uid == userId;

                  match /orders/{orderId} {
                    allow read: if request.auth != null && request.auth.uid == userId;
                    allow write: if false;
                  }
                }
                match /feature_flags/{flagId} {
                  allow read: if true;
                  allow write: if request.auth.token.admin == true;
                }
              }
            }
            """
        }
        return FirebaseRuleset(
            name: rulesetName,
            shortId: shortId,
            createTime: Date().addingTimeInterval(-86400 * 4),
            files: [FirebaseRuleFile(name: filename, content: content)]
        )
    }

    static func firebaseRemoteConfig() -> FirebaseRemoteConfigTemplate {
        let params = [
            FirebaseRemoteConfigParam(key: "enable_new_checkout", defaultValue: "true", valueType: "BOOLEAN", description: "Roll out single-page checkout v3"),
            FirebaseRemoteConfigParam(key: "max_upload_mb", defaultValue: "25", valueType: "NUMBER", description: "Client-side attachment size ceiling"),
            FirebaseRemoteConfigParam(key: "welcome_banner_copy", defaultValue: "Stratus Console 2.0 is live", valueType: "STRING", description: "Top banner announcement string"),
            FirebaseRemoteConfigParam(key: "pricing_tiers_json", defaultValue: "{\"pro\":29,\"enterprise\":199}", valueType: "JSON", description: "Plan pricing config")
        ]
        let rawJSON = """
        {
          "parameters": {
            "enable_new_checkout": {
              "defaultValue": { "value": "true" },
              "description": "Roll out single-page checkout v3",
              "valueType": "BOOLEAN"
            },
            "max_upload_mb": {
              "defaultValue": { "value": "25" },
              "description": "Client-side attachment size ceiling",
              "valueType": "NUMBER"
            },
            "pricing_tiers_json": {
              "defaultValue": { "value": "{\\"pro\\":29,\\"enterprise\\":199}" },
              "description": "Plan pricing config",
              "valueType": "JSON"
            },
            "welcome_banner_copy": {
              "defaultValue": { "value": "Stratus Console 2.0 is live" },
              "description": "Top banner announcement string",
              "valueType": "STRING"
            }
          },
          "version": {
            "versionNumber": "42",
            "updateUser": { "email": "ada@stratus.dev" }
          }
        }
        """
        return FirebaseRemoteConfigTemplate(
            etag: "etag-demo-42-9f81c",
            versionNumber: "42",
            updateTime: Date().addingTimeInterval(-3600 * 5),
            updateUserEmail: "ada@stratus.dev",
            parameters: params,
            rawJSON: rawJSON
        )
    }

    static func firebaseRemoteConfigVersions() -> [FirebaseRemoteConfigVersion] {
        let now = Date()
        return [
            FirebaseRemoteConfigVersion(versionNumber: "42", updateTime: now.addingTimeInterval(-3600 * 5), updateUserEmail: "ada@stratus.dev", description: "Bump max_upload_mb to 25", isRollback: false),
            FirebaseRemoteConfigVersion(versionNumber: "41", updateTime: now.addingTimeInterval(-86400 * 2), updateUserEmail: "grace@stratus.dev", description: "Enable checkout v3", isRollback: false),
            FirebaseRemoteConfigVersion(versionNumber: "40", updateTime: now.addingTimeInterval(-86400 * 5), updateUserEmail: "ada@stratus.dev", description: "Initial pricing tiers JSON", isRollback: false)
        ]
    }

    static func realtimeDBInstances(for projectId: String) -> [RealtimeDBInstance] {
        [
            RealtimeDBInstance(
                name: "projects/\(projectId)/locations/us-central1/instances/\(projectId)-default-rtdb",
                instanceId: "\(projectId)-default-rtdb",
                databaseUrl: "https://\(projectId)-default-rtdb.firebaseio.com",
                region: "us-central1",
                type: "DEFAULT_DATABASE",
                state: "ACTIVE"
            )
        ]
    }

    static func realtimeDBSampleNode(path: String, shallow: Bool) -> String {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if shallow {
            return """
            {
              "config": true,
              "metrics": true,
              "presence": true
            }
            """
        }
        if clean == "presence" {
            return """
            {
              "usr_ada_01": {
                "online": true,
                "region": "us-central1"
              },
              "usr_grace_02": {
                "online": true,
                "region": "europe-west1"
              }
            }
            """
        }
        return """
        {
          "config": {
            "maintenanceMode": false,
            "minClientVersion": "2.4.0"
          },
          "metrics": {
            "activeSockets": 412,
            "eventsPerSec": 89
          },
          "presence": {
            "usr_ada_01": { "online": true },
            "usr_grace_02": { "online": true }
          }
        }
        """
    }
}
