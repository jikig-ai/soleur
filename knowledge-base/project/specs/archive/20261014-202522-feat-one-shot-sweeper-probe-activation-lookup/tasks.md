# Tasks: follow-through marker probes trust by collaborator permission (Ref #9818)

Plan: knowledge-base/project/plans/2026-10-13-fix-followthrough-probe-trust-by-collaborator-permission-plan.md
Constraints: no ci.yml / Actions settings / CI_PUSH_DEDUPE / CI_DRAFT_LIGHT changes; post no S2-/S3- marker; no tracker comment or body edit; PR text `Ref #9818` only; no ADR-270-as-evidence; no "canary closed".
Public helper name: `trusted_verdict_comments` (rulings D1/D1b used the name `trusted_marker_comments`; renamed at deepen-plan).

## Phase 0: Reproduce (RED), commit 1
- [x] 0.1 Dual-route fake gh (old REST comments route + new `issue view`/permission arms) and `privact` knob + `r_privmember` in scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh; run against the UNMODIFIED probe; require the `no activation on record` FAIL (rc 1) AND a `requests.log` line proving the REST route was hit; keep output for the PR body
- [x] 0.2 Same `r_privmember` in scripts/followthroughs/ci-draft-light-soak-9728.test.sh; RED on the unmodified probe

## Phase 1: Lib (separate commits)
- [x] 1.1 Behavior-preserving refactor of scripts/lib/trusted-verdict.sh (extract `_trusted_verdict_is_trusted_perm`, `_trusted_verdict_strip_fences`, `_trusted_verdict_core`; `trusted_verdict_bodies` = `.b` view; core does NOT validate createdAt; keep the `if ! _trusted_verdict_permission ... >/dev/null; then` line verbatim)
  - [x] 1.1.1 Gate: scripts/lib/trusted-verdict.test.sh + concierge-strand-754ee124-5733, cpx22-invoice-reconcile-7431, inngest-zot-client-authz-6500 suites pass unchanged
- [x] 1.2 Add `trusted_verdict_comments <issue> [repo]` (`{t,b}`, jq -c --arg emit, ISO regex on `t` only in this view, rc 2 with empty stdout otherwise); update lib header memo sentence, Usage block, rc comments
- [x] 1.3 Hardening (new behavior, after the gate): login-shape guard `^[A-Za-z0-9][A-Za-z0-9_-]{0,38}$` => untrusted with zero requests
- [x] 1.4 scripts/lib/trusted-verdict.test.sh: REFUSED log, `run_case_raw`, JSON permission arm with `--jq`, request logs, `mutant_lib` (multi-edit, anchor count 1), mutant floor; rows M-H1..M-H10 + 1.3 rows; mutants per the plan's Guard 1 matrix; raise MIN_ASSERTIONS to measured

## Phase 2: S2 probe (commit 2 removes the REST arm)
- [x] 2.1 Source the lib; tool-check loop + `base64 awk mktemp sort`; replace lines 100-103 with the helper call `|| fail_api` and a checked `jq -r .b | tr -d '\r'` projection
- [x] 2.2 Header (lines 21-31, `(d)` clause) + one mechanical sweep of "owner, member or collaborator" strings (grep tests first: must be empty)
- [x] 2.3 Harness: `issue view`/permission arms, REFUSED log, ISO createdAt on every comment, decoy `authorAssociation`, default activation by CONTRIBUTOR-admin; rows r_privmember/r_assocowner/r_permfail/r_badjq + requests.log assertion; `mk_tree` + lib symlink + crash detection ported from S3 + identity/no-symlink controls; re-anchor m-trusted/m-crlf, retire m-no-collab/m-contrib, add m-legacy-assoc/m-project-raw/m-empty-helper; set floors to measured counts

## Phase 3: S3 probe
- [x] 3.1 Migrate lines 109-113 and add `|| fail_api` to the projection (113) and to `conf_iso` (121); headers/strings/tool-check loop
- [x] 3.2 Harness migration (wiring rows only: r_privmember, r_late_conf_private, r_assocowner, r_permfail, r_badjq); move `mutant_probe`, shape loop and `mut-c-crash-rt.sh` check to the tree together; retire/replace mutants; set floors
- [x] 3.3 Verify no marker posted, no variable changed, #9707 and ci.yml untouched

## Phase 4: Lint
- [x] 4.1 Rule 5 with `# rule5-grep|strip|walk|exempt|loop|count` markers, regex canary, non-vacuous counter, override env `VARQ_BAN_MIN_RULE5_FILES`; header/summary/rule-4 paragraph rewrites
- [x] 4.2 Widen `LIB_CALL` to `trusted_verdict_(bodies|comments)` and `VERDICT_BRANCH` to `RESULT:|S[0-9]+-(ACTIVATED|DEACTIVATED|CONFIRMED|EXIT-CENSUS)` (pre-check no existing direct reader matches)
- [x] 4.3 Rows R5-M1..M10, R5-H1/H2; `rule 4:` assertion on R4-M2c; set floor to measured

## Phase 5: Docs
- [x] 5.1 Runbook: marker-probe view, read-time/retroactive-trust/write-scope/edit-time caveats, behavior changes, rule 5 pointer, reword "subsumed by rule 4"
- [x] 5.2 plugins/soleur/skills/ship/SKILL.md (~2799-2801) and references/followthrough-stub-template.sh (~50-66)
- [x] 5.3 Append dated correction to the 2026-10-09 learning
- [x] 5.4 One new learning (directory + topic only)

## Phase 6: Verify
- [x] 6.1 Run every suite, the ratchets (fixture-relative-assert, test-affected-kb-consumers), guard-contract and infra lints, shellcheck, directly; rebase on origin/main first (conflicts with #9788/#9554 expected)
- [x] 6.2 Read-only real-comment replay on #9818/#9728 with negative control and the #9777 pagination parity check

## Ship-time obligations
- File the deferred-scope-out issues listed in the plan's Deferred section (fence strip, unfiltered sentinel readers, github-community.sh tally, S3 stderr line if it survives, `.test.sh` directive path)
- PR body: `Ref #9818` only; advisory (not independent) owner review note; no operator checklist
