# Tasks: follow-through marker probes trust by collaborator permission (Ref #9818)

Plan: knowledge-base/project/plans/2026-10-13-fix-followthrough-probe-trust-by-collaborator-permission-plan.md
Constraints: no ci.yml / Actions settings / CI_PUSH_DEDUPE / CI_DRAFT_LIGHT changes; post no S2-/S3- marker; no tracker comment or body edit; PR text `Ref #9818` only.

## Phase 0: Reproduce (RED)
- 0.1 Add `privact` knob + row `r_privmember` to scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh; run against the UNMODIFIED probe, require the `no activation on record` FAIL (rc 1); keep output for the PR body
- 0.2 Same `r_privmember` in scripts/followthroughs/ci-draft-light-soak-9728.test.sh; require RED on the unmodified probe

## Phase 1: Lib core + two views (contract first)
- 1.1 Behavior-preserving refactor of scripts/lib/trusted-verdict.sh: extract `_trusted_verdict_is_trusted_perm`, `_trusted_verdict_strip_fences`, internal core; `trusted_verdict_bodies` = `.b` view
  - 1.1.1 Gate: scripts/lib/trusted-verdict.test.sh + concierge-strand-754ee124-5733, cpx22-invoice-reconcile-7431, inngest-zot-client-authz-6500 suites pass unchanged (separate commit)
- 1.2 Add `trusted_marker_comments <issue> [repo]` (`{t,b}` per trusted comment, `t` = createdAt, fail closed on missing/non-ISO createdAt, rc 2 with no partial output)
- 1.3 Extend scripts/lib/trusted-verdict.test.sh: `mutant_lib` helper, rows M-H1..M-H10, lib mutants, raise MIN_ASSERTIONS to measured

## Phase 2: S2 probe
- 2.1 Source the lib; replace lines 100-103 with `trusted_marker_comments ... || fail_api`; `jq -r .b | tr -d '\r'`
- 2.2 Update header comment (lines 21-31) and runtime strings ("owner, member or collaborator") after confirming no row asserts them
- 2.3 Harness: fake gh `issue view` + permission arms, decoy `authorAssociation`, rows r_privmember/r_assocowner/r_permfail/r_manycomments, requests.log assertion
  - 2.3.1 Mutation tree: mirrored dirs, lib symlink, identity-copy green row, no `No such file`; re-anchor m-trusted/m-crlf, retire m-no-collab/m-contrib, add m-project-raw/m-empty-helper
  - 2.3.2 Recompute `_FLOOR`, mutant floor, always-PASS reds from measured counts

## Phase 3: S3 probe
- 3.1 Migrate lines 109-113 and headers/strings
- 3.2 Harness migration (wiring rows only) incl. r_late_conf_private; recompute floors; file a deferred-scope-out issue only if the `requests.log` stderr line still reproduces
- 3.3 Verify no marker posted, no variable changed, #9707 and ci.yml untouched

## Phase 4: Lint rule 5
- 4.1 Add rule 5 (`# rule5-grep`, `# rule5-count`, own counter/floor with test override), update header/summary/clean-line, fix rule-4 "not banned" sentence
- 4.2 Widen `LIB_CALL` to `trusted_verdict_bodies|trusted_marker_comments`
- 4.3 Rows R5-M1..M8, R5-H1/H2; add `rule 4:` assertion to R4-M2c; raise floor to measured

## Phase 5: Docs
- 5.1 Runbook sentence + rule 5 pointer
- 5.2 Append dated correction to the 2026-10-09 learning
- 5.3 One new learning (rule 4 anchor miss, live-but-masked S3 sibling, two-tokens-same-code method)

## Phase 6: Verify
- 6.1 Run every suite, ratchets (fixture-relative-assert, test-affected-kb-consumers), guard-contract and infra lints, shellcheck, directly
- 6.2 Read-only real-comment replay on #9818/#9728 with negative control
