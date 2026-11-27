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
