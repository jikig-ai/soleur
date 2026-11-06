# Decision challenges: feat-one-shot-bun-pair-ratchet-accept-cleanup

Headless planning (2026-11-06). Every technical fork was routed to the CTO agent; nothing was put to the operator.
The rulings below are copied from the agent's reply.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| D1 item 1: add accept rows or declare edges for the pair-PR ratchet findings, or verify only | technical | Ruled by CTO agent, 2026-11-06: verify-only, no TSV or edge edit in this PR - the pair-PR pairs were already accepted by `cffdf2705a` (#12166); the ratchet reads `live=2` (terraform-target-parity and lint-gh-dedupe-shape pairs, owned by #12212), `audit --accept` reads `gap_suites=2 accepted=1579 stale=0`, no duplicate keys, and both refresh-stage-a row sets are live and complementary; an edit would only have collided with #12153 and #12149 on the same file at ruling time (#12149 has since merged) |
| D2 item 1: re-sort the accept TSV (seven pre-existing (suite, path) inversions, including the split generator / emit-fix-constraints rows) | technical | Ruled by CTO agent, 2026-11-06: leave as is - `load_accept` merges rows per suite and no test enforces order, so the split is cosmetic and a re-sort only adds conflict risk |
| D3 item 2: extend `work/SKILL.md` bullet 6.7 (12 bytes of headroom, ceiling can only be lowered) | technical | Ruled by CTO agent, 2026-11-06: not cheap in SKILL.md, skip it there - a 395-byte trim of a per-turn lifecycle skill buys a rule that fires only for a floor-bearing suite under a deferred dir; put the sentence in `plugins/soleur/skills/work/references/work-test-harness-sharp-edges.md` (the `PROMOTED_FILES` bullet) at zero SKILL.md byte cost; do not touch SKILL.md or `skill-body-budget.json` |
| D4 item 3: file a follow-up for digest-scrub / `.git/config` token | technical | Ruled by CTO agent, 2026-11-06: do not file - `digest-scrub.sh` line 51 already has a `github_token` class and aborts on a match; the workflow checks out with `persist-credentials: false`; the token does reach `.git/config` via claude-code-action's `configureGitAuth` (pinned SHA 3b7e1a45, `git-config.ts`, the `git remote set-url origin https://x-access-token:` step) but it is the same short-lived `GITHUB_TOKEN` already in the agent step's `GH_TOKEN` env, and the sink is a private issue; the encoded-form residual is already in #6045 (reversibly-encoded secrets, digest-scrub sync) and #7124 (collector-side minimisation) |
| D5 item 3 flip criterion | technical | Ruled by CTO agent, 2026-11-06: file only if the digest agent gains write or egress beyond a private repo issue, or the token becomes a PAT or an App token wider than the job's `GITHUB_TOKEN`, or the sink repo gains readers beyond the operator, or the scrub moves from fail-closed to fail-open (review addition, security-sentinel, 2026-11-06); then title it `operator-digest: scrub or strip the checkout credential from .git/config before the agent step` |
| D6 pair-PR review-trailer caveat for the final report | taste | Planner's call (Claude, not an agent ruling), 2026-11-06: report the nuanced finding, not the bare "not seat-reviewed" - trailers on `a23cb47efc` and `a879cf27ae` name `16d77c3aaa` as the reviewed commit and as the end of the fix range, but those trailers are a boolean "a review ran" (ADR-127), `16d77c3aaa` itself applies the seats' findings, and the PR author states it was only lead-verified |
| D7 ship-time: fix the brief-constraint propagation gap (ship ran the local battery despite "rely on CI") in this PR or a separate one | technical | Ruled by CTO agent, 2026-11-06: separate PR - `one-shot` writes the brief's constraints under `## Operator Constraints` in `session-state.md` with a `ci-is-the-gate` token, and `battery-owed.sh` exits 42 on it unless `--full` or an infra/unresolved diff; byte-neutral SKILL.md edits (ship 44 B, one-shot 9 B headroom), detail in `one-shot/references/operator-constraints.md`, new rows in `ship-battery-owed.test.sh`; bundling would turn a reviewed, CI-gated docs PR into a lifecycle-skill change needing fresh seats and mutation rows; this PR carries only the learning and the Test-plan line |

## Premise corrections recorded (not operator questions)

- The brief said the ratchet was red with 13 findings, 11 from the pair PR. That was true of the merge_group runs at `04fc68d782` and `4542477be1` (`live=12`); it stopped being true at `cffdf2705a` (`live=2`, different pairs).
- The brief said `digest-scrub.sh` has no GitHub-token pattern. It has one (line 51).
- The brief said the checkout token sits in `.git/config`. The workflow's checkout persists nothing; the token lands there through claude-code-action's own git auth step.
- Open draft PR #12217 (`feat-one-shot-10865-constraint-scaffold-pairs`) overlaps the topic of item 1; this plan makes no edit to the files it would touch.

## Deepen-plan update (2026-11-06)

- #12212 merged at 07:52:55Z (`511db9f84f`) and #12149 merged; the merge_group ratchet runs for both print `exit=0 reason=pass live=0 baseline=0` (runs 42178796263 and 42178975746). D1 stands and is now stronger: the ratchet is green on main, so the "DONE WHEN" ratchet condition needs no edit from this PR. No CTO ruling changed.
