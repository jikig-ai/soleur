# Tasks: Fix pdf-text-extract tests failing on Node <22

Derived from `knowledge-base/project/plans/2026-05-06-fix-pdf-text-extract-tests-fail-on-node-lt-22-plan.md`.
Issue: #3383

## Phase 1 — Operator Environment Pin

1.1. Add `.nvmrc` at the repo root (parent of `apps/`, `plugins/`, `knowledge-base/`) containing exactly `22\n`. No other content; `nvm use` / `fnm use` / `volta` resolves the latest 22.x.

1.2. Add an `"engines": { "node": ">=20.16.0 || >=22.3.0" }` block to `apps/web-platform/package.json`. Mirror `pdfjs-dist@5.4.296`'s own engines field VERBATIM (verified at planning time from `node_modules/pdfjs-dist/package.json`). The disjunction is precise about the `process.getBuiltinModule` back-port boundary — it correctly accepts ubuntu-latest's pre-installed Node 20.20.2 (where the back-port is present) AND Node 22.3+ while still rejecting Node 21 (no back-port, EOL). Do NOT bump any other field. Do NOT collapse to a single-version floor.

1.3. Verify locally (Node ≥22.3 shell):

```bash
nvm use
node --version            # → v22.x.x
cd apps/web-platform
./node_modules/.bin/vitest run test/pdf-text-extract.test.ts
# Expect: 9 passed, 0 failed
```

## Phase 2 — CI Test Job Pin

2.1. Edit `.github/workflows/ci.yml` `test:` job (currently lines 101-126). After the existing `Setup Bun` step (lines 107-110) and BEFORE the first `Install dependencies` step (lines 112-113), insert a `Setup Node.js` step using the literal pinned SHA already used by `web-platform-build` (line 87) and `e2e` (line 140):

```yaml
- name: Setup Node.js
  uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
  with:
    node-version: 22
    cache: 'npm'
    cache-dependency-path: apps/web-platform/package-lock.json
```

Do NOT introduce a new SHA. Do NOT bump v4.4.0 to v4.x.y. SHA + comment must be identical to the existing pin (verifiable via `grep -nE "setup-node@" .github/workflows/ci.yml` showing identical SHA in all 4 jobs after the edit).

2.2. Verify the pin landed on the right job (not silently inserted into `e2e:` or `web-platform-build:`):

```bash
awk '/^  [a-z][a-z-]+:/{job=$1} /node-version:/{print job, "→", $0}' .github/workflows/ci.yml
# Expected output (after edit):
#   lockfile-sync: → node-version: 22
#   web-platform-build: → node-version: 22
#   test: → node-version: 22       # ← NEW: this row was missing before
#   e2e: → node-version: 22
#   critical-css-gate: → node-version: 20
```

2.3. Verify the workflow YAML is syntactically valid (`actionlint .github/workflows/ci.yml` if available; otherwise rely on CI rejecting an invalid file at PR open).

## Phase 3 — Verify

3.1. Push the branch.

3.2. Confirm CI runs the `test:` job with `node-version: 22` (check the `Setup Node.js` step output in the run log: `node --version` line should print `v22.x`).

3.3. Confirm all 9 tests in `pdf-text-extract.test.ts` pass in CI (look at the `Run tests` step output — `apps/web-platform` suite line should show `Tests  9 passed (9)`).

3.4. Confirm sibling CI jobs (`lockfile-sync`, `web-platform-build`, `e2e`, `verify-readme-counts`) remain green — no expected breakage but verify no `engines` field warning escalates to an error in any of them.

## Phase 4 — PR

4.1. Open PR with `Closes #3383` in the body. Title: `fix(test): pin Node ≥22.3 for pdf-text-extract tests (closes lazy_import_failed cascade)`.

4.2. Set semver label: `semver:patch` (no API surface change, no new component, no breaking change — pure operator/CI environment pin).

4.3. PR body MUST include:
- Link to the prior learning `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md` Engine Requirement section.
- Note that production runtime (`node:22-slim` Docker) was already compliant — this is operator/CI alignment only.

## Phase 5 — Compound

5.1. Run `/soleur:compound`. Likely outcomes:
- A learning entry capturing "engines+nvmrc+CI-node-pin" as the canonical fix shape for "Node-version-required-by-dep-but-not-enforced-locally" failure mode (so the next pdf-related dep bump triggers the right remediation).
- No new AGENTS.md rule (the discoverability exit per `wg-every-session-error-must-produce-either` applies — `npm install` warning + `.nvmrc` auto-switch + CI pin make the constraint discoverable on the next run).

## Out of Scope (deferred — file follow-on issues if pursued)

- Promoting `engines.node` from advisory to hard via `engine-strict=true` in `.npmrc`. Broader blast radius (affects every `npm install` in the repo); separate decision.
- Capturing the underlying error message inside `extractPdfText`'s `lazy_import_failed` branch so the user-facing label includes `process.getBuiltinModule is not a function` instead of an opaque tag. Production runtime is `node:22-slim` so the surface is unreachable; the cost of widening the discriminated union exceeds the value today.
- Fixing #3342 (`kb-preview-metadata.ts` Buffer-vs-Uint8Array). Adjacent file, separate root cause.
- Adding a unit-test suite for `kb-preview-metadata.ts` itself (it has no test today; same Node-22 constraint applies). Out of scope but worth filing a follow-on.
