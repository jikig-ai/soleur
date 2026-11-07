# Learning: an ECR-dead latch made the cold cache run converge instead of timing out empty

## Problem

`rls-authz-fuzz` (issue #11386) could not populate its own image cache during a sustained ECR-saturation window. `supabase-pre-pull-images.sh` probed ECR first for every one of the ~14 Supabase images; each probe paid ~65 s of throttled retry before the ghcr fallback, so a cold-cache pull+save could not fit inside `timeout-minutes: 30`. Two consecutive `workflow_dispatch` runs (40653699076, 40657761446) were cancelled at the deadline — and because `actions/cache` skips its post-job save on cancel, each dead run left **zero** banked progress, so the next cold run restarted from nothing. The same code fit ~20 min in a calmer window (control run 40661730763), which is what made "the job is too slow" read wrong: the budget was being consumed by a *per-image dead tax* on a registry that was not going to answer, plus ~10 min of default-level `gzip` on the save.

## Solution

Three coordinated changes (PR #11396):

1. **ECR-dead latch** — after `SUPABASE_ECR_DEAD_AFTER` (default 2) *consecutive* ECR throttle exhaustions, one `::warning::` fires on the transition and remaining images skip ECR entirely, converting N×65 s of dead tax into one-time cost. Classification reads the helper's own terminal verdict — the LAST `::error::` line of its tee'd output carries `toomanyrequests` iff the final attempt died on the signature. Grepping the whole aggregate log would misclassify a throttle-then-deterministic sequence (an earlier attempt's quoted signature survives in it). Any non-throttle outcome — success OR a deterministic answer — resets the counter, because a deterministic reply is evidence the registry *responds*, i.e. against saturation. The env is digit-validated before arithmetic: `08` is octal-shaped and makes `(( x >= 08 ))` never true (inert latch, no fatal), and a non-numeric value dies as `unbound variable` under `set -u`. Latch state is in-memory only — a false trip forfeits ECR upside for the rest of ONE run.
2. **Best-effort pulls + present-subset save** — a failed ghcr pull is recorded in `failed[]` and the loop walks on; at the end the tar is built from `docker image inspect`-verified *present* refs (never the intended `refs[]` list — one absent ref makes `docker save` die and forfeits the whole partial). The step still exits 1 naming the unfetched set, and a FAILED step's post-job cache save still uploads the partial tar (it is skipped only on timeout-cancel), so progress banks monotonically across runs — a residual overrun converges instead of restarting from zero.
3. **`.tmp`+`mv` fast save + 45-min budget** — `pigz -1` (fall back to `gzip -1`; default level cost ~10 min on this set, run 40657761446) writes to `$CACHE_TAR.tmp` and `mv`s on success, so a mid-save failure cannot clobber the tar the cache action restored. `timeout-minutes: 45` covers the measured post-latch worst case (~20-30 min pulls + ~4 min write + ~10 min suite) with headroom; 60 only extends a genuinely-hung job's blast radius.

The resilience suite pins the contract with exact counts (`ecr pulls == 6/7/12`, `pulls == 42` on total exhaustion — the latch truncates probing at img-b), once-only-warning assertions, and digit-shape gating; 175 assertions, `MIN_ASSERTIONS` raised in the same diff (ADR-193).

## Key Insight

A job that can never complete inside its deadline has two failure surfaces, not one: the timeout itself, and the *zero banked progress* that `actions/cache`'s skip-on-cancel semantics guarantee. Fixing only the budget (raise the timeout) leaves the second surface live for the next saturation window. The durable fix is per-run convergence — a latch that stops paying a measured dead tax, and a save that persists the inspect-verified subset through a `.tmp`+`mv` so partial progress survives a failed step. Also: when a retry helper's terminal verdict is machine-readable (`::error::` tail), classify on the LAST line, not the aggregate log — intermediate attempts' signatures survive in the aggregate and invert the classification.

## Session Errors

1. **(forwarded, plan phase) Plan skill agent fan-outs executed inline — Devin subagent cannot spawn Task agents** — Recovery: gates and fan-outs ran inline per the deepen-pass note in the plan. **Prevention:** none needed; structural harness constraint, already disclosed in session-state.md.
2. None further — QA ran clean on the first pass (resilience suite 175/0, `run-all.sh` ALL FIXTURE TESTS PASS).

## Tags

category: ci-reliability
module: rls-authz-fuzz, supabase-pre-pull-images
