---
title: "fix: cla-evidence-timestamp same-month re-dispatch dies on R2 ObjectLockedByBucketPolicy"
type: fix
date: 2026-11-02
slug: fix-cla-evidence-r2-versioned-manifest-key
branch: feat-one-shot-11916-r2-manifest-key
issue: 11916
closes: 11916
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed — the diff renames R2 object keys on an already-provisioned bucket and edits docs; it introduces no server, service, secret, vendor, DNS record, or persistent runtime process, so no Terraform routing applies. Flagged prose describes runbook reads of existing objects, not provisioning. -->

# fix: cla-evidence-timestamp same-month re-dispatch dies on R2 ObjectLockedByBucketPolicy

## Overview

The monthly `cla-evidence-timestamp.yml` workflow uploads its RFC 3161 manifest and `.tsr` reply to fixed object keys (`timestamps/<yyyy-mm>/manifest.jsonl`, `timestamps/<yyyy-mm>/manifest.tsr`) in the `soleur-cla-evidence` R2 bucket, which enforces write-once-read-many retention via a bucket-wide Lock Rule. Once any object lands at those keys, a second dispatch for the same month — including the workflow's own documented `workflow_dispatch` retry path — fails at the upload step with `ObjectLockedByBucketPolicy`. The fix versions the object key per workflow run attempt so every dispatch writes to a fresh, never-before-written key, preserving the WORM property while making same-month re-dispatch safe. Retrieval documentation is updated so consumers fetch the latest object under the month prefix rather than fixed filenames, and the two legal-disclosure copies that assert the fixed filename are reconciled in lockstep.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed); no spec.md exists on this branch yet.

## Problem Statement / Motivation

Issue #11916 (verified OPEN 2026-11-02): post-merge dispatch run 41532801944, verifying the #3926 fixes, died at `Upload manifest + .tsr to R2` with `ObjectLockedByBucketPolicy` on `timestamps/2026-11/manifest.jsonl`. The November cron had already written that key, and the bucket's R2 Lock Rule (10-year retention floor, `apps/cla-evidence/infra/object_lock.tf`) makes every object immutable. The result: the workflow's own retry recipe — `workflow_dispatch` with `manifest_yyyy_mm` — is structurally unable to go green inside a month that already produced an upload, even after a partial first upload. The tracking-issue machinery (Kieran F9) then files/escalates failures that no retry can resolve.

## Proposed Solution

Ruled in-session at go routing (2026-11-02), recorded in `knowledge-base/project/specs/feat-one-shot-11916-r2-manifest-key/decision-challenges.md`: version the R2 object key per run. Rejected alternative: relaxing the R2 Lock Rule on the `timestamps/` prefix — operator-class decision and it weakens the tamper-evidence control the Art. 30 register relies on.

Change the upload step's destination keys from `timestamps/${YYYY_MM}/manifest.jsonl` and `timestamps/${YYYY_MM}/manifest.tsr` to `timestamps/${YYYY_MM}/manifest-${RUN_ID}-${RUN_ATTEMPT}.jsonl` and `timestamps/${YYYY_MM}/manifest-${RUN_ID}-${RUN_ATTEMPT}.tsr`. `RUN_ID` is already exported at job env (`RUN_ID: ${{ github.run_id }}`); add `RUN_ATTEMPT: ${{ github.run_attempt }}` beside it. The run-attempt segment is required because GitHub's re-run-failed-jobs / re-run-all paths reuse the same `run_id` with an incremented `run_attempt` — a `run_id`-only key would re-collide with the locked object a failed attempt already wrote (plan-time ruling, same table).

The git paper-trail on the `cla-signatures` branch stays month-keyed (`timestamps/<yyyy-mm>/manifest.jsonl` + `manifest.tsr` remain canonical latest; full history lives in git) — the "Persist via PR-with-auto-merge" step is unchanged except its stale comment claiming the R2 PUT "overwrites".

Every retrieval recipe switches from fixed filenames to "latest object under `timestamps/<yyyy-mm>/`", which is backward-compatible: months that only have the legacy `manifest.jsonl`/`manifest.tsr` pair still resolve, and months with multiple versioned objects resolve to the newest by `LastModified`.

## Technical Considerations

