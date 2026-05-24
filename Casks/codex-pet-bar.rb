cask "codex-pet-bar" do
  version "0.1.0"
  sha256 "09f18185cd2720333a017e413357595b75b561b87ec9968b85eaaecf40483a18"

  url "https://github.com/andytyler/codex-pet-bar/releases/download/v#{version}/CodexPetBar-#{version}-macos.zip",
      verified: "github.com/andytyler/codex-pet-bar/"
  name "CodexPetBar"
  desc "Menu bar companion for Codex pets"
  homepage "https://github.com/andytyler/codex-pet-bar"

  depends_on macos: :sonoma

  app "CodexPetBar.app"
  binary "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-bar"
  binary "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-install-hooks"
  binary "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-install-pet"
  binary "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-validate-pet"

  zap trash: "~/Library/Preferences/dev.ajt.CodexPetBar.plist"

  caveats <<~EOS
    Start CodexPetBar:
      codex-pet-bar

    Install global Codex activity hooks:
      codex-pet-bar --add-codex-hooks

    Install workspace-local hooks, or install and validate custom pets:
      codex-pet-install-hooks --workspace /path/to/workspace
      codex-pet-install-pet /path/to/pet
      codex-pet-validate-pet /path/to/pet

    Pets live in:
      ~/.codex/pets
  EOS
end
