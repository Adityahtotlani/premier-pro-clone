import Foundation

public enum ProjectFactory {
    public static func starterProject(name: String, fps: Double = 30) -> Project {
        let videoTrack = TimelineTrack(name: "V1", kind: .video)
        let audioTrack = TimelineTrack(name: "A1", kind: .audio)

        let sequence = EditorSequence(
            name: "Main Sequence",
            mode: .track,
            duration: 0,
            videoTracks: [videoTrack],
            audioTracks: [audioTrack]
        )

        let bin = MediaBin(name: "Imported")

        return Project(
            name: name,
            fps: fps,
            sequences: [sequence],
            bins: [bin]
        )
    }
}
