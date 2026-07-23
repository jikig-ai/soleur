---
date: 2026-07-23
type: feat
issue: 6882
pr: 6883
branch: feat-lint-bot-statuses-required-promotion
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-lint-bot-statuses-required-promotion/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-07-23-lint-bot-statuses-required-promotion-brainstorm.md
adr: ADR-139 (provisional ordinal — re-verify at ship)
---

# Plan: promote the credential-path guard to a blocking required check (#6882)

## Overview

Split `scripts/lint-credential-path-literals.py` out of the bundled `lint-bot-statuses` ci.yml job
into its own always-run job `credential-path-guard`, run it in **full-scan** mode, and register that
one job as a blocking required status check — while adding an **earned-green** preflight to the
bot-PR composite action so bot PRs cannot merge under a fabricated pass.

`lint-bot-statuses` keeps its remaining six steps and stays advisory.

Design decisions are settled (brainstorm + operator choice). This plan is sequencing only.

## Research Reconciliation — Spec vs. Codebase

Everything below was measured on this branch, not paraphrased.

| Claim | Reality | Plan response |
|---|---|---|
| Issue: job "bundles four checks" | Seven steps / six distinct linters (`ci.yml` `lint-bot-statuses`) | Split only the credential step; NG1–NG3 fence the rest |
| Issue: promote in changed-files mode | Full-scan is clean **today**: `OK: no resolvable credential-file path literals in 7450 scanned file(s)`, exit 0 | FR2 promotes in full-scan (stronger green semantic) |
| `lint-infra-no-human-steps` could ride along | Full-scan `FAIL: 475 …`, exit 1 | NG3 — changed-files only; cannot be promoted without a drain |
| Preflight prescription: `… "${PATHS[@]}"` | **Verified working.** Passing both bot paths scans **1** file (the `.json` is filtered — scanner is `*.md`-only). Verified it *catches*: a synthetic doc naming the home-relative Doppler CLI config file → `FAIL: 1 …`, exit 1 | FR4 as written; AC notes the 1-of-2 scan count is correct, not a bug |
| Counts to move | `required-checks.txt` 21 names (19 CI + 2 CLA); canonical JSON 20 (19×15368 + `CodeQL`×57789); TF 20 `required_check` blocks | 22 / 21 / 21 |
| TF header comment | `ruleset-ci-required.tf:18` says "the 19 `context` strings below are public ABI" | FR7 updates 19 → 20 |
| "Audit every bot-PR-creating workflow" (AC3) | **Mechanically automated already.** `scripts/lint-bot-synthetic-completeness.sh` reads `required-checks.txt` as `CONFIG_FILE` and fails any bot-PR workflow missing a synthetic per required check; composite-action callers are skipped by design (the action derives names from the SSOT). Baseline: `All 2 PR-creating workflow(s) use App tokens (no synthetics needed)`, exit 0 | AC3 = re-run the linter post-change and confirm still exit 0. No manual audit needed |
| Composite-action callers | Exactly two: `weakness-miner.yml` (writes `weakness-digest.md`), `rule-metrics-aggregate.yml` (writes `rule-metrics.json`). No workflow hand-rolls a synthetic check-run POST | FR4 covers both via the shared action |
| `scripts/post-bot-statuses.sh` also matches the SSOT grep | **Zero callers**, legacy **Statuses API** (cannot satisfy a ruleset, which requires Check-Runs). Already recorded as out-of-scope dead code by `plans/2026-07-05-fix-bot-synthetic-check-names-drift-plan.md` | Out of scope; do **not** edit. Noted so /work does not rediscover it |
| Other SSOT readers | `create-ci-required-ruleset.sh`, `update-ci-required-ruleset.sh`, `cron-ruleset-bypass-audit.ts` all read the canonical JSON at runtime | No edit; re-confirm in Phase 0 |
| Parity test | `plugins/soleur/test/required-checks-canonical-parity.test.sh` — baseline **30 assertions, 0 failed** | Phase 4 re-runs; Phase 4 adds Test 8 |

## Open Code-Review Overlap

