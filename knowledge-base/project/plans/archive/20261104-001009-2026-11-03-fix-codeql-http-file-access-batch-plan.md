---
title: "fix(server): bound the three open js/http-to-file-access and js/file-access-to-http CodeQL flows (alerts #215, #230, #280)"
type: fix
date: 2026-11-03
slug: fix-codeql-http-file-access-batch
branch: feat-one-shot-codeql-215-230-280-http-file-access
lane: single-domain
priority: p2-medium
domain: engineering
---

# fix(server): bound the three open js/http-to-file-access and js/file-access-to-http CodeQL flows (alerts #215, #230, #280)

Three open medium CodeQL alerts in the `javascript-security-extended` suite flag
remote/file data flows across the filesystem boundary in `apps/web-platform/server/`:

| Alert | Rule | Sink | Flow |
|---|---|---|---|
| #215 | `js/file-access-to-http` (CWE-200) | `_cron-safe-commit.ts:1137` — `body: prBody` in `POST /repos/{owner}/{repo}/pulls` | file-derived text (caller `config.prBody`, e.g. compound-promote's `agentsPointerNote(…, proposed_diff_unified)`; dropped-path names via `safeMd(e.path)`) → GitHub API |
| #230 | `js/http-to-file-access` (CWE-434/912) | `c4-stage-sources.ts:475` — `writeFile(target, buf, { flag: "wx", mode: 0o600 })` | GitHub blob API bytes / `known` buffers / `blobCache` hits → workspace file |
| #280 | `js/http-to-file-access` (CWE-434/912) | `cron-compound-promote.ts:1224` — `writeFile(p, text)` inside `deriveDiff` | `base` (`git show` bytes) + `after` (base + model `new_lines`) → private `mkdtemp` scratch |

## Overview

Each flow is already substantially mitigated but each leaves one gap that the
prescribed fix classes (size caps, content/integrity validation, allowlisted
output paths) close at the sink:

- **#215** — `prBody` is the one unbounded string reaching the GitHub request.
  Callers can embed file-derived diffs (`agentsPointerNote`); an oversize body
  both widens the egress surface and risks a 422 the `alreadyExists` fallback
  would misread. Fix: a `MAX_PR_BODY_CHARS` cap in `safeCommitAndPr` with the
  file's existing loud-truncation idiom (⚠️ marker + `reportSilentFallback`),
  applied to the assembled body so `prBodyExtras` cannot silently widen it
  either.
- **#230** — the fetch path verifies `buf.length === s.size` and
  `gitBlobSha(buf) === s.sha`, but the `cacheGet`/`known` hit paths write `buf`
  without re-checking integrity at the sink. Keys are derived from
  `gitBlobSha`, so this is defense-in-depth, not a live hole — still, a single
  sink-side check makes the invariant uniform and cheap. Fix: verify
  `gitBlobSha(buf) === s.sha && buf.length === s.size` immediately before the
  write, covering all three provenance paths.
- **#280** — `base` is byte-capped pre-buffer (`EDIT_TARGET_MAX_BYTES`) and
  `new_lines` is count/per-line/charset/credential/render-hazard gated, but the
  concatenated `text` reaching `writeFile` has no explicit total-byte bound
  adjacent to the sink. Fix: refuse when
  `base.length + Σ newLines.length` exceeds `EDIT_TARGET_MAX_BYTES +
  EDIT_NEW_LINES_MAX × lineCap` inside `deriveDiff`, before the scratch write.

## Premise Validation

- Alert numbers verified live: `gh api repos/{owner}/{repo}/code-scanning/alerts/{215,230,280}`
  → all `state: open`, medium, at the stated `path:line`.
- GitHub refs #215/#230/#280 resolve to unrelated Feb-2026 issues/PRs
  (`Parallel pre-flight review agents`, `ops-provisioner agent v2.25.0`,
  `Archive working properly?`) — coincidental number collision, not work-target
  issues. Per scope, medium severity files no tracker issues; PR body cites
  alert numbers only.
- No cited issues/PRs/migrations to re-validate. Mechanism vs ADR corpus:
  size caps + integrity checks + allowlisted paths match ADR-050 amendment
  2026-09-24 (C4 staging security model) and the `#7122` exactPaths precedent;
  no rejected-alternative conflict.

## Property List / Cut List

- Property 1: no unbounded string reaches `POST /pulls` `body`.
- Property 2: bytes written to a staged `.c4` source equal the tree-declared
  blob (sha + size) on EVERY provenance path (fetch, cache, `known`).
