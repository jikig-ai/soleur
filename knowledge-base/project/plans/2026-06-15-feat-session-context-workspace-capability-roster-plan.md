---
title: "feat: Inject workspace state + MCP capability roster at session start"
issue: 5319
branch: feat-one-shot-5319-session-context-workspace-capability-roster
date: 2026-06-15
type: enhancement
lane: cross-domain  # Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).
brand_survival_threshold: none
---

# ✨ feat: Inject workspace state + MCP capability roster at session start (#5319)

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Implementation (Phase 2 code), Acceptance Criteria, Risks, Test Scenarios, Observability
**Research agents used:** repo-research-analyst, learnings-researcher, verify-the-negative pass (general-purpose, sonnet), architecture-strategist

### Key Improvements (from deepen pass)
1. **Fixed a real bug pre-implementation:** `git ... | wc -l || echo 0` produces a double `0\n0` under `pipefail` when git fails (wc emits `0`, then `|| echo 0` fires on the propagated pipe exit). Phase 2 now wraps git INSIDE the pipe (`{ git ... || true; } | wc -l`).
2. **Corrected the fail-OPEN rationale:** command-substitution assignment failures do NOT fire the ERR trap (empirically verified); the `|| …` guards exist for fallback VALUES, and the real trap risk is bare statement-position commands — documented in the Phase 2 comment.
3. **Relabeled `MCP(static):` → `MCP(committed-config):`** — `.claude/settings.json` mcpServers are also "static"; the new label names the source honestly.
4. **Promoted malformed-JSON (the load-bearing `|| true` guard) to AC10 + a RED test** per `cq-write-failing-tests-before`.
5. **AC7 now pins line POSITION (4-6), not just byte width**, guarding the "outside Test 11's `head -3` window" invariant against a newline-in-`REPO_ROOT` shift.

### New Considerations Discovered
- The MCP roster spans TWO committed files, not one (issue's `.mcp.json`-only premise undercounts); confirmed `.mcp.json`={playwright}, `plugin.json`={context7,cloudflare,vercel,stripe}.
- `jq -r '.mcpServers // {} | keys[]'` is correct and returns empty (exit 0) on `{}` — guards are defense-in-depth, not load-bearing for the empty case.
- `paste -sd, -` (GNU) verified to comma-join; `head -3` Test 11 window verified to exclude lines 4+.

## Overview

The SessionStart hook `.claude/hooks/session-rules-loader.sh` already injects change-class
rule partitions, a rule-count stamp, a re-run hint, and the manifest path into the agent's
`additionalContext`. It does **not** inject two context types the scheduled agent-native audit
flagged (Context Injection scored 45%, second-lowest of 8 principles):

1. **Workspace state** — current branch, worktree path, and uncommitted (dirty) file count.
   Subagents currently resolve this manually, the documented root cause of stale bare-repo
   reads (`2026-03-04-sessionstart-hook-api-contract.md`, `2026-04-29-subagent-stale-file-read-in-worktree.md`).
2. **MCP capability roster** — the live MCP server list is never surfaced in-prompt, so the
   agent cannot see which capabilities (playwright, cloudflare, vercel, stripe, context7) are live.

This plan extends the existing stamp block with a `[session-context]` snapshot, guarded fail-open
so a missing `git`/`jq` or a malformed config file never breaks session start (fail-open on the
snapshot, fail-closed on the rules — these are distinct contracts).

**Scope:** ~30-40 LOC added to one existing 215-line bash script + new tests in the colocated
`.test.sh` harness. No new dependencies (git + jq are already required by the hook).

## Research Reconciliation — Spec vs. Codebase / Issue

The issue body contains two factual drifts that change the plan shape. Caught at plan-time grep
(`hr-verify-repo-capability-claim-before-assert`):

| Issue claim | Reality (verified `origin/main`) | Plan response |
|---|---|---|
| MCP roster example output: `MCP: playwright,pencil,stripe,vercel` | `.mcp.json` contains **only** `playwright`. `pencil` is in **neither** static config (registered dynamically by the `pencil-setup` skill / CLI). `stripe`+`vercel` live in `plugins/soleur/.claude-plugin/plugin.json` `mcpServers`, not `.mcp.json`. | Roster reads **two** sources: `.mcp.json` (playwright) ∪ `plugins/soleur/.claude-plugin/plugin.json` `mcpServers` (context7, cloudflare, vercel, stripe). Label dynamically-registered servers (pencil/supabase) out of scope — they are not statically discoverable. Annotate the roster as `MCP(committed-config):` to avoid over-claiming. |
| "~50 LOC: git queries + `jq` parse of `.mcp.json`" — single source | Roster must union two files; `plugin.json` is the larger source. | Parse both files; tolerate either being absent with `// empty` + `|| true`. |
| Example single line: `[session-context] branch: … | worktree: … | dirty: N | MCP: …` | A realistic line (full worktree abs-path + 60-char branch name + 5 servers) measures **287 bytes** — exceeds the 200-byte/line stamp constraint that Test 11 asserts on the first 3 lines. | Do **not** emit session-context as one ≤200-byte line. Either (chosen) place it on its own line(s) AFTER the manifest line so it is outside Test 11's `head -3` window, and give it a **dedicated** byte-budget test with a relaxed (or per-field) cap. See Sharp Edges + Phase 2. |

## User-Brand Impact

**If this lands broken, the user experiences:** the agent boots with a malformed or absent
`[session-context]` line — degraded context quality (agent re-derives branch/worktree manually),
but no user-facing UI artifact and no data exposure. Worst case if the fail-open guard is wrong:
the hook errors before emitting `additionalContext`, dropping ALL rule bodies — but the existing
`trap ERR emit_core_only_fallback` (line 29) already guarantees core rules ship on any error path,
so this regression is bounded to "core-only fallback," not "no rules."

**If this leaks, the user's data is exposed via:** the snapshot is local repo metadata (branch
name, worktree path, file count, MCP server names) emitted only into the agent's own
`additionalContext` — no PII, no secrets, no cross-tenant data. MCP server names are
configuration-public (already in committed `.mcp.json` / `plugin.json`). No exposure vector.

