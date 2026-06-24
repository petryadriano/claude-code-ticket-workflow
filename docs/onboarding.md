# Onboarding — set up the workspace

Stand up a working Claude Code workspace driven by the shared skills.
The fast path is **clone the workflow repo → run `/setup`**.

> **Mental model.** A *workspace* is one folder (e.g. `ws1`) holding **all** your repos
> side-by-side, plus a `.claude/` with the shared skills, scripts, and settings. Skills treat
> the workspace root (the parent of `.claude/`) as `$WORKSPACE_ROOT`.

---

## 0. Install the Superpowers plugin (once per machine)

The flow runs on a **two-layer architecture**: the lifecycle skills (the domain layer) delegate
generic engineering discipline to the **[Superpowers](https://github.com/obra/superpowers)** plugin
(the substrate) via `REQUIRED: superpowers:*` references. It's MIT-licensed, distributed via
Anthropic's official `claude-plugins-official` marketplace; the only thing it auto-runs is a local
context-injection hook at session start (no telemetry, no external egress).

> **Version policy.** Treat the version as **pinned by team convention**: adopt one vetted version,
> record it, and re-review the session-start hook's diff before bumping. The marketplace install may
> track latest, so the pin is enforced by your review discipline, not by the tooling — worth being
> deliberate about for a shared team repo.

Installing it is a one-time, per-machine **user action** — Claude can't do it for you. In `claude`, run:

```
/plugin install superpowers@claude-plugins-official
/reload-plugins
```

After this, every workspace `/setup` creates keeps it enabled automatically — the workspace
`settings.json` from the template sets `enabledPlugins`, so you only install once.

> **Why it's a real prerequisite, not optional polish.** `/setup` has a **Step 0b** that checks for
> the plugin and prints this install command if it's missing, and `/complete-ticket` warns at flow
> entry when it isn't loaded. The coupling is **degradable** — without it the flow still runs and every
> gate is intact; you just lose the substrate disciplines (test-first, evidence-before-claims,
> systematic debugging, …). So the order for a new dev is: **install Superpowers → run `/setup` → open a
> workspace and run `/complete-ticket PROJ-123`**.

---

## 1. Clone and run `/setup`

```
git clone <your-workflow-repo-url>
```

Then run `claude` in the repo folder and call `/setup`.

It first checks/validates your Git host token (prompting if it's missing), then
asks for a **root directory** (defaults to your code directory — `C:\source` on Windows, `~/source`
on macOS/Linux) and **how many workspaces** (default `3` → `ws1`, `ws2`, `ws3`), shows you the
plan, and on your confirmation does this per workspace:

- **links** the shared `skills` + `scripts` into `<workspace>/.claude/` — a *junction* on
  Windows, a *symlink* on macOS/Linux,
- writes a `CLAUDE.md` that imports the shared conventions doc,
- drops in `settings.json` from the template,
- clones + syncs all your repos.

`/setup` is **idempotent** and **skips any workspace that already has work** — safe to re-run to
add a workspace or repair one.

## 2. Start a ticket

In a workspace folder (`ws1` — **not** the workflow clone), run `claude` and call:

```
/complete-ticket PROJ-123
```

It's the single entry point — it syncs your repos for you, so you don't run `/sync-repos` or
anything else first.

---

## Staying current

You don't pull manually. `/complete-ticket` and `/review` check the shared clone at the start of
each ticket and offer a fast-forward when it's behind — one pull updates every workspace (via the
links) and the conventions doc (via the import).

## What stays personal (never commit)

- `.claude/tickets/` — live ticket state.
- `.claude/settings.local.json` — your machine-specific permission grants.
- Your Git host token (e.g. `~/.claude/git-token`).

---

## See also

- **Your own `CLAUDE.md`** — the architecture and conventions doc each workspace imports (you write this for your stack).
- [`ticket-workflow.md`](ticket-workflow.md) — how the skills drive a ticket.
