---
title: "infra: recurring delete-protection check for web-1's workspaces_luks volume (a second matrix entry of sole-copy-protection-check)"
date: 2026-11-10
slug: infra-web1-workspaces-volume-protection-check
branch: feat-one-shot-10432-web1-workspaces-protection-check
issue: 10432
type: chore
lane: cross-domain
ref: "Ref #9927"
closes: "Closes #10432"
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

# infra: web-1 workspaces volume delete-protection check (#10432)

Spec lacks valid `lane:` (no spec.md exists for this branch) - defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-10. **Sections enhanced:** Design, Suite structure, Implementation Phases, Arm x loosening
table, Guard Contract, Observability, User-Brand Impact, Files to Edit, Acceptance Criteria, Test Scenarios.
**Agents used:** security-sentinel, test-design-reviewer, observability-coverage-reviewer, architecture-strategist, a
verify-the-negative sweep (no contradictions found); before that, in plan review: spec-flow-analyzer, an advisor
consult, a sharp-edges catalogue pass, DHH, Kieran, code-simplicity and the CTO (devex lens and rulings 11-15).
**Verified live:** every cited issue (#10432, #11163, #9927, #10430, #10431, #6590, #12272, #9371 open; #11535 merged;
#10972 closed), the attribution of 47aa18b44a (#11535, on `main`), the labels `action-required`, `infra-drift`,
`priority/p1-high` and `priority/p2-medium`, the milestone `Post-MVP / Later`, and every cited rule id.

### Key improvements

1. The filers carry `GH_REPO`, so a leg whose checkout failed still files its p2 issue. Today that gap exists on the
   Inngest leg and would have been copied to web-1 (row C10).
2. Runbook 6604 gets a top-level read-only read-back section (`--only-secrets HCLOUD_TOKEN_READONLY`, token to
   `curl --config -`, one named word per outcome). Its "Verify the retired end state" block is rewritten in the same
   shape, not just renamed. N3 bans a fallback, an argv header and a second `--only-secrets` on that line.
3. Per-row RED evidence comes from a scaffold-only workflow copy (Phase 1b.6). A no-op `use_entry web1` cannot turn
   the W rows into passing Inngest cases: on that sandbox mutant (`mutation-proofs.md`, row "harness: `use_entry web1`
   a no-op") N1c, WF1, WF12, WV1, WX5, WX9, C3, C4-C6 and C9 go RED. (H13 and WX7 also went RED there and are deleted
   by CTO ruling 23, which also merges C4 and C5. The selected-entry invariant is deleted by ruling 22: it compared
   ENTRY with ENTRY and drew no failure from that mutant.) H11b/c run against `gha-expr.py` itself, which stays as on
   `main` (ruling 21).
4. Byte-identity now covers the templated titles, the `TITLES` list, the `file_unreadable` body and the `finish()`
   notes, by substitution and diff (Phase 4.8, second half). Before, it covered only LEAD/REMEDY/email.

### New considerations discovered

- The ids are public: they appear in the workflow rows, the ADRs, the runbooks and the probe's log line. The
  issue-body ban keeps recipes out of issues; it is not a confidentiality control.
- A whole workflow that never runs is caught by the existing `scheduled-terraform-drift` Sentry monitor. It is the
  job being skipped, or one leg never starting, that stays an accepted residual (#10430). A future check-in keys on the
  combined `needs.<job>.result`.
- The Arm table's Inngest-leg cells for templated strings name the web-1 rows, because a revert to the Inngest literal
  renders identically on the Inngest leg.

PR body must carry `Closes #10432` and `Ref #9927` (never `Closes #9927`). #11163 is closed separately with an
evidence comment (Phase 6). Draft PR: #12563.

## Overview

The `sole-copy-protection-check` job in `.github/workflows/scheduled-terraform-drift.yml` reads the live Hetzner
`protection.delete` flag of the Inngest store volume with one read-only GET and files an issue of its own when the
flag differs from the committed declaration (beyond a 90-minute apply grace), when the volume is missing or
ambiguous, or when the check could not run. Today it covers the Inngest store volume only. The web-1 volume
`hcloud_volume.workspaces_luks` holds every user's checked-out repository (ADR-119) and has no distinct recurring
signal: a lifted flag there shows up only as one more comment on the generic drift-plan issue.

This plan turns the job into a two-row `strategy.matrix` (CTO ruling 1). The Inngest row keeps every title, verdict
and `$GITHUB_OUTPUT` byte-identical. The web-1 row checks `hcloud_volume.workspaces_luks` (name
`soleur-web-platform-data-luks`, Hetzner id 106443278) against `delete_protection` in
`apps/web-platform/infra/workspaces-luks.tf`, with its own name lookup, id pin, expected flag, 90-minute grace read
from its own file's history, issue filers, clear step and email. Both rows use the same read-only token with no
fallback. The executed suite gains a matrix context, a web-1 table and cross-entry cases. An ADR-119 addendum records
the coverage and is the independent anchor for the web-1 pin.

No `.tf` file and no boot byte (user_data, cloud-init) changes. Nothing in this plan writes to Hetzner, Doppler or
Terraform state.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality on `origin/main` (b258336eb5) | Plan response |
|---|---|---|
| "a data-driven second entry ... reusing the verdict taxonomy, the 90-minute grace, the id pin and the could-not-perform filer" (#10432) | The job is NOT data-driven today: the probe hard-codes `readonly VOLUME_ID_PIN=106903269`, the awk regex `"inngest_redis_luks"`, the path `inngest-redis-luks.tf` (probe and `tf_commit`), and every title, LEAD, REMEDY, email subject and ADR pointer names the Inngest volume. | Lift each per-entry literal into an include-row field reached through `env:` (the suite forbids `${{ }}` inside `run:`); keep per-entry PROSE in a `case "$ENTRY"` arm (CTO Fork 1). |
| "the job's name-filtered query guarantees zero contact with the web-1 volume by construction" (D2 of #10424) | True today, and the suite enforces it: `WEB1 = "1064" + "43278"` drives a `web1-id` shape violation banning the web-1 id anywhere in the job, and `invariants()` bans it from every stream. | Narrow, never delete (CTO Fork 2): the web-1 id is allowed only as the `web1` row's `volume_id`; the Inngest id only as the `inngest` row's; neither id in any step, title, body or comment. Each narrowed rule gets its own mutation row. |
| "Keep it read-only with the same `HCLOUD_TOKEN_READONLY` read and no fallback; no new credential." | The probe reads `HCLOUD_TOKEN_READONLY` from `soleur/prd_terraform` with `DOPPLER_TOKEN` bound in the probe step only. | Unchanged; both legs run the same probe body. No new secret, no `environment:`, no loader. |
| Likely files include `token-drift-workflow-causes.test.sh` "if it keys on the job name" | It keys on the job id (unchanged) AND on the literal step name `Probe the Inngest store volume protection flag at Hetzner` (R3b). | Rename to entry-neutral step names and update R3b's literal (CTO Fork 3). |
| ADR-119 carries id 106406962 for `hcloud_volume.workspaces_luks` | The 2026-07-23 addendum names 106406962, the orphaned volume that addendum's re-cut was built to replace; `expenses.md` (corrected 2026-10-01) records that the first provision was re-cut under #6812/#6855. No destroy record for 106406962 is cited in the repo. ADR-148, the cutover runbook and the 2026-10-08 addendum carry 106443278, which the CTO read live at 2026-11-10T10:57:41Z. | Appended correction note in the new ADR-119 addendum; the 2026-07-23 text is not edited. |
| Possible `.tf` / boot-byte change (CTO stop condition 6) | `workspaces-luks.tf` already declares `delete_protection = true` inside a block the probe's awk parses as-is: one top-level `name`, one top-level `delete_protection`, no `/*` anywhere in the file (`grep -c '/\*'` = 0). | No `.tf` or boot-byte change. The stop condition did not fire. |
| The web-1 re-protect route | ADR-119 (2026-10-08 addendum, D1) and runbook `workspaces-luks-cutover-6604.md`: the Hetzner-side flag is delivered by the `apply` job's SSH stage (`manual-rerun` dispatch, or a push); `terraform_data.workspaces_boot_unlock_install` is in that stage's `-target` list (`apply-web-platform-infra.yml`) and its precondition references `hcloud_volume.workspaces_luks.id` (`workspaces-luks.tf`), which puts the volume in the target closure. | The web-1 REMEDY names that route and the runbook's read-only read-back, prints no command, and says an agent reports and does not dispatch. |

## Research Insights

### Premise Validation (Phase 0.6)

- #10432 OPEN (`priority/p2-medium`); #11163 OPEN; #9927 OPEN (epic; Ref only); #10430 OPEN; #6590 OPEN; #12272 OPEN
  (the only place operator notes go). Draft PR #12563 is this branch's own PR (the collision pre-check's only PR hit).
  The pre-check also listed `test-all.sh` processes owned by two unrelated worktrees (#12514, #12559): not duplicates of
  this work, but they explain the host load (average 40-64) during the baseline measurement below.
- #11163's premise is stale in the direction the CTO ruled: `git grep -n unrouted b258336eb5 --
  .github/workflows/scheduled-terraform-drift.yml` returns nothing (exit 1). `git log -S 'unrouted until #10972'`
  names 47aa18b44a (#11535) as the last commit that touched the string. Close it with that evidence (Phase 6).
- Every cited path exists on `origin/main`: the workflow job (line ~1911), the suite, `gha-expr.py`, ADR-119, ADR-148,
  ADR-282, `workspaces-luks.tf` (resource at line ~902), runbooks `inngest-luks-cutover-6894.md`,
  `workspaces-luks-cutover-6604.md`, `infra-credential-tiers-8209.md`.
- Mechanism vs. ADR corpus: ADR-282's 2026-10-16 addendum created the job for the Inngest volume; its "Considered
  options" rejects copying web-1's pin SET onto the Inngest volume, not checking web-1. No ADR rejects a matrix. The
  CTO ruled the matrix (ruling 1).
- Functional-overlap check (registries): three loosely related community skills, none covering a read-only per-volume
  flag check that files issues; nothing installed.

### Property List (Phase 0.6b)

1. P1 — A lifted web-1 flag (live `false`, declared `true`, `workspaces-luks.tf` last changed more than 90 minutes ago)
   files its own p1 issue and turns its leg red within one drift cycle.
2. P2 — Every Inngest-entry title, verdict and probe output is byte-identical to today, and every existing suite row
   stays green with its expected strings unchanged.
3. P3 — Neither entry's request, id pin, expected flag, grace, issue titles, clear step or email depends on the other
   entry's data (cross-entry isolation).
4. P4 — No issue title, body or comment carries either volume id, a command, or an API answer.
5. P5 — The job stays read-only: one GET per attempt per leg, the read-only token only, no fallback, no write verb.
6. P6 — A red leg never cancels or hides the other leg.
7. P7 — The suite still counts itself, its negative controls still fire, and a matrix reference the suite cannot
   resolve is a harness error, never an empty string.
8. P8 — The web-1 pin is anchored to a reviewed document outside the workflow (the ADR-119 addendum and the cutover
   runbook's read-back), as the Inngest pin is anchored to ADR-282, the postmerge skill and runbook 5c.

### Cut List (Phase 0.6b)

- A copied second job → P1/P3 are bought by the matrix rows plus per-entry `env:`; the copy would duplicate ~570 lines
  that drift (CTO ruling 1).
- A loop inside one step → P6 is bought by `fail-fast: false` legs; a loop would rewrite every filer (CTO ruling 1).
- A new Sentry monitor / check-in for this job → #10430, held while #6590 is open (CTO ruling 4).
- A new credential or loader → P5 is already bought by the existing read-only read (CTO ruling 5).
- Running the whole suite table a second time for web-1 → P3 is bought by data-dependent rows plus cross-entry rows;
  the shared probe body is one code path (CTO Fork 2).
- Long prose matrix fields → P2 is bought by keeping the Inngest strings verbatim in a `case` arm (CTO Fork 1).
- An ADR-282 pin anchor for web-1 → P8 is bought by the ADR-119 addendum (CTO ruling 2). ADR-282 still gets a short
  appended note, because its 2026-10-24 addendum counts "exactly three" probe-and-sweep pin literals and the probe's
  literal moves into the `inngest` row.

### Measured baseline (Phase 0.6c, not a cost claim; recorded for the suite budget)

`( time bash plugins/soleur/test/sole-copy-drift-check.test.sh )` at b258336eb5 on the authoring host:
`=== Results: 195/195 passed, 0 failed ===`, `real 5m1.311s`, `user 0m49.990s`, `sys 0m39.879s`, load average
40.50 / 63.41 / 64.51. The table declares `FLOOR=195`, `TABLE_ROWS=126`. Most wall time is process start-up per case
(each case is a fresh python harness run with stubs), so added rows cost wall time roughly linearly.
`scripts/suite-durations.tsv` carries this suite at the default `1222 floor` weight (not measured), so no duration
row moves.

### Relevant files (anchors are content strings; line numbers move)

- `.github/workflows/scheduled-terraform-drift.yml` — job `sole-copy-protection-check` (comment block from
  `INNGEST STORE VOLUME: LIVE DELETE PROTECTION`), steps `doppler_cli`, `tf_commit`, `probe`, `file_finding`,
  `file_unreadable`, `clear`, `notify`, `gate`. Two sibling copies of `readonly VOLUME_ID_PIN=106903269` live in
  `rung2-rehearsal-orphan-sweep` and `inngest-rehearsal-orphan-sweep` (`IDENTITY-PROOF-BEGIN`); they are NOT touched.
- `plugins/soleur/test/sole-copy-drift-check.test.sh` — python harness `h.py` (`cmd_extract`, `violations`,
  `mutants`, `cmd_run`), stubs (`curl`, `doppler`, `timeout`, `sleep`, `gh`), case machinery (`new_case`, `mk_tf`,
  `set_api`, `set_age`, `go`, `want_out`, `want_steps`, `invariants`, `end_row`), pins (`N1`, `N1b`, `N2`, `N3`),
  harness rows `H1`-`H7`. Token fixtures carry distinctive 6-character prefixes; the web-1 id is split today (`"1064""43278"`, the `web1-id` check this plan replaces) so
  the suite file does not carry the literal.
- `plugins/soleur/test/lib/gha-expr.py` — expression subset; unknown context refs are `null` today; only this suite
  imports it.
- `plugins/soleur/test/token-drift-workflow-causes.test.sh` — R3b (`sole-copy-protection-check/(job-level)`,
  `.../Probe the Inngest store volume protection flag at Hetzner`, `.../Fail the run on any verdict that is not clean`);
  its Doppler-install parity compares sibling installs to this job's `doppler_cli` step (unchanged).
- `apps/web-platform/infra/workspaces-luks.tf` — `resource "hcloud_volume" "workspaces_luks"`: `name =
  "soleur-web-platform-data-luks"`, `delete_protection = true`, `lifecycle { prevent_destroy = true }`. Read only.
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` — the
  2026-07-23 addendum's stale `106406962`; the 2026-10-08 addendum's D1 (delete protection delivered by the SSH stage);
  addendum heading style `## Addendum — YYYY-MM-DD (#N, ...)` with an "Appended; nothing above is edited." lead.
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` — "Verify the retired end state
  (read-only ...)" with the `v1/volumes/106443278` read-back, today read with the read/write `HCLOUD_TOKEN` and
  printing a bare `true`/`false`; and `inngest-luks-cutover-6894.md` section 5c step 3, the read-only one-liner
  (`--only-secrets HCLOUD_TOKEN_READONLY`, token to `curl --config -`, one named word per outcome) the web-1 read-back
  copies.
- `scripts/lib/test-affected-paths.sh` — `AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS` ("declared
  from the repo paths its suite file names").
- `.claude/hooks/grep-q-pipe-guard.test.sh` — exemption rows for this suite's `curl` and `doppler` stubs.
- `scripts/alarm-issue-filing-guard.highwater` — ratchet-down count of filing steps that cannot report their verdict;
  this plan adds no filing step.
- `scripts/infra-drift-autoclose.sh` — closes only `infra: drift detected in web-platform`; cannot touch these titles.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `github -> hetzner` edge already names "drift and
  apply workflows"; the web-1 workspaces store element already describes `delete_protection`.

### Institutional learnings applied

- `2026-11-09-a-fix-round-closes-the-instance-the-reviewer-named-and-leaves-its-sibling-arms.md` — write the ARM x
  LOOSENING table first and hand it to every fix agent (section below); a heredoc opener inside a quoted string blanks
  `scripts/guard-vacuity-floor.test.sh`'s view of the rest of the file, so build mock bodies with `printf`.
- `2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md` — the second row adds a second copy of
  every guarded literal (id, path, resource, title subject); each copy needs its own guard row, and the `web1-id` ban
  must be narrowed by position (the row), not deleted.
- `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md` and
  `2026-10-10-my-must-pass-arm-passed-wherever-its-mutation-landed-and-nothing-noticed-the-arms-could-be-deleted.md` —
  FLOOR and TABLE_ROWS move to the REALIZED numbers in the same commit as the new rows; prove the floor fires by
  deleting a new row block on a copy.
- `instrument-answers-instead-of-failing.md` (patterns) — a missing matrix value must fail, not evaluate to a clean
  empty string (`check()` in the harness refuses an unknown `matrix` key; CTO ruling 21).
- `2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md` — every stub and shim keeps
  `#!/usr/bin/env bash` (CI `/bin/sh` is dash).
- `2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md` — exact-title dedupe via `select(.title == $t)`,
  never `--search`.
- `2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path.md` — public issue bodies are
  an unredacted sink; neither id goes there.

### Conventions

Separate `git add` and `git commit` calls; never `git stash`; never `cd` out of the worktree; any new mock shim uses
`#!/usr/bin/env bash`; run the repo-global ratchets (`plugins/soleur/test/fixture-dir-operand-assert.test.sh`,
`plugins/soleur/test/fixture-relative-assert.test.sh`, `scripts/guard-vacuity-floor.test.sh`) directly; every new
fixture helper that takes a directory calls the suite's existing `assert_fixture_dir` (no new copy of the helper);
only `merge_group` or `workflow_dispatch` runs count as Guard 1 evidence.

## Design

### The job after the change

```yaml
  sole-copy-protection-check:
    name: sole-copy-protection-check (${{ matrix.entry }})
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    if: github.ref == 'refs/heads/main'
    strategy:
      fail-fast: false
      matrix:
        include:
          - entry: inngest
            subject: Inngest store volume
            tf_file: apps/web-platform/infra/inngest-redis-luks.tf
            tf_resource: inngest_redis_luks
            volume_id: "106903269"
            adr: ADR-282
          - entry: web1
            subject: web-1 workspaces volume
            tf_file: apps/web-platform/infra/workspaces-luks.tf
            tf_resource: workspaces_luks
            volume_id: "106443278"
            adr: ADR-119
```

`fail-fast: false` is load-bearing (P6): with the default `true`, a red leg cancels the other, still-running leg. That
leg's filers are `always()`, so they still run, but its probe is skipped or killed: it never reaches its own verdict,
and with an empty verdict its could-not-perform filer files a false `(name-unreadable)` p2 issue, and the leg ends
cancelled (its always() gate exits 1, but a fail-fast cancel concludes the leg `cancelled`, not `failure`).
Each leg keeps every step timeout; the job ceiling is 20 minutes, above the 16-minute sum of step bounds (review
round 1, R10: main's 10 was below that sum, so a slow leg could be cancelled mid-filer).

### Step-by-step changes (every per-entry value reaches a `run:` body only through `env:`)

| Step | Change |
|---|---|
| `doppler_cli` | None (byte-identical; `token-drift-workflow-causes.test.sh` compares sibling installs to it). |
| `tf_commit` | `env: TF_PATH: ${{ matrix.tf_file }}`; `path=${TF_PATH}` in the commits URL. No runtime check of the value: matrix values are committed constants on a `main`-only job, so the suite's `matrix-shape` check validates them before merge (plan-review, DHH + simplicity). |
| `probe` | Name `Probe the volume protection flag at Hetzner`. `env:` adds `TF_PATH`, `TF_RESOURCE: ${{ matrix.tf_resource }}`, `PIN: ${{ matrix.volume_id }}`, `SUBJECT: ${{ matrix.subject }}`. Then `readonly VOLUME_ID_PIN="$PIN"` and `TF_FILE="${GITHUB_WORKSPACE:?}/${TF_PATH}"`. The awk gets `-v res="$TF_RESOURCE"` and builds the resource-line pattern once in `BEGIN` as `"^[ \t]*resource[ \t]+\"hcloud_volume\"[ \t]+\"" res "\"[ \t]*[{][ \t]*$"` (`[{]`, not `\{`, so mawk and gawk agree; `matrix-shape` pins `tf_resource` to `^[a-z0-9_]{1,64}$`, so `res` carries no metacharacter). The three `finish()` notes that name the volume (`lift-pending-apply`, `unprotected-as-declared`, `lift-not-applied`) say `the ${SUBJECT}` instead of `the Inngest store volume` (renders identically for Inngest). The closed `finish` argument set, the two `$GITHUB_OUTPUT` writer sites, the EXIT trap, the single `bc_curl` request and the URL line stay exactly as they are. |
| `file_finding` | Name `File an issue when the volume protection differs from its declaration`. `env:` adds `ENTRY: ${{ matrix.entry }}`, `SUBJECT`. Titles become `infra: ${SUBJECT} delete protection differs from Terraform (${NAME})` and `infra: ${SUBJECT} not found at Hetzner (${NAME})`. LEAD, REMEDY and a new `DECISION` line come from one `case "${ENTRY}:${VERDICT}"`: the named `inngest:lifted-outside-terraform`, `inngest:volume-not-found`, `web1:lifted-outside-terraform`, `web1:volume-not-found` arms (Inngest strings verbatim; web-1 strings below), then ONE `*)` arm that keeps today's slug and widens its message: `::error::sole_copy_finding_filer_unexpected_verdict — this step ran for an entry and verdict it does not file (${ENTRY:-none}:${VERDICT:-none}).` and `exit 1` (CTO ruling 7's fail-closed arm; one arm covers an unknown verdict and an unknown entry, and the log names which). It reaches the email and a red gate and files no issue. The body's last pointer line becomes `echo "${DECISION}"`. Labels, milestone retry, dedupe and comment shapes are unchanged. |
| `file_unreadable` | `env:` adds `SUBJECT`, `ADR: ${{ matrix.adr }}`. Titles `infra: the ${SUBJECT} protection check has no usable credential (${NAME})` / `... could not read Hetzner (${NAME})`. Body: `the ${SUBJECT}'s delete-protection flag` and `Decision record: ${ADR}.` Renders identically for Inngest. |
| `clear` | `env:` adds `SUBJECT`. `TITLES` built from `${SUBJECT}`, including both `(name-unreadable)` forms. The comment that says "The web-1 check (#10432) must use a different title prefix" is rewritten: the subject IS the per-row prefix, and C4/C5 prove the two rows' title sets are disjoint on one shared issue store (dedupe and clear match exact titles). |
| `file_finding`, `file_unreadable`, `clear` (all three) | `env:` adds `GH_REPO: ${{ github.repository }}`, so `gh issue list/create/comment/close` work when the leg's checkout failed (today they need the `.git` directory; the gap exists on the Inngest leg on `main` and would be copied to web-1). No output or title changes. |
| `notify` | Name `Email notification (volume protection check)`. `subject: '[INFRA DRIFT] ${{ matrix.subject }} protection check needs attention'`; body: `The twice-daily ${{ matrix.subject }} protection check needs attention.` and `(${{ matrix.adr }})`. Renders identically for Inngest. |
| `gate` | None. |
| Job comment block | Rewritten to describe both rows: WHAT IT CHECKS per row, WHY A MATRIX (`fail-fast: false`, one set of steps), the pins (each row's `volume_id`, anchored to ADR-282 / ADR-119), BOUNDED WAITS per leg, and each row's forcing function for a reviewed lift that reads `unprotected-as-declared` (Inngest: the dated re-protect issue, as today; web-1: Guard B4 in `apps/web-platform/infra/workspaces-luks.test.sh`, which pins `delete_protection = true`, so a lift PR must edit that guard in review). Keep `tracked: #10430`, and add one sentence there: a future check-in keys on `needs.sole-copy-protection-check.result`, which for a matrix job is the combined result of both legs (success only when every leg succeeded, so a missing or cancelled leg makes it non-success), and must not rely on job `outputs` (the job declares none; with a matrix they would come from whichever leg wrote last). Add an ADDING AN ENTRY list naming every place a third row must touch (the row, the `case` arms, `use_entry`, `matrix-shape`'s count and entry set, an N-pin row and its document, `test-affected-paths.sh`, the 8209 register row, runbook 6894's pin count when the id is the Inngest one); the `*)` arm's message and `matrix-shape`'s failure text say "see ADDING AN ENTRY in the job comment". Drop the SCOPE line naming #10432 (keep #10431). |

The web-1 strings (public-safe: no id, no command, no API answer, no "sole copy" / "only copy" wording):

- `web1:lifted-outside-terraform` LEAD: `The delete-protection flag of the web-1 workspaces volume at Hetzner does not
  match what the committed Terraform declares.`
- REMEDY: ``To restore it, the owner-approved `manual-rerun` dispatch of the per-merge apply (or the next infra-path
  merge) re-applies the flag in that run's SSH stage (ADR-119 D1, addendum of 2026-10-08), then read the flag back with
  "Read back the delete-protection flag (read-only token)" in workspaces-luks-cutover-6604.md. An agent reports this
  and does not dispatch it unprompted.``
- `web1:volume-not-found` LEAD: `Hetzner reports no single volume with the expected name and identity for the web-1
  workspaces volume.`; REMEDY: the Inngest "Confirm the Hetzner listing first ..." sentence verbatim up to "do not mean
  the volume is gone.", then ``Only if the volume is gone, treat it as a total loss: use the `soleur:incident` skill and
  ADR-119 (addendum of 2026-10-08) for the loss modes.``
- `web1` DECISION: `Decision record: ADR-119 (D1 and the addendum of 2026-11-10). The read-back: "Read back the
  delete-protection flag (read-only token)" in workspaces-luks-cutover-6604.md.`

### `gha-expr.py` — the `matrix` context

Superseded by CTO ruling 21 (review round 1): `gha-expr.py` is unchanged from `main`. The refusal of an unknown
`matrix` key lives in the harness: `h.py`'s `check()`, called by `refs()` from `render()` and `evif()`, refuses
`matrix.<key>` absent from the selected row (`unresolvable reference`, exit 3) on every expression it renders, so an
empty value can never silently select the wrong row's data. The runner itself renders an unknown matrix key as an
empty string; the harness refuses it. `gha-expr.py` keeps today's "absent is null" semantics for every context. Only
`sole-copy-drift-check.test.sh` imports the module (stays true), so no other consumer depended on a strict branch.

### Suite structure

- **Per-entry constants** set by one helper, `use_entry inngest|web1`: `ENTRY`, `OTHER_ENTRY`, `NAME`, `VOL_ID`, `TF_REL`,
  `TF_RES`, `TF_STEM`, `OTHER_ID`, `OTHER_NAME`, `OK_KEYS`, `TITLE_DIFF`, `TITLE_GONE`, `TITLE_NOCRED`, `TITLE_UNREAD`, the
  per-arm `LEAD_*`/`REMEDY_*`/`DECISION` lines and `OTHER_WORDS` (`SUBJ` and `ADR_ID` were deleted in review round 1, R8).
  The name/id pairs come from `_ids_of` (h.py's `INNGEST_ID`/`WEB1` are a second copy, tied by `id_placement:row`).
  These are the suite's oracle and are written independently of the workflow (titles spelled out per entry, not built
  from the workflow's rows). The suite starts in `use_entry inngest`, so every existing row runs unchanged.
  `use_entry` OWNS these names: today's top-level assignments (`NAME`/`VOL_ID` in the case machinery, `OK_KEYS` after
  `end_row`, the `TITLE_*` block before the F rows) are deleted, so execution passing a former assignment site cannot
  silently reset a web-1 case to Inngest values. A harness row calls `use_entry web1` and checks that `TITLE_DIFF`
  starts with `infra: web-1 workspaces volume` and `VOL_ID` is the web-1 id. Both ids are plain literals in the suite
  (`VOL_ID=106903269` stays as today; `use_entry web1` sets `VOL_ID=106443278`), and the old split
  `WEB1 = "1064" + "43278"` goes with the `web1-id` check it served: runbook 6894's pin-bump list is regenerated with
  `git grep -n <id>` and names "the `VOL_ID` constant in the suite itself", so a split constant would silently drop
  out of that list. `OTHER_NAME` is the other volume's real name.
- **Harness (`h.py`)**: `cmd_extract` also writes `rows.json` (the job's `strategy.matrix.include`). The run spec gains
  `entry`; `cmd_run` selects exactly one row with that `entry` (zero or more than one is exit 3), loads its keys into the
  context as `matrix.<key>`, and `refs()`/`check()` treat `matrix` like `secrets` (a key the row lacks is
  `unresolvable reference`, exit 3).
- **Stubs**: the `gh api` arm accepts `repos/*/commits?...path=apps/web-platform/infra/<file>.tf...per_page=1` for any
  `<file>` matching `[a-z0-9-]+`, records `gh api commits path=<file>` in `$SEQ`, and serves `$S/api.<file>.json`
  (absent: HTTP 404). `set_age` writes the CURRENT entry's file; `set_age_other` writes the other entry's file. No new
  stub file; every stub keeps `#!/usr/bin/env bash`.
- **Fixtures**: `mk_tf` writes `"$1/$TF_REL"` with `resource "hcloud_volume" "$TF_RES"` and the same traps (decoy
  resource, commented-out values, trailing comments); it keeps `assert_fixture_dir` on both operands. `set_api` serves
  the target volume plus the other entry's real-shaped volume (`OTHER_ID`, `OTHER_NAME`).
- **Invariants**: the other entry's id (`OTHER_ID`) may not reach any stream, output, summary or issue; NEITHER id may
  reach any issue title, body or comment (a new jq read of `issues.json`); each request URL equals
  `name=${CASE_NAME}`; no request argv, stdin or env carries `OTHER_NAME`; each recorded `gh api commits path=` equals
  the case's `TF_REL` basename.
- **Shape (`violations`)**, added checks:
  - `matrix-shape`: `strategy` keys are exactly `fail-fast` and `matrix`; `fail-fast` is `False` (absent counts as
    true, the default); `matrix` keys are exactly `include`; `include` is a list of exactly 2 dicts, each with exactly
    the keys `entry, subject, tf_file, tf_resource, volume_id, adr`; `entry` values are exactly `{inngest, web1}`;
    every value is a string matching its pattern (`entry` `^[a-z0-9]{1,16}$`, `subject`
    `^[A-Za-z0-9][A-Za-z0-9 -]{0,39}$`, `tf_file` `^apps/web-platform/infra/[a-z0-9-]{1,64}\.tf$`, `tf_resource`
    `^[a-z0-9_]{1,64}$`, `volume_id` `^[1-9][0-9]{0,11}$` (no leading zero: the probe passes it to `jq --argjson`, where `007` is not valid JSON), `adr` `^ADR-[0-9]{1,4}$`); the job `name:` is exactly
    `sole-copy-protection-check (${{ matrix.entry }})`. These patterns are the only
    validation of row values (a pre-merge check over committed constants; no runtime branch). Distinctness of ids,
    files and titles is proven by N1c, C3 and C4/C5, not restated here.
  - `id-placement` (replaces `web1-id`; CTO Fork 2): in the job's text and JSON, each id appears exactly once, and that
    once is its own row's `volume_id`; no step (`run`, `env`, `with`, `if`, `name`) and no comment in the job region
    names either id.
  - Not added (plan-review cuts): `row-mapping`, `matrix-bindings` and a `pin-literal` check. Every mis-mapping or
    mis-binding is caught by an executed row against the independent `use_entry` oracle (a wrong `PIN` -> WV1
    id-mismatch; a wrong `TF_PATH` -> V1/WV1/C3 and the `gh api commits path=` invariant; a wrong `SUBJECT`/`ENTRY` ->
    WF1; a wrong `ADR` -> WX9), and a re-hard-coded pin literal in a step is already an `id-placement` violation. An
    unknown `matrix.*` ref is caught by `check()` on every rendered expression (H11). The job `name:` (CTO Fork 3) is
    asserted by one line in `matrix-shape`.
- **Pins**:
  - `N1` reads the Inngest pin from `rows.json` (the `inngest` row's `volume_id`) and keeps its four comparisons (ADR-282
    `Hetzner id <pin>`, the postmerge skill, runbook 5c's one-liner).
  - `N1b` becomes: the workflow carries exactly 2 comment-stripped `readonly VOLUME_ID_PIN=<digits>` lines (the two
    sweeps) and both equal the `inngest` row's `volume_id` (a literal inside this job is an `id-placement` violation).
  - `N1c` (new): the `web1` row's `volume_id` equals the `Hetzner id <pin>` stated inside ADR-119's
    `## Addendum — 2026-11-10 (#10432` section (section-bounded with awk, so a mention elsewhere in the file cannot
    satisfy it) AND the id in the `v1/volumes/<id>` URL of runbook 6604's new `## Read back the delete-protection flag
    (read-only token)` one-liner, read with the same bound
    (`awk '/^## Read back the delete-protection flag \(read-only token\)$/{f=1; next} /^## /{f=0} f'`), exactly one
    `v1/volumes/<id>` on the `--only-secrets HCLOUD_TOKEN_READONLY` line, and it differs from the `inngest` row's. The section read starts AFTER the heading line, so the bound cannot close on its
    own start line:
    ``awk '/^## Addendum — 2026-11-10 \(#10432/{f=1; next} /^## /{f=0} f' "$ADR119" | grep -oE 'Hetzner id `?[0-9]+`?' | tr -d '`'``
    must yield exactly one match (ADR-119's house style writes ids in backticks). The runbook side mirrors N1: inside
    the "Read back the delete-protection flag (read-only token)" subsection, the line carrying
    `--only-secrets HCLOUD_TOKEN_READONLY` yields `v1/volumes/<id>`, and that id must equal the row's. A harness row
    writes the correction note as "Hetzner id 106406962" on a copy and N1c must go RED (two matches). A harness row runs N1c on a copy whose addendum body is empty and must go RED.
  - `N3`'s existing `file_unreadable` check `grep -qF 'ADR-282' <<<"$_fu"` becomes a check for `Decision record: ${ADR}.`
    (the literal leaves that step's source), and N3 adds: every `rows.json` `adr` value has a matching
    `knowledge-base/engineering/architecture/decisions/<adr>-*.md` file. `N3` also adds the web-1 pointers: ADR-119 contains `D1 — the sole copy is protected in Terraform` and the heading
    `## Addendum (2026-10-08): the plaintext backstop is retired`; runbook 6604 contains the top-level heading
    `## Read back the delete-protection flag (read-only token)` exactly once. The rendered web-1 text (`ADR-119 D1`, that subsection's
    name, `workspaces-luks-cutover-6604.md`, `soleur:incident`) is asserted by WF1 and WX5, so N3 checks only the
    document side for web-1. Over the new subsection's command line only (so the outcome table's prose "does not fall
    back to `HCLOUD_TOKEN`" stays legal), N3 requires exactly one `--only-secrets`, naming `HCLOUD_TOKEN_READONLY`,
    and `curl -sS --config -`, and bans `HCLOUD_TOKEN([^_]|$)`, an Authorization header on argv in any spelling (`-H`,
    `--header`, `--header=`, `-HAuthorization`, bundled `-sSH`, `--proxy-header`, `--oauth2-bearer`; review round 1, H15)
    and a `:-` fallback expansion; one mutant row per pattern (a second `--only-secrets HCLOUD_TOKEN`, each argv-header
    spelling, `${HCLOUD_TOKEN_READONLY:-$HCLOUD_TOKEN}`).
- **Counting**: `FLOOR` and `TABLE_ROWS` move to the realized numbers in the same commit as the rows (expected about
  +30 table rows and +50 assertions after the plan-review cuts). The header comment's PROPERTY and COUNTING paragraphs are rewritten for two
  entries.

## Files to Edit

- `.github/workflows/scheduled-terraform-drift.yml` — the `sole-copy-protection-check` job only (Design above). The
  orphan sweeps' prose ("The sole-copy-protection-check issue is the primary page for a gone volume", in two comments,
  two `::error::` echoes and two emails) is deliberately left alone: the sweeps pin only the Inngest volume, and that
  issue's title names the "Inngest store volume" subject, so the pointer stays unambiguous; no suite asserts those
  strings either way.
- `plugins/soleur/test/sole-copy-drift-check.test.sh` — harness, stubs, per-entry constants, web-1 table, cross-entry
  rows, shape checks and mutants, N1/N1b/N1c/N3, H1 extension, harness rows H11/H12, FLOOR, TABLE_ROWS, header.
- `plugins/soleur/test/lib/gha-expr.py` — not edited: the strict `matrix` branch was reverted to `main` (CTO ruling
  21); `check()` in the harness refuses an unknown `matrix` key.
- `plugins/soleur/test/token-drift-workflow-causes.test.sh` — R3b's probe literal becomes
  `sole-copy-protection-check/Probe the volume protection flag at Hetzner` (nothing else; its FLOOR is unchanged
  because R3b stays one assertion).
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` —
  appended `## Addendum — 2026-11-10 (#10432, recurring delete-protection check for the volume)` only.
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` — the
  `scheduled-terraform-drift.yml::sole-copy-protection-check` register row: "one `api.hetzner.cloud` GET of the Inngest
  store volume by name" becomes one GET per matrix leg (the Inngest store volume and the web-1 workspaces volume), same
  token, same tier. The suite pins only the `| O5 |` row of this file, which is not touched.
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` — appended
  `## Addendum - 2026-11-10 (#10432, the pin moves to the matrix row)` only: "Appended; nothing above is edited. The
  probe's `readonly VOLUME_ID_PIN=` literal is replaced by the `inngest` include row's `volume_id`; N1b now pins exactly
  two sweep copies, both equal to that row." The 2026-10-24 addendum's "exactly three" stays as the dated record.
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` — the pin-bump checklist's "every
  `readonly VOLUME_ID_PIN=` line ... (exactly three: the sole-copy probe and the two orphan sweeps)" becomes "exactly two
  (the two orphan sweeps), plus the `volume_id:` of the `inngest` row in the `sole-copy-protection-check` matrix". An
  operational checklist, not an append-only record.
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` — (1) an appended, permanent
  top-level section `## Read back the delete-protection flag (read-only token)` (a `##`, not a `###`: the file's last
  `##` section is the dead-man heartbeat section, and a `###` would nest under it; the runbook's code blocks carry
  shell comment lines starting with a hash, so every section bound uses `/^## /`), a copy of
  runbook 6894 section 5c step 3's one-liner for id 106443278: `--only-secrets HCLOUD_TOKEN_READONLY
  --no-exit-on-missing-only-secrets`, no fallback to `HCLOUD_TOKEN`, the bearer header passed to `curl --config -` on
  stdin, and one word per outcome (`protected`, `not-protected`, `missing-token`, `volume-gone`, `read-failed`) with its
  exit code. This is the read-back the web-1 REMEDY and DECISION point at, and the one N1c and N3 read. (2) In "Verify
  the retired end state (read-only ...)", all four GETs are rewritten in the 6894 section 5c shape, not just renamed:
  `doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY --no-exit-on-missing-only-secrets --
  sh -c '[ -n "$HCLOUD_TOKEN_READONLY" ] || { echo missing-token; exit 3; }; printf "header = \"Authorization: Bearer
  %s\"\n" "$HCLOUD_TOKEN_READONLY" | curl -sS --config - ...'` (renaming the variable alone would still inject the
  read/write token, send an empty bearer header when the read-only one is missing, and put the token in curl's argv). The
  trailing note "Use `HCLOUD_TOKEN_READONLY` once it is provisioned, #9371." becomes a statement that the block uses it
  (CTO ruling, row 12). The ids, URLs and
  `jq '.volume.protection.delete'` text that N1c reads are unchanged. #9371 stays open (it is about the cutover job).
- `scripts/lib/test-affected-paths.sh` — add `apps/web-platform/infra/workspaces-luks.tf`,
  `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` and
  `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` to
  `AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS`, keeping the array sorted (the suite now reads all
  three, so an edit to any of them must select it).

## Files to Create

None (the plan and `tasks.md` aside).

## Implementation Phases

### Phase 1a — GREEN refactor of the suite against the UNCHANGED workflow

So that a harness bug and a workflow bug cannot look the same in Phase 2, the per-entry machinery first lands green on
today's workflow, with `FLOOR` and `TABLE_ROWS` unchanged:

1. `use_entry inngest` (the default), the per-path commits stub, `mk_tf`/`set_api` parameterization, and the invariants
   extension (other-entry id and name bans, the `issues.json` id ban, the `gh api commits path=` check).
2. Run the suite against the untouched workflow: `=== Results: 195/195 passed` with `FLOOR=195`, `TABLE_ROWS=126`.
   Commit this alone (message: refactor, no new rows, 195/195 on the unchanged workflow).

### Phase 1b — RED: the matrix rows (cq-write-failing-tests-before)

1. `gha-expr.py` negative controls in S0b first: `python3 gha-expr.py value "matrix.nope" '{}'` must exit 3 and
   `python3 gha-expr.py value "matrix.entry" '{"matrix.entry":"web1"}'` must print `web1`. RED against today's module
   (it prints an empty line). Reverted in review round 1 (CTO ruling 21): the S0b matrix clauses and H11a are deleted
   and `gha-expr.py` stays as on `main`; `check()` in the harness is the one refusal.
2. Harness: `rows.json`, row selection by `entry`, `matrix` in `refs()`/`check()`. The extractor floor (E1) also
   requires `strategy.matrix.include` with the two entries; against today's workflow it is a FATAL ("job lacks the
   matrix rows"), which is the RED.
3. Shape checks and mutants (table below), N1/N1b/N1c/N3, the web-1 table, cross-entry rows, H1 extension, harness rows H11 and H12 (new ids: table rows
   `H8`, `H9`, `H10` already exist and keep their meaning).
4. The real-file derivation rows: the existing `R1` (the probe's derivation over the checkout's REAL
   `inngest-redis-luks.tf`, compared to an independent python derivation) stays and now exercises the parameterized
   awk; `WR1` does the same over the REAL `workspaces-luks.tf`. Each asserts the derived name, the expected flag, and
   that the resource line matches exactly once. Fixture shapes from `mk_tf` alone cannot prove the real web-1 file
   parses.
5. Run the suite against the unchanged workflow: it must stop RED at E1. Commit the RED rows separately (message names
   the expected RED).
6. Per-row RED evidence (E1 alone shows nothing about individual rows): run the RED suite through
   `SOLE_COPY_DRIFT_WF=<copy>` against a scratch copy of the workflow that has ONLY the matrix scaffold (`name:`, both
   include rows, `fail-fast: false`) with today's hard-coded Inngest steps unchanged. E1 then passes; the 126 existing
   rows must stay green (the matrix plumbing alone does not break Inngest), and every new W and C row must fail with its
   own message. List each row and its failure line in `mutation-proofs.md`; a W or C row green against that copy is
   vacuous and is rewritten before Phase 2.

### Phase 2 — GREEN: `gha-expr.py` and the workflow

1. `gha-expr.py` `matrix` strictness; S0b green. (Reverted in review round 1, CTO ruling 21: `gha-expr.py` is
   unchanged from `main`.)
2. The workflow job per the Design table. Inngest strings: copy them, never retype them; diff the rendered Inngest
   titles, LEAD, REMEDY and email subject against `git show origin/main:.github/workflows/scheduled-terraform-drift.yml`
   (the existing V/F/X rows assert most of them exactly).
3. Run the suite to green; set `FLOOR` and `TABLE_ROWS` to the realized numbers it prints.

### Phase 3 — the sibling edits

1. ADR-119 addendum (append only). Content: what was added (the `web1` row, its name, the declared flag's file, the
   same verdicts and grace, its titles under "web-1 workspaces volume", p1 finding / p2 could-not-perform, the email);
   the pin sentence written exactly as `Hetzner id 106443278` with the live read (2026-11-10T10:57:41Z: name
   `soleur-web-platform-data-luks`, protection.delete=true, attached to server 123931471; ADR-148 carries the same id);
   the correction note (the 2026-07-23 addendum's `106406962` is the orphaned volume that addendum's re-cut was built
   to replace, and the record says the first provision was re-cut (`expenses.md`, corrected 2026-10-01); the 2026-07-23
   text stays as the dated record; the note writes "the volume `106406962`", never the
   `Hetzner id <digits>` form, so N1c's exactly-one bound stays true); the pin bump for the web-1 id points at
   `git grep -n 106443278` rather than a fixed list (review round 1, R4); what the check does not defend (a single diff that
   changes the `.tf`, the row and this addendum proves consistency, not integrity; the outside anchor is live Hetzner
   state; a mis-minted read-only token is undetectable here, control O5); no Sentry check-in of this job's own (#10430, held
   while #6590 is open): a workflow that never runs is caught by the `scheduled-terraform-drift` monitor (the
   drift-check job's check-in), while this job being skipped, or one leg never starting, is the accepted residual; a
   failed checkout files the p2 issue but sends no email. The web-1 pin bump: if `hcloud_volume.workspaces_luks` is ever recreated, the `web1` row's `volume_id`,
   this addendum's id and runbook 6604's read-back move in the same PR as the `.tf` change (N1c reds the suite on a
   partial bump; the first scheduled run reds on a missed one); the incident owner owns it, as ADR-282 states for the
   Inngest pin. Two accepted windows, stated plainly: (i) the grace keys on the last commit to the whole
   `workspaces-luks.tf` (CTO ruling 5: the same 90-minute grace per entry), so an unrelated edit to that file within 90
   minutes of a real lift reads `lift-pending-apply` (green, warning only) and the issue lands one 12-hour cycle later;
   (ii) a reviewed lift reads `unprotected-as-declared` (green). Guard B4 in `apps/web-platform/infra/workspaces-luks.test.sh`
   only makes the lift reviewed (the lift PR must edit it); the lift PR must also open a dated re-protect follow-through
   issue before it merges (ADR-282 step 1), and that issue is the only forcing function back to protected (CTO ruling 20).
   Its probe is event-grep, never the Date shape (CTO ruling 28, amending ruling 20: a Date-shape `exit 0` closes the issue
   as PASS on its date, and the sweeper holds no Hetzner token): exit 0 only on a later `scheduled-terraform-drift` run on
   `main`, after the issue's `earliest`, whose web1 leg succeeded and emitted `sole-copy-check verdict=matches-declared
   entry=web1` (`entry=inngest` for the Inngest row); 2 before the pinned date, 5 after it, 3 on a failed read. (iii) A leg
   that reads no flag files the p2 could-not-perform issue only (no email unless a filer fails).
2. `infra-credential-tiers-8209.md` register row, the ADR-282 appended note, the runbook 6894 checklist and both runbook
   6604 edits (Files to Edit). Run the new 6604 one-liner once, read-only, and record its word (`protected` expected)
   in `mutation-proofs.md`; a `missing-token` or `read-failed` answer is reported, never worked around with the
   read/write token.
3. `token-drift-workflow-causes.test.sh` R3b literal.
4. `scripts/lib/test-affected-paths.sh` array.

### Phase 4 — verification (local, then CI)

1. `( time bash plugins/soleur/test/sole-copy-drift-check.test.sh )` green, and its realized count equals `FLOOR`.
   Record wall, user and sys before (the baseline above: user+sys about 90 s) and after, on the same host, in
   `mutation-proofs.md`; compare user+sys, not wall (the baseline's load average was 40-64). After the `merge_group`
   run, add that run's per-suite time. The suite header's COUNTING paragraph gains one line: edits to ADR-119, runbook
   6604 and `workspaces-luks.tf` now select this suite.
2. Mutation proofs on COPIES via `SOLE_COPY_DRIFT_WF=<copy>` (never the real file): execute every Guard 1-3
   mutation-matrix row that is not an in-process S2 mutant (the Guard Contract is the one inventory; this step does not
   restate it). Record each result (the row that went RED) in
   `knowledge-base/project/specs/feat-one-shot-10432-web1-workspaces-protection-check/mutation-proofs.md`; `ship` folds
   it into the PR body.
3. Delete one new row block on a copy of the suite and confirm the outer count fails the FLOOR (then discard the copy).
4. `bash plugins/soleur/test/token-drift-workflow-causes.test.sh`.
5. Repo-global ratchets: `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`,
   `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash scripts/guard-vacuity-floor.test.sh`,
   `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bash scripts/alarm-issue-filing-guard.test.sh`.
6. The other suites that read this workflow: `bash plugins/soleur/test/terraform-drift-step-order.test.sh`,
   `bash plugins/soleur/test/terraform-drift-sentry-leg.test.sh`,
   `bash plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`,
   `bun test plugins/soleur/test/terraform-target-parity.test.ts`, `bash tests/scripts/test-argv-bearer-sweep.sh`,
   `bash tests/scripts/test-apply-github-infra-mint-shape.sh`, `bash tests/scripts/test-git-data-wipe-wedge.sh`,
   `bun test apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` (reads `strategy.matrix`),
   `bun test apps/web-platform/test/server/inngest/cron-terraform-drift.test.ts`,
   `bash scripts/check-cloudflare-token-drift.test.sh` (loops over every job),
   `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`,
   `bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh`,
   `bash scripts/cf-tunnel-liveness-gate-mutations.test.sh`. This list is a floor: the census is
   `git grep -l scheduled-terraform-drift -- '*.test.*' 'tests/'`, rerun at work time, and every test-file hit runs.
   Use each suite's documented runner (check the suite's header or `scripts/lib/test-affected-paths.sh` before
   choosing `bun test` vs `vitest`).
7. `python3 -I -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' .github/workflows/scheduled-terraform-drift.yml`.
8. Byte-identity of the Inngest strings (the new suite cannot render `origin/main`'s file, since E1 is FATAL without
   the matrix, so this is a text check over the old job's lines):

   ```bash
   git show "$(git merge-base origin/main HEAD)":.github/workflows/scheduled-terraform-drift.yml \
     | sed -n '/^  sole-copy-protection-check:/,/^  rung2-rehearsal-orphan-sweep:/p' \
     | grep -E '^ *(LEAD|REMEDY)=|^ *(subject|body): ' | sed 's/^ *//; s/ ;;$//' \
     | while IFS= read -r l; do grep -qF -- "$l" .github/workflows/scheduled-terraform-drift.yml || echo "MISSING: $l"; done
   ```

   Expected output: only the notify `subject:` and `body:` lines (they now carry `${{ matrix.subject }}` /
   `${{ matrix.adr }}`, and the suite's X rows assert their rendered Inngest text).

   Second half, for the strings that become templates (every `TITLE=` line of `file_finding` and `file_unreadable`,
   every element of `clear`'s `TITLES` including both `(name-unreadable)` forms, the `file_unreadable` body lines, and
   the three volume-naming `finish()` notes): extract the old lines and the new lines into two files under the
   scratchpad, substitute `${SUBJECT}` -> `Inngest store volume` and `${ADR}` -> `ADR-282` in the new ones (a
   `python3 -I` one-off over the two files, pure string replacement), and `diff` them; the expected diff is empty.
   AC2's `TITLE_*` claim is checked the same way: the old top-level `TITLE_*` block and the `use_entry inngest` block
   are diffed, and the values must be identical (moved verbatim). Confirm at work time that the
   `sed` range end is the job that follows `sole-copy-protection-check` in the file.
9. `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-10-infra-web1-workspaces-volume-protection-check-plan.md`.
10. A missing summary line or `rc=124` under host load is UNRESOLVED, never a pass or a fail: rerun with a longer bound
   before concluding (learning 2026-11-09, session error 3).
11. CI is the gate: the `merge_group` run of this suite is the Guard 1 evidence.

### Phase 5 — post-merge (acceptance f)

Prefer the first Inngest-dispatched run on `main` after the merge (06:00 or 18:00 UTC). A `workflow_dispatch` of
`scheduled-terraform-drift.yml` on `main` is the same run the dispatcher makes and is acceptable; if one is made, arm a
Monitor watch on it (hr-dispatch-async-must-arm-watch). Read, for BOTH jobs `sole-copy-protection-check (inngest)` and
`sole-copy-protection-check (web1)`, the probe's `sole-copy-check verdict=matches-declared ...` line and the gate's
`(clean)` line, and confirm no new `infra-drift` issue titled with either subject. Any other verdict on the web-1 leg
is a real finding (or a could-not-perform) and is handled by the issue it files; it does not reopen this plan.

### Phase 6 — #11163 (in the ship phase)

`gh issue close 11163 --comment "<evidence>"` with: the grep `git grep -n unrouted b258336eb5 --
.github/workflows/scheduled-terraform-drift.yml` returned nothing (exit 1); `git log -S 'unrouted until #10972'` names
47aa18b44a (#11535) as the commit that last touched the string; CTO ruling 2026-11-10 that the close is not
operator-held. Before closing, re-run the grep on the then-current `origin/main` (hr-before-asserting-github-issue-status).

## Arm x loosening table (hand this to every fix agent)

Each cell names the loosened mutant a fix round could leave behind and the row that must turn RED. "I" is the Inngest
arm, "W" the web-1 arm. Rows prefixed `S2/` are in-process shape mutants; `W*` rows are the web-1 table; `C*` rows
are cross-entry; `N*` are pins.

| Path | Inngest arm (I): loosened mutant -> RED row | web-1 arm (W): loosened mutant -> RED row |
|---|---|---|
| Name + flag derivation | probe reads the other row's `TF_PATH` -> V1 (could-not-read: no `inngest-redis-luks.tf` resource in the fixture) | probe regex hard-codes `inngest_redis_luks`, ignoring `TF_RESOURCE` -> WV1 (could-not-read), WR1, WT3 (WT1 deleted, CTO ruling 23) |
| Derivation, real file | `R1`/`R2` unchanged; R1 now exercises the parameterized awk | `WR1` (REAL `workspaces-luks.tf` vs an independent python derivation; the shared traps stay single-run in R2) |
| Id pin | Inngest pin re-hard-coded as a literal -> S2/`id-placement`; swapped row ids -> V1 (id-mismatch) and N1 | web-1 row carries the Inngest id -> WV1 (id-mismatch), N1c; jq pin compare dropped -> V8/WV8 (C2 deleted, ruling 23) |
| Pin anchors | ADR-282 / skill / runbook 5c disagree -> N1; a third or missing sweep copy -> N1b | ADR-119 addendum or runbook 6604 disagree -> N1c; the id stated only outside the addendum section -> N1c |
| Request URL | `name=` filter dropped -> L2, invariants | request carries the other name -> the per-case request-URL invariant (C1 deleted, ruling 23) |
| 90-minute grace | `tf_commit` path hard-coded to the other file -> C3 (I leg) | `tf_commit` path hard-coded to `inngest-redis-luks.tf` -> C3 (W leg: a 5-minute-old Inngest commit hides a 3-hour-old web-1 lift), WV3 (WV3b deleted, ruling 23) |
| Grace boundary | 89/91 -> V3b | the 90-minute constant is shared, so 89/91 -> V3b (WV3b deleted, ruling 23) |
| Finding filer | title reverts to the Inngest literal -> renders identically on the I leg, so only WF1 sees it; p1 label dropped -> F1 | `web1` arms deleted (falls to `*)` or to Inngest strings) -> WF1, WF12 (body contains "Inngest"); p1 dropped -> WF1 |
| Could-not-perform filer | titles revert to the Inngest literal -> invisible on the I leg; the merged C4/C5 row and C6 catch it (WX7 deleted, ruling 23) | web-1 titles collide with Inngest's -> the merged C4/C5 row, C6; `ADR` literal -> WX9 |
| Clear step | `TITLES` lists both subjects -> the merged C4/C5 row (a clean Inngest run closes the web-1 finding) | same mutant -> the merged C4/C5 row (a clean web-1 run closes the Inngest finding); `(name-unreadable)` forms shared -> the merged C4/C5 row |
| Email | subject reverts to the Inngest literal -> invisible on the I leg; WF1 catches it | subject literal "Inngest store volume" -> WF1; ADR literal `ADR-282` -> WF1 |
| Public safety | Inngest id in a body -> F12, invariants (issues.json ban) | web-1 id in a body -> WF12, invariants (issues.json ban); `recipe_vocab` gains `106443278` -> F13 extension |
| Token | fallback to the read/write name -> H9, S2 (rw-token-named) | same code edit (the read names one literal on both legs) -> H9 |
| Row values | a value outside its pattern (e.g. a `tf_resource` with a metacharacter) -> S2/`matrix-shape` | same |
| Matrix plumbing | `fail-fast` true or absent -> S2/`matrix-shape`; a third row, a renamed or missing key -> S2/`matrix-shape`; an unknown `matrix.*` ref -> H11 | same |
| Finding filer catch-all | `*)` arm deleted or made non-failing -> WX16 | same |
| Expression strictness | `check()` lets an unknown matrix key through -> H11b, H11c (`gha-expr.py` unchanged from `main`, CTO ruling 21) | same |
| Row selection | zero or two rows match the entry -> H11d (C8, the swapped-order must-PASS, deleted by ruling 23) | same |
| Step list (review round 2) | an extra `uses:` or `run:` step, two steps swapped, a second checkout -> S1/S2 `step-sequence`, `checkout-count`; the harness refuses an unmodelled action -> H11e | same (one job) |
| Step `if:` and keys | any step's `if:` edited, added (checkout `if: false`) or removed -> S2 `step-if:<id>`, `step-key:<id>:if` | same |
| Expression contexts | a `runner`/`vars`/`env`/`job` context, or a modelled root read by index, in any `if:`/`env:`/`with:`/`name:` -> S2 `expr-context:<loc>:<root>`; at run time -> H11e | same |
| Env names | a probe env `DOPPLER_API_HOST`/`HTTPS_PROXY`/`LD_PRELOAD`, a workflow env `HTTPS_PROXY`/`CURL_CA_BUNDLE`/`LD_PRELOAD` -> S2 `step-env:probe`, `wf-env` | same |
| Checkout and notify actions | checkout on a tag (`@v4`) -> S2 `checkout-uses`; a notify `with:` value changed -> S2 `notify-with` | same |
| Verdict lines present | the gate's clean or `::error::` echo stripped of `verdict=`, or the probe's finish echo removed -> the per-case verdict-line count (H5 `_iv_noprobeline`, `_iv_nogateline`, `_iv_twogatelines`) | same |
| Runbook 6604 read-only lines | an argv header in any spelling, a second token channel (`-u`, `--oauth2-bea`, URL credentials, a second curl in the wrapper), another Doppler config or the wrapper without `--no-exit-on-missing-only-secrets`, `jq` outside the wrapper -> H15 (exact wrapper, exact stdin construct, curl argument grammar, token-name count 3, tail check) | n/a (6604 is the web-1 runbook) |
| Forcing-function prose | "Guard B4 … forcing function" in either word order, `Re-evaluate by`, the marker removed or moved to another job's comment -> N4 (H17) | same |

## Guard Contract

### Guard 1 — the matrix entries of the sole-copy protection check

**Property.** For every include row of `sole-copy-protection-check`, a live Hetzner volume that carries that row's
name and pinned id and whose `protection.delete` differs from that row's own `.tf` declaration beyond 90 minutes of
that file's last commit, or that is absent or ambiguous, files that row's own p1 issue and turns that leg red, and no
row's request, pin, expected flag, grace, titles, clear step or email depends on the other row's data.

**Assembly.** The chokepoint is the job's `strategy.matrix.include` list: it is the only source of per-entry data, and
it reaches the `run:` bodies only through `env:` bindings (`expr-in-run` forbids an expression inside `run:`); the
`notify` step reads `matrix.*` in its `with:` inputs instead. The bindings live in six steps (`tf_commit`, `probe`,
`file_finding`, `file_unreadable`, `clear`, and `notify` via `with:`). Title text is built at
three sites (`file_finding` TITLE, `file_unreadable` TITLE, `clear` TITLES), per-entry prose at one (`file_finding`'s
`case "${ENTRY}:${VERDICT}"`), the request at one (`bc_curl` in `probe`), the pin compare at one (the probe's jq). In the
suite, every case enters through one harness function (`cmd_run`), which selects exactly one row by `entry`.

**Mutation matrix.**

| # | Edit (derived from the design) | Must turn RED |
|---|---|---|
| 1 | Dispatch: `cmd_run` ignores `entry` and always loads the first row | every W row (each asserts web-1 titles, name and id) and C3-C6 (C1 and C2 deleted and C4/C5 merged, ruling 23) |
| 2 | Second member after a compliant first: the `web1` row is correct, a third row `entry: web2` is appended | S2/`matrix-shape` (exactly 2 rows) |
| 3 | Swap `volume_id` between the rows | V1 and WV1 (id-mismatch), N1, N1c |
| 4 | `tf_commit` hard-codes `inngest-redis-luks.tf` (a window property: the grace) | C3 W leg (a 5-minute-old Inngest commit must not open the web-1 grace), invariants (`gh api commits path=` mismatch) |
| 5 | `clear` builds `TITLES` for both subjects | the merged C4/C5 row |
| 6 | `fail-fast` removed (defaults to true) | S2/`matrix-shape` |
| 7 | The `web1:` case arms deleted | WF1, WF12, WX5 |
| 8 | The probe ignores `PIN` and keeps a literal | S2/`id-placement`, WV1 |
| 10 | The probe ignores `TF_RESOURCE` (regex hard-codes `inngest_redis_luks`) | WV1, WR1, WT3 (WT1 deleted, ruling 23) |
| 11 | The notify subject made the literal "Inngest store volume" | WF1 |
| 9 | `id-placement` relaxed back to "the web-1 id appears somewhere in the job" (a second copy in a comment passes) | S2 row "the web-1 id in a comment" |

**Harness rows.** RED edits to the SUITE: `use_entry web1` made a no-op -> N1c, WF1, WF12, WV1, WX5, WX9, C3, C4-C6
and C9 (observed, `mutation-proofs.md` row "harness: `use_entry web1` a no-op"; a full no-op otherwise turns every W
case into a passing Inngest case; the selected-entry invariant is deleted by CTO ruling 22, H13 by ruling 23); WR1's
independent derivation takes its path and resource from `use_entry`, never from `rows.json`; `invariants()` stops
reading `issues.json` for ids -> H12; `check()` stops refusing an unknown `matrix` key -> H11b, H11c; the gh stub
serves one commits answer for every path -> C3. Must-PASS non-canonical inputs: none kept. C8 (the include rows in
swapped order) is deleted by ruling 23: rows are selected by `entry`, so row order carries no meaning and C8 could
never go red; H11d covers row selection.

**Anchor.** The `web1` pin is compared to ADR-119's 2026-11-10 addendum and runbook 6604's read-back; the `inngest` pin
to ADR-282, the postmerge skill and runbook 5c. One diff can edit a pin and its documents together, so the N rows prove
consistency, not integrity. What no diff can edit is live Hetzner state: a wrong pin produces `volume-not-found
reason=id-mismatch` on the first scheduled run (a p1 issue), and acceptance (f) reads both legs live after merge.
`FLOOR` is a `>=` count, so it is paired with `TABLE_ROWS` (row conservation, H3) and named rows.

### Guard 2 — the evaluator refuses an unknown matrix key

**Property.** An expression that names a `matrix.<key>` absent from the selected row is a harness error (exit 3),
never an empty value.

**Assembly.** One chokepoint, in the harness: `h.py`'s `check()`, called by `refs()` from `render()` and `evif()`;
every `if:`, `env:` and `with:` expression of every case passes through it. `gha-expr.py` is unchanged from `main`
(CTO ruling 21, amending ruling 1): its strict-matrix branch only duplicated `check()`, and only the strictness
self-tests went red without it (`mutation-proofs.md` row G2 r1).

**Mutation matrix.**

| # | Edit | Must turn RED |
|---|---|---|
| 1 | `check()` stops treating `matrix` refs (dispatch) | H11b (a job whose step env names `matrix.nope` must exit exactly 3 with `unresolvable reference: matrix.nope`) |
| 2 | Strictness applied only to the first `matrix.*` ref of an expression (second member) | H11c (`matrix.entry == 'web1' && matrix.nope == 'x'`, exact rc 3 and the same stderr line) |
| 3 | Row selection loosened: `cmd_run` takes the first include row when zero or two rows match `entry` (the "selected row" the refusal is judged against is then the wrong one) | H11d (zero or two matches must exit 3; one match renders that row) |

H11b and H11c run against `$EXPRLIB` itself, with no stripped evaluator copy, so `check()` is the only strictness
under test; an instrument control runs the same spec on the pristine harness (rc 3) and with `matrix.nope` removed
(rc 0). H11a and the S0b matrix clauses are deleted with the evaluator branch (ruling 21).

**Harness rows.** RED: H11 run through its own `printf` + `exit` reporting (not through the helpers under test).
Must-PASS: `matrix.entry` present renders its value; a `steps.*` ref absent from the context still renders empty (no
collateral strictness).

**Anchor.** Not a stored-value guard; the comparison is against the job file itself.

### Guard 3 — every pin agrees with its documents

**Property.** The `inngest` row's `volume_id` equals ADR-282's, the postmerge skill's, runbook 5c's and both sweeps'
literals; the `web1` row's equals ADR-119's 2026-11-10 addendum and runbook 6604's read-back; the two differ.

**Assembly.** `rows.json` (the include rows), the two `IDENTITY-PROOF-BEGIN` literals in the sweep jobs, ADR-282,
`plugins/soleur/skills/postmerge/SKILL.md`, runbook `inngest-luks-cutover-6894.md` 5c, ADR-119's addendum section,
runbook `workspaces-luks-cutover-6604.md`.

**Mutation matrix.**

| # | Edit | Must turn RED |
|---|---|---|
| 1 | `web1` row id changed by one digit | N1c, WV1 |
| 2 | The addendum's `Hetzner id` sentence moved outside the addendum section (dispatch of the section bound) | N1c |
| 3 | A third `readonly VOLUME_ID_PIN=` copy added inside the sole-copy job after the compliant sweeps (second member) | N1b, S2/`id-placement` |
| 4 | Both rows given the same id | N1c (must differ), S2/`id-placement` (one id then appears twice) |

**Harness rows.** RED: `N1c` reading the whole ADR file instead of the section (an older mention would satisfy it) ->
covered by row 2. Must-PASS: the addendum text with the id inside backticks or not (the anchor matches the digits).

**Anchor.** See Guard 1: the outside anchor is the live Hetzner read on every scheduled run.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (94 issues) has no body naming any planned file.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings 1-6 (brief) and Forks 1-3 (this plan) are recorded in
`knowledge-base/project/specs/feat-one-shot-10432-web1-workspaces-protection-check/decision-challenges.md`. The change is
detection only on an existing read-only job; no new credential, store, connection, cost or product surface. Other
domains (Product, Legal, Marketing, Operations, Finance, Sales, Support): no implication. The volume holds user data,
but the job reads one flag of it and writes only public-safe issue text; no personal data is read or moved, so the
GDPR gate does not fire.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly. A broken check either stays silent about a lifted
delete-protection flag on the volume that holds every user's checked-out repository (today's state for web-1), files a
false p1 issue and email every 12 hours, or, worst, breaks the existing Inngest check so that neither volume is
watched. The last is why the Inngest rows must stay byte-identical and the legs independent (`fail-fast: false`).

**If this leaks, the user's data is exposed via:** a public issue body that names a recipe, or "only copy" wording,
would put a searchable, notifying pointer at the one object whose deletion loses every workspace. The bodies carry the
volume name, the verdict and pointers only, and the suite bans both ids and the recipe vocabulary from every rendered
body. The ids are not secret: they are public in the workflow's matrix rows, ADR-119/148/282, runbooks 6604 and 6894,
and the probe's public log line. The ban keeps recipes out of issues; it is not a confidentiality control, and no
later change should be justified by treating an id as confidential.

**Brand-survival threshold:** aggregate pattern

A lifted flag alone deletes nothing (it removes an accident guard); the harm needs a second event. One missed alert is
not a user incident; a pattern of silent detectors is.

## Observability

```yaml
liveness_signal:
  what: each leg's gate line "sole-copy-check verdict=<verdict> entry=<entry> (clean)" (the probe's verdict line also carries entry=<entry> directly after verdict=<v>, CTO ruling 26) and the conclusion of jobs "sole-copy-protection-check (inngest)" and "sole-copy-protection-check (web1)"
  cadence: twice daily (06:00 and 18:00 UTC), dispatched by apps/web-platform/server/inngest/functions/cron-terraform-drift.ts
  alert_target: an infra-drift issue per leg (p1 finding, p2 could-not-perform) plus the notify-ops-email message
  configured_in: .github/workflows/scheduled-terraform-drift.yml, job sole-copy-protection-check, strategy.matrix.include
error_reporting:
  destination: GitHub issues labelled infra-drift (exact-title dedupe per leg) and the ops email via .github/actions/notify-ops-email
  fail_loud: yes, with one stated exception; the could-not-perform filer is the complement of every named verdict (an empty verdict files), the gate is red on every non-clean verdict, and the email fires on a finding or on any failed or cancelled filer or clear step. Exception: a failed checkout files the p2 issue (the filers carry GH_REPO, row C10) but sends no email, because notify is a local action that needs the checkout
failure_modes:
  - mode: web-1 flag lifted outside Terraform
    detection: layer 6 (workflow run log) - the probe's ::error::sole-copy-check verdict=lifted-outside-terraform line and the red gate on job "sole-copy-protection-check (web1)"
    alert_route: p1 issue "infra: web-1 workspaces volume delete protection differs from Terraform (soleur-web-platform-data-luks)" plus email
  - mode: web-1 volume missing, duplicated, or carrying another id
    detection: layer 6 (workflow run log) - verdict volume-not-found with reason zero, many or id-mismatch in the leg's log and job summary
    alert_route: p1 issue "infra: web-1 workspaces volume not found at Hetzner (...)" plus email
  - mode: the check cannot run (token absent or rejected, Hetzner unreachable, malformed answer or matrix row, crash)
    detection: layer 6 (workflow run log) - verdict no-token or could-not-read, or an empty verdict
    alert_route: p2 issue under the leg's own could-not-perform title; email only if a filer fails
  - mode: one leg red
    detection: layer 6 (workflow run log) - fail-fast false keeps the other leg running to its own verdict
    alert_route: each leg's own issue
  - mode: one leg cancelled or timed out
    detection: layer 6 (workflow run log) - the probe is skipped and the always() could-not-perform filer runs on that leg with an empty verdict
    alert_route: a p2 issue under that leg's own "(name-unreadable)" title only (row C9)
  - mode: one leg's checkout fails or times out
    detection: layer 6 (workflow run log) - the checkout step fails, the probe is skipped, the verdict is empty
    alert_route: a p2 "(name-unreadable)" issue for that leg (the filers name the repository through GH_REPO, so they work without a checkout; row C10); no email (accepted residual, the notify action is local)
  - mode: one leg never starts while the other is clean
    detection: none from this job today; the combined `needs.sole-copy-protection-check.result` turns non-success when a leg never runs, so the future #10430 check-in (held while #6590 is open) closes this residual
    alert_route: the accepted residual, stated in the job comment and the ADR-119 addendum
  - mode: the whole workflow never runs
    detection: Sentry monitor scheduled-terraform-drift (the drift-check job's final check-in in the same workflow run)
    alert_route: that monitor's existing alert; work-time step: confirm read-only that it still routes to a person after the #6590 prune
  - mode: the workflow runs but this job is skipped
    detection: none from this job (no Sentry check-in of its own, #10430)
    alert_route: the accepted residual, stated in the job comment and the ADR-119 addendum
logs:
  where: GitHub Actions run logs and job summaries of scheduled-terraform-drift.yml, per leg
  retention: the repository's Actions log retention (GitHub default 90 days)
discoverability_test:
  command: grep -c -e 'entry: web1' .github/workflows/scheduled-terraform-drift.yml
  expected_output: "1"
```

The command proves the web-1 leg is declared (it prints `0` before this change). It carries no pipe and no `${`, so it
survives preflight Check 10. The live lookup for open web-1 protection issues uses the public API with no credential
and a bound: `curl -sS --max-time 15
"https://api.github.com/search/issues?q=repo:jikig-ai/soleur+is:issue+is:open+label:infra-drift+in:title+%22web-1+workspaces+volume%22"`
(read `total_count`; `0` is healthy).

## Encryption Posture

This plan adds no store and no connection: it reads one metadata flag of an existing store over the job's existing
connection.

```yaml
at_rest:
  - store: hcloud_volume.workspaces_luks (unchanged by this plan)
    mechanism: guest-side LUKS2 (cryptsetup) under ADR-119
    evidence: scripts/encryption-posture-ledger.json row "hcloud_volume.workspaces_luks"; apps/web-platform/infra/workspaces-luks.tf
    defends_against: reading the volume's blocks at the provider without the passphrase
    does_not_defend: a deletion of the volume (what this check's flag guards against accidents), a compromised web-1 host with the volume open
    disclosed_as: ADR-119 and its ledger row
    live_verification: unchanged by this plan; the ledger row's own verification stands
in_transit:
  - connection: GitHub-hosted runner to api.hetzner.cloud (existing, GET only)
    tls: HTTPS through scripts/lib/bearer-curl.sh (no insecure flag; the suite's curl stub refuses any argv it does not model)
    cert_verification: on
    does_not_defend: a compromised runner or a planted read-only token in another project (the id pin turns that into volume-not-found, never clean)
    disclosed_as: ADR-282 addendum of 2026-10-16 and the ADR-119 addendum of 2026-11-10
```

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-119 by appending `## Addendum — 2026-11-10 (#10432, recurring delete-protection check for the volume)`
(Phase 3.1). This extends ADR-282's recurring check to ADR-119's volume; no new ADR (CTO ruling 2). ADR-282 gets one
appended note recording that the probe's pin literal moved into the `inngest` row (its 2026-10-24 addendum's literal
count changes from three to two); its decision is unchanged.

### C4 views

No C4 change. All three model files were read for this plan
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Checked against them: the external
system (Hetzner Cloud API) is modeled, and the `github -> hetzner` edge already names "drift and apply workflows" as
read callers; the store (web-1 workspaces volume) is modeled and its description already records `delete_protection`
and its delivery by the SSH-stage apply; the email recipient path is the existing notify edge; no actor-to-surface
access relationship changes. No cardinality in edge prose counts this job's legs. `bash
plugins/soleur/test/c4-count-parity.test.sh` was green at plan time (`ALL TESTS PASSED`) and is re-run in Phase 4.

### Sequencing

None: the addendum is true on merge (the check runs from the first scheduled run).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6.
- The Inngest strings must be COPIED from the current file, never retyped: a one-character difference in a title
  orphans an open issue from its dedupe and from the clear step.
- `fail-fast` absent means `true`. The shape check must treat absent as a violation, not only an explicit `true`.
- An include-only matrix creates one job per row, and GitHub appends every row value to the job's display name unless
  `name:` is set; set it to the `entry` form.
- Both ids are plain literals in the suite (`VOL_ID` per entry), so `git grep -n <id>` lists the suite as a pin
  consumer, which runbook 6894's pin-bump list and the ADR-119 addendum's list both expect.
- Do not edit the two sweep copies of `readonly VOLUME_ID_PIN=106903269`; N1b now counts exactly those two.
- `mk_tf` writes into the case workspace; every directory operand goes through the existing `assert_fixture_dir`
  (fixture-dir-operand-assert ratchet). Build any mock body with `printf`, never a here-document inside a quoted string
  (guard-vacuity-floor).
- The ADR-119 addendum is append-only: do not touch the 2026-07-23 text that names `106406962`.
- Close #11163 only after re-running the grep on the then-current `origin/main`.
- Operator-held items are out of scope and must not be touched, drafted or attested: A6 signing; the Hetzner console
  check and support question; the off-project copy decision; authorizing or dispatching `apply_target=inngest-host-replace`
  (window 2026-11-24); closing #9927, #12158 or #11265; `doppler_service_token.inngest_arm_write` and its `.tf`; the G2e
  pin; unpausing the Better Stack dead-man heartbeat. Technical holds (flip-token design, the `ci-head-verdict.sh` gap,
  the item-7 note) stay held. Not ours: the `CI_ORACLE_LANE` variable, the SOLEUR-DEBT marker in `ci.yml`,
  `scripts/ci-pr-affected-audit.accept.tsv`. Operator notes go on #12272 only; no new action-required issue.

## Non-Goals

- A Sentry check-in for this job (#10430; held while #6590 is open).
- A shared pinned Doppler install step (#10431).
- Any change to the drift-check matrix, the sweeps, or the per-merge apply.
- Re-protecting, lifting or otherwise changing any Hetzner flag.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add the web-1 workspaces_luks delete-protection check to the sole-copy-protection-check job" [brief] | Design: the `web1` include row and step changes | mapped |
| 2 | "A second table entry (resource name, Hetzner id pin, expected flag derived from the `.tf`) in the same job, reusing the verdict taxonomy, the 90-minute grace, the id pin and the could-not-perform filer." [issue #10432] | Design table; Phase 2 | mapped |
| 3 | "Extend the executed suite with the second entry, including a case proving the two entries never query each other's id." [issue #10432] | Suite structure; W rows; the per-case request invariant plus V8/WV8 (C1 and C2 deleted, CTO ruling 23) | mapped |
| 4 | "Keep it read-only with the same `HCLOUD_TOKEN_READONLY` read and no fallback; no new credential." [issue #10432] | Design (probe unchanged); H9; shape `rw-token-*` | mapped |
| 5 | "State the web-1 coverage in ADR-119 or ADR-282 as an append-only addendum." [issue #10432] | Phase 3.1 (ADR-119 addendum) | mapped |
| 6 | "A lifted flag on the web-1 volume produces its own issue within one drift cycle." [issue #10432] | AC1; WV2, WF1 | mapped |
| 7 | "Existing Inngest-volume verdicts are unchanged and their suite rows stay green." [issue #10432] | AC2 | mapped |
| 8 | "Also close #11163 with an evidence comment" [brief] | Phase 6 | mapped |
| 9 | "Extend plugins/soleur/test/lib/gha-expr.py with a `matrix` context that fails on an unknown key." [brief] | Guard 2: `check()` in the harness refuses an unknown `matrix` key; `gha-expr.py` unchanged from `main` (CTO ruling 21 amends ruling 1) | mapped |
| 10 | "Pin web-1 at volume id 106443278 ... The suite checks the workflow pin against a new ADR-119 addendum; that addendum also corrects ADR-119's stale id 106406962" [brief] | Phase 3.1; N1c; Guard 3 | mapped |
| 11 | "Web-1 titles replace \"Inngest store volume\" with \"web-1 workspaces volume\"; same labels, p1-high." [brief] | Design (titles); WF1 | mapped |
| 12 | "keep the \"tracked: #10430\" comment" [brief] | Design (job comment block) | mapped |
| 13 | "raise its count floor from 195" [brief] | Suite structure (Counting); AC5 | mapped |
| 14 | "(c) cross-entry case proves neither entry requests the other's id" [brief] | the per-case request invariant plus V8/WV8 (C1 and C2 deleted, CTO ruling 23) | mapped |
| 15 | "(d) issue body stays public-safe incl. 106443278" [brief] | invariants issues.json ban; WF12; F13 extension | mapped |
| 16 | "(f) post-merge, a workflow_dispatch of scheduled-terraform-drift.yml (read-only) or the first scheduled run on main reads matches-declared for both entries." [brief] | Phase 5; AC8 | mapped |
| 17 | "have the plan include that table for this change's arms" [brief] | Arm x loosening table | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Matrix job, `fail-fast: false` | "One job with strategy.matrix ... fail-fast: false" | asked |
| `case "$ENTRY"` per-entry prose | — | inferred — justification: CTO Fork 1 ruling; Inngest strings must stay byte-identical (ruling 3) |
| Entry-neutral step names, job `name:` with entry, R3b literal | "possibly plugins/soleur/test/token-drift-workflow-causes.test.sh if it keys on the job name" | asked (CTO Fork 3 ruled the rename) |
| `scripts/lib/test-affected-paths.sh` additions | — | inferred — justification: the suite now reads `workspaces-luks.tf`, ADR-119 and runbook 6604; without the edge an edit to them would not select the suite under the affected gate |
| Row-value patterns in `matrix-shape` (pre-merge, no runtime branch) | "Each entry: own name lookup, id pin, expected flag read from its own .tf" | inferred — justification: a matrix value reaches a shell variable that builds a URL and an awk pattern; the pre-merge shape check is the one place that rejects a malformed row |
| Runbook 6604 read-only read-back subsection | — | inferred — justification: the web-1 issue body points readers there every 12 hours; it must use the read-only token like the Inngest leg's 5c read-back (CTO plan-review finding, row 12) |
| N1b rewrite | "The suite checks the workflow pin against a new ADR-119 addendum" | inferred — justification: the Inngest pin moves from a probe literal to its row, so N1b's exact count of three literals becomes two plus the row |
| Ratchet runs, mutation proofs on copies | "plan to run repo-global ratchets (fixture-dir-operand-assert, fixture-relative-assert, guard-vacuity-floor)" | asked |

### Split Assessment

- Subsystems touched: 4 — `.github/`, `plugins/soleur/test/`, `knowledge-base/engineering/`, `scripts/lib/`
- Planned files: 10 | Estimated changed lines: about 570
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the four roots are one change's workflow, its executed suite, the ADR text that suite
  reads as the pin anchor, and the test-selection edge for those reads; any split merges a red suite (the suite reads
  the workflow's rows and the addendum) or a workflow change its guard has not seen.

## Acceptance Criteria

### Pre-merge (PR)

- AC1 (a): with the web-1 row live `false`, declared `true`, and `workspaces-luks.tf` last committed 3 hours ago, the
  web-1 leg files exactly one issue titled `infra: web-1 workspaces volume delete protection differs from Terraform
  (soleur-web-platform-data-luks)` with labels `action-required`, `infra-drift`, `priority/p1-high` and milestone
  `Post-MVP / Later`, sends the email, and its gate exits 1 (WV2, WF1).
- AC2 (b): every pre-existing suite row passes with its expected strings unchanged (the Inngest `TITLE_*` constants
  move verbatim into `use_entry inngest`, checked by the Phase 4.8 second-half diff; `want_out` keys and F/X text assertions are not edited; the one edited existing row is N3's `file_unreadable`
  check, which moves from the literal `ADR-282` to `Decision record: ${ADR}.`), F1 asserts the Inngest body's
  decision line equals today's sentence (`Decision record: ADR-282. Loss modes and the reviewed route: ...`), spelled
  out in full in the suite, and the Phase 4.8 byte-identity check prints nothing
  beyond its two listed exceptions.
- AC3 (c): the per-case request invariant plus V8/WV8: no request of a leg carries the other leg's name, and a
  same-name volume carrying the other leg's id is `volume-not-found reason=id-mismatch` for each leg. (C1 and C2, which
  restated these, are deleted by CTO ruling 23.)
- AC4 (d): no rendered issue title, body or comment in any case contains `106443278` or `106903269`, and `recipe_vocab`
  flags an injected `106443278` (F13 extension).
- AC5 (e): the suite's realized count equals the new `FLOOR` (above 195), `TABLE_ROWS` equals the executed rows (H3),
  the harness rows H1-H7, H11 and H12 pass, table rows H1-H10 are unchanged, and deleting one new row block on a copy fails the outer count.
- AC6: H11d (row selection: zero or two rows matching the entry is exit 3); the mutation proofs of Phase 4.2 each turn
  the named row RED; results are listed in `mutation-proofs.md`, and the PR body carries them. (The swapped-order copy,
  C8, is deleted by CTO ruling 23.)
- AC7: `token-drift-workflow-causes.test.sh`, the ratchets of Phase 4.5, and every test-file hit of the Phase 4.6
  census pass (the named list there is a floor); `lint-guard-contract.py` passes on this plan.
- AC9: the PR body carries `Closes #10432` and `Ref #9927` (never `Closes #9927`).
- AC10: no `.tf`, cloud-init or user_data file is in the diff (`git diff --name-only origin/main...HEAD` lists none).
- AC11: in runbook 6604's "Verify the retired end state" block
  (`sed -n '/Verify the retired end state/,/^   > /p' knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`),
  every `doppler run` line carries `--only-secrets HCLOUD_TOKEN_READONLY` (four lines) and `curl -sS --config -`, and
  the block carries no Authorization header on argv in any spelling (H15) and no `HCLOUD_TOKEN` not followed by `_READONLY`
  (`grep -cE 'HCLOUD_TOKEN([^_]|$)'` over the command lines prints `0`). The new "Read back the delete-protection flag
  (read-only token)" subsection's command line passes the same checks and names `v1/volumes/106443278`; N1c and N3
  are green.

### After merge (automated: Phase 5 / ship Phase 6)

- AC8 (f): the first run on `main` (scheduled or `workflow_dispatch`) shows `sole-copy-check verdict=matches-declared`
  and the gate's `(clean)` line in both `sole-copy-protection-check (inngest)` and `sole-copy-protection-check (web1)`.
- AC12: #11163 is closed with the evidence comment (grep re-run on the then-current `origin/main`); #9927 stays open.

## Test Scenarios

Review round 1 (CTO rulings 21-23) changes the list below: WV3b, WT1, WF3, WX7, C1, C2, C8, H11a and H13 are deleted, the
selected-entry invariant is deleted, C4 and C5 become one row that seeds all six titles of the other leg (and takes WF3's
"one cleared comment" check), and H11b/H11c run against `gha-expr.py` itself, which stays as on `main`. C9 is kept.
Ruling 23 names the rows that cover each deleted one.

Web-1 table (`use_entry web1`): WV1 matches-declared (clear runs); WV2 lifted-outside-terraform (finding, email, red);
WV3 lift-pending-apply at 5 minutes; WV3b 89/91 minutes on its own file; WV4 unprotected-as-declared; WV5
lift-not-applied; WV6 empty listing (reason zero); WV8 same-name volume with the Inngest id (reason id-mismatch); WT1
a different declared name flows into URL and outputs; WT3 resource renamed; WR1 the REAL `workspaces-luks.tf` against
an independent derivation; WF1 first lifted run (title, labels, milestone, ADR-119 pointer, web-1 remedy, the read-back
subsection's name, email subject and body); WF3 clean run closes; WF12/each of four verdicts (only named dynamic fields, no recipe vocabulary, no id, no "Inngest"); WX5
volume-not-found body (reason pointer, `soleur:incident`); WX7 web-1 `(name-unreadable)` titles cleared; WX9 web-1
could-not-perform bodies name ADR-119; WX16 the `file_finding` catch-all: an unexpected verdict on a known entry and an
unknown entry each print `sole_copy_finding_filer_unexpected_verdict` with the `entry:verdict` pair, file no issue,
send the email and exit 1. Route: both inputs are overrides on `file_finding` alone with the probe still reporting
`lifted-outside-terraform` (`OVR+=("file_finding:VERDICT=bogus")`, separately `OVR+=("file_finding:ENTRY=zzz")`);
assert `file_finding` outcome `failure` with rc 1, exactly one slug line carrying `inngest:bogus` /
`zzz:lifted-outside-terraform`, `issues.json` unchanged, and the email body's `finding filer` failure line (the gate rc
and "email sent" are not evidence here: a lifted verdict produces both anyway). The W rows cover only the arms where a row value changes the outcome (CTO Fork 2); the
shared paths (token read, body parse, awk traps, comment-on-existing, HTTP-500 and crash titles) stay single-run on the
Inngest entry, and their per-entry part, the title, is asserted by C5 and C6.

Cross-entry (every seeded other-entry issue carries `author: "app/github-actions"`, `state: open`,
`labels: ["infra-drift"]`, and in the same row and `SCEN` a clean run of the seed's own entry must then close it, so a
row cannot pass because the fixture fails the clear step's author, label or state filter; C3 writes the other file's
commit 5 minutes old with `set_age_other` in both directions and asserts it was served, since a missing commits answer
also yields "no grace"): C1 request isolation; C2 id isolation; C3 grace isolation (each leg reads its own file's commit time); C4
clear isolation on one shared issue store; C5 `(name-unreadable)` isolation; C6 could-not-perform isolation; C8 rows
in swapped order (must PASS); C9 a cancelled web-1 leg (`__job_status`
cancelled, probe skipped) files only under the web-1 `(name-unreadable)` title and leaves every Inngest title alone;
C10 a web-1 leg whose checkout failed (no `.git` in the case workspace, probe skipped) still files its p2
`(name-unreadable)` issue, with the gh stub requiring `GH_REPO` when no `.git` is present.

Harness: an N1c runbook-side row (the read-back subsection body emptied on a copy, heading kept, must go RED, proving
the subsection bound); a `date` shim on PATH that returns `$FAKE_NOW` for a bare `+%s` and passes `-d` through, used by
V3b and WV3b so the 89/91-minute boundary does not depend on wall-clock drift under host load (expected strings
unchanged); H1 extended (a neutered stub turns WV2, WV6, WV8 RED); H11 matrix negative controls (H11a gha-expr, H11b `check()`,
H11c second member, H11d row selection with zero or two matches); H12 the id ban fires on a planted id in an issue body (one leg; the ban does not depend on the leg).

Shape (S2 additions): `fail-fast` true; `fail-fast` absent; a third row; a missing key; a renamed key; a duplicate
entry; a value outside its pattern (one mutant per key); the job name without the entry; a pin literal in the probe
(an `id-placement` violation); the web-1 id in a comment; the Inngest id in a step.
