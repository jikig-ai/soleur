# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

- `dig` absent; DNS checked over DNS-over-HTTPS.
- A hook blocked a heredoc that contained a Doppler write example; it was rewritten with silent stdin-only writes.
- The first CTO ruling on the ssh/registry records (import, then replace) did not fit three A records per name; it was re-ruled to a pinned pre-delete.
- The guard-contract lint failed once on Guard 4; fixed.
- The Terraform-mechanics agent ended without its report and was asked again.

### Decisions

- Ruled by CTO agent, 2026-11-18: remove old ids from state, then import by new id; one Doppler id flip plus `cf_r2_account_id`; a dedicated `cf-account-migrate` dispatch with a plan gate; two PRs (redirects first, then tunnel and deploy hosts); Load Balancing, DNSSEC and Pro-only bot settings switched off in code.
- Plan review: the `app` record import moved to the tunnel phase; the rehearsal uses a local state copy; new tokens go to staging keys and swap together with the ids.
- Deepen: gate checks for no-op imports, real forced replaces and exact state-removal counts; apply legs behind the reviewer-gated environment; Origin CA re-mint before the redeploy; ADR-329 amends ADR-068 and ADR-321.

### Components Invoked

soleur:plan, soleur:plan-review, soleur:spec-templates, soleur:deepen-plan, soleur:engineering:cto, soleur:operations:coo, soleur:marketing:cmo, the dhh, kieran and code-simplicity reviewers, learnings-researcher, terraform-architect, security-sentinel, architecture-strategist.

## Operator Constraints

- Operator directive 2026-11-18: "go on #12931 migration restoring the redirects and deploy hosts".
- Do not dispatch apply-web-platform-infra.yml until the zone and account ids and the Terraform-minted tokens point at the new account.
- Never mutate or delete the old zone. No SSH to prod.

- cto_spawns=1 (technical-ruling gate: 30 applied-finding rows sent for ruling)

## Review: escalated full panel over fdf2aa5962..d075535c38 (2026-11-20)

