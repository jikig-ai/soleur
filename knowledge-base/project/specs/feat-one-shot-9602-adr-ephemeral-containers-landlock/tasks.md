# Tasks: ADRs for per-session ephemeral containers and Landlock ruleset (#9602)

Plan: `knowledge-base/project/plans/2026-11-03-feat-adrs-ephemeral-containers-landlock-plan.md`
Branch: `feat-one-shot-9602-adr-ephemeral-containers-landlock` | Draft PR: #11935 | Keywords: `Ref #9602`, `Ref #9601` only.
Diff scope: the two ADR files plus this feature's own spec and plan files; nothing else.

## Phase 0: Preconditions at work start

- [ ] 0.1 Ordinal census over every origin ref plus open-PR ADR claims (commands in plan Phase 0 step 1); take the next two above the max of both (315 and 316 at plan time).
- [ ] 0.2 Overlap state: #9854, PR #9832 (pin its branch sha), PR #11592, any open PR touching ADR-075, ADR-068 or the seccomp profile; if #9854's ADR has merged, ADR-315 stays `proposed` with the topology-of-record Status line (ruling X).
- [ ] 0.3 Re-verify every row of both claim ledgers (C1-C10, L1-L8): re-find the content anchor and update the coordinate; relabel `unverified` only when the content is gone or changed.
- [ ] 0.4 Read nfr-register.md and principles-register.md (read-only) and pick the real NFR and AP IDs for the NFR Impacts and Principle Alignment sections.

## Phase 1: ADR-315 container ADR

- [ ] 1.1 Write `knowledge-base/engineering/architecture/decisions/ADR-315-per-session-ephemeral-containers-recorded-not-adopted.md` (Write tool, whole file): frontmatter per plan (no `adr:`, `amends` or `supersedes` key), `status: proposed`, `related_adrs` with the nine ADRs of ruling Z (one-clause reason each in the body), `related` including #9859.
- [ ] 1.2 Status section first lines verbatim; relates-to-ADR-075 statement; #9854 owns topology; flip semantics of ruling X (requires #9854's merged decision; P1-P5 necessary not sufficient; cost ceiling and go-ahead operator-class; a decision to plan, not to ship); `not adopted` is not accepted risk.
- [ ] 1.3 Context with ledger rows C1-C10 labelled; broker relation (#9543, ADR-311, ADR-272).
- [ ] 1.4 Considered Options: four options with pros, cons, disposition; option 4 uses the ruling N sentence verbatim and avoids the words rejected, adopted, planned.
- [ ] 1.5 Decision: "Not adopted now. Adoption is gated on the measured preconditions below." P1-P5 measurements (baseline arm = production today; machine record with each) plus P6 consistency with #9854; ruling P label wording; triggers; no-public-claim clause.
- [ ] 1.6 Consequences, Cost Impacts, NFR Impacts, Principle Alignment with real content (no "None" padding, no Diagram stub).
- [ ] 1.7 Re-read: line count at least 150, required headings in order.

## Phase 2: ADR-316 Landlock ADR

- [ ] 2.1 Write `knowledge-base/engineering/architecture/decisions/ADR-316-active-landlock-ruleset-beneath-bwrap-recorded-not-adopted.md`: frontmatter per plan, `status: proposed`, `supersedes: none`, `related_adrs` including ADR-122 (one-clause reason).
- [ ] 2.2 Status section first lines verbatim; layer beneath bwrap, supersedes nothing.
- [ ] 2.3 Context with ledger rows L1-L8 labelled; Bash-tier-only coverage stated; run and record the `git grep -il landlock` command and date for L2 as `measured`.
- [ ] 2.4 Considered Options A-D: B places the ruleset in the sandboxed child after the filesystem view is built and before exec (the shim and the outer-wrap spawn are not candidates, reason stated); option C reasoning labelled `unverified`; OpenShell and sandlock labelled "README-level, unverified, from the #9842 spec"; no CVE text.
- [ ] 2.5 Decision: not adopted now; gate G1-G6 (3-5 day spike estimate read from #9602), canary Landlock probe with replay argv unchanged, degrade-and-signal arm G6; ownership sentence from ruling Q; flip semantics of ruling X; no-public-claim clause.
- [ ] 2.6 Consequences, Cost Impacts, NFR Impacts, Principle Alignment with real content.
- [ ] 2.7 Re-read: line count at least 150, required headings in order.

## Phase 3: Verification on the final tree

- [ ] 3.1 `bash scripts/markdown-lint.sh` on the two ADR files.
- [ ] 3.2 `bash scripts/check-adr-ordinals.sh`; hand-verify the headings Status, Context, Decision, Consequences (and the rest of the rich set); `python3 scripts/lint-infra-no-human-steps.py` on both ADRs.
- [ ] 3.3 `bash scripts/test-affected-kb-consumers.test.sh` (baseline only if a test pairs with a new file; none expected).
- [ ] 3.4 `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash scripts/always-on-ledger.test.sh`.
- [ ] 3.5 Stale-ghs census via `bash scripts/lint-shell-trace-credential-refusal.test.sh`.
- [ ] 3.6 `bash plugins/soleur/test/c4-count-parity.test.sh`; paste exit code and output as the no-C4-impact evidence.
- [ ] 3.7 Vocabulary check against glossary.md; disclosure greps (no CVE identifiers, no exploit-shaped text); AC9 personal-data check.
- [ ] 3.8 `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` exits 0.
- [ ] 3.9 Run every acceptance-criterion command (AC1 through AC12) including the AC1 negative control.
- [ ] 3.10 After any ordinal bump, merge of origin/main or archive commit: re-run the ordinal census, Phase 3 steps 1, 2, 3, 6, AC1, AC2, and re-check #9854, PR #9832, PR #11592.

## Phase 4: Commit, ship, post-merge

- [ ] 4.1 Commit exact paths (two ADRs, plan, tasks.md, decision-challenges.md, session-state.md); never a directory add of `plans/`.
- [ ] 4.2 Review: soleur:engineering:review:user-impact-reviewer and soleur:engineering:review:security-sentinel on the ADR text; resolve or rule findings.
- [ ] 4.3 PR body: `Ref #9602`, `Ref #9601`, overlap with PR #9832 and #9854, "Preflight Check 4 skipped: it reads Doppler", "Net issue flow: 0 filed, 0 closed"; no `Closes`.
- [ ] 4.4 Ship archives the KB artifacts in the PR (Phase 6.45); compound writes no learning file for a clean session (ruling W); `bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh 11935` shows `Filing:  0`.
- [ ] 4.5 After merge: `gh issue comment 9602` with both ADR links and the remaining criterion (the proposed to adopting gate); leave #9602 open; do not close #9601 or tick any epic item.

## Stop condition

If the diff must touch any file outside the two ADRs and this feature's plan and spec files (docs/legal/, toggle copy, plugins/soleur/docs/, .github/, apps/, any .tf file, flag configuration): revert that file out of the diff, keep PR #11935 draft, file ONE `action-required` issue naming the action, record it in session-state.md and the PR body (ruling AA); do not rule around it. If any public or legal file enters the diff, the CLO is mandatory.
