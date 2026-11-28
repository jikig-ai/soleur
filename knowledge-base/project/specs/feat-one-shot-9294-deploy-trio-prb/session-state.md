# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-9294-deploy-trio-prb/knowledge-base/project/plans/2026-11-20-feat-deploy-trio-consumer-migration-prb-plan.md
- Status: complete
- Plan artifact: complete (selector=branch; planning subagent f123c22b, sequential-fallback deepen-plan)

### Resume 2026-11-27 (second session)
- Picked up abandoned: worktree cold since 2026-11-20, PR #13006 still WIP draft, 5 real commits unpushed; WIP preserved as checkpoint 2fc97d058e.
- Verified committed state: zero `secrets.<trio>` binds under .github/; all consumers bind `environment: deploy-channel` + narrow loader; probe retirement + doc de-shapes landed.
- Fixed two self-inflicted census failures: doppler-read.sh `run` mode gained --preserve-env (G2a); 4 lever prose lines reverted to main's `doppler run --name-transformer tf-var` form (G2b — `bash <path>` inside quoted prose counts as an invocation).
- argv-bearer-sweep migrated to the canonical `WEBHOOK_DEPLOY_SECRET` spelling (HM_CANON→deploy spelling, HM_PFX_LEGACY for the two host-side infra scripts, per-target S4 prefixes); stale inngest-soak-6178 refs removed (HMAC_MANIFEST row, lint-betterstack entry, 2 test-affected-paths rows, TSV regen).
- Trio-baseline end state: 18 tier-b + 52 sink + 5 @allow rows, zero tier-a; floor 603→619.
- ADR-241 amendment + index bullet appended (2026-11-27); model.c4 STATUS clause + env enumeration + consumer wording refreshed.
- Remaining: argv-sweep green confirmation, commit+push, PR body postcondition slot (task 9.3), ready for review.

### Resume 2026-11-27 (argv-sweep failure round, third session)
- argv-bearer-sweep 784/41 -> **825/0 green** (floor re-pinned 832->825 with the history comment).
- Fixes: s4_decl_py models the narrow loader (jobs calling infra-credentials with doppler-project=soleur-deploy-channel declare the trio, like HCLOUD_TOKEN for the broad arm); s4_b7_py ambient-trio + de-shaped trim judgement (dcanon lines in s4_trim_py; ambient names count only when the step body uses them — the RESEND-only email step); s4_b7_mut per-name pair rewrites; VTIO mutants redirect the $INFRA_DIR-relative doppler-read.sh call to the stub `doppler run` form; _bs_read_remedy rc1 arm text updated; S7 exec blocks get a $S7_X/scripts/lib/doppler-read.sh stub; HM5 census audited set += cutover-inngest.sh (its 19-copy audit, not hm5_audit); S4_INLINE_FILES += the two HM5 scripts (7 files).
- trio-baseline.tsv: restored the 3 tier-a rows for tests/scripts/test-argv-bearer-sweep.sh (the checkpoint regen had dropped them; the suite file names the trio).
- trio-census 618/1 — sole failure is T4 `scripts/cutover-inngest.sh WEBHOOK_DEPLOY_SECRET` (new key, needs the spent @allow at merge-base): PR #13087 (@allow reservation, ready-for-review, CI green) must merge, then PR-B rebases.
- Lever fix verified via tier-census: doppler-read.sh tf mode self-locates (cd apps/web-platform/infra); the 4 levers rewritten to root-relative `bash scripts/lib/doppler-read.sh tf ...` form.

### Errors
- Collision detector exit=10: PR #13006 is this branch's own WIP draft; two `test-all.sh` PIDs in sibling worktree feat-one-shot-12931-cf-account-migration. Recorded as decision row D-7; no action.
- `gh pr view --json merged` field rejection; corrected via mergeCommit/mergedAt — #12810 confirmed MERGED (squash 9cfcc7f47).
- markdownlint MD004 fixed before commit.

