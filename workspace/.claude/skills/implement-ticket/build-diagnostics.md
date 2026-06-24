# Build & type-check diagnostics (.NET + UI)

Reference for **implement-ticket Step 4 (Build check)**. Load this when a `dotnet build`,
`npx tsc`, or lint run produces output you are not sure how to read.

> **EXAMPLE STACK.** This catalog is written for a **.NET + UI** stack as a concrete example of
> *what a build-diagnostics reference looks like* — replace its error signatures with your own
> stack's (the "real error vs. environmental noise" discipline is what transfers, not the specific
> `MSB####` codes).

> **The general discipline — read the COMPLETE error output and find the root cause before
> writing any fix — is delegated.** **REQUIRED: superpowers:systematic-debugging.** This file is
> only the .NET-specific layer on top of it: which lines are real compile errors versus
> environmental noise, so you don't "fix" code that was never broken.

## .NET build — what counts as a real error

```bash
dotnet build "$WORKSPACE_ROOT/<repo>/<Repo>.sln" --no-restore 2>&1 | grep -E "error CS|^\s+[0-9]+ Error\(s\)" | head -30
```

Build is clean when `grep "error CS"` returns nothing **and** the Error count shows `0 Error(s)`.
Only `error CS####` lines are real compilation failures.

| Output | What it actually is | What to do |
|---|---|---|
| `MSBUILD : error : Building target...` | Incremental-build diagnostic, **not** a compile error | Ignore; look for `error CS####` |
| `MSB3027: Could not copy ... because it is being used by another process` | **File-lock**, not a compile error — another process (e.g. the running API) holds the DLLs | Kill the running process, rebuild. Never treat as a code error. |
| `MSB3492: Could not read existing file "obj\...cache"` (+ `Building target "CoreCompile" completely`) | **obj-cache lock** — usually an IDE or leftover MSBuild worker nodes holding incremental caches | `dotnet build-server shutdown`, then rebuild with `-nodeReuse:false`. Do **not** capture build output through `\| tail -N` — that hides the real `error CS####` lines behind cache-lock noise; write the full log to a file and `grep -E ': error \|error CS'`. |
| `N Error(s)` with **zero** `error CS####` lines | Transient restore/lock state, typically right after a pull or fresh restore | Re-run the build once. Only a *repeatable* count with visible `error CS`/`: error` lines is real. |

**Pre-existing compile break in an upstream file unrelated to the ticket** — before hand-fixing it,
check whether an in-flight upstream commit already fixes it (`git -C <repo> log origin/<base> --oneline -- <file>`
after a fetch, or look for the owning ticket's branch). If you must fix it to unblock the build (e.g. your
tests live in the same project), keep the fix minimal, journal it, and expect it to be **superseded at
push-time sync** — be ready to drop it from the commit scope rather than ship a duplicate of the owning
team's fix.

**LSP/IDE diagnostics are NOT the build authority.** The editor's LSP may report spurious
`type or namespace name 'X' could not be found` / "are you missing an assembly reference" on **every**
`using` when the solution hasn't been restored in the
LSP session — it looks like your edit broke the whole file. It's noise, not compile errors. Trust ONLY the
`dotnet build` output (`error CS####` / `N Error(s)`); never edit code to "fix" an LSP diagnostic that
`dotnet build` does not also report.

## UI type-check & lint

```bash
npx tsc --noEmit -p "$WORKSPACE_ROOT/web/tsconfig.json" 2>&1 | tail -20
```
TypeScript type errors are caught here — do not skip even if no `.tsx` file was created (existing types may
have been broken).

If the change touched a UI SPA, run **ESLint**. This catches
import-ordering (`eslint-plugin-simple-import-sort`), unused vars, and the other rules that otherwise surface
only at review — `npx tsc` does **not** cover them, so do not skip this even when build and type-check are clean:
```bash
(cd "$WORKSPACE_ROOT/web/<spa>" && npm run lint)
```
If the change **also** touched any `.scss`, additionally run **stylelint**:
```bash
(cd "$WORKSPACE_ROOT/web/<spa>" && npm run slint)
```
Append `-- --fix` to either command (e.g. `npm run lint -- --fix`) to auto-apply the fixable violations,
then re-run to confirm clean. **Scope the result to your change:** `--fix` (especially stylelint's
`order/properties-order`) will also rewrite **pre-existing** violations elsewhere in a file you touched — keep
only the fixes on the lines this ticket changed and revert unrelated reorders, so the diff stays scoped to the ticket.

## "UI change not appearing" protocol

If a UI change you made doesn't show up in the running app, verify **objectively** before concluding "stale
build / cached bundle" (this is the local instance of the evidence rule —
**REQUIRED: superpowers:verification-before-completion**):

1. Grep the built bundle / `dist` for the new symbol (component name, class, label) — is the edit actually compiled in?
2. Confirm the dev server / watcher was restarted (or HMR fired) **after** the edit.
3. Confirm any gating feature flag is actually `true` in the running store (Redux DevTools `auth` slice),
   not just set in the dev env form.

Never insist a change is present (or that an image is "identical / stale") against the user's direct
observation — get objective evidence first, and if the user reports seeing something different, trust that
and investigate.