- Property 3: scratch writes in `deriveDiff` are byte-bounded before the write.
- Cut List: none — no repo helper provides any of the three bounds (grepped
  `apps/web-platform/{server,lib}` for `boundedWrite|safeWriteFile|MAX_WRITE`;
  zero hits). Existing `MAX_STAGED_*`/`EDIT_*` caps cover their own layers, not
  these sink-adjacent gaps.

## Research Insights

- Precedent: CodeQL alert #86 (`js/http-to-file-access`, `push-branch.ts`) was
  dispositioned "well-mitigated → won't fix"
  (`learnings/2026-04-13-codeql-alert-triage-and-issue-automation.md`); per this
  run's scope, no dismissal without operator sign-off — unclosed alerts are
  documented in the PR body.
- Precedent: CodeQL #234 (`js/request-forgery`) fixed by pinning egress at the
  chokepoint (`github-api.ts` `assertGithubApiAbsoluteUrl`) — same shape as the
  #215 sink-side bound.
- Precedent: PR #11276 (`js/file-system-race` in the same
  `cron-compound-promote.ts`) — prior CodeQL fix in this file.
- Query help (codeql.github.com): `js/file-access-to-http` = CWE-200,
  `js/http-to-file-access` = CWE-434/912, precision medium; recommendation is
  "examine the highlighted code closely to ensure it is behaving as intended" —
  no recognized sanitizer API; bounds + validation are the fix shape.
- These CodeQL rules are dataflow queries; post-fix, alerts may remain flagged
  if the flow still exists syntactically. Each fix is real hardening regardless;
  any alert still open after merge is dispositioned in the PR body.
