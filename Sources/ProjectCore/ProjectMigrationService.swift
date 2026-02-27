import Foundation

public struct ProjectMigrationService {
    public init() {}

    public func migrateIfNeeded(data: Data) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectStoreError.invalidProjectData
        }

        var schemaVersion = json["schemaVersion"] as? Int ?? 1
        if schemaVersion > Project.currentSchemaVersion {
            throw ProjectStoreError.unsupportedSchema(schemaVersion)
        }

        var migrationLog = (json["metadata"] as? [String: Any])?["migrationLog"] as? [[String: Any]] ?? []

        while schemaVersion < Project.currentSchemaVersion {
            let fromVersion = schemaVersion
            switch schemaVersion {
            case 1:
                migrateV1toV2(&json)
                schemaVersion = 2
            case 2:
                migrateV2toV3(&json)
                schemaVersion = 3
            default:
                throw ProjectStoreError.unsupportedSchema(schemaVersion)
            }

            migrationLog.append([
                "fromVersion": fromVersion,
                "toVersion": schemaVersion,
                "migratedAt": ISO8601DateFormatter().string(from: Date())
            ])
        }

        json["schemaVersion"] = schemaVersion
        var metadata = json["metadata"] as? [String: Any] ?? [:]
        metadata["migrationLog"] = migrationLog

        if metadata["createdAt"] == nil {
            metadata["createdAt"] = ISO8601DateFormatter().string(from: Date())
        }
        metadata["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        json["metadata"] = metadata

        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    private func migrateV1toV2(_ json: inout [String: Any]) {
        if let frameRate = json.removeValue(forKey: "frameRate") {
            json["fps"] = frameRate
        }

        guard var sequences = json["sequences"] as? [[String: Any]] else {
            return
        }

        for index in sequences.indices {
            if let timelineMode = sequences[index].removeValue(forKey: "timelineMode") {
                sequences[index]["mode"] = timelineMode
            }
            if sequences[index]["captionTracks"] == nil {
                sequences[index]["captionTracks"] = []
            }
        }

        json["sequences"] = sequences
    }

    private func migrateV2toV3(_ json: inout [String: Any]) {
        if json["assets"] == nil {
            json["assets"] = []
        }

        if json["settings"] == nil {
            json["settings"] = [
                "autosaveIntervalSeconds": 30,
                "audioDuckingPresetEnabled": true,
                "defaultQualityMode": "full"
            ]
        }

        if json["colorSpace"] == nil {
            json["colorSpace"] = "Rec.709"
        }
    }
}
