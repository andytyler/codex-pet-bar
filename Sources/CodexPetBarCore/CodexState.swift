import Foundation

public enum CodexGlobalState {
    public static func selectedPetID(from data: Data) throws -> String? {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let avatarID = object["selected-avatar-id"] as? String
        else {
            return nil
        }

        if avatarID.hasPrefix("custom:") {
            return String(avatarID.dropFirst("custom:".count))
        }

        if avatarID.isEmpty {
            return nil
        }

        return avatarID
    }
}

public enum PetSelection {
    public static func resolve(
        pets: [PetPackage],
        preferences: AppPreferences,
        codexSelectedPetID: String?
    ) -> PetPackage? {
        if
            preferences.followCodexPet,
            let codexSelectedPetID,
            let pet = pets.first(where: { $0.id == codexSelectedPetID })
        {
            return pet
        }

        if
            let overrideID = preferences.selectedPetIDOverride,
            let pet = pets.first(where: { $0.id == overrideID })
        {
            return pet
        }

        return pets.first
    }
}
