---
title: "Tasks — runbook SSH split, legal off-host claims, Art. 30 PA8 bound, register-lint promotion"
branch: feat-one-shot-7874-7786-6474-7787-runbook-ssh-legal-registers
plan: knowledge-base/project/plans/2026-09-07-fix-runbook-ssh-split-and-legal-register-claims-plan.md
lane: cross-domain
---

# Tasks

Derived from the finalized plan. Phase order is a dependency order, not a preference:
Phase 0 must land before Phase 1 (the renames depend on the carve reaching fences), and
**Phase 6 is last and is its own terminal commit** (the revert unit).

## Phase 0 — make the sanctioned heading work

- [ ] 0.1 Add `_is_last_resort_heading(title)` carrying the existing `Last-resort diagnosis`
      regex verbatim; leave `_is_carve_heading`'s two arms unchanged so `Resolved` behaviour
      is untouched.
- [ ] 0.2 Track `carve_last_resort`. ASSIGN inside the `if _is_carve_heading` branch
      (`carve_last_resort = _is_last_resort_heading(title)`), clear in the `elif`. Do NOT OR it:
      a `## Last-resort diagnosis` → `## Resolved` adjacency skips the `elif` and would leak the
      carve. Guard 1 row 7 pins this.
- [ ] 0.3 Gate the in-fence host-login exception:
      `if HOST_LOGIN_RE.search(raw) and not carve_last_resort:`.
- [ ] 0.4 Add Guard 1's fixtures to `scripts/lint-infra-no-human-steps.test.sh`: F-a (fenced
      host-login under `## Resolved` -> rc=1), F-b (PROSE host-login under a last-resort heading
      -> rc=0), F-c (ignore-region-wrapped fence with a host-login -> rc=0), plus the must-PASS
      level-4 suffixed-heading case. Without F-a/F-b/F-c, rows 2/3/6 are GREEN.
- [ ] 0.5 RAISE `MIN_CASES` (currently 51, exactly pinned) to the new exact TOTAL in the same
      edit. The harness DOES have a floor; adding cases without raising it gives it slack and
      disarms harness row (a).
- [ ] 0.7 Pin `_is_carve_heading` and `_is_last_resort_heading` to the same literal.
- [ ] 0.8 Make full-scan mode fail-closed: zero collected files exits 2, not `OK ... 0 scanned`.
- [ ] 0.6 Capture the `main` baseline finding set over all `SCAN_DIRS` before any runbook edit
      (needed by AC3).

## Phase 1 — the two SSH-diagnosis runbooks

- [ ] 1.1 Rename `### Step R3 -- Verify` → `### Last-resort diagnosis (SSH channel, after the
      no-SSH probes) — Step R3: confirm SSH is restored` (`admin-ip-drift.md`). Title must BEGIN
      with the literal; the parenthetical is regex-safe and matches house convention.
- [ ] 1.2 Rename `### Step 6: Verify from the operator machine` → `### Last-resort diagnosis
      (SSH channel — not the noVNC channel of last resort) — Step 6: confirm SSH is restored`
      (`ssh-fail2ban-unban.md`).
- [ ] 1.3 Add the reader-visible sentence per renamed section. It must OPEN by naming the
      section terminal ("not an entry point — do not start here"), then carry the precondition
      and the no-SSH probes. Plus the per-file disambiguation: `ssh-fail2ban-unban.md` (probe vs
      the noVNC channel of last resort; escalation is `## If This Runbook Does Not Work`) and
      `admin-ip-drift.md` (distinct from `# Last-resort fallback:` in Diagnosis Step 1).
- [ ] 1.4 Wrap each `## Symptom` fence in a `lint-infra-ignore` region (block markers are safe
      around a fence), rationale on the start marker, class (b-transcript), owner #7874.
- [ ] 1.5 Add three INLINE SAME-LINE markers (plan Phase 1.3) for the class-(a) prose findings in
      `admin-ip-drift.md`. Never one region. Rationale names #6806 + the same-PR removal
      instruction + why the marker exists (whole-file scan).
- [ ] 1.6 Post the #6806 comment (plan Phase 1.4) naming the three markers by file + content anchor and the
      same-PR coupling. This is the removal trigger.

## Phase 2 — grok provisioning debt

- [ ] 2.1 File the deferral issue (`domain/engineering`, `type/chore`, `priority/p3-low`,
      milestone `Post-MVP / Later`) with the binding-rule verdicts, the two candidate
      remediations, the re-evaluation trigger, and the region re-triage note.