### Decisions
- Consumer set re-derived live: 11 workflows; inngest-link-flip.yml/key-rotate.yml/inngest-key-rotate.yml added vs issue list; git-data-cutover.yml/apply-web-platform-infra.yml/7220/5875 scripts no longer name the trio; apply-deploy-pipeline-fix.yml keeps 3 tier-a rows (non-trio doppler reads) — decision point D-2.
- Sweeper partition: exclusive two-arm design with coverage refusal; flag surface `pending - assumed:` (D-1) — flagged for parent CTO spawn.
- Baseline end-state rule adopted verbatim; scanner class refinement assumed as D-2 remedy — CTO-flagged.
- #6178 verified CLOSED → probe + test + function-ids.txt + test-all.sh line deleted in one diff; two live citations (sweeper.yml:135, grep-q-pipe-guard.test.sh:2215) in work-list.

### Components Invoked
- soleur:plan (skeleton → full body, Scope Check, Guard Contract lint green, plan-sharp-edges, markdownlint)
- soleur:deepen-plan (sequential — Reviewed-Coverage: sequential-fallback; halts 4.5–4.13; §4.45 self-audit; WebSearch verification)
- scripts/lint-guard-contract.py, npx markdownlint-cli2, gh CLI, git grep census

### Rulings (pre-work CTO spawn — resolved)
- cto_spawns=2 (first spawn returned an empty report; re-spawn in foreground delivered all rulings). Agent-round tally incremented by 2.
- technical-ruling-gate.sh: PASS, 9 rows, 2026-11-20 — all `pending - assumed`/`assumed` cells rewritten in canonical form.
- Outcomes: D-1 derive trio set from `@stems` (fail-closed parse, both arms); D-2 pinned scanner refinement (targeted non-family `secrets get` uncounted; bulk `doppler` exempt only with literal `-p`+`-c` outside the pinned trio-carrying set; fail closed); D-3 keep both flags; D-4 delete #6178 probe+pin+test+run_suite in one diff; D-6 third env arm confirmed (arm-extraction verified); D-7 no action; D-8 job-level `environment:` on both naming jobs + `${!_v}` de-shape.

## Operator Constraints

- constraint: operator-authorized live steps — apply/seed the deploy-channel carrier, verify the main-only environment policy, migrate workflow consumers, delete old credential copies, rotate the trio.
- constraint: #12937 zot-mirror CF-tunnel outage is pinning all releases at 43234154a2.

no ci-is-the-gate token written (silent brief — no reliance instruction)

## 2026-11-27 late — post-rebase CI repaired, panel spawning

