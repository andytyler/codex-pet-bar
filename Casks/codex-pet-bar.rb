cask "codex-pet-bar" do
  version "0.1.2"
  sha256 "ffdf524ed1fadab89947ec8cd523c4f1dff4f61b9569bb590df70a4b3e8f8302"

  url "https://github.com/andytyler/codex-pet-bar/releases/download/v#{version}/CodexPetBar-#{version}-macos.zip"
  name "CodexPetBar"
  desc "Menu bar companion for Codex pets"
  homepage "https://github.com/andytyler/codex-pet-bar"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "CodexPetBar.app"
  binary "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-bar"
  binary "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-install-hooks"
  binary "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-install-pet"
  binary "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-validate-pet"

  uninstall script: {
    executable: "#{appdir}/CodexPetBar.app/Contents/SharedSupport/bin/codex-pet-install-hooks",
    args: ["--provider", "all", "--remove-global"],
    must_succeed: false,
  }

  zap trash: "~/Library/Preferences/dev.ajt.CodexPetBar.plist"

  caveats <<~EOS
    Start CodexPetBar:
      codex-pet-bar

    Install activity hooks for Codex, Claude Code, and Cursor:
      codex-pet-bar --add-hooks --provider all
    Remove activity hooks for all providers:
      codex-pet-install-hooks --provider all --remove-global

    Install workspace-local hooks, or install and validate custom pets:
      codex-pet-install-hooks --workspace /path/to/workspace
      codex-pet-install-hooks --remove-workspace /path/to/workspace
      codex-pet-install-pet /path/to/pet
      codex-pet-validate-pet /path/to/pet

    Pets live in $CODEX_HOME/pets (default):
      ~/.codex/pets
  EOS
end
