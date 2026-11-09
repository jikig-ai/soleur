# /tmp producer census — #11764 work-phase evidence

Measured 2026-11-09 on the operator host (the alarm's host), in the
`feat-one-shot-11764-12484-12501-12507-12508-queue-resid` worktree. Committed
as PR evidence per the plan's AC14 (census → PR body; this file is the
canonical record).

## 1. Live `/tmp` top-level histogram

`ls -U /tmp` → 23,387 top-level entries (the #11764 alarm measured ~6.3k on
2026-11-01 and the plan cites 23,358 for 2026-11-09 — this run is the same
regime). Leading-token histogram (`sed 's/^([a-zA-Z][a-zA-Z_]*).*/\1/'`):

| class | count | disposition |
|---|---|---|
| `tmp.*` (mktemp default template; includes `tmp.*` DIRS) | 21,966 | repo-fixed (test-helpers TMPDIR lever) + agent-routed (`.cs`) |
| `soleur-run.<pid>.*` session roots | 36 | already-owned (`.soleur-owned`; Reaper 3 dead-owner) |
| `soleur-inc-*` incident sandboxes | ~5 | already-owned (marker + composed trap; now also TMPDIR root) |
| `soleur-watch.*`, `watch-*`, `poll-*`, `review-*`, `pr-*`, `oracle-*`, `replay-*`, `ratchet-*`, long tail (<100 each) | ~1.4k | external/harness-side — agent-routed to `.cs`, `.cs` age-reaped |
| `srt-*`, `skill-*`, `pencil-*`, `claude-http-*`, `rung2-*` | ~0 residual this run (srt 7; skill/pencil/rung2/claude-http 0) | producer classes from the issue; `.cs` routing + reaper arm |
| `/tmp/.cs` | 1 tenant subdir | the new routing target |

The pile is overwhelmingly `tmp.*` — mktemp's DEFAULT template — i.e.
descendants of processes whose TMPDIR was `/tmp`, not any one named producer.
That is why the fix routes TMPDIR rather than chasing per-site traps.

## 2. `git grep -n mktemp` census (excludes `knowledge-base/`)

Call sites / files per tree:

| tree | mktemp lines | files |
|---|---|---|
| `.claude/hooks/` | 530 | 62 (51 are `*.test.sh`) |
| `plugins/soleur/` | 933 | 324 (mostly docs/fixtures/`.test.sh`) |
| `scripts/` | 887 | 403 |
| `tests/` | 206 | 91 |
| `apps/` | 1404 | 309 |

File-level classification (heuristic: owns a `trap … EXIT|RETURN` /
`lint-trap-ownership: ok` annotation / `rm -f` only / none):

| class | files | meaning |
|---|---|---|
| trapped | ~1070 | owns a cleanup trap — covered |
| annotated-bounded | ~18 | explicit `lint-trap-ownership: ok` — covered |
| rm-only | ~63 | adjacent `rm -f`; covered except signal/errexit window |
| none | ~38 | docs, fixtures, `.service`, prose hits — no live allocation |

The `none`/`rm-only` buckets are dominated by `.md`, `.fixture`, `.service`,
`.tsv` files where `mktemp` is prose or a template line, not an allocation.

## 3. Per-file verdicts on the plan's named producers

