# Evidence — #7432 soak-strike disposition (2026-10-20)

## Probe run (local, authoritative flags)

```
SOLEUR_FT_EARLIEST=2026-10-19T18:00:00Z GH_TOKEN=*** bash scripts/followthroughs/jobs1-stopgap-7432.sh
→ ACTION REQUIRED: 2 REDs outside the allowlist: 39378082716(git-data-wipe-assert.test.sh) 39446197504(git-data-wipe-assert.test.sh). If both reproduce (same suite RED at the same sha in infra-validation, or at -P 1) add the run ids to JUDGED_REPRODUCING_RUNS by PR; otherwise the revert trigger fires.
PROBE_EXIT=5
```

## The two strikes

| Run | SHA | Created | RED line | Tally |
|---|---|---|---|---|
| 39378082716 | 1cb50078e01c | 2026-10-20T06:02Z | `RED  apps/web-platform/infra/git-data-wipe-assert.test.sh` — `SOLEUR| --- RED ... (rc=124 elapsed=363s start_offset=+628s)` | 180 passed, 1 failed, 0 unaccounted (of 181) |
| 39446197504 | 8eed32dfb9e1 | 2026-10-20T15:11Z | same suite, `(rc=124 elapsed=363s start_offset=+625s)` | 182 passed, 1 failed, 0 unaccounted (of 183) |

## Reproduction evidence (probe's two literal tests)

- **Same-sha infra-validation:** run 39370876316 at 1cb50078e0 (same sha as strike 1) — suite ran in shard 3/4 (65 suites, `-P 4`), PASSED. No infra-validation run exists at 8eed32df.
- **`-P 1` rerun:** serial measurement on dev host `time bash apps/web-platform/infra/git-data-wipe-assert.test.sh` → `real 2m57.783s` (178 s; subagent measured 2m41.8s / 162 s — same suite on the same host, both < 360 s), RC=0, loopback tier skipped (needs root). Est. ~240 s on the 4-core CI runner — still under 360 s.
- **Attribution:** `run-registered-suites.sh` ATTRIBUTION block — `rc=124 → H4` "CONFIRMED class, owned by _SUITE_BOUNDS; tune per-suite at ≥1.5x worst observed". Deterministic capacity defect, not the -P 4 flake signature.

## Soak window state

`gh run list --workflow main-health-monitor.yml --branch main --created ">=2026-10-19T18:00:00Z"`: 4 completed non-cancelled counted runs (39298929992, 39345015242 clean; 39378082716, 39446197504 struck) + 39470997821 in_progress. N=12 needed; ~4 runs/day → ~2 days remain.

## grep -q linter re-evaluation (issue #7432 item 2)

- Census ~1267 `| grep -q` sites in `*.sh`; zero stream a >64 KiB file into the pipe. `ci-deploy.sh` (212 KB), `workspaces-cutover.sh` (176 KB), `server.tf` (114 KB) appear only as `grep -q P FILE` operands (no pipe) or in comments documenting the deliberate avoidance.
- One latent-capable site: `plugins/soleur/skills/ship/SKILL.md:161` `git show "HEAD:$f" | grep -q "code-review"` over `todos/` files (all ~1 KB today).
- No captured `PIPESTATUS[0]==141` failure in the soak-window CI history; the two REDs are rc=124.
- **Verdict: mechanism still unreachable — no linter; the #7432 comment carries this measurement.**

## Context facts verified

- `.github/workflows/main-health-monitor.yml:365` — `JOBS: 1` remains ONLY on the tests step (by design; nested runner when a branch diff touches `apps/web-platform/infra/`). Never touched by this work.
- `_SUITE_BOUNDS` in `run-registered-suites.sh` (~L630-691) has no `git-data-wipe-assert` entry → 360 s default applies.
- `jobs1-stopgap-7432.test.sh` `mutate()` rows R4b3 (~L261), R4q (~L290), K12 (~L423), K22 (~L445) pin the literal `JUDGED_REPRODUCING_RUNS=""` — must be re-anchored in the same commit.
- Overlap preflight: `SOLEUR_OVERLAP exit=0 prs=none`. Sibling worktree `feat-wipe-assert-hooks-fields-10476` touched only the suite file (PR #10567, CLOSED) — no collision with the runner file.
