import Foundation
import CoreFoundation

// MARK: - Firestore Data & Query Models

indirect enum FirestoreValue: Sendable, Hashable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case boolean(Bool)
    case null
    case timestamp(String)
    case geoPoint(latitude: Double, longitude: Double)
    case reference(String)
    case bytes(String)
    case array([FirestoreValue])
    case map([String: FirestoreValue])

    var typeLabel: String {
        switch self {
        case .string: return "string"
        case .integer: return "integer"
        case .double: return "double"
        case .boolean: return "boolean"
        case .null: return "null"
        case .timestamp: return "timestamp"
        case .geoPoint: return "geopoint"
        case .reference: return "reference"
        case .bytes: return "bytes"
        case .array: return "array"
        case .map: return "map"
        }
    }

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .integer(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .boolean(let b): return b ? "true" : "false"
        case .null: return "null"
        case .timestamp(let ts): return ts
        case .geoPoint(let lat, let lon): return "(\(lat), \(lon))"
        case .reference(let ref): return ref
        case .bytes(let b64): return "<bytes: \(b64.count) chars>"
        case .array(let items):
            return "[\(items.map(\.displayString).joined(separator: ", "))]"
        case .map(let dict):
            let pairs = dict.keys.sorted().map { "\($0): \(dict[$0]?.displayString ?? "null")" }
            return "{\(pairs.joined(separator: ", "))}"
        }
    }

    func toRESTJSON() -> [String: Any] {
        switch self {
        case .string(let s):
            return ["stringValue": s]
        case .integer(let i):
            return ["integerValue": String(i)]
        case .double(let d):
            return ["doubleValue": d]
        case .boolean(let b):
            return ["booleanValue": b]
        case .null:
            return ["nullValue": NSNull()]
        case .timestamp(let ts):
            return ["timestampValue": ts]
        case .geoPoint(let lat, let lon):
            return ["geoPointValue": ["latitude": lat, "longitude": lon]]
        case .reference(let ref):
            return ["referenceValue": ref]
        case .bytes(let b64):
            return ["bytesValue": b64]
        case .array(let arr):
            return ["arrayValue": ["values": arr.map { $0.toRESTJSON() }]]
        case .map(let dict):
            return ["mapValue": ["fields": Self.encodeFieldsREST(dict)]]
        }
    }

    static func fromRESTJSON(_ dict: [String: Any]) -> FirestoreValue {
        if let s = dict["stringValue"] as? String {
            return .string(s)
        }
        if let iStr = dict["integerValue"] as? String, let i = Int64(iStr) {
            return .integer(i)
        }
        if let iNum = dict["integerValue"] as? NSNumber {
            return .integer(iNum.int64Value)
        }
        if let d = dict["doubleValue"] as? Double {
            return .double(d)
        }
        if let b = dict["booleanValue"] as? Bool {
            return .boolean(b)
        }
        if dict["nullValue"] != nil {
            return .null
        }
        if let ts = dict["timestampValue"] as? String {
            return .timestamp(ts)
        }
        if let geo = dict["geoPointValue"] as? [String: Any] {
            let lat = geo["latitude"] as? Double ?? 0
            let lon = geo["longitude"] as? Double ?? 0
            return .geoPoint(latitude: lat, longitude: lon)
        }
        if let ref = dict["referenceValue"] as? String {
            return .reference(ref)
        }
        if let b64 = dict["bytesValue"] as? String {
            return .bytes(b64)
        }
        if let arrObj = dict["arrayValue"] as? [String: Any] {
            let vals = arrObj["values"] as? [[String: Any]] ?? []
            return .array(vals.map { fromRESTJSON($0) })
        }
        if let mapObj = dict["mapValue"] as? [String: Any] {
            let fields = mapObj["fields"] as? [String: Any] ?? [:]
            return .map(decodeFieldsREST(fields))
        }
        return .null
    }

    static func encodeFieldsREST(_ fields: [String: FirestoreValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in fields {
            out[k] = v.toRESTJSON()
        }
        return out
    }

    static func decodeFieldsREST(_ dict: [String: Any]) -> [String: FirestoreValue] {
        var out: [String: FirestoreValue] = [:]
        for (k, rawVal) in dict {
            if let valDict = rawVal as? [String: Any] {
                out[k] = fromRESTJSON(valDict)
            }
        }
        return out
    }

    func toPlainJSON() -> Any {
        switch self {
        case .string(let s): return s
        case .integer(let i): return NSNumber(value: i)
        case .double(let d): return d
        case .boolean(let b): return b
        case .null: return NSNull()
        case .timestamp(let ts): return ts
        case .geoPoint(let lat, let lon): return ["latitude": lat, "longitude": lon]
        case .reference(let ref): return ref
        case .bytes(let b64): return b64
        case .array(let arr): return arr.map { $0.toPlainJSON() }
        case .map(let dict):
            var out: [String: Any] = [:]
            for (k, v) in dict {
                out[k] = v.toPlainJSON()
            }
            return out
        }
    }

    static func fromPlainJSON(_ value: Any) -> FirestoreValue {
        if value is NSNull {
            return .null
        }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .boolean(num.boolValue)
            }
            let objCType = String(cString: num.objCType)
            if objCType == "d" || objCType == "f" {
                let d = num.doubleValue
                if d.rounded(.towardZero) == d && abs(d) < Double(Int64.max / 2) && !String(describing: value).contains(".") {
                    return .integer(num.int64Value)
                }
                return .double(d)
            }
            return .integer(num.int64Value)
        }
        if let b = value as? Bool {
            return .boolean(b)
        }
        if let i = value as? Int64 {
            return .integer(i)
        }
        if let i = value as? Int {
            return .integer(Int64(i))
        }
        if let d = value as? Double {
            return .double(d)
        }
        if let s = value as? String {
            return .string(s)
        }
        if let arr = value as? [Any] {
            return .array(arr.map { fromPlainJSON($0) })
        }
        if let dict = value as? [String: Any] {
            var map: [String: FirestoreValue] = [:]
            for (k, v) in dict {
                map[k] = fromPlainJSON(v)
            }
            return .map(map)
        }
        return .null
    }

    static func prettyJSONString(from fields: [String: FirestoreValue]) -> String {
        var plain: [String: Any] = [:]
        for (k, v) in fields {
            plain[k] = v.toPlainJSON()
        }
        guard JSONSerialization.isValidJSONObject(plain),
              let data = try? JSONSerialization.data(withJSONObject: plain, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    static func fields(fromPlainJSONString json: String) throws -> [String: FirestoreValue] {
        let data = Data(json.utf8)
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw GCPAPIError.decodingError("Document fields JSON must be an object ({...})")
        }
        var result: [String: FirestoreValue] = [:]
        for (k, v) in dict {
            result[k] = fromPlainJSON(v)
        }
        return result
    }

    func toCodableValue() -> AnyCodableValue {
        switch self {
        case .string(let s): return .string(s)
        case .integer(let i): return .int(Int(clamping: i))
        case .double(let d): return .double(d)
        case .boolean(let b): return .bool(b)
        case .null: return .null
        case .timestamp(let ts): return .string(ts)
        case .geoPoint(let lat, let lon): return .object(["latitude": .double(lat), "longitude": .double(lon)])
        case .reference(let r): return .string(r)
        case .bytes(let b64): return .string(b64)
        case .array(let arr): return .array(arr.map { $0.toCodableValue() })
        case .map(let dict):
            var obj: [String: AnyCodableValue] = [:]
            for (k, v) in dict { obj[k] = v.toCodableValue() }
            return .object(obj)
        }
    }
}

