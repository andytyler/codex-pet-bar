# frozen_string_literal: true

# Run with `brew ruby script/audit_cask.rb /absolute/path/to/codex-pet-bar.rb`.
# `brew audit` accepts installed tokens only on newer Homebrew versions. Loading
# these explicit source bytes prevents an older installed tap from being audited.
require "cask/cask_loader"
require "cask/auditor"

abort "Usage: brew ruby script/audit_cask.rb <cask.rb>" unless ARGV.length == 1
path = Pathname(ARGV.fetch(0)).expand_path
abort "Missing cask: #{path}" unless path.file?
cask = Cask::CaskLoader::FromContentLoader.new(path.read).load(config: nil)
abort "Expected codex-pet-bar, found #{cask.token}" unless cask.token == "codex-pet-bar"
puts "Auditing #{path}: version=#{cask.version}, sha256=#{cask.sha256}"
# This is an update of a fixed, existing token. Rechecking its name against the
# global catalogue can auto-install homebrew/core; keep this validation local.
errors = Cask::Auditor.audit(cask, any_named_args: true, quarantine: true,
                           audit_online: false, audit_signing: false,
                           except: ["token_conflicts"])
exit 1 unless errors.empty?
puts "Exact staged cask content audit passed (existing token catalogue check omitted)."