- [ ] 2.2 Wrap `### Bootstrap (after OS is up)`'s fence in a region naming that issue.
      Do NOT rename the heading — this is provisioning, not a last-resort diagnosis.

## Phase 3 — published corpus (six files + DPA template)

- [ ] 3.1 Renumber §2.3(m)'s outer `(i)`/`(ii)` to `(A)`/`(B)`; leave the inner Better Stack
      `(i)`/`(ii)` alone.
- [ ] 3.2 Sweep the SIX sites citing the inner numbering: `privacy-policy.md` §5.14 + mirror,
      `gdpr-policy.md` §3.7 + mirror, the register's Better Stack vendor row, register PA8 §(d),
      `compliance-posture.md`, and the DPA template's Schedule 2 note.
- [ ] 3.3 Retire the off-host claim in all six files with the affirmative one-sentence
      replacement; retire "rolling Docker log buffer"; carry both dates (2026-06-02 / #4786 for
      the application stream, 2026-05-21 / #4279 for the host plane).
- [ ] 3.4 Retire the 30 MB claim in the four files that carry it.
- [ ] 3.5 Attribute pseudonymisation to the APPLICATION (pino), not to Vector. Measured live:
      the shipped record carries `pii_scrub_applied: "drop_userdata+string"` — no `+structured`,
      because the HMAC transform short-circuits on `if !exists(parsed_obj.userIdHash)`. Keep the
      separate `soleur-registry` carve-out (no Vector, no `userIdHash` at all).
- [ ] 3.6 Re-ground "under processor-DPA terms" on the register's three limbs; conclusion
      untouched. Do NOT touch #7851's other two statements.
- [ ] 3.7 Sweep `AC15 of PR #4293` → **#7529** at all four sites.
- [ ] 3.8 Add a Better Stack row to DPD §4.2 (or repoint `gdpr-policy.md` §3.7).
- [ ] 3.9 (plan Phase 3.5d) Correct `data-processing-agreement-template.md` — SEVEN sites:
      Schedule 4 items 9/11/12/16, §8.3, Schedule 2's retention cell, and the Schedule 2
      reconciliation note that 3.5c falsifies.
- [ ] 3.13 Add a one-line operational-log retention entry to `privacy-policy.md` §7 and
      `gdpr-policy.md` §8.5.
- [ ] 3.10 Correct `betterstack-log-query.md`'s "tracked as a follow-up infra task" bullet.
- [ ] 3.11 Carry `[DRAFT — pending CLO/counsel review per #7786]` markers on edited clauses.
- [ ] 3.12 Bump `Last Updated` in NINE places (3 canonical body + 3 mirror hero + 3 mirror body); refresh three `LEGAL_DOC_SHAS` literals; correct
      `tc-version-bump-policy.md` §"Body-equivalence scope". Do NOT enrol the three docs in
      `BODY_EQUIVALENCE_DOCS`. Do NOT bump `TC_VERSION`.

## Phase 4 — Art. 30 register + trigger lists + accountability

- [ ] 4.1 PA8 §(f) additive dated bracket: retract the misattribution at both §(f) sites, state
      the redirect (#4786 → #4800) and the gap window, preserve `NOT RECORDED`, re-anchor to
      `assert "SystemMaxUse=1G"` + the `infra-validation.yml` step name. No volume figure.
- [ ] 4.2 Correct the THIRD site: PA8 §(b) limb (vi) — figure and the `post-PR #4279` date — AND
      the wrong date inside §(f)'s own Better Stack limb.
- [ ] 4.3 Bring both trigger lists to PARITY: add trigger 5 (`journald-soleur.conf`) to each,
      fold #7772's two per-source triggers into the runbook's numbered list, and RE-SCOPE trigger
      2 (it anchors on the json-file daemon block this PR retracts as non-governing).
- [ ] 4.4 Lockstep `recover-userid-from-pino-stdout.md`'s two descriptions of the register claim.
- [ ] 4.5 Add the `compliance-posture.md` Active Items row; anchor on trigger numbering, not
      trigger text.
- [ ] 4.6 CLO attestation via the `clo` agent, with `tier_classification: Tier 1`, AND
      discharging the `re_evaluation_triggers` entry in `2026-09-counsel-review-7717.md` that
      names the #7787 promotion — Phase 6 fires it.
- [ ] 4.7 In the SAME commit: add the attestation's `NOT_TRANSCRIBED` waiver (with a citing
      `#NNNN`) to `scripts/lint-legal-registers.sh` AND its `## Excluded records` parity row in
      `knowledge-base/legal/breach-register.md`.

## Phase 5 — durability

- [ ] 5.1 Extend `FORBIDDEN` with the FIVE retired phrasings — including
      `rolling Docker log buffer` AND `fixed-capacity Hetzner-local rolling buffer` (the second
      gdpr-policy occurrence carries none of the other literals).
- [ ] 5.2 Promote `REQUIRED` to a list; add the affirmative Better Stack anchor so deletion
      cannot pass.
- [ ] 5.3 (plan Phase 5.2) Add the checked-count floor using ABSOLUTE literals
      (`MIN_SURFACES=2`, `MIN_DOCS=3`, `checked >= 6`) — never `== len(SURFACES)*len(DOCS)`,
      which `DOCS=[]` satisfies at 0==0. Print the count beside `CORPUS-OK`.
- [ ] 5.4 (plan Phase 5.3) Register `run_suite "scripts/probe-legal-corpus-truth-live"` in `scripts/test-all.sh`
      with the deviation comment naming Phase 8.2 as the unit-arm owner.
- [ ] 5.4b (plan Phase 5.3b) Add `"scripts/probe-legal-corpus-truth.sh"` to `REQUIRED_RUNNERS`
      in `scripts/lint-orphan-test-suites.sh` and raise its floor from `< 6` to `< 7`. Without
      this the wiring is a one-line disarm and Guard 2 row 6 is GREEN.
- [ ] 5.5 (plan Phase 5.4) Pre-author the waiver + parity row for any `/ship` Phase 5.5 counsel-review file.

## Phase 6 — the promotion (LAST, own terminal commit)

- [ ] 6.1 Re-run `bash scripts/lint-legal-registers.sh` over the tree with all Phase 4/5
      artifacts COMMITTED; confirm rc=0 and `waiver-parity=ok` before touching the flag.
- [ ] 6.2 Delete the trailing `--advisory` token together with its leading space.
- [ ] 6.3 Rewrite the `# ADVISORY FOR ONE MERGE CYCLE (#7717)` comment block.
- [ ] 6.4 Append the remedy line to the `MIN_CHECKS` failure message.
- [ ] 6.5 Record the five hazards in the PR body; name this commit as the revert unit.

## Phase 7 — C4 lockstep

- [ ] 7.1 Amend the Vector `hetzner -> betterstack` edge label (identify by content anchor —
      two edges share the endpoints).
- [ ] 7.2 Amend the `betterstack` element description to name the application container's
      pino WARN+ stream.
- [ ] 7.3 Add one clause to `inngest -> betterstack` saying what it does not carry.
- [ ] 7.4 Regenerate `model.likec4.json` (c4-model-freshness.test.sh byte-diffs it; the KB C4
      route serves it to users).

## Phase 8 — follow-ups (file, do not inline)

- [ ] 8.1 Carve/fence suppression precedence, generalised (ADR-132 class).
- [ ] 8.2 Unit arm for the corpus-truth probe.
- [ ] 8.3 Narrow `lint-legal-registers.sh` predicate (c) on frontmatter `type:`.
- [ ] 8.4 grok GEX44 IaC birth path (filed in 2.1).
- [ ] 8.5 `harvest-debt` cannot see in-place deferrals in `*.md`.
- [ ] 8.6 Make a re-verification trigger actually fire (the Art. 5(2) defect).
- [ ] 8.7 Model the application → Better Stack relationship in C4.
- [ ] 8.8 Rebuild the retention sections per processor.
- [ ] 8.9 Name Better Stack + Sentry in the International Data Transfers sections.
- [ ] 8.10 Bring the DPA template inside the corpus-truth probe's scope, or own the gap.

## Verification

- [ ] V1 Acceptance criteria AC1–AC26 (see the plan). AC3, AC6, AC6b, AC15, AC18b, AC21 and
      AC22 are the ones that catch this PR's specific failure modes.
- [ ] V2 `bash scripts/test-all.sh` green. Prefix vitest invocations with
      `env -u GIT_DIR -u GIT_WORK_TREE`.
- [ ] V3 Every diff assertion uses `git diff "$(git merge-base origin/main HEAD)"`.
