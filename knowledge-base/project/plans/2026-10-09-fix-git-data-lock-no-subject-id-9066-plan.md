---
title: "fix: git-data lock carries no subject id; pin the property; set the plaintext-volume retention end (#9066)"
date: 2026-10-09
slug: git-data-lock-no-subject-id-9066
branch: feat-one-shot-9066-git-data-lock-no-subject-id
issue: 9066
lane: cross-domain
requires_cpo_signoff: true
---

# fix: git-data lock carries no subject id; pin the property; set the plaintext-volume retention end (#9066)

## Enhancement Summary

**Deepened on:** 2026-10-09 (after plan-review: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow; CLO and CPO consults)
**Agents used:** learnings-researcher, CLO, CPO, five plan-review seats; deepen gates 4.6-4.12 run inline (no 40-agent fan-out: constraint "targeted, contended box").

### Key Improvements
1. Premise corrected with evidence: the constant-name lock is already on main (#9226) and its rung-2 evidence hash is current (#9254) — no bound-file edit.
2. Guard redesigned around a pure predicate with a committed negative control, so the mutation evidence is CI-enforced rather than pasted; arms made per-suite.
3. AC1 hardened (a failed bound-files call can no longer read as a pass); ADR wording aligned with D2 (the Hetzner delete is the end event, no zeroing write); post-merge chain and slip rule made explicit; C4 edit and issue comment cut.

### New Considerations Discovered
- The wipe PR (#6897) has no implementation on main, so 2026-10-22 is a target; the ledger lint hard-fails CI after that date.
- Running host serves pre-#9226 wrappers until the next replace; the runbook step (d) text needs a qualifier.
- Deepen gate results: 4.6 pass (filled, `single-user incident`); 4.7 pass (5 fields, probe `grep -c purge.count=` prints 1); 4.8 pass (no PAT shapes); 4.10 pass (section added); 4.11 pass (`lint-guard-contract.py` green, assembly structural); 4.12 pass (one unfenced Scope Check, all rows compliant); cited rule ids and PR/issue numbers verified live.

Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to cross-domain (fail-closed).

## Overview

Issue #9066 asks for three things: a lock that carries no subject identifier (requirement 1), a
count-only measure and purge of the lock files already on the served store (requirement 2, a
production write that needs the owner's per-step authorization), and a stated retention end for the
retained plaintext volume in ADR-239 and the LUKS cutover runbook (requirement 3, docs only).

**The brief's central premise is stale.** The brief says the lock sites still open
`REPO_ROOT/.<workspace_id>.init.lock` and that this PR is "PR1" of the rung-2 two-PR sequence.
`origin/main` already carries the constant-name lock (PR #9226, `a96d123938`, 2026-09-30) and the
rung-2 evidence for that exact payload (PR #9254, `b4a05d5776`). So requirement 1's *code* is
done and evidenced; the two-PR sequence has already run for it. This plan therefore does **not**
edit any hash-bound payload (an edit would void the evidence and HOLD every git-data birth and
replace for no gain). What is left, and what this PR delivers:

1. a verification record for requirement 1, with a file-anchored claim per fact (the issue's own
   comment says "the verification pass against the merged code is still to do");
2. a regression guard for the *property* ("no subject identifier on the store"), which today is only
   implied by the symlink and retention tests — test files only, outside the hash-bound set;
3. requirement 3: the plaintext-volume retention end in ADR-239 and the runbook (and, per the CLO
   consult, one superseded-marker in Art. 30 PA-36 (f)), with the live-host caveat that the
   constant lock reaches the running host only through the next replace.

Requirement 2 (measure + purge on the served store) is **not** done here: the purge is already
coded inside `MODE=freeze` (`git-data-cutover.sh`), and running it is a production write.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "git-data-remove.sh and git-data-provision.sh open REPO_ROOT/.<workspace_id>.init.lock and never unlink it" | Both open `${REPO_ROOT}/.init.lock` (constant name): `git-data-remove.sh` `lock_file="${REPO_ROOT}/.init.lock"`, `git-data-provision.sh` same. Landed in #9226 (commit message: "fix(9066): constant-name .init.lock"). | Req 1 code is done. No payload edit. Verify and guard it. |
| "this PR is PR1 (the payload change, with whatever hash/trigger bookkeeping that sequence requires)" | `git_data_rung2_user_data_sha256` over the current tree = `90b2e7af…74ba` = `RUNG2_TEMPLATE_SHA256` in `git-data-rung2-boot-evidence.env` (rehearsal run 36659264513, merged #9254). The bound set is intact. | Do NOT edit any of the bound files (17 paths: the template, the 3 module `.tf` files and the 13 `file()` payloads — derived by `git_data_rung2_bound_files`, never hand-listed); do NOT delete the evidence file. A payload edit would open an interlock window (evidence voided → birth/replace HOLD) for a zero-behavior change. |
| "`_repo_count` and the cutover proof's store count skip `.*.init.lock`; any new lock name must keep those counters correct" | Predicates already exclude `.*.init.lock`, `.init.lock`, `lost+found` in `git-data-bootstrap.sh` (`_repo_count` case `d`) and `git-data-cutover.sh` (proof `find`), pinned by `git-data-bootstrap-store-verify.test.sh` S9 and the access suite. `.boot-probe-0.init.lock` is excluded by the purge and matched by the `.*.init.lock` count exclusion. | Nothing to change. Verification record cites each. |
| "`.boot-probe-0.init.lock` is synthetic and must stay excluded" | The purge `find` has `! -name '.boot-probe-0.init.lock'`; loop `case` skips it (`git-data-cutover.sh` mode_freeze step 4). | Nothing to change; the guard below carries a must-PASS row containing it. |
| "Req 2: measure count only, then purge" | Coded: `purge count=$n` annotation (count only, no names) then flock-checked `rm` inside the freeze window; a held lock refuses `lock_held`. Runs only inside a real `flip`. | Out of scope (prod write). Leave to the issue. |
| "Req 3: set the plaintext-volume retention end" | Not stated in ADR-239 or the runbook (both say "retained read-only until its wipe decision (#6897/#8571)"). Art. 30 PA-36 (f) and the ledger already carry `expires_on: 2026-10-22` / "until the DL-2 wipe". | Do it (Phase 3), reusing the existing 2026-10-22 outer bound (CLO consult). |
| (implicit) "the fix is live once merged" | Host payload is `user_data`, ForceNew: the running host keeps the pre-#9226 wrappers until the next `git_data_host_replace`. Erasures until then still write `.<id>.init.lock` (on the LUKS store, purged in the freeze window). | State the caveat in ADR-239 and runbook. The replace is a production action — not taken here. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #9066 (open, correct), #5914 (closed), #8211 (open),
#9377 (open, unrelated header-escrow split — cited by the brief only as a Refs), #8609 (open),
PR #9226 (merged 2026-09-30), PR #9254 (evidence, merged), the cited paths (all exist on
`origin/main`), and the ADR corpus for the mechanism (ADR-239 amendment 2026-09-30 already records
the lock migration and purge binding). Held: the issue, the three requirements, the 2026-10-24
deadline. **Stale:** "payload change still to do" / "PR1".

**Property List (Phase 0.6b).**
- P1. After an erasure or provision completes, no file on the store carries the workspace id in its name or content, except the repository itself (`<id>.git`), which the erasure deletes.
- P2. The store-empty counters ignore the shared lock, legacy `.<id>.init.lock` residue, the boot probe's lock and `lost+found`, so `served_repos=0` stays true.
- P3. The legacy residue on the served store is gone (requirement 2; flip window; production write).
- P4. The legacy residue on the plaintext volume has a stated end, and the volume is never mounted to purge in place.

**Cut List (Phase 0.6b).**
- "PR1 payload change + rung-2 hash bookkeeping" → buys P1 → already covered by #9226 (constant name) and #9254 (evidence for that hash). CUT.
- "Delete `git-data-rung2-boot-evidence.env`" → only meaningful with a payload edit → CUT (would HOLD birth/replace for nothing).
- "Lock outside the repo root" → buys P1 → the constant name already satisfies P1; moving the lock adds a new path to the wrapper's mount-assertion chain. CUT.
- "Unlink the lock after use" → rejected by the wrappers' own measured fd-reuse race and pinned by T14. CUT.
- "Purge in place on the plaintext volume" → forbidden by the issue and ADR-239 D2. CUT.

**Institutional learnings applied.**
- `2026-09-27-a-read-only-proof-must-measure-with-the-writers-predicate-not-a-narrower-one.md` — the counters must use the writer's exclusion list; the verification record re-derives it by reading both predicates.
- `2026-09-11-the-gate-i-skipped-for-contention-hid-my-own-red-suite-and-two-rehearsals-attested-a-gc-that-never-ran.md` — never-unlink rationale; derive the consumer list from the tree.
- `2026-07-23-ci-guard-test-must-assert-enforcement-not-just-presence.md` and `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md` — mutate behavior, not text; fixtures must discriminate.
- `2026-10-05-i-told-the-operator-a-count-was-wrong-and-my-grep-had-counted-a-comment.md` — re-derive any count a doc states with a second method.

**CLO consult (this planning run).** Retention end: event-bound (the DL-2 destructive wipe of
`hcloud_volume.git_data`, tracked #6897) with the existing outer bound 2026-10-22 (ledger
`expires_on`, two days before the 2026-10-24 re-rule date); a slip re-opens the ADR, the ledger and
the CLO rather than extending quietly; never write "erased/purged" for the lock files or the volume
before the Hetzner delete has happened; same wording in ADR-239, runbook and Art. 30 PA-36 (f);
the `#5914` "not covered" line gets a dated addendum, not a rewrite; the 10.3(b) disclosure question
belongs to the 2026-10-24 re-ruling, so DPD / GDPR Policy are not touched.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "a lock that carries no subject identifier or does not outlive the operation" [brief] | Phase 1 (verified already satisfied on main) + Phase 2 (guard) | mapped |
| 2 | "this PR is PR1 (the payload change, with whatever hash/trigger bookkeeping that sequence requires)" [brief] | Research Reconciliation row 2; Phase 1 hash check | descoped — justification: the payload change already merged (#9226) and its evidence matches the current hash; editing a bound file would void the evidence. Recorded as a decision challenge (DC-1). |
| 3 | "do NOT do the PR2 step" [brief] | Non-Goals | mapped |
| 4 | "set the plaintext-volume retention end in ADR-239 and the LUKS cutover runbook (requirement 3, docs only)" [brief] | Phase 3 | mapped |
| 5 | "CLO-agent attestation per ship gate if a legal doc is touched" [brief] | Phase 4 (CLO attestation, Art. 30 PA-36 (f) marker) | mapped |
| 6 | "no purge of existing lock files on any store" [brief] | Non-Goals | mapped |
| 7 | "PR body: use Refs for #9066, #5914, #8211, #9377 and #8609 (never Closes" [brief] | Phase 4 | mapped |
| 8 | "Targeted test suites only" [brief] | Phase 2 verification commands | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 verification record | "a lock that carries no subject identifier" (ask 1) | asked |
| Phase 2 guard in the two test suites | "a lock that carries no subject identifier or does not outlive the operation" (ask 1) | inferred — justification: the property is only implied by T10/T13/T14; a revert to a per-id name plus a second residue file would pass today's rows, and the Art. 17 property is the issue's whole point |
| Phase 3 ADR-239 amendment + runbook | "set the plaintext-volume retention end in ADR-239 and the LUKS cutover runbook" (ask 4) | asked |
| Phase 3 Art. 30 PA-36 (f) superseded marker | — | inferred — justification: CLO consult: the register's retention cell states the retained-volume limb and would contradict the ADR otherwise; append-only marker, CLO-attested |
| Phase 3 runbook qualifiers on step (d) and the `not covered:` template | "Set its retention end in ADR-239 and the LUKS cutover runbook" (ask 4) | asked |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/infra` (tests), `knowledge-base/engineering` (ADR, runbook), `knowledge-base/legal` (register marker)
- Planned files: 6 | Estimated changed lines: ~200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The failure is a record that overstates erasure — a user whose account was deleted still has a file named with their account id on the git-data store, while the Art. 17 record says "no repository held; nothing to erase".
- **If this leaks, the user's identifier is exposed via:** a zero-byte file whose name is the user's `auth.users.id` on the git-data store or the retained plaintext volume (a holder of the volume or a Hetzner snapshot reads the id; no content, no email, no repository).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the CLO consult classifies this gap at the single-user tier (one user's id outliving their erasure) even though it is not a breach; `aggregate pattern` would understate a per-user right. `requires_cpo_signoff: true` is set accordingly.

## Implementation Phases

### Phase 1 — Verification record for requirement 1 (read-only)

Produce the evidence as one PR-body "Verified on main" block (the PR's `Refs #9066` links it; no separate issue comment). Every claim cites a content anchor, not a line number (cq-cite-content-anchor-not-line-number).

- Constant name in both wrappers: anchors `lock_file="${REPO_ROOT}/.init.lock"` in `apps/web-platform/infra/git-data-remove.sh` and `apps/web-platform/infra/git-data-provision.sh`; no `rm -f "$lock_file"` (T14 asserts it).
- No other writer puts the id on the store: the pre-receive fence lock is `$GIT_DIR/fence/<worktree_id>.lock` inside `<id>.git` (erased with it); `git-data-gc.sh` iterates `*.git` only; provision writes only `git init --bare "$repo_path"`.
- Counters: `_repo_count` case `d` in `git-data-bootstrap.sh` and the proof `find` in `git-data-cutover.sh` both read `! -name '.*.init.lock' ! -name '.init.lock' ! -name lost+found`; pinned by `git-data-bootstrap-store-verify.test.sh` S9 and the access suite.
- Purge (requirement 2 code, not run): `mode_freeze` step 4 in `git-data-cutover.sh` emits `purge count=<n>` only, excludes `.init.lock` and `.boot-probe-0.init.lock`, and refuses with `verdict=lock_held` (exit 5; 23 is only the inner subshell code) instead of racing a held lock.
- Hash bookkeeping is intact: `source tests/scripts/lib/git-data-birth-readiness-gate.sh; git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml` equals `RUNG2_TEMPLATE_SHA256` in `git-data-rung2-boot-evidence.env`.
- Live-host caveat (stated, not fixed): `user_data` is ForceNew; the running host serves the pre-#9226 wrappers until the next `git_data_host_replace`.

### Phase 2 — Regression guard for the property (tests only; not hash-bound)

Edit `apps/web-platform/infra/git-data-remove.test.sh` and `apps/web-platform/infra/git-data-provision.test.sh`. Neither is in the bound roster, so the rung-2 evidence is unaffected (AC1 proves it).

- Add a pure predicate `subject_id_leaks <root> <id>` that prints offenders (empty output = clean): (a) names: `find "$root" -mindepth 1 -name "*${id}*" ! -path "$root/${id}.git" ! -path "$root/${id}.git/*"`; (b) content: `grep -rlF --exclude-dir="${id}.git" -- "$id" "$root"`. Use an id token unlike any fixed filename (`uid-7f3a9c`; it passes the wrapper charset `[A-Za-z0-9._-]`). Name matching is on the basename, so a tmpdir containing the id cannot false-positive.
- Committed negative control (CI-enforced, no wrapper needed, ~ms): build fixture roots holding `.${id}.init.lock`, `.${id}.seen`, and an `.init.lock` whose content is the id; assert the predicate flags each. Must-PASS control: a root holding `.init.lock`, `.boot-probe-0.init.lock`, `lost+found`, another id's `<other>.git` and legacy `.<other>.init.lock` stays clean.
- Arms, two per suite: remove suite — remove-present and remove-absent (the "not present" erasure the issue calls out); provision suite — provision-new and provision-again. Each arm asserts rc=0, `<root>/.init.lock` exists (anti-vacuity) and the predicate is empty. Fixed number of assertions per arm (no loops, no conditional `pass`), then raise the floors (66 and 50 today) to the measured totals in the same diff.
- Wrapper-copy mutation runs (PR-body evidence only; CI enforcement is the committed negative control plus the floor): sed-edit a temp copy of each wrapper (`lock_file=` and `exec 9>` each occur once per wrapper), run the same arms with `WRAPPER=$copy`, restore `WRAPPER` afterwards (the C1i row greps `$WRAPPER`).
- After the edit, re-run `plugins/soleur/test/fixture-relative-assert.test.sh` and `fixture-dir-operand-assert.test.sh`; regenerate their row-by-row baselines with `--write-baseline` only if the rows added are the new ones. `suite-durations.tsv` only if the suite measurably moves (~0.6-0.9 s today).

### Phase 3 — Requirement 3: the plaintext-volume retention end (docs)

Wording rule from the CLO consult: say "destroyed" only after the Hetzner delete has happened; "targeted no later than" before it; never "erased/purged" for the lock files or the volume; conditional wording for the wipe PR ("fires on the merge of PR #N"). Draft rule (final text at work time):

> The residue on `hcloud_volume.git_data` (name-only `.<id>.init.lock` files from the pre-#9226 wrappers) ends when that volume is destroyed by the DL-2 destructive wipe (#6897): the Hetzner volume delete is the end event, recorded in the wipe PR's evidence (ADR-239 D2 "never writable" holds until destruction; the delete is the only terminal act, so the ADR does not describe a zeroing write). Target: no later than 2026-10-22 (the ledger `expires_on` for this store, two days before the 2026-10-24 re-rule date). A slip re-opens this ADR, the ledger and the CLO together; the date is not extended quietly. The volume is never mounted to purge in place (D2). The served LUKS store is a different limb, closed only by the in-freeze purge.

- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`: new dated amendment (2026-10-09), placed with the existing amendments, carrying the rule above, the requirement-1 status (constant lock on main, evidence hash current, host picks it up at the next replace) and the dependency that the wipe is itself a hash-bound PR with its own rung-2 rehearsal (existing Consequences bullet "The wipe branch needs a rehearsal of its own").
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`: (i) the opening paragraph's "retained read-only until its wipe decision (#6897/#8571)" gains the retention end; (ii) record-template addendum for the `not covered:` line (retained-volume limb bound to destruction, target 2026-10-22; served-store limb closed only by the freeze purge; counts only, no ids); (iii) step (d) gets a one-sentence qualifier that the quoted wrapper behavior is the pre-#9226 payload the running host serves until its next replace. Do not touch the verdict-map table rows (the access suite pins them).
- `knowledge-base/legal/article-30-register.md` PA-36 (f): append-only `> **Superseded 2026-10-09 (#9066): …**` marker under the retained-plaintext-residual sentence naming the lock-file residue class and the same retention end. CLO agent attests (ship gate).
- Legal sweep (done at plan time): `grep -rn "init.lock\|9066" knowledge-base/legal docs/legal` hits only Art. 30 PA-36 (g) (the `.*.init.lock` count exclusion, no tense claim about the lock name) and nothing in the counsel-review audits; PA-36 (f) is the one cell that states the retained-volume retention.
- Lint: run `scripts/lint-infra-no-human-steps.py` over the edited runbook/ADR (phrase destroy/wipe as the workflow or route doing it, not as a person).

### Phase 4 — Ship

PR body: `Refs #9066`, `Refs #5914`, `Refs #8211`, `Refs #9377`, `Refs #8609` — never `Closes`. Include: the Phase 1 verification block, the Decision Challenge DC-1, and a drafted `#5914` addendum text for the owner/CLO to post (this PR does not write to the closed #5914 record). The CLO agent attestation covers the Art. 30 marker. No `--admin` merge. Do not touch PR #9466. Push and let CI run the heavy battery.

## Guard Contract

### Guard 1 — no subject identifier on the store

**Property.** After a provision or remove arm completes (including the already-present and not-present no-op arms), no entry under the repo root other than `<id>.git` carries the workspace id in its name or content.

**Assembly.** The lock sites `exec 9>"$lock_file"` in `git-data-remove.sh` and `git-data-provision.sh`, plus `git init --bare "$repo_path"`; the chokepoint is the predicate `subject_id_leaks`, which quantifies over every entry name and every file's content under the root (not over the `.*.init.lock` glob), applied after each arm: remove-present and remove-absent in the remove suite, provision-new and provision-again in the provision suite. A future writer of any new name is caught by the listing.

**Mutation matrix.** (M1-M3 are encoded permanently as the committed negative control on fixture roots; M1, M3, M4 are also run against sed-edited wrapper copies as PR-body evidence. Every row MUST turn the arms or the control RED.)

| # | Mutation | Expected |
|---|----------|----------|
| M1 | revert the lock path to `${REPO_ROOT}/.${workspace_id}.init.lock` | RED (name carries id) |
| M2 | keep the compliant `.init.lock` AND add a second writer `: > "${REPO_ROOT}/.${workspace_id}.seen"` after it (second member after a compliant first) | RED — a check that stops at the first member, or that globs only `.*.init.lock`, stays green |
| M3 | keep the constant name but write the id into it: `printf '%s\n' "$workspace_id" >&9` (content, not name) | RED (content grep) |
| M4 | dispatch: exit 0 before `exec 9>` (the wrapper never touches the root) | RED (anti-vacuity: `.init.lock` must exist) |

**Harness rows.** H1: remove one arm's assertions from a suite → the floor, raised to the measured total with a fixed per-arm assertion count, reds the suite. H2 (must-PASS, non-canonical): the clean control root (`.init.lock`, `.boot-probe-0.init.lock`, `lost+found`, another id's `<other>.git` and legacy `.<other>.init.lock`) stays clean — the contract permits unrelated entries; the predicate is per-id. The canonical wrappers run GREEN first (control) before M1-M4 are scored.

**Anchor.** No stored value is compared; the only count is the suite's assertion floor, raised in the same diff, so deleting an arm reds on a floor edit visible in the merge-base diff.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-239 (`## Amendment 2026-10-09 — plaintext-volume retention end and lock-name status (#9066)`) via `soleur:architecture`: decision = the plaintext volume's residue is bounded by destruction of `hcloud_volume.git_data` (DL-2 wipe, #6897), target 2026-10-22, slip re-opens ADR + ledger + CLO. The amendment also says plainly that the wipe body was deleted from `git-data-cutover.sh` in #8189's PR (the wipe is a future hash-bound PR with its own rung-2 rehearsal), so the 2026-10-22 target is a target, and lists the three states the 2026-10-24 CLO re-ruling needs as input: wipe done (Hetzner delete evidence), wipe slipped, or flip slipped (so the wipe, which is gated behind the flip, has not been reached). Alternatives considered (add to the ADR's existing table): purge in place by mounting (rejected — violates D2 "never mounted"); a standalone dated purge (rejected — requires the writable mount); extend the date silently (rejected — storage limitation; ledger `expires_on_not_extended` precedent).

### C4 views

No C4 edit. Work-time task: read `model.c4`, `views.c4`, `spec.c4` in full (not a keyword grep) and confirm the enumeration below. (a) External human actors — none new (no new reader or sender). (b) External systems — none new (Hetzner volume, Better Stack and Sentry edges unchanged). (c) Container/data-store — `gitDataStore` already says the plaintext volume is RETAINED and never mounted; that stays true until the volume is destroyed, and the retention date lives in ADR-239 rather than being copied into a diagram description where it would rot. (d) Actor-to-surface access — unchanged. Run `plugins/soleur/test/c4-count-parity.test.sh` only if a `.c4` file ends up edited (none planned).

### Sequencing

The ADR describes the target state (volume destroyed) with "targeted" wording; nothing is postponed to a follow-up issue.

## Observability

```yaml
liveness_signal:
  what:            "the freeze-window 'purge count=<n>' annotation emitted by git-data-cutover.sh mode_freeze (requirement 2's count-only evidence); no new runtime surface is added by this PR"
  cadence:         "per flip dispatch"
  alert_target:    "git-data-cutover.yml run annotations and the existing cutover notify channel"
  configured_in:   "apps/web-platform/infra/git-data-cutover.sh (mode_freeze lock-purge step)"

error_reporting:
  destination:     "existing: the cutover verdict map (lock_held, probe_failed) in the runbook; unchanged by this PR"
  fail_loud:       "verdict=lock_held (exit 5; inner subshell code 23) when a legacy lock is held during the purge"

failure_modes:
  - mode:          "a wrapper regresses to a per-id lock name or writes the id elsewhere on the store"
    detection:     "the new assert_no_subject_id arms in git-data-remove.test.sh / git-data-provision.test.sh fail in the infra-validation CI job"
    alert_route:   "red CI on the PR / main"
  - mode:          "the retention end (2026-10-22) passes with the plaintext volume still present"
    detection:     "scripts/lint-encryption-posture.py hard-fails on the ledger exception once expires_on is in the past (the existing hcloud_volume.git_data row)"
    alert_route:   "red encryption-posture lint in CI"

logs:
  where:           "GitHub Actions run annotations for the cutover; CI job logs for the suites"
  retention:       "GitHub Actions default retention"

discoverability_test:
  command:         grep -c purge.count= apps/web-platform/infra/git-data-cutover.sh
  expected_output: "1"
```

## Domain Review

**Domains relevant:** Legal, Engineering

### Legal (CLO)

**Status:** reviewed
**Assessment:** Retention end event-bound to the DL-2 wipe with the existing outer bound 2026-10-22; slip re-opens ADR, ledger and CLO; no "erased/purged" wording for the volume or lock files; same wording in ADR-239, runbook and Art. 30 PA-36 (f); `#5914` "not covered" gets a dated addendum, not a rewrite; DPD / GDPR Policy untouched pending the 2026-10-24 re-ruling; attestation recorded to `knowledge-base/legal/audits/` at ship.

### Product (CPO sign-off, `requires_cpo_signoff`)

**Status:** reviewed — signed off 2026-10-09, no blocking changes
**Assessment:** Not editing the bound payload is right; test-only guard, docs-only retention end and no production write fit the threshold. Conditions carried: no user-facing erasure claim may imply the residue is gone until the host is replaced and the volume destroyed; do not claim zero residue beyond the destroyed device (Hetzner snapshots unmeasured); put the 2026-10-22 slip rule in the PR body; keep the #5914 addendum as drafted PR-body text for the owner to post.

### Engineering (CTO lens, carried from the issue and ADR-239)

**Status:** reviewed
**Assessment:** Hash-bound payload stays untouched (evidence hash verified current); the guard lives in unbound test files; the live-host replace and the in-freeze purge remain owner-authorized production actions outside this PR.

## GDPR / Compliance Gate

Triggers: (b) brand-survival `single-user incident` declared. Surface: infra test files and retention docs (no schema/auth/API/SQL). `soleur:gdpr-gate` runs against this plan at deepen time; advisory only. Mandated-By: hr-gdpr-gate-on-regulated-data-surfaces.

## Encryption Posture

No new store and no new connection. The one store in scope is existing and already ledgered; this PR restates its posture and edits no `.tf`, cloud-init or ledger file.

```yaml
at_rest:
  - store: hcloud_volume.git_data   # the retained plaintext ext4 volume
    mechanism: plaintext-exception
    evidence: "scripts/encryption-posture-ledger.json, store hcloud_volume.git_data (format = ext4, no LUKS apparatus); never mounted after boot, read once per instance through a kernel-read-only dm snapshot (ADR-239 D2)"
    defends_against: "nothing at the volume layer; the volume is detached from serving and holds only name-only legacy lock residue"
    does_not_defend: "a seized or snapshotted disk exposes any data still resident on this volume, including the legacy .<id>.init.lock names (auth.users.id)"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable: Hetzner snapshots of the volume are unmeasured (Art. 30 PA-36 (f) already says so); the boot's plaintext_empty count covers entries, not freed blocks"
in_transit: []   # no new connection
exception:
  justification: "retained plaintext rollback backstop pending the DL-2 wipe (#6897); residue bounded by destruction of the volume"
  tracking_issue: "#6897"
  reevaluate_when: "the DL-2 wipe's Hetzner volume delete is recorded, or 2026-10-22 passes (slip rule: re-open ADR-239, the ledger and the CLO)"
  expires_on: "2026-10-22"
```

## Open Code-Review Overlap

None. (Queried open `code-review` issues against every planned path and the two payload names: zero hits.)

## Files to Edit

- `apps/web-platform/infra/git-data-remove.test.sh`
- `apps/web-platform/infra/git-data-provision.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/legal/article-30-register.md` (PA-36 (f), append-only marker; CLO-attested)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` and the sibling operand baseline — only if the new operands change the scanned rows (regenerated by the suite's `--write-baseline`)

Verified: every path above exists on `origin/main` (`git ls-files`); no glob prescribed.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9066-git-data-lock-no-subject-id/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9066-git-data-lock-no-subject-id/decision-challenges.md`
- `knowledge-base/legal/audits/2026-10-counsel-attestation-9066.md` (CLO agent output at ship; append-only record)

Files that must NOT appear in the PR diff (the hash-bound set and the evidence file; the list below is illustrative, AC1 derives the real one): `apps/web-platform/infra/cloud-init-git-data.yml`, `modules/git-data-userdata/{main,outputs,variables}.tf`, `git-data-{bootstrap,gc,provision,remove,transport-wrapper,pre-receive}.sh`, the gc and luks-reopen units, and `git-data-rung2-boot-evidence.env`. Also not `.github/workflows/**`, `git-data-cutover.sh`.

## Non-Goals

- Requirement 2: measuring or purging lock files on any store (production write; owner's explicit per-step authorization; leave to #9066).
- The PR2 step, a host replace, a flag flip, key rotation, a workflow dispatch, a ruleset change.
- The DL-2 wipe itself (#6897) and copy mode (#8571) — separate hash-bound work; this PR only states the retention end that the wipe satisfies.
- DPD §10.3(b) / GDPR Policy edits — the 2026-10-24 CLO re-ruling.
- #9394 (the owner's decision), PR #9466 and its worktree, the main checkout's `.mcp.json`.

## Post-Merge Hand-Off (owner-authorized; NOT taken by this PR)

The docs and this PR are only true end to end after a chain that this PR neither performs nor schedules. The chain, in order, with its evidence: (1) a `git_data_host_replace` onto the #9226 payload (until then the running host's wrappers still write `.<id>.init.lock` onto the LUKS store); (2) the flip's freeze window, whose purge publishes `purge count=<n>` (count only) and refuses `lock_held` rather than racing — on `lock_held` the runbook's existing recovery applies and the freeze is cleared by `MODE=unfreeze` before a re-run; (3) the DL-2 wipe PR (#6897; hash-bound, own rung-2 rehearsal; the wipe body does not exist on main today) and the Hetzner volume delete. #9066 closes only when the purge count, the replace run and the wipe evidence are each recorded; the owner closes it. The tripwire for a slip is the existing ledger lint (warns inside 14 days, hard-fails CI after 2026-10-22); the slip rule is: re-open ADR-239 and the ledger together and ask the CLO before 2026-10-24 — it goes in the PR body. A dated follow-through enrollment is deliberately not added: its probe would need Hetzner API credentials, which this run may not use without asking.

## Acceptance Criteria

- [ ] AC1. No hash-bound file or evidence file is in the diff. Capture first, validate, then compare (a failed call must not read as a pass): `files=$(bash -c 'source tests/scripts/lib/git-data-birth-readiness-gate.sh; git_data_rung2_bound_files apps/web-platform/infra/cloud-init-git-data.yml') && [ "$(printf '%s\n' "$files" | wc -l)" -eq 17 ] && printf '%s\n' "$files" | xargs -n1 realpath -e --relative-to=. >/dev/null && comm -12 <(git diff --name-only origin/main...HEAD | sort) <(printf '%s\n' "$files" | xargs -n1 realpath --relative-to=. | sort)` exits 0 and prints nothing (verified at plan time: 17 paths all resolve, empty intersection); the diff neither deletes nor modifies `apps/web-platform/infra/git-data-rung2-boot-evidence.env`.
- [ ] AC2. The evidence hash still matches: `git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml` equals `RUNG2_TEMPLATE_SHA256` in the evidence file.
- [ ] AC3. `bash apps/web-platform/infra/git-data-remove.test.sh` and `bash apps/web-platform/infra/git-data-provision.test.sh` pass with the raised floors; the committed negative control flags M1-M3-shaped fixtures and stays clean on the must-PASS root; the wrapper-copy runs of M1, M3, M4 are RED (pasted in the PR body as evidence).
- [ ] AC4. ADR-239 has the 2026-10-09 amendment with the retention rule, the no-wipe-implementation statement and the three re-ruling states; the runbook intro, record template and step (d) qualifier carry the matching text; both contain `2026-10-22` and `never mounted`. Checkable wording rule: `git diff -U0 origin/main...HEAD -- <ADR> <runbook> <register> | grep '^+' | grep -iE '(volume|lock files?)[^.]{0,40}(was|is|were|been) (erased|purged|wiped)'` prints nothing; CLO attestation reviews the rest.
- [ ] AC5. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` reports no new finding; the access suite's runbook-parity case (`case_rb`) is unaffected (verdict-map rows untouched).
- [ ] AC6. Art. 30 PA-36 (f) (the retained-plaintext-residual sentence) carries the append-only Superseded marker, and the CLO attestation file exists under `knowledge-base/legal/audits/` and states its conclusion before PR-ready.
- [ ] AC7. PR body uses `Refs` only for #9066, #5914, #8211, #9377, #8609; contains the Phase 1 verification block, DC-1 and the slip rule; #9066 stays open.
- [ ] AC8. No production write, no workflow dispatch, no edit under `.github/workflows/`, no Doppler/Better Stack/Supabase credential use.

## Risks and Sharp Edges

- A comment-only edit to a bound payload still changes the hash: do not "tidy" the `#9066` comments in the wrappers.
- The Art. 30 register is append-only: a superseded marker, never an in-place rewrite.
- The 2026-10-22 target depends on the flip chain (#8573, #8609, #8209, a fresh replace) and on a wipe PR that does not exist yet; 13 days is tight and the docs say so. The ledger lint is the mechanical tripwire; see Post-Merge Hand-Off.
- Hetzner-side snapshots/backups of the plaintext volume are unmeasured (Art. 30 PA-36 (f) already says so); the docs must not claim zero residue beyond the destroyed device.
- Suite floors are tight to current counts (66, 50); a partial run must not look green.
- A `## User-Brand Impact` section that is empty or placeholder fails deepen-plan Phase 4.6; this one is filled.
