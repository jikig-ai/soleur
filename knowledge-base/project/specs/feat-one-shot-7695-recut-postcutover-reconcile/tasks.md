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

- [x] 0.1 Re-run the four live reads (Better Stack `SOLEUR_INNGEST_SERVER_PROBE` newest dedicated row;
      Doppler `soleur-inngest/prd` `INNGEST_CUTOVER_FLIP` + `INNGEST_DIAGNOSTIC_BOOT`; Hetzner
      `GET /volumes/106261946` + `GET /servers?name=soleur-inngest`;
      `scripts/followthroughs/inngest-host-not-serving-7674.sh`) and paste them verbatim into
      `knowledge-base/project/specs/feat-one-shot-7695-recut-postcutover-reconcile/measurements.md`.
      **STOP** if `cutover_flag != done`, `redis_keys == 0`, volume id ≠ `106261946`,
      `probe_schema != 8`, `data_mount_devid != scsi-0HC_Volume_106261946`, `registry_fns` absent/0,
      or the #7674 probe rc ≠ 0.
- [x] 0.2 `gh pr diff 8248 --name-only` captured for AC12.
- [x] 0.3 `archive-kb.sh --dry-run` for the four slugs (`infra-inngest-volume-recut-luks`,
      `one-shot-7695-inngest-volume-recut-luks`, `fix-inngest-bootstrap-pin-and-guard-hardening`,
      `one-shot-7695-inngest-image-pin-probe-schema`) — exactly one artifact each.
- [x] 0.4 `bash plugins/soleur/test/c4-count-parity.test.sh` → exit 0.
- [x] 0.5 Re-measure the `- [ ]` counts of the two spec `tasks.md` files (plan-time: 26 / 40).

## Phase 1: Runbook (`knowledge-base/engineering/operations/runbooks/inngest-server.md`)

- [x] 1.0 Strike the superseded sentence where it is read (`~~…~~` + "superseded 2026-09-18" note,
      anchor text byte-intact); rewrite the `The latch clears only when` remediation sentence with
      the precondition (measured-empty store) before the mechanism, keeping `op=resume` is not it.
- [x] 1.1 Prefix the 2026-08-25 blockquote's lazy-continuation lines with `> `, then insert the
      paste-ready callout from plan § Phase 1.1c after them, every line `>`-prefixed (G19 first;
      rollback is one-way; `FLUSH_LATCH_SINCE` has no application; every value names its read —
      `inngest-host-state.sh`, Doppler `INNGEST_CUTOVER_FLIP`, Hetzner `GET /v1/volumes/106261946`,
      `gh run view 34948112813`; "dormant on this volume", never "retired").
- [x] 1.2 Add the Quick-reference row (plan § Phase 1.2).
- [x] 1.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` → `OK`.

## Phase 2: ADR-100 addendum (append-only)

- [x] 2.1 Append `## Addendum — 2026-09-18 (#7695) — the recut target exists, and is dormant on the
      volume the cutover landed on` per plan § Architecture Decision (five items; G8 worded as the
      #8078 predicate so the file agrees with its own 2026-09-11 §7; `Ref #8285`).
- [x] 2.2 `git diff origin/main -- <ADR-100>` shows additions only.

## Phase 3: Reconcile and archive the `issue: 7695` plan/spec pairs

- [x] 3.1 Append the reconciliation addendum to the 2026-09-02 plan (P1–P10 superseded; two replaces
      since for other reasons; P2 met but unconsumed; P9/P10 belong to the ADR-142 path).
- [x] 3.2 Archive the four artifacts with `archive-kb.sh <slug>` (spec dirs and the 09-07 plan
      unchanged — no notes, no ticking).
- [x] 3.3 AC5–AC8 checks (history preserved, byte-identical archived specs, 09-10 pair untouched).

## Phase 4: GitHub records

- [x] 4.1 `gh issue view 8316 --json state` → OPEN (already filed; do not file a second).
- [x] 4.2 Comments + relabels: #8078 (p1→p3, link #8316), #7777 (bound scope, clause-2 cross-link,
      `domain/legal` → `domain/engineering`); edit #8316 body (`Ref #8285`, ADR-199 §Consequences
      anchor, `model.c4` `inngestRedis` description anchor, G8 wording); one comment on PR 8248
      naming #8316. No comment on #8018.
- [x] 4.3 Verdict comments on #7695, #8017, #8015 quoting `measurements.md` fields with the read that
      produced each beside it, each ending "closes on merge of PR #8314".
- [x] 4.4 Draft PR body; `grep -oE 'Closes #[0-9]+' <draft> | sort -u` → exactly 7695/8015/8017
      BEFORE `gh pr edit --body`; then `gh pr view 8314 --json closingIssuesReferences` → the three.
      Body names the INDEX.md / kb-tags.txt overlap with PR 8248.

## Phase 5: Verification

- [x] 5.1 AC1–AC15 from the plan, each run and recorded (AC16–AC19 are post-merge).
- [ ] 5.2 `bash scripts/test-all.sh` at the /ship full-battery checkpoint.

## AC record (run 2026-09-18 in /work; commands per the plan)

| AC | Result |
|---|---|
| AC1 | callout count 1; `~~…today.**~~` count 1; Remediation block carries `op=resume` is not it` and `measured empty` before `recut` |
| AC2 | all 16 tokens ≥ 1 (`redis_keys=1261`, amended from plan-time 1081 to the measured value); G19 before G8; `op=resume` before `FLUSH_LATCH_SINCE`; every line `>`-prefixed; `retired` count 0 |
| AC3 | `OK: no human-run infra steps in 8 scanned file(s)` |
| AC4 | addendum count 1; `git diff origin/main -- ADR-100` has 0 `-` lines |
| AC5 | old plan absent; 1 archived copy; `git log --follow` 5 entries |
| AC6 | archived plan's last H2 is the 2026-09-18 addendum; archived spec dir diff vs `origin/main` empty |
| AC7 | old spec dir absent; `find` → 1 |
| AC8 | 2026-09-10 pair intact; 09-07 plan + spec archived, both diffs vs `origin/main` empty |
| AC9 | all fields present; `"id": 106261946` present; PASS line present |
| AC10 | `c4-count-parity.test.sh` exit 0 |
| AC11 | every path in the allow-list (renames listed both sides with `--no-renames`) |
| AC12 | intersection with PR 8248 (66 files) = `knowledge-base/INDEX.md` only |
| AC13 | `closingIssuesReferences` → `[7695,8015,8017]` |
| AC14 | any-case closing-keyword grep on the body → exactly the three |
| AC15 | `cloud-init-inngest.yml` count 0 |