struct FirestoreDocument: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let documentId: String
    let relativePath: String
    let fields: [String: FirestoreValue]
    let createTime: Date?
    let updateTime: Date?

    var summaryLine: String {
        let keys = fields.keys.sorted().prefix(3)
        if keys.isEmpty { return "(empty document)" }
        return keys.map { "\($0): \(fields[$0]?.displayString ?? "")" }.joined(separator: " · ")
    }
}

struct FirestoreIndexField: Sendable, Hashable {
    let fieldPath: String
    let orderOrMode: String
}

struct FirestoreIndex: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let collectionGroup: String
    let queryScope: String
    let state: String
    let fields: [FirestoreIndexField]
}

enum FirestoreQueryOperator: String, CaseIterable, Identifiable, Sendable {
    case equal = "EQUAL"
    case notEqual = "NOT_EQUAL"
    case lessThan = "LESS_THAN"
    case lessThanOrEqual = "LESS_THAN_OR_EQUAL"
    case greaterThan = "GREATER_THAN"
    case greaterThanOrEqual = "GREATER_THAN_OR_EQUAL"
    case arrayContains = "ARRAY_CONTAINS"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .equal: return "=="
        case .notEqual: return "!="
        case .lessThan: return "<"
        case .lessThanOrEqual: return "<="
        case .greaterThan: return ">"
        case .greaterThanOrEqual: return ">="
        case .arrayContains: return "array-contains"
        }
    }
}

