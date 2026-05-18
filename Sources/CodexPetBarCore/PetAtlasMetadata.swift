public struct AnimationRowMetadata: Equatable, Sendable {
    public let state: PetAnimationState
    public let rowIndex: Int
    public let usedColumns: [Int]
    public let frameDurationsMS: [Int]

    public init(
        state: PetAnimationState,
        rowIndex: Int,
        usedColumns: [Int],
        frameDurationsMS: [Int]
    ) {
        self.state = state
        self.rowIndex = rowIndex
        self.usedColumns = usedColumns
        self.frameDurationsMS = frameDurationsMS
    }
}

public enum PetAtlasMetadata {
    public static let columns = 8
    public static let rows = 9
    public static let cellWidth = 192
    public static let cellHeight = 208

    public static let animationRows: [AnimationRowMetadata] = [
        AnimationRowMetadata(
            state: .idle,
            rowIndex: 0,
            usedColumns: Array(0...5),
            frameDurationsMS: [280, 110, 110, 140, 140, 320]
        ),
        AnimationRowMetadata(
            state: .runningRight,
            rowIndex: 1,
            usedColumns: Array(0...7),
            frameDurationsMS: [120, 120, 120, 120, 120, 120, 120, 220]
        ),
        AnimationRowMetadata(
            state: .runningLeft,
            rowIndex: 2,
            usedColumns: Array(0...7),
            frameDurationsMS: [120, 120, 120, 120, 120, 120, 120, 220]
        ),
        AnimationRowMetadata(
            state: .waving,
            rowIndex: 3,
            usedColumns: Array(0...3),
            frameDurationsMS: [140, 140, 140, 280]
        ),
        AnimationRowMetadata(
            state: .jumping,
            rowIndex: 4,
            usedColumns: Array(0...4),
            frameDurationsMS: [140, 140, 140, 140, 280]
        ),
        AnimationRowMetadata(
            state: .failed,
            rowIndex: 5,
            usedColumns: Array(0...7),
            frameDurationsMS: [140, 140, 140, 140, 140, 140, 140, 240]
        ),
        AnimationRowMetadata(
            state: .waiting,
            rowIndex: 6,
            usedColumns: Array(0...5),
            frameDurationsMS: [150, 150, 150, 150, 150, 260]
        ),
        AnimationRowMetadata(
            state: .running,
            rowIndex: 7,
            usedColumns: Array(0...5),
            frameDurationsMS: [120, 120, 120, 120, 120, 220]
        ),
        AnimationRowMetadata(
            state: .review,
            rowIndex: 8,
            usedColumns: Array(0...5),
            frameDurationsMS: [150, 150, 150, 150, 150, 280]
        )
    ]

    public static let rowsByState: [PetAnimationState: AnimationRowMetadata] = {
        Dictionary(uniqueKeysWithValues: animationRows.map { ($0.state, $0) })
    }()
}
