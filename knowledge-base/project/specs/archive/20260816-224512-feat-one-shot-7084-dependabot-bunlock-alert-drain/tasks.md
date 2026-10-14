---
feature: feat-one-shot-7084-dependabot-bunlock-alert-drain
plan: knowledge-base/project/plans/2026-08-16-fix-dependabot-dual-lockfile-drain-plan.md
issue: 7084
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — npm as the single lockfile of record, then drain the Dependabot backlog

Derived from the finalized plan after five reviewers and a scoped strong-model consult. Phase order
is load-bearing; §2 in particular encodes "retire every reader before deleting the artifact, and
repair every gate before widening its scope."

## Phase 0 — Preconditions (blocking)

- [ ] 0.1 Re-query live state (Dependabot alerts, Dependabot PRs, CodeQL alerts); snapshot into this spec dir
- [ ] 0.2 Re-derive the install-site inventory **repo-wide**: `git grep -nE '(bun install|npm ci)' -- ':!knowledge-base' ':!*.md'`. Never scope to `.github/workflows/` — two live sites sit outside it
- [ ] 0.2b Measure `min-release-age=3` against a root-cwd global exact pin (`npm install -g <pkg>@<published-today>`). Decision rule: if it fails, do **not** create root `.npmrc`; record root's exemption in ADR-191
- [ ] 0.3 Verify `npx --yes npm@11 install --help | grep -- '--min-release-age'`
- [ ] 0.4 Re-derive the next free ADR ordinal across **all** `origin/*` refs (ADR-191 is provisional)
- [ ] 0.5 Record baseline CI timings for every converting job
- [ ] 0.6 Confirm `apps/web-platform/next.config.ts` declares no `images` key
- [ ] 0.7 Publish the 39-alert → package → target → disposition table into this spec dir (the residual must be derived, not asserted)

## Phase 1 — RED (write the failing tests first)

- [ ] 1.1 Create `scripts/lint-dual-lockfile.sh` + `.test.sh` (Guard 1)
- [ ] 1.2 Create `scripts/lint-workflow-install-sites.sh` + `.test.sh` (Guard 2) — split so each floor matches its own enumeration
- [ ] 1.3 Register both suites with `run_suite` in `scripts/test-all.sh` (orphan-suite linter is a CI gate)
- [ ] 1.4 Capture Guard 1 RED on today's tree (two `bun.lock`, two `[install]` blocks)
- [ ] 1.5 Capture Guard 2 RED on today's tree (sixteen `bun install` sites)
- [ ] 1.6 Add `apps/web-platform/test/next-config-images-absent.test.ts` (no `images` key)
- [ ] 1.7 Add the `sw-source.test.ts` handler-scope assertion (sole effect remains `skipWaiting`)
- [ ] 1.8 Build fixture corpora for both mutation matrices, including must-PASS non-canonical inputs

## Phase 2 — GREEN (order is load-bearing)

