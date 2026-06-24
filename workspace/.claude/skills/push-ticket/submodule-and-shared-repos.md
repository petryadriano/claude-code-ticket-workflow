# Submodule & shared-repo push reference

Reference for **push-ticket Step 3 (Pre-push checks)** and **Step 4 (Branch, commit, push)**. Load
this when `implementation.files_changed` lists paths under a UI SPA / nested submodule
(`repo-ui`, `repo-ui-app`, `ui-core`, `common-ui`) or under a consumer's shared submodule
(`api/Shared`, …). These repos are **separate repos on the Git host** (git submodules), so their branches /
commits / MRs go to those repos, not the host — but the branch/commit/push/MR **mechanics**
themselves stay in the SKILL's Step 4. Nothing here is delegated to Superpowers; this is
repo-topology detail.

## UI submodule repos (repo-ui / repo-ui-app / ui-core / common-ui)

The UI host's SPAs and their nested libs are **separate repos on the Git host** (git submodules), NOT part of the
UI host repo. If `implementation.files_changed` lists paths under any of them, the
branches/commits/MRs go to **those repos**, not the host:

- The UI host itself gets **no branch or MR** — its submodule pointers are bumped by a daily automated job.
- Repos + bases (use `--repo "<path under $WORKSPACE_ROOT>"` for all scripts):
  - `web/repo-ui` → `develop`
  - `web/repo-ui-app` → `dev`
  - `web/repo-ui-app/ui-core` → `main` (nested submodule of repo-ui-app)
  - `web/repo-ui-app/common-ui` / `web/repo-ui/common-ui` → `develop`
- Branch naming for these repos is **`PROJ-XXX-short-description`** (no `feature/`/`bugfix/` prefix, no verb). So:
  - the **Step 1 branch-verb check does NOT apply** to them;
  - do **not** run `sync-repos.sh` with these submodule paths (it only accepts top-level repos) — freshen each base via `create-branch.sh --from <base>` (it fetches+pulls the base per repo);
  - `prepare-mr.sh` recognizes the `PROJ-XXX-desc` form and prints `CHECK|PASS` for these repos — no special handling needed.
- Order producer → consumer: ui-core (`main`) → repo-ui-app (`dev`) → repo-ui (`develop`). If you changed a nested submodule (ui-core), bump its pointer in the parent commit (see Step 4 staging).

## Shared submodule repo (`<consumer>/Shared`, e.g. `api/Shared`)

A shared DTO/model change is its own repo on the Git host (a shared submodule / vendored dependency) and its own MR:
- Branch via `create-branch.sh --repo <consumer>/Shared --branch <plan.branch> --from develop` (always pass `--from develop` — belt-and-suspenders for base resolution on a submodule path), push, then `prepare-mr.sh --repo <consumer>/Shared --branch <plan.branch> --target develop`.
- Process the shared submodule **FIRST** (producer) — before the consumer repos that compile against it.
- The shared submodule **pointer** is NEVER staged in ANY consumer repo (api, web, services — `prepare-mr.sh` enforces this with a `CHECK|FAIL`). The pointer bump happens via the team's own process after the shared MR merges.
- Consequence: a consumer MR whose code references the new shared symbol will not compile in CI until the shared MR merges and the pointer is bumped — say so in the consumer MR description ("Depends on shared MR <link>; merge the shared submodule first").