**Brand-survival threshold:** none.

_threshold: none, reason: internal tooling hook that injects local repo metadata into the agent's own context; touches no user data, no schema, no auth, no API surface, no regulated data._

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Workspace fields present.** `additionalContext` contains a `[session-context]`
  block whose first line carries `branch: <name>`, `worktree: <abs-path>`, and `dirty: <N> files`
  where `<N>` equals `git -C "$REPO_ROOT" status --porcelain | wc -l`.
  Verify: invoke the hook against a fixture repo with 2 dirty files; assert
  `printf '%s' "$ctx" | grep -E '^\[session-context\].*dirty: 2 files'` returns the line.
- [x] **AC2 — MCP roster unions both sources.** The roster line lists every key from BOTH
  `.mcp.json` `.mcpServers` and `plugins/soleur/.claude-plugin/plugin.json` `.mcpServers`,
  de-duplicated and comma-joined, prefixed `MCP(committed-config):`. Against a fixture seeding
  `.mcp.json` = `{playwright}` and a stub `plugin.json` = `{context7,stripe}`, assert the line
  contains all three names.
- [x] **AC3 — Fail-open on missing config.** With NO `.mcp.json` and NO `plugin.json` in the
  fixture repo, the hook still exits 0, still emits non-empty `additionalContext` with all rule
  bodies, and the roster reads `MCP(committed-config): (none)`. Assert exit code 0 and rule bodies present.
- [x] **AC4 — Fail-open on missing/old git.** Stub `PATH` to hide `git` (or feed a repo where
  `git rev-parse --abbrev-ref HEAD` fails); assert the hook still exits 0, emits `additionalContext`,
  and the workspace line degrades gracefully (`branch: (unknown)` rather than crashing).
- [x] **AC5 — Existing 14 tests still pass.** `bash .claude/hooks/session-rules-loader.test.sh`
  reports `RESULT: N/N passed (0 failed)` with N ≥ 19 (14 existing + ≥5 new: AC1-AC4, AC7, AC10).
- [x] **AC6 — Rule-loading contract untouched.** The class-selection logic (AC for `assert_class`
  tests in the existing harness) is unchanged: docs→`core+docs-only`, code→`core+rest`, mixed→all.
  The session-context block is **appended** after the manifest line; it must not alter `STAMP`,
  `HINT`, `RULE_COUNT`, `TOTAL_RULES`, or `CONTEXT`.
