# Tasks - record the 2026-11-06 owner decisions, refresh the A6 draft, design #12158 (Ref #9927)

Plan: `knowledge-base/project/plans/2026-11-06-chore-record-owner-decisions-a6-refresh-9927-plan.md`. Never a closing keyword. No dispatch, revoke or production write.

## 0. Setup

- 0.1 `git fetch origin main`; confirm the tail of ADR-282 is unchanged (PR 12218 may append) and `git ls-files` prints every path in "Files to Edit".
- 0.2 File the revisit tracker WITHOUT the `follow-through` label and directive (body: "not enrolled until the probe is on main") to get `<N>`.
- 0.3 Verify every deferral has its own open issue (header backup, dead-man alert PR, off-project copy, #11265, #12158); file those that lack one (`Post-MVP / Later`).
- 0.4 Re-run `technical-ruling-gate.sh` on `decision-challenges.md` (`[PASS]`).

## 1. ADR-282 addendum

- 1.1 Append `## Addendum - 2026-11-06 (#9927 owner decisions, items 1b, 4, 8, 10)`: six asks with the label and status words plus the ask-to-row map, one line per ruling with its row id (R1-R6 keep their source clause), window preconditions, off-project copy status and C1-C11, epic close conditions, exposure statement verbatim, "What this does not change".
- 1.2 Dated `Superseded 2026-11-06` markers, each on its own line after its paragraph: 2026-11-03 sunset sentence; 2026-11-05 flip-read "rejected for now" and "direction #12158 takes for the write credential".
- 1.3 `lint-infra-no-human-steps.py --changed --base origin/main`; AC 1 wording gate.

## 2. A6 draft refresh

- 2.1 Hetzner API read (pinned `curl` form, header file mode 600, `timeout`, no xtrace; invalid-token 401 mapping exercised once); pending form on failure; nothing filed.
- 2.2 Edit the draft: `refreshed: 2026-11-06`, visible line `unsigned, owner sentence pending` under the H1, API read section, last-console-read section with the PENDING row, A5 / measured-re-read / Hetzner-answer cells with Superseded markers, empty "Owner's own sentence" section.
- 2.3 Delete the old statement block with the CLO's replacement note (SHA from `git log --follow`); marker under the 2026-11-02 banner; claim-limit content kept in third person; three claim-limit paragraphs verbatim; paragraph under the 2026-10-31 heading with the #10382 pointer (URL after step 6.1 exists).
- 2.4 No rename, no conditional rename; if an owner sentence appears, stop and hand off.

## 3. #12158 design doc

- 3.1 Write `arm-token-replacement-design-12158.md` per Phase 3 (revisit question first; pointers to D1, D1b, D1c, D2; test pins once; failure modes; sequence; revoke change and rollback; held versus tracked; recorded-now versus built-later; ADR-241 fit; arm-write-token.tf 403 anchor).
- 3.2 Lint; verify AC 7.

## 4. G2e supersession

- 4.1 `bun test plugins/soleur/test/terraform-target-parity.test.ts` (365 pass baseline); add the one comment line; re-run; re-run after the Phase 5 registration.
- 4.2 One appended line in the 2026-10-11 learning.

## 5. Revisit probe

- 5.1 Failing suite first: `scripts/followthroughs/arm-token-revisit-<N>.test.sh` (six mutants, about five cases, exit-set {2,3,5}, mode 100755 assertion, synthesized fixtures, test-only path override).
- 5.2 Probe from the stub template, header with notify-only / credential posture / residuals / RETIREMENT; `chmod 755`.
- 5.3 Register: `run_suite` in `scripts/test-all.sh` (beside zot-soak), `scripts/suite-shard-legs.tsv` row, `scripts/lib/test-affected-paths.sh` (amended by D3-r2a: no declared block; the edge is derived); `lint-orphan-test-suites.sh` after `git add`.
- 5.4 If registration exceeds that footprint, split the probe into its own PR.

## 6. Review and ship hand-off

- 6.1 Pre-merge comment on #10382 (CLO conditions, PR link) after the draft is pushed; put its URL into the draft.
- 6.2 Review seats receive the recorded rulings as settled (8.2); any `contradicts-ruling` goes to the owner agent in one batched call.
- 6.3 PR body: `Ref #9927`, `Ref #12158`, surviving wording-gate hits with justification, owner list with `(operator: <category>)` items, no closing keyword.

## 7. Post-merge (agent-run, none closes anything)

- 7.1 Only after the PR shows MERGED: #12158 comment first, then the single #9927 comment (idempotency markers, banned-token grep), link comments on #10382 and #10136 with SHA permalinks.
- 7.2 Edit the tracker's own body to add the unfenced directive and add the `follow-through` label; read-only re-check of #12213 and the latest merge-queue or dispatch run, reported in the #9927 comment.