- **Retrieval ordering.** GitHub `run_id`s are variable-width decimal strings, so lexicographic key sort is NOT a safe ordering across digit-boundary crossings. Recipes sort by `LastModified` via `list-objects-v2` and fetch the `.tsr` sibling carrying the identical `<run_id>-<attempt>` suffix — the manifest/`.tsr` pair must be same-run or `openssl ts -verify` fails.
- **Audit invariant preserved.** Learning `2026-05-04-cla-evidence-sidecar-pattern.md` §8 notes an auditor verifies the YYYY-MM matches the upload key. The YYYY-MM stays in the key's directory portion, so the invariant survives verbatim (a learning is a point-in-time record — not edited).
- **No renumbering of evidence.** Objects already locked under legacy fixed names stay; they are older `LastModified` and lose "latest" selection naturally.
- **DPD mirror lockstep.** `docs/legal/data-protection-disclosure.md` and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` both assert `timestamps/<yyyy-mm>/manifest.tsr` verbatim (§2.3(n)); `scripts/lint-legal-mirror-drift-baseline.sh`/`legal-normalise.sh` require the pair to move together.
- **Article 30 register needs no edit.** Its TOM cell (PA row for the CLA archive) describes "the monthly `timestamps/<yyyy-mm>/` objects … written unconditionally and sealed by the Lock Rule" — true at prefix granularity before and after; the args' reconcile-only-if-fixed-names condition does not fire.
- **Partial-upload safety.** A first run that wrote only `manifest-<id>.jsonl` before dying leaves a half-pair under the prefix; "latest by LastModified" recipes select the newest `.jsonl` and require its same-suffix `.tsr` to exist, else the run is documented as incomplete and the previous pair is read instead — the runbook states this explicitly.
- **No new guard, store, connection, ADR, or autonomous task.** Existing substrate and trust boundaries are unchanged; no `*.tf`, no new workflow file, no schema change. Encryption posture, Task Design, Guard Contract, and ADR/C4 gates all skip on their own detection rules.
- **Merge does not mutate production.** The diff touches `.github/workflows/` (no push-triggered apply reaches it — apply workflows are `paths:`-filtered to `infra/`) plus docs; the change takes effect on the next dispatch/cron only.

## Research Insights

**Premise Validation.** Issue #11916 is OPEN (state verified via `gh issue view`, no closing PR). All three cited paths exist on `origin/main`: `.github/workflows/cla-evidence-timestamp.yml`, the retrieval runbook, `article-30-register.md`. `RUN_ID` is confirmed already defined at job env (workflow line ~53). Collision precheck flagged PR #11924 — it is this pipeline's own draft PR on this same head branch, not a foreign duplicate; reported and proceeded. ADR-corpus grep for `manifest.tsr`/`manifest.jsonl`/`timestamps/` returns zero — no ADR asserts the fixed key scheme, so no ADR reversal/amendment is owed.

**Property List.** (1) A same-month re-dispatch succeeds after a prior upload exists — retry path produces green. (2) WORM/no-overwrite retention preserved — no Lock Rule relaxation. (3) Retrieval consumers (runbook §6 notarized export, §7.7 tombstone confirm) still fetch the latest monthly manifest+`.tsr` pair, backward-compatible with legacy fixed names. (4) Git paper-trail month-keying preserved on `cla-signatures`.

**Cut List.** (a) Lock Rule relaxation on `timestamps/` — rejected at routing (operator-class; weakens tamper-evidence). (b) Conditional-PUT on the timestamp write — buys nothing; versioned keys make collision impossible by construction. (c) Skip-if-exists check — rejected: masks partial-upload gaps (a `.jsonl`-only month would never get its `.tsr`).

**Files (all verified on `origin/main`).** `.github/workflows/cla-evidence-timestamp.yml` (upload step ~lines 218-233; job env ~51-54; git-persist step ~242-298, incl. the stale "PUT overwrites" comment ~267; PR-body verify snippet ~290). `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` (§6 lines ~154-165 fixed-name fetch; §7.7 ~359-367). `docs/legal/data-protection-disclosure.md:202` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md:211` (§2.3(n) fixed-name assertion). `apps/cla-evidence/scripts/timestamp.test.sh` (fixture verify-replay; unaffected — tests openssl semantics, not key naming). `inspect-evidence.sh`, `object_lock.tf`, `main.test.sh` — grep-confirmed no `timestamps/`/`manifest` key references. No other workflow references `timestamps/`.