- [x] **AC7 — Byte-budget + line-position test for the new line(s).** A new test asserts each
  `[session-context]` line is ≤ the agreed cap (proposed: 512 bytes, justified in Phase 3 against
  realistic worktree-path + branch-name lengths) AND that the `additionalContext` envelope has the
  expected total line count with the 3 session-context lines at positions 4-6 (pins the "lines 4-6,
  outside Test 11's `head -3` window" invariant against a newline-in-REPO_ROOT line-shift rather
  than assuming it). Test fixture uses a long branch name + deep worktree path.
- [x] **AC8 — `shellcheck` clean.** `shellcheck .claude/hooks/session-rules-loader.sh` produces no
  new warnings vs. the pre-change baseline (capture baseline at Phase 0).
- [x] **AC10 — Fail-open on malformed JSON.** Seed the fixture `.mcp.json` with literal
  `{invalid json` (not valid JSON → jq exit-5). Assert the hook exits 0, the roster falls back to
  the `plugin.json` keys only (the `|| true` on the first jq line swallows the parse error), and
  rule bodies are present. This is the load-bearing test for the `|| true` guards — promoted from
  Test Scenario 6 per `cq-write-failing-tests-before` (the guard must have a RED test).

### Post-merge (operator)

- [ ] **AC9 — Live verification.** _Automation: feasible inline._ After merge, the change ships
  via the repo (no deploy step — hooks run from the checked-out tree). Verify by starting a fresh
  session in the worktree and confirming the `[session-context]` line appears. This is a
  read-only observation; no operator prod-write. (The merge IS the delivery.)

## Files to Edit

- `.claude/hooks/session-rules-loader.sh` — add a `[session-context]` snapshot block between
  the manifest write (line ~210) and the final `OUT_BODY` assembly (line ~213). New helper(s):
  `git rev-parse --abbrev-ref HEAD`, `git status --porcelain | wc -l`, and a jq union over the two
  config sources. All guarded `|| true` / `// empty`. (~30-40 LOC.)
- `.claude/hooks/session-rules-loader.test.sh` — add ≥5 new tests (AC1-AC4, AC7, AC10). Extend
  `setup_repo` to optionally seed a `.mcp.json` fixture (well-formed AND a malformed variant for
  AC10) and a stub `plugin.json` at the fixture's `plugins/soleur/.claude-plugin/` path. Model
  after existing Test 9 (manifest schema) and Test 11 (byte budget). Increment `TOTAL` per test.

## Files to Create

None. (Both edits are to existing files; no new test file, no new doc — the hook's README already
documents the SessionStart contract.)

## Implementation Phases

### Phase 0 — Preconditions (verify at /work start, do not trust plan-quoted numbers)
- Re-read `.claude/hooks/session-rules-loader.sh` lines 170-215 (assembly block) — confirm line
  numbers haven't drifted since 2026-06-15.
- Run `bash .claude/hooks/session-rules-loader.test.sh` — confirm baseline `14/14 passed`.
- Run `shellcheck .claude/hooks/session-rules-loader.sh` — capture baseline warning set.
- `python3 -c "import json; print(list(json.load(open('plugins/soleur/.claude-plugin/plugin.json'))['mcpServers'].keys()))"`
  — confirm the plugin roster is still `[context7, cloudflare, vercel, stripe]`.
- Confirm `scripts/test-all.sh` line ~182 still globs `.claude/hooks/*.test.sh` (CI wiring).

### Phase 1 — RED: write failing tests (cq-write-failing-tests-before)
- Add tests AC1-AC4 + AC7 + AC10 to `session-rules-loader.test.sh`, extending `setup_repo` to seed
  the two config fixtures (well-formed + a malformed `.mcp.json` variant for AC10). Run the suite;
  the new tests MUST fail (no session-context line emitted yet).

### Phase 2 — GREEN: implement the snapshot block
Insert after the manifest `jq` write (current line ~210), before `OUT_BODY=` (current line ~213):

