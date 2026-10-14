# Decision Challenges — feat-one-shot-6288-zot-restart-loop-oom-telemetry

Recorded during plan + plan-review (headless). Surfaced by /ship into the PR body + an
`action-required` issue for operator visibility.

## 1. Cut the operator-requested `mem_used_mb` / `mem_total_mb` telemetry fields

- **Class:** user-challenge → resolved to KEEP (operator's stated direction is the default).
- **Source:** fable scoped advisor consult (Change 1) + DHH plan-review (Finding 1) + code-simplicity plan-review (cut #1) — three independent reviewers converged.
- **Issue #6288 said (operator direction):** "Extend the reporter to emit `mem_used_mb` / `mem_total_mb` and zot's last exit / OOM-kill reason."
- **Reviewers found:** host `mem_used_mb` is **page-cache-confounded** — a ~35 GB store scan pins page cache, so host "used" fills to near-total regardless of whether zot's *anonymous* memory ever starved; using it to confirm OOM auto-confirms unconditionally (a rubber stamp). `mem_total_mb` is a per-host near-constant re-emitted every 5 min. The decode table references neither. Recommendation: drop both (9 fields → 7).
- **Plan resolution (KEEP, do not silently override the operator):**
  - The confounding was fixed *additively*, not by removal: `zot_anon_mb` (container cgroup `memory.stat` anon, excludes page cache) is now the confirmation signal, so the operator-requested fields are no longer misused.
  - `mem_total_mb` was found to carry an independent, non-confounded job the reviewers overlooked: on a **no-SSH host it self-verifies the cx32 bump landed** (reads ~8000 vs ~4000 post-redeploy).
  - `mem_used_mb` stays as host-pressure context that corroborates the host-OOM decode row (`exit_code=137` + `oom_killed=false`).
  - Both fields ARE emitted exactly as the operator asked → no divergence from stated direction; the reviewers' "cut them" is a taste refinement, surfaced here for the operator to decide in a follow-up rather than applied silently.
- **Operator decision requested:** keep both fields as-is (current), OR drop `mem_used_mb` (keep `mem_total_mb` for bump-verification), OR drop both and rely solely on `zot_anon_mb` + `oom_kills_5m` + `exit_code`. No code change is blocked on this — the plan ships with both retained.
