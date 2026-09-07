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
- [ ] 0.2 Track `carve_last_resort` alongside `carve` / `carve_level`, set only by the
      last-resort arm, cleared by the same `level <= carve_level` rule.
- [ ] 0.3 Gate the in-fence host-login exception:
      `if HOST_LOGIN_RE.search(raw) and not carve_last_resort:`.
- [ ] 0.4 Add Guard 1's fixtures to `scripts/lint-infra-no-human-steps.test.sh`, including the
      must-PASS non-canonical case (level-4, suffixed heading) and both harness rows.
- [ ] 0.5 Add a case-count floor to that harness — it has none today.
- [ ] 0.6 Capture the `main` baseline finding set over all `SCAN_DIRS` before any runbook edit
      (needed by AC3).

## Phase 1 — the two SSH-diagnosis runbooks

- [ ] 1.1 Rename `### Step R3 -- Verify` → `### Last-resort diagnosis — Step R3: verify SSH is
      restored` (`admin-ip-drift.md`). Title must BEGIN with the literal.
- [ ] 1.2 Rename `### Step 6: Verify from the operator machine` → `### Last-resort diagnosis —
      Step 6: verify from the operator machine` (`ssh-fail2ban-unban.md`).
- [ ] 1.3 Add one reader-visible sentence per renamed section: the "after 3 tries" precondition,
      the no-SSH probes to exhaust first, and — in `ssh-fail2ban-unban.md` — a line
      distinguishing this from its "Channel of last resort: Hetzner Cloud Console (noVNC)"
      header.
- [ ] 1.4 Wrap each `## Symptom` fence in a `lint-infra-ignore` region (block markers are safe
      around a fence), rationale on the start marker, class (b-transcript), owner #7874.
- [ ] 1.5 Add three INLINE SAME-LINE markers for the class-(a) prose findings in
      `admin-ip-drift.md`. Never one region. Rationale names #6806 + the same-PR removal
      instruction + why the marker exists (whole-file scan).
- [ ] 1.6 Post the #6806 comment naming the three markers by file + content anchor and the
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
- [ ] 3.2 Sweep the three sites citing the inner numbering (+ mirrors): `privacy-policy.md`
      §5.14, the register's Better Stack vendor row, `gdpr-policy.md` §3.7.
- [ ] 3.3 Retire the off-host claim in all six files with the affirmative one-sentence
      replacement; retire "rolling Docker log buffer"; carry both dates (2026-06-02 / #4786 for
      the application stream, 2026-05-21 / #4279 for the host plane).
- [ ] 3.4 Retire the 30 MB claim in the four files that carry it.
- [ ] 3.5 Scope the pseudonymisation claim to the Vector paths (the `soleur-registry` shipper
      computes no `userIdHash`).
- [ ] 3.6 Re-ground "under processor-DPA terms" on the register's three limbs; conclusion
      untouched. Do NOT touch #7851's other two statements.
- [ ] 3.7 Sweep `AC15 of PR #4293` → **#7529** at all four sites.
- [ ] 3.8 Add a Better Stack row to DPD §4.2 (or repoint `gdpr-policy.md` §3.7).
- [ ] 3.9 Correct `data-processing-agreement-template.md` Schedule 4 items 9/11/12 and §8.3.
- [ ] 3.10 Correct `betterstack-log-query.md`'s "tracked as a follow-up infra task" bullet.
- [ ] 3.11 Carry `[DRAFT — pending CLO/counsel review per #7786]` markers on edited clauses.
- [ ] 3.12 Bump `Last Updated` in six places; refresh three `LEGAL_DOC_SHAS` literals; correct
      `tc-version-bump-policy.md` §"Body-equivalence scope". Do NOT enrol the three docs in
      `BODY_EQUIVALENCE_DOCS`. Do NOT bump `TC_VERSION`.

## Phase 4 — Art. 30 register + trigger lists + accountability

- [ ] 4.1 PA8 §(f) additive dated bracket: retract the misattribution at both §(f) sites, state
      the redirect (#4786 → #4800) and the gap window, preserve `NOT RECORDED`, re-anchor to
      `assert "SystemMaxUse=1G"` + the `infra-validation.yml` step name. No volume figure.
- [ ] 4.2 Correct the THIRD site: PA8 §(b) limb (vi) — figure and the `post-PR #4279` date.
- [ ] 4.3 Bring both trigger lists to PARITY: add trigger 5 (`journald-soleur.conf`) to each,
      and fold #7772's two per-source triggers into the runbook's numbered list.
- [ ] 4.4 Lockstep `recover-userid-from-pino-stdout.md`'s two descriptions of the register claim.
- [ ] 4.5 Add the `compliance-posture.md` Active Items row; anchor on trigger numbering, not
      trigger text.
- [ ] 4.6 CLO attestation via the `clo` agent to `knowledge-base/legal/audits/`.
- [ ] 4.7 In the SAME commit: add the attestation's `NOT_TRANSCRIBED` waiver (with a citing
      `#NNNN`) to `scripts/lint-legal-registers.sh` AND its `## Excluded records` parity row in
      `knowledge-base/legal/breach-register.md`.

## Phase 5 — durability

- [ ] 5.1 Extend `FORBIDDEN` with the four retired phrasings (including
      `rolling Docker log buffer`).
- [ ] 5.2 Promote `REQUIRED` to a list; add the affirmative Better Stack anchor so deletion
      cannot pass.
- [ ] 5.3 Add the checked-count floor; print the count beside `CORPUS-OK`.
- [ ] 5.4 Register `run_suite "scripts/probe-legal-corpus-truth-live"` in `scripts/test-all.sh`
      with the deviation comment naming Phase 8.2 as the unit-arm owner.
- [ ] 5.5 Pre-author the waiver + parity row for any `/ship` Phase 5.5 counsel-review file.

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

## Phase 8 — follow-ups (file, do not inline)

- [ ] 8.1 Carve/fence suppression precedence, generalised (ADR-132 class).
- [ ] 8.2 Unit arm for the corpus-truth probe.
- [ ] 8.3 Narrow `lint-legal-registers.sh` predicate (c) on frontmatter `type:`.
- [ ] 8.4 grok GEX44 IaC birth path (filed in 2.1).
- [ ] 8.5 `harvest-debt` cannot see in-place deferrals in `*.md`.
- [ ] 8.6 Make a re-verification trigger actually fire (the Art. 5(2) defect).
- [ ] 8.7 Model the application → Better Stack relationship in C4.

## Verification

- [ ] V1 Acceptance criteria AC1–AC26 (see the plan). AC3, AC6, AC15, AC18b, AC21 and AC22 are
      the ones that catch this PR's specific failure modes.
- [ ] V2 `bash scripts/test-all.sh` green. Prefix vitest invocations with
      `env -u GIT_DIR -u GIT_WORK_TREE`.
- [ ] V3 Every diff assertion uses `git diff "$(git merge-base origin/main HEAD)"`.
