import Foundation

public final class AppPreferences {
    private enum Key {
        static let followCodexPet = "followCodexPet"
        static let selectedPetIDOverride = "selectedPetIDOverride"
        static let petSize = "petSize"
        static let manualAnimationState = "manualAnimationState"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var followCodexPet: Bool {
        get {
            if defaults.object(forKey: Key.followCodexPet) == nil {
                return true
            }
            return defaults.bool(forKey: Key.followCodexPet)
        }
        set {
            defaults.set(newValue, forKey: Key.followCodexPet)
        }
    }

    public var selectedPetIDOverride: String? {
        get {
            defaults.string(forKey: Key.selectedPetIDOverride)
        }
        set {
            defaults.setOptionalString(newValue, forKey: Key.selectedPetIDOverride)
        }
    }

    public var petSize: PetSize {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.petSize),
                let size = PetSize(rawValue: rawValue)
            else {
                return .medium
            }
            return size
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.petSize)
        }
    }

    public var manualAnimationState: PetAnimationState? {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.manualAnimationState),
                let state = PetAnimationState(rawValue: rawValue)
            else {
                return nil
            }
            return state
        }
        set {
            defaults.setOptionalString(newValue?.rawValue, forKey: Key.manualAnimationState)
        }
    }
}

private extension UserDefaults {
    func setOptionalString(_ value: String?, forKey key: String) {
        if let value {
            set(value, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
