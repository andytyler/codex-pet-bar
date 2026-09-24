import Foundation

public struct PetPackage: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let directoryURL: URL
    public let spritesheetURL: URL
    public let spriteVersionNumber: Int

    public init(
        id: String,
        displayName: String,
        description: String,
        directoryURL: URL,
        spritesheetURL: URL,
        spriteVersionNumber: Int = 1
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.directoryURL = directoryURL
        self.spritesheetURL = spritesheetURL
        self.spriteVersionNumber = spriteVersionNumber
    }
}

public enum PetSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var menuBarLength: Double {
        switch self {
        case .small:
            44
        case .medium:
            56
        case .large:
            102
        }
    }
}

public enum PetAnimationState: String, CaseIterable, Sendable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review
}

public enum CodexActivity: String, CaseIterable, Sendable {
    case idle
    case running
    case reviewing
    case listening
    case failed

    public var animationState: PetAnimationState {
        switch self {
        case .idle:
            .idle
        case .running:
            .running
        case .reviewing:
            .waiting
        case .listening:
            .idle
        case .failed:
            .failed
        }
    }
}