**Learnings applied.** `2026-05-04-cla-evidence-sidecar-pattern.md` §8 (YYYY-MM audit invariant — preserved via the directory portion). `2026-05-22-dpa-template-pre-draft-and-cross-document-disclosure-drift.md` (legal-doc mirror edits must move in lockstep; keep customer-facing prose minimal).

**Related.** #11916 (this fix), #3926 (parent defect batch — verified fixed by the failing run itself), PR #11924 (this branch's draft PR), run 41532801944.

**Conventions.** Workflow `run:` blocks set `set -euo pipefail`; step outputs route via `env:`; commit/PR messages carry no CI-skip token; heredoc-into-file pattern for multi-line strings.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality | Plan response |
|---|---|---|
| Issue proposes `manifest-<run_id>.jsonl` | `github.run_id` is constant across re-run attempts of the same run | Key becomes `manifest-<run_id>-<run_attempt>` — inside the ruled versioned-key shape; recorded as a decision-challenges row |
| Workflow comment: "The R2 upload above is idempotent in practice (PUT overwrites)" (~:267) | False under the Lock Rule — the exact defect | Comment corrected in the same diff |
| Args scope: runbook + article-30 register | Register asserts no fixed names, but the two DPD copies do | Fold both DPD copies in as same-class stale-key reconciliation (decision-challenges taste row) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a continued dead retry path — the Kieran F9 tracking issue keeps escalating a failure no dispatch can fix; or an ops/CLO reader following the runbook during a live DMCA/IP-dispute incident retrieves a stale or mismatched manifest/`.tsr` pair that fails `openssl ts -verify` mid-incident.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — object contents, bucket, retention, and credential scopes are unchanged; the key rename adds a public `run_id`/`run_attempt` integer to object names (already public in run URLs on the public repo).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the evidentiary chain's canonical latest copy lives in git on `cla-signatures`, so a single botched R2 retrieval is recoverable; the risk is a repeated pattern of stale/incoherent fetches eroding trust in the Art. 30 register's timestamp chain — recorded as a taste row in decision-challenges.

## Observability

```yaml
liveness_signal:
  what: Monthly GitHub Actions run `cla-evidence-timestamp` — green conclusion means the manifest + .tsr pair landed under timestamps/<yyyy-mm>/
  cadence: monthly cron '0 6 1 * *' UTC plus on-demand workflow_dispatch retries
  alert_target: auto-filed tracking issue labelled cla-evidence,timestamp-failure, escalating to action-required after 7 days (Kieran F9 arm)
  configured_in: .github/workflows/cla-evidence-timestamp.yml (on.schedule; failure() step)
error_reporting:
  destination: GitHub Actions run failure + the auto-filed tracking issue (issues: write permission already held)
  fail_loud: PutObject error fails the Upload step → job red → failure() arm files or updates the monthly issue; a red run nobody watches is the exact failure class the arm exists for
failure_modes:
  - mode: PutObject rejected (object lock collision, expired R2 token, endpoint drift)
    detection: workflow run conclusion=failure on the Upload step, surfaced by the Kieran F9 issue arm
    alert_route: GitHub issue labels cla-evidence + timestamp-failure, action-required at ≥7 days
  - mode: retrieval fetches a stale or suffix-mismatched pair
    detection: openssl ts -verify fails against a mismatched .tsr; runbook recipe requires the identical <run_id>-<attempt> suffix on both objects
    alert_route: incident responder during evidence retrieval (runbook-driven)
logs:
  where: GitHub Actions run logs — gh run view <id> --log
  retention: GitHub default run-log retention (~90 days)
discoverability_test:
  command: curl -s "https://api.github.com/repos/jikig-ai/soleur/actions/workflows/cla-evidence-timestamp.yml/runs?per_page=1"
  expected_output: workflow_runs
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Version the key per-run: `timestamps/YYYY-MM/manifest-<run_id>.jsonl` (keeps WORM, makes re-dispatch safe; consumers must read the latest key)" [issue #11916] | FR-1 / Phase 1 / `.github/workflows/cla-evidence-timestamp.yml` | mapped |
| 2 | "update knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md to fetch the LATEST object under timestamps/<yyyy-mm>/ rather than fixed manifest.jsonl/manifest.tsr names" [args] | FR-2 / Phase 2 / runbook §6 + §7.7 edits | mapped |
| 3 | "reconcile knowledge-base/legal/article-30-register.md wording only if it asserts fixed monthly key names" [args] | verified — register asserts no fixed names; no edit (grep evidence in Research Insights) | mapped |
| 4 | "Git paper-trail on the cla-signatures branch stays month-keyed (canonical latest; full history in git)" [args] | FR-3 — git-persist step unchanged except stale comment fix | mapped |
| 5 | "Post-merge verification: gh workflow run cla-evidence-timestamp.yml with manifest_yyyy_mm=2026-11 and confirm the PutObject lands at the run-id-versioned key" [args] | AC Post-merge block / Phase 4 | mapped |
| 6 | "Or an operator decision on the retention policy for this prefix (allow-replace on the monthly key)" [issue #11916] | — | descoped — justification: ruled at go routing; operator-class and weakens the tamper-evidence control the Art. 30 register relies on |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Edit `.github/workflows/cla-evidence-timestamp.yml` (versioned keys + RUN_ATTEMPT env + comment fixes) | "Version the key per-run" | asked |
| Edit `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` | "update knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md to fetch the LATEST object" | asked |
| Edit `docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | — | inferred — justification: both assert `timestamps/<yyyy-mm>/manifest.tsr` verbatim, the same stale-fixed-name class the args' reconcile directive covers; a falsified legal disclosure must not ship |
| `RUN_ATTEMPT` key segment | — | inferred — justification: GitHub re-runs reuse `run_id`; without the attempt segment the retry path the fix exists to save can re-collide on the key it just locked |
| Post-merge live dispatch verification | "gh workflow run cla-evidence-timestamp.yml with manifest_yyyy_mm=2026-11" | asked |

