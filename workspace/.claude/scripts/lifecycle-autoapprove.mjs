#!/usr/bin/env node
// PreToolUse hook (matcher: Bash) — DEFAULT-ALLOW + DENYLIST.
//
// Goal: the lifecycle should stop ONLY at meaningful gates. So this auto-approves Bash by
// default and returns `permissionDecision: "ask"` only for a denylist of destructive or
// external actions — which (per Claude Code precedence) forces a prompt even when an allow
// rule like `Bash(git *)` would otherwise auto-approve. MCP external writes (MR/tracker) stay
// gated by the settings `ask` list, which a Bash hook does not touch.
//
// FAIL-DANGER caveat (be honest): in default-allow mode the risky direction is a *missed*
// denylist entry (a novel destructive command would auto-run). The denylist below covers the
// common dangerous/external shapes; it is not a proof of safety. This is the trade-off the
// "stops only at gates" model accepts.
//
// Denylisted -> ASK (still prompts):
//   • git push (any, incl. --force)            • git reset --hard/--keep      • git clean
//   • git branch -d/-D/-m/-M                    • git tag -d                   • git filter-branch/-repo
//   • git stash drop/clear/pop/apply           • git checkout . / -- . / -f    • git restore . (whole tree)
//   • git remote add/remove/set-url/rename      • git gc --prune/--aggressive  • git worktree remove/add/prune
//   • rm -r / -rf (recursive delete)           • sudo                          • chmod/chown -R
//   • curl|wget … | sh/bash/iex or BARE node/python (stdin executed; `node -e`/`python -c`
//     inline-program data-parses are allowed)   • dd / mkfs / fdisk / diskpart  • writes to /dev/disk
//   • shell writes to the safety config (lifecycle-autoapprove / .claude/settings) • forkbomb
// Everything else (reads, Grep, builds, tests, git status/log/diff/branch-list/add/commit/
// checkout-branch/merge/fetch/pull, targeted `git checkout <ref> -- <paths>` / `git checkout -- <path>`
// restores, targeted `git restore <path>`, state-file helpers, file ops) -> ALLOW.

import process from 'process'

function readStdin () {
  return new Promise((resolve) => {
    let data = ''
    process.stdin.setEncoding('utf8')
    process.stdin.on('data', (chunk) => { data += chunk })
    process.stdin.on('end', () => resolve(data))
  })
}

const ASK = (reason) => {
  console.log(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'ask', permissionDecisionReason: reason }
  }))
  process.exit(0)
}
const ALLOW = (reason) => {
  console.log(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'allow', permissionDecisionReason: reason }
  }))
  process.exit(0)
}
const DEFER = () => process.exit(0)

// Whole-command non-git danger checks (operate on the normalised command string).
function dangerousNonGit (cmd) {
  if (/\brm\s+(?:-[a-z]*r[a-z]*|--recursive)\b/i.test(cmd)) { return 'recursive rm' }
  if (/(^|[\s;&|(])sudo\b/i.test(cmd)) { return 'sudo' }
  // Piping a download into an interpreter: bare `node`/`python` EXECUTE stdin (remote code), so
  // they ask — but `node -e '<prog>'` / `python -c '<prog>'` run a fixed inline program and read
  // stdin as DATA (e.g. `curl … | node -e 'JSON.parse(...)'`), which is a legitimate parse, so
  // those are allowed. sh/bash/zsh/iex/powershell always execute stdin → always ask.
  if (/\b(?:curl|wget|iwr|invoke-webrequest)\b[^\n]*\|\s*(?:sh|bash|zsh|iex|powershell|node(?!\s+(?:-e|--eval)\b)|python3?(?!\s+-c\b))\b/i.test(cmd)) { return 'pipe remote content to a shell' }
  if (/\bchmod\s+-[a-z]*R/i.test(cmd) || /\bchown\s+-[a-z]*R/i.test(cmd)) { return 'recursive chmod/chown' }
  if (/\b(?:dd|mkfs|fdisk|diskpart)\b/i.test(cmd)) { return 'disk tool' }
  if (/>\s*\/dev\/(?:sd|nvme|disk|hd)/i.test(cmd)) { return 'write to raw disk' }
  if (/(?:>>?|\btee\b|\bsed\s+-i|\brm\b|\bmv\b|\bcp\b)[^\n]*(?:lifecycle-autoapprove|\.claude\/settings)/i.test(cmd)) { return 'modifies the safety config' }
  if (/\(\s*\)\s*\{\s*:\s*\|\s*:/.test(cmd)) { return 'forkbomb' }
  return null
}

// Per-segment git danger check.
function dangerousGit (seg) {
  const m = seg.match(/^git\b\s*([\s\S]*)$/)
  if (!m) { return false }
  const rest = m[1].replace(/^(?:-C\s+\S+\s+|-c\s+\S+\s+|--no-pager\s+|--paginate\s+|-p\s+|--git-dir=\S+\s+|--work-tree=\S+\s+)*/, '')
  const parts = rest.split(/\s+/).filter(Boolean)
  const sub = parts[0]
  const args = parts.slice(1)
  if (!sub) { return false }
  switch (sub) {
    case 'push': return true
    case 'clean': return true
    case 'filter-branch': case 'filter-repo': return true
    case 'reset': return args.includes('--hard') || args.includes('--keep')
    case 'branch': return args.some(a => ['-d', '-D', '-m', '-M', '--delete', '--move', '--force', '-f'].includes(a))
    case 'tag': return args.some(a => ['-d', '--delete'].includes(a))
    case 'stash': return ['drop', 'clear', 'pop', 'apply'].includes(args[0])
    // Targeted file restores — `git checkout <ref> -- <paths>` and `git checkout -- <path>` — are
    // lifecycle plumbing (set specific files to a known state), so they ALLOW. Only a whole-working-tree
    // discard (`git checkout .` / `git checkout -- .`) or a force checkout (`-f` / `--force`) still prompts.
    case 'checkout': return args.includes('.') || args.includes('-f') || args.includes('--force')
    case 'restore': return !args.includes('--staged') && args.includes('.') // targeted `git restore <path>` is plumbing; only whole-tree `git restore .` prompts
    case 'gc': return args.includes('--prune') || args.includes('--aggressive')
    case 'remote': return ['add', 'remove', 'rm', 'set-url', 'rename'].includes(args[0])
    case 'worktree': return ['remove', 'add', 'prune'].includes(args[0])
    case 'update-ref': return true
    default: return false
  }
}

async function main () {
  let input
  try {
    input = JSON.parse(await readStdin())
  } catch {
    DEFER()
  }
  if (!input || input.tool_name !== 'Bash') { DEFER() }

  const command = (input.tool_input && input.tool_input.command) || ''
  const normalised = command.replace(/\\/g, '/')

  const nonGit = dangerousNonGit(normalised)
  if (nonGit) { ASK(`Denylisted: ${nonGit} — confirm before running`) }

  const segments = command.split(/\|\||&&|;|\||\n/).map(s => s.trim()).filter(Boolean)
  for (const seg of segments) {
    if (/^git\b/.test(seg) && dangerousGit(seg)) {
      ASK('Denylisted git operation (push / reset --hard / clean / branch -d / … ) — confirm before running')
    }
  }

  ALLOW('Lifecycle default-allow (reads/builds/tests/local-git/file ops); destructive & external actions still prompt')
}

main().catch(() => process.exit(0))