```bash
# --- Session-context snapshot (#5319) — workspace state + committed-config MCP roster. ---
# Fail-OPEN value contract: every query yields a usable fallback so the snapshot
# never blanks out. NOTE on the ERR trap (verified 2026-06-15): a plain assignment
# `VAR=$(failing_cmd)` does NOT fire the trap even unguarded — command-substitution
# failure in assignment position is ERR-exempt. The `|| …` guards here exist to
# produce FALLBACK VALUES, not for trap-safety. The genuine trap risk is a BARE
# non-zero-returning command at statement position — DO NOT introduce one in this
# block (keep every external call inside a command-sub with a `|| …` fallback).
WS_BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(unknown)")
# Guard git's non-zero exit INSIDE the pipe, not after it. `… | wc -l || echo 0`
# is a double-output bug under pipefail: when git fails, `wc -l` already emits "0"
# AND the pipeline's non-zero exit fires `|| echo 0`, yielding "0\n0" → a 2-line
# dirty field that breaks the format. Wrapping git in `{ …; || true; }` keeps the
# pipe success so wc's single "0" is the only output. (verify-negative pass #7.)
WS_DIRTY=$( { git -C "$REPO_ROOT" status --porcelain --ignore-submodules=all 2>/dev/null || true; } | wc -l | tr -d ' ')

# Committed-config MCP roster = .mcp.json ∪ plugins/soleur/.claude-plugin/plugin.json
# mcpServers. Label is MCP(committed-config) — NOT MCP(static) — because servers
# declared in .claude/settings.json or registered dynamically (pencil via
# pencil-setup, supabase via plugin) are also "static" but out of this read's scope.
# The label names the SOURCE honestly rather than over-claiming the live set.
MCP_SERVERS=$(
  {
    jq -r '.mcpServers // {} | keys[]' "$REPO_ROOT/.mcp.json" 2>/dev/null || true
    jq -r '.mcpServers // {} | keys[]' "$REPO_ROOT/plugins/soleur/.claude-plugin/plugin.json" 2>/dev/null || true
  } | sort -u | paste -sd, - || true
)
[[ -z "$MCP_SERVERS" ]] && MCP_SERVERS="(none)"

# Line-1 field order (branch | dirty) is LOAD-BEARING for AC1's grep
# `^\[session-context\].*dirty: N files`. Do not move `dirty` to its own line.
SESSION_CONTEXT="[session-context] branch: ${WS_BRANCH} | dirty: ${WS_DIRTY} files
[session-context] worktree: ${REPO_ROOT}
[session-context] MCP(committed-config): ${MCP_SERVERS}"
```

