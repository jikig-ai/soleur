---
title: "Tasks — reconcile inngest-volume-recut against the completed cutover"
branch: feat-one-shot-7695-recut-postcutover-reconcile
plan: knowledge-base/project/plans/2026-09-18-chore-inngest-recut-postcutover-reconcile-plan.md
closes: [7695, 8017, 8015]
refs: [8078, 7777, 8018, 8316, 8285, 6894]
lane: cross-domain
brand_survival_threshold: none
---

# Tasks: reconcile inngest-volume-recut against the completed cutover

Derived from the plan above. **Read the plan first** — every "why", the measured live state, the
per-issue evidence and the paste-ready runbook callout live there; this file carries only steps.
Tick a box only after running its check in this session.

## Phase 0: Preconditions (measure, do not assume)

- [ ] 0.1 Re-run the four live reads (Better Stack `SOLEUR_INNGEST_SERVER_PROBE` newest dedicated row;
      Doppler `soleur-inngest/prd` `INNGEST_CUTOVER_FLIP` + `INNGEST_DIAGNOSTIC_BOOT`; Hetzner
      `GET /volumes/106261946` + `GET /servers?name=soleur-inngest`;
      `scripts/followthroughs/inngest-host-not-serving-7674.sh`) and paste them verbatim into
      `knowledge-base/project/specs/feat-one-shot-7695-recut-postcutover-reconcile/measurements.md`.
      **STOP** if `cutover_flag != done`, `redis_keys == 0`, volume id ≠ `106261946`,
      `probe_schema != 8`, `data_mount_devid != scsi-0HC_Volume_106261946`, `registry_fns` absent/0,
      or the #7674 probe rc ≠ 0.
- [ ] 0.2 `gh pr diff 8248 --name-only` captured for AC12.
- [ ] 0.3 `archive-kb.sh --dry-run` for the four slugs (`infra-inngest-volume-recut-luks`,
      `one-shot-7695-inngest-volume-recut-luks`, `fix-inngest-bootstrap-pin-and-guard-hardening`,
      `one-shot-7695-inngest-image-pin-probe-schema`) — exactly one artifact each.
- [ ] 0.4 `bash plugins/soleur/test/c4-count-parity.test.sh` → exit 0.
- [ ] 0.5 Re-measure the `- [ ]` counts of the two spec `tasks.md` files (plan-time: 26 / 40).

## Phase 1: Runbook (`knowledge-base/engineering/operations/runbooks/inngest-server.md`)

- [ ] 1.0 Strike the superseded sentence where it is read (`~~…~~` + "superseded 2026-09-18" note,
      anchor text byte-intact); rewrite the `The latch clears only when` remediation sentence with
      the precondition (measured-empty store) before the mechanism, keeping `op=resume` is not it.
- [ ] 1.1 Prefix the 2026-08-25 blockquote's lazy-continuation lines with `> `, then insert the
      paste-ready callout from plan § Phase 1.1c after them (G19 first; rollback is one-way;
      `FLUSH_LATCH_SINCE` has no application; "dormant on this volume", never "retired").
- [ ] 1.2 Add the Quick-reference row (plan § Phase 1.2).
- [ ] 1.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` → `OK`.

## Phase 2: ADR-100 addendum (append-only)

- [ ] 2.1 Append `## Addendum — 2026-09-18 (#7695) — the recut target exists, and is dormant on the
      volume the cutover landed on` per plan § Architecture Decision (five items; G8 worded as the
      #8078 predicate so the file agrees with its own 2026-09-11 §7; `Ref #8285`).
- [ ] 2.2 `git diff origin/main -- <ADR-100>` shows additions only.

## Phase 3: Reconcile and archive the `issue: 7695` plan/spec pairs

- [ ] 3.1 Append the reconciliation addendum to the 2026-09-02 plan (P1–P10 superseded; two replaces
      since for other reasons; P2 met but unconsumed; P9/P10 belong to the ADR-142 path).
- [ ] 3.2 Archive the four artifacts with `archive-kb.sh <slug>` (spec dirs and the 09-07 plan
      unchanged — no notes, no ticking).
- [ ] 3.3 AC5–AC8 checks (history preserved, byte-identical archived specs, 09-10 pair untouched).

## Phase 4: GitHub records

- [ ] 4.1 `gh issue view 8316 --json state` → OPEN (already filed; do not file a second).
- [ ] 4.2 Comments + relabels: #8078 (p1→p3, link #8316), #7777 (bound scope, clause-2 cross-link,
      `domain/legal` → `domain/engineering`); edit #8316 body (`Ref #8285`, ADR-199 §Consequences
      anchor, G8 wording); one comment on PR 8248 naming #8316. No comment on #8018.
- [ ] 4.3 Verdict comments on #7695, #8017, #8015 quoting `measurements.md` fields, each ending
      "closes on merge of PR #8314".
- [ ] 4.4 Draft PR body; `grep -oE 'Closes #[0-9]+' <draft> | sort -u` → exactly 7695/8015/8017
      BEFORE `gh pr edit --body`; then `gh pr view 8314 --json closingIssuesReferences` → the three.
      Body names the INDEX.md / kb-tags.txt overlap with PR 8248.

## Phase 5: Verification

- [ ] 5.1 AC1–AC14 from the plan, each run and recorded.
- [ ] 5.2 `bash scripts/test-all.sh` at the /ship full-battery checkpoint.