### Split Assessment

- Subsystems touched: 4 — `.github`, `knowledge-base`, `docs`, `plugins`
- Planned files: 5 | Estimated changed lines: ~80
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the 4-root count is a mechanical false positive: the `plugins/` file is the byte-mirror of the `docs/` file (legal-mirror lint requires lockstep, so splitting it reds the lint), and the real change is ~10 lines of workflow + doc reconciliation

## Files to Edit

- `.github/workflows/cla-evidence-timestamp.yml` — upload step keys → `manifest-${RUN_ID}-${RUN_ATTEMPT}.{jsonl,tsr}`; add `RUN_ATTEMPT: ${{ github.run_attempt }}` to job env beside `RUN_ID`; correct the stale "PUT overwrites" comment in the persist step; touch the upload-step comment so it documents the versioned-key contract.
- `knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` — §6 step 4: replace the two fixed-name `s3 cp` fetches with a list-and-select-latest recipe (sort `list-objects-v2` by `LastModified`, take newest `manifest-*.jsonl`, fetch the same-suffix `.tsr`); §7.7: same recipe for the tombstone-presence check, including the partial-pair caveat (`.jsonl` present without its same-suffix `.tsr` means the latest run is incomplete — read the previous pair instead).
- `docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — §2.3(n): `timestamps/<yyyy-mm>/manifest.tsr` → run-id-versioned wording (e.g., "at `timestamps/<yyyy-mm>/` under a per-run key"), minimal and identical in both copies.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-11916-r2-manifest-key/tasks.md` (this pipeline artifact)

(Plus pipeline artifacts already written this session: `decision-challenges.md`, `specs/<branch>/` dir. No product-code file is created.)

## Implementation Phases

