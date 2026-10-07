<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO new infrastructure. The flagged
     `doppler secrets set` token is a verbatim quote of an EXISTING call inside
     workspaces-luks-verify.yml that this change wraps behind a sanitizing helper —
     not a prescribed operator provisioning step. -->

---
title: "fix(ci): four sibling CI-machinery repairs — cron-stale liveness source, worktree hook ordering, gh-argv --arg sentinel, doppler_call() stderr hygiene"
type: fix
date: 2026-10-06
slug: fix-ci-machinery-sweep
branch: feat-one-shot-7255-8480-9612-9613-ci-machinery
issue: 7255
closes: [7255, 8480, 9612, 9613]
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix(ci): four sibling CI-machinery repairs

## Overview

Four independently-filed CI-machinery defects, all in the same defect family — scheduled-cron
observability plumbing that silently lost the property it was built to hold:

- **#7255** — `cmd_cron_run_stale` in `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh`
  returns 999 unconditionally because its `gh run list --workflow=scheduled-content-vendor-drift.yml`
  query targets a workflow that no longer exists (the job is now the Inngest cron
  `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`).
- **#8480** — `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` false-denies edits from linked
  worktrees: the `"$PROJECT_DIR"/*` case arm strips a worktree path to
  `.worktrees/feat-*/.github/workflows/...`, so the `git cat-file -e origin/main:` check fails and the
  edit is denied as if new.
- **#9612** — the `--arg`-in-`gh`-argv defect class (gh rejects `--arg` as an unknown flag;
  cli/cli#10263) has shipped five times; prior fixes were file-local pins. Needs a repo-wide sentinel
  over `.github/workflows/*.yml` and `scripts/*.sh`, plus normalization of 13 inconsistent dedupe
  fault policies to the fail-open-with-`::error::` shape.
- **#9613** — in `workspaces-luks-verify.yml`, the marker step's `marker_state()` sanitizes doppler
  stderr, but the `secrets set`, read-back `get`, and `secrets delete` siblings emit doppler stderr
  raw on failure. Wrap all four in a `doppler_call()` helper; the Guard-3 mutation anchors pinning the
  call shapes move in the same commit.

## Problem Statement / Motivation

