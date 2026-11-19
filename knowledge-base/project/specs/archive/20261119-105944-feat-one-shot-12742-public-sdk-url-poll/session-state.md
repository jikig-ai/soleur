# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-17-feat-inngest-sdk-url-sync-evidence-strict-preflight-plan.md
- Status: complete

### Errors
- `gh issue view --comments --json` flag conflict (earlier thread) — resolved by separate calls.
- `git commit` blocked twice by the worktree guard: (a) false-positive "main/master" branch detection, (b) unresolvable `$(pwd)`/env-mutation in command. Fixed by using literal `git -C /abs/path` with `git add` as its own call.
- `lint-guard-contract.py` rejected the first Guard Contract draft (numbered lists don't count as matrix rows — only markdown table rows). Fixed; lint now green (3 guard entries).

### Decisions
- **Sync evidence (item 1):** second loopback GQL `apps { url error }` → appended fields `sdk_sync` (`ok|error|no_apps|n/a|__UNREADABLE__`) and `sdk_app_url` (sanitized) on both emit and phone-home lines; `probe_schema` 9→10. `error` is refreshed by the server's own pollSDKs loop, so `ok` proves the *last* attempt succeeded — discriminates stale-registry (the gap the #12737 alert cannot see) without extending the live paging SQL (extension deferred; recorded).
- **F4(ii):** chose sanitize over `countMatches` — a spaced free-text value corrupts `key=value` parsing for *every* consumer; sanitize at the `image_ref`/`cli_version` bind sites (charset `[A-Za-z0-9_:.@/+-]`, in-file `tr` precedent L1184), plus a rendered-line hostile-input row in the drift guard.
- **Preflight:** new `tests/scripts/lib/inngest-public-sdk-url-preflight.sh` mirrors the ADR-136 `preapply-entrypoint-gate.sh` shape — execs `doppler run -p soleur -c prd_terraform -- cloudflare-readonly.sh config-entrypoint`, judges the `.rules[]` projection (not the wrapper's dated-snapshot verdict): pass iff the LAST enabled `mentions_app_host` rule is `ssl=strict`; distinct `::error::` per refusal arm; `--from-file` test seam. Steps placed *after* `Load infra credentials` in both `inngest_host`/`inngest_host_replace` (old "before-credentials" property vacated by design).
- **Deepen findings folded in:** dark-gate lib has three sourcing callers — `scheduled-inngest-health.yml`'s report-only witness needs a `stale_schema` streak-classification audit (T2a); workflow byte headroom is 5 B → net-negative step swap mandated; `hr-` (not `cq-`) rule-ID citation corrected.
- **Out of scope preserved:** items 2–9, `inputs.confirm` input itself (~10 other consumers), registry-empty alert SQL. Item-9 carrier-comment tension recorded (decision row 7 — recommend opportunistic refresh since this PR edits the file "for a real reason").
- Only `knowledge-base/project/**` paths were created/edited — no product code, workflow YAML, or tests touched.

### Components Invoked
- `soleur:plan` skill (phases 0–5 run inline; skeleton + research + gates consolidated into the plan write; skeleton checkpoint satisfied by the premise-validation research log)
- `soleur:deepen-plan` skill (prose mode; all mechanical gates verified inline: User-Brand Impact `aggregate pattern`, Observability 5-field block, Encryption Posture schema, Guard Contract lint green, Scope Check schema w/ Ask Mapping + Provenance + Split Assessment, Downtime & Cutover, precedent-diff, PAT sweep clean, rule-ID check; §4.5/4.9/4.13 not triggered). `Reviewed-Coverage: sequential-fallback` — agent spawns, Context7, and WebSearch unavailable; research/verify-the-negative/review passes ran inline.
- Tools used: `gh`, `git`, `python3 scripts/lint-guard-contract.py`, grep/sed/wc sweeps.

## Operator Constraints

None — the resume brief carried no constraint lines (status handoff, no Constraints paragraph or rules list).

## Technical Rulings
- `cto_spawns=1` (2026-11-17, batched — all 10 rows ruled; 8 ratified, item 4 strengthened, item 5 overturned; plan/tasks amended)
