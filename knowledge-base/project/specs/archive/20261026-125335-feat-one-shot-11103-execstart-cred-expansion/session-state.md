# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-26-fix-inngest-execstart-inner-bash-credential-expansion-plan.md
- Status: complete

### Errors
- Plan/deepen ran in a Devin CLI subagent with no nested-agent tool: all fan-outs executed inline; `git commit` was false-denied (`.cwd` envelope omission) so the parent committed the planning artifacts.
- Technical rulings were written `pending - assumed` during planning, then resolved by ONE batched `soleur:engineering:cto` spawn (cto_spawns=1) — all 9 rows ruled, gate PASS.

### Decisions
- Site 1 (`inngest-redis.service`): aclfile delivery — bound `--only-secrets INNGEST_REDIS_PASSWORD` ExecStartPre runs a refusal-first acl writer (0600 on /mnt/data/redis); ExecStart drops doppler run + bash -c entirely.
- Site 2 (rendered `inngest-server.service`): resolve-after-refusal via rendered `inngest-server-launch.sh`; `@@BACKEND_FLAGS@@` stays on unit argv (durable sentinel for 4 consumers); `@@BACKEND_ENV@@` moves inside the script.
- Corpus stage in `doppler-injection-bound.test.sh`: flags plain `$VAR`/`${VAR}`/`$${VAR}` inside `bash -c` bodies, resolves `@@SENTINEL@@` fragments, excludes `${!...}`.
- Discovered: second expansion site at inngest-bootstrap.sh:1747 (INNGEST_REDIS_URI) now in scope; vinngest pin is v1.1.61 not v1.1.59.

### Components Invoked
- soleur:plan, soleur:deepen-plan (inline in subagent)
- soleur:engineering:cto (binding ruling, one batched spawn)
- technical-ruling-gate.sh --branch: PASS (9 rows)

### Agent ledger
- cto_spawns=1

## Work Phase

Status: COMPLETE — all four phases landed, both commits pushed to branch (not pushed upstream).

- Phase 1 RED: doppler-injection-bound.test.sh inner-c stage flagged both live sites — inngest-redis.service ($INNGEST_REDIS_PASSWORD) + rendered inngest-server.service ($INNGEST_REDIS_PASSWORD,$INNGEST_SIGNING_KEY via @@BACKEND_ENV@@ fragment resolution).
- Phase 2: inngest-redis.service ExecStartPre aclfile writer after mount-guard; conf declares aclfile; ExecStart plain redis-server. inngest-redis-bootstrap.sh step 3.6 installs inngest-redis-acl.sh (refusal-first, charset validation, atomic 0600 tmp+mv).
- Phase 3: /usr/local/bin/inngest-server-launch.sh rendered reconcile-always (case $- refusal -> set -u -> signing-key strip single-$ -> @@BACKEND_ENV@@ -> exec ... "$@"); unit ExecStart = doppler run -- /usr/local/bin/inngest-server-launch.sh @@BACKEND_FLAGS@@ --poll-interval 60 --sdk-url @@SDK_URL@@; @@BACKEND_ENV@@ substitution retargeted to launch_content + chmod 0755.
- Phase 4: comments corrected (cat-deploy-state.sh:746, inngest.tf:166, bootstrap secrets-delivery prose, unit/conf headers).

Suite results: doppler-injection-bound 71/71 (MIN_ASSERTIONS 59->71); inngest.test.sh 585/585 (floor 549->585); journald-config 113/113; vector-admission 58/58; cloud-init-inngest-provision-unit 88 rows PASS; cat-deploy-state 167/167; inngest-cutover-flip 194/194. cloud-init-inngest-bootstrap rc=1 — GuardA DESIGNED-advisory red only (drifted: the 4 edited carrier files vs vinngest-v1.1.61; ADR-232, propagates at next tag bump — expected, non-required).

AC9 verified: grep -c 'bash -c' inngest-redis.service = 0; rendered server unit ExecStart carries no $/bash -c.

Notable: #7286 lockstep selector widened ExecStart->Exec(Start|StartPre|StartPost) (doppler call moved to ExecStartPre — same hazard class). Scanner's @@-fragment resolution is quote-aware (single-quoted full scan; double-quoted only backslash-literal \$) — avoids the SDK_URL="${SDK_URL:-...}" render-time-default false positive. INNGEST_REDIS_ACL_FILE is a test-only override seam (--only-secrets injects only the password; nothing writes it to the env file, and a stray ambient value is confined by ReadWritePaths=/mnt/data/redis).

Commits: 9cfa25769b (tests), d211a1488b (source), b9e8a10aa7 (docs). Pushed to the PR head (b9e8a10aa7).

## Review Phase

Status: COMPLETE — soleur:review, sequential-fallback (no nested-agent tool in this harness; 12 seat-passes run inline by the lead).

- Class: code | Tier: aggregate pattern (plan frontmatter) | Design-risk: yes (design pass: code-simplicity + architecture-strategist ran first, deduped from panel)
- Seats (12/12, sequential inline): code-simplicity, architecture-strategist, git-history, pattern-recognition, security-sentinel, performance-oracle, data-integrity, agent-native, code-quality, user-impact, structural-enumeration, test-design; deterministic: shellcheck rc=0
- Findings: 4 (0 P1 / 3 P2 / 1 P3), all pr-introduced. Fixed inline: aclfile `>`→`#<sha256>` spelling (c93e281846, P2 — cleartext no longer at rest); KB doc nits (7c81057b20, P3). Filed meta/machinery: #11171 (inner-c stage grammar window), #11172 (acl default-path unpinned wire).
- Suites re-verified post-fix: inngest 585/585, doppler-injection-bound 71/71, ci-deploy 735/735, carrier-vocab 52/52, workflow-guard 13/13, config-refresh 163/163; loopback LUKS suite environmentally unavailable (needs root+losetup).
- Trailer: f0b013fc9d (`Reviewed-Coverage: sequential-fallback 12/12`); Review-Evidence comment posted on PR #11159. Branch NOT pushed per parent constraint — push + ship remain for the orchestrator.

