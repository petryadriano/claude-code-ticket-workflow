---
description: Provision one or more workspaces from this standards repo. Prompts for a root directory and a workspace count, then runs a self-contained script once per workspace that creates the workspace, junctions the shared skills/scripts, wires CLAUDE.md + settings, and clones + syncs all repos — streaming the full per-repo and per-submodule progress live (exactly like /sync-repos), with a per-repo and per-submodule branch table at the end. Auto-approved (no per-command prompts) and idempotent; never touches a workspace that already has work. Usage: /setup
allowed-tools:
  - Bash
  - Read
  - Write
---

# /setup — provision workspaces

Bootstraps the workspace(s) described in this repo. Run it from inside a clone
of the **standards repo**. It is **idempotent** and **never overwrites a
workspace that already contains work** (your other sessions are safe).

> **$STD_ROOT** = this standards repo's root = the parent of the `.claude/` folder
> that holds this skill (e.g. `C:/source/standards-repo`).
> Resolve it before anything else; every path below is relative to it.

**How this skill is wired (so it runs hands-off):**
- All shell work lives in scripts under `$STD_ROOT/workspace/.claude/scripts/`
  (`check-token.sh`, `ensure-superpowers.sh`, `provision-workspaces.sh`), so the only command you
  ever run is `bash <script>`. The repo's checked-in `.claude/settings.json` pre-approves
  `Bash(bash *)`, so the user is **not** prompted to approve each step.
- Provisioning runs as an ordinary **foreground Bash command** (one per workspace), so its
  full output — every clone, sync, and submodule line — **streams live to the terminal exactly
  like `/sync-repos`**: you see everything as it happens and parse the same stream for the
  end-of-run table.
- The scripts are **OS-agnostic**: they detect the platform and use a directory
  *junction* on Windows (Git Bash, no admin) or a *symlink* on macOS/Linux.

---

## Step 0 — Git host credentials (check + validate before anything else)

Cloning every repo per workspace and the MR-related skills both need a Git host token. Handle it here so a bad/missing token fails fast instead of as a dozen cryptic clone errors later.

Run the check — it reads `~/.claude/git-token` locally and prints **only** a status word, so the secret never enters this chat:

```bash
bash "<STD_ROOT>/workspace/.claude/scripts/check-token.sh"
```

Branch on the single word it prints:

- **`OK`** → token is valid; continue to Step 1.
- **`MISSING`** → ask the user to create it, **and tell them to enter it with the `!` prefix so the secret runs locally and never enters this chat:**

  ```
  !printf '%s' 'your-token-here' > ~/.claude/git-token
  ```

  It needs `api` scope (so MR-creating skills work) and the **shortest workable expiry** (30–90 days, not the max). Wait for them, then re-run the check.
- **`INVALID`** → the token is present but expired / wrong scope / revoked. Stop and have the user re-issue it (as above), then re-run the check. Do not clone with a known-bad token.

> Secure alternative (recommended for new machines): if your Git host's CLI supports storing the token in the OS keyring (no plaintext) and auto-configuring the git credential helper for clones, prefer that. The MR skills still read `~/.claude/git-token` today, so for now also set that file — until the skills are migrated to the CLI.

---

## Step 0b — Superpowers plugin (the engineering substrate)

The lifecycle skills delegate their generic engineering discipline (test-first, verify-before-claim,
systematic debugging, code review, plan-writing, …) to the **Superpowers** plugin via
`REQUIRED: superpowers:*` references. `/setup`'s job here is to guarantee the plugin is **installed at
user (machine-wide) scope**, so the **workspace** sessions you'll open next can load it (each workspace's
`settings.json` enables it).

> **Do NOT gate on whether `superpowers:*` is loaded in *this* session — that is the wrong signal, and
> was the cause of a real bug.** The plugin can look "loaded" here yet be **absent in every workspace**:
> a `local`-scope install belongs to one project only, so it satisfies a setup-session check while the
> workspaces (separate projects) get nothing. Only a **user-scope** install reaches the workspaces. So
> **always run the installer below** — never skip it because the setup session happens to show `superpowers:*`.

Run the installer (idempotent — `claude plugin install … --scope user`; a no-op if already user-scoped):

```bash
bash "<STD_ROOT>/workspace/.claude/scripts/ensure-superpowers.sh"
```

Branch on its final stdout line:

