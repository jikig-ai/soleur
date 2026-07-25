---
issue: 6901
branch: feat-one-shot-6901-encryption-posture-required-check
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-24-feat-encryption-posture-required-check-promotion-plan.md
verdict: DEFER-ARM
deepened: 2026-07-24
---

# Tasks — encryption-posture required-check promotion (measure-then-arm → DEFER)

Verdict: DEFER arming (the standalone `encryption-posture` check-context does not
exist yet → 0 attributable runs). This PR stands up the soak infrastructure +
documents the corrected arming recipe; sites (2)–(5) + MB-10 are deferred to a
tracked follow-up. (Deepened: soak follow-through probe CUT — R1; exact N deferred
to arm time — R2.)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm the sweep step still at `ci.yml:185` inside `lint-bot-statuses`
      (no sibling PR already split it out).
- [ ] 0.2 `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 (paste code).
- [ ] 0.3 `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` GREEN (baseline).

## Phase 1 — Site (1): standalone advisory `encryption-posture` job (NON-arming)
- [ ] 1.1 Remove the sweep step from the `lint-bot-statuses` job in `ci.yml`.
- [ ] 1.2 Add a top-level advisory `encryption-posture` job (stable context name,
      pinned checkout SHA, no path filter) running `--repo-sweep`. Mirror
      `lint-conversations-update-callsites` (ci.yml:188) / the `credential-path-guard`
      extraction (ci.yml:148-156, #6882).
- [ ] 1.3 Carry the ADVISORY/NOT-BLOCKING comment + add the soak/#6901/ADR-117 note.
- [ ] 1.4 Prove non-arming invariant via grep across the 4 SSOTs (only comment hits).
- [ ] 1.5 Re-run parity test — GREEN + 15368 set unchanged.

## Phase 2 — ADR-140 Amendment (this PR)
- [ ] 2.1 Add `## Amendment (2026-07-24, #6901)` — 5-site count; 15368-not-CodeQL
      shape; measure-then-arm (N lives in the tracking issue, NOT the ADR — R2).
- [ ] 2.2 Cross-reference the stale "three coupled edits" cell (line 123).

## Phase 3 — Arming tracking issue
- [ ] 3.1 Verify labels exist, then `gh issue create` (type/security,
      domain/engineering, priority/p2-medium; Phase 4 milestone; NOT follow-through);
      body = canonical arming recipe (sites 2–5 + MB-10) + re-eval one-liner + R5 residual.
- [ ] 3.2 Use `Ref #6901` in the issue body (not `Closes`).

## Phase 4 — Re-eval criterion (no automation)
- [ ] 4.1 Record the runnable re-eval one-liner in the issue
      (`gh run list --workflow=ci.yml --branch main --json conclusion,databaseId` +
      `gh run view <id> --json jobs`). No follow-through script, no sweeper wiring.
- [ ] 4.2 State the directional soak criterion (green across diverse infra/migration/docs
      PRs over ~2 weeks, no false-positive-attributable red; exact N set at arm time).

## Phase 5 — DEFERRED (documented only; executed in the tracked follow-up PR)
- [ ] (deferred) Site 2 — required-checks.txt: ADD name (15368), CODEOWNERS note.
- [ ] (deferred) Site 3 — ruleset-ci-required.tf: required_check {15368} + ABI-count amend (20→21).
- [ ] (deferred) Site 4 — canonical JSON: append {context, integration_id:15368}.
- [ ] (deferred) Site 5 — bot action adjudication: unreachability note; no code edit
      unless an encryption path enters ALLOWED_PATHS.
- [ ] (deferred) MB-10 — continue-on-error:true still reds a bad fixture's required check.
- [ ] (deferred) R5 — post-apply live check that a real PR reaches the required check satisfied.

## Testing (this PR)
- [ ] T1 parity GREEN + set unchanged; T2 non-arming grep zero; T3 sweep exit 0;
      T4 actionlint + bash -c on the new job's run block.