Then append to the envelope (note: AFTER the manifest line so it is outside Test 11's `head -3`):

```bash
OUT_BODY="${STAMP}"$'\n'"${HINT}"$'\n'"[rules-loader] manifest: ${MANIFEST}"$'\n'"${SESSION_CONTEXT}"$'\n'"${CONTEXT}"
```

Design notes baked into the block:
- **Split across 3 lines** (branch+dirty / worktree / MCP) so no single line approaches the
  287-byte worst case from the Research Reconciliation table. Worktree path gets its own line.
- **`|| true` / `// empty` on every external query** per `2026-03-18-stop-hook-jq-invalid-json-guard.md`
  and `2026-05-27-bash-set-e-leaks-from-functions-use-or-true.md` — no `set +e` toggling.
- **No new `jq`-availability guard needed at point of use**: jq is already required for the
  manifest write (line 205) and final envelope (line 214); if jq were absent the hook would have
  already failed earlier. The `|| true` is defense-in-depth for malformed-JSON exit-5, not absence.

Run the suite; AC1-AC4 + AC7 must now pass and the original 14 must stay green.

### Phase 3 — Byte-budget test + cap justification (AC7)
- Set the per-line cap to **512 bytes** (justification: a 200-char abs worktree path + a 100-char
  branch name + label overhead ≈ 320 bytes worst case; 512 leaves headroom without being unbounded).
- Add a fixture with a 100-char branch name and a deep worktree path; assert each
  `[session-context]` line ≤ 512 bytes.
- Confirm Test 11 (the existing `head -3` ≤200 check) still passes UNCHANGED — the session-context
  lines are lines 4-6, outside its window. This is intentional: the 200-byte stamp contract is for
  the operator-glanceable header; session-context carries unbounded-by-nature paths.

### Phase 4 — Lint + full-suite gate
- `shellcheck .claude/hooks/session-rules-loader.sh` — zero new warnings (AC8).
- `bash scripts/test-all.sh bash` (or the scripts shard) — confirm the hook test runs green under
  the CI harness, not just standalone.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| 1 | Clean worktree, both config files present | `branch:`, `dirty: 0 files`, `worktree:`, full union roster |
| 2 | 2 dirty files | `dirty: 2 files` |
| 3 | No `.mcp.json`, no `plugin.json` | `MCP(committed-config): (none)`, hook exits 0, rule bodies present |
| 4 | `git` hidden from PATH | `branch: (unknown)`, hook exits 0 |
| 5 | Long branch + deep worktree path | each session-context line ≤ 512 bytes; session-context at envelope lines 4-6 |
| 6 (AC10) | Malformed `.mcp.json` (invalid JSON) | jq exit-5 swallowed by `|| true`; roster falls back to plugin.json keys only; exit 0 |
| 7 | docs-only / code / mixed change classes | class selection unchanged (existing assert_class tests) |
| 8 | `git status` fails mid-pipe (bare repo) | `dirty: 0 files` — single `0`, NOT `0\n0` (the wrapped-git-in-pipe fix); one-line dirty field |

## Observability

```yaml
liveness_signal:
  what: "[session-context] line present in additionalContext on every session start"
  cadence: "every SessionStart event (startup|resume|clear|compact)"
  alert_target: "none — non-critical context enrichment; absence degrades but does not break"
  configured_in: ".claude/hooks/session-rules-loader.sh (emit at OUT_BODY assembly)"
error_reporting:
  destination: "stderr of the hook process (visible in Claude Code hook logs); NO Sentry — cq-silent-fallback-must-mirror-to-sentry N/A because this hook runs in the local CLI process, not a server runtime (the rule targets server error paths)"
  fail_loud: "false by design — fail-OPEN on the snapshot per #5319; the rules contract remains fail-CLOSED via the existing ERR trap (emit_core_only_fallback)"
failure_modes:
  - mode: "git query fails (bare repo / no git)"
    detection: "WS_BRANCH falls back to (unknown); asserted by AC4 test"
    alert_route: "none — graceful degradation, covered by test"
  - mode: "config file missing or malformed JSON"
    detection: "MCP(committed-config): (none) or partial roster; asserted by AC3 + AC10 tests"
    alert_route: "none — graceful degradation, covered by test"
  - mode: "session-context line absent entirely (regression)"
    detection: "AC1/AC5 tests fail in CI (scripts/test-all.sh globs the .test.sh)"
    alert_route: "CI red on PR — pre-merge gate"
logs:
  where: "Claude Code hook stdout (additionalContext) + stderr; no persistent log file"
  retention: "session-scoped; the 3-field manifest at .claude/.session-manifests/<id>.json is the only persisted artifact and is unchanged by this PR"
discoverability_test:
  command: "bash .claude/hooks/session-rules-loader.test.sh"
  expected_output: "RESULT: N/N passed (0 failed) with N >= 18"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change to a local SessionStart hook.
No UI surface (no file under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`), no
schema/migration/auth/API surface, no marketing/legal/finance/sales/support implication. The
mechanical UI-surface override did not fire (Files to Edit are `.sh` only).

## Infrastructure (IaC)

Skipped — no new infrastructure. This edits an existing repo-local bash hook that runs from the
checked-out tree. No server, service, cron, secret, vendor account, DNS, or firewall rule
introduced. The MCP servers being *enumerated* already exist in committed config; this PR only
*reads* them.

## GDPR / Compliance Gate

Skipped — no regulated-data surface touched. The hook reads local git metadata (branch, path, file
count) and public MCP-server config names, emitting them only into the agent's own context. None of
the canonical regex surfaces (schema, migration, auth, API route, `.sql`) apply, and none of the
(a)-(d) expansion triggers fire (no LLM processing of session-derived data, threshold `none`, no
cron reading learnings/specs, no new distribution surface).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue body referencing
`session-rules-loader` or `.mcp.json`.

