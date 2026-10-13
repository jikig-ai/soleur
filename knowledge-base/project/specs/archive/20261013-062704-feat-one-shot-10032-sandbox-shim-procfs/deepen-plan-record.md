# Deepen-Plan Record — 2026-10-11

Plan: `knowledge-base/project/plans/2026-10-11-fix-sandbox-shim-procfs-under-masked-proc-plan.md`
Harness note: no Task/subagent tool available — the prescribed parallel
skill/learning/research/review fan-out (Phases 2-5) ran as inline passes
by the planning agent. `Reviewed-Coverage: inline-single-agent`.

## Gate verdicts

| Gate | Result |
|---|---|
| 4.4 precedent-diff | Patterns (argv scan/splice arms, `setup_marks` merged-stream semantics, fail-closed refuse) reuse the shim's own established forms — precedent is the same file; no novel pattern |
| 4.45 verify-the-negative | 6 load-bearing negative claims probed: `--bind-fd` absent on 0.8.0 (confirmed — upstream 0.10.0, backported 0.9.0); `denyRead /proc` → `--tmpfs` (confirmed, config L57-62); tail `--bind /proc /proc` in fixture (confirmed, last 3 argv entries); DIAG arms only on `sandbox_broken` (confirmed, ci-deploy.sh L1633); `add_cmd_fd_refs` substring scan (confirmed, L231 `=~` on `$joined`); `BWRAP_FD_VALUED_OPTS` already carries `--bind-data`/`--bind-fd` (confirmed, L261-278) |
| 4.5 network-outage | SKIP — no trigger patterns in Overview/Problem |
| 4.55 downtime/cutover | FIRED (single-container restart surface) → `## Downtime & Cutover` added; zero-downtime evaluated, standing deploy mechanism, no new offline op |
| 4.6 user-brand | PASS — section present, threshold `single-user incident`, concrete |
| 4.7 observability | PASS — 5 fields non-placeholder; `printf 'ok'` verb-allowlisted, no SSH, literal expected_output, non-placeholder credentials_required (SKIP-DECLARED) |
| 4.8 PAT | PASS — zero regex hits |
| 4.9 UI-wireframe | SKIP — no UI-surface files |
| 4.10 encryption | SKIP — no new store/connection (existing log routing referenced, not introduced) |
| 4.11 guard contract | PASS — `scripts/lint-guard-contract.py` clean (2 guard entries); assemblies name chokepoints (merged-stream rewrite path; replay path), not member lists |
| 4.12 scope check | PASS — 1 unfenced `## Scope Check`, all subsections, no unmapped/unjustified rows, `Recommendation:` present |

## Verify-the-negative + citation checks (Quality Checks §)

- `git grep -nE 'security-opt[= ]+systempaths' apps/web-platform/` → rc=1 (zero hits), literal AC6 command executed.
- Line citations re-verified: `docker run -d` at ci-deploy.sh L4250 (canary) and L4595 (prod); config #9723 block L498-501; `enableWeakerNestedSandbox` comment L571-575; `classifyProcMaskProbe` L389 / probe argv L437-441; `classifyShared` L87; `runHardeningProbes` L465; `SOLEUR_BWRAP_REAL` shim L74; `setup_marks` L166.
- Issue/PR states verified live 2026-10-11: #10032 OPEN, #9860 OPEN, #9723 CLOSED, #9773/#9842/#10045 OPEN; PR #9768/#9803/#9938 MERGED.
- Rule-ID citations: only `cq-write-failing-tests-before` — verified active in AGENTS.md.
- No SHAs cited; no Terraform variables; no labels prescribed in ACs (#10045 labels verified at create-time).
- markdownlint: 0 issues over plan + specs artifacts.

## Corrections applied in this pass

1. Fallback enumeration corrected to BOTH moby path lists (masked +
   readonly) — `/proc/sys` writable named the sharper widening edge.
2. `--bind-fd` availability corrected (0.10.0 upstream / 0.9.0 backport;
   still absent from 0.8.0).
3. Phase 0.1 pinned to existing `add_cmd_fd_refs` substring semantics.
4. `## Downtime & Cutover` + `## Enhancement Summary` + References
   citations added.

## Deferred

- `AskUserQuestion` post-enhancement options — headless pipeline; the
  run is operator-scoped to stop after deepen-plan.
- Independent multi-agent review — deferred to `soleur:review` +
  issue-mandated CTO+CLO seats (no Task tool here).