Remaining: push branch, then soleur:compound -> soleur:ship.

## QA Phase

Status: COMPLETE — PASS (sequential-fallback; no browser surface — infra-only diff, plan Test Scenarios are unit/integration prose, verified via the named suites + AC checks per the pipeline brief).

- Step 2.6 nav-states gate: skipped silently (diff touches no `app/(dashboard)/**`, `components/dashboard/**`, or `layout.tsx`).
- Suite greens: doppler-injection-bound 71/71; inngest 586/586; cloud-init-inngest-provision-unit 88 rows; cat-deploy-state 167/167; inngest-cutover-flip 194/194; journald-config 113/113; vector-admission (`apps/web-platform/test/infra/`) 58/58.
- cloud-init-inngest-bootstrap: 268/269 — the one red is the designed-advisory GuardA (vinngest pin propagation, ADR-232, non-required).
- QA FINDING FIXED: GuardD census floor `GD_ALL == 10` was stale — the diff added the quoted `SERVERLAUNCHEOF` heredoc to inngest-bootstrap.sh (11 heredocs). Bumped to 11 in be11fc8a1e (pushed); convention precedent: 235693e411 added GuardD + a heredoc together.
- AC ledger: AC1 ExecStart plain redis-server + acl-writer ExecStartPre after mount-guard ✓; AC2 aclfile directive, refusal-first writer, atomic 0600 (#<sha256> form per review P2) ✓; AC3 rendered ExecStart sentinel-shaped, zero expansions ✓; AC4 launch script ordering + chmod 0755 reconcile-always ✓; AC5/AC6 via suite greens ✓; AC7 journald + vector-admission green, no vector.toml diff ✓; AC8 named suites pass (GuardA excluded by design) ✓; AC9 `grep -c 'bash -c' inngest-redis.service` = 0 ✓.

## Compound Phase

Status: COMPLETE.

- Learning: `knowledge-base/project/learnings/test-failures/2026-10-26-the-advisory-red-i-attributed-was-two-reds-a-census-floor-the-diff-moved.md` (Session Errors: 4 items, each with **Prevention:**).
- Deviation Analyst: no hard-rule deviations this phase; `.rule-incidents.jsonl` absent (no incidents). Rule budget: linter `[WARN] B_ALWAYS=44390 >= 44000` (approaching 46000 ratchet — no new rule added; insight routed to the owning skill instead); registry 44463 bytes / 99 rules (longest 597); constitution.md 320/300 advisory; 79 rules unused>8w (informational only).
- Route-to-definition: one bounded bullet appended to `plugins/soleur/skills/qa/SKILL.md` Notes (designed-advisory red = set-membership claim; bump census floors with the diff). Constitution promotion: skipped — covered by the routed bullet + existing qa notes.
- Archival: DEFERRED to ship Phase 6.45 (archive-kb.sh) per pipeline brief — spec dir still in flight, ship Phase 6 reads decision-challenges.md from it.
- Phase 1.6 token-efficiency: skipped by script (small uncommitted diff).

## Ship Phase

Status: IN PROGRESS — gates green, arming next.

- Phase 0-4: trailer gate PASS; review evidence `Reviewed-By-Soleur: soleur:review` + `Reviewed-Coverage: sequential-fallback` (newest trailer, `aggregate pattern` threshold — non-blocking, disclosed); learning present (`compound:` commit); README counts in sync; affected battery launched detached (contended siblings — capacity-gated wait then affected-tests.sh).
- Phase 5.4/5.5: probe-residue clean; preflight degraded-inline (sensitive-path match → Check 6 PASS via plan `aggregate pattern`, Check 10 PASS probe-verb allowlisted + AC9 probe expected=actual=0; path-gated checks SKIP); Review-Findings Exit COUNT=0; net-issue-flow NET=+1 OVERRIDDEN via PR-body marker (Filed: #11171 #11172, Closes #11103); CMO/COO/vendor gates not triggered; deploy-pipeline drift gate FIRED (cat-deploy-state.sh + inngest-redis-bootstrap.sh) → tracking comment posted; Incident-PIR gate FIRED on the plan-in-corpus scan → PIR authored + committed (30f6821bcf), action-items gate PASS (#10382 #10390 #11171); undeferred-opstep + soak scans clean; technical-ruling --branch PASS + --pr-body PASS; merge-base lints OK (skill-body-budget caught + reverted a qa SKILL.md route bullet — file was at 36989/37000 B on main); hold-gate 0 standing; overlap preflight clean.
- Phase 6: PR #11159 retitled `fix(infra): remove inner-bash credential expansion…` + body rewritten (Closes #11103, Filed, Model Dissents, Merge Danger, Tally, Changelog, Test plan); labels semver:patch + type/security + app:web-platform; auto-close scan clean (intentional Closes only).
- Phase 6.45: archive-kb.sh archived plan + spec dir (this file now lives under specs/archive/).
- Holds: none recorded. Errors this phase: GuardD stale census floor found+fixed (be11fc8a1e); skill-body-budget FAIL on route bullet → reverted (insight kept in learning).