- **#3593** — *"review: extract post-synthetic-checks child composite (deferred per ADR-027)"* — touches
  `.github/actions/bot-pr-with-synthetic-checks/action.yml`, which FR4 edits.
  **Disposition: acknowledge.** #3593 is a structural refactor (extract a child composite); this PR adds
  one preflight step. Folding a composite extraction into a merge-gate promotion is exactly the
  rollback-coupling the CPO flagged — a preflight bug and a required-check change must not share a
  revert. #3593 stays open; note that this PR adds ~6 lines to the action, marginally strengthening
  its case.

No other open `code-review` issue names any planned file.

## Implementation Phases

Phase order is load-bearing: the **earner** (FR4) must precede the **contract** (FR5). Adding the name
to `required-checks.txt` is what causes the composite action to fabricate a green; until the preflight
exists, that green is unearned over a reachable surface.

### Phase 0 — Preconditions (verification only, no edits)

0.1 Re-confirm full-scan green: `python3 scripts/lint-credential-path-literals.py; echo $?` → `0`.
    Do **not** pipe to `tail`/`head` before reading `$?` — a pipeline returns the last command's status
    and will report `0` for a failing linter (session error #3).
0.2 Re-confirm counts: `grep -vE '^\s*#|^\s*$' scripts/required-checks.txt | wc -l` → 21;
    `jq 'length' scripts/ci-required-ruleset-canonical-required-status-checks.json` → 20;
    `jq '[.[]|select(.integration_id==15368)]|length' …` → 19;
    `grep -c 'required_check {' infra/github/ruleset-ci-required.tf` → 20.
0.3 Re-confirm `create-ci-required-ruleset.sh` / `update-ci-required-ruleset.sh` /
    `cron-ruleset-bypass-audit.ts` read the canonical JSON and hardcode no set.
0.4 Baseline both gates: parity test (30 pass) and `scripts/lint-bot-synthetic-completeness.sh` (exit 0).

### Phase 1 — Earn the bot green (composite action)

1.1 In `.github/actions/bot-pr-with-synthetic-checks/action.yml`, add a step to the Phase-4
    "Secret-safety ceiling" block, immediately after the existing `lint-fixture-content` reproduction,
    modelled on it (same fail-loud shape):

    ```yaml
    - name: Earn credential-path green over staged paths (#6882)
      shell: bash
      run: python3 scripts/lint-credential-path-literals.py "${PATHS[@]}"
    ```

    `python3` is preinstalled on `ubuntu-latest`. A non-zero exit must abort before the branch is
    pushed / the PR is opened / any synthetic is posted — same as the gitleaks arm.
1.2 Update the action's `ALLOWED_PATHS` comment block: the `#6103` / `#6589` preflight-TODO notes
    explain unreachability-based soundness; add a sibling note that `credential-path-guard` is
    **EARNED, not fabricated**, via 1.1, and that its `SCAN_DIRS` **does** intersect `ALLOWED_PATHS`
    (`weakness-digest.md`), which is why the unreachability argument was not reused.
1.3 Syntax-check embedded shell only: `bash -c '<extracted run snippet>'`.
    Do **not** run `actionlint` on a composite action definition — it validates workflows and emits
    spurious schema errors against `action.yml` (Sharp Edge, plan skill).

### Phase 2 — Extract the job (ci.yml)

2.1 Add a new always-run job `credential-path-guard` to `.github/workflows/ci.yml`:

    ```yaml
    credential-path-guard:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        - name: Lint resolvable credential-file paths in docs (full scan)
          run: python3 scripts/lint-credential-path-literals.py
    ```

    Deliberately **no** `if:` on `github.event_name` — the job must report on `pull_request` **and**
    `merge_group`, or a queue entry stalls pending forever (ci.yml's own header warns about this).
    Deliberately **no** `fetch-depth: 0` — full-scan needs no merge base, so a shallow checkout is
    correct and faster. This also removes the `github.base_ref`-is-empty-on-merge_group fragility
    that the changed-files form carries.
2.2 Remove the `Lint resolvable credential-file paths in docs (changed vs base)` step from
    `lint-bot-statuses`. Leave its `fetch-depth: 0` in place — `lint-infra-no-human-steps` still
    needs the merge base.
2.3 Add a comment above the new job stating it is a **required** check and above the remaining
    `lint-bot-statuses` steps restating that they remain advisory (mirroring the existing #6734
    ADR-129 comment, which already documents that convention).

### Phase 3 — Register the contract (SSOT fan-out, one commit)

All four edits land together — the parity test enforces set equality file-vs-file, so any partial
staging goes red immediately (TR1).

3.1 `scripts/required-checks.txt` — add `credential-path-guard` to the CI Required section with a
    comment stating the green is **EARNED** by the action's Phase-4 preflight (Phase 1), explicitly
    contrasting with the `rule-body-lint` / `sentry-destroy-required` FABRICATED-NOT-EARNED entries
    above it, and naming the `ALLOWED_PATHS ∩ SCAN_DIRS ≠ ∅` reason.
3.2 `scripts/ci-required-ruleset-canonical-required-status-checks.json` — append
    `{"context": "credential-path-guard", "integration_id": 15368}`.
3.3 `infra/github/ruleset-ci-required.tf` — add the matching `required_check` block.
3.4 Same file — update the header comment `the 19 \`context\` strings` → `20`, and add a dated note
    recording this addition (mirroring the existing `#6049` / `#6103` header notes).

### Phase 4 — Tests

4.1 Extend `plugins/soleur/test/required-checks-canonical-parity.test.sh` with **Test 8**: assert
    `action.yml` invokes `lint-credential-path-literals.py` in its preflight. This is the enforcement
    teeth for ADR-139 — without it, a future edit could delete the preflight and leave a fabricated
    green behind with every other gate still passing. Follow the existing Test-4 style (grep the
    action body; fail loud with a message naming the ADR).
4.2 Re-run the parity test: expect 30 + new assertions, 0 failed.
4.3 Re-run `bash scripts/lint-bot-synthetic-completeness.sh`: expect exit 0 and the new check name in
    its `Required synthetic checks:` echo — this is AC3's mechanical satisfaction.
4.4 Re-run `bash scripts/lint-bot-synthetic-statuses.sh` (sibling gate, unchanged) — expect green.

### Phase 5 — Records

5.1 Create `ADR-139` (see `## Architecture Decision (ADR/C4)`).
5.2 Append a `knowledge-base/legal/compliance-posture.md` ledger entry recording the incident class and
    the advisory→blocking upgrade as **Art. 32(1)(d)** evidence (testing and evaluating the
    effectiveness of a technical measure). No Article 30 amendment — no new purpose, category,
    recipient, or sub-processor (CLO).

### Phase 6 — Verification

6.1 Full-scan green; parity test green; both bot linters green.
6.2 Confirm the new job appears in the PR's check list and reports on the merge queue ref.

## User-Brand Impact

Carried forward verbatim from the brainstorm — not re-authored.

**If this lands broken, the user experiences:** the `credential-path-guard` check either blocks every
PR (a context nobody posts) or silently passes on bot PRs while a doc reintroduces a resolvable
credential path — the merge gate standing between a tracked doc and Claude Code's harness
auto-attaching a live credential file into model context.

**If this leaks, the user's credentials are exposed via:** a doc containing a home-relative resolvable
path to a real credential file; the harness resolves and reads it as a Read-tool result; a live token
lands in session transcripts shared with a model provider outside any registered processing agreement.

**Brand-survival threshold:** `single-user incident`.

This is a **realized-class** vector: `preflight/SKILL.md` Check 10 previously wrote the literal
home-relative path to the operator's live Doppler CLI config and a live `dp.ct.*` token was read into
transcripts. Non-technical Soleur users cannot read CI, so an advisory gate offers them nothing.

CPO sign-off: carried forward from the brainstorm's Domain Assessments (CPO reviewed; verdict "worth
doing now, size it as hours"). `user-impact-reviewer` will be invoked at review time.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carry-forward from brainstorm `## Domain Assessments`)

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Path (A) — reproduce in preflight — not the unreachability precedent, which would be
its first application to a reachable surface. Job-level promotion is the wrong granularity: split the
genuinely-blocking gate out, leave the self-declared advisory linters alone. All SSOT artifacts must
co-land (parity test enforces set equality). Ruleset apply must not precede the job existing on main.
Warrants an ADR citing the `ALLOWED_PATHS ∩ SCAN_DIRS` test as the general rule.

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** Not an Art. 33/34 personal-data breach (a Doppler token is infrastructure credential,
not personal data), but an **Art. 32(1)(b)** confidentiality failure over a credential that unlocks
systems processing personal data, plus secret-in-transcript disclosure outside any registered
processing agreement. Accountability hook is **Art. 32(1)(d)**. No statutory clock fires on the
residual alone. The tripwire-comment pattern is **not** defensible here — a comment is not a control.
No Article 30 amendment; an ADR + `compliance-posture.md` ledger entry are required.

### Product/UX Gate

**Tier:** none. Mechanical UI-surface scan over `## Files to Edit` / `## Files to Create` matched no
UI-surface path (all entries are CI config, IaC, scripts, tests, and knowledge-base docs). No
wireframe required; `wg-ui-feature-requires-pen-wireframe` does not fire.

### GDPR / Compliance Gate (Phase 2.7)

Canonical regulated-data regex does not match (no schema, migration, auth flow, API route, or `.sql`).
Trigger (b) fires (`single-user incident` threshold), and the CLO carry-forward above **is** the
assessment: no new processing activity, no new sub-processor, no Article 30 amendment. Required output
is the `compliance-posture.md` ledger entry (Phase 5.2).

## Infrastructure (IaC)

### Terraform changes

- `infra/github/ruleset-ci-required.tf` — one added `required_check` block (`context =
  "credential-path-guard"`, `integration_id = var.actions_integration_id`) plus the header count
  comment. No new provider, no new variable, no new secret.

### Apply path

Auto-applied on merge by `.github/workflows/apply-github-infra.yml`, which fires when a PR touching
`infra/github/*.tf` merges to main (GitHub App credentials from Doppler `prd_terraform`; the PR merge
**is** the human authorization per `hr-menu-option-ack-not-prod-write-auth`). No operator SSH, no
manual `terraform apply`, no dashboard step. Kill switch: `[skip-github-apply]` in the merge commit.

Because the merge that triggers the apply also carries the new ci.yml job, the job exists on `main` at
apply time (TR4 satisfied by construction).

### Distinctness / drift safeguards

- The daily `scheduled-ruleset-bypass-audit` + `cron-ruleset-bypass-audit.ts` reconcile live ruleset
  state against the canonical JSON and auto-close drift issues on green — the new context is
  auto-enrolled because both read the canonical file at runtime.
- `bypass_actors` untouched (canonicalized separately in
  `scripts/ci-required-ruleset-canonical-bypass-actors.json`).
- Job name is public ABI in three files (ADR-032 Sharp Edge 1) — a rename silently un-requires the
  check. Recorded in ADR-139 and in the ci.yml comment.

### Vendor-tier reality check

N/A — GitHub rulesets on an existing repo; no tier gate.

## Observability

```yaml
liveness_signal:
  what: the `credential-path-guard` check-run reports on every PR and merge_group ref
  cadence: per-PR / per-merge-queue-entry
  alert_target: GitHub PR check list; drift caught by the daily ruleset-bypass audit cron
  configured_in: .github/workflows/ci.yml + infra/github/ruleset-ci-required.tf
error_reporting:
  destination: GitHub Actions job log (linter prints `file:line: …` per violation); ruleset drift →
    scheduled-ruleset-bypass-audit auto-files an issue
  fail_loud: true — linter exits 1 on any hard-fail; composite action exits non-zero before opening a PR
failure_modes:
  - mode: ruleset requires a context nobody posts (job renamed / removed)
    detection: every PR blocks pending; daily ruleset-bypass audit compares live vs canonical JSON
    alert_route: auto-filed drift issue
  - mode: preflight deleted from the composite action, restoring a fabricated green
    detection: parity test Test 8 (Phase 4.1) fails in CI
    alert_route: blocking `test` check on the offending PR
  - mode: a bot PR introduces a credential path into weakness-digest.md
    detection: composite action Phase-4 preflight exits 1 before the branch is pushed
    alert_route: the bot workflow run fails; no PR, no synthetics
  - mode: full-scan regresses (a doc reintroduces a resolvable path)
    detection: credential-path-guard fails on the PR that introduces it
    alert_route: blocking required check
logs:
  where: GitHub Actions run logs for ci.yml / the bot workflow
  retention: GitHub default (90 days)
discoverability_test:
  command: gh run list --workflow=ci.yml --branch main -L 5 --json databaseId --jq '.[].databaseId' | while read -r id; do gh run view "$id" --json jobs --jq '.jobs[] | select(.name=="credential-path-guard") | .conclusion'; done
  expected_output: success (one line per recent main run) — no ssh
```

No soak-gated / time-boxed close criterion in any AC, so §2.9.1 follow-through enrollment does not fire.

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-139` — "Earned-green preflight required for reachable-surface content gates".**
Ordinal is **provisional** (highest existing is ADR-138); a sibling PR can claim it during the
pipeline, so `/ship` re-verifies against `origin/main` before merge. **If renumbered, sweep this plan,
`tasks.md`, and every AC naming the ordinal in the same edit** — a renumber that reaches only the ADR
body leaves ACs asserting a nonexistent file.

Decision to record: a content-scoped gate may rely on the fabricated-but-unreachable argument **only**
where `ALLOWED_PATHS ∩ SCAN_DIRS = ∅`, and that intersection must be **re-derived per gate, never
inherited** from a prior ADR. Where it is non-empty, the green must be **earned** by reproducing the
scanner over the staged paths in the action's Phase-4 preflight. Alternatives considered must record:
(a) the non-15368 `integration_id` option and why it is a **deadlock** rather than an exclusion, and
(b) shrinking `ALLOWED_PATHS`, rejected because it breaks the `weakness-miner` loop.

Must also record the **tripwire-axis** finding: existing tripwire comments key on `ALLOWED_PATHS`
edits only, but reachability is the intersection of two independently-mutable sets — a change to a
*generator's output format* (e.g. `weakness-miner.sh` emitting learning titles instead of bare
basenames) moves the other input and fires nothing.

This amends — does not reverse — ADR-092 and the ADR-031 2026-07-17 amendment: their unreachability
arguments remain sound for their own surfaces.

### C4 views

**No C4 impact.** Enumerated against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), not a keyword grep:

- **External human actors:** none added. No new correspondent, reviewer, or recipient — the change
  alters which CI check blocks a merge, not who participates.
- **External systems / vendors:** none added. `github = system "GitHub"` (`model.c4:230`) is already
  modeled `#external` with description *"Source control, CI/CD, issue tracking, and releases"* — CI/CD
  is explicitly within that element's stated responsibility.
- **Containers / data stores:** none touched. No runtime container, no persistent store; this is CI
  configuration and repo-tracked IaC.
- **Actor↔surface access relationships:** none change. Nobody gains or loses access to any surface;
  no element description is falsified.
- The only CI-adjacent relationship in the model (`model.c4:424`, `github -> cloudflare`) concerns the
  **Cloudflare** rulesets API and is unrelated to GitHub branch rulesets.

### Sequencing

ADR-139 is authored in this PR describing the state as shipped (`status: accepted`) — nothing here is
soak-gated.

## Risks & Mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Name enters the SSOT before the preflight exists → fabricated greens in the window | Phase order 1→3; single PR (TR2) |
| R2 | Ruleset requires a context the job does not post → all PRs block | Job + IaC in the same merge; apply runs after (TR4) |
| R3 | Open PRs created before the merge lack the new context and block until rebased | Expected transitional cost of adding any required check; strict-up-to-date policy already forces rebase. Call out in the PR body |
| R4 | Full-scan regresses between now and merge | CI re-runs it on every push; verified green at plan time |
| R5 | Future job rename silently un-requires the gate | ADR-032 contract restated in ADR-139 + ci.yml comment; three-file name coupling |
| R6 | Preflight later deleted, restoring a fabricated green | Parity test Test 8 (Phase 4.1) fails CI |
| R7 | `weakness-miner.sh` output format changes, widening reachability | Retired, not tracked — the earned green is correct regardless of generator output |
| R8 | Full-scan wall-clock on hosted runner | 7450 files completed comfortably locally; TR7 confirms on the runner before ready |

## Files to Edit

- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — Phase-4 preflight step + comment (FR4)
- `.github/workflows/ci.yml` — new `credential-path-guard` job; remove step from `lint-bot-statuses` (FR1–FR3)
- `scripts/required-checks.txt` — add name + EARNED comment (FR5, FR6)
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — add context (FR5)
- `infra/github/ruleset-ci-required.tf` — add `required_check` block + header count 19→20 (FR5, FR7)
- `plugins/soleur/test/required-checks-canonical-parity.test.sh` — add Test 8 (Phase 4.1)
- `knowledge-base/legal/compliance-posture.md` — Art. 32(1)(d) ledger entry (AC6)

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-139-earned-green-required-for-reachable-surface-content-gates.md`

**Explicitly NOT edited:** `scripts/post-bot-statuses.sh` (zero callers, legacy Statuses API — already
recorded as out-of-scope dead code), `scripts/create-ci-required-ruleset.sh`,
`scripts/update-ci-required-ruleset.sh`, `cron-ruleset-bypass-audit.ts` (all read the canonical JSON
at runtime).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — Decision recorded: preflight reproduction chosen; the `integration_id` alternative
  documented as a bot-PR deadlock. Present in ADR-139 `## Alternatives Considered`.
- **AC2** — `credential-path-guard` present in all three SSOT artifacts. Verify:
  `grep -c '^credential-path-guard$' scripts/required-checks.txt` → 1;
  `jq '[.[]|select(.context=="credential-path-guard" and .integration_id==15368)]|length' scripts/ci-required-ruleset-canonical-required-status-checks.json` → 1;
  `grep -c 'credential-path-guard' infra/github/ruleset-ci-required.tf` → ≥1.
- **AC3** — `bash scripts/lint-bot-synthetic-completeness.sh` exits 0 **and** its
  `Required synthetic checks:` line contains `credential-path-guard`. This is the mechanical audit of
  every bot-PR-creating workflow; no manual enumeration is accepted as a substitute.
- **AC4** — `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` → `ALL TESTS PASSED`,
  with Test 8 present and failing when the preflight line is removed (verify by temporary deletion,
  then restore).
- **AC5** — `python3 scripts/lint-credential-path-literals.py; echo $?` → `0` (no pipeline before
  reading `$?`).
- **AC6** — Preflight catches: `python3 scripts/lint-credential-path-literals.py <tmpfile containing a
  home-relative Doppler config path>` exits 1. (Verified at plan time; re-assert post-edit.)
- **AC7** — `lint-bot-statuses` still absent from `scripts/required-checks.txt` and the canonical JSON;
  its six remaining steps unchanged. `grep -c 'lint-bot-statuses' scripts/required-checks.txt` → 0.
- **AC8** — Counts moved: 22 SSOT names, 21 canonical contexts (20×15368), 21 TF `required_check`
  blocks; TF header comment reads `20 \`context\` strings`.
- **AC9** — The `credential-path-guard` job has no `if:` gating on `github.event_name` (reports on
  `merge_group`).
- **AC10** — ADR-139 exists, is referenced from `scripts/required-checks.txt`, and its ordinal matches
  the file on disk. **If renumbered, this AC and every ordinal reference in the plan and `tasks.md`
  are updated in the same edit.**
- **AC11** — `compliance-posture.md` carries the Art. 32(1)(d) entry; Article 30 register unchanged
  (`git diff --stat knowledge-base/legal/article-30-register.md` → empty).
- **AC12** — PR body uses `Closes #6882` (the fix ships at merge; no post-merge remediation gates
  closure).

### Post-merge (operator)

None. The Terraform apply is automated by `apply-github-infra.yml` on merge; verification is the
`discoverability_test` command above, runnable by the agent. No operator step in this plan.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Promote the whole `lint-bot-statuses` job | Reverses ADR-129's deliberate advisory posture for the tempfile ratchet and makes #6752 / #6751 merge blockers |
| Reuse the fabricated-but-unreachable precedent | `ALLOWED_PATHS ∩ SCAN_DIRS ≠ ∅` (`weakness-digest.md`) — would be its first use on a reachable surface |
| Non-15368 `integration_id` | Deadlock, not exclusion: Actions always post as 15368, bot PRs never trigger CI, so the context would never report |
| Shrink `ALLOWED_PATHS` to restore unreachability | Breaks `weakness-miner.yml`; trades a CI change for a product-loop regression |
| Promote in changed-files mode | Green would assert only "this diff is clean"; full-scan is available today because the backlog was drained |

No item is deferred by this plan, so no deferral-tracking issue is required. (NG3's drain of the 475
`lint-infra-no-human-steps` violations was already out of scope at brainstorm and remains untracked by
design — it is a prerequisite for a *different* promotion, not a deferral of this one.)
