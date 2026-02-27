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
    public init() {}

    public func `import`(urls: [URL]) -> MediaImportResult {
        var assets: [MediaAsset] = []
        var warnings: [String] = []

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path()) else {
                warnings.append("Missing file at \(url.path())")
                continue
            }

            let inferredType = inferAssetType(url: url)
            let duration = loadDuration(url: url)
            let asset = MediaAsset(
                name: url.deletingPathExtension().lastPathComponent,
                path: url.path(),
                type: inferredType,
                duration: duration
            )
            assets.append(asset)
        }

        return MediaImportResult(importedAssets: assets, warnings: warnings)
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
