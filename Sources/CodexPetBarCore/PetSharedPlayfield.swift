import Foundation

/// Small, deterministic motion for companions sharing one horizontal playfield.
/// Positions are sprite left edges. The caller supplies elapsed time; zero time
/// freezes motion without resetting direction or animation. Newly standing
/// groups settle once if their sprites overlap, then keep their positions.
public struct PetSharedPlayfield: Sendable {
    public struct Participant: Equatable, Identifiable, Sendable {
        public let id: String
        public let moves: Bool

        public init(id: String, moves: Bool) {
            self.id = id
            self.moves = moves
        }
    }

    public struct Frame: Equatable, Identifiable, Sendable {
        public let id: String
        public let x: Double
        public let facingRight: Bool
        public let isMoving: Bool
        public let animationTime: TimeInterval
    }

    /// Limits catch-up after a delayed frame or wake to an ordinary small step.
    public static let maximumDeltaTime: TimeInterval = 0.1
    private var participants: [Participant] = []
    private var states: [String: MotionState] = [:]
    private var pendingIdleSettle = false

    public init(participants: [Participant] = []) {
        update(participants: participants)
    }

    /// Existing participants keep their motion state, even when reordered or
    /// paused. Removed IDs are discarded, keeping storage bounded to this group.
    public mutating func update(participants: [Participant]) {
        let previousStanding = Set(self.participants.filter { !$0.moves }.map(\.id))
        var seen = Set<String>()
        self.participants = participants.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        let standing = Set(self.participants.filter { !$0.moves }.map(\.id))
        pendingIdleSettle = pendingIdleSettle || standing != previousStanding
        states = states.filter { seen.contains($0.key) }
        for participant in self.participants where states[participant.id] == nil {
            states[participant.id] = MotionState(seed: Self.stableHash(participant.id))
        }
    }

    /// Each moving pet traverses the entire available width, reflecting only at
    /// its outer edges. Pets may pass one another; there are no permanent slots.
    public mutating func step(
        deltaTime: TimeInterval,
        width: Double,
        spriteWidth: Double
    ) -> [Frame] {
        let width = width.isFinite ? max(0, width) : 0
        let spriteWidth = spriteWidth.isFinite ? max(0, spriteWidth) : 0
        let maximumX = max(0, width - spriteWidth)
        let elapsed = deltaTime.isFinite ? min(max(0, deltaTime), Self.maximumDeltaTime) : 0

        for id in states.keys {
            if let x = states[id]?.x { states[id]?.x = min(max(0, x), maximumX) }
        }
        if maximumX > 0 {
            placeNewParticipants(width: width, spriteWidth: spriteWidth, maximumX: maximumX)
        }
        if pendingIdleSettle { settleStandingParticipants(width: width, spriteWidth: spriteWidth) }

        return participants.compactMap { participant in
            guard var state = states[participant.id] else { return nil }
            let x = state.x ?? 0
            let moving = participant.moves && maximumX > 0
            if moving, elapsed > 0 {
                let distance = state.speed * elapsed
                // Express a round trip as a forward phase, so a narrow field
                // can reflect several times in one tick without a loop.
                let period = 2 * maximumX
                if period.isFinite {
                    let phase = state.facingRight ? x : period - x
                    let advanced = (phase + distance).truncatingRemainder(dividingBy: period)
                    state.x = advanced <= maximumX ? advanced : period - advanced
                    state.facingRight = advanced < maximumX
                } else {
                    // Finite but enormous caller dimensions cannot form a
                    // finite round-trip period; a single bounded step suffices.
                    let next = x + (state.facingRight ? distance : -distance)
                    state.x = min(max(0, next), maximumX)
                    if next >= maximumX { state.facingRight = false }
                    if next <= 0 { state.facingRight = true }
                }
                state.animationTime += elapsed
                states[participant.id] = state
            }
            return Frame(id: participant.id, x: state.x ?? 0, facingRight: state.facingRight,
                         isMoving: moving, animationTime: state.animationTime)
        }
    }

