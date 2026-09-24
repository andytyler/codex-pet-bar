import Foundation

/// Layout and idle-presentation policy shared by the native status renderer.
public enum PetMenuBarPresentation {
    public static func shouldSleep(
        activity: CodexActivity,
        activeTaskCount: Int,
        manualAnimationState: PetAnimationState?,
        hasReaction: Bool,
        hasAttention: Bool
    ) -> Bool {
        activity == .idle
            && activeTaskCount == 0
            && manualAnimationState == nil
            && !hasReaction
            && !hasAttention
    }

    /// Goblin, Grumble, and Mini Gandalf have a verified closed-eye pose at idle frame two.
    /// Other custom pets keep their first idle frame as a restful still pose;
    /// the atlas contract does not guarantee a closed-eye frame for every pet.
    public static func sleepingFrameIndex(petID: String?, frameCount: Int) -> Int {
        guard frameCount > 2, petID == "goblin" || petID == "grumble" || petID == "mini-gandalf-the-grey" else {
            return 0
        }
        return 2
    }

    public static let providerIconWidth: Double = 14
    public static let providerGap: Double = 5
    public static let providerLeadingGap: Double = 4

    /// A tightly fitted icon row; repeat tasks share their provider's mark.
    public static func providerWidth(count: Int) -> Double {
        let count = min(PetProvider.allCases.count, max(0, count))
        guard count > 0 else { return 0 }
        return providerLeadingGap + Double(count) * providerIconWidth + Double(count - 1) * providerGap
    }

    public static func contentWidth(petWidth: Double, providerCount: Int) -> Double {
        petWidth + providerWidth(count: providerCount)
    }

    public static let completionAccessoryWidth: Double = 44

    /// Reserve a modest runway only while work is running; keep the sprite's size unchanged.
    public static func petWidth(spriteWidth: Double, preferredWidth: Double, isRunning: Bool) -> Double {
        let compact = sleepingWidth(spriteWidth: spriteWidth)
        return isRunning ? max(compact, min(preferredWidth, 64)) : compact
    }

    /// Collapse unused playfield space without reducing the pet's rendered size.
    public static func sleepingWidth(spriteWidth: Double) -> Double {
        ceil(spriteWidth) + 4
    }
}