| file | verdict |
|---|---|
| `plugins/soleur/test/test-helpers.sh` | **repo-fixed** — no-outer-root arm now exports `TMPDIR` at the `.soleur-owned` sandbox (the single lever: every descendant mktemp of a directly-invoked suite lands inside the dir the composed trap reaps; runner-led suites were already covered by `soleur_scratch_session_begin` in test-all.sh) |
| `plugins/soleur/skills/skill-security-scan/scripts/lib.sh` | already-owned — `stdin_to_tempfile` is caller-cleanup by contract; all 5 `check-*.sh` callers verified trapping (`trap 'rm -f "$tmp"…' EXIT`) |
| `…/skill-security-scan/scripts/run-scan.sh` | already-owned — `INPUT`+`results_dir` EXIT-trapped; `.scan-meta.json` deliberately persisted (GDPR Art. 32 evidence) with its own 7d age-reap plus the `skill-scan-*`/`skill-security-scan-*`/`sss-write.*.err` scratch sweep |
| `…/skill-security-scan/scripts/run-self-test.sh`, `parse-override.sh` | already-owned / no allocation |
| `plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` | already-owned — `work` dir + `trap cleanup EXIT` (the measured `pencil-*`/`pen-*` residue is the Node adapter's `mkdtempSync` with a `process.on("exit")` reaper — SIGKILL residue only; agent-routed to `.cs` by the agent-env TMPDIR injection) |
| `scripts/followthroughs/git-data-rung2-evidence-capture.sh` | **repo-fixed** — `_sentry_consult` `rung2-sentry.*.err` / `rung2-live.*.err` gains a self-disarming RETURN trap (shape-pinned `rm -f`), closing the signal/errexit window the adjacent `rm -f` could not cover |
| `tests/scripts/lib/git-data-birth-readiness-gate.sh` | already-owned — `rung2-fetch.*` documented bounded (every return path `rm -f`s; sourced lib may not trap EXIT — ADR-129 (c)); `rung2-archive.*` under a self-disarming RETURN trap |
| `tests/scripts/test-git-data-birth-readiness-gate.sh` | already-owned — `TMP` + `trap 'rm -rf "$TMP"' EXIT`; `_r2res_base` allocated inside `$TMP` |
| `apps/web-platform/server/agent-env.ts` | **repo-fixed** — `env.TMPDIR = opts.claudeTmpDir` beside `CLAUDE_CODE_TMPDIR`; `TMPDIR` was already in `AGENT_ENV_ALLOWLIST` and the sandbox binds `/tmp/.cs` writable |
| `.claude/hooks/git-commit-secret-scan.sh` | already-owned — `cleanup()` reaps `report_file`, `nodiff_report`, `nodiff_dir`, `sim_dir` via `trap hook_exit EXIT`; `sim_sweep` additionally reaps marker dirs >60m |
| `.claude/hooks/lib/{commit-index-sim,hook-input,test-incident-sandbox}.sh` | already-owned — lib files allocate nothing or compose cleanup by contract |
| `.claude/hooks/pencil-collapse-guard.sh` | already-owned — `trap 'rm -f "$tmp_restore"' EXIT INT TERM` |
| `.claude/hooks/pre-merge-auto-close-scan.sh` | already-owned — `trap 'rm -f "$SCAN_FILE" "${GH_ERR:-}"' EXIT INT TERM` |
| `.claude/hooks/ship-kb-archive-gate.sh` | already-owned — `trap 'rm -f "$_census_f"' EXIT` |
| `.claude/hooks/ship-operator-step-gate.sh` | already-owned — `trap 'rm -f "$PR_BODY_FILE"' EXIT INT TERM` |
| `.claude/hooks/memory-backstop-mutation-battery.sh` | **repo-fixed** — `HOPFX` synthetic /proc fixture added to the `cleanup` EXIT trap (shape-pinned `/*/hopfx.*`); previously only two explicit exit paths removed it |
| `.claude/hooks/ship-soak-followthrough-gate.sh` | **repo-fixed** — `_plan_stripped` added to BOTH `rm -f` trap registrations (allocated between them; the signal window between allocation and re-registration was the strand) |
| `.claude/hooks/skill-security-scan-write.sh` | already-owned — `sss-write.$$.err` `rm -f`'d on both branches; SIGKILL residue covered by run-scan.sh's family sweep |

Net `.claude/hooks/` finding: the plan's "~9 files / ~27 call sites lacking
cleanup" estimate was high — every non-test hook producer was already
trap-owned; exactly TWO files had allocations outside their trap bodies.

## 4. Dispositions summary

- **repo-fixed (this PR):** test-helpers.sh (TMPDIR lever), agent-env.ts
  (TMPDIR injection), rung2-evidence-capture.sh, memory-backstop battery,
  ship-soak-followthrough-gate.
- **agent-routed (`.cs` via TMPDIR injection):** every spawned-agent
  descendant — hooks, skill scripts, `srt-*`, `pencil-*`/`pen-adapter-*`
  mkdtemp, `claude-http-*`, subagent scratch, `rung2-*-job`.
- **external-documented:** `srt` sandbox runtime, `claude-http-*` and
  `postmerge-poll*` harness-side artifacts — not repo-trappable; reached only
  by the `.cs` route + `reap_owned_cs_base` 48h age arm.
- **already-owned:** everything else in §3.