- `Reviewed-Coverage: sequential-fallback` — no Task fan-out available in this
  harness; all research ran inline in the pipeline session.

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch; nothing to reconcile.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open -L 200` bodies contain
none of the three file paths.

## Implementation Phases

### Phase 1 — `_cron-safe-commit.ts` (#215)

- Add `export const MAX_PR_BODY_CHARS = 60_000` (below GitHub's ~64 KiB body
  ceiling, sized so `prBodyExtras` + marker fit).
- After `prBody` assembly (post-`prBodyExtras`), if over cap: truncate to
  `MAX_PR_BODY_CHARS - marker.length`, append
  `\n\n> ⚠️ PR body truncated at <N> chars (Sentry op \`safe-commit-pr-body-truncated\`)`,
  and `reportSilentFallback(null, { feature: "safe-commit", op: "safe-commit-pr-body-truncated", … })`
  — mirrors the dropped-path loud-truncation idiom in the same function.

### Phase 2 — `c4-stage-sources.ts` (#230)

- Immediately before `writeFile(target, buf, …)` (all provenance paths converge
  here), assert `buf.length === s.size && gitBlobSha(buf) === s.sha`, else
  `throw new StageAbort({ ok: false, reason: "io_error", detail: "stage: blob integrity mismatch" })`.
  Covers `cacheGet`/`known` hits that currently skip the fetch-path check.

### Phase 3 — `cron-compound-promote.ts` (#280)

- In `deriveDiff`, before the scratch `writeFile` loop, compute the assembled
  size (`base.length` + sum of `newLines`) and `return fail("too-large")` when
  it exceeds `EDIT_TARGET_MAX_BYTES + EDIT_NEW_LINES_MAX * SKILL_EDIT_LINE_MAX_CHARS`
  (~140 KB — uses the larger per-line cap so both target types fit; the
  per-target `editLineMaxChars` check already ran upstream in `newLinesCause`).

### Phase 4 — Tests

- `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts`: a
  `config.prBody` over `MAX_PR_BODY_CHARS` is truncated with the ⚠️ marker and
  reports `safe-commit-pr-body-truncated`.
- `apps/web-platform/test/c4-stage-sources.test.ts`: a `known`/`cache` buffer
  whose bytes do not match `s.sha`/`s.size` refuses with
  `blob integrity mismatch` (construct via the exported test seam if a direct
  path is not reachable).
- `apps/web-platform/test/server/inngest/cron-compound-promote-draft-edit.test.ts`:
  an edit whose assembled `after` exceeds the derived cap returns
  `failure: "too-large"` (or the `edit-derive-failed` wrapper cause).

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` — PR-body cap
- `apps/web-platform/server/c4-stage-sources.ts` — sink-side blob integrity check
- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` — derive-side byte bound
- `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts` — truncation case
- `apps/web-platform/test/c4-stage-sources.test.ts` — integrity-mismatch case
- `apps/web-platform/test/server/inngest/cron-compound-promote-draft-edit.test.ts` — too-large case

## Files to Create

- (none)

## User-Brand Impact

- **If this lands broken, the user experiences:** compound-promotion/safe-commit
  crons fail to open their draft PRs (PR body cap misfire) or C4 diagram staging
  refuses legitimate sources (integrity check misfire) — visible as missing
  PRs/stale diagrams, never silent corruption.
- **If this leaks, the user's data is exposed via:** the pre-existing unbounded
  `prBody` egress — the cap narrows, never widens, the exposure surface.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** server-internal cron hardening with
  bounded fail-closed behavior; no user-facing surface changes.

*Scope-out override:* `threshold: none, reason: server-side byte bounds inside
private scratch/staging paths; no user data surface changes shape`

## Observability

```yaml
liveness_signal:
  what:            "Sentry cron monitors already on the three crons (safe-commit op tags, cron-compound-promote SENTRY_MONITOR_SLUG) plus c4 staging failure refusals surfaced to the caller"
  cadence:         "per-run"
  alert_target:    "Sentry issue stream"
  configured_in:   "apps/web-platform/server/inngest/functions/_cron-safe-commit.ts (reportSilentFallback ops) and cron-compound-promote.ts (SENTRY_MONITOR_SLUG)"

error_reporting:
  destination:     "Sentry web-platform via reportSilentFallback"
  fail_loud:       "new ops: safe-commit-pr-body-truncated; stage refusal detail 'blob integrity mismatch'; deriveDiff fail('too-large') — all land in the existing Sentry path"

failure_modes:
  - mode:          "caller supplies oversize prBody (file-derived diff > cap)"
    detection:     "safe-commit-pr-body-truncated op + in-PR ⚠️ marker (in-surface signal — emitted by the worker itself)"
    alert_route:   "Sentry"
  - mode:          "cache/known blob bytes diverge from tree sha"
    detection:     "StageAbort 'blob integrity mismatch' io_error refusal (in-surface)"
    alert_route:   "Sentry via existing stage-failure reporting"
  - mode:          "model edit inflates assembled text past derived cap"
    detection:     "deriveDiff fail('too-large') → edit-derive-failed refusal + draft-edit-error op (in-surface)"
    alert_route:   "Sentry"

logs:
  where:           "Inngest run logs + Sentry reportSilentFallback events"
  retention:       "existing Sentry/Inngest retention"

discoverability_test:
  command:         "grep -n MAX_PR_BODY_CHARS apps/web-platform/server/inngest/functions/_cron-safe-commit.ts"
  expected_output: "MAX_PR_BODY_CHARS"
```

## Guard Contract

### Guard 1 — staged-blob integrity at the write sink

**Property.** Every buffer written to a staged `.c4` source path is exactly the
tree-declared blob — `gitBlobSha(buf) === s.sha` and `buf.length === s.size` —
regardless of which of the three provenance arms produced it.

**Assembly.** The single `writeFile(target, buf, …)` sink inside `stageWith`'s
worker; the three provenance arms — `cacheGet(cacheKey(s.sha))`,
`known.get(s.sha)`, and the `/git/blobs` GET — all converge at the assert
immediately preceding the write. There is no second write site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Corrupt one byte of a `known`/`cache` buffer (correct `s.sha` key, wrong bytes) | RED |
| 2 | Delete the sink-side assert while keeping the fetch-path checks (guard's own dispatch vacuous on the two non-fetch arms) | RED |
| 3 | Stage two sources where the SECOND buffer mismatches (first passes — a check that stops at member one is the defect) | RED |
| 4 | Truncate a buffer by one byte so `buf.length !== s.size` with sha untouched | RED |
| 5 | Stub `gitBlobSha` to return `s.sha` unconditionally (vacuous harness — assert passes on any bytes) | suite must still fail |
| 6 | Stage a source whose buffer genuinely equals the declared blob (must-PASS, the canonical happy path) | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix THREE CodeQL alerts in one PR — js/http-to-file-access / js/file-access-to-http (medium)" | Phases 1–3 | mapped |
| 2 | "#215 — apps/web-platform/server/inngest/functions/_cron-safe-commit.ts:1137" | Phase 1 | mapped |
| 3 | "#230 — apps/web-platform/server/c4-stage-sources.ts:475" | Phase 2 | mapped |
| 4 | "#280 — apps/web-platform/server/inngest/functions/cron-compound-promote.ts:1224" | Phase 3 | mapped |
| 5 | "real finding … fix via size caps, content-type/extension validation, allowlisted output paths, or streaming with bounds" | the three sink-adjacent bounds | mapped |
| 6 | "or false positive (leave open, note in PR body; do NOT dismiss without operator sign-off)" | PR-body disposition note for any alert still open post-merge | mapped |
| 7 | "No tracker issues for medium severity — reference alert numbers in the PR body" | ship/PR-body step | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| prBody cap (`_cron-safe-commit.ts`) | "fix via size caps" | asked |
| sink-side sha/size assert (`c4-stage-sources.ts`) | "content-type/extension validation" (integrity validation at the sink; cache/known paths lack it) | asked |
| assembled-text cap (`cron-compound-promote.ts`) | "fix via size caps … or streaming with bounds" | asked |
| test additions (3 files) | "Fix THREE CodeQL alerts" — fixes unverifiable without regression tests | inferred — justification: `cq-write-failing-tests-before` requires red tests preceding each fix |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 6 | Estimated changed lines: ~120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `_cron-safe-commit.ts` refuses to send a `body:` over `MAX_PR_BODY_CHARS`; truncation carries the ⚠️ marker and reports `safe-commit-pr-body-truncated`
- [ ] `c4-stage-sources.ts` verifies `gitBlobSha(buf) === s.sha && buf.length === s.size` on the single line preceding `writeFile(target, buf)` for fetch, cache, and `known` provenance alike
- [ ] `cron-compound-promote.ts` `deriveDiff` returns `fail("too-large")` before any scratch `writeFile` when the assembled text exceeds the derived cap
- [ ] New tests fail on `origin/main` and pass with the fixes
- [ ] Targeted suites pass: `cron-safe-commit`, `c4-stage-sources`, `cron-compound-promote-draft-edit` tests + typecheck on touched files
- [ ] PR body carries a per-alert disposition table (alert / rule / fix-or-mitigated / residual) with `Reviewed-Coverage: sequential-fallback` disclosure

## Test Scenarios

- `unit` — Given `config.prBody` of `MAX_PR_BODY_CHARS + 500` chars, when `safeCommitAndPr` assembles the body, then the POST body is ≤ cap and ends with the truncation marker.
- `unit` — Given a `known` buffer whose `gitBlobSha` ≠ `s.sha`, when staging runs, then it aborts with `blob integrity mismatch` and no file is written.
- `unit` — Given an edit whose `new_lines` push the assembled `after` past the derived cap, when `deriveDiff` runs, then it returns `failure` before touching the filesystem.
- `integration` — Given the existing staging happy path (sha/size-verified blob fetch), when staging runs, then it still succeeds (the sink-side check accepts what the fetch-path check accepted).

## Domain Review

**Domains relevant:** engineering only

No cross-domain implications — internal server-side security hardening; no UI
surface, no regulated-data surface, no infra, no marketing touchpoints.

### Product/UX Gate

Not applicable — no UI-surface file in Files to Edit/Create (mechanical
override scan: `apps/web-platform/server/**` + `test/**` only).

## Sharp Edges

- `buf` has THREE provenance paths in `c4-stage-sources.ts` (`cacheGet`,
  `known`, blob fetch); the existing sha/size verify sits inside the fetch-only
  branch — the new check must run AFTER provenance resolution, before the path
  checks/write, not be moved earlier.
- `prBody` assembly happens BEFORE `prBodyExtras` join order matters — cap the
  FINAL assembled string so extras cannot push it over.
- `EDIT_TARGET_MAX_BYTES` gates `cat-file -s` (bytes), while `text.length` is
  chars — ASCII-only `newLines` keeps chars == bytes for the added portion, and
  base was already byte-gated, so summing `length`s is conservative.
- Do NOT add `// codeql[...]` suppression comments — the repo has zero precedent
  (`grep -rn 'codeql\['` over apps/plugins/scripts: no hits); dispositions go in
  the PR body.
- Commit author: repo's CLA identity (Jean Deruelle <jean.deruelle@jikigai.com>),
  never `devin-ai-integration[bot]`.

## References

- CodeQL query help: `js/file-access-to-http` (CWE-200), `js/http-to-file-access` (CWE-434/912) — codeql.github.com codeql-query-help
- Prior dispositions: `knowledge-base/project/learnings/2026-04-13-codeql-alert-triage-and-issue-automation.md` (alert #86), plan `20261013-051752-2026-09-29-sec-codeql-alert-234-server-side-request-forgery-plan.md` (alert #234)
- Prior same-file fix: PR #11276 (`js/file-system-race` in `cron-compound-promote.ts`)
