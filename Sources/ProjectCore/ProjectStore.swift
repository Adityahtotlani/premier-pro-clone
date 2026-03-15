import Foundation

public enum ProjectStoreError: Error, LocalizedError {
    case missingProjectFile(URL)
    case invalidProjectData
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .missingProjectFile(let url):
            return "Project file not found at \(url.path())"
        case .invalidProjectData:
            return "Project data is invalid or unreadable"
        case .unsupportedSchema(let version):
            return "Unsupported schema version \(version)"
        }
    }
}

public struct ProjectPaths: Sendable {
    public let bundleURL: URL
    public let projectFileURL: URL
    public let autosavesDirectoryURL: URL
    public let cacheDirectoryURL: URL

    public init(bundleURL: URL) {
        self.bundleURL = bundleURL
        self.projectFileURL = bundleURL.appendingPathComponent("project.json", isDirectory: false)
        self.autosavesDirectoryURL = bundleURL.appendingPathComponent("autosaves", isDirectory: true)
        self.cacheDirectoryURL = bundleURL.appendingPathComponent("cache", isDirectory: true)
    }
}

public final class ProjectStore {
    private let fileManager: FileManager
    private let migrationService: ProjectMigrationService
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        migrationService: ProjectMigrationService = ProjectMigrationService()
    ) {
        self.fileManager = fileManager
        self.migrationService = migrationService

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func createProjectBundle(at bundleURL: URL, with project: Project) throws {
        let paths = ProjectPaths(bundleURL: bundleURL)

        try fileManager.createDirectory(at: paths.bundleURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.autosavesDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.cacheDirectoryURL, withIntermediateDirectories: true)

        try save(project: project, to: bundleURL)
    }

    public func save(project: Project, to bundleURL: URL) throws {
        let paths = ProjectPaths(bundleURL: bundleURL)
        let updatedProject = withUpdatedMetadata(project)
        let data = try encoder.encode(updatedProject)

        if !fileManager.fileExists(atPath: paths.bundleURL.path()) {
            try fileManager.createDirectory(at: paths.bundleURL, withIntermediateDirectories: true)
        }

        try data.write(to: paths.projectFileURL, options: .atomic)
    }

    public func autosave(project: Project, to bundleURL: URL) throws -> URL {
        let paths = ProjectPaths(bundleURL: bundleURL)
        if !fileManager.fileExists(atPath: paths.autosavesDirectoryURL.path()) {
            try fileManager.createDirectory(at: paths.autosavesDirectoryURL, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let autosaveURL = paths.autosavesDirectoryURL.appendingPathComponent("autosave-\(timestamp).json")
        let updatedProject = withUpdatedMetadata(project)
        let data = try encoder.encode(updatedProject)
        try data.write(to: autosaveURL, options: .atomic)
        return autosaveURL
    }

    public func load(from bundleURL: URL) throws -> Project {
        let paths = ProjectPaths(bundleURL: bundleURL)
        guard fileManager.fileExists(atPath: paths.projectFileURL.path()) else {
            throw ProjectStoreError.missingProjectFile(paths.projectFileURL)
        }

        let rawData = try Data(contentsOf: paths.projectFileURL)
        let migratedData = try migrationService.migrateIfNeeded(data: rawData)

        guard let project = try? decoder.decode(Project.self, from: migratedData) else {
            throw ProjectStoreError.invalidProjectData
        }

        return project
    }

    public func latestAutosaveURL(from bundleURL: URL) throws -> URL? {
        let paths = ProjectPaths(bundleURL: bundleURL)
        guard fileManager.fileExists(atPath: paths.autosavesDirectoryURL.path()) else {
            return nil
        }

        let autosaves = try fileManager.contentsOfDirectory(
            at: paths.autosavesDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )

        return try autosaves
            .filter { $0.pathExtension.lowercased() == "json" }
            .max { lhs, rhs in
                let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                return lhsDate < rhsDate
            }
    }

    public func recoverLatestAutosave(from bundleURL: URL) throws -> Project? {
        let latest = try latestAutosaveURL(from: bundleURL)
        guard let latest else {
            return nil
        }

        let data = try Data(contentsOf: latest)
        let migratedData = try migrationService.migrateIfNeeded(data: data)
        return try decoder.decode(Project.self, from: migratedData)
    }

    private func withUpdatedMetadata(_ project: Project) -> Project {
        var mutable = project
        mutable.metadata.updatedAt = Date()
        mutable.schemaVersion = Project.currentSchemaVersion
        return mutable
    }
}
