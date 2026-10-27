---
title: "git-data: record PR after the plaintext-volume destroy (delete the one-shot workflow, retire the ledger row, attest the ADR amendment)"
date: 2026-10-27
slug: git-data-plaintext-volume-destroy-record
branch: feat-one-shot-11195-plaintext-volume-destroy-record
issue: 11195
lane: cross-domain
type: chore
closes: none (Ref #11195, Ref #8211, Ref #6897, Ref #11194 - the DPD section 10.3(b) refresh stays open)
---

# git-data: record PR after the plaintext-volume destroy

## Enhancement Summary

**Deepened on:** 2026-10-27
**Method:** direct evidence-first verification; no further agent fan-out (the caller capped the planning session at two spawns: one CTO ruling agent, one report-only plan reviewer). Sections enhanced: Research Reconciliation, Scope Check, Observability, Encryption Posture, Open Code-Review Overlap.

### Key improvements
1. The brief's `BASELINE_DECLARED_PROBES 84 -> 83` was falsified against the tree (constant is 85; the declaring plan is archived and stays), so the plan keeps 85 with a dated comment instead of breaking `G1`.
2. Whole-file restores (`git checkout edade6cb3e^ --`) are proven byte-exact for six files (no later commit) and replaced by hunk reversals for the three files later commits touched.
3. The ledger-row retirement is gated on the CLO attestation (Branch A / B), with `expires_on` unmoved in both branches.
4. A falsified architecture-record sentence the brief did not list (`model.c4` gitDataStore) was found and added.

### New considerations discovered
- The destroy run's log is the only durable copy of the read-back until the ADR section carries it.
- ADR-239 item 7 binds the DPD refresh to this issue (2026-11-03 target, 2026-11-11 bound); the brief excludes `docs/legal/**`, so the issue must stay open (`Ref`, not `Closes`).
- Any file under `apps/web-platform/infra/**` fires the per-merge apply on main; the expected plan is empty.

## Overview

The retired plaintext git-data volume (id 106867358, name `soleur-git-data-store`) was deleted at the provider on 2026-10-27 by run [40478209838](https://github.com/jikig-ai/soleur/actions/runs/40478209838) of the one-shot destroy workflow that PR #11179 (merge commit `edade6cb3e`) added. This change is the closing record. It removes the one-shot artifacts and reverses every counter and registry entry they moved, retires the encryption-posture ledger row for the device (gated on the CLO attesting), brings the prose that #11179 wrote into line with what happened, and appends the read-back evidence to the decision records. Nothing is dispatched, applied or written to production, and the git-data host replace/rotate/create routes stay disabled until #11194.

Measured run facts (read from the public run log on 2026-10-27, counts and identifiers only; the log is the only durable copy, default retention is finite, so the records must carry them):

| Step | Result |
|---|---|
| run | `workflow_dispatch` on `main`, head `2e9874cdf6`, created 2026-10-27T09:05:55Z, concluded `success` (validate 09:05:59-09:06:03Z, destroy 09:06:21-09:07:09Z) |
| pre-plan read | `shape=present_attached`, `volume_server_id=170370833`, `server_id=170370833`, `luks_volume_id=107140231`, `luks_server_id=170370833` |
| plan | `Plan: 0 to add, 0 to change, 2 to destroy.`; destroy gate PASS (volume 106867358 and its attachment, live server 170370833) |
| apply | attachment destroyed 09:07:04Z (8 s), volume destroyed 09:07:04Z (1 s); `Apply complete! Resources: 0 added, 0 changed, 2 destroyed.`; gate PASS again inside the apply step |
| read-back | `shape=gone`, `volume_server_id=null`, `server_id=170370833`, `luks_volume_id=107140231`, `luks_server_id=170370833` (09:07:07Z) |
| claim limit | device deleted at the provider API only (404 by id, empty list by name); nothing about emptiness, snapshots, provider copies or lock residue |

## Research Reconciliation - Brief vs. Current Tree

| Brief / issue claim | Reality (measured 2026-10-27 on `2e9874cdf6`) | Plan response |
|---|---|---|
| `BASELINE_DECLARED_PROBES` 84 -> 83 | The constant is **85** (`11c23a4e4f` added +1 after #11179). `G1` walks `knowledge-base/project/plans/` recursively, archive included; the declaring plan is archived and is a dated record that stays | Leave 85, add one dated comment line (CTO R2). Editing the archived plan is cut |
| `PJ_TRIPLES` 292 -> 291 and a `drains` row | `PJ_TRIPLES=292`; the row `tests/scripts/test-git-data-plaintext-destroy-gate.sh \| curl \| drains \| 1 \| *` is present. File untouched since #11179 | Restore the file from `edade6cb3e^`; confirm 291 with a green run |
| census `FLOOR` 465 / `MUTANT_FLOOR` 200 and the `DISPATCH_GATED_DESTROYS` entry | Present at those values; file untouched since #11179; pre-#11179 values were 402 / 154 | Restore from `edade6cb3e^` (CTO R1: whole mechanism leaves) |
| `TEST_FLOOR` 309 | 309 = exact declared count (`grep -cE '^\s*test\(' ...` = 309); pre-#11179 = 297. The floor is exact and is asserted `toBeGreaterThanOrEqual` | Restore from `edade6cb3e^` (297) |
| `test-affected-paths.sh`, `test-all.sh` entries | Both moved by later commits (`2e9874cdf6`, `cb46e5454e`), so a checkout would drop unrelated work | Hand-reverse only the #11179 hunks |
| accept rows `operator-9321-stages` | Three rows at the end of `scripts/ci-pr-affected-audit.accept.tsv` (anchors `29652c91c131`, `414af6df7316`, `93d74076191c`); file untouched since | Restore from `edade6cb3e^` |
| "keep the `expires_on` clock until it can be retired under the lint rules" | `scripts/lint-encryption-posture.py` PASSES with the row removed (20 stores, 0 failing, measured on a scratch copy); ADR-239 Amendment 2026-10-26 item 6 says this PR retires the row; but the amendment is DRAFT | Row removal gated on CLO attestation (CTO R3); otherwise keep row and clock, rewrite evidence only |
| records "need CLO attestation or an owner decision" (issue item 4) | `expenses.md` row 24 is a bookkeeping flip; the Art. 30 PA-36(f) marker is append-only legal wording; the DPD refresh is `docs/legal/**` | expenses flip in scope; Art. 30 marker only from CLO-supplied wording; DPD excluded (brief) |
| ADR-239 item 7: the record PR "must be merged and live at soleur.ai/legal/" by the earlier of read-back + 7 days and 2026-11-11 | That bound includes the DPD edit, which the brief excludes from this PR | Recorded as a dated CLO item (2026-11-03 target, 2026-11-11 bound); PR uses `Ref`, issue stays open |
| prose to "update to past tense" | `apply-web-platform-infra.yml` still `-target`s `hcloud_volume.git_data` and `hcloud_volume_attachment.git_data` (four sites), #11194 is open | DISABLED banners, ADR-119 addendum, DISABLED note in `git-data.tf` STAY; the destroy procedure prose goes past tense |
| not in the brief | `model.c4` gitDataStore still says the plaintext volume "is RETAINED ... until the post-soak wipe" | In scope (architecture-record gate): update in place |

## Research Insights

**Premise Validation.** Checked by reference: #11195 OPEN (milestone Phase 4: Validate + Scale), PR #11179 MERGED 2026-10-26T22:12:49Z, draft PR #11284 OPEN, #6897/#9066/#8211/#11194 all OPEN, run 40478209838 `success`. `git log edade6cb3e..HEAD -- <file>` is empty for the census test, the parity test, the guard test, both `.tsv` registries and the accept file (so `git checkout edade6cb3e^ -- <file>` is byte-exact) and non-empty for `preflight-discoverability-test.test.ts`, `test-affected-paths.sh`, `test-all.sh` (hand-revert). `origin/main` equals the merge base of this branch. Stale premise found and corrected: the 84 -> 83 baseline (see above). The #6897 comment of 2026-10-27T09:10:24Z already carries the dated items (2026-11-03 record PR ready, 2026-11-11 hard bound, 2026-11-12 published retention date), so no new tracking issue is needed for the deferred DPD item (#11195 and #6897 are the trackers).

**Property List** (what this change must buy):

1. No artifact left in the tree can run the destroy again: workflow, plan gate, probe and gate suite are gone.
2. Every counter, floor and registry that #11179 moved reads its pre-#11179 value where the deleted artifacts caused the move, and each guard is green.
3. The posture ledger carries no row for a device that no longer exists (conditional on the CLO attesting) and the rehearsal row's trigger is true.
4. The decision records state the read-back append-only, counts and identifiers only, with the claim limit "device deleted at the provider API".
5. Prose that describes still-disabled routes stays true; prose that describes the deleted procedure is past tense or gone; the `model.c4` description no longer says the volume is retained.
6. Nothing outside scope changes: `docs/legal/**`, `AGENTS.rules.md`, `apply-web-platform-infra.yml`, the #11194 gate arms, `git-data-gc.sh`, `.gc-cursor`, the other worktrees and PRs named in the brief.

**Cut List** (mechanism -> property -> what already covers it):

- Keep the generic `DISPATCH_GATED_DESTROYS` allowance with empty entries -> buys no property (no consumer; its 17 rows need the deleted workflow or a synthetic injection) -> git history keeps it for a future real target (CTO R1).
- Edit or delete the archived #11179 plan to reach 84 -> would rewrite a dated record -> the dated baseline comment line covers it (CTO R2).
- A new ADR -> the decision is already recorded in ADR-239 Amendment 2026-10-26 -> an appended amendment section covers the read-back and the status.
- A replacement read-only probe or doc recipe for "is the volume gone" -> the run's read-back plus one fresh read taken before the probe is deleted cover it; no standing need.
- Reverting the `test-git-data-wipe-wedge.sh` `WEDGE_ADDRS` change -> the HCL still does not declare the addresses -> stays (CTO R4).
- Editing `apply-web-platform-infra.yml` or the replace/birth gates -> #11194 -> untouched.

**Applicable learnings.** `knowledge-base/project/learnings/2026-10-26-the-same-wrong-index-cut-recurred-and-my-destroy-pinned-ids-its-own-documented-step-re-mints.md`: a scripted section replacement deleted 173 lines of the previous plan because `index('## Name')` matched mid-line prose. Every markdown section edit in this plan (ADR-239 append, runbook rewrite, `expenses.md` row) uses the Edit tool with a unique anchor, and the level-two heading list is compared before and after each file. Sharp-edges catalogue (`plan-sharp-edges.md`, 335 lines) could not be paged in whole within this turn's context; it was searched by targeted grep for the classes that apply here (heading-anchored splices, residual-zero ACs must exclude the plan itself, measure the base before attributing a ratchet move, baseline moves are one commit). Each is applied below.

## User-Brand Impact

**If this lands broken, the user experiences:** a red CI on `main` for the infra and test guards (blocking every other PR), or a record that says the retained device is gone when a different state holds; the first is a delivery stall, the second an inaccurate retention statement in our own decision records.
**If this leaks, the user's data is exposed via:** no new vector. The change deletes a CI workflow and registry rows and edits records; the records carry counts and identifiers only (no volume contents were ever read) and the claim is limited to "device deleted at the provider API".
**Brand-survival threshold:** aggregate pattern. (The legal-risk content, DPD section 10.3(b), is out of scope and CLO-owned.)

## Open Code-Review Overlap

Queried 2026-10-27 (`gh issue list --label code-review --state open --limit 200`, then `jq --arg path` per planned file). Three matches, all acknowledged (none folded in: this change is a deletion record, and widening the scope on the guards being reverted raises blast radius):

- #7942 (`scripts/test-all.sh`: two `*.mutation.sh` batteries run in no gate) - acknowledge; unrelated to the destroy suite, needs its own cycle.
- #8800 (`scripts/lib/test-affected-paths.sh`: census sandbox shares inodes with the live repo) - acknowledge; a fixture-isolation concern, not touched by removing three list entries and one array.
- #10112 (`scripts/encryption-posture-ledger.json`: finish the #9786 residuals once #10081 lands, including an unused rehearsal volume) - acknowledge; it is gated on #10081 and concerns the rehearsal volume's existence, while this change only settles the rehearsal row's `reevaluate_when`. The new text points at #11194, and the #10112 owner re-reads the row when #10081 lands.

No other planned file appears in an open code-review issue body.

## Architecture Decision (ADR/C4)

### ADR

No new ordinal. Append `## Amendment 2026-10-27 - read-back of the plaintext-volume destroy (#11195, #8211, #6897)` to `ADR-239-git-data-serves-from-luks-at-birth.md` (end of file, after the 2026-10-26 amendment, which is never edited). Contents: run URL, the measured table above (counts and identifiers only), the claim limit restated once by reference to item 2 of the 2026-10-26 amendment, the retirement of the workflow/gate/probe and the ledger row, the state of the attestation, and the dated CLO item for DPD section 10.3(b). The status line in that section reads `IN FORCE` only if the CLO attests (recorded `Ruled by CLO agent, <date>: ...`); otherwise `executed, still pending attestation` and the ledger row stays. The ADR-119 addendum is not touched.

### C4 views

Read in full: `spec.c4` (54 lines, element kinds only). `views.c4` (142 lines) and `model.c4` were swept for every `plaintext`, `git_data` and `git-data-store` mention: `views.c4` has none; `model.c4` has hits at the web-1 workspaces element (retained web-1 plaintext volume, a different device), the inngest element (retired backstop), the web-2 rebirth edge, the `github -> hetzner` edge (wipe-mode DELETE allow-list of `git-data-cutover.yml`, which still exists and still describes that code) and the `github -> gitDataStore` edge (wipe modes, "retired plaintext volume is deleted through the Hetzner API edge" - still accurate), plus the gitDataStore element. Actors and systems checked: Hetzner Cloud API (already modeled as the `hetzner` edge target), GitHub Actions (already modeled; a deleted workflow adds no edge, and #11179 added none), the R2 Terraform state (not modeled per workflow). The only falsified description is the gitDataStore element: "That plaintext volume is RETAINED and is never mounted ... it stays a ledgered exception (encryption-posture-ledger.json, tracking #6897) until the post-soak wipe." Update in place to: the volume was deleted at the provider on 2026-10-27 (run 40478209838, 404 by id), the ledger exception is retired (or, if not attested, retained pending attestation), and the cloud-init plaintext arm plus the literal `git_data_volume_id` remain until #11194 so a host rebirth would hit the bootstrap `plaintext_unverified` FATAL (ADR-239 Amendment 2026-10-26 item 4). Commit hook regenerates `model.likec4.json`; run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (derived counts: heartbeat workflows, Resend emitters, monitor slugs - the deleted workflow uses none, measured by #11179 not touching the diagrams).

### Sequencing

All in this PR; nothing deferred to a follow-up issue.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.git_data   # retired 2026-10-27
    mechanism: plaintext-exception  # until its row is retired
    evidence: apps/web-platform/infra/git-data.tf no longer declares it; run 40478209838 read-back shape=gone (404 by id 106867358, empty list by name)
    defends_against: nothing at the volume layer (never mounted writable by policy, ADR-239 D2)
    does_not_defend: a seized or snapshot disk exposed any git data and any id-bearing lock residue resident on this volume while it existed; provider snapshots or copies, and the LUKS-served store's own lock files and .gc-cursor, are not covered by the deletion and stay unmeasured
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:point-in-time provider API read in the run log; no on-host probe; contents never read"
  - store: hcloud_volume.git_data_luks   # unchanged by this PR
    mechanism: luks
    evidence: scripts/encryption-posture-ledger.json row hcloud_volume.git_data_luks (device_binding resolved by lint-encryption-posture.py); the read-back shows volume 107140231 on server 170370833 unchanged
    defends_against: a seized or snapshot disk of the volume at rest
    does_not_defend: a live host with the mapper open and the Doppler passphrase available; a Doppler compromise (the passphrase lives there)
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:point-in-time provider API read in the run log; no on-host probe"
in_transit:
  - connection: none introduced or changed
    tls: not applicable (no connection added)
    cert_verification: on
    does_not_defend: not applicable (no connection added)
    disclosed_as: not-publicly-claimed
exception:
  justification: the retired plaintext device existed until 2026-10-27; its ledger exception is removed with its row only if the CLO attests (Branch A), otherwise kept unmoved (Branch B)
  tracking_issue: "#6897"
  reevaluate_when: the CLO attestation outcome is recorded in this PR (Phase 0.4)
  expires_on: "2026-11-12 (unmoved in both branches; the row and its clock leave together on Branch A)"
```

## Domain Review

**Domains relevant:** Engineering, Legal, Operations

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-10-27: seven items (census revert, baseline, ledger, prose triage, expenses, closing keyword, completeness); all recorded in `knowledge-base/project/specs/feat-one-shot-11195-plaintext-volume-destroy-record/decision-challenges.md`.

### Legal (CLO)
**Status:** reviewed (deferred to implementation by design)
**Assessment:** The ADR-239 attestation, the ledger-row retirement gate, the Art. 30 PA-36(f) marker wording and the DPD section 10.3(b) item are CLO matters. The implementer obtains them with one report-only `soleur:legal:clo` spawn (prompt carries "do NOT use AskUserQuestion") and records `Ruled by CLO agent, <date>`. `docs/legal/**` is not edited.

### Operations
**Status:** reviewed
**Assessment:** The `expenses.md` retire flip is a bookkeeping record ruled by the CTO (R5); no spend decision.

## Gate Dispositions

- **Infrastructure routing:** not applicable. No new infrastructure: the change deletes a workflow and a read-only probe and edits comments in two `.tf` files; no resource is added, changed or destroyed by this PR (the state already lost both addresses in the destroy). Side effect to expect: any change under `apps/web-platform/infra/**` fires the per-merge apply workflow on `main`; its `-target` list does not contain the retired addresses and `hcloud_server.git_data` is outside it, so the expected plan is empty - read the run, do not intervene.
- **Observability quality gate:** deletes-only plus records (no new code path, log call, service or failure mode); a minimal `## Observability` block follows because `deepen-plan` 4.7 applies to any non-docs Files-to-Edit.
- **Guard contract gate:** skipped. The deliverable adds no guard. It retires guards (the destroy gate, its suite, the census allowance, the parity pins) and moves the counters those guards own back; Phase 4 re-runs each affected guard as evidence the reversal is exact.
- **Task-design gate:** skipped. No new autonomous-task surface (no workflow, function, check or timer is added).
- **GDPR gate:** no schema, migration, auth, API or `.sql` surface and none of the four extra triggers; the legal content (attestation, Art. 30 wording, DPD) is routed to the CLO in Phase 0.4.

## Observability

```yaml
liveness_signal:
  what: the encryption-posture ledger lint resolves the ledger against the Terraform tree, and the CI guard suites stay green on main
  cadence: every pull request and every push to main (CI), plus the scheduled drift run twice a day
  alert_target: CI status on the PR and main; the drift workflow files an issue labelled infra-drift
  configured_in: .github/workflows/ci.yml and .github/workflows/scheduled-terraform-drift.yml
error_reporting:
  destination: GitHub Actions run status and the drift-detected issue; the per-merge infra apply reports through its own failure notifier
  fail_loud: true
failure_modes:
  - mode: a restored counter or floor disagrees with a green run (a guard goes red)
    detection: the owning guard suite fails in CI
    alert_route: red required check on the PR
  - mode: a stale reference to a deleted file survives in a registry or path list
    detection: orphan-suite, shard-totality and affected-path lints in CI
    alert_route: red required check on the PR
  - mode: the per-merge infra apply plans a change after merge
    detection: the apply run's plan output on main
    alert_route: apply workflow failure notifier and the drift issue
logs:
  where: GitHub Actions run logs (the destroy run log is the only durable copy of the step output until the ADR section carries it)
  retention: Actions default run-log retention; the appended ADR-239 section is the permanent copy
discoverability_test:
  command: python3 scripts/lint-encryption-posture.py
  expected_output: PASS
```

## Implementation Phases

### Phase 0 - Preconditions and read-only evidence (before anything is deleted)

- 0.1 `git fetch origin main` and re-check the premises: `gh issue view 11195`, `gh pr view 11284`, `git log edade6cb3e..origin/main -- <each restored file>` still empty for the six restore-by-checkout files (if a later commit appears, hand-revert that file instead). Re-read the run: `gh run view 40478209838 --json conclusion`.
- 0.2 Baseline: run the guards that will be touched on the unmodified tree and record counts (census suite, parity test, `grep-q-pipe-guard.test.sh`, `lint-encryption-posture.py`, `preflight-discoverability-test.test.ts -t G1`). A red baseline is a base problem, not this change (measure the base before attributing a move).
- 0.3 Fresh read-only state read, before the probe is deleted: `bash apps/web-platform/infra/git-data-plaintext-volume-state.sh` with `HCLOUD_TOKEN_READONLY` (Doppler `prd_terraform`, read). Expect `plaintext_volume=absent`, `shape=gone`. Record the UTC time and the identifier-only output for the ADR section. If no read credential is available in the session, record that and rely on the run's read-back; this is not a blocker.
- 0.4 Spawn the CLO once (report-only). Prompt: the measured table above, the DRAFT amendment text, and four questions - attest the equivalence now that the read-back is in; may the ledger row be retired on that basis; supply append-only wording for the Art. 30 PA-36(f) marker (the register row says the residue "ends when that volume is destroyed ... the Hetzner volume delete is the end event"); confirm DPD section 10.3(b) stays a CLO-owned item (2026-11-03 target, 2026-11-11 bound). Persist the answer as rows in this branch's `decision-challenges.md`. Branch A (attested): proceed with the row removal and `IN FORCE`. Branch B (not attested or conditional): keep the row and its clock, rewrite evidence only, status stays "executed, still pending attestation". The rest of the plan is identical in both branches.

### Phase 1 - Delete the one-shot artifacts and reverse the counters (one commit; baselines compare to the live census)

Delete: `.github/workflows/git-data-plaintext-volume-destroy.yml`, `tests/scripts/lib/git-data-plaintext-destroy-gate.sh`, `tests/scripts/test-git-data-plaintext-destroy-gate.sh`, `apps/web-platform/infra/git-data-plaintext-volume-state.sh`.

Restore byte-exact (`git checkout edade6cb3e^ -- <file>`, valid because nothing touched them since):

| File | Reversal |
|---|---|
| `tests/scripts/test-infra-privileged-tier-census.sh` | `DISPATCH_GATED_DESTROYS`, `step_code`/`step_obeys`/`dispatch_gated_ok`, the G4c orphan clause, the G4f extension, rows g4-15..g4-31; `MUTANT_FLOOR` 200 -> 154, `FLOOR` 465 -> 402 (confirm both with a green run) |
| `plugins/soleur/test/terraform-target-parity.test.ts` | `MAIN_ROOT_TF_WORKFLOWS` entry, `found.length` 4 -> 3, the 12-test destroy describe, `TEST_FLOOR` 309 -> 297 (exact; re-derive with `grep -cE '^\s*test\(' plugins/soleur/test/terraform-target-parity.test.ts`) |
| `.claude/hooks/grep-q-pipe-guard.test.sh` | `PJ_TRIPLES` 292 -> 291 and the `... \| curl \| drains \| 1 \| *` row for the deleted suite (confirm 291 with a green run of the suite) |
| `scripts/ci-pr-affected-audit.accept.tsv` | the three `operator-9321-stages.test.sh` rows naming the deleted workflow |
| `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` | the `tests/scripts/git-data-plaintext-destroy-gate` row |

Hand-revert only the #11179 hunks (later commits touched these):

- `scripts/test-all.sh`: the `run_suite "tests/scripts/git-data-plaintext-destroy-gate" ...` line and its comment line.
- `scripts/lib/test-affected-paths.sh`: three `AFFECTED_PLUGINS_SOLEUR_PATHS` entries (the workflow, the probe, the gate library) and the `AFFECTED_TESTS_SCRIPTS_GIT_DATA_PLAINTEXT_DESTROY_GATE_PATHS` array with its comment.
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` stays 85; add one dated comment line after the #11179 entry's block saying the probe command is retired 2026-10-27 and the declaration remains as history (the #11179 TRUTH note no longer holds).

Leave alone: `apply-web-platform-infra.yml`, the replace/birth gates and their suites, `test-git-data-wipe-wedge.sh` `WEDGE_ADDRS`/`M1`, `variables.tf`, `zot-registry.tf`, `key-principles.md`, the archived plan/spec/learning, the files that mention the older `git-data-plaintext-snapshot-loopback.test.sh`.

### Phase 2 - Ledger (`scripts/encryption-posture-ledger.json`)

- Branch A: remove the whole `hcloud_volume.git_data` store object (precedent #10132). Branch B: keep it, rewrite `evidence`/`live_verification` to the 2026-10-27 read-back (run 40478209838, gone), leave `expires_on` 2026-11-12.
- Rehearsal row (`hcloud_volume.rehearsal` store): `reevaluate_when` -> "#11194 retires the plaintext `git_data_volume_id` arm from the git-data cloud-init template and its gates (the destroy half fired 2026-10-27, run 40478209838), or the GIT_DATA_STORE_ENABLED cutover completes - then retarget this mirror to the LUKS shape or retire it"; replace the stale 2026-10-26 parenthetical in `justification` with "device deleted 2026-10-27, template arm still live until #11194"; `expires_on` 2026-12-31 unmoved.
- No `expires_on` moves in either branch. Run `python3 scripts/lint-encryption-posture.py` and `bash scripts/lint-encryption-posture.test.sh`.

### Phase 3 - Records (Edit tool only, unique anchors; compare `^## ` heading lists before and after each file)

Prose triage (evidence in parentheses; rulings in decision-challenges.md):

| Prose | Disposition |
|---|---|
| runbook `git-data-luks-cutover-5274.md` section "Plaintext-volume destroy (Option B, #8211 / #6897)" | UPDATE-IN-PLACE. Keep the heading text (the `git-data-birth.md` banner names it). Replace "Order", "Dispatch", "Read the state without dispatching", "What the run proves", "Between merge and dispatch" and "Recovery" with a short past-tense "As run (2026-10-27)" record: run URL, the table above, gate PASS, read-back gone, LUKS and server unchanged; no runnable commands (they would name deleted files). KEEP the "If the git-data host is lost ..." paragraph and the "Retention and public disclosure" paragraph (routes stay disabled until #11194; DPD refresh still open). Rewrite the "After the destroy" paragraph to say what this PR did. Update the opening sentence ("DRAFT, pending CLO attestation") to match the attestation outcome |
| `git-data-birth.md` and `apply-web-platform-infra-job-rationale.md` DISABLED banners | STAY verbatim (`apply-web-platform-infra.yml` still targets the retired addresses at four sites; #11194 open) |
| ADR-119 addendum 2026-10-26 | STAY (append-only; its ordering claim is still true) |
| ADR-239 Amendment 2026-10-26 | never edited; new appended section (see ADR above) |
| `git-data.tf` | DISABLED note near the top STAYS; `SOLEUR-DEBT:` marker above `module "git_data_userdata"` -> past tense ("the destroy workflow deleted ... on 2026-10-27"), keep the #11194 trigger and the rebirth-FATAL warning; the comment block after `hcloud_server.git_data` that names the workflow and gate paths -> cite the runbook and ADR-239 Amendment 2026-10-27 instead |
| `git-data-luks.tf` comment ("deleted by the dispatched destroy workflow") | past tense, no path to a deleted file |
| `test-git-data-wipe-wedge.sh` header ("are deleted by .github/workflows/git-data-plaintext-volume-destroy.yml") | one-line past-tense fix only |
| `model.c4` gitDataStore description | UPDATE-IN-PLACE as in "C4 views"; hook regenerates the JSON |
| `knowledge-base/operations/expenses.md` row "Hetzner Volume (git-data, 10 GB, plaintext)" | status `retired`; drop the `estimate verify_by=2026-08-01` marker; RETIRED lead-in "RETIRED 2026-10-27 (#11195): volume 106867358 deleted by Terraform destroy, run 40478209838; read-back gone; billing ends with the deletion (hourly)"; strike or rewrite the PHANTOM sentence; date column stays "-"; run `bash scripts/expenses-verify-by-check.sh` |
| `knowledge-base/legal/article-30-register.md` PA-36 (f) | Append-only superseded marker authored ONLY from wording the CLO returns; if none, no edit and the item stays open on #11195 |

### Phase 4 - Verification (the gates' own invocations, not reconstructions)

Run and record green: `bun test plugins/soleur/test/terraform-target-parity.test.ts`; `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` (G1 = 85); `bash tests/scripts/test-infra-privileged-tier-census.sh` (floors 402/154 exact); `bash .claude/hooks/grep-q-pipe-guard.test.sh` (291); `bash tests/scripts/test-git-data-wipe-wedge.sh`, `test-git-data-host-replace-gate.sh`, `test-git-data-host-birth-gate.sh`, `test-git-data-root-key-arm.sh`; `python3 scripts/lint-encryption-posture.py`; `bash scripts/lint-orphan-test-suites.sh`; `bash scripts/guard-vacuity-floor.test.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh` and the two C4 vitest files; `bash scripts/lint-workflows.sh`; the CI ratchet step for `scripts/ci-pr-affected-replay.py` as `.github/workflows/ci.yml` invokes it; `bash scripts/test-affected-kb-consumers.test.sh` (the runbook, ADR and `model.c4` are KB inputs); `scripts/test-all.sh` affected selection. A heavy suite that the box cannot finish is left to CI and read back, per the repo's contended-box principle.

### Phase 5 - PR and dated items

PR body: `Ref #11195`, `Ref #8211`, `Ref #6897`, `Ref #11194` (never `Closes`); includes the rendered decision-challenges table; names the open items (DPD section 10.3(b) refresh - CLO, target 2026-11-03, hard bound 2026-11-11; Art. 30 marker if the CLO returned no wording; #11194). Comment the PR link on #11195 and #6897. After merge: read the per-merge infra apply run (expected empty plan) and the next scheduled drift run that logs "No drift detected in web-platform" (the 2026-10-27 18:00Z run); close a drift issue only if its plan shows exactly the two retired destroys (the two currently open drift issues predate the destroy, 2026-10-21/22, so they are not this).

## Files to Edit

- `tests/scripts/test-infra-privileged-tier-census.sh` (restore), `plugins/soleur/test/terraform-target-parity.test.ts` (restore), `.claude/hooks/grep-q-pipe-guard.test.sh` (restore), `scripts/ci-pr-affected-audit.accept.tsv` (restore), `scripts/suite-durations.tsv` (restore), `scripts/suite-shard-legs.tsv` (restore)
- `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `plugins/soleur/test/preflight-discoverability-test.test.ts` (hand-revert hunks)
- `scripts/encryption-posture-ledger.json`
- `apps/web-platform/infra/git-data.tf`, `apps/web-platform/infra/git-data-luks.tf` (comments only), `tests/scripts/test-git-data-wipe-wedge.sh` (header comment only)
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md` (append), `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, `knowledge-base/engineering/architecture/diagrams/model.c4` (+ regenerated `model.likec4.json`), `knowledge-base/operations/expenses.md`, `knowledge-base/legal/article-30-register.md` (only with CLO wording)
- `knowledge-base/project/specs/feat-one-shot-11195-plaintext-volume-destroy-record/decision-challenges.md` (append the CLO row)

## Files to Delete

- `.github/workflows/git-data-plaintext-volume-destroy.yml`
- `tests/scripts/lib/git-data-plaintext-destroy-gate.sh`
- `tests/scripts/test-git-data-plaintext-destroy-gate.sh`
- `apps/web-platform/infra/git-data-plaintext-volume-state.sh`

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "delete the one-shot workflow .github/workflows/git-data-plaintext-volume-destroy.yml, the gate tests/scripts/lib/git-data-plaintext-destroy-gate.sh, its test tests/scripts/test-git-data-plaintext-destroy-gate.sh, the probe apps/web-platform/infra/git-data-plaintext-volume-state.sh" [brief, issue #11195 scope 1] | Phase 1, Files to Delete | mapped |
| 2 | "every parity/registry/census/affected-path/accept-row/credentials_required-baseline/PJ_TRIPLES/floor entry that referenced them" [brief] | Phase 1 restore and hand-revert tables | mapped |
| 3 | "retire the hcloud_volume.git_data row in scripts/encryption-posture-ledger.json (keep the lint-enforced expires_on clock until it can be retired under the ledger lint rules)" [brief] | Phase 2 (Branch A / B) | mapped |
| 4 | "settle the rehearsal row reevaluate_when" [brief] | Phase 2 | mapped |
| 5 | "append the run URL and counts/identifiers-only step summary to the records" [brief] | Phase 3 ADR-239 appended section, runbook "As run" record | mapped |
| 6 | "ADR-239 attestation: the implementer will obtain it by spawning soleur:legal:clo (report-only) and record 'Ruled by CLO agent'; flip DRAFT to attested only if the CLO attests" [brief] | Phase 0.4, Branch A / B | mapped |
| 7 | "decide, with evidence, which of the PR #11179 prose ... must stay ... versus be updated to past tense" [brief] | Phase 3 prose-triage table, decision-challenges.md | mapped |
| 8 | "verify each against the CURRENT tree, since main has moved" [brief] | Research Reconciliation table, Phase 0.1 | mapped |
| 9 | "`knowledge-base/operations/expenses.md` status flip for the retired volume" [issue #11195 scope 4] | Phase 3 expenses row | mapped |
| 10 | "the Art. 30 PA-36(f) marker" [issue #11195 scope 4] | Phase 3.6, only from CLO wording | mapped |
| 11 | "do not edit docs/legal/** ... do not edit AGENTS.rules.md ... Do not edit apply-web-platform-infra.yml gates beyond what removing the destroy workflow strictly requires" [brief] | Acceptance Criteria diff-scope bullet | mapped |
| 12 | "the DPD 10.3(b) refresh stays an item on #6897/#11195 for the CLO" [brief] | Phase 5 open items, `Ref` keywords | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Delete (four files) | "delete the one-shot workflow" | asked |
| Restore-by-checkout of six registry/guard files; hand-revert of three | "must reverse each counted baseline it moved" | asked |
| `BASELINE_DECLARED_PROBES` stays 85 with a dated comment | "verify each against the CURRENT tree, since main has moved" | asked |
| Ledger row removal gated on CLO; rehearsal text | "flip DRAFT to attested only if the CLO attests" | asked |
| ADR-239 appended section | "dated records are APPEND-ONLY (append a new section, never rewrite old text)" | asked |
| Runbook "As run" rewrite; `git-data.tf`, `git-data-luks.tf` comments | "which of the PR #11179 prose ... must stay ... versus be updated to past tense" | asked |
| `expenses.md` row; Art. 30 marker | asks 9-10 | asked |
| `model.c4` gitDataStore update | - | inferred - justification: the architecture-record gate requires the recorded architecture not to lag the change, and the description says the deleted device is retained |
| `test-git-data-wipe-wedge.sh` header one-line fix | asks 7 | inferred - justification: the header states in present tense that the deleted workflow deletes the volume; a dead pointer, listed by the CTO ruling |
| Phase 0.3 fresh read before the probe is deleted | - | inferred - justification: the probe is deleted in Phase 1, so a second independent read of the end state is only obtainable first |
| Phase 4 verification battery | "must reverse each counted baseline it moved" | asked |
| Phase 5 post-merge watch (apply run, drift run) | - | inferred - justification: the deleted runbook section made closing the drift issue a post-destroy step; the watch is read-only and keeps that step from rotting |

### Split Assessment

- Subsystems touched: 7 - apps/, tests/, scripts/, plugins/, .claude/, .github/, knowledge-base/
- Planned files: 23 | Estimated changed lines: about 1,500 (almost all deletions: gate suite 579, workflow 345, gate 145, probe 145, census and parity reversals about 370)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the thresholds are exceeded by deletions of one feature; the counters must move in the same commit as the artifacts that moved them (a baseline drawdown is one commit), and splitting the records from the deletion would leave a tree whose records describe artifacts that still exist or whose guards disagree with their floors.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The four files above are deleted, and `git grep -n -e 'git-data-plaintext-volume-destroy' -e 'git-data-plaintext-destroy-gate' -e 'git-data-plaintext-volume-state' -e 'git_data_plaintext_destroy_gate' -e 'DISPATCH_GATED_DESTROYS' -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/project/learnings'` returns hits only in `ADR-239-...md`, the runbook `git-data-luks-cutover-5274.md`, `git-data.tf` (past-tense comments) and `article-30-register.md` (dated rows); no hit in any workflow, test, registry or script. The plan and spec directories are excluded because they quote the names by design.
- [ ] `AFFECTED_TESTS_SCRIPTS_GIT_DATA_PLAINTEXT_DESTROY_GATE_PATHS` and every `AFFECTED_PLUGINS_SOLEUR_PATHS` destroy entry are gone (`git grep -c` = 0 in `scripts/lib/test-affected-paths.sh`).
- [ ] Census `FLOOR=402` and `MUTANT_FLOOR=154`, each equal to the measured run count of a green run; `TEST_FLOOR=297` equals the `grep -cE '^\s*test\('` count; `PJ_TRIPLES` equals the green-run distinct-triple count (expected 291); `BASELINE_DECLARED_PROBES=85` and G1 green.
- [ ] The three accept rows are gone and the ratchet step of `ci.yml` is green; `suite-durations.tsv` / `suite-shard-legs.tsv` have no row for the deleted suite and the orphan-suite and shard-totality lints are green.
- [ ] Ledger: lint green; Branch A: no `hcloud_volume.git_data` store row, 20 stores; Branch B: row kept, `expires_on` still 2026-11-12. Rehearsal row `reevaluate_when` is the ruled text and `expires_on` is still 2026-12-31. No `expires_on` in the file moved.
- [ ] ADR-239 has a new final `## Amendment 2026-10-27` section with the run URL and the measured table; the text of every earlier section is byte-identical (`git diff` shows additions only in that file); status wording matches the CLO outcome; the level-two heading list differs only by the new heading.
- [ ] Every sentence the diff adds traces to a named source: the run log (table), the CLO return (attestation, Art. 30 wording), or the CTO rulings; the claim limit is "device deleted at the provider API" and nothing wider appears in any record.
- [ ] Runbook: heading text unchanged; no runnable command naming a deleted file remains; the host-lost and retention paragraphs remain; DISABLED banners in `git-data-birth.md` and `apply-web-platform-infra-job-rationale.md` are unchanged (`git diff` empty for those two files).
- [ ] `model.c4` gitDataStore no longer says the plaintext volume is retained; C4 tests and `c4-count-parity` green; `model.likec4.json` regenerated by the hook, not hand-edited.
- [ ] `expenses.md` row is `retired`, marker dropped, `expenses-verify-by-check.sh` exit code unchanged from baseline.
- [ ] Diff scope: only the files listed above, plus generated `model.likec4.json`, the generated knowledge-base index if the pipeline regenerates it, and this branch's `specs/` and `plans/` artifacts. Zero changes to `docs/legal/**`, `AGENTS.rules.md`, `.github/workflows/apply-web-platform-infra.yml`, `git-data-gc.sh`, `.mcp.json`.
- [ ] This plan declares no `credentials_required` (keeps G1 at 85).
- [ ] PR body uses `Ref` for #11195, #8211, #6897, #11194 and lists the open DPD and Art. 30 items with dates.

### Post-merge

- [ ] The per-merge infra apply run triggered by the `apps/web-platform/infra/**` change concludes with an empty plan (read-only watch; nothing is dispatched).
- [ ] The next scheduled `web-platform` drift run reports no drift; a drift issue is closed only if it lists exactly the two retired destroys.
- [ ] #6897 / #11195 carry the PR link and the dated DPD item (2026-11-03 target, 2026-11-11 bound); #11195 stays open until the CLO closes the DPD (and, if applicable, Art. 30) items.

## Test Scenarios

- Reversal exactness: after Phase 1 the six restored files are identical to `edade6cb3e^` (`git diff edade6cb3e^ -- <file>` empty) and each owning guard is green with its restored floor.
- Anti-drift: temporarily re-adding a destroy-gate row to `suite-shard-legs.tsv` must make the shard-totality or orphan lint red (spot check, not committed).
- Ledger gate: Branch A lint passes with the row removed and fails if a leftover `device_binding` references `hcloud_volume.git_data` elsewhere; Branch B passes with the row kept.
- Append-only: `git diff` of ADR-239 contains only `+` lines in the file's tail.

## Risks

- **A later commit lands on a restore-by-checkout file before this merges.** Phase 0.1 re-checks and falls back to a hand-revert; the checkout would otherwise erase that commit.
- **Floors are exact counts.** Setting 402/154/297/291 from this plan rather than from a green run would pass or fail by luck; each must be confirmed by a run.
- **Attestation outcome.** If the CLO does not attest, the amendment stays DRAFT and the row keeps the legal clock; the PR still merges (records and reversal are independent of the attestation).
- **Per-merge apply.** Touching `apps/web-platform/infra/**` fires it; the expected plan is empty because the retired addresses are neither in HCL nor in state and `hcloud_server.git_data` is outside the target list. A non-empty plan is a stop-and-read, not a retry.
- **Probe deleted before the fresh read.** Phase 0.3 is ordered first for that reason.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; it is filled here (`aggregate pattern`).
- The residual-zero grep excludes `plans/`, `specs/` and `learnings/` because they quote the deleted names by design; an unqualified grep is unsatisfiable.
- `git checkout <rev> -- <file>` restores the whole file, including any later unrelated edit; the six chosen files were verified untouched since `edade6cb3e`, the other three were not and are hand-reverted.
- Dated records are append-only: ADR-239 earlier sections, ADR-119 addendum, the archived plan/spec, the Art. 30 register's existing markers, and the 2026-10-26 learning are never rewritten.
- Disk quota note for the implementer: scratch files go under the session scratchpad and are deleted after use.