// MARK: - Firebase Management, Auth, Hosting, Rules, Remote Config, RTDB

enum FirebaseSubTab: String, Sendable, CaseIterable, Identifiable, Hashable {
    case apps
    case auth
    case hosting
    case rules
    case remoteConfig
    case realtimeDB

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return "Project & Apps"
        case .auth: return "Authentication"
        case .hosting: return "Hosting"
        case .rules: return "Security Rules"
        case .remoteConfig: return "Remote Config"
        case .realtimeDB: return "Realtime DB"
        }
    }
}

struct FirebaseProjectInfo: Sendable, Hashable {
    let projectId: String
    let projectNumber: String
    let displayName: String
    let state: String
    let defaultHostingSite: String?
    let defaultRealtimeDatabaseInstance: String?
    let defaultStorageBucket: String?
    let locationId: String?
}

enum FirebaseAppPlatform: String, Sendable, Hashable, CaseIterable {
    case web
    case ios
    case android

    var title: String {
        switch self {
        case .web: return "Web"
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }

    var icon: String {
        switch self {
        case .web: return "globe"
        case .ios: return "apple.logo"
        case .android: return "smartphone"
        }
    }

    var colorHex: String {
        switch self {
        case .web: return "#4BC3F7"
        case .ios: return "#A78BFA"
        case .android: return "#34D399"
        }
    }
}

struct FirebaseAppItem: Identifiable, Sendable, Hashable {
    var id: String { appId }
    let appId: String
    let displayName: String
    let platform: FirebaseAppPlatform
    let bundleOrPackageId: String?
    let state: String
    let apiKeyId: String?
}

struct FirebaseAppConfig: Sendable, Hashable {
    let appId: String
    let platform: FirebaseAppPlatform
    let filename: String
    let rawContent: String
}

struct FirebaseAuthUser: Identifiable, Sendable, Hashable {
    var id: String { localId }
    let localId: String
    let email: String?
    let displayName: String?
    let phoneNumber: String?
    let emailVerified: Bool
    let disabled: Bool
    let providers: [String]
    let createdAt: Date?
    let lastLoginAt: Date?
}

struct FirebaseHostingSite: Identifiable, Sendable, Hashable {
    var id: String { siteId }
    let name: String
    let siteId: String
    let defaultUrl: String
    let type: String
}

struct FirebaseHostingRelease: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let versionId: String
    let status: String
    let message: String
    let releaseTime: Date?
    let releaseUserEmail: String?
}

struct FirebaseHostingChannel: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let channelId: String
    let url: String
    let expireTime: Date?
    let retainedReleaseCount: Int?
}

struct FirebaseRuleFile: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let content: String
}

struct FirebaseRuleset: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let shortId: String
    let createTime: Date?
    let files: [FirebaseRuleFile]
}

struct FirebaseRulesRelease: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let shortName: String
    let rulesetName: String
    let createTime: Date?
    let updateTime: Date?
}

struct FirebaseRemoteConfigParam: Identifiable, Sendable, Hashable {
    var id: String { key }
    let key: String
    let defaultValue: String
    let valueType: String
    let description: String
}

struct FirebaseRemoteConfigTemplate: Sendable, Hashable {
    let etag: String
    let versionNumber: String
    let updateTime: Date?
    let updateUserEmail: String?
    let parameters: [FirebaseRemoteConfigParam]
    let rawJSON: String
}

struct FirebaseRemoteConfigVersion: Identifiable, Sendable, Hashable {
    var id: String { versionNumber }
    let versionNumber: String
    let updateTime: Date?
    let updateUserEmail: String?
    let description: String?
    let isRollback: Bool
}

struct RealtimeDBInstance: Identifiable, Sendable, Hashable {
    var id: String { instanceId }
    let name: String
    let instanceId: String
    let databaseUrl: String
    let region: String
    let type: String
    let state: String
}