    private mutating func placeNewParticipants(width: Double, spriteWidth: Double, maximumX: Double) {
        let newIDs = participants.map(\.id).filter { states[$0]?.x == nil }.sorted { left, right in
            let leftFraction = states[left]?.placementFraction ?? 0
            let rightFraction = states[right]?.placementFraction ?? 0
            return leftFraction == rightFraction ? left < right : leftFraction < rightFraction
        }
        guard !newIDs.isEmpty else { return }
        var placed = states.values.compactMap(\.x)

        if placed.isEmpty {
            let count = Double(newIDs.count)
            let fits = count * spriteWidth <= width
            let slack = max(0, width - count * spriteWidth)
            let gap = count > 1 ? min(3, slack / (count - 1)) : 0
            let looseSpace = max(0, slack - gap * max(0, count - 1))
            for (index, id) in newIDs.enumerated() {
                let fraction = states[id]?.placementFraction ?? 0.5
                // Sorted random gaps give a natural initial arrangement while
                // guaranteeing no overlap whenever the group fits at all.
                let x = fits
                    ? Double(index) * (spriteWidth + gap) + fraction * looseSpace
                    : maximumX * Double(index) / max(1, count - 1)
                states[id]?.x = min(x, maximumX)
            }
            return
        }

        for id in newIDs {
            var cursor = 0.0
            var gaps: [(start: Double, length: Double)] = []
            for x in placed.sorted() {
                if x - cursor >= spriteWidth { gaps.append((cursor, x - cursor)) }
                cursor = max(cursor, x + spriteWidth)
            }
            if width - cursor >= spriteWidth { gaps.append((cursor, width - cursor)) }
            let fraction = states[id]?.placementFraction ?? 0.5
            let gap = gaps.max { $0.length < $1.length }
            let x = gap.map { $0.start + fraction * max(0, $0.length - spriteWidth) }
                ?? fraction * maximumX
            states[id]?.x = min(max(0, x), maximumX)
            placed.append(x)
        }
    }

    private mutating func settleStandingParticipants(width: Double, spriteWidth: Double) {
        let standing = participants.filter { !$0.moves }.map(\.id).sorted {
            let left = states[$0]?.x ?? 0
            let right = states[$1]?.x ?? 0
            return left == right ? $0 < $1 : left < right
        }
        guard standing.count > 1 else { pendingIdleSettle = false; return }
        // Keep this pending when the field is too small or not laid out yet.
        guard Double(standing.count) * spriteWidth <= width,
              standing.allSatisfy({ states[$0]?.x != nil }) else { return }
        let positions = standing.map { states[$0]!.x! }
        guard zip(positions, positions.dropFirst()).contains(where: { $1 - $0 < spriteWidth }) else {
            pendingIdleSettle = false
            return
        }

        // Subtract sprite widths to pack only overlapping neighbors. Merging
        // adjacent out-of-order blocks gives the nearest standing positions
        // while preserving their left-to-right identity order.
        var blocks: [(start: Int, end: Int, mean: Double)] = []
        for (index, x) in positions.enumerated() {
            blocks.append((index, index, x - Double(index) * spriteWidth))
            while blocks.count > 1, blocks[blocks.count - 2].mean > blocks[blocks.count - 1].mean {
                let right = blocks.removeLast()
                let left = blocks.removeLast()
                let leftCount = Double(left.end - left.start + 1)
                let rightCount = Double(right.end - right.start + 1)
                let mean = left.mean + (right.mean - left.mean) * rightCount / (leftCount + rightCount)
                blocks.append((left.start, right.end, mean))
            }
        }
        let slack = width - Double(standing.count) * spriteWidth
        for block in blocks {
            let offset = min(max(0, block.mean), slack)
            // An isolated, already separated pet retains its exact position.
            if block.start == block.end, offset == block.mean { continue }
            for index in block.start...block.end {
                states[standing[index]]?.x = offset + Double(index) * spriteWidth
            }
        }
        pendingIdleSettle = false
    }

    private struct MotionState: Sendable {
        var x: Double?
        var facingRight: Bool
        let speed: Double
        let placementFraction: Double
        var animationTime: TimeInterval

        init(seed: UInt64) {
            facingRight = seed & 1 == 0
            speed = 16 + Double(seed % 997) / 997 * 12
            placementFraction = Double((seed >> 17) % 1_009) / 1_009
            animationTime = Double((seed >> 32) % 1_000) / 1_000
        }
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
