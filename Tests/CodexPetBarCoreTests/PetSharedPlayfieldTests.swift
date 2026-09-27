import Foundation
import Testing
@testable import CodexPetBarCore

@Suite("Shared pet playfield")
struct PetSharedPlayfieldTests {
    private let ids = ["alpha", "beta", "gamma", "delta"]

    @Test("initial standing pets fit without overlap and ignore participant ordering")
    func naturalInitialPlacement() {
        let participants = ids.map { PetSharedPlayfield.Participant(id: $0, moves: false) }
        var first = PetSharedPlayfield(participants: participants)
        var reordered = PetSharedPlayfield(participants: participants.reversed())
        let frames = first.step(deltaTime: 0, width: 220, spriteWidth: 24)
        let other = reordered.step(deltaTime: 0, width: 220, spriteWidth: 24)
        let positions = frames.map(\.x).sorted()

        #expect(byID(frames) == byID(other))
        #expect(frames.allSatisfy { !$0.isMoving && $0.x >= 0 && $0.x <= 196 })
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $1 - $0 >= 24 })
        #expect(Set(frames.map(\.facingRight)).count == 2)
    }

    @Test("working pets cross the shared width continuously with individual speeds")
    func fullWidthContinuousMotion() {
        var model = PetSharedPlayfield(participants: ids.map { .init(id: $0, moves: true) })
        var previous = byID(model.step(deltaTime: 0, width: 220, spriteWidth: 24))
        var minimum = previous.mapValues(\.x)
        var maximum = minimum
        var firstDistances: [Double] = []

        for tick in 0..<1_200 {
            let frames = model.step(deltaTime: 0.1, width: 220, spriteWidth: 24)
            for frame in frames {
                let displacement = abs(frame.x - previous[frame.id]!.x)
                #expect(displacement <= 2.800_001)
                #expect(frame.x >= 0 && frame.x <= 196)
                if tick == 0 { firstDistances.append(displacement) }
                minimum[frame.id] = min(minimum[frame.id]!, frame.x)
                maximum[frame.id] = max(maximum[frame.id]!, frame.x)
            }
            previous = byID(frames)
        }

        #expect(Set(firstDistances).count > 1)
        #expect(ids.allSatisfy { minimum[$0]! < 3 && maximum[$0]! > 193 })
    }

    @Test("pausing and refreshing participants preserves position direction and animation")
    func pauseAndResumeDoesNotTeleport() {
        var model = PetSharedPlayfield(participants: [.init(id: "alpha", moves: true)])
        _ = model.step(deltaTime: 0, width: 180, spriteWidth: 24)
        for _ in 0..<30 { _ = model.step(deltaTime: 0.1, width: 180, spriteWidth: 24) }
        let moving = model.step(deltaTime: 0, width: 180, spriteWidth: 24)[0]
        model.update(participants: [.init(id: "alpha", moves: false)])
        let paused = model.step(deltaTime: 10_000, width: 180, spriteWidth: 24)[0]

        #expect(paused.x == moving.x)
        #expect(paused.facingRight == moving.facingRight)
        #expect(paused.animationTime == moving.animationTime)
        #expect(!paused.isMoving)
        model.update(participants: [.init(id: "alpha", moves: true)])
        #expect(model.step(deltaTime: 0, width: 180, spriteWidth: 24)[0] == moving)
        let resumed = model.step(deltaTime: 0.1, width: 180, spriteWidth: 24)[0]
        #expect(abs(resumed.x - moving.x) <= 2.800_001)
        #expect(resumed.animationTime > moving.animationTime)
    }

    @Test("reordering an existing group cannot move or reverse its pets")
    func refreshPreservesIdentity() {
        let participants = ids.map { PetSharedPlayfield.Participant(id: $0, moves: true) }
        var model = PetSharedPlayfield(participants: participants)
        let before = model.step(deltaTime: 0.1, width: 220, spriteWidth: 24)
        model.update(participants: participants.reversed())
        let after = model.step(deltaTime: 0, width: 220, spriteWidth: 24)

        #expect(byID(before) == byID(after))
        #expect(after.map(\.id) == ids.reversed())
    }

    @Test("resize clamps instead of redistributing surviving pets")
    func resizingOnlyClamps() {
        var model = PetSharedPlayfield(participants: ids.map { .init(id: $0, moves: false) })
        let before = byID(model.step(deltaTime: 0, width: 220, spriteWidth: 24))
        let shrunk = model.step(deltaTime: 0, width: 80, spriteWidth: 24)

        for frame in shrunk {
            #expect(frame.x == min(before[frame.id]!.x, 56))
            #expect(frame.facingRight == before[frame.id]!.facingRight)
        }
        #expect(model.step(deltaTime: 0, width: 300, spriteWidth: 24) == shrunk)
    }

    @Test("wake and invalid deltas cannot advance more than one capped step")
    func deltaSafety() {
        var delayed = PetSharedPlayfield(participants: [.init(id: "alpha", moves: true)])
        _ = delayed.step(deltaTime: 0, width: 180, spriteWidth: 24)
        var ordinary = delayed
        #expect(delayed.step(deltaTime: 5_000, width: 180, spriteWidth: 24)
            == ordinary.step(deltaTime: PetSharedPlayfield.maximumDeltaTime, width: 180, spriteWidth: 24))
        let frozen = delayed.step(deltaTime: 0, width: 180, spriteWidth: 24)
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            #expect(delayed.step(deltaTime: invalid, width: 180, spriteWidth: 24) == frozen)
        }
    }

    @Test("narrow or empty fields remain finite and bounded")
    func narrowFieldsAreSafe() {
        var model = PetSharedPlayfield(participants: ids.map { .init(id: $0, moves: true) })
        let noTravel = model.step(deltaTime: 0.1, width: 20, spriteWidth: 24)
        #expect(noTravel.allSatisfy { $0.x == 0 && !$0.isMoving })
        for _ in 0..<10 {
            let narrow = model.step(deltaTime: 0.1, width: 24.001, spriteWidth: 24)
            #expect(narrow.allSatisfy { $0.x.isFinite && $0.x >= 0 && $0.x <= 0.001_001 })
        }
        #expect(model.step(deltaTime: 0.1, width: .nan, spriteWidth: 24).allSatisfy { $0.x == 0 })
        model.update(participants: [])
        #expect(model.step(deltaTime: 0.1, width: 220, spriteWidth: 24).isEmpty)
    }

    @Test("joining a pet preserves existing positions and uses available clear space")
    func newParticipantUsesFreeSpace() {
        var model = PetSharedPlayfield(participants: [.init(id: "alpha", moves: false)])
        let original = model.step(deltaTime: 0, width: 220, spriteWidth: 24)[0]
        model.update(participants: [.init(id: "alpha", moves: false), .init(id: "beta", moves: false)])
        let joined = byID(model.step(deltaTime: 0, width: 220, spriteWidth: 24))

        #expect(joined["alpha"] == original)
        #expect(abs(joined["beta"]!.x - original.x) >= 24)
    }

    @Test("an initial zero-width layout does not leave standing pets stacked after layout")
    func placementWaitsForUsableWidth() {
        let participants = ids.map { PetSharedPlayfield.Participant(id: $0, moves: false) }
        var initiallyHidden = PetSharedPlayfield(participants: participants)
        var directlySized = initiallyHidden
        #expect(initiallyHidden.step(deltaTime: 0, width: 0, spriteWidth: 24).count == ids.count)
        #expect(initiallyHidden.step(deltaTime: 0, width: 220, spriteWidth: 24)
            == directlySized.step(deltaTime: 0, width: 220, spriteWidth: 24))
    }

    @Test("preview pets settle overlapping runs once and remain independently visible when idle")
    func previewStopSettlesAndFreezes() {
        let previewIDs = ["codex:approve-release", "claude:review-settings", "cursor:keyboard-check", "codex:task-sidebar"]
        var model = PetSharedPlayfield(participants: previewIDs.map { .init(id: $0, moves: true) })
        _ = model.step(deltaTime: 0, width: 176, spriteWidth: 32)
        for _ in 0..<144 { _ = model.step(deltaTime: 1.0 / 24, width: 176, spriteWidth: 32) }
        let moving = byID(model.step(deltaTime: 0, width: 176, spriteWidth: 32))
        let runningPositions = moving.values.map(\.x).sorted()
        #expect(zip(runningPositions, runningPositions.dropFirst()).contains { $1 - $0 < 32 })

        var reordered = model
        model.update(participants: previewIDs.map { .init(id: $0, moves: false) })
        reordered.update(participants: previewIDs.reversed().map { .init(id: $0, moves: false) })
        let stopped = byID(model.step(deltaTime: 0, width: 176, spriteWidth: 32))
        #expect(stopped == byID(reordered.step(deltaTime: 0, width: 176, spriteWidth: 32)))
        let positions = stopped.values.map(\.x).sorted()
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $1 - $0 >= 32 - 1e-8 })
        for frame in stopped.values {
            #expect(frame.x >= 0 && frame.x <= 144 && !frame.isMoving)
            #expect(frame.facingRight == moving[frame.id]!.facingRight)
            #expect(frame.animationTime == moving[frame.id]!.animationTime)
        }
        for _ in 0..<50 {
            model.update(participants: previewIDs.reversed().map { .init(id: $0, moves: false) })
            #expect(byID(model.step(deltaTime: 0.1, width: 176, spriteWidth: 32)) == stopped)
        }
    }

    @Test("stopping an already separated group leaves every position untouched")
    func separatedStopDoesNotRedistribute() {
        var model = PetSharedPlayfield(participants: ids.map { .init(id: $0, moves: true) })
        let before = byID(model.step(deltaTime: 0, width: 220, spriteWidth: 24))
        model.update(participants: ids.map { .init(id: $0, moves: false) })
        for frame in model.step(deltaTime: 0, width: 220, spriteWidth: 24) {
            #expect(frame.x == before[frame.id]!.x)
            #expect(frame.facingRight == before[frame.id]!.facingRight)
            #expect(frame.animationTime == before[frame.id]!.animationTime)
        }
    }

    @Test("an impossible standing group remains bounded and settles when space becomes available")
    func pendingSettleWaitsForSpace() {
        var model = PetSharedPlayfield(participants: ids.map { .init(id: $0, moves: true) })
        _ = model.step(deltaTime: 0.1, width: 60, spriteWidth: 24)
        model.update(participants: ids.map { .init(id: $0, moves: false) })
        let small = model.step(deltaTime: 0, width: 60, spriteWidth: 24)
        #expect(small.allSatisfy { $0.x >= 0 && $0.x <= 36 })
        let settled = model.step(deltaTime: 0, width: 220, spriteWidth: 24)
        let positions = settled.map(\.x).sorted()
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $1 - $0 >= 24 - 1e-8 })
        #expect(model.step(deltaTime: 100, width: 220, spriteWidth: 24) == settled)
    }

    private func byID(_ frames: [PetSharedPlayfield.Frame]) -> [String: PetSharedPlayfield.Frame] {
        Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
    }
}