14 seats at pin d075535c38. dedup: 71 raw -> 32 unique (1 P1-class gate gap, 4 P2, 27 P3).
Structural-cause roll-up: (a) a discriminator keyed on a proxy, not the property
(verify's single zone read, D1; the per-run forget marker, D7); (b) a hand lexer
re-derived each round (D12c normaliser, D5; A8 walk, D6), so both heuristics are deleted for
the platform's own parser or a stricter positive check.

| canonical defect key | reporting seat(s) | planned fix |
|---|---|---|
| D1 verify/Halt tell old from new by GET /zones/<new> for every key (narrow new tokens fail; all-zones old tokens pass) | git-history, security, architecture, data-integrity, simplicity, user-impact, observability, pattern, structural, agent-native | per-key read inside its grant on NEW must succeed AND same read on OLD must fail; stand-in per-key; Halt per-key + both-false stop |
| D2 verify swapped arm shares sentinel `a`: empty/unreadable live key reads ok | security, code-quality | both reads must succeed before compare |
| D3 token read twice (check vs bearer) | security, code-quality | single read, filter-and-emit |
| D4 gate expected-values leaves token members' destination attrs ungraded; header misstates | structural, pattern | pin non-value attrs, restate residual |
| D5 D12c awk normaliser desync ($'..') hides a live curl | test-design, simplicity | replace with bash --pretty-print |
| D6 A8 recursive walk guards unreachable states | simplicity | exempt workflows carry no job-level uses: |
| D7 cancel/restore guidance keyed on per-run backup=uploaded; forget=unknown undefined; Verify-first over-scoped | architecture, data-integrity, observability, pattern, agent-native | cross-run test (backup-uri comment / R2 listing), applying=true first, named gh commands |
| D8 Halt step 4 reads rehearsal plan, absence-only grep, names only 525 address | data-integrity, user-impact, observability | expected_in_state_updates input checked before applying=true; PASS line required |
| D9 job messages: verify-failed over-authorises edit; apply-failed forget sentence on zone-rest; apply-failed failing= omits Halt | architecture, agent-native | message text |
| D10 bootstrap ROLLBACK lines vs runbook revert; revert loses new tokens | architecture | qualify lines; copy KEY->_NEXT before restore |
| D11 import-block remedy needs class flip; half-applied zone-rest replace has no row; gptbot=>403 vs Halt | architecture, agent-native | runbook rows |
| D12 verify retries a 525/526 for its whole budget | user-impact | stop on first 525/526 app-health |
| D13 apply-failed 60s ceiling untested; "once" wording; job-suite weight/bound | performance | ceiling row, wording, weight 106000 + bound 720 |
| D14 prev-0a copies NEW into _PREV when KEY==NEXT; header residual omits interrupted swap | data-integrity, code-quality | refuse when KEY==NEXT digest; widen residual |
| D15 curl failure reads as re-mint/NOT_ACTIVE | pattern | unreachable marker with e=<rc> |
| D16 preflight case-folds ids | pattern | drop fold |
| D17 own_copies misses constant reassignment | pattern | add check + row |
| D18 timeout-minutes vs VERIFY_CAP unpinned | pattern | scope row |
| D19 gated_workflows misses reusable callers | pattern | include callers |
| D20 bootstrap failure markers without runbook action | pattern, agent-native | Halt bullets + coverage row |
| D21 A4 does not pin step shell/working-directory/defaults | test-design | refuse keys |
| D22 bootstrap mutation rows accept any non-zero (M0->P7) | test-design | pin failing step |
| D23 defines_lib_fn line-start anchor; LIB_FNS floor | test-design | widen anchor, exact count |
| D24 sources_lib binding not adjacency-pinned | test-design | next_line_is |
| D25 parity planner regex narrower than A6 | test-design | state residual (6) |
| D26 plan-time data http/external, provisioner on spec member unseen | structural | scope row refusing them |
| D27 rehearsal email "writes nothing" | structural | wording |
| D28 pipe-guard header archive boundary; cf-token-scope mode 100755 | git-history | header text; mode restore |
| D29 dead local `c`; pipe-guard \' in FAIL text | sast | trivial |
| D30 n_deep ordering; VERIFY_PASS_MAX hand-counted; /health no Location | simplicity, agent-native | reorder; derive; redirect_url |
| D31 grep -q rc 2 read as no marker (job:462) | code-quality | capture rc |
| D32 runbook "only" for in-state update too strong | architecture | scope sentence |
| D33 zone-rest apply has no live post-apply probe (zone settings / bot management can 526 the app or 403 GPTBot) | coverage consult | app-health + gptbot + noindex probes after zone-rest apply, verify-failed on failure |
| D34 old-id refusal points only at prd_terraform; loader's soleur-infra-privileged values win under --preserve-env | coverage consult | refusal text + runbook name both stores |
| D35 a Doppler-writing bootstrap stage can run while a migrate run is in flight | coverage consult | SOLEUR_CFAM_RUN_IN_FLIGHT refusal, fail closed on gh error |
| D36 gate replace arm accepts create-before-destroy; name-keyed doppler_secret would delete the key it wrote | coverage consult | delete-then-create only |

Wontfix: light-suite floor rows under CI (performance P3-4), including the bootstrap suite (now ~184 s local vs a 1802 ms floor, under the 600 s corpus cap) — advisory, regenerated at the next shard rebalance.
Coverage consult (5 leads): 4 verified and added (D33-D36); the GitHub repo-secret consumer lead was already handled at work time (plan, scheduled-followthrough-sweeper row).

### Verification pass (one seat, pinned 0f0b43d313)

0 P1, 2 P2, 7 P3. All fixed inline, or stated as residuals in the guard header:
- F1 (P2) runbook forget record read a gh error as "not committed": fail closed, all three sources required (2918ef51dd).
- F2 (P2) a 429/5xx/non-JSON OLD read made an old All-zones token read NEW: denial vs no-verdict split in bootstrap token_read (9fdb325c83) and job preflight (675b9ce281).
- F3 runbook swapped-prev-revoked remedy reads NEW and OLD (2918ef51dd). F4 job verify-failed Halt text follows the runbook ruling (675b9ce281).
- F5 swap ROLLBACK lines keep the new token in _NEXT; F9 run-in-flight scope stated as residual (9fdb325c83).
- F6 D12c glob/brace-expansion residual stated. F7 gate header names what vouches for token values (675b9ce281). F8 rehearsal-write refusals get a Halt bullet (2918ef51dd).
- CI lint-bot-statuses (shell-trace credential refusal) on bearer_get's PIPESTATUS line: fixed (9fdb325c83).
Below P3, not fixed: gptbot 525/526 still retries for the verify budget; gated_workflows does not follow a composite action that wraps infra-credentials (none exists).
