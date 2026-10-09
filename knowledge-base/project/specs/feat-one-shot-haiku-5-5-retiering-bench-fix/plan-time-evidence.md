# Plan-time evidence (2026-10-09)

Measured while planning `feat-one-shot-haiku-5-5-retiering-bench-fix`. Aggregates only: no
transcript content, no credential, no issue or email text. The work phase re-measures every number
below on its own date (the commands are recorded), because the spend regime moved once already.

## 1. Bench self-test diagnosis (clean checkout)

| Revision | `bash scripts/learning-retrieval-bench.sh --self-test` | Notes |
|---|---|---|
| origin/main `8729cc0dfa` (this worktree, clean env) | `PASS=177 FAIL=0 TOTAL=177`, rc 0, 3.6 s warm (9.1 s measured by a reviewer on a cold host) | green |
| `git show d0707d3fa3^:scripts/learning-retrieval-bench.sh` (the revision before PR #9753), run as a copy | `PASS=51 FAIL=1 TOTAL=52`, `kb-search: WARN - paraphrase generation failed: all 3 variants returned (API_ERROR)` then `FAIL: ... Stage 2 union-of-paraphrases lost target (rank=null)` | reproduces the parent session's `51/1` exactly, including the totals line |
| origin/main with `NO_PARAPHRASE=1` exported | `PASS=173 FAIL=4 TOTAL=177` (Stage 2 row plus three api-key rows) | env leak |
| origin/main with `ANTHROPIC_API_KEY` exported and `CURL_BIN` a recording stub | killed at the 45 s timeout; the stub logged 9 calls before the kill (fixtures other than Stage 2 call `anthropic_paraphrase` through the real `CURL_BIN`) | env leak, live API egress |

Root cause of the reported `51/1`: #8394 (2026-09-20, `d0f39fed6f`) changed the reader to select the
first `"type":"text"` block (`jq 'first(.content[]? | select(.type == "text") | .text | strings)'`)
but the self-test's mock curl still printed `{"content":[{"text":"..."}]}` with no `type`. Every
paraphrase read as empty, `anthropic_paraphrase` returned `(API_ERROR)` three times, Stage 2 fell
back to the zero-overlap baseline and the assertion failed. #9753 (2026-10-08, `d0707d3fa3`)
rewrote the mock as `st_make_recording_curl` with `"type":"text"` and fixed it incidentally. The
parent session's worktree base predates #9753, so "51/1 on origin/main" was a stale base. The
script's `ST_MIN_ASSERTIONS=177` floor and TOTAL=52 prove which revision ran.

Why it stayed red for 18 days: nothing runs the self-test (`grep -rn "learning-retrieval-bench"`
over `.github`, `scripts/test-all.sh` and the suite registries finds only the lockstep test that
greps the file, and `scripts/lib/test-affected-paths.sh` edge lists).

## 2. Spend per candidate (SOLEUR_CLAUDE_COST markers, Better Stack, 2026-08-26 .. 2026-10-09)

Command (read-only, aggregate in `jq`; the raw file stays in the scratchpad):

```bash
doppler run -p soleur -c prd_terraform --silent -- \
  scripts/betterstack-query.sh --since 45d --grep SOLEUR_CLAUDE_COST --limit 4000 > cost.raw
jq -c '. as $o | (.raw|fromjson? // empty) | (.message // .) | select(type=="object")
  | select(.component=="claude-cost" and .SOLEUR_CLAUDE_COST==true)
  | {d:($o.dt[0:10]),src:.source,m:.model,c:.cost_usd,st:.capture_status,sub:.subtype,turns:.num_turns}' cost.raw
```

992 rows returned (under the 4000 limit, so the window is complete); 843 passed the structural
`component == "claude-cost"` filter. Projection = (sum of paid runs in the window / window days) x 30
for daily crons, mean paid run x runs per 30 days (21.4 weekday, 4.3 weekly) for weekday and weekly crons. Haiku saving factor
0.87 = 1 - (0.01 x 1.3 tokenizer inflation) / 0.10 on the cache-read line that dominates a spawn.

| Class | Cadence | Post-cutover S (2026-10-01..10-09, 9 d) | Saving at 0.65 / 0.87 | Pre-cutover 14 d S (2026-09-26..10-09, stale regime) |
|---|---|---:|---:|---:|
| `cron-community-monitor` | daily 08:00 | $9.08 (13 runs, 0 null/zero) | $5.90 / $7.90 | $17.45 (saving $11.34 / $15.18) |
| `cron-daily-triage` | daily 04:00 | $5.36 (9 runs) | $3.48 / $4.66 | $8.82 |
| `cron-follow-through-monitor` | Mon-Fri 09:00 | $3.10 (7 runs) | $2.01 / $2.69 | $5.73 |
| `cron-campaign-calendar` | Mon 16:00 | $1.56 (1 run; weak) | $1.01 / $1.35 | $3.29; all-regime 5-run mean gives $5.91 |

Per-run p50 / p90 after the cutover: community-monitor $0.14 / $0.34, daily-triage $0.19 / $0.34,
follow-through $0.14 / $0.18, campaign-calendar $0.36 (one run).

Regime change: per-run cost for all four fell about 4-5x between 2026-09-29 and 2026-10-01
(community-monitor $1.05-$1.47/run on 09-26..09-29, $0.11-$0.37 from 10-01; daily-triage $0.35-$1.06
then $0.08-$0.34), coincident with the Sonnet 5.5 migration (#9236, merged 2026-09-29). Causation is
not established; windows that straddle the change overstate the current regime and are not the
primary figure. Sums over all metered runs since 2026-09-09 (daily-triage and follow-through were only
metered from 2026-09-24, so those two sums cover about 16 and 12 runs, not 30 days): community-monitor
$42.39, daily-triage $5.45, follow-through $4.94, campaign-calendar $6.87.

Other execution-tier crons for scale (not candidates), sums over 2026-09-26..10-09: bug-fixer $5.93,
content-generator $1.80, roadmap-review $1.23, seo-aeo-audit $2.85; audit tier: growth-audit $14.72,
architecture-diagram-sync $4.85.

`claude-code-review.yml`: `gh api repos/jikig-ai/soleur/actions/workflows` reports
`state: disabled_manually`, `updated_at: 2026-02-12T11:09:49+01:00`, workflow id 229704973; `gh run
list --workflow=claude-code-review.yml --limit 100` returns 40 runs, the newest 2026-02-12. Measured
spend in the last 30 days: $0 (no runs). `knowledge-base/finance/api-spend-ledger.jsonl` is empty.

`'standard'` workflow pins: the seven pins live in opt-in `Workflow`-tool ports (the prose skill is the
default, `review/SKILL.md` "Dynamic-workflow alternative (opt-in)"). `find ~/.claude/projects -path
"*subagents/workflows/*" -name "agent-*.jsonl"` returns 0 files across every local project directory,
so there is no metered or even observed use on the one machine that develops this repo, and no other
metering exists (the agent-token tee does not see workflow spawns, ADR-053 finding 1).

## 3. Which model the claude-code CLI 2.1.293 reports (measured, `soleur-ci-eval` key)

Pinned CLI 2.1.293 (`claude --version` printed `2.1.293 (Claude Code)`), `--print --output-format
json --no-session-persistence --max-budget-usd 0.30`, key from `doppler run -p soleur -c ci` (env
only, never argv, never printed), config dir and cwd in the scratchpad, one synthesized prompt per cell.

| Cell | `--model` | Tools | `modelUsage` keys | `total_cost_usd` |
|---|---|---|---|---:|
| a | `claude-sonnet-5-5` | none | `claude-sonnet-5-5` | 0.0049 |
| b | `claude-sonnet-5-5` | Bash (one `echo`) | `claude-sonnet-5-5` | 0.0445 |
| c | `haiku` (alias) | none | `claude-haiku-5-5` | 0.0003 |
| d | `claude-sonnet-5-5` | WebFetch of a synthetic page | `claude-sonnet-5-5` and `claude-haiku-5-5` (255 in / 137 out, $0.000094) | 0.0076 |

Findings: (1) the `haiku` alias resolves to `claude-haiku-5-5` on 2.1.293, confirming the ADR-053
"Follows via alias" row; (2) the CLI's internal small/fast call (the WebFetch page summarizer) reports
`claude-haiku-5-5`, so on 2.1.293 the internal model is Haiku 5.5; (3) Bash-only runs emit no internal
call, and the cron prompts are Bash-only, so the cron cost shift cannot come from this; (4)
`_cron-claude-eval-substrate.ts` records `model` as `Object.keys(r.modelUsage ?? {})[0]`, the first key
only, and the marker's `cost_usd` is the all-model total, so a run that does trigger an internal call
is attributed to whichever key the CLI lists first. Total spend of this section: about $0.058.
