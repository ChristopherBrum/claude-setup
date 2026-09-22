#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse boundary hook (Write|Edit|Bash): keeps a subagent inside the checkout its
# session started in, derived from cwd so it holds for any project without naming one.
#
# Order: read-only agents get Write/Edit denied; a subagent inside a git checkout is
# confined to it plus SHARED_WRITABLE; a top-level session is untouched.
#
# Write/Edit confinement is hard, since the target path is resolved before comparison.
# Bash confinement is soft because only the command string is visible: it denies absolute
# paths into another checkout, but a bare relative command in the inherited cwd gets
# through. Peer reads are expected to go through git remote names, which carry no paths.

require 'json'
require 'pathname'

HOME = Dir.home

# Without this carve-out an agent's own notes write is denied, which surfaces as a
# mysterious failure rather than a clear boundary error.
SHARED_WRITABLE = [
  "#{HOME}/.claude/repos",
  "#{HOME}/.claude/projects",
  "#{HOME}/.claude/scratch",
  '/tmp',
  '/private/tmp'
].freeze

READ_ONLY_AGENTS = %w[architect explorer qa-engineer reviewer].freeze
WRITE_TOOLS = %w[Write Edit MultiEdit NotebookEdit].freeze

# Opt-in extra checkouts for work that genuinely spans two repos, from identity.json:
# { "git": { "sibling_repos": ["some-other-repo"] } } — absolute, or relative to code_dir.
def sibling_repos
  identity = File.join(HOME, '.claude', 'identity.json')
  return [] unless File.exist?(identity)

  config = JSON.parse(File.read(identity))
  code_dir = File.expand_path((config['code_dir'] || '~/Documents').sub(/\A~/, HOME))
  Array(config.dig('git', 'sibling_repos')).map do |repo|
    repo.start_with?('/') ? repo : File.join(code_dir, repo)
  end
rescue StandardError
  []
end

def deny(reason)
  puts JSON.generate(
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason
    }
  )
  exit 0
end

# `.git` is a directory in a clone and a file in a worktree, so both count.
def project_root(dir)
  Pathname.new(dir).ascend do |path|
    return path.to_s if (path + '.git').exist?
  end
  nil
end

def under?(target, dir)
  target == dir || target.start_with?("#{dir}/")
end

payload =
  begin
    JSON.parse($stdin.read)
  rescue JSON::ParserError
    exit 0
  end

tool       = payload['tool_name']
tool_input = payload['tool_input'] || {}
agent_type = payload['agent_type']
cwd        = payload['cwd'].to_s

if agent_type && READ_ONLY_AGENTS.include?(agent_type)
  deny("#{agent_type} is read-only — #{tool} is not permitted. Report findings instead.") if WRITE_TOOLS.include?(tool)
  exit 0
end

exit 0 if agent_type.nil? || cwd.empty?

cwd_real    = File.expand_path(cwd)
confined_to = project_root(cwd_real)
exit 0 unless confined_to

who = "#{agent_type} (in #{File.basename(confined_to)})"

if WRITE_TOOLS.include?(tool)
  file_path = tool_input['file_path'].to_s
  exit 0 if file_path.empty?

  file_path = File.join(cwd_real, file_path) unless Pathname.new(file_path).absolute?
  target = File.expand_path(file_path)

  exit 0 if under?(target, confined_to)
  exit 0 if SHARED_WRITABLE.any? { |dir| under?(target, File.expand_path(dir)) }
  exit 0 if sibling_repos.any? { |dir| under?(target, File.expand_path(dir)) }

  deny(
    "#{who} may only write under #{confined_to}, or in: #{SHARED_WRITABLE.join(', ')}. " \
    "Blocked write to #{target}. Another checkout is off-limits — to read one, use a git " \
    'remote name (`git fetch <remote> && git show <remote>/<branch>:<path>`) rather than a ' \
    'path into its working tree.'
  )

elsif tool == 'Bash'
  command = tool_input['command'].to_s

  # Requiring a `.git` ancestor keeps this off ordinary paths that merely sit near the code
  # directory; only a real foreign checkout trips it.
  stray = command.scan(%r{/(?:[\w.\-~]+/)+[\w.\-]+}).filter_map do |path|
    expanded = File.expand_path(path.sub(/\A~/, HOME))
    root = project_root(expanded)
    root if root && !under?(expanded, confined_to)
  end.uniq

  unless stray.empty?
    deny(
      "#{who} Bash is confined to #{confined_to} — this command references #{stray.join(', ')}. " \
      'Use a git remote name for a peer read, not an absolute path into another checkout.'
    )
  end
end

exit 0