## Risks & Mitigations

- **Risk: insertion point shifts an existing line into / out of Test 11's `head -3` window.**
  Mitigation: append session-context AFTER the manifest line (line 4+), keeping STAMP/HINT/manifest
  as lines 1-3. Phase 3 explicitly re-runs Test 11 to confirm it stays green unchanged.
- **Risk: `plugin.json` path differs across plugin layouts / the file is absent in a consumer's
  checkout.** Mitigation: `|| true` + `// {}` makes an absent file contribute zero keys; AC3
  covers the both-absent case. The path `plugins/soleur/.claude-plugin/plugin.json` is verified to
  exist on `origin/main`.
- **Risk: `paste -sd, -` behaves differently on BSD vs GNU.** Mitigation: the repo's hooks already
  assume GNU coreutils (CI runs ubuntu-latest; `awk`/`sort -u` used elsewhere). Precedent:
  `CHANGES` block at line 91-97 uses `sort -u` identically. Note in /work to confirm `paste -sd,`
  output on the dev box.
- **Risk: over-claiming the MCP set.** pencil/supabase (dynamic) AND any server in
  `.claude/settings.json` would be absent from this read. Mitigation: label
  `MCP(committed-config):` not `MCP(static):` — the label names the SOURCE (the two committed config
  files) honestly rather than claiming completeness over the live set. Adding `.claude/settings.json`
  as a third source is a deliberate YAGNI scope-out (the two-file union covers the audited gap).
- **Risk: double-output `0\n0` in the dirty count under pipefail** (verify-negative pass #7).
  `git ... | wc -l | tr -d ' ' || echo 0` emits TWO zeros when git fails (wc's `0` + the `|| echo 0`
  firing on the propagated non-zero pipe exit), breaking the single-line dirty field. Mitigation
  (baked into Phase 2): wrap git in `{ git ...  || true; } | wc -l | tr -d ' '` so the pipe succeeds
  and wc's single `0` is the only output. Scenario 8 tests this.
- **Risk: newline / control char in `REPO_ROOT` shifts session-context out of lines 4-6**, pulling a
  fragment into Test 11's `head -3` window. The hook already constrains `REPO_ROOT` to a real git
  worktree (source lines 81-84), making this near-impossible, but AC7's total-line-count + position
  assertion pins the invariant rather than assuming it.

## Sharp Edges

- A single-line `[session-context]` with a full abs worktree path + long branch name measures
  **287 bytes** (verified 2026-06-15), exceeding the 200-byte stamp contract. The split-into-3-lines
  design and the line-4+ placement are load-bearing — do NOT collapse them back to one line to
  "match the issue's example output," which is itself wrong (see Research Reconciliation).
- A plan whose `## User-Brand Impact` section is empty, placeholder, or threshold-less fails
  `deepen-plan` Phase 4.6. This section is filled (threshold: none, with sensitive-path scope-out
  reason).
- The MCP roster spans TWO files, not one. The issue's "jq parse of `.mcp.json`" undercounts —
  `.mcp.json` holds only playwright; the four HTTP servers live in `plugin.json`.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Emit session-context as ONE ≤200-byte line (per issue example) | Rejected — 287-byte worst case overflows the stamp contract; truncation would drop the worktree path, the single most load-bearing field for the stale-read mitigation. |
| New standalone hook for session-context | Rejected (YAGNI) — the SessionStart loader already resolves `REPO_ROOT` safely and emits `additionalContext`; a second hook duplicates the worktree-resolution + fail-open logic the audit specifically wants consolidated. |
| Parse only `.mcp.json` (issue's literal recommendation) | Rejected — would surface only `playwright` and silently omit cloudflare/vercel/stripe/context7, defeating the "capability roster" goal. |
| Subject session-context to the 200-byte test by truncating fields | Rejected — truncating the worktree path defeats the purpose; a relaxed 512-byte per-line cap with a dedicated test is the honest contract. |

_No deferrals requiring tracking issues: dynamic MCP servers (pencil/supabase) are out of scope by
nature (not statically discoverable), not deferred work — there is no future state in which a
static config read would surface them, so no tracking issue is warranted._
