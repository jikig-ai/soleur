# Tasks: flip ADR-282 adopting to accepted (Ref #10018)

Plan: `knowledge-base/project/plans/2026-10-15-chore-flip-adr-282-adopting-to-accepted-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-10018-adr-282-adopting-to-accepted/decision-challenges.md`

## Phase 0 - Setup

- 0.1 `git fetch origin main`; confirm `delete_protection = true` on `hcloud_volume.inngest_redis_luks` at `origin/main`.
- 0.2 Re-run the repo-wide subject sweep over non-archived paths; reconcile against the plan's ten-row table.
- 0.3 Run the AC-4 and AC-5 stale-phrase greps against `origin/main` (they must be non-zero there).

## Phase 1 - ADRs

- 1.1 ADR-282: frontmatter `status: accepted`; leading "Accepted 2026-10-15 (#10018)" blockquote under `## Status`; append the `## Addendum - 2026-10-15` evidence section.
- 1.2 ADR-119, ADR-142 (directly under "Status of this addendum: adopting"), ADR-263, ADR-199: one dated supersession blockquote each; frontmatter untouched.

## Phase 2 - Runbook (in place)

- 2.1 `inngest-luks-cutover-6894.md`: three spots (the only-copy paragraph, the wrapped "Rules that stay in force" bullet, the section 5c status paragraph). Keep the heading text and the read-back one-liner byte-identical.

## Phase 3 - C4 and ledger

- 3.1 `model.c4`: replace the PROTECTION parenthetical; `bash scripts/regenerate-c4-model.sh`; commit the regenerated `model.likec4.json`.
- 3.2 `scripts/encryption-posture-ledger.json`: the CLO's one-clause replacement in `does_not_defend`.

## Phase 4 - Legal registers (CLO wording, verbatim)

- 4.1 `article-30-register.md` PA-13 (g)(13): heading parenthetical + appended marker; no `last_reviewed` bump.
- 4.2 `compliance-posture.md` row ~205: appended marker before the closing `**]**`; no front-matter bump.
- 4.3 If `soleur:ship` Phase 5.5 requires an attestation: CLO verdict on the final diff text.

## Phase 5 - Verification (targeted only)

- 5.1 `bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh`
- 5.2 `python3 scripts/lint-encryption-posture.py`; `bash scripts/lint-encryption-posture.test.sh`; ledger JSON parses
- 5.3 `bash plugins/soleur/test/c4-count-parity.test.sh`
- 5.4 `bash scripts/lint-legal-registers.sh`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`
- 5.5 `bash scripts/check-adr-ordinals.sh`; `bun test plugins/soleur/test/adr-frontmatter-ordinal-guard.test.ts`

## Phase 6 - Ship and merge

- 6.1 Commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; `Ref #10018` only; no closing keyword anywhere.
- 6.2 PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; assert `closingIssuesReferences` is `[]` after every body edit.
- 6.3 Once required CI is green, queue auto-merge; never sync a queued or armed PR by hand (merge main with a merge commit if ever needed).
- 6.4 Post-merge: confirm the merge diff on main, postmerge Phase 5.7 SKIPPED (no triggering paths), no Hetzner/Doppler call; close #10018 with a comment; report #10081 status (OPEN draft, `parked`, untouched).
