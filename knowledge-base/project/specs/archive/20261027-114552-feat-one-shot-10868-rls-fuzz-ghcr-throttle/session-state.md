# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10868-rls-fuzz-ghcr-throttle/knowledge-base/project/plans/2026-10-27-fix-rls-fuzz-ghcr-throttle-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=3 (during plan/deepen — recorded by planning subagent)

### Errors
- `bash: /scripts/collision-precheck.sh: No such file or directory` (exit 127) — plugin-root resolution issue; collision precheck completed via repo mechanisms instead.
- Nested `devin -p` syntax error (`--print [<PROMPT>]` vs `[PATH]`); corrected; subsequent spawns returned successfully.
- A research subagent's tool call was rejected under `auto` permissions; re-run with `smart` permission mode succeeded.
- Collision precheck found own draft PR #11295 naming #10868, and foreign `test-all.sh` processes (PIDs 2190650/2190651/2237246) in worktree `feat-one-shot-10972-route-orphan-sweeps-monitor` — reported, not actioned.

### Decisions
- Retry placement → dedicated CI helper `.github/scripts/ghcr-pull-with-retry.sh` (CTO ruling, fork A→a3).
- Retry signature → `toomanyrequests` only, tail-scoped, fresh per-attempt log, never on rc=2 (CTO ruling, fork B→b3); decoy tokens `Retrying after`/`failed to pull docker image`/`failed to display json stream` excluded (advisor + spec-flow).
- Parameters → 3 attempts, sleeps `20 45` env-overridable, tail ~200-line re-emission (CTO Item C).
- Supporting deltas applied: `2>&1` + `${PIPESTATUS[0]}` pinned and asserted; symmetric `::error::` on deterministic exit; annotation sanitization; `timeout-minutes` 25→30; `docker manifest inspect` positive control; `MIN_SUITES` 15→17 (review found main already lags at 16 suites vs floor 15 — pre-existing discrepancy noted); `RUNNER_TEMP` fallback; `logout:`-key absence + full-SHA pin assertions.
- User-Brand threshold `none`; all rulings persisted in `decision-challenges.md` (`| Item | Class | Ruling |`).

### Components Invoked
- Skills run to completion: `soleur:plan` (all phases incl. skeleton, research fan-out, scope check, user-brand, observability, guard contract, sharp-edges catalogue) and `soleur:deepen-plan` (halt gates 4.5–4.13; `lint-guard-contract.py` PASS — 1 guard entry; Scope Check exactly once; no blocked-verdict).
- Spawns: `soleur:product:spec-flow-analyzer` (4 P1 + 6 P2, all applied), solo advisor consult (2 design changes applied), `soleur:engineering:cto` (3 binding rulings persisted), combined plan-review panel (4 findings, all applied).

## Review dedup ledger (panel @ PANEL_SHA 3c2928ad2b, class=code, tier=none)

| raw finding | canonical defect | seats | fix |
|---|---|---|---|
| MIN_ASSERTIONS 49 < 52 actual | under-floored anti-vacuity bound | git-history, code-quality, pattern, architecture, test-design | recount each change; now 78 |
| pull_request.paths omits helper+suite | helper-only edits never exercise live wiring | pattern, architecture, enum | paths += helper, suite, config.toml |
| warn/error-line substring-match | annotation content unasserted (stub stderr satisfies) | test-design, code-quality | ^::warning::/^::error:: anchored regex rows |
| tail-40 window unexercised | whole-log grep regression greens | test-design, code-quality, enum | fake-sig-above-tail stub |
| exhaustion re-emit unpinned | `tail -n $REEMIT_LINES` deletable | test-design, enum | b:exhaust-reemit non-annotation count=4 |
| fork PR token in docker config | GITHUB_TOKEN reachable by fork code | security | same-repo if: gate on login+probe |
| SLEEPS glob-expands / short array 0s | backoff silently erased | security, code-quality, architecture | read -ra + last-element fallback |
| "$*" unsanitized in ::error:: | annotation injection (latent) | security, code-quality | sanitize "$*" |
| log_dir shared RUNNER_TEMP / leak | collision + /tmp residue | architecture, code-quality, test-design | mktemp -d per invocation + RUNNER_TEMP fixture |
| LN_* head-1 unanchored greps | comment/duplicate forgery of ordering | enum, code-quality | anchored uses:/run: key-shape greps |
| login inputs unasserted | registry/token retarget silent | enum | registry+password rows in step slice |
| lacks-list gaps | docker run/create/compose/logout, DOCKER_CONFIG, pull_request_target, continue-on-error, sleeps-override | enum | extended lacks rows |
| probe `|| true` / reachability-only | silenced control + wrong comment | enum | run-line ends at >/dev/null$; comment corrected |
| SLEEPS default 20 45 unasserted | silent de-backoff | enum | helper-sleeps-default row |
| "$@" 2-arg unexercised | argv mangle invisible | enum | fake-two-arg stub |
| supabase-local.sh unread | rc remap / cred strip invisible | enum | supa-rc-propagated + supa-no-cred-strip rows |
| logout 9-line window | padding escapes sweep | enum, code-quality | step-boundary slice |
| job-block top-level close missing | later section satisfies perms | code-quality | 0-indent close added |
| -i case-insensitivity unasserted | dropping -i greens | test-design | mixed-case token in fake-stale-sig |
| assert_* not driven in self-test | neutered helper greens | test-design, enum | designed-fail drives + counter check |
| instrument reset shape | — | (lead) | selftest drives silenced via { } >/dev/null |
| probe tag vs CLI pin coupling | orphaned tag risk | architecture | lockstep comment |

Scope-outs (recorded, not fixed — the guard is a tripwire, not channel-exclusivity proof): second `rls-fuzz:`/extra job under `jobs:`, `services:`/`container:` keys, self-hosted runner env, PQG run-line repoint (required-context enforcement lives in repo settings), MIN_SUITES cross-suite second pin, duplicate YAML key union-slice. Assembly: guard proves the mechanism is wired + correct over stubbed classes; it does not prove exclusivity of every pull channel.
