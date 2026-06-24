# Build & type-check diagnostics

Reference for **implement-ticket Step 4 (Build check)**. Load this when a build, type-check, or lint
run produces output you are not sure how to read.

> **The general discipline — read the COMPLETE error output and find the root cause before
> writing any fix — is delegated.** **REQUIRED: superpowers:systematic-debugging.** This file is
> only the layer on top of it: how to tell real compile errors from environmental noise, so you
> don't "fix" code that was never broken. The failure classes below are described generically —
> substitute your own stack's exact error strings (the discipline transfers, not the signatures).

## Build — what counts as a real error

```bash
<build command>   2>&1 | tee "$WORKSPACE_ROOT/build.log"   # capture the FULL log — do NOT pipe through `| tail -N`
```

The build is clean only when it reports **zero** real compile errors. Capture the full output (piping
through `| tail` hides real error lines behind noise), then scan it for your compiler's actual error
signature. Distinguish these classes:

| Output class | What it actually is | What to do |
|---|---|---|
| Build-tool / target chatter that is **not** a compile error | Incremental-build diagnostics from the build tool, not your code | Ignore; look only for the real compile-error lines. |
| **File-lock** error ("could not copy/write … in use by another process") | A running process (e.g. the app you started) is holding the built binaries | Stop that process, then rebuild. Never treat as a code error. |
| **Stale-cache / incremental-build** error (can't read a cache/temp file, "rebuilding completely") | A stale incremental-build cache, or a leftover build-server / worker process holding caches | Clear the build cache / restart the build server, then rebuild. Write the FULL log to a file and grep for real errors — cache noise otherwise buries them. |
| A nonzero **error count with no actual error lines** | Transient restore/lock state, typically right after a pull or a fresh dependency restore | Re-run the build once. Only a *repeatable* count with visible error lines is real. |

**Pre-existing compile break in an upstream file unrelated to the ticket** — before hand-fixing it,
check whether an in-flight upstream commit already fixes it (`git -C <repo> log origin/<base> --oneline -- <file>`
after a fetch, or look for the owning ticket's branch). If you must fix it to unblock the build (e.g. your
tests live in the same project), keep the fix minimal, journal it, and expect it to be **superseded at
push-time sync** — be ready to drop it from the commit scope rather than ship a duplicate of the owning
team's fix.

**LSP/IDE diagnostics are NOT the build authority.** The editor's language server may report spurious
"type/name could not be found" / "missing reference" errors on **every** import when the project hasn't
been restored/indexed in the LSP session — it looks like your edit broke the whole file. It's noise, not
compile errors. Trust ONLY the actual `<build command>` output; never edit code to "fix" an LSP diagnostic
that the build does not also report.

## Type-check & lint (UI / frontend changes)

```bash
<type-check command>   2>&1 | tail -20
```
Type errors are caught here — do not skip even if no new component file was created (existing types may
have been broken by your change).

If the change touched a UI/frontend module, also run your **linter** — it catches import-ordering, unused
vars, and the other rules that surface only at review; the type-checker does **not** cover them, so don't
skip it even when build and type-check are clean:
```bash
<lint command>
```
If the change **also** touched styles, additionally run your **style-linter** (`<style-lint command>`).
Most linters accept a `--fix` flag to auto-apply fixable violations; re-run to confirm clean. **Scope the
result to your change:** `--fix` (especially style-ordering rules) will also rewrite **pre-existing**
violations elsewhere in a file you touched — keep only the fixes on the lines this ticket changed and revert
unrelated reorders, so the diff stays scoped to the ticket.

## "UI change not appearing" protocol

If a UI change you made doesn't show up in the running app, verify **objectively** before concluding "stale
build / cached bundle" (this is the local instance of the evidence rule —
**REQUIRED: superpowers:verification-before-completion**):

1. Grep the built bundle / output dir for the new symbol (component name, class, label) — is the edit actually compiled in?
2. Confirm the dev server / watcher was restarted (or hot-reload fired) **after** the edit.
3. Confirm any gating feature flag is actually `true` in the running app's state, not just set in the dev env form.

Never insist a change is present (or that an image is "identical / stale") against the user's direct
observation — get objective evidence first, and if the user reports seeing something different, trust that
and investigate.