- [ ] 2.0 **Graph-switch proof (blocking).** Push a scratch branch with *only* the install-site conversion; drive the full required matrix green against current pins. If red, stop and re-scope
- [ ] 2.1 Convert the sixteen `bun install` sites to `npm ci --ignore-scripts`, including `plugins/soleur/scripts/grok-fidelity-gate.sh:28` and `apps/web-platform/.github/workflows/constraint-gates.yml:54`
- [ ] 2.1b Move all three constraint-gates byte-parity files in **one** commit (root workflow, nested workflow, template) or `test-scripts` goes red
- [ ] 2.1c Decide the tenant-template boundary (`fix-constraints-stage-a.template:87`); record in ADR-191
- [ ] 2.2 Add `--ignore-scripts` to the four pre-existing bare `npm ci` sites — this closes a **live** fork-PR execution path at `ci.yml:587`, not a hypothetical one. Verify `next build` still succeeds; if not, enumerate the required `npm rebuild` set rather than dropping the flag
- [ ] 2.3 Add `actions/setup-node` (node 22, `cache: npm`, `cache-dependency-path`) to the eight workflows lacking a Node pin. `e2e` keeps container Node 24
- [ ] 2.4 Delete all four `actions/cache` blocks (`npm ci` deletes `node_modules`; `setup-node` caching replaces them)
- [ ] 2.5 Remove `setup-bun` + the `e2e` `unzip` step from jobs that no longer run bun. **Do not strip `setup-bun` from `test-scripts`**
- [ ] 2.6 Retire the bun half of `sdk-bump-sandbox-gate.sh` — **keep the `[[ -z "$pv" ]]` presence arm**, rename PARITY → PRESENCE. Deleting Section 1 wholesale reopens the #5849 silent-green class
- [ ] 2.7 Delete `apps/web-platform/bun.lock` and root `bun.lock`
- [ ] 2.8 Remove `[install]` from both `bunfig.toml` (keep `[test]` byte-for-byte); add `.npmrc` per directory; add `.npmrc` to `apps/web-platform/.dockerignore`
- [ ] 2.8b Sweep the six agent-facing prose surfaces that would instruct the next agent to recreate `bun.lock`
- [ ] 2.8c Fix `worktree-manager.sh:1544` root branch (add the lockfile detection its per-app branch already has)
- [ ] 2.8d Decide `AGENTS.rules.md:118` explicitly; if editing, route through the AP-017 / ADR-092 ack path
- [ ] 2.9 Add `name` + `overrides` to root `package.json`; repair root `package-lock.json`'s `name`
- [ ] 2.10 Extend `lockfile-sync` to root and invoke both guards (**after** 2.9, or the gate fails on its own introduction commit)

## Phase 3 — Drain the alert backlog

- [ ] 3.1 `apps/web-platform`: nanoid, js-yaml (both lines), hono, @hono/node-server, ip-address, fast-uri, undici, brace-expansion via `overrides`, and the OTel three-package chain
- [ ] 3.2 `pencil-setup/scripts`: hono, @hono/node-server, ip-address, fast-uri
- [ ] 3.3 Root: js-yaml (both lines), brace-expansion — requires a **new** `overrides` block; no `bun.lock` resync needed
- [ ] 3.4 Leave alerts 144, 161, 162, 170 open with the reachability reason and the recorded same-origin-proxy residual. Never dismiss
- [ ] 3.5 Verify no package landed on a major past target (undici 7.x, @hono/node-server 1.x, js-yaml 3.15.1/4.3.1, nanoid 3.3.x)

## Phase 4 — Dependabot PR queue

- [ ] 4.1 Write `scripts/close-superseded-dependabot-prs.sh` — idempotent and resumable
- [ ] 4.2 Re-verify subsumption immediately before each close; escalate rather than close on a raised target
- [ ] 4.3 Run only after the consolidated PR merges. Accept Dependabot self-closes as a valid disposition

## Phase 5 — Code-scanning alerts

- [ ] 5.1 Create the alert-203 tracking issue explicitly (medium severity, so `codeql-to-issues.yml` will not have filed one); apply `keep-open` **before** dismissing; record the reason in a comment
- [ ] 5.2 Dismiss alert 203 with a space-separated `dismissed_reason`
- [ ] 5.3 Add PWA update-accept telemetry + a Sentry alert rule; fold coverage into the existing `sw-update.test.ts`
- [ ] 5.4 Fix alerts 213/214 by removing the `bash -c` inline-script sink, preserving the execute-don't-match property

## Phase 6 — Verify and report

- [ ] 6.1 Re-measure converted-job timings against the +5-minute budget
- [ ] 6.2 Dispatch each converted scheduled workflow (`gh workflow run`)
- [ ] 6.3 Re-query the alerts API in-session with backoff; report the actual open set itemized by ID against the derived expectation of 4
- [ ] 6.4 Assert inline from the regenerated lockfiles that no cleared package remains vulnerable
- [ ] 6.5 File follow-ups with **both** `action-required` and `decision-challenge` and a concrete milestone
- [ ] 6.6 Put the plain-language consequence in the PR **title** and the follow-up issue **titles** — the digest never reads PR bodies

## Definition of done

All pre-merge acceptance criteria in the plan pass, both guards are green with their scanned-set
counts above all floors, every mutation-matrix row drives its guard RED, and the post-merge criteria
are executed in-session rather than deferred to any human or scheduled probe.
