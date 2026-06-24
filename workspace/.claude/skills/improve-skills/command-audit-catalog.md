# Command-audit catalog

Reference for **improve-skills Step 2 (Command audit)**. These are the recurring command failures seen
across ticket sessions and their known-good replacements. Check every command the session ran against
the three categories below; for each failure, record it in the Step 2 format and fix the owning skill/script
before moving on.

> **Root-cause each failure before cataloguing a "fix."** A command that failed for an environmental reason
> (dirty tree, missing restore, wrong base) doesn't need a skill edit — it needs the precondition fixed.
> **REQUIRED: superpowers:systematic-debugging** — read the complete error, find why it failed, and only then
> decide whether the fix belongs in a skill/script. This catalog is the domain-specific layer of known causes;
> add new entries here as they're discovered.

## Tracker MCP calls — did any call fail or return truncated/wrong data?
- Wrong instance-id format → always use the tracker's hostname (e.g. `"tracker.example.com"`), not a UUID
- Missing response-format option → always request the format the parser expects (e.g. `"markdown"`)
- Missing or wrong `fields` → use the canonical field list from your tracker-calls reference memory
- Pagination not detected → check that the returned item count matches the reported total

## Git commands — did any git command fail, produce unexpected output, or need a retry?
- `git remote set-head origin -a` → replace with a `git branch -r | grep <develop-prefix>` pattern (already fixed in scripts — check skills for inline use)
- `git checkout <branch>` failing due to dirty tree → must stash first
- `git push` failing → check if force-with-lease is needed (branch already exists on remote)
- `git log base..HEAD` with wrong base → verify base branch before running
- `git status --short` vs `--porcelain` → use `--porcelain --ignore-submodules=all` for scripting

## Bash/shell commands — did any shell command produce wrong output or need adaptation?
- `paste -sd ',' -` for joining → may fail on some systems; safer: use a loop with IFS
- `grep -oE '[0-9]+'` for parsing JSON values → breaks on string values; use `sed` with capture groups
- `sort -t. -k1,1n -k2,2n` for version sorting → this is correct and reliable

For each found: update the relevant script or skill immediately, before moving to Step 3. A change to a
**skill** is itself a skill edit — apply it under the writing-skills discipline (see the skill's Step 4/5).
