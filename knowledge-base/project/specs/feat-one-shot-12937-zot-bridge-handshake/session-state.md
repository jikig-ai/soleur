# Session State

## Plan Phase

- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12937-zot-bridge-handshake/knowledge-base/project/plans/2026-11-19-fix-zot-bridge-tunnel-hosts-after-zone-move-plan.md
- Status: complete

### Errors

- Plan-write hook flagged Phase 0 dashboard-only wording; resolved with iac-routing-ack marker and lint-infra-ignore block.
- gh run view --log-failed truncated; raw log fetched via REST. dig absent; DNS checks via DoH.
- Architecture reviewer first returned no findings text; re-asked.
- Plan review and deepen found and fixed: registry token never reaching Doppler, discoverability probe failing preflight, concurrent release re-runs colliding on the draft tag, unrepointed census and ci_ssh_token_replace consumers.

### Decisions

- Root cause: soleur.ai zone moved to the Soleur Cloudflare account about 16:24Z 2026-11-18; registry./ssh. are scanner A records (CF Error 1000), deploy. is NXDOMAIN; tunnel and Access apps remain in the old account and cfargotunnel CNAMEs route only within one account. zot and the tunnel are healthy.
- The 16:33Z supabase-ref-resolver failure is the same incident; no issue filed.
- Fix: CTO Option A, re-home only the tunnel slice into the Soleur account as new _soleur Terraform addresses, then replace web-2 to re-bake the connector.
- Visibility: classifier gains host-nxdomain, edge-error-NNNN, tunnel-down; SOLEUR_ZOT_BRIDGE marker; tunnel-zone authority drift step.
- PR uses Ref 12937 and Ref 12931; issue closed after prod serves the new SHA.

### Components Invoked

- soleur:plan, soleur:plan-review, soleur:deepen-plan; learnings-researcher, repo-research-analyst, functional-discovery, soleur:engineering:cto, soleur:operations:coo, dhh/kieran/code-simplicity reviewers, architecture-strategist, security-sentinel, observability-coverage-reviewer, terraform-architect, spec-flow-analyzer.

## Operator Constraints

- constraint: Diagnose first by self-pulling telemetry, registry host Better Stack rows for zot and cloudflared.
- constraint: Once the bridge is back, re-run the failed push runs for 5d4851f7af and 52bf12cc5b, then run postmerge for the 5d4851f7af merge.
- constraint: Follow-ons 12863 and 12920 are not in this PR.

## Technical Rulings

- cto_spawns=2

## Work Phase

- Status: code complete for Phases 1, 2, 2b (commits 90a90897a8..b19eae5331).
- Affected gate (run on c86b4b35bf+stub fix): rc=1. Real reds fixed (lint-shell-capture-exit S4 x2, fixture-relative-assert). Contention reds re-run in isolation green: trio-baseline-census 603/603, check-web-host-escrow-config 105/105, plugins/soleur bun 5848 tests with 2 unrelated fails (inngest-userdata-budget pre-existing #12850; pencil-adapter-stub-repl MCP timeout). Web-platform app suites killed under load left to CI (no app code touched).
- Blocked on operator: CF_API_TOKEN widening (Phase 0.1); placeholder deploy token id FILL-AT-PHASE-3.1 in tunnel.tf must be replaced before merge.

## Review Phase (re-review after the 2026-11-23 rework)

- Status: complete at 4a865f919c (pushed). Main (#13019 import-normalize) merged at 392d5371e2.
- CTO rulings 2026-11-25: pre-delete after every gate (amends F5); cf_migration_import_app validation stays deleted (amends D9 for that flag). Both recorded in decision-challenges.md.
- Panel: 7 report-only seats (security, data-integrity, terraform, deployment-verification, user-impact, test-design, structural). 54 findings: 53 fixed inline in 4a865f919c, 1 declined (DOPPLER_TOKEN_WRITE narrowing, decision-challenges.md). Pre-existing routine-path gaps filed as #13061.
- Suites green at 4a865f919c: gate 534/0, job 331/331, pre-delete 52/0, completion, runbook, scope, mint. Token-forget fails only S7 and Q8, the expected owner rows until the deploy token is minted.
- Scan gate: ok files=30 findings=341 over 62 of 63 paths. tests/scripts/test-argv-bearer-sweep.sh (8,270 lines) was excluded: shellcheck exhausted memory on it.
- Next: soleur:compound, then soleur:ship from Phase 5.4 (preflight); stop at the first operator go (step 3, minting the 0b tokens). No operator go has been given.

## CI Repair Round (2026-11-25, after merging origin/main at 96e83b380e)

- Merged origin/main (15 commits; carries cf-account-migrate bounds 3dfc0f9502, flatten_cname gate 27e84d0b4f, cf-token-scope probes 6baae09683/1ec95e1664, and main's pooled execution rewrite of cf-account-migrate-job.test.sh). Conflicts kept both sides; merged gate floor recounted 549/0.
- jq 1.7.1 incompatibility fixed: `[gen] + [gen]` concatenations inside an object literal need parentheses (CI runner jq is 1.7.1; local 1.8.2 parses both). Program line ~48 of build_plan().
- Pool-snapshot race fixed: the four [tunnel]-block headers used bare `printf`, so top-level `$SBX/mirror-tunnel` creation raced queued `red` rows -> POOL_SNAP_BAD. Converted to `section` (flushes first).
- web-1 private-IP ratchet: branch's new tunnel fixtures swapped to the #12910 convention (web-3 / 10.0.1.12; one comment literal dropped from verify-tunnel-ingress-origin.sh). IP_CEIL re-baselined 318 -> 314 (measured 314).
- argv-bearer sweep S4: the two new scripts joined S4_SCRIPT_MANIFEST + S4_REPLAY_FILES (floors 13->16, 26->29); `bc_curl` name args must be LITERAL script names (the suite's counts and name checks ignore `"$P"`); `source` hoisted textually before the first bc_* line; `2>/dev/null`/`>&1` discards removed from bc_curl calls (the refusal marker rides stderr).
- Pin drift absorbed: cherry-picked #12985's 4-line pin bump (v1.1.73 -> v1.1.74, soleur-infra[bot] 50e8a2d391). This PR now carries the bump; #12985 becomes redundant on merge. NOTE for the operator: merging this PR bumps the main pin to v1.1.74 before the mirror backfill has the digest in zot — the same window #12985's merge was withheld for. Sequence the merge after the bridge apply + a green mirror_only backfill, or accept the provisioning window (see resume prompt).
- Verified locally: cfamj suite green (pool batch integrity 14 batches, only expected instrument FAIL), gate 549/0, web-hosts-generic green, cloud-init-inngest-bootstrap 297/297, argv-bearer sweep 832/0, lint-infra-no-human-steps --changed clean.
- Still expected-red by design: `validate (apps/web-platform/infra)` + `infra-validate-required` (FILL-AT-PHASE-3.1); `test` (draft-mode verdict, clears on ready).
