import Foundation

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
    public static let v1Rows = 9
    public static let v2Rows = 11
    public static let rows = v1Rows
    public static let cellWidth = 192
    public static let cellHeight = 208
    public static let defaultDirectionalDeadzone = 0.01

    public struct DirectionalFrame: Equatable, Sendable {
        public let rowIndex: Int
        public let columnIndex: Int
        public let headingIndex: Int

        public init(rowIndex: Int, columnIndex: Int, headingIndex: Int) {
            self.rowIndex = rowIndex
            self.columnIndex = columnIndex
            self.headingIndex = headingIndex
        }
    }

    public static func rowCount(forSpriteVersionNumber spriteVersionNumber: Int) -> Int? {
        switch spriteVersionNumber {
        case 1:
            v1Rows
        case 2:
            v2Rows
        default:
            nil
        }
    }

    /// Maps an AppKit-style vector to the nearest v2 directional frame.
    ///
    /// Heading zero points up. Heading indices then advance clockwise in 22.5-degree
    /// sectors, filling row 9 before row 10. Exact sector boundaries choose the
    /// clockwise frame.
    public static func directionalFrame(
        x: Double,
        y: Double,
        deadzone: Double = defaultDirectionalDeadzone
    ) -> DirectionalFrame? {
        guard x.isFinite, y.isFinite, deadzone.isFinite, deadzone >= 0 else {
            return nil
        }

        let magnitudeSquared = x * x + y * y
        guard magnitudeSquared > deadzone * deadzone else {
            return nil
        }

        let headingCount = 16
        let sectorWidth = 2 * Double.pi / Double(headingCount)
        var clockwiseAngleFromUp = atan2(x, y)
        if clockwiseAngleFromUp < 0 {
            clockwiseAngleFromUp += 2 * Double.pi
        }

        let boundaryTolerance = Double.ulpOfOne * Double(headingCount)
        let headingIndex = Int(
            floor(clockwiseAngleFromUp / sectorWidth + 0.5 + boundaryTolerance)
        ) % headingCount

        return DirectionalFrame(
            rowIndex: 9 + headingIndex / columns,
            columnIndex: headingIndex % columns,
            headingIndex: headingIndex
        )
    }

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

    public static let slowIdleRow: AnimationRowMetadata = {
        let idle = rowsByState[.idle]!
        return AnimationRowMetadata(
            state: idle.state,
            rowIndex: idle.rowIndex,
            usedColumns: idle.usedColumns,
            frameDurationsMS: idle.frameDurationsMS.map { $0 * 6 }
        )
    }()

    public static func playbackRow(for state: PetAnimationState) -> AnimationRowMetadata? {
        state == .idle ? slowIdleRow : rowsByState[state]
    }
}