HEAD d1d41f413e (Jean-authored; CLA green). Fixes pushed: N3b de-carry (skill points at runbook 6894 §5c, zero-count pin, mutation rows repurposed as insertion tests — 286/0 green), ADR census end-state corrected (3 tier-a residual rows on argv-bearer fixture monolith acknowledged, #13102, fuse 2026-11-30), model.c4 brace-folded + re-rendered (census 619/0, c4 freshness green).

**Review state**: tier `aggregate pattern`. PANEL_SHA=329d32ddc7 (design pass ran there; panel spawns at d1d41f413e, fix-round coverage for the delta). Design pass DONE: simplicity + strategist verdicts mechanism-justified; open items for synthesis: P1-2 doppler-read.sh census-invisible bulk-read broker (no project allowlist; `run soleur prd` into env-less jobs), P1-3 Doppler control-plane availability correlation incl. watchdog. P1-1 FIXED in diff. Scan receipt (fresh at d1d41f413e): `SOLEUR_REVIEW_SCAN_GATE ok engine=mixed files=32 rules=219 findings=1252`, argv-bearer excluded (#13098/#13099).

**Resume if interrupted**: 11 panel seats spawned in background (git-history, pattern-recognition, security-sentinel, performance-oracle, data-integrity, agent-native, code-quality, user-impact, structural-enumeration, test-design, semgrep-sast). Collect reports → synthesize with dedup ledger → fix dispositions → emit trailer via emit-review-trailer.sh (`Reviewed-Risk-Tier: aggregate pattern`) → CTO domain-ruling (workflows+infra touched) → Review-Evidence comment (domain-ruling=CTO, scan receipt quoted, exclusion disclosed) → merge per evidence gate. shellcheck seat = lead quotes receipt in synthesis (no agent file). SKEPTICS=3 for the workflow. Also pending: verify full CI green on d1d41f413e.

## Review round (2026-11-27, panel SHA 329d32ddc7 / HEAD d1d41f413e)

Scan gate: ok (mixed, 31 files; test-argv-bearer-sweep.sh EXCLUDED per operator — shellcheck runaway, tech-debt issue filed). Design pass: both seats conditionally justified all 3 mechanisms. Main panel: 9 seats.

### Findings inventory (status: FIXED / PENDING / TRIAGE)
1. P1 live-verify cd-path (git-history): `.github/workflows/web-platform-release.yml` :2375 invoked repo-root-relative `scripts/lib/doppler-read.sh` after `cd apps/web-platform` → BLOCK on every release. FIXED: `$GITHUB_WORKSPACE`-absolute.
2. P2 trio-baseline.tsv lost 76-line hand-kept prose header (arch/git-history). FIXED: header restored w/ D-2-updated class semantics + D-1 @stems-consumer mitigation; census re-verified 619/0.
3. P1 doppler-read.sh fail-open (cqa): no argc guards, hash pipefail-less, bs `|| true` empty-cred success. FIXED: arity validation all modes, fail-closed reads, empty-value refusal; 8/8 behavioral probes green; bs batching (perf P3) deliberately NOT done — multi-name --json shape unverified, ops-critical; sequential --plain kept. Disposition note for synthesis.
4. P1 classifier `--timeout` hole (tdr): value-taking global flags before subcommand parse as boolean → fail-open. PENDING FIX: invert unknown pre-subcommand flags to fail-closed + add --timeout to _DOP_VALFLAG + probes/mutations.
5. P1 G1l expression bypass (tdr): `environment: ${{ inputs.e || 'deploy-channel' }}` passes as literal. NOTE tension: D-6 settled shape `(rollback||resume||backup) && 'inngest-cutover' || 'deploy-channel'` is itself an expression — rule must be "every possible resolution is a Tier-B literal", not "no expressions". PENDING FIX.
6. P1 sweeper partition missing Guard-2 tests (cqa): sweep-followthroughs.test.sh unchanged, zero FT_ARM coverage; plan :483-499 prescribes 4-row mutation matrix. PENDING FIX — biggest work item.
7. P2 infra-tier assertion FLOOR stale: 474 vs measured 501, and lower-bound-only despite "exact" comments (tdr). PENDING: bump to 501 exactness decision.
8. P2 quadratic classifier worst-case (perf): per-occurrence suffix rescan O(k·len); measured 0.865s @40KB single line. PENDING: segment-once tokenization.
9. P2 github-app-key-status.sh stale prd_terraform operator text (cqa, also arch P3). PENDING.
10. P2 stale "no checkout" comments (cqa): deploy-inngest-image.yml:66, web-platform-release.yml:1465,1634,1677,1903,2011. PENDING.
11. P3s: ensure-doppler.sh capital-D `Doppler login` (csr/git-history); fetch-depth:0 in sweep-deploy-channel unneeded (perf); jq whole-payload reparse (perf, pre-existing pattern); TIER_B_NAMES[-3:] positional fragility (tdr); infra-config-verify.sh:497 half-prose recovery string (cqa); checkout persist-credentials inconsistency (cqa); embedded-python duplication (cqa, disposition: deliberate defense-in-depth, document).
12. RETIRED: csr's "zero tier-a ADR contradiction" — architecture correct, ADR:1286-1289 accurately discloses 3-row residual scoped to #13102. Seats also confirmed branch==origin at d1d41f413e; b69cc3d76e is a dangling pre-rebase SHA, not divergence.
13. Wrapper-relay census invisibility (arch P2-2): doppler-read.sh call sites produce no rows. TRIAGE at synthesis — sanction-by-design vs classifier extension; likely CTO-dissent or follow-up since lib is the D-2-sanctioned indirection.

### Seats still out at checkpoint
c7dca599 (pattern-recognition?), security-sentinel 1beb43ba, data-integrity fdbdf0f8, enum-retry 1c26580f, user-impact f1a36a24.

### Verification state
census 619/0 WITH restored header. argv-bearer + infra-tier NOT rerun since lib/path fixes (needed in fix-round). Fix-round review per ADR-267 required over fix range before qa/ship.

### Security-sentinel findings (late arrival, post-checkpoint)
14. P1 APP_DOMAIN_BASE branch-plantable redirector — CONFIRMED REAL, task 4.4 was checked but the reads remain:
    `infra-config-verify.sh:48`, `verify-tunnel-ingress-origin.sh:136`, `apply-deploy-pipeline-fix.yml` (:2171 + repetitions
    :653/:702, :849/:863, :1233/:1260, :2471/:2486) all still `doppler secrets get APP_DOMAIN_BASE ... || echo soleur.ai` —
    the fallback fires only on read FAILURE, a planted value wins. Threat: branch actor plants APP_DOMAIN_BASE in
    prd_terraform (DOPPLER_TOKEN_WRITE is repo-secret-writable per loader action.yml:30-34) → next main apply sends
    CF Access pair + valid body-only HMAC (replayable, no nonce/timestamp) to attacker domain. ALSO the tf-var vector:
    doppler-read.sh tf uses --preserve-env + --name-transformer tf-var and nothing exports canonical TF_VAR_app_domain_base,
    so a planted APP_DOMAIN_BASE injects as TF_VAR_app_domain_base and redirects even the terraform-driven push-infra-config.sh path.
    FIX per plan :207-216 (prescribed, task 4.4): use committed scripts/derive-app-domain-base.sh derivation at every site;
    pin/export canonical TF_VAR_app_domain_base for tf invocations; regression-test the planted-value case.
    Sites enumerated in the security seat report. THIS IS THE TOP REMAINING FIX.
15. Security seat verified clean: no pull_request trigger paths to the trio, workflow_run trust gate intact,
    checkouts persist-credentials:false, loader fails closed, no residual secrets.WEBHOOK_DEPLOY_SECRET/CF_ACCESS_* binds,
    host fetch helper restrictive perms, hash callers guard empty. Its live-verify P2 duplicates already-fixed finding 1.

### Remaining seats at this point: c7dca599, fdbdf0f8 (data-integrity), 1c26580f (enum), f1a36a24 (user-impact).
### NEXT ACTIONS in order: (1) collect remaining 4 seats; (2) fix APP_DOMAIN_BASE P1 (#14) — biggest;
### (3) classifier --timeout inversion + probes/mutations (#4); (4) G1l literal-resolution rule + mutations (#5);
### (5) Guard-2 sweeper tests (#6); (6) P2 batch: floor 474→measured exactness, quadratic segment-once, github-app-key-status,
### stale no-checkout comments, derive/fix smalls; (7) triage wrapper-relay census invisibility (#13) — disposition
### (sanctioned-indirection vs classifier extension, possibly follow-up issue); (8) rerun affected suites (trio census,
### infra-tier census, key/cutover workflow tests) bounded; (9) commit+push; (10) ADR-267 fix-round review over fix range
### 329d32ddc7..HEAD; (11) soleur:qa; (12) soleur:ship → merge #13006. Operator tail post-merge is RESERVED (seed
### doppler trio copies, delete Tier-A copies after green canaries, rotate) — never perform it.

## Fix-round progress checkpoint 2 (commits d3165228dd, 04d40b270b)

FIXED + VALIDATED since the first checkpoint:
- #14 APP_DOMAIN_BASE P1 CLOSED (d3165228dd): 8 direct-read sites now derive from committed variables.tf
  (2 more sites found in apply-web-platform-infra.yml :4886/:5303 the seat missed — also converted);
  infra-config-verify.sh + verify-tunnel-ingress-origin.sh are pure env consumers with :? guards;
  doppler-read.sh tf pins canonical TF_VAR_app_domain_base before bulk injection (tf-var vector closed);
  ship/SKILL.md snippet converted. infra-config-verify.test.sh 55/0 GREEN (I6c/I6d/T6 rewritten to the
  stronger zero-doppler contract); argv-bearer harness updated (vt_run + S4 r21 sentinel env + S7X derive stub).
- #4 --timeout hole CLOSED (04d40b270b): full global value-flag grammar modeled, modeled booleans skip,
  unknown pre-subcommand flags fail closed. Probes N26-N30 green. Trio census floor 619->624 exact. Suite green.
- #5 G1l expression bypass CLOSED (04d40b270b): literalness enforced on raw env value (`${{` forbidden);
  TRIO_REF now case-insensitive (secrets context resolves case-insensitively). Mutation rows g1l-6/7/8 green.
  MUTANT_FLOOR 201->204 exact. ipt suite 507/0 GREEN. FLOOR 474->507 (tdr P2 closed) — uncommitted at this checkpoint.
- #9 github-app-key-status.sh converted (04d40b270b). #10 no-checkout comments corrected ×7. capital-D fixed.
- G2b spelling fix: plain ${GITHUB_WORKSPACE} in derive invocations.

STILL OPEN (in priority order):
- #6 Guard-2 sweeper partition tests — IN PROGRESS NOW. Plan :483-499 mutation matrix (4 rows).
  Harness: scripts/sweep-followthroughs.test.sh (2371 lines, MIN_ASSERTIONS=334), stubbed-gh pattern,
  pass/fail ledger with conservation identity. ALSO user-impact FINDING 3: @stems family variants
  (_NEXT/TF_VAR_/lowercase) not in the sweeper's runtime set — rotation-time trackers escape both arms;
  decide: extend runtime set or document. AND enum-seat sweeper holes (whitespace/repeated/fenced directives,
  FT_ARM empty→sweep collapse) — triage as pre-existing parser fragility vs in-scope.
- #13/#F1 wrapper-relay census visibility (user-impact P1, arch P2-2): doppler-read.sh invocations are
  glued-suffix-excluded from _DOP_WORD so produce no read shapes. DESIGN TENSION: full visibility flips
  web-platform-release.yml tier-b→tier-a which HAS NO ratchet lane. Disposition options: (a) count wrapper
  invocations only for the two POST-deletion carriers (deploy-channel/infra-privileged pairs) — but inconsistent
  with literal-shape counting; (b) document as accepted residual + follow-up issue; (c) full visibility +
  ADR-ruled reclass. NOT YET DECIDED — needs empirical check of which files naming the trio invoke the wrapper.
- #8 quadratic classifier (perf P2) — segment-once tokenization, not yet done.
- P3 batch remaining: fetch-depth:0 in sweep-deploy-channel (perf), infra-config-verify.sh:497 half-prose (cqa),
  TIER_B_NAMES[-3:] positional fragility (tdr), jq reparse (perf, low), checkout persist-credentials inconsistency
  (cqa, pre-existing), embedded-python duplication (cqa — disposition: deliberate, document), phantom _NOT_SET
  baseline keys (user-impact F4), data-integrity P2 tail-gate wording (operator-tail guidance — PR BODY update,
  not code), seeding-order P3 wording contradiction (ADR/PR body — verify whether seed already done).
- enum-seat G1l residuals beyond the fixed items: secrets:inherit/composite-internals/noncanonical copies/
  dynamic access — mostly documented blind spots or sibling-row coverage; triage in synthesis.

VERIFICATION QUEUE before fix-round review: argv-bearer rerun2 result (was running), then commit floors,
then implement Guard-2, then full three-suite validation + commit + push, then ADR-267 fix-round review
over 329d32ddc7..HEAD, then qa, then ship → merge #13006.

## 2026-11-27 ~23:30 — PANEL SYNTHESIS INPUT (9/11 seats in; structural-enumeration a0617cf8 + semgrep-sast 3100e412 rate-limited, resume when limit clears)

**PANEL VERDICT: BLOCKER-MERGE convergent across 7 of 9 reporting seats. NO merge, NO trailer yet. Fix round required.**

### BLOCKER findings (dedup ledger)

1. **[CONVERGENT ×4 — sentinel/pattern/data-integrity/design-P1-2] census-invisible broker.** `doppler-read.sh run <proj> <cfg>` accepts arbitrary pairs, bulk-injects trio-carrying `(soleur,prd)` into env-less web-platform-release.yml jobs (migrate/verify/live-verify at :1086,1141,1281,2337,2375) on Tier-A tokens, while those files were reclassified tier-b/sink — false end-state. Fix direction: teach census the broker call shapes + mutation rows, OR forbid trio-carrying pairs/dynamic names in broker (allowlist per mode like infra-credentials' two-literal), or split `run` into purpose-specific injectors.
2. **[pattern] D-2 exemption NOT inheritance-aware.** `doppler run -p soleur -c prd_workspaces_luks_marker` inherits prd (documented in model.c4 itself!) yet exempts. False-negative hole in census ratchet. Fix: treat inheriting soleur production configs as carrying, or drop negative exemption unless inheritance proven absent.
3. **[agent-native] live-verify BROKEN PATH.** web-platform-release.yml:2368-2442 does `cd apps/web-platform` then `bash scripts/lib/doppler-read.sh` — doesn't exist (needs `../../scripts/`). Every live-verify job fails closed as `no-result-line`. Must fix.
4. **[CONVERGENT ×3 — pattern/agent-native/code-quality] ship SKILL.md wrong mode.** :1066-1067,1100-1101 prescribe `doppler-read.sh run soleur prd_terraform terraform …` — `run` injects raw uppercase WITHOUT `--name-transformer tf-var`; only `tf` mode produces TF_VAR_*. Production recovery instructions broken as written. Also apply-deploy-pipeline-fix.yml:1446,1917,1971,1974 remedies don't end-to-end (missing AWS backend pair precondition per infra-credential-tiers-8209.md:954-966).
5. **[test-design + data-integrity CONVERGENT] sweep-followthroughs FT_ARM partition ZERO test coverage** — no test matches FT_ARM/TRIO_DECLARED/TRIO_RAN/load_trio_set anywhere. PLUS [data-integrity NEW] ordering hole: missing-script return at :627-634 runs BEFORE partition classification — tracker with missing script is neither declared nor run, zero-probes red can't fire (false-green). Fix: classify/count partition before existence returns + full mutation-pinned fixture battery.
6. **[git-history] REBASE STALE AGAIN.** main moved post-rebase: suite-shard-legs.tsv/suite-durations.tsv now n=12 (branch n=8), cf-old-login-token-remint suites added, inngest-soak-6178 still on main but branch removes it. Must rebase onto current main preserving CF suites, regenerate TSVs. NOTE: floor arithmetic actually MUTANT_FLOOR=208/FLOOR=619 on both trees — my rebase-resolution history comment (196+5=201) was wrong-shape; realized state may still be correct, verify don't cite.

### HIGH/MEDIUM non-blocking (fix-round or tightly-scoped follow-ups)

7. [user-impact+perf CONVERGENT] loader observability: `doppler secrets download` stderr to file never printed; outage reads as token-misconfig. Classify rc, name vendor-outage possibility. Bound network legs: curl --connect-timeout/--max-time, `timeout` on doppler download, timeout-minutes on loader steps (perf MEDIUM). CLI tarball caching — non-secret sha256-pinned, ~500MB/day watchdog traffic (perf MEDIUM).
8. [user-impact] watchdog probe-unavailable path unreachable: loader failure aborts job before probe; pages shape-identical to real inngest-down, no tracking issue. Fix: probe runs despite loader failure so `secret_unset`/`[ci/inngest-probe-unavailable]` path fires.
9. [sentinel+design] GITHUB_ENV lifetime widening step→job (GH_TOKEN-carrying steps incl.) — acceptable only as explicitly owned residual in ADR or per-step scoping. TF_VAR duplication on non-TF consumers (hygiene). op=backup double-carrier precedence (pin or skip narrow loader).
10. [code-quality ×several] broker contract defects: run --preserve-env precedence inversion on prod migrate path (stray DATABASE_URL steers prod!); hash no pipefail (doppler failure hashes empty, rc=0); cd unchecked + competing cwd authorities with KR_INFRA_DIR; tf hardcodes -p/-c leaving dead DOPPLER_PROJECT/CONFIG env in workflow; no arity validation; bs mode silent-empty (×3 seats — suppresses real Doppler error, misclassifies as missing creds).
11. [pattern/code-quality] betterstack-query.sh:30-32,95-100 + one-shot SKILL:297 + reproduce-bug SKILL:51 still prescribe bulk `doppler run -p soleur -c prd_terraform` — consolidate to bs mode.
12. [agent-native] infra-config-verify.sh:497 prose replaced copy-pasteable recovery command — restore full command. cutover-inngest.sh remedies need cwd precondition. restart/canary headers need dispatch-main-only + local fallback note.
13. [data-integrity] ADR-168 measured wrong-config but NOT cross-project or `run` verb — vendor docs say service-token project/config precedence may invalidate D-2 exemption: measure pinned-CLI matrix.
14. [git-history] plan never amended: AC3/P4 still certify zero tier-a — amend plan or record post-plan variance (ADR already corrected).
15. [test-design] narrow loader no_credential_source only grep-pinned; file has R22 render-harness standard — execution-test it.
16. [user-impact] seed-before-merge is process-only: if merged before operator seeds deploy-channel token, 15-min probe error-pages constantly. PR body must record seed verification as merge precondition.
17. [pattern MINOR] checkout persist-credentials:false divergence restart/health vs deploy-image/canary.

### Positive confirmations (defended items)
- N3b zero-count de-carry did NOT weaken protection (sentinel INFO + test-design verified anchor cardinality, insertion coverage equal-or-stronger).
- @allow spend shape correct (git-history PASS); ADR correction accurate; brace-folding effective; D-2 pcase/mutant pinning well-designed (test-design); no user-observable product surface change (user-impact); no material parser quadratic (perf INFO).

### RESUME INSTRUCTIONS
1. Resume seats a0617cf8 (structural-enumeration) + 3100e412 (semgrep-sast) when rate limit clears (~15min windows) — `run_subagent resume`.
2. Run fix round addressing BLOCKERS 1-6 first (they interact: broker/census fixes overlap). This is hours of work — consider which are in-PR vs follow-up, but note seats rated them BLOCKER because they falsify the certified end-state or break production paths NOW.
3. Rebase onto current main (BLOCKER 6) before any merge.
4. Then: `--fix-round` review per risk-tier-and-fix-rounds.md on the fix range (seats re-review delta), fresh scan receipt, then synthesis → trailer (Reviewed-Risk-Tier: aggregate pattern) → CTO domain-ruling → evidence comment → merge.
5. Census/correctness verification commands: `bash tests/scripts/test-trio-baseline-census.sh` (619/0 green at d1d41f413e), `bash plugins/soleur/test/sole-copy-drift-check.test.sh` (286/0), `bash plugins/soleur/test/c4-model-freshness.test.sh`.
6. EXPIRY FUSE: tier-a rows expire 2026-11-30 — 3 days. If merge slips past, need ruled Re-date in separate baseline/ADR-only PR (#13102 tracks).
