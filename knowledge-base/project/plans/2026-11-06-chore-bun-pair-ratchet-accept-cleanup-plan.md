---
title: "chore: close out the Bun 1.4.4 pair arc cleanup (verify the ratchet, land the PROMOTED_FILES guidance, decide the digest-scrub follow-up)"
type: chore
date: 2026-11-06
slug: bun-pair-ratchet-accept-cleanup
branch: feat-one-shot-bun-pair-ratchet-accept-cleanup
issue: 12146
closes: none
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore: close out the Bun 1.4.4 pair arc cleanup

## Overview

Cleanup after the merged constraint-scaffold pair PR (#12177, squash `04fc68d782`, deployed; tracker #12146 CLOSED). The brief named three items. Research (below) shows two of the three rest on stale or wrong premises, so the PR shrinks to one documentation edit plus recorded decisions:

| Brief item | Finding | Disposition |
|---|---|---|
| 1. Add accept rows / edges for the 11 pair-PR new-pair findings | Already done on main by `cffdf2705a` (#12166), which added 22 refresh-stage-a rows and the generator / emit-fix-constraints rows (`scripts/ci-pr-affected-audit.accept.tsv` lines ~627-654). The ratchet on main reads `live=2`, neither of them pair-PR pairs. | Verify-only. No edit to the accept TSV or `scripts/lib/test-affected-paths.sh`. |
| 2. Extend `work/SKILL.md` bullet 6.7 (optional) | SKILL.md has 12 bytes of headroom and the budget lint reads ceilings from the merge base (a ceiling can only be lowered). Not cheap there. | Put the sentence in the on-demand reference `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md` at zero SKILL.md byte cost. |
| 3. File a digest-scrub follow-up (optional) | Premise half wrong: `digest-scrub.sh` has a `github_token` class. The residual (encoded-form exfil) is already tracked by #6045 and #7124. | Do not file. |

## Research Insights

### Premise Validation (Phase 0.6)

- Cited trackers #12155, #10865, #10859, #12129: all OPEN. #12146 CLOSED. PRs #12153 and #12149 OPEN (both touch the accept TSV). #12160 is an OPEN PR (owner-run merge freeze), not an issue.
- **Stale premise, item 1.** Merge-group ratchet runs at `04fc68d782` (run 42118698053) and `4542477be1` (run 42127357840) printed `live=12` (11 pair-PR pairs plus `cloudflare-readonly.test.sh` to `seo-config-rules.tf`). The run at `cffdf2705a` (run 42168400997, job 127730192388) printed `SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=new-pair live=2`. The two are `plugins/soleur/test/terraform-target-parity.test.ts:4583` to `.github/workflows/build-inngest-bootstrap-image.yml` and `scripts/lint-gh-dedupe-shape.test.sh:733` to `.github/workflows/scheduled-zot-restart-loop.yml`. Open PR #12212 declares exactly those two edges (its own PR run was green, local `live=0`). The brief's "13 findings, other 2 = cloudflare-readonly and real-sdk-ask-probe" matches none of the current verdicts.
- **Local confirmation.** `python3 -I scripts/ci-pr-affected-replay.py ratchet` from this worktree (HEAD = main `cffdf2705a` + init commit) took 8m05s and printed `live=2`, same two pairs. The CTO's `audit --accept scripts/ci-pr-affected-audit.accept.tsv` read `gap_suites=2 gap_refs=2 accepted=1579 stale=0`; a plain `audit` without `--accept` prints `accepted=0` and says nothing about stale rows.
- **Sort order.** The accept TSV is sorted by (suite, path). Seven adjacent inversions already exist (lines 626/627, 637/638, 974/975, 1029/1030, 1084/1085, 3029/3030, 3048/3049), including the split of the generator / emit-fix-constraints rows across the two refresh-stage-a blocks. `load_accept` (`scripts/ci-pr-affected-replay.py`:1487) merges rows into a dict per suite and rejects only duplicate (suite, path, anchor, ordinal) tuples; no test enforces order. The split is cosmetic and is left alone to avoid conflicts with #12153 / #12149.
- **Stale premise, item 3.** `plugins/soleur/skills/operator-digest/scripts/digest-scrub.sh` line 51 defines `[github_token]` (`ghp|gho|ghu|ghs|ghr` and `github_pat_`) and is in `SECRET_ORDER`. The workflow asset checks out with `persist-credentials: false` (line 49, pinned by `plugins/soleur/test/operator-digest-workflow.test.sh`:52). The half that holds: `anthropics/claude-code-action` v1.0.263 (pinned SHA `3b7e1a45ca6f231c62605aabcf79e6a41b08c7da`), `src/github/operations/git-config.ts` lines 132-133, runs `git remote set-url origin https://x-access-token:${githubToken}@...` unless `ALLOWED_NON_WRITE_USERS` is set, so the job's short-lived `GITHUB_TOKEN` is in `.git/config` during the agent step.
- **Collision pre-check** (`collision-precheck.sh`, exit 10 on #12155 / #10865 / #12129): open PR #12217 (`feat-one-shot-10865-constraint-scaffold-pairs`, a draft with only an init commit and a live `test-all.sh` in its worktree) names #10865 and is plausibly a parallel run of the same stale brief; open PR #12212 names #10865 and owns the two live pairs. This plan edits neither the accept TSV nor `test-affected-paths.sh`, so it cannot conflict with either; the work phase must still re-run the pre-check and report the hit.

### Property List (Phase 0.6b)

1. After this PR, no ratchet verdict attributable to the pair PR is live on main (already true; must be re-verified at ship time).
2. The `PROMOTED_FILES` lesson from #12146 (floor-bearing suite under a deferred dir reddens ARM 5c; promote, never raise `MAX_DEFERRED`) is findable by a future `soleur:work` run without spending skill-body bytes.
3. The digest-scrub / `.git/config` concern has a recorded decision, so it is not re-litigated.

### Cut List

- New accept rows / edges for the pair-PR pairs, property 1: already covered by `cffdf2705a` rows (`stale=0`).
- Bullet 6.7 extension in `work/SKILL.md`, property 2: covered more cheaply by the existing reference file already linked from SKILL.md line 1183; avoids a 395-byte trim of a per-turn lifecycle skill (see learning `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`).
- New digest-scrub issue, property 3: covered by #6045 (reversibly-encoded secrets, digest-scrub sync) and #7124 (collector-side minimisation).
- Re-sorting the accept TSV: no property buys it; conflict risk with #12153 / #12149.

### Institutional learnings applied

- `test-failures/2026-11-01-hot-anchor-accept-rows-are-kept-when-no-expressible-alternative.md` and `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`: anchor-keyed accept rows go stale when main moves; rebuild on the merged tree, not the branch tip. This is why the final verdict is read from a post-`#12212` merge_group run, not from the branch.
- `2026-11-05-a-ledger-that-guards-a-clobber-needs-its-own-integrity-pins-and-a-refresh-converges-more-than-the-pin.md`: the learning whose guidance item 2 routes.
- `2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`: installation-token lifetime (supports the "short-lived" point in item 3).

### Pair PR review-trailer check (for the final report)

The pair PR body says commit `16d77c3aaa` was "checked by the lead through mutation runs but not seat-reviewed". The commits on the PR branch carry these trailers:

- `a23cb47efc` (11-seat panel record, after `16d77c3aaa`): `Reviewed-By-Soleur: soleur:review`, `Reviewed-Commit: 16d77c3aaa93860b368d1d37119a644c9d2e1330`, `Reviewed-Coverage: full 11/11 agents`, `Reviewed-Risk-Tier: aggregate pattern`.
- `a879cf27ae` (fix-round record): `Reviewed-Fix-Round: unknown`, `Reviewed-Commit: a23cb47efc...`, `Reviewed-Fix-Range: 908e91ac627fd94ef5012da2faed44072d1a0818..16d77c3aaa93860b368d1d37119a644c9d2e1330`.
- The trailers' own text says they are a boolean "a review ran", not an attestation of the merged tree (ADR-127), and `16d77c3aaa`'s own message reads "Fix round 2 from the targeted seats", i.e. it applies the seats' findings.

So the caveat is not a clean fact in either direction. Report it as: the trailers name `16d77c3aaa` as the reviewed commit and as the end of the fix-round range, but the commit itself applies the seats' findings and the PR author states it was only lead-verified; no seat is recorded as having re-read the post-`16d77c3aaa` tree. Do not repeat the bare "not seat-reviewed" claim.

## Scope Check

### Ask Mapping

| Ask | Plan item |
|---|---|
| 1. ratchet: no pair-PR new-pair / stale-accept verdicts | Phase 1 (verify-only; evidence above) |
| 2. optional work/SKILL.md bullet 6.7, only if CTO says cheap | Phase 2 (CTO: not cheap in SKILL.md; reference-file variant) |
| 3. optional digest-scrub issue | Phase 3 (decision recorded: do not file) |
| carry unresolved notes for the final report | Phase 4 |
| decisions persisted as `| Item | Class | Ruling |` rows | `decision-challenges.md` |

### Plan-Item Provenance

All items are `asked` except the reference-file placement in Phase 2, which is the CTO's resolution of ask 2 (`inferred`, justified: it delivers the asked guidance without the SKILL.md budget breach).

### Split Assessment

One small PR. No split.

## Implementation Phases

### Phase 1: Ratchet verification (no file edit)

1. `git fetch origin main`; read the newest `CI` merge_group run on main whose `affected-index-ratchet` job executed (push runs skip it): `gh run list --workflow=ci.yml --event merge_group -L 10`, then `gh run view <run> --json jobs` and `gh run view <run> --job <id> --log`, grep `^new-pair|^stale-accept|^SOLEUR_PR_AFFECTED_RATCHET`.
2. Pass condition: no verdict names `constraint-scaffold/test/{refresh-stage-a,generator,emit-fix-constraints}.test.sh`. Expected today: `live=2` (or `live=0` once #12212 merges), none pair-attributed. The local `ratchet` command is a fallback (about 8 minutes locally, 3-4 in CI); do not start it while another copy runs.
3. If a pair-attributed verdict has reappeared (a later main moved the anchors), rebuild the rows from `audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` on the merged tree, add them in sorted (suite, path) position next to the existing refresh-stage-a block, and keep the diff to those lines only. This branch is conditional and not expected.
4. Do not touch the `cloudflare-readonly` or `real-sdk-ask-probe-workflow` pairs, nor the two #12212 pairs.

### Phase 2: PROMOTED_FILES guidance in the work reference (CTO-ruled)

Edit `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md`, the bullet that begins `- \`PROMOTED_FILES\` promotion only *after \`git add\`*` (around line 34, wrapped across two lines; anchor on that text, not the line number). Append:

> A floor-bearing suite under a DEFERRED dir (`plugins/soleur/skills/*/test/`, `apps/web-platform/infra/`, `.claude/hooks/`) grows the deferred ledger and reddens ARM 5c: add the file to `PROMOTED_FILES` (one edit to the single canonical line; on merge conflict keep main's set plus yours), never raise `MAX_DEFERRED` (#12146).

Wrap to the file's existing line width (about 80 columns, two-space continuation indent). Do not edit `plugins/soleur/skills/work/SKILL.md` or `plugins/soleur/test/skill-body-budget.json`. Verify: `python3 scripts/lint-skill-body-budget.py --base origin/main` passes unchanged; `npx markdownlint-cli2` (or the repo's markdown-lint invocation) on the file passes.

### Phase 3: digest-scrub decision (no issue filed)

Ruled: do not file. Record the flip criterion in `decision-challenges.md` so a future change to the digest agent's write or egress surface, or to the token class, re-opens it. No issue creation in work or ship for this item.

### Phase 4: PR body and final report content

- PR body: `Ref #12155`, `Ref #10865`, `Ref #10859`, `Ref #12129` (never `Closes`); a Changelog line (`semver:patch`, plugin docs only). State that item 1 was found already resolved and name `cffdf2705a`, and that #12212 owns the remaining two pairs. Do not file a new tracker.
- Final-report unresolved notes (carry verbatim):
  - Better Stack incident `soleur-egress-gw-probe-silent-prd` (id 1047829421) still open; API `started_at` 2026-11-05T17:15Z versus the brief's 2026-10-12, unexplained, out of scope. Not independently re-queried by the planner.
  - Issues 2737, 12008, 12007, 12006 untouched (all OPEN as of 2026-11-06).
  - The `rf-window-hold` owner-run merge freeze (#12160, an OPEN PR) did not block the pair PR.
  - Review trailers on the pair PR: see "Pair PR review-trailer check" above; report the nuanced finding.
  - The feature-tweet gate did not apply to the pair PR (it carried only `semver:patch`, no `app:web-platform` label); this PR is likewise plugin-docs only.
  - Collision: open draft PR #12217 (`feat-one-shot-10865-constraint-scaffold-pairs`) overlaps the brief's topic.

## Files to Edit

- `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md` (one bullet extended, Phase 2)

## Files to Create

- `knowledge-base/project/plans/2026-11-06-chore-bun-pair-ratchet-accept-cleanup-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-bun-pair-ratchet-accept-cleanup/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-bun-pair-ratchet-accept-cleanup/decision-challenges.md`

Explicitly NOT touched: `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` (no new suite is added, so no registry row is owed), `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/test/skill-body-budget.json`, `apps/web-platform/test/claude-pin-lockstep.test.ts`.

## Open Code-Review Overlap

None. Queried open `code-review` issues for `work-test-harness-sharp-edges` and `plugins/soleur/skills/work/SKILL.md`: no matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The only code-adjacent change is a sentence in a skill reference read by a developer agent during `soleur:work`; a malformed bullet would at worst fail `markdown-lint` on this PR.
- **If this leaks, the user's data is exposed via:** no vector. No secret, credential, schema, route or workflow is touched. Item 3's discussion names the `GITHUB_TOKEN` class only, with no value.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, because the diff is a documentation-only plugin reference edit plus planning artifacts, with no sensitive path (preflight Check 6 regex) and no runtime behaviour change.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed
**Assessment:** The CTO agent ruled all three items (see `decision-challenges.md`): item 1 verify-only, item 2 reference-file placement, item 3 do not file. No Product/UX surface (no `components/`, `app/**/page.tsx`, or UI-surface path), no Legal, GDPR, IaC, ADR or C4 impact: no architectural decision is made or changed, no persistent store or connection is introduced, and no guard is authored (the plan adds no gate, lint or assertion). Observability, Encryption Posture, Task Design and Guard Contract sections do not apply: no code under `apps/*/server`, `apps/*/src`, `apps/*/infra` or `plugins/*/scripts` is edited and no autonomous task surface is created.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] The diff is limited to `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md` plus `knowledge-base/project/{plans,specs}/` artifacts (`git diff --name-only origin/main...HEAD`); the accept TSV, `test-affected-paths.sh`, SKILL.md, the budget JSON and `claude-pin-lockstep.test.ts` are absent from it.
- [ ] The extended bullet contains the strings `DEFERRED dir`, `PROMOTED_FILES` and `MAX_DEFERRED` (here-string `grep`, no bare pipe into `grep -q`).
- [ ] `python3 scripts/lint-skill-body-budget.py --base origin/main` exits 0.
- [ ] The newest executed `affected-index-ratchet` log shows no verdict naming a `constraint-scaffold/test/*.test.sh` suite and no `stale-accept` / `star-row` verdict (the log lines are quoted in the PR body).
- [ ] PR body carries `Ref #12155`, `Ref #10865`, `Ref #10859`, `Ref #12129` and no `Closes` / `Fixes` / `Resolves`; no new tracker issue is created.
- [ ] Required checks green on the PR head: `test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`. `affected-index-ratchet` is advisory (`continue-on-error`) and a red `live=2` from #12212's pairs does not block; it is reported, not fixed here.
- [ ] `decision-challenges.md` rows match the CTO rulings.

### Post-merge (operator-free)

- [ ] The `CI` run on the merge commit is `success` and no deploy is triggered or needed (plugin docs only; PR `Blast Radius: plugin`): verify with `gh run list --branch main -L 3` and, if `web-platform-release.yml` ran for the merge SHA, `curl -s https://app.soleur.ai/health` returns the healthy payload.
- [ ] After #12212 lands, the next executed merge_group ratchet shows `live=0`, or `live=2` while it is still open; record whichever it is in the ship summary.

## Test Scenarios

- Given main at `cffdf2705a` (or later), when the ratchet runs, then no `new-pair` line names `refresh-stage-a`, `generator` or `emit-fix-constraints` and no `stale-accept` line appears.
- Given the edited reference file, when `markdownlint` runs, then it exits 0.
- Given `skill-body-budget.json` and `work/SKILL.md` unchanged, when `lint-skill-body-budget.py --base origin/main` runs, then it exits 0.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled (`none`, with a reason).
- Do not "fix" the live=2 pairs here: they belong to #12212, and a duplicate edge edit would conflict with it and with #12153 / #12149.
- The ratchet's log lists only the first 25 entries of each class; the totals come from the marker line `live=<n>`.
- Anchors in the accept TSV are line-content hashes; any later edit to a refresh-stage-a, generator or emit-fix-constraints line (or to `constraint-scaffold.sh` line 672-674) turns the matching row stale. Nothing in this plan edits those files.
- `plugins/soleur/skills/work/SKILL.md` bullet 6.7 stays exactly as it is; do not "restore" the reverted extension (commit `abadc63ddf`).

## References

- Pair PR: #12177 (`04fc68d782`); tracker #12146 (CLOSED)
- Ratchet repair on main: `cffdf2705a` (#12166); open repair PR #12212 (two live pairs); parallel draft #12217
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` section 7
- Budget lint: `scripts/lint-skill-body-budget.py`, `plugins/soleur/test/skill-body-budget.json` (work = 359189, file = 359177)
- CTO rulings: `knowledge-base/project/specs/feat-one-shot-bun-pair-ratchet-accept-cleanup/decision-challenges.md`
