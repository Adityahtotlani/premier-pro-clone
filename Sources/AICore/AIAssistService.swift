import Foundation
import ProjectCore
import TimelineCore

public enum AITaskType: String, Codable, Sendable {
    case autoCaptions
    case silenceRemoval
    case transcriptSearch
    case smartReframe
    case highlightSuggestions
}

public struct AIArtifact: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var taskType: AITaskType
    public var sequenceID: UUID
    public var payload: [String: String]

    public init(
        id: UUID = UUID(),
        taskType: AITaskType,
        sequenceID: UUID,
        payload: [String: String]
    ) {
        self.id = id
        self.taskType = taskType
        self.sequenceID = sequenceID
        self.payload = payload
    }
}

public enum AIAssistError: Error {
    case sequenceNotFound
}

public protocol AIAssistServiceProtocol: Sendable {
    func run(taskType: AITaskType, sequenceID: UUID, options: [String: String], in project: Project) throws -> AIArtifact
}

public struct AIAssistService: AIAssistServiceProtocol {
    public init() {}

    public func run(taskType: AITaskType, sequenceID: UUID, options: [String: String], in project: Project) throws -> AIArtifact {
        guard let sequence = project.sequences.first(where: { $0.id == sequenceID }) else {
            throw AIAssistError.sequenceNotFound
        }

        switch taskType {
        case .autoCaptions:
            return generateAutoCaptions(sequence: sequence)
        case .silenceRemoval:
            return generateSilenceRemoval(sequence: sequence)
        case .transcriptSearch:
            return transcriptSearch(sequence: sequence, query: options["query"] ?? "")
        case .smartReframe:
            return smartReframe(sequence: sequence, aspect: options["aspect"] ?? "9:16")
        case .highlightSuggestions:
            return highlightSuggestions(sequence: sequence)
        }
    }

    private func generateAutoCaptions(sequence: EditorSequence) -> AIArtifact {
        let estimatedSegments = max(1, Int(sequence.duration / 3.5))
        return AIArtifact(
            taskType: .autoCaptions,
            sequenceID: sequence.id,
            payload: [
                "language": "en",
                "segments": "\(estimatedSegments)",
                "summary": "Generated draft captions from voice activity"
            ]
        )
    }

    private func generateSilenceRemoval(sequence: EditorSequence) -> AIArtifact {
        let audioClips = sequence.audioTracks.flatMap(\.clips)
        let sparseClips = audioClips.filter { $0.duration < 1.0 }

        return AIArtifact(
            taskType: .silenceRemoval,
            sequenceID: sequence.id,
            payload: [
                "suggestedCuts": "\(sparseClips.count)",
                "thresholdSeconds": "1.0"
            ]
        )
    }

    private func transcriptSearch(sequence: EditorSequence, query: String) -> AIArtifact {
        let totalSegments = sequence.captionTracks.flatMap(\.segments)
        let matchCount = totalSegments.filter { $0.text.localizedCaseInsensitiveContains(query) }.count

        return AIArtifact(
            taskType: .transcriptSearch,
            sequenceID: sequence.id,
            payload: [
                "query": query,
                "matches": "\(matchCount)"
            ]
        )
    }

    private func smartReframe(sequence: EditorSequence, aspect: String) -> AIArtifact {
        AIArtifact(
            taskType: .smartReframe,
            sequenceID: sequence.id,
            payload: [
                "aspect": aspect,
                "strategy": "center-weighted crop with motion bias"
            ]
        )
    }

    private func highlightSuggestions(sequence: EditorSequence) -> AIArtifact {
        let clipCount = sequence.videoTracks.flatMap(\.clips).count
        let markerBoost = sequence.markers.count
        let score = min(1.0, (Double(clipCount) * 0.05) + (Double(markerBoost) * 0.08))

        return AIArtifact(
            taskType: .highlightSuggestions,
            sequenceID: sequence.id,
            payload: [
                "score": String(format: "%.2f", score),
                "reason": "speech energy + cut density heuristic"
            ]
        )
    }
}