1. **Workflow.** Edit the env block and upload step in `.github/workflows/cla-evidence-timestamp.yml`; fix the stale idempotency comment; leave the git-persist step's fixed filenames untouched.
2. **Runbook.** Rewrite the two retrieval recipes to latest-under-prefix selection with the suffix-pairing and partial-pair rules.
3. **Legal disclosures.** Apply the identical minimal §2.3(n) key-wording reconciliation to both DPD copies.
4. **Verify.** `actionlint` on the workflow; no new `run:` shell logic is introduced so `bash -n` extraction is N/A — instead assert the `env:` wiring and key strings via grep; markdownlint the touched docs; run the plan's AC greps. Post-merge (automatable, `gh` CLI): dispatch the workflow for `manifest_yyyy_mm=2026-11` and read back the run log for a `manifest-<digits>-<digits>.jsonl` PutObject.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — The workflow's two `s3 cp` destination lines name `manifest-${RUN_ID}-${RUN_ATTEMPT}.jsonl` and `manifest-${RUN_ID}-${RUN_ATTEMPT}.tsr` under `timestamps/${YYYY_MM}/`; `RUN_ATTEMPT: ${{ github.run_attempt }}` is exported at job env. Verify: `grep -n 'manifest-\${RUN_ID}-\${RUN_ATTEMPT}' .github/workflows/cla-evidence-timestamp.yml` returns 2 hits and `grep -n 'RUN_ATTEMPT' .github/workflows/cla-evidence-timestamp.yml` returns ≥2.
- [ ] AC2 — No `s3 cp` line in the workflow still targets the fixed `manifest.jsonl`/`manifest.tsr` R2 keys. Verify: `grep -nE 's3 cp .*(manifest\.jsonl|manifest\.tsr)' .github/workflows/cla-evidence-timestamp.yml` returns 0 (scoped to `s3 cp` lines because git `cp`/`git add` lines legitimately keep the fixed names).
- [ ] AC3 — The git paper-trail still writes `timestamps/${YYYY_MM}/manifest.jsonl` + `manifest.tsr` to `cla-signatures`. Verify: `grep -n 'timestamps/\${YYYY_MM}/manifest' .github/workflows/cla-evidence-timestamp.yml` still returns the persist-step `cp`/`git add` lines.
- [ ] AC4 — The stale "PUT overwrites"/"idempotent" comment is gone or corrected. Verify: `grep -in 'overwrites\|idempotent' .github/workflows/cla-evidence-timestamp.yml` returns no stale claim (any retained text must describe the locked, never-overwrite contract).
- [ ] AC5 — Runbook contains no remaining fixed-name `timestamps/.../manifest.jsonl` or `manifest.tsr` fetch recipe; §6 and §7.7 both instruct latest-by-`LastModified` selection with identical suffix pairing. Verify: `grep -nE 'timestamps/.*/manifest\.(jsonl|tsr)' knowledge-base/engineering/operations/runbooks/cla-signature-evidence-retrieval.md` returns 0.
- [ ] AC6 — Both DPD copies carry the versioned-key wording and remain mirror-consistent. Verify: `grep -c 'manifest.tsr' docs/legal/data-protection-disclosure.md` and the same on the plugin copy each return 0, and `bash scripts/lint-legal-mirror-drift-baseline.sh` (or its normalise diff) shows no new drift.
- [ ] AC7 — `actionlint .github/workflows/cla-evidence-timestamp.yml` exits 0.
- [ ] AC8 — `knowledge-base/legal/article-30-register.md` is untouched by the diff (`git diff --quiet origin/main...HEAD -- knowledge-base/legal/article-30-register.md` exits 0) — its prefix-level wording stays true.

### Post-merge (automated — `gh` CLI via Bash, no operator-only step)

- [ ] AC9 — Dispatch `gh workflow run cla-evidence-timestamp.yml -f manifest_yyyy_mm=2026-11` (flag form verified against `gh workflow run --help`, 2026-11-02), wait for the run, then `gh run view <id> --log` shows the upload step writing `timestamps/2026-11/manifest-<run_id>-<attempt>.jsonl` and the matching `.tsr` — and the run concludes `success` despite the pre-existing locked `manifest.jsonl`. Then `gh issue close 11916` (or confirm `Closes #11916` in the PR body already closed it) with the run URL noted.

## Domain Review

**Domains relevant:** Legal, Engineering

### Legal

**Status:** reviewed (inline — no subagent capacity in this harness)
**Assessment:** The diff reconciles two copies of a public legal disclosure (DPD §2.3(n)) whose fixed-key assertion becomes factually wrong at merge; the article-30 register needs no edit (prefix-level claims stay true). The WORM floor, retention, lawful basis (Art. 6(1)(f)), sub-processor list, and erasure path are all unchanged — the disclosure edit is a factual key-name correction, not a posture change. No CLO-blocking concern surfaced; the legal-doc edit stays minimal and identical across the mirror pair per the drift lint.

### Engineering

**Status:** reviewed (inline — no subagent capacity)
**Assessment:** Narrow key rename on an existing substrate; the only correctness traps are `run_id` reuse across re-run attempts (handled via `run_attempt`) and retrieval ordering across variable-width run ids (handled via `LastModified` sort). No architecture change; no IaC; no new secrets — the existing `prd_cla` Doppler token's `timestamps/` put scope is unchanged.

