# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-18-fix-host-roster-key-lease-host-id-web2-pre-heal-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=0 (main context; the planning subagent's CTO rounds are recorded in decision-challenges.md)

### Errors
- plan-sharp-edges.md read partially (over read limit); targeted grep + 13 relevant bullets read in full.
- Two hook-blocked `gh issue create` attempts for #12919 (variable body-file path; missing Mandated-By line); fixed and filed.
- A plan edit with a conditional `doppler secrets set` was blocked; the plan now prescribes no Doppler write (Phase 5 read-only, escalate on false).
- decision-challenges.md first failed the ruling gate (bad-class); fixed, gate passes with 18 rows.
- CTO's 120 s lease window was stale; live value 240 s (migration 133, LEASE_LIVENESS_WINDOW_MS).
- Deepen corrected T9: the post-merge release redeploy needs the owner's per-command go-ahead (operator production-mutating row); command needs `-f bump_type=patch`.

### Decisions
- Defect 1: lease placement id becomes the var.web_hosts key (web-1/web-2), derived in ci-deploy.sh from Hetzner metadata hostname (exact inverse of server.tf's name expression), injected as SOLEUR_HOST_KEY; resolveHostId() accepts it only when roster[key] equals the container's SOLEUR_HOST_PRIVATE_IP, else falls back to hetzner-<id>; key is sticky (3 retries, deploy aborts on a key change).
- Gate: lb-weight-gate.sh A.3 gains four fail codes against SOLEUR_WEB_HOSTS derived from committed variables.tf; census parity test pins name expression, inverse, regexes, no create_before_destroy.
- Defect 2 is a false-positive signal: the web-2 turn ran after the self-stop row; T8 narrows the pre-heal emit to a post-heal escaping file-pointer.
- No Doppler prd write needed: live SOLEUR_HOST_ROSTER already keyed web-1/web-2 with committed addresses; read-only re-check before merge; Terraform-generated roster deferred to #12919.
- Single PR; post-merge: pipeline-fix apply, owner-approved redeploy, verify host_key resolved=web-N on both hosts, web-2 stays at weight 0 until then, then one owner-authorized serve to prove AC-P3.

### Components Invoked
soleur:plan, soleur:deepen-plan, plan-review panel (dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer), soleur:engineering:cto (R1-R4, T1-T11), soleur:product:cpo, advisor consult, repo-research-analyst, learnings-researcher, functional-discovery, deepen research agents, betterstack-query.sh, collision-precheck.sh, technical-ruling-gate.sh, lint-guard-contract.py, lint-infra-no-human-steps.py, c4-count-parity.test.sh, prepush-secret-scan.sh.

### Post-planning re-probe (2026-11-18)
- #12910 and #8211 open; #12919 open (deferral). Overlap preflight exit=13: PRs 12704 and 12897 share apps/web-platform/server/cc-dispatcher.ts only (different features); continue.

## Operator Constraints

- constraint: never git stash
- constraint: no secrets on argv or in output
- constraint: prepush-secret-scan before any push
- constraint: merge only via `bash plugins/soleur/scripts/lib/session-state.sh with_lock merge-main 600 -- gh pr merge <n> --squash --auto`
- constraint: owner-gated: any further serve/drain dispatch, Doppler writes, host replace
- constraint: machine saturated, single test files only, scratch under /var/tmp
- constraint: don't touch #12330, #11694, #11676, #11669, #10476

## Work Phase
- Phase 0 (2026-11-18): live SOLEUR_HOST_ROSTER keys = [web-1, web-2], both addresses match var.web_hosts; no Doppler write.
- Phase 1 done (3086ba3244). Phase 2: ci-deploy.sh resolve_host_key + T3 sticky check (top of the web-platform branch, before any prune/pull/run); retry only on a failed curl (an empty answer is final, keeps harness deploys fast); env-file refusal dropped (T1 verification makes a Doppler-set key inert).
- Phase 3 (0c4b50566b), Phase 4, Phase 6 (ADR-068 addendum via soleur:architecture; no amend sub-command, appended directly; domain-model.md has no host_id row, 8.5 skipped).

## QA (2026-11-20, HEAD cf3d30a1f1 + QA edits)
- Phase 5 roster read (read-only, booleans only): `{"keys":["web-1","web-2"],"web1_ok":true,"web2_ok":true,"n":2}` (AC9).
- Automated QA skipped: the plan's Test Scenarios carry no Browser:/API verify: steps; coverage is the single-file suites (ci-deploy 833/833, docker-run-tuple 366, web-hosts-generic 58, cat-deploy-state 167, inngest-inventory 173, fresh-boot-ready 75, lb-weight-gate-with-marker OK, inngest-link-resolver OK; vitest host-identity 57, session-router 21, real-factory 146, worktree-validity 24, boot-wiring 7, ws-handler-proxied-attach 8, session-proxy-hello 83; tsc 0).
- AC8 amended in place (the curl-flag line); AC10 technical-ruling-gate PASS (27 rows).
- CI at c762b36c93: 54 pass / 3 fail = draft-light `test` aggregator + `deploy-script-tests (4/4)` inngest pin red inherited from main (bump PR #12985) + its roll-up.
