import Foundation
import ProjectCore

#if canImport(AVFoundation)
import AVFoundation
#endif

public struct MediaImportResult: Equatable, Sendable {
    public var importedAssets: [MediaAsset]
    public var warnings: [String]

    public init(importedAssets: [MediaAsset], warnings: [String] = []) {
        self.importedAssets = importedAssets
        self.warnings = warnings
    }
}

public final class MediaImporter {
    private let fileManager: FileManager
    private let stagingRootURL: URL

    public init(
        fileManager: FileManager = .default,
        stagingRootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PremierCloneImports", isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.stagingRootURL = stagingRootURL
    }

    public func `import`(urls: [URL]) -> MediaImportResult {
        var assets: [MediaAsset] = []
        var warnings: [String] = []

        for url in urls {
            let sourceURL = url.standardizedFileURL
            guard fileManager.fileExists(atPath: sourceURL.path()) else {
                warnings.append("Missing file at \(sourceURL.path())")
                continue
            }

            let ingestURL = stageImportedFileIfNeeded(sourceURL, warnings: &warnings)
            let inferredType = inferAssetType(url: ingestURL)
            let duration = loadDuration(url: ingestURL)
            let asset = MediaAsset(
                name: sourceURL.deletingPathExtension().lastPathComponent,
                path: ingestURL.path(),
                type: inferredType,
                duration: duration
            )
            assets.append(asset)
        }

        return MediaImportResult(importedAssets: assets, warnings: warnings)
    }

    private func stageImportedFileIfNeeded(_ sourceURL: URL, warnings: inout [String]) -> URL {
        do {
            try ensureStagingDirectoryExists()
            let destinationURL = stagedDestination(for: sourceURL)

            if !fileManager.fileExists(atPath: destinationURL.path()) {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }

            return destinationURL
        } catch {
            warnings.append("Using original path for \(sourceURL.lastPathComponent): \(error.localizedDescription)")
            return sourceURL
        }
    }

    private func ensureStagingDirectoryExists() throws {
        if !fileManager.fileExists(atPath: stagingRootURL.path()) {
            try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
        }
    }

    private func stagedDestination(for sourceURL: URL) -> URL {
        let safeBase = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension.lowercased()
        let signature = sourceSignature(for: sourceURL)
        let filename = "\(safeBase)-\(signature).\(ext)"
        return stagingRootURL.appendingPathComponent(filename, isDirectory: false)
    }

    private func sourceSignature(for sourceURL: URL) -> String {
        let attributes = (try? fileManager.attributesOfItem(atPath: sourceURL.path())) ?? [:]
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(Int(modified))"
    }

    private func inferAssetType(url: URL) -> MediaAsset.AssetType {
        let ext = url.pathExtension.lowercased()
        if ["mov", "mp4", "m4v", "mkv"].contains(ext) {
            return .video
        }
        if ["wav", "mp3", "aac", "m4a"].contains(ext) {
            return .audio
        }
        if ["jpg", "jpeg", "png", "heic", "gif"].contains(ext) {
            return .image
        }
        return .unknown
    }

    private func loadDuration(url: URL) -> TimeInterval {
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: url)
        return asset.duration.seconds.isFinite ? max(0, asset.duration.seconds) : 0
        #else
        return 0
        #endif
    }
}

public struct ProxyRecord: Codable, Equatable, Sendable {
    public var sourceAssetID: UUID
    public var proxyPath: String
    public var generatedAt: Date

    public init(sourceAssetID: UUID, proxyPath: String, generatedAt: Date = Date()) {
        self.sourceAssetID = sourceAssetID
        self.proxyPath = proxyPath
        self.generatedAt = generatedAt
    }
}

public final class ProxyManager {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    public func createProxyManifest(for assets: [MediaAsset], in cacheDirectory: URL) throws -> URL {
        let proxiesDirectory = cacheDirectory.appendingPathComponent("proxies", isDirectory: true)
        if !fileManager.fileExists(atPath: proxiesDirectory.path()) {
            try fileManager.createDirectory(at: proxiesDirectory, withIntermediateDirectories: true)
        }

        let records = assets.map { asset in
            ProxyRecord(
                sourceAssetID: asset.id,
                proxyPath: proxiesDirectory.appendingPathComponent("\(asset.id.uuidString)-proxy.mov").path()
            )
        }

        let manifestURL = proxiesDirectory.appendingPathComponent("manifest.json", isDirectory: false)
        let data = try encoder.encode(records)
        try data.write(to: manifestURL, options: .atomic)
        return manifestURL
    }
}