**Brainstorm-recommended specialists:** none (no brainstorm ran).

### Product/UX Gate

Not applicable — mechanical UI-surface scan over Files to Edit/Create returns no UI-surface path; Product domain assessed NONE. **Pencil available:** N/A (no UI surface).

## GDPR Gate (Phase 2.7 — inline advisory)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Canonical-regex surfaces: none touched (no migration/auth/API/`.sql`). Expansion triggers (a)–(d): none fire — no new processing activity, no new cron reading learnings/specs, no new distribution surface, threshold is `aggregate pattern`. Inline check: the change renames object keys; manifest content, retention, erasure (tombstone) path, and data egress (SHA-256 digest only to FreeTSA) are unchanged; the DPD edit is a factual reconciliation. No Critical/Important findings.

## Open Code-Review Overlap

None — open `code-review`-labelled issues were queried (`gh issue list --label code-review --state open`) and no issue body names any file in `## Files to Edit`.

## Test Scenarios

- Given a month whose `timestamps/<yyyy-mm>/` prefix already holds a locked `manifest-<old>.jsonl` pair, when `cla-evidence-timestamp` is re-dispatched for that month, then the upload succeeds at the new `manifest-<run_id>-<attempt>` keys and the job goes green (`integration` — the post-merge live dispatch, AC9).
- Given a bucket prefix holding only the legacy fixed `manifest.jsonl`/`manifest.tsr`, when the runbook's latest-selection recipe is followed, then the recipe resolves the legacy pair (backward compatibility) (`unit`-level recipe correctness — reviewed statically).
- Given a partial upload (`manifest-<id>.jsonl` present, no same-suffix `.tsr`), when the recipe runs, then it selects the newest complete pair, not the incomplete latest object (`unit` — recipe logic).
- Given `openssl ts -verify` on a suffix-mismatched pair, when the `.tsr` belongs to a different run's manifest, then verification fails — which is why the recipe mandates identical suffixes (`unit` — already covered conceptually by `timestamp.test.sh` TS17.c tamper arm).
- Regression: the exact #11916 failure mode — PutObject to an already-written key — is covered by AC9's live re-dispatch over the locked `timestamps/2026-11/manifest.jsonl`.

## Success Metrics

- A second `workflow_dispatch` for `2026-11` completes `success` where run 41532801944 could not.
- The Kieran F9 tracking-issue arm stops re-filing for the lock-collision class.
- Runbook retrieval recipes resolve the latest monthly pair for both legacy and versioned key shapes.

## Dependencies & Risks

- **Risk: ordering ambiguity in "latest".** Mitigated by `LastModified` sort + same-suffix pairing rule written into the runbook.
- **Risk: a reader still assumes `manifest.jsonl`.** Grepped — no code consumer references `timestamps/` outside the runbook and the two DPD copies; `inspect-evidence.sh`, `gdpr-override.sh`, `main.test.sh`, `object_lock.tf` are clean.
- **Risk: run_id-only key re-collision on re-run of failed jobs.** Mitigated by the `run_attempt` segment.
- **Dependency:** none — no new secrets, tokens, or infra. The `prd_cla` R2 token already holds put on `timestamps/`.
- **Rollback:** revert this PR; the versioned objects already written are orphaned but harmless (older `LastModified`, unpicked by latest-selection, still sealed by the Lock Rule — they cannot be deleted, which is the property's point).

## References & Research

- Issue: `gh issue view 11916` (OPEN; body contains the failing PutObject log verbatim).
- Workflow: `.github/workflows/cla-evidence-timestamp.yml` upload step (~:218-233), job env (~:51-54), persist step (~:242-298).
- Design record: `knowledge-base/project/specs/feat-one-shot-11916-r2-manifest-key/decision-challenges.md`.
- Evidence-layer plan of record (archived): `knowledge-base/project/plans/archive/20261013-014038-2026-05-04-feat-cla-legal-rigor-evidence-layer-plan.md`; learning `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` §8.
- CLI tokens verified locally 2026-11-02: `gh workflow run -f <key=value>` (via `--help`); `gh run view --log`; `actionlint` on PATH; discoverability probe run once — returns `workflow_runs` unauthenticated.
