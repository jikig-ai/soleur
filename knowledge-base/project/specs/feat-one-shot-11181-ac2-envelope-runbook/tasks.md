# Tasks — docs: Commit the AC2 delegation-envelope runbook for epic #11181

Derived from `knowledge-base/project/plans/2026-10-27-docs-delegated-act-11181-ac2-envelope-runbook-plan.md` (MINIMAL). KB-only documentation PR; no code or infrastructure changes. Plan source of truth for scope: the plan's `## Scope Check` (all six asks mapped) and `## Acceptance Criteria` (AC-1..AC-5).

## Phase 1 — Archive the envelope

- [ ] 1.1 Obtain the CTO ruling for decision-challenges rows T1-T3 (batched spawn; replace `pending - assumed:` cells) before `work` starts — one-shot contract, technical-ruling-delegation.md §3.
- [ ] 1.2 Copy the scratch envelope verbatim: `cp /tmp/opencode/delegated-act-11181-ac2-envelope.md knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md`. No edit of any byte (no frontmatter, no heading normalization — precedent files carry none and receipts fingerprint bytes).
- [ ] 1.3 Verify the anchor before committing: `sha256sum` of the new file equals `ffa9cbe118ac875635f5ae051682c418f678f069b22a9d546e2e9c901d038b5f` (AC-1). If the scratch file drifted or vanished, STOP — do not reconstruct from memory; the only copy is the artifact.
- [ ] 1.4 Commit; then re-verify AC-1 against the commit (`git show HEAD:knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md | sha256sum`).
- [ ] 1.5 PR body: one-line summary + the literal line `Ref #11181`. Never spell a Closes/Fixes/Close token adjacent to `#11181`, not even in prose (AC-3's absence-grep would false-fail on the prohibition sentence itself — see plan Phase 1 step 3). Phrase the epic-stays-open note as "epic stays open for residual operator-class items".

## Phase 2 — Acceptance verification (deterministic, all commands measured at plan time)

- [ ] 2.1 AC-2 — no credential values: `git show HEAD:knowledge-base/engineering/operations/runbooks/delegated-act-11181-ac2-envelope.md | grep -c -e 'sdu_' -e 'dop_pat_' -e 'dop_oi_' -e 'dop_st_' -e 'ghp_' -e 'gho_' -e 'ghu_' -e 'github_pat_' -e '-----BEGIN'` exits 1 (zero matches). The repeated-`-e` form is used because preflight-style token scanners reject pipes inside a quoted regex; the alternation form was measured equivalent (rc 1) on the real bytes.
- [ ] 2.2 AC-3 — PR body contains `Ref #11181` (`grep -c 'Ref #11181'` rc 0) and no close-keyword+`#11181` pattern (`grep -icE 'clos(es|e) #11181|fixes #11181'` rc 1). Post-merge read-only check: `gh issue view 11181 --json state -q .state` returns `OPEN` (consequence check, not the verifiable property — the body grep is).
- [ ] 2.3 AC-4 — KB-only diff: `git diff --name-only origin/main...HEAD | grep -v '^knowledge-base/'` prints nothing (rc 1). Triple-dot pins the merge base so a sibling merge cannot redden it.
- [ ] 2.4 AC-5 — exactly one tracked copy: `git ls-files knowledge-base | grep delegated-act-11181` returns exactly one line.

## Out of scope (do not fold in)

- Delegated-act receipt reconciliation on epic #11181 (Context note in the plan; decision row T3).
- Any change to the envelope's markdown, ADR-289, workflows, or Doppler (ask 4: "no code or infra changes").