- **`SUPERPOWERS|installed`** → ✓ Superpowers is on disk at **user scope**. The workspaces will load it
  on first session start (their `settings.json` enables it). Nothing to reload here — `/setup` itself
  doesn't use it. Continue to Step 1.
- **`SUPERPOWERS|nocli` or `SUPERPOWERS|failed|…`** → 🛑 **GATE — do NOT continue to Step 1.** Auto-install
  couldn't run (`claude` not on PATH, or it errored). Ask the user to install it at **user scope**
  themselves, then message you back (slash commands don't give you a turn):

  > Install Superpowers machine-wide, then send me any message (e.g. "done"):
  > ```
  > claude plugin install superpowers@claude-plugins-official --scope user
  > ```
  > Make sure it's **user** scope (not a single project), or the workspaces won't see it.

  When they reply, re-run `ensure-superpowers.sh` and branch again. **Only skip if the user explicitly
  says to** (e.g. "skip" / "continue without it") — never on your own. If they skip, the workspaces still
  provision (each one's `settings.json` enables the plugin for later), but the ticket flow won't apply the
  substrate disciplines until it's installed; `/complete-ticket` re-checks at entry.

---

## Step 1 — Ask the user (wait for answers)

Ask both, offering the defaults, and wait:

1. _"Where should the workspaces be created? (root directory) — default `<parent of $STD_ROOT>` (the folder that holds this standards repo, so the workspaces sit beside it). Alternative: `C:\source` (Windows) / `~/source` (macOS/Linux)."_
2. _"How many workspaces? — default `3`. Each workspace is a complete, independent checkout of all the repos, which lets you work several tickets **in parallel** — run one Claude Code session per workspace, each on its own branches, with no WIP or branch collisions between them. Two or three (`ws1`, `ws2`, `ws3`) is typical."_

When you present the root-directory choices, list `<parent of $STD_ROOT>` **first** as the recommended default and `C:\source` / `~/source` second — never `C:\source` first.

Then derive:
- `ROOT` = the answer to (1), trailing slashes stripped.
- `COUNT` = the answer to (2).
- **Names:** the first workspace is `ws1`, then `ws2`, `ws3`, … `ws<COUNT>`. Join them space-separated into `NAMES` (e.g. `ws1 ws2 ws3`).

Show the resolved plan so the user sees exactly what's about to happen, then **go straight to Step 2 — no second confirmation** (the root + count they chose above are the go-ahead; `provision-workspaces.sh` is idempotent and never clobbers an existing workspace, so there's nothing to guard):

```
Standards repo: <STD_ROOT>
Workspaces to create under <ROOT>:
  - <ROOT>\ws1
  - <ROOT>\ws2
  - <ROOT>\ws3
Each gets: linked skills + scripts (junction on Windows, symlink on macOS/Linux), a CLAUDE.md that imports <STD_ROOT>\CLAUDE.md,
settings.json from the template, then every repo cloned + synced.
```

(The token was already verified in Step 0 — if you skipped it, do it now: a bad token surfaces as a dozen clone failures otherwise.)

---

## Step 2 — Provision + clone (one foreground run per workspace)

Everything — create dirs, link skills/scripts, write CLAUDE.md, copy settings, record the
standards-root, then clone + sync **every** repo — is done by one idempotent script,
`provision-workspaces.sh`. It skips any workspace that already has content.

Resolve the arguments first:
- `STD`   = `<STD_ROOT>`
- `ROOT`  = the confirmed root from Step 1
- `NAMES` = the space-separated workspace names (e.g. `ws1 ws2 ws3`)

Run the script as an ordinary **foreground `Bash` command, once per workspace name** (do not
background it) so its full output **streams live to the terminal exactly like `/sync-repos`** —
every `:: cloning …`, `CLONE|`, `OK|`, and `SUB|` line shows as it happens, for free, because
terminal scrollback costs nothing. Merge stderr into stdout with `2>&1` so the `:: …` progress
lines stream alongside the `…|` result lines.

For **each** `NAME` in `NAMES`, run (set the Bash tool `timeout` to its max, `600000` ms):

```bash
bash "<STD>/workspace/.claude/scripts/provision-workspaces.sh" --std "<STD>" --root "<ROOT>" --names "<NAME>" 2>&1
```

One workspace at a time keeps each call's multi-repo clone comfortably inside the Bash tool's
10-minute ceiling. Cloning is genuinely slow; if a workspace ever exceeds 10 minutes the call
times out — that is safe, nothing is corrupted. **Recovery for a partially-cloned workspace:** re-running
`/setup` will *skip* it (the never-clobber guard skips any workspace that already has content) — instead,
open that workspace and run `/sync-repos` there: its Phase 0 clones every missing repo and syncs the rest.
The script prints `SETUP_DONE` as its last line on a clean run.

**Keep each call's full output** — its `WS|`, `CLONE|`, `OK|`, `SUB|`, `WARN|`, `ERROR|`, and
`CONFLICT|` lines are what Step 3 parses to build the branch table. There is no separate log
file: the foreground tool result already holds the complete stream.

---

## Step 3 — Summary (after the runs complete)

Use the **combined output of the Step 2 calls** (one foreground run per workspace) — you already
streamed and captured it, so no log file is involved. Across the runs, each emits a
`WS|<name>|created|…` or `WS|<name>|skipped|…` header, followed by that workspace's result lines:

| Line | Meaning | Branch field |
|---|---|---|
| `CLONE\|<repo>\|…` | repo freshly cloned | — |
| `OK\|<repo>\|<branch>\|<commit> <msg>` | repo synced | field 3 |
| `SUB\|<parent>\|<name>\|<branch>\|<commit> <msg>` | submodule synced | field 4 |
| `WARN\|…` / `ERROR\|…` / `CONFLICT\|…` | problem | — |

Group every result line under the most recent `WS|` header. For each workspace, render a tree
of **every repo and submodule with its current branch** — the user wants this explicitly, and
the data is already in the `OK|` / `SUB|` lines, so **do not re-run git** to get it. Indent each
submodule under its parent repo; a nested submodule (parent like `web/<ui>`) indents
one level further.

**Render it inside a fenced code block with space-aligned columns — NOT a Markdown table.**
Markdown table cells trim leading whitespace, so the `└` indentation collapses and the
parent/child structure is lost. Do **not** try to fake the indent with `&nbsp;` or other HTML
entities — the terminal prints them as literal text. A fenced code block is monospace and
preserves leading spaces exactly, so the tree lines up:

```
Setup complete.

Created:   <workspaces with a WS|…|created header>
Skipped:   <workspaces with a WS|…|skipped header — untouched>

=== <workspace name> ===
Repo / submodule                Branch         Commit
─────────────────────────────   ────────────   ────────────────
auth                            develop        f6d16ff v1.0
  └ shared                      develop        933f295
api                             develop        267653dac v1.0
  └ shared                      develop        933f295
…                               …              …
web                             develop        d896825bd v1.0
  └ shared                      develop        933f295
  └ <ui>                        dev            4730ae26d
      └ <ui-core>               main           5420bc5
…                               …              …
→ <n CLONE> cloned, <n OK> synced, <n WARN> warnings, <n ERROR> errors

(repeat the tree block for each workspace)

Next — start your ticket in a WORKSPACE, in a separate session (not here):
  - Open a NEW Claude Code session in one of the workspaces above — e.g. <ROOT>\ws1 — and run /complete-ticket PROJ-XXX there.
  - Do NOT run /complete-ticket in this standards-repo session: it isn't a workspace (no cloned product repos), so the lifecycle can't run here.
```

Keep the **Branch** column — it is the point of the tree. Add a short commit column too if it
adds clarity. If two workspaces resolved identically (the normal case), you may still show both
trees, or show one and note the other matched it — but never drop the branch detail. A submodule
in detached-HEAD state reports `HEAD` instead of a branch name in its `SUB|` line — show it as
e.g. `(detached @ <commit>)` rather than the literal `HEAD`.

If any repo reported `ERROR|...clone failed`, call it out and remind the user to check
their Git host token / credentials, then they can re-run `/setup` (it will only top up
what's missing). If any `CONFLICT|` lines appear, surface them — a stash pop hit conflicts and
the user's changes are preserved in the stash. The full streamed output is still in this
conversation, so point the user at it if they want the unabridged detail behind any error.

---

> **Hand off — never start the ticket here.** `/setup` runs in the **standards repo**, which is **not**
> a workspace: the ticket-lifecycle skills resolve `$WORKSPACE_ROOT` to a *workspace* (the cloned product repos
> live there, not here). So once the summary is shown, **do not run or offer to run `/complete-ticket` —
> or any lifecycle skill — in this session.** Your closing instruction is always: open a **separate**
> Claude Code session **in one of the provisioned workspaces** (name the concrete path, e.g. `<ROOT>\ws1`)
> and run `/complete-ticket PROJ-XXX` there. One session per workspace.