Each defect is a silent-degradation shape: a probe returning its own safe default (#7255), a guard
misreading its operand (#8480), a filing step that dies before the alarm it exists to file (#9612),
and remote error text reaching a run log unsanitized (#9613). None produce operator-visible signal at
failure time. The fixes are small but each sits inside heavily-pinned test infrastructure, so the
plan's main risk is mechanical: moving every test anchor that references the changed call shapes.

## Proposed Solution

Four workstreams, one PR (sibling defect family, all CI machinery, shared test-harness surface):

### A. #7255 — repoint `cmd_cron_run_stale` at the attestation-PR head branch

Replace the dead-workflow `gh run list` query with a `gh pr list` query over the cron's own GitHub
artifact: the weekly attestation PR, whose head branch prefix is the exported constant
`ATTEST_BRANCH_PREFIX = "ci/vendor-attest"` (`cron-content-vendor-drift.ts:129`). ADR-203's machinery
creates one such PR **every run** — `chore(vendor-drift): attest … unchanged` merges even when zero
files drift — so "days since the newest `ci/vendor-attest-*` PR was created" is a faithful "days
since the check last ran to completion".

Query (verified live 2026-10-06 — returns #9522 created 2026-10-05T11:17:34Z, currently open):

```bash
gh pr list --search "head:ci/vendor-attest" --state all --limit 10 \
  --json createdAt --jq '[.[].createdAt] | max // empty'
```

Rationale for `createdAt` over `mergedAt`: merge latency is days and unrelated to run health
(#8166 merged +3d; #9522 still open). PR *creation* is the completed run's output. `--state all` is
load-bearing: `--state merged` against `head:` returned empty in testing while `--state all` returns
both rows. `limit 10` + `max` aggregation removes dependence on search-result ordering. gh's embedded
`--jq` (gojq) is kept — the defect class (#9533) is `--arg`, never `--jq`; no external `jq` dependency
is added.

Preserve every existing guard unchanged: token presence, `command -v gh`, `timeout 5s`, strict
RFC3339 regex, `days < 0 → 999`, and 999 on all failure modes (fail-safe direction). Update the
stale comments in `notice-frontmatter.sh` (header :12-13, the ⚠️ block in `cmd_cron_run_stale`),
`gdpr-gate.sh` (:118-128 "INERT TODAY" block), and `gdpr-gate/SKILL.md` (:326-332) — the
`gdpr-gate-self-test.test.sh` parity check requires the `scheduled-content-vendor-drift.yml` literal
to reach zero in the parser AND SKILL.md together.

### B. #8480 — reorder the rel-path case arms

In `new-scheduled-cron-prefer-inngest.sh` (:96-99) swap the two arms so
`/*/.github/workflows/*` (basename extraction) wins over `"$PROJECT_DIR"/*`. For a path directly under
`$PROJECT_DIR` the basename arm produces the identical `rel_path`, so the reorder changes nothing for
the main checkout and fixes worktree paths. Nested `.github/workflows/` under subdirectories reduce
to basename — GitHub only reads root `.github/workflows/`, so that reduction cannot smuggle an active
workflow past the gate.

### C. #9612 — repo-wide sentinel + dedupe normalization

(a) New `scripts/lint-gh-argv-arg.py` + `scripts/lint-gh-argv-arg.test.sh`, registered in
`scripts/test-all.sh` as unit + `-live` suites (ADR-166 lint-gate precedent; same both-halves shape
as `lint-workflow-errexit-capture`). The linter scans every `.github/workflows/*.yml|yaml` and
`scripts/*.sh`: join `\`-continuations into logical lines, strip comments (quote-aware `#` handling —
the fixed files carry comments like "`gh --jq` does not forward `--arg`" that must NOT fire), split
each logical line into command segments on unquoted `|` `||` `&&` `;`, and flag any segment whose
command resolves to `gh` while carrying a standalone `--arg` token in its argv.

(b) Normalize 13 sites to the fail-open-with-`::error::` shape of `workspaces-luks-verify.yml`
(~:896-909) / `scheduled-actions-queue-health.yml` (:135-143, :191-199):

```bash
if ! EXISTING="$(gh issue list ... | jq -r --arg t "$ISSUE_TITLE" '...')"; then
  echo "::error::<step>: dedupe query failed — filing without dedupe; a duplicate is the deliberate trade against filing nothing."
  EXISTING=""
fi
```

Sites: `scheduled-zot-restart-loop.yml` :240, :293, :432, :480, :516;
`scheduled-inngest-health.yml` :510, :537, :566, :586, :606, :633, :1354 (bare shape),
:1052 (silent `|| true`). Keep the documented `search_rc` fail-closed shape at
`scheduled-zot-restart-loop.yml` ~:391 unchanged.

### D. #9613 — `doppler_call()` stderr hygiene

Introduce one helper in the marker step body of `workspaces-luks-verify.yml` that captures `2>&1`,
on success prints captured stdout (callers keep `>/dev/null` to suppress the config dump), and on
failure prints the sanitized `[doppler-stderr]` diagnostic (the existing marker_state redact:
`DOPPLER_TOKEN` substitution + `dp.*` token-shape redact + non-printable strip + per-line prefix +
8192-char cap) to stderr. `marker_state()` delegates its `get` to the helper; the three sibling calls
(`set`, read-back `get`, `delete`) route through it, keeping their existing `|| { ... }` handlers.

Test-anchor moves (same commit — `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`):
structural checks at ~:1450/:1454 (`doppler secrets set/delete ... >/dev/null`, `get --plain`),
census `VERB` regex (:1899) gains the `doppler_call` form (ALLOWED_SITES stays 2), `g3_mut` row 3
(delete-call-shape anchor) and row 17g (the sanitize block now inside `doppler_call`) re-anchored, row
17d/17a/17e anchors unchanged. New scenarios asserting `[doppler-stderr]` lands on set- and
delete-fault paths (reusing `FIXTURE_DOPPLER_SET_FAIL` / `FIXTURE_DOPPLER_DELETE_FAIL`), registered
into `G3_EXPECTED_IDS`, and folded into mutation row 17g's id list.

## Technical Considerations

- **Hook context.** `cmd_cron_run_stale` runs inside `git commit` (lefthook → gdpr-gate) on dev
  hosts: GH_TOKEN is the only reliably-present credential; `gh pr list` resolves the repo from the
  checkout's remote exactly as `gh run list` did. No new credential, no Doppler/Sentry client.
- **Why not the alternatives (Cut List below):** Sentry API needs `SENTRY_ACTIONS_RO_TOKEN` (a GHA
  secret absent on dev hosts — the probe would stay 999); Inngest API needs signing keys; Better
  Stack needs Doppler. All three fail the "present on a dev host inside a git hook" test.
- **Backdating semantics untouched.** `gdpr-gate.sh`'s `MIN(cron, notice)` combination and banner
  precedence are unchanged; only the probe's data source moves.
- **`2>&1` merge caveat (D).** A `secrets get` success that also writes stderr would pollute `got`.
  The real CLI prints nothing to stderr on success, and `marker_state` already merges today, so the
  contract is preserved; the read-back equality check pins it.
- **`ALLOWED_SITES` invariant (D).** The census's "exactly two write/delete sites" must still count
  the `doppler_call secrets set|delete` spellings; the VERB regex update is the move.
- **Sentinel precision (C).** `--arg` must match as a standalone argv token, not inside a quoted jq
  program; the segment must end at unquoted pipes so `gh … | jq --arg` (the correct form) stays green.
- **`set -euo pipefail` interplay (B, C).** The dedupe normalization replaces bare `$(…)` with
  `if ! VAR="$(…)"` — pipeline rc is captured, never aborts mid-step; fail-open is deliberate per
  the issue (a duplicate issue is recoverable; a missed filing is not).

## Research Insights

**Premise validation (Phase 0.6).** All eight cited files verified present at `origin/main` `d58f804f78`
(worktree base). Issues #7255/#8480/#9612/#9613 all OPEN, zero `closedByPullRequestsReferences`.
Linked-PR probes surfaced only citations (#7241→#7234, #7984→#7836, #5220 — prose mentions, none in
`closingIssuesReferences` of these issues). Mechanism check vs ADR corpus: ADR-203 (attestation
write-back) is the enabling mechanism this fix *consumes*; ADR-166 is the precedent for the lint
sentinel. No cited mechanism sits in any ADR's rejected-alternatives table.

**Property List (Phase 0.6b).**

1. `cron-run-stale` resolves a real day-count from a source that can see the Inngest cron.
2. Worktree paths under the repo dir are not false-denied by the scheduled-cron hook.
3. `gh`-argv `--arg` is caught mechanically anywhere in workflows/scripts, not per-file.
4. Dedupe lookups fail open with a `::error::` breadcrumb instead of aborting mid-alarm or staying silent.
5. All four doppler calls route stderr through one sanitizer.

**Cut List (Phase 0.6b).**

| Cut mechanism | Property it would buy | Why cut |
|---|---|---|
| Sentry cron-monitor check-in API read | prop 1 | needs `SENTRY_ACTIONS_RO_TOKEN`; absent on dev-host git hooks → probe still 999 |
| Inngest API run-status read | prop 1 | needs signing keys; not on dev hosts |
| `SOLEUR_*` marker → Better Stack read-back | prop 1 | needs Doppler creds inside a `git commit` hook — heavier and new dependency |
| New GHA status workflow for the cron | prop 1 | new infra to observe infra; the attestation PR is already the artifact |
| Extend sentinel to `.github/actions/*/action.yml`, `.claude/hooks/*.sh` | prop 3 | issue scopes to workflows + scripts; noted as deliberate boundary |
| Changing `MIN`→`MAX` semantics in gdpr-gate.sh | — | out of scope; semantics pinned by existing tests |

**Relevant files.**

- `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh` (:186-244 probe; :12-14 header note)
- `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` (:105-161 binding + comment :118-128)
- `plugins/soleur/skills/gdpr-gate/SKILL.md` (:326-332 doc rows — parity-checked)
- `plugins/soleur/test/test-helpers.sh` (`make_gh_stub` :151, `make_gh_stub_sleep` :169 — serve `run list` only)
- `plugins/soleur/test/{notice-frontmatter,_base-notice-frontmatter}.test.sh` (TS-cron-1..5, TS-cron-empty)
- `plugins/soleur/test/fixtures/gdpr-gate-stale/gh-stub/gh` (Case B stub; `run list` branch)
- `plugins/soleur/test/gdpr-gate-self-test.test.sh` (:114-132 dead-workflow parity check; :136-137 stale comment)
- `plugins/soleur/test/vendor-drift-workflow.test.sh` (Inngest-side structural suite; optional ATTEST_BRANCH_PREFIX pin)
- `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` (:96-99) + `.test.sh`
- `.github/workflows/scheduled-zot-restart-loop.yml`, `scheduled-inngest-health.yml`, `workspaces-luks-verify.yml`
- `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` (G3 battery, census, g3_mut anchors)
- `scripts/test-all.sh` (:4599-4627 lint-suite registration block; SUITE_GLOBS do NOT cover `scripts/*.test.sh`)

**Conventions.** Two-stage `jq --arg` is the repo's post-#9533 canonical form; `|| true` on dedupe is
a known-bad silent variant. Fail-open-with-`::error::` reference: `workspaces-luks-verify.yml`
:896-909. Fail-closed `search_rc` reference: `scheduled-zot-restart-loop.yml` :391 (kept).

**Community/functional discovery (Phase 1.5/1.5b).** Internal CI-machinery repair; no stack gap and no
plausibly-overlapping community artifact (the fixes are repo-local call shapes). Recorded as assessed-
not-applicable in this pipeline context (no subagent spawn available — see Deviations).

## Open Code-Review Overlap

| Issue | File(s) shared | Disposition |
|---|---|---|
| #8659 (test-helpers EXIT-trap refactor) | `test-helpers.sh`, both notice-frontmatter suites, `test-all.sh` | Acknowledge — orthogonal refactor of the same files; our edits are additive (stub args, new cases) and do not touch trap composition. Not folded: different concern, needs its own cycle. |
| #7942 (mutation-battery naming) | `test-helpers.sh`, `test-all.sh` | Acknowledge — unrelated to call-shape anchors. |
| #8593 (#6793 probe-gate window) | `scheduled-inngest-health.yml` | Acknowledge — different concern (probe window vs dedupe fault policy). |

## User-Brand Impact

- **If this lands broken, the user experiences:** a CI-machinery surface misbehaving — the gdpr-gate
  staleness banner showing spuriously, the hook denying a legitimate edit, a monitor alarm that fails
  to file (or files a duplicate), or a doppler error line reaching a run log without redaction. All
  internal-tooling surfaces; the operator sees degraded CI behavior, not product breakage.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the LUKS soak marker's
  verdict machinery (the marker guards the user-data at-rest attestation for workspaces) — but this
  diff changes only stderr hygiene of the marker plumbing, not the verdict logic; a `DOPPLER_TOKEN`
  or foreign `dp.*` token could reach CI logs only if the sanitizer regresses, and the G3 battery +
  DUMPED_SECRET_SENTINEL/`dp.st.*` log greps pin that.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI machinery only; the one compliance-adjacent
  surface (marker soak verdict) is covered by an existing mutation battery that this change extends,
  and fail-safe directions are preserved (999-on-error, gate-fails-closed).
- `threshold: none, reason: the sensitive-path match (apps/web-platform/infra/ test file) is assertion plumbing for the marker verdict, not the verdict path itself; verdict semantics are unchanged and pinned by the G3 battery.`

## Observability

```yaml
liveness_signal:
  what: "the surfaces themselves are observability plumbing; the change's own signal is the sentinel suite going red on a --arg-in-gh-argv regression, and cron-run-stale resolving <999 when the attestation PR stream is alive"
  cadence: "per CI run (test-all gate) / per git commit (gdpr-gate hook)"
  alert_target: "CI gate failure on the PR; operator-attested-mode banner on the gate"
  configured_in: "scripts/test-all.sh run_suite registration; plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
error_reporting:
  destination: "run log — ::error:: breadcrumbs on dedupe failure; [doppler-stderr] lines on doppler failure; gdpr-gate emit_incident rows (gdpr-gate-cron-binding)"
  fail_loud: "::error::dedupe query failed … / [doppler-stderr] … / suite RED lines"
failure_modes:
  - mode: "attest-PR stream stops (cron dead) or query breaks"
    detection: "cron-run-stale returns 999 → operator-attested banner resumes; TS-cron suites pin the query shape"
    alert_route: "the banner itself + CI suite red"
  - mode: "sentinel stops detecting (broken classifier)"
    detection: "unit suite's verify-the-verifier fixture + anti-vacuity MIN_ASSERTIONS floor"
    alert_route: "scripts/lint-gh-argv-arg suite RED"
  - mode: "doppler stderr escapes unsanitized"
    detection: "G3 battery dp.st.*-in-logs grep + [doppler-stderr] needle scenarios"
    alert_route: "workspaces-luks-verify-workflow suite RED"
logs:
  where: "GHA run logs (workflow steps), local hook stdout/stderr"
  retention: "GitHub run retention; incident rows in .claude/.rule-incidents.jsonl"
discoverability_test:
  command: "bash -c 'python3 scripts/lint-gh-argv-arg.py --root . >/dev/null && echo \"gh-argv clean\"'"
  expected_output: "gh-argv clean"
```

## Guard Contract

### Guard 1 — `lint-gh-argv-arg` sentinel

**Property.** No `gh` invocation in any scanned file carries a standalone `--arg` token in its own
argv (the flag belongs to a downstream `jq`, never to `gh`).

**Assembly.** Every `.github/workflows/*.yml|yaml` and `scripts/*.sh` file enumerated by directory
walk at scan time (membership is structural — a new file entering either directory is scanned without
registration); within a file, every logical command line after `\`-continuation join and quote-aware
comment strip, segmented on unquoted `|`/`||`/`&&`/`;` — the argv boundary is the chokepoint.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Insert `EXISTING=$(gh issue list --json number,title --jq '…' --arg t "$T")` into a fixture workflow | RED — finding names file+line |
| 2 | Remove the `--arg` token pattern from the linter's token check (guard's own dispatch) | RED via a verify-the-verifier suite case that re-runs the linter against a known-bad fixture |
| 3 | Plant the defect in the *second* scanned file after a clean first file (scanner that returns after first file) | RED — finding on file 2 |
| 4 | Defect hidden behind a `\`-continuation (`gh … \` + `--arg t` on next line) or inside `$(…)` | RED — continuation-join/segment handling catches it |
| 5 | MUST-PASS: `gh … --json … \| jq -r --arg t "$t"` correct form; a `#` comment mentioning `--arg`; `--arg` inside a quoted jq program token | stays GREEN |
| 6 | HARNESS: neuter the suite's `fail()` to a no-op | RED via instrument self-test (helper-count proof, per test-helpers convention) |

### Guard 2 — worktree-path regression coverage on `new-scheduled-cron-prefer-inngest.sh`

**Property.** An `Edit`/`Write` payload whose `file_path` sits inside a linked worktree under the
project dir resolves `rel_path` to the repo-rooted `.github/workflows/<name>` so the
`origin/main` existence check is authoritative.

**Assembly.** The single `case` statement that produces `rel_path` (the only chokepoint — every
payload path flows through it before `git cat-file -e origin/main:`); driven by the hook test suite's
payload fixtures, not by enumerating today's paths.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the original arm order (`"$PROJECT_DIR"/*` first) | RED — worktree regression case denies-as-new and the test asserts allow |
| 2 | Delete the basename arm entirely (guard's own dispatch weakened) | RED — same case |
| 3 | Regression case's own pin weakened: assert on a path that does NOT exist on origin/main but shares the worktree prefix | RED — the deny-for-new arm must still fire under CLAUDE_PROJECT_DIR set (ordering fix must not over-allow genuinely-new files) |
| 4 | MUST-PASS: pre-existing cases a–f (new-file deny, marker allow, relative path) | stay GREEN |

### Guard 3 — `doppler_call` stderr hygiene (extension of the existing G3 battery)

**Property.** No doppler CLI diagnostic reaches the run log without the redact pipeline
(`DOPPLER_TOKEN` substitution, `dp.*`-shape redact, non-printable strip, per-line `[doppler-stderr]`
prefix, 8192 cap), and no success path drops the `>/dev/null` stdout suppression.

**Assembly.** Every `doppler secrets` invocation inside the marker step body — extracted verbatim
into `marker.sh` by the G3 structural harness, so the battery quantifies over the shipped text, not a
copy. Call-site count is additionally pinned by the census (`ALLOWED_SITES 2` for write/delete verbs).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `doppler_call` failure path prints `out` raw instead of sanitized (drop the redact line) | RED — `dp.st.foreign0fixture` needle scenario + the `dp.st.*`-in-logs grep |
| 2 | `doppler_call` swallows rc (returns 0 on failure — dispatch broken) | RED — S42/S51-style fault scenarios see the step proceed past a failed write/delete |
| 3 | A second unwrapped `doppler secrets delete` added beside the helper (coverage gap after a compliant first member) | RED — census `ALLOWED_SITES` count leaves 2 |
| 4 | `>/dev/null` dropped from the set call through the helper | RED — `DUMPED_SECRET_SENTINEL` grep |
| 5 | Reorder sanitize so per-line prefix precedes `tr` strip (order-dependent defect) | RED — `[doppler-stderr]` prefix assertion on fault scenarios |
| 6 | HARNESS: doppler stub stops recording (`DOPPLER_STUB_MODE=norecord`) | RED — existing row-10 zero-recorded-calls check |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "cmd_cron_run_stale resolves a real timestamp for the Inngest-hosted content-vendor-drift check, or the frontmatter field is retired if the banner no longer needs it." [#7255] | FR-A (Phase 1) — `gh pr list --search head:ci/vendor-attest` repoint | mapped |
| 2 | "A test pins the non-999 path, so a future move of the job reds instead of silently reverting to the sentinel." [#7255] | FR-A tests — stub serves `pr list`; argv-shape pin asserting `head:ci/vendor-attest` in the query; dead-workflow-literal parity to zero | mapped |
| 3 | "The ⚠️ warning block added by #7234 is removed once the binding actually resolves." [#7255] | FR-A comment/doc updates (parser + gdpr-gate.sh + SKILL.md) | mapped |
| 4 | "Reorder the case arms so `/*/.github/workflows/*` (basename extraction, always correct for this gate's file set) wins over the `$PROJECT_DIR` strip." [#8480] | FR-B | mapped |
| 5 | "Add a regression test that reproduces the worktree path case." [#8480] | FR-B — new case (g) in the hook test suite | mapped |
| 6 | "Add a `--arg`-in-`gh`-argv check (continuation-joined, comment-stripped, argv-scoped — the `gh +(api\|issue\|…) [^\|]*--arg` shape the queue-health hygiene block uses) somewhere cheap that covers every `.github/workflows/*.yml` and `scripts/*.sh`, not one file." [#9612] | FR-C-a — `scripts/lint-gh-argv-arg.py` + unit suite + test-all registration | mapped |
| 7 | "Normalize to the fail-open-with-`::error::` shape (`workspaces-luks-verify.yml` ~:896-909, now queue-health's two steps) or the deliberate `search_rc` fail-closed shape … `scheduled-zot-restart-loop.yml` :240, :293, :432, :480, :516 … `scheduled-inngest-health.yml` :510, :537, :566, :586, :606, :633, :1354 … :1052 — fail-open but *silent* (`|| true`)" [#9612] | FR-C-b — 13 site rewrites | mapped |
| 8 | "Wrap the four `doppler secrets` invocations in a `doppler_call()` helper that captures `2>&1`, applies the redact, and prints a sanitized diagnostic on failure — one definition, no drift." [#9613] | FR-D — helper + four call sites | mapped |
| 9 | "The Guard-3 mutation anchors that pin the call shapes must move with it." [#9613] | FR-D — test.sh anchor moves (struct checks, census VERB, g3_mut rows 3/17g, new S57/S58 + G3_EXPECTED_IDS) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `gh pr list --search "head:ci/vendor-attest"` as liveness source | "a liveness source that can see an Inngest cron — the Inngest API, a Sentry cron monitor check-in, or a `SOLEUR_*` marker the function emits that Better Stack already ingests — … Choose the cheapest reliable source" [#7255 + dispatch brief] | asked |
| `scripts/lint-gh-argv-arg.py` dedicated linter + `.test.sh` + test-all registration | "somewhere cheap that covers every `.github/workflows/*.yml` and `scripts/*.sh`" [#9612] | asked (form inferred — justification: ADR-166 lint-gate precedent is the repo's canonical "somewhere cheap"; a workflow step would only cover CI runs and could not run pre-merge locally) |
| Sentinel argv tokenization (unquoted-pipe segmenting) | "continuation-joined, comment-stripped, argv-scoped" [#9612] | asked |
| `doppler_call()` helper shape | "captures `2>&1`, applies the redact, and prints a sanitized diagnostic on failure" [#9613] | asked |
| gdpr-gate SKILL.md + gdpr-gate.sh comment updates | — | inferred — justification: the self-test's parity check fails closed if parser and doc drift, and leaving a "binding is inert" comment would falsify the doc |
| test-helpers `make_gh_stub`/`make_gh_stub_sleep` `pr list` arm | — | inferred — justification: TS-cron-* fixtures must serve the new subcommand or every non-999 assertion is vacuous |
| New S57/S58 `[doppler-stderr]` scenarios | — | inferred — justification: without a fault-path needle for set/delete, the helper could print nothing and the suite stays green (the exact failure shape the issue fixes) |

### Split Assessment

- Subsystems touched: 5 — `.github`, `.claude`, `plugins/soleur`, `scripts`, `apps/web-platform/infra`
- Planned files: ~14 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the 5-root count is driven by one test file under `apps/web-platform/infra/` that is coupled to a workflow edit in the same commit (the issue mandates the anchor moves land together); splitting would put a red suite on main between the halves. The diff is ~450 lines of mostly mechanical rewrites.

## Domain Review

**Domains relevant:** engineering (internal CI/tooling only)

No cross-domain implications detected — CI machinery repair. Product/UX gate: NONE (no UI-surface
file in Files to Edit/Create). Legal/compliance: assessed — the gdpr-gate probe edit changes a
measurement source, not any compliance claim or attestation logic (ADR-203 machinery is untouched);
the LUKS marker edit changes stderr hygiene only. IaC gate: no new infrastructure — all changes are
in-place edits of existing workflows/hooks/scripts. GDPR gate (plan Phase 2.7): no regulated-data
surface; triggers (a)–(d) — (d) assessed: `plugins/soleur/` is an existing distribution surface
(marketplace plugin), not a new one; no new processing activity on operator-session data.

## Implementation Phases

### Phase 1 — #7255 liveness repoint

1.1 Update `plugins/soleur/test/test-helpers.sh`: `make_gh_stub`/`make_gh_stub_sleep` serve `pr list`
    (record argv to a log file for the shape pin), keeping `run list` removed only if no other
    consumer needs it — grep consumers first.
1.2 Update both `plugins/soleur/test/notice-frontmatter.test.sh` and
    `_base-notice-frontmatter.test.sh` TS-cron-* cases to the `pr list` stub; add a case asserting the
    recorded argv contains `pr list` + `head:ci/vendor-attest` and no `run list`.
1.3 Update `plugins/soleur/test/fixtures/gdpr-gate-stale/gh-stub/gh` to serve `pr list`.
1.4 Rewrite `cmd_cron_run_stale` in `notice-frontmatter.sh` per Proposed Solution A; drop the ⚠️
    block and the :12-14 header caveat; keep every guard.
1.5 Update `gdpr-gate.sh` :118-128 comment (binding is live via attestation-PR creation) and
    `SKILL.md` :326-332 (remove dead-workflow literal; keep MIN semantics documented).
1.6 Verify `gdpr-gate-self-test.test.sh` parity check lands on the "retired from both" PASS arm;
    refresh its stale :136-137 comment.

### Phase 2 — #8480 hook arm reorder

2.1 Add failing regression case (g) to `new-scheduled-cron-prefer-inngest.test.sh`: `CLAUDE_PROJECT_DIR=$PWD`
    + `file_path=$PWD/.worktrees/feat-x/.github/workflows/<existing scheduled>.yml` → `allow`; plus
    the deny control for a worktree path that does NOT exist on origin/main.
2.2 Swap the two case arms in the hook (:96-99).
2.3 Run the hook suite; all cases a–g green.

### Phase 3 — #9612 sentinel + normalization

3.1 Write `scripts/lint-gh-argv-arg.test.sh` fixtures first (must-fire + must-not-fire +
    verify-the-verifier), run red.
3.2 Write `scripts/lint-gh-argv-arg.py`; drive fixtures green; run live scan over the repo → must be
    clean after 3.3.
3.3 Normalize the 13 dedupe sites (5 zot + 8 inngest-health) to the `if ! VAR="$(…)"; ::error::; fi`
    shape; keep the `search_rc` fail-closed site documented.
3.4 Register both suites in `scripts/test-all.sh` beside the other lint entries.

### Phase 4 — #9613 doppler_call

4.1 Add the two new fault-diagnostic scenarios (set-fail, delete-fail `[doppler-stderr]` needles) and
    register them in `G3_EXPECTED_IDS`; re-anchor rows 3 and 17g and the two structural checks to the
    `doppler_call` spellings — run suite red first (anchors won't match the old text yet is fine;
    the NEW scenarios must fail against the un-wrapped code).
4.2 Write `doppler_call()` into the marker step; route the four invocations through it; `marker_state`
    delegates its read (the absent-classify stays in `marker_state`).
4.3 Extend the census `VERB` regex to count `doppler_call secrets (set|delete|upload)`;
    `ALLOWED_SITES` stays 2.
4.4 Run `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` end-to-end.

### Phase 5 — verification

5.1 `bash -n` on every edited workflow-embedded and shell file; run the touched suites
    (notice-frontmatter ×2, gdpr-gate-self-test, hook suite, lint-gh-argv-arg pair,
    workspaces-luks-verify-workflow).
5.2 Live smoke: `GH_TOKEN=$(gh auth token) bash plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh cron-run-stale` → prints a small integer.
5.3 `git diff` review for comment/instruction drift; update the two skill comment blocks.

## Files to Create

- `scripts/lint-gh-argv-arg.py`
- `scripts/lint-gh-argv-arg.test.sh`
- `knowledge-base/project/specs/feat-one-shot-7255-8480-9612-9613-ci-machinery/tasks.md`

## Files to Edit

- `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh`
- `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh`
- `plugins/soleur/skills/gdpr-gate/SKILL.md`
- `plugins/soleur/test/test-helpers.sh`
- `plugins/soleur/test/notice-frontmatter.test.sh`
- `plugins/soleur/test/_base-notice-frontmatter.test.sh`
- `plugins/soleur/test/fixtures/gdpr-gate-stale/gh-stub/gh`
- `plugins/soleur/test/gdpr-gate-self-test.test.sh` (comment refresh only)
- `.claude/hooks/new-scheduled-cron-prefer-inngest.sh`
- `.claude/hooks/new-scheduled-cron-prefer-inngest.test.sh`
- `scripts/test-all.sh`
- `.github/workflows/scheduled-zot-restart-loop.yml`
- `.github/workflows/scheduled-inngest-health.yml`
- `.github/workflows/workspaces-luks-verify.yml`
- `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`

## Acceptance Criteria

- [ ] AC1: `bash plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh cron-run-stale` with a stubbed `gh` serving `pr list` JSON prints a real day-count (non-999), and each failure fixture (no token, `null`, non-RFC3339, empty, slow) still prints 999. Live probe: with `GH_TOKEN` present the command prints a small integer or 999 — never aborts.
- [ ] AC2: `plugins/soleur/test/notice-frontmatter.test.sh`, `plugins/soleur/test/_base-notice-frontmatter.test.sh`, and `plugins/soleur/test/gdpr-gate-self-test.test.sh` pass, with the dead-workflow literal at zero hits in BOTH parser and SKILL.md, and a test asserting the query carries `head:ci/vendor-attest`.
- [ ] AC3: `Edit` of `.github/workflows/scheduled-*.yml` under a worktree path (`<repo>/.worktrees/feat-*/...`) with `CLAUDE_PROJECT_DIR=<repo>` returns `allow` in the hook suite; a genuinely-new scheduled file at a worktree path still returns `deny`.
- [ ] AC4: `python3 scripts/lint-gh-argv-arg.py` exits 0 on the live tree; its unit suite covers must-fire shapes (`--arg` in gh argv: mid-argv, after `--jq` program, continuation-joined, inside `$(…)`) and must-not-fire shapes (post-pipe `jq --arg`, `--arg` in comments, quoted tokens, non-gh commands) and exits non-zero on a deliberately-broken linter.
- [ ] AC5: `scripts/test-all.sh` registers `scripts/lint-gh-argv-arg` (unit) and `scripts/lint-gh-argv-arg-live`; `lint-orphan-test-suites` stays green.
- [ ] AC6: all 13 named dedupe sites use the fail-open `if ! VAR="$(gh … | jq …)"; ::error:: …; VAR=""; fi` shape (or retain the documented `search_rc` shape at zot ~:391); `grep -n 'gh issue list' scheduled-zot-restart-loop.yml scheduled-inngest-health.yml` shows zero bare `EXISTING=$(gh …)` assignments.
- [ ] AC7: `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` passes with the `doppler_call` call shapes; census still reports `ALLOWED_SITES 2`; new S57/S58 fault-diagnostic scenarios are registered in `G3_EXPECTED_IDS`; mutation rows 3/17g re-anchored and still drive RED.
- [ ] AC8: `bash -n` on every edited shell body and each edited workflow still parses under the repo's existing workflow lint path; no `doppler secrets (set|delete)` invocation exists outside `doppler_call`.
- [ ] AC9: PR body carries `Closes #7255`, `Closes #8480`, `Closes #9612`, `Closes #9613` each on its own line.

## Test Scenarios

- Given a stub `gh` that answers `pr list` with a fixture `createdAt` 99 days ago, when `cron-run-stale` runs, then it prints `99`.
- Given the same stub answering `null`/empty/date-only/sleep-10s, then `cron-run-stale` prints `999` (and TS-cron-5's <6s bound holds).
- Given `CLAUDE_PROJECT_DIR=$REPO` and an Edit payload at `$REPO/.worktrees/feat-x/.github/workflows/<existing scheduled>.yml` adding a `cron:` line, when the hook runs, then permissionDecision is `allow`; a `scheduled-new.yml` at the same worktree prefix gets `deny`.
- Given a fixture workflow containing `gh issue list --json n --jq '…' --arg t "$T"`, when the sentinel runs, then it reports file:line and exits 1; the same file with `| jq --arg` stays clean.
- Given `FIXTURE_DOPPLER_SET_FAIL=1`/`FIXTURE_DOPPLER_DELETE_FAIL=1`, when the marker step runs under the stub, then the log carries a `[doppler-stderr]` line naming the refusal and no raw `dp.st.*` token.

## Success Metrics

- `cron-run-stale` resolves a real number on a networked dev host (verified once manually: `GH_TOKEN=$(gh auth token) bash notice-frontmatter.sh cron-run-stale` prints days since the newest `ci/vendor-attest-*` PR creation).
- The four issues' "Done when"/"Scope" bullets are all met; no issue-filing path in the 13 normalized sites can die silently on a transient `gh` fault.

## Dependencies & Risks

- **`gh pr list --search "head:…" --state merged` empirically returned empty** while `--state all`
  works — the query pins `--state all`; a test asserts the argv shape so a future substrate/prefix
  move reds loudly.
- **G3 anchor drift**: the biggest rework risk — anchors are byte-exact substitutions (`g3_sub`
  requires exactly-one occurrence); new call text must be written first, anchors updated to match,
  then the suite run. Mitigation: implement D in one pass, run the suite before committing.
- **`gdpr-gate-self-test` parity check**: dead-workflow literal must hit zero in parser AND SKILL.md
  in the same commit — the FAIL arm triggers on one-sided drift.
- **Hook reorder over-allow edge**: a *nested* `.github/workflows/` path inside the repo now reduces
  to basename; assessed safe because GitHub only executes root-level `.github/workflows/` and the
  gate's deny arm still fires on genuinely-new filenames.
- **Sentinel false-positive surface**: comments quoting the defect pattern exist in the normalized
  files themselves — comment stripping is mandatory, and the unit suite carries a fixture for it.

## Sharp Edges

- Plan-phase deviations vs the canonical skill: research/domain/review subagents could not be spawned
  in this harness (no Task tool) — the equivalent checks ran inline (documented in Research Insights).
  The on-disk artifacts (this plan + tasks.md) carry the full gate output regardless.
- `hr-when-a-plan-specifies-relative-paths-e-g`: every glob the sentinel scans was verified —
  `.github/workflows/*.yml` (96 files) and `scripts/*.sh` both resolve non-empty.
- `cq-write-failing-tests-before`: work phase writes the failing cases first (argv-pin, worktree
  regression, `[doppler-stderr]` needle, sentinel fixtures) and watches them red before implementing.
- The `## User-Brand Impact` section is filled (threshold `none` + scope-out reason) — deepen-plan
  Phase 4.6 halts on an empty one.

## Enhancement Summary (deepen-plan pass)

Applied inline (no subagent spawn in this harness — the mechanical halt gates and the
learnings sweep ran directly):

- **Halt gates verified mechanically:** 4.6 `## User-Brand Impact` present (threshold `none` +
  scope-out reason — required because `apps/web-platform/infra/` matches `SENSITIVE_PATH_RE`);
  4.7 `## Observability` 5-field block present with an allowlisted `<15s` discoverability_test;
  4.8 no PAT-shaped TF variable introduced (`GH_TOKEN` is a pre-existing gh-CLI env, not a
  provisioned credential); 4.9 no UI files → wireframe gate silent; 4.10 no store/connection →
  skip; 4.11 `lint-guard-contract.py` run over this file — `3 guard entries`, clean; 4.12
  `## Scope Check` single unfenced heading, all subsections + `Recommendation:` present.
- **Learning folded — jq-flag family widening** (`learnings/2026-03-04-gh-jq-does-not-support-arg-flag.md`):
  gh rejects the whole jq-flag family in argv, not only `--arg`. Sentinel detection widens to
  `--arg|--argjson|--argfile|--slurpfile|--rawfile` (standalone tokens); the issue's named shape
  stays the headline case. tasks.md Phase 3 updated to match.
- **Learning folded — workflow-file Edit-tool friction** (`learnings/2026-03-18-security-reminder-hook-blocks-workflow-edits.md`):
  a PreToolUse security reminder may fire on the first Edit/Write of `.github/workflows/*.yml`;
  retry the same tool call — do not work around it with sed.
- **Precedent check (4.4):** no new scheduled workflow is introduced (hook gate `new-scheduled-cron-prefer-inngest`
  untouched as a trigger); the dedupe normalization copies the in-repo reference shapes verbatim.
- **Portability edge recorded:** the probe's `timeout 5s`/`date -d` are GNU-isms already shipped in
  `cmd_cron_run_stale`; this fix preserves them unchanged (macOS hosts continue to fail-safe to 999,
  same as today — no portability regression, out of scope for this PR).
- **tasks.md propagation:** the flag-family widening is reflected in Phase 3 step text.
- No corrections requiring plan-body restructuring; all four issue mappings unchanged.

## References & Research

- `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh:186-244` — the probe
- `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts:129` — `ATTEST_BRANCH_PREFIX`
- ADR-203 — attestation write-back machinery (the artifact the new query reads)
- ADR-166 — lint-gate precedent for a recurring CI defect class
- `cli/cli#10263` — gh does not forward `--arg`
- `workspaces-luks-verify.yml` :896-909, :1098-1125 — the two reference shapes (fail-open dedupe, stderr sanitize)
- `scripts/lint-workflow-errexit-capture.py` — sibling sentinel shape to mirror
- #7255, #8480, #9612, #9613 — scope sources
