---
title: "fix: memory-backstop version-independent hook resolution"
type: fix
date: 2026-09-29
slug: fix-backstop-hook-version-resolution
branch: feat-one-shot-9239-backstop-hook-resolution
issue: 9239
closes: 9239
priority: high
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: memory-backstop version-independent hook resolution

## Enhancement Summary

**Deepened on:** 2026-09-29 (inline deepen — this run executes inside a pipeline subagent with no Task/Workflow spawn capability; all deepen-plan halt gates were executed mechanically and the fan-out lenses were applied as inline verification passes)

**Gates run (all PASS):** 4.6 user-brand (section present, `none` threshold, zero sensitive-path matches), 4.7 observability (5-field block, allowlisted `bash` probe verb, literal `resolved=` expected output), 4.8 PAT regex (no hits), 4.9 UI-wireframe (no UI-surface files — skip), 4.10 encryption (evaluated — the managed path carries executable code, not a data store; the ledger pre-exists; no new cross-component connection — skip), 4.11 guard contract (`lint-guard-contract.py` green, 3 entries), 4.4 precedent-diff (flock idiom precedent: `agent-token-tee.sh:179`, already cited by the hook at :85; atomic tmp+mv publish precedent: `scripts/lib/scratch-root.sh`, `scripts/ensure-doppler.sh`).

**Corrections applied by the deepen pass:**

1. `_repo_root()` needs NO change — it already prefers `CLAUDE_PROJECT_DIR` (`memory-backstop.sh:87-90`); the plan originally claimed it required a patch. AC5 now *pins* the existing behavior.
2. Publish needed a TOCTOU clause: concurrent SessionStarts could both publish, so the install is serialized under `flock` with an in-lock revision re-check (macOS lacks `flock` → `command -v` guard + pre-`mv` re-check, residual race self-heals).
3. `devin-dispositions.tsv:111` was cited as evidence the hook "fires-then-exits under Devin" — that row predates #9231's multi-agent adoption, so the plan now relies on the directly-verified `.devin/config.json` absence instead.

### New Considerations Discovered

- Plugin caches verified live: `~/.claude/plugins/cache/<mkt>/<plugin>/<ver>/hooks/` and `~/.local/share/devin/cli/plugins/cache/<slug>/<ver>/hooks/`. A plugin installed from a *local-path* marketplace source may not appear under `plugins/cache` — that gap is covered by the managed path, not the glob (recorded in Risks).
- Nothing outside the hook itself + README consumes `.memory-backstop.jsonl` and no test pins `schema:1` — the `schema:2` bump is free (verified: zero grep hits for `schema` in the test file/battery, zero external readers).

## Overview

`.claude/settings.json` invokes `"$CLAUDE_PROJECT_DIR"/.claude/hooks/memory-backstop.sh` — the copy inside whichever checkout or worktree the session runs in. A merged protection upgrade therefore only reaches sessions launched from a checkout containing it; sessions resumed from stale branches run the stale hook. On 2026-09-29 a third herdr crash was demonstrated from exactly this shape: sessions resumed into a stale branch's hook were adopted with the default `TasksMax=37984`, and a detached `gh api` storm inside an unadopted devin pane re-saturated the terminal scope's `pids.max` at 22:53:47. Updating the Soleur plugin cannot help today because the plugin does not ship the hook and the plugin cache is not on the exec path.

This plan makes hook resolution version-independent: a thin, rarely-changing resolver shim becomes the stable `settings.json` entry point and selects the newest installed copy — a managed path under the user's data directory and the plugin caches — with the per-checkout copy as the development fallback. A revision marker in the hook orders candidates; the newest copy observed self-publishes to the managed path so one fresh session upgrades the whole host. A stale-scope cap repair folded into the sweep closes the "running session adopted under old caps" window without restarts, and the ledger records which copy ran so future regressions are visible in the same evidence channel this issue used.

## Problem Statement / Motivation

Three distinct defects compose the issue:

1. **Resolution is checkout-pinned.** `settings.json` execs the hook file inside the session's checkout. Merged upgrades (#9230 TasksMax, #9231 multi-agent adoption + sweep) protect only checkouts that contain them. A resumed session on an old branch silently runs old protection — the ledger showed five adoptions at 20:54:21Z missing `scope_tasks`/`swept` fields, and `systemctl show` confirmed `TasksMax=37984` (default).
2. **Plugin updates bypass the hook entirely.** `plugins/soleur/hooks/` does not contain `memory-backstop.sh` (verified — the plugin ships `browser-cleanup-hook.sh`, `codex-session-start.sh`, `devin-session-start.sh`, `compaction-state.sh`, `stop-hook.sh`, etc., but not the backstop), so `claude plugin update` delivers nothing for this control. The operator's demonstrated remediation action was a no-op.
3. **Stale-adopted scopes are never repaired.** `sweep_unadopted_agents` (`.claude/hooks/memory-backstop.sh:301`) explicitly skips `soleur-agent-*.scope` members (`[[ "$ts" == soleur-agent-*.scope ]] && continue`), so a session adopted by the old hook keeps default caps until its own next SessionStart — and a running session fires SessionStart only on `startup|resume|clear|compact`.

## Proposed Solution

Four cooperating mechanisms, ordered by which property each buys (see Research Insights → Property List):

**M1 — Resolver shim** `.claude/hooks/memory-backstop-resolve.sh` (new, ~120 lines, `#!/usr/bin/env bash`). `settings.json` invokes `bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/memory-backstop-resolve.sh` (the `bash`-prefixed form is mode-bit-immune — the #7151 `EACCES` defect). The shim:

- Enumerates candidates in precedence order:
  1. `$(dirname "${BASH_SOURCE[0]}")/memory-backstop.sh` — the checkout copy
  2. `${XDG_DATA_HOME:-$HOME/.local/share}/soleur/hooks/memory-backstop.sh` — the managed copy
  3. `$HOME/.claude/plugins/cache/*/*/*/hooks/memory-backstop.sh` — Claude plugin cache (glob; all installed versions)
  4. `$HOME/.local/share/devin/cli/plugins/cache/*/*/hooks/memory-backstop.sh` — Devin plugin cache (glob)
- Reads each candidate's `BACKSTOP_REVISION` by **grep, never `source`** (`grep -m1 -oE 'BACKSTOP_REVISION=[0-9]+'`), treating a missing/non-numeric marker as revision 0 and skipping unreadable/non-regular files. Sourcing a candidate to learn its version would execute unverified code in the resolver — ADR-156's untrusted-input posture applied to hook bodies.
- Selects the highest revision; ties resolve to the first candidate in precedence order (checkout first — a local uncommitted edit wins over an equally-versioned installed copy, preserving dev flow).
- `bash -n` syntax-checks the winner before exec; on failure falls to the next candidate in descending revision order.
- Self-publishes: when the winner is not the managed copy and its revision is strictly greater than the managed copy's, atomically installs it — `install -m 0755` to `tmp` sibling then `mv`, `mkdir -p` of `${XDG_DATA_HOME}/soleur/hooks/` and `lib/`, plus `lib/log-rotation.sh` when the winner's own `lib/` carries it (the hook sources `$(dirname BASH_SOURCE)/lib/log-rotation.sh` opportunistically; publish keeps that path real for the managed copy). Publish happens BEFORE exec, so a hook that crashes still leaves the upgrade installed. **TOCTOU:** concurrent SessionStarts can both decide to publish — serialize the install under `flock` on `${XDG_DATA_HOME}/soleur/.publish.lock` (guarded by `command -v flock`; macOS lacks it, so there re-check the managed revision immediately before `mv` and accept the residual race — a strictly-newer candidate re-publishes on its next run, so the regression is transient, and worst case is bounded because the winner set still contains the newest copy). Inside the lock, re-read the managed revision and skip the install unless strictly newer.
- Exports `SOLEUR_BACKSTOP_RESOLVED_FROM=<path>` and `SOLEUR_BACKSTOP_RESOLVED_REVISION=<n>` for the ledger, then `exec bash "$winner"`.
- `--print-resolution` mode: prints `resolved=<path> revision=<n>` and exits 0 read-only (no publish, no exec) — the observability probe.
- **Never blocks**: `exit 0` on every path; on total failure (no candidate execs) emits a `systemMessage` JSON line (`jq -n '{systemMessage:$m}'`, the same channel `emit_message` uses at `memory-backstop.sh:118` — printf fallback when jq is absent, since the hook itself declines `no_jq` anyway) and exits 0.
- Carries its own `RESOLVER_REVISION=1` marker. The shim is the one component that cannot self-upgrade — a stale checkout's shim stays stale — so it is kept minimal and its contract (candidate set + revision ordering) is designed to be stable.

**M2 — Hook changes** `.claude/hooks/memory-backstop.sh`:

- `readonly BACKSTOP_REVISION=1` beside the cap constants (~line 78), with a header contract line: *bump on every behavioral change; the resolver orders candidates by it*.
- `_repo_root()` (line 86) needs **no change** — it already prefers a non-empty `${CLAUDE_PROJECT_DIR}` (:87-90) before the `BASH_SOURCE`-derived path, so a managed/plugin copy already writes the ledger, lock and stamp under the session's project dir. AC5 pins that pre-existing behavior with a fixture test (a managed-dir copy writing into the project root is the new exec shape; pinning it is what makes the arrangement contractual).
- New `repair_stale_scopes()` called inside the flock after `sweep_unadopted_agents`: enumerate `soleur-agent-*.scope` units (`systemctl --user list-units --no-legend --no-pager 'soleur-agent-*.scope'`), read caps back (batched `systemctl --user show`), and `busctl ... SetUnitProperties ... true` (runtime-only — never `set-property` without `--runtime`, same rule the existing code documents) any scope whose caps differ from current constants. `OOMPolicy` is deliberately EXCLUDED from the repair set — measured on systemd 261 it is creation-only on scopes and SetUnitProperties is all-or-nothing, so including it would drop the four caps with it (the equivalent defect in the re-entry refresh path is filed as #9246). Bounded by `MAX_REPAIR=32`; per-scope failures logged, never fatal; **BindsTo is never re-set or re-derived** (the kill-switch preservation the re-entry branch already documents). This closes the third defect: ANY new-version SessionStart converges every stale-adopted scope on the host, no restart needed.
- Ledger schema `1` → `2` with new fields `backstop_revision` (the running copy's marker), `resolved_from` (`$SOLEUR_BACKSTOP_RESOLVED_FROM`, empty when run directly), `repaired` (count from `repair_stale_scopes`). The issue's own evidence was *missing* fields — explicit fields remove the inference.

**M3 — Plugin payload** `plugins/soleur/hooks/memory-backstop.sh` (new): a byte-equal vendored copy, pinned by a parity test (Guard 2). It is NOT registered in `plugins/soleur/hooks/hooks.json` — payload only; the backstop stays repo-scoped by design (C4 model.c4 `hooks` container: "in the repo-local `.claude/` hook surface only"). With this, `claude plugin update` becomes an independent delivery channel for the protection — the issue's "plugin updates do not reach this hook" complaint — because the resolver globs both plugin caches.

**M4 — Wiring + guards**:

- `.claude/settings.json` SessionStart entry → `bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/memory-backstop-resolve.sh`. This is the ONLY registry that binds the backstop — verified directly: `.devin/config.json` SessionStart binds rules-loader/supabase-loopback-warn/ensure-kb-index only and `.codex/config.toml` binds only `session-rules-loader.sh`. (Do not cite `devin-dispositions.tsv:111`'s "fires-then-exits under Devin" row as evidence — it predates #9231's multi-agent adoption and may be stale; the config-file absence is the live fact.) Devin/codex sessions are covered by the sweep, and now by sweep-repair.
- `scripts/check-backstop-revision.sh` (new) + a path-gated step in `.github/workflows/pr-quality-guards.yml` (mirroring its existing `changed_files`/`git diff --name-only "${diff_base}"...HEAD` pattern at ~line 614): when the PR diff touches `.claude/hooks/memory-backstop.sh`, the `BACKSTOP_REVISION=` line must differ vs merge-base (`git merge-base origin/${{ github.base_ref }} HEAD`, with `git fetch` of the base ref as the workflow already does). Capture the per-file diff to a tempfile before grepping it — the pipe-into-`grep -q` form misfires under `set -e`/pipe-buffering interactions (sharp-edges: `#3550` tempfile-shape learning).
- `plugins/soleur/test/backstop-parity.test.ts` (new): byte-equality of vendored copy vs repo hook, `BACKSTOP_REVISION` marker present, and `settings.json` SessionStart binds the resolver not the hook directly (Guards 2+3).
- `.claude/hooks/README.md`: resolution-order section, managed path, ledger schema:2 fields.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt`: regenerate to admit the vendored copy's entries.

## Technical Considerations

- **Trust boundary.** Every candidate sits under `$HOME` or the checkout — all same-uid-writable, identical trust class to the status quo (the checkout copy is equally editable). The shim adds `bash -n` verification and never sources candidate text. A planted newer revision in a same-uid-writable path confers no privilege the planter didn't already have.
- **Bootstrap limit.** Checkouts predating this change run their old `settings.json` → old hook; nothing can reach their hook *code*. Their *caps* are repaired by M2's sweep-repair the next time any session fires SessionStart, and the branch ages out on rebase. Stated plainly so it is not mistaken for covered.
- **Equal-revision divergence.** Tie-break prefers checkout: a same-revision local edit runs in the checkout that made it, and stays invisible elsewhere until the author bumps the revision and the plugin/parity guards force the copies equal. Deliberate dev-flow choice; documented in the shim header.
- **Failure isolation.** Publish and exec are independent failure domains: a failed publish never blocks exec of the winner; a `bash -n` failure demotes that candidate. Resolver exit 0 unconditionally — SessionStart hooks must never block a session (hook's own invariant).
- **ADR-159 alignment.** "Delivery is not activation": the resolver is the delivery channel; `repair_stale_scopes` is the reconcile-the-units proposition applied to scopes; the ledger's `resolved_from`/`repaired` fields are the per-unit verdicts.

## Research Insights

**Subagent fan-out note:** this run executes inside a pipeline Task subagent with no Task/Skill spawn tool — the `soleur:engineering:research:*` and discovery-agent fan-outs of Phases 1/1.5/1.5b were performed inline via grep/read. Community/functional overlap: N/A — this is repo-internal hook/systemd machinery; no community artifact covers it.

**Premise Validation (Phase 0.6):**

- #9230 `fix(hooks): bound soleur-agent scopes on task count` — **MERGED**. #9231 `feat(hooks): adopt devin and codex sessions, sweep unadopted siblings` — **MERGED**. #7166 (backstop origin) — CLOSED. #9232 (shard packing) — OPEN, unrelated.
- `.claude/settings.json` invokes `"$CLAUDE_PROJECT_DIR"/.claude/hooks/memory-backstop.sh` — verified on this branch (and matches `origin/main`; `git log` shows the hook file's last changes are the two merged PRs).
- `plugins/soleur/hooks/` carries **no** `memory-backstop.sh` — verified; "plugin updates don't reach it" holds literally: the plugin doesn't ship it.
- Proposed mechanism vs ADR corpus: no ADR decides a hook-resolution mechanism; ADR-159 (delivery ≠ activation) *supports* the reconcile-direction; ADR-178/ADR-179 establish plugin-shipped executable payloads as precedent. No rejected-alternative collision.
- Re-entry path (`memory-backstop.sh` ~line 715) already refreshes caps in place on `resume|clear|compact` — the stale-caps window is narrower than the issue frames it for sessions that fire SessionStart again; the uncovered remainder is exactly what `repair_stale_scopes` closes.

**Property List (Phase 0.6b):**

- P1 — A merged protection upgrade reaches sessions regardless of checkout freshness, without rebasing worktrees.
- P2 — A scope adopted under stale caps is brought to current caps without a session restart.
- P3 — Plugin updates (`claude plugin update`) deliver the hook — the operator's demonstrated remediation action must stop being a no-op.
- P4 — The checkout copy still works standalone for plugin-less development and local edits.
- P5 — Which copy ran is visible in the ledger, so "stale hook ran" is evidence, not inference.

**Cut List (Phase 0.6b):**

- `systemd --user` path-unit/timer sweeper — CUT. Buys P2 for the residual "zero SessionStarts ever fire after upgrade" window; M2's `repair_stale_scopes` covers P2 on the first SessionStart of *any* session on the host (10–14 worktrees fire these constantly). A persistent user unit is new lifecycle infrastructure to close a window measured in minutes of host activity.
- Advisory "outdated protection" message — CUT. The issue offers it as the *alternative* to the sweeper. With M1 the running hook is already the newest installed copy at event time; with M2 the stale-caps harm is repaired regardless of which version adopted the session. The remaining signal (this session's code is older than a copy that landed mid-session) is self-evident in the ledger's `resolved_from`/`backstop_revision` fields — P5 subsumes it.
- Re-keying the ledger to a central location — CUT. `_last_logged` semantics are per-checkout; `CLAUDE_PROJECT_DIR` preserves them exactly.

**Key file map:**

- `.claude/settings.json` — the single binding site for the backstop.
- `.claude/hooks/memory-backstop.sh` — 942 lines; `_repo_root`:86, `sweep_unadopted_agents`:301, `main`:447, re-entry refresh ~:715, cap constants :69-80, `BASH_SOURCE==$0` exec guard :942, sources `lib/log-rotation.sh` opportunistically (:467, :882).
- `.claude/hooks/memory-backstop.test.sh` — suite (pure-fixture + live arms; sources the hook, no env injection seams — convention: functions take path arguments).
- `.claude/hooks/memory-backstop-mutation-battery.sh` — mutation battery.
- `plugins/soleur/hooks/hooks.json` — plugin registrations; vendored copy deliberately NOT added (payload only).
- `scripts/plugin-legacy-resolver-probe.sh` — precedent for walking plugin cache/settings sites.
- Cache layouts verified live: `~/.claude/plugins/cache/soleur/soleur/<sha>/hooks/`, `~/.local/share/devin/cli/plugins/cache/github.com_jikig-ai_soleur_plugins_soleur-<hash>/0.0.0-unversioned/hooks/`.
- `scripts/test-all.sh`: `.claude/hooks/*.test.sh` is glob-discovered (line ~100) and shard-assigned by cksum fallback for unmanifested labels — no manifest edit required for the new suite.
- `.github/workflows/pr-quality-guards.yml`: `changed_files` collection pattern at ~line 614/644; `.github/enforcement-contracts.json` has no hook-path entries.

**Relevant learnings:** ADR-161 + #7151 post-mortem (EACCES mode-bit → prefer `bash <path>` exec; no env-var test seams in production code; verify-don't-assume on D-Bus writes); `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous` (mutation matrix written before the guard); `2026-09-19-cleanup-on-failure-is-a-property-of-the-window` (publish ordering vs exec ordering — publish first).

## Open Code-Review Overlap

Two open `code-review` issues touch files this plan edits:

- **#7208** — "memory backstop (#7166): post-merge hardening" — targets `memory-backstop.test.sh` sweep coverage and `memory-backstop-mutation-battery.sh` coverage gaps. **Disposition: acknowledge.** A different concern (assertion coverage of the cgroup sweep, not resolution). This plan's new repair-path arms and resolver suite coexist without conflicting; #7208 stays open.
- **#8008** — "memory-backstop.test.sh live-arm ledger records reachability, not emission" — targets the test file's `live_mark` placement. **Disposition: acknowledge.** Orthogonal to resolution; new arms added by this plan will place `live_mark` correctly per that issue's guidance where live assertions are added.

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator's agent sessions lose the memory/task caps — a runaway command can again exhaust `pids.max`/RAM and kill the whole terminal multiplexer with all in-flight sessions (the demonstrated third herdr crash).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data-egress path is introduced; the new surface is a user-local writable directory (`~/.local/share/soleur/`) of the same trust class as the checkout itself.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: ledger line `outcome:"applied"` carrying `backstop_revision`, `resolved_from`, `repaired` appended to `.claude/.memory-backstop.jsonl` on every SessionStart event
  cadence: per SessionStart (startup|resume|clear|compact)
  alert_target: operator-visible `systemMessage` on any non-applied outcome (edge-triggered, existing channel)
  configured_in: .claude/hooks/memory-backstop.sh (`_log`, `emit_message`) + .claude/hooks/memory-backstop-resolve.sh
error_reporting:
  destination: `.claude/.memory-backstop.jsonl` (per-checkout ledger) + `systemMessage` stdout channel
  fail_loud: `outcome:"failed"` lines with `reason` (`adoption_unverified`, `scope_caps_unverified`, `fleet_caps_unverified`) emit operator-visible banners — unchanged contract, extended to record `resolved_from` so a stale-copy run is attributable
failure_modes:
  - mode: stale checkout lacks the shim entirely
    detection: ledger lines missing `backstop_revision`/`resolved_from` (schema:1 shape) — the issue's own evidence shape, now explicit
    alert_route: sibling sessions' `repair_stale_scopes` converges the scope caps; ledger `repaired>0` on the repairing session's ledger
  - mode: managed/plugin copy poisoned (truncated, bad marker)
    detection: `bash -n` demotion + `resolved_from` falling back to checkout in the ledger
    alert_route: ledger `resolved_from` divergence visible; resolver emits systemMessage only on total failure
  - mode: publish failure (unwritable XDG dir)
    detection: managed copy revision stays behind checkout revision across runs (`resolved_from` never leaves checkout)
    alert_route: ledger field divergence; non-fatal by design
  - mode: revision not bumped on a hook change
    detection: `scripts/check-backstop-revision.sh` fails in pr-quality-guards
    alert_route: required-PR-check failure
logs:
  where: `.claude/.memory-backstop.jsonl` per checkout
  retention: rotated by `lib/log-rotation.sh` (existing)
discoverability_test:
  command: bash .claude/hooks/memory-backstop-resolve.sh --print-resolution
  expected_output: resolved=
```

## Guard Contract

### Guard 1 — revision bump on hook change

**Property.** Every PR that changes `.claude/hooks/memory-backstop.sh` also changes its `BACKSTOP_REVISION=` line — an un-bumped behavioral change must be undeliverable to the resolver's ordering.

**Assembly.** The single chokepoint is the PR diff: `git diff --name-only <merge-base>...HEAD` contains the hook path **iff** the hook changed, and `git diff <merge-base>...HEAD -- <hook>` carries the `BACKSTOP_REVISION` line iff the marker moved. `scripts/check-backstop-revision.sh` implements it; `pr-quality-guards.yml` invokes it unconditionally (the script self-skips with an explicit `NO-OP` line when the hook is untouched — no path filter, so a deleted filter can never darken it).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Hook body edited, `BACKSTOP_REVISION` line untouched | RED |
| 2 | `BACKSTOP_REVISION` re-set to the same value (no-op edit of the line) | RED |
| 3 | Hook untouched entirely | PASS (must-PASS, non-canonical input: guard declines by design) |
| 4 | Hook edited AND revision bumped | PASS (canonical compliant input) |
| 5 | Check script deleted/renamed while the workflow step still references it | RED (dispatch row — `bash scripts/check-backstop-revision.sh` on a missing path exits non-zero) |

### Guard 2 — vendored-copy parity

**Property.** `plugins/soleur/hooks/memory-backstop.sh` is byte-identical to `.claude/hooks/memory-backstop.sh` — the plugin payload can never drift from the source it claims to ship.

**Assembly.** Exactly two files, compared byte-for-byte by `plugins/soleur/test/backstop-parity.test.ts` at every test run — the drift chokepoint is the file pair itself; there is no third write site (the vendored copy is never generated, only copied).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | One-byte edit to the vendored copy only | RED |
| 2 | Vendored copy deleted | RED (zero-member row — file absence must fail, not vacuously pass) |
| 3 | Both copies edited together to a new consistent state | PASS (must-PASS differing from canonical: proves the guard admits legitimate change) |
| 4 | Marker line stripped from BOTH copies | RED (the `BACKSTOP_REVISION` presence assertion, independent of byte-equality) |

### Guard 3 — settings wiring

**Property.** `.claude/settings.json`'s SessionStart hook for the backstop names `memory-backstop-resolve.sh`, never `memory-backstop.sh` directly — a rewiring to bypass the resolver is a test failure.

**Assembly.** The one JSON entry in the one registry that binds the backstop (verified: `.devin/config.json` and `.codex/config.toml` do not bind it). Asserted in `backstop-parity.test.ts` by parsing the settings JSON, not grepping the file text.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Command reverted to `memory-backstop.sh` | RED |
| 2 | SessionStart entry for the backstop deleted entirely | RED (absence is a violation, not a vacuous pass) |
| 3 | A second, unrelated SessionStart hook added alongside | PASS (must-PASS differing in a permitted way) |

## Architecture Decision (ADR/C4)

### ADR

New **ADR-261** (provisional ordinal — next free after ADR-256..260 on `origin/main`; `adr-ordinals` re-verification at ship time may renumber it, and on renumber all `ADR-261` tokens in this plan/tasks sweep together) — "Version-independent hook resolution via managed-path newest-copy selection." Decision record: dispatch boundary moves from checkout-pinned to newest-installed; revision marker is the ordering key; self-publish converges the host on one fresh session; checkout copy remains the plugin-less fallback; `repair_stale_scopes` applies ADR-159's reconcile-the-units proposition to transient scopes. Alternatives to record: systemd --user timer sweeper (rejected — coverage indistinguishable from sweep-repair for any host with session activity, at the cost of persistent lifecycle infra), per-hook copy in every new checkout only (status quo — the defect), sourcing candidates for version (rejected — executes unverified code, ADR-156).

### C4 views

Task: update the `hooks` (Hook Engine) container description in `knowledge-base/engineering/architecture/diagrams/model.c4` (~line 129, already documents ADR-161 adoption) to record that the SessionStart backstop dispatch is version-independent — repo-local `settings.json` execs a resolver that selects the newest installed copy across the checkout, the managed path `~/.local/share/soleur/hooks/`, and the two plugin caches. No new element or edge: the completeness enumeration checked (a) external human actors — none new (founder/operator already modeled, `founder -> systemdUser` edge exists); (b) external systems/vendors — `systemdUser` already models the per-user manager; the managed path is a host-local file directory of the same class as the existing ledgers, not a modeled system; (c) containers/data-stores — the vendored plugin copy is already inside the modeled `platform.plugin` container's shipped payload; (d) access relationships — none change (`hooks -> systemdUser` edge semantics unchanged). If during implementation the description update reads awkwardly without a node, add a `soleurManagedHooks` element tagged host-local with an edge `hooks -> soleurManagedHooks "selects newest hook copy (BACKSTOP_REVISION)"` — implementer's call, description update is the minimum. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing.

### Sequencing

ADR-261 is authored in this PR in `accepted` state — the decision is true on merge; no staged slice.

## Files to Create

- `.claude/hooks/memory-backstop-resolve.sh` — the resolver shim (M1)
- `.claude/hooks/memory-backstop-resolve.test.sh` — resolver suite (fixture candidates, ordering, publish, fallback, never-blocks)
- `plugins/soleur/hooks/memory-backstop.sh` — vendored byte-equal payload copy (M3)
- `plugins/soleur/test/backstop-parity.test.ts` — Guards 2+3
- `scripts/check-backstop-revision.sh` — Guard 1
- `knowledge-base/engineering/architecture/decisions/ADR-261-version-independent-hook-resolution.md` — via `soleur:architecture`

## Files to Edit

- `.claude/settings.json` — SessionStart command → resolver (one-line change)
- `.claude/hooks/memory-backstop.sh` — `BACKSTOP_REVISION` marker, `repair_stale_scopes` + call inside the flock, ledger schema:2 fields (`backstop_revision`, `resolved_from`, `repaired`)
- `.claude/hooks/memory-backstop.test.sh` — new arms: pin `_repo_root`'s existing `CLAUDE_PROJECT_DIR` preference under a fake managed-dir exec, ledger schema:2 fields, `repair_stale_scopes` fixture + live arms
- `.claude/hooks/memory-backstop-mutation-battery.sh` — mutants: strip `BACKSTOP_REVISION` (resolver must demote to rev 0), drop `TasksMax` from the repair call (repair-verify arm must redden)
- `.claude/hooks/README.md` — resolution order, managed path, ledger schema:2 field docs, revision-bump contract
- `.github/workflows/pr-quality-guards.yml` — step invoking `check-backstop-revision.sh`
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — regenerate for the vendored copy
- `knowledge-base/engineering/architecture/diagrams/model.c4` — hooks container description update
- `knowledge-base/engineering/architecture/diagrams/views.c4` — only if the optional `soleurManagedHooks` element is added

## Implementation Phases

### Phase 1: Failing tests first (cq-write-failing-tests-before)

- 1.1 Write `.claude/hooks/memory-backstop-resolve.test.sh`: fixture candidate dirs under `TMPDIR` (managed/plugin/checkout layouts), revision parsing incl. absent/non-numeric marker → 0, precedence + tie-break, `bash -n` demotion, atomic publish (`tmp`+`mv`, mode 0755, `lib/log-rotation.sh` carried), never-sourcing assertion (`grep` the shim for `source`/`.` of candidate paths → none), never-blocks exit 0 on every fixture failure, `--print-resolution` shape.
- 1.2 Extend `.claude/hooks/memory-backstop.test.sh`: pin that `_repo_root` prefers `$CLAUDE_PROJECT_DIR` (fixture arm execs a copy staged at a fake managed path and asserts the ledger lands under the fake project dir); ledger line carries `schema:2`, `backstop_revision`, `resolved_from`, `repaired`; `repair_stale_scopes` fixture arm (stubbed `systemctl`/`busctl` on PATH in the suite's fixture sandbox — the suite's existing no-env-seam convention: the function takes its unit list or enumerator as an injectable *path/command argument*, never a magic env) asserting `SetUnitProperties` is called only on mismatched scopes and BindsTo is never written; live arm repairs a deliberately-miscapped `soleurtest-*` scope.
- 1.3 Write `plugins/soleur/test/backstop-parity.test.ts` (Guards 2+3 — RED until the vendored copy and rewiring land).
- 1.4 Extend `memory-backstop-mutation-battery.sh` with the two resolver-era mutants.

### Phase 2: Hook + resolver + payload

- 2.1 Add `BACKSTOP_REVISION=1` + header contract to `memory-backstop.sh`; `_repo_root` CLAUDE_PROJECT_DIR preference; `repair_stale_scopes`; ledger schema:2 fields.
- 2.2 Write `memory-backstop-resolve.sh` per M1.
- 2.3 `cp .claude/hooks/memory-backstop.sh plugins/soleur/hooks/memory-backstop.sh` + `chmod 0755`; regenerate `fixture-relative-assert.baseline.txt`.

### Phase 3: Wiring, guards, docs

- 3.1 `.claude/settings.json` → resolver command.
- 3.2 `scripts/check-backstop-revision.sh` + `pr-quality-guards.yml` step.
- 3.3 `.claude/hooks/README.md` updates.

### Phase 4: Decision record

- 4.1 ADR-261 via `soleur:architecture`; 4.2 `model.c4` (+ optional `views.c4`) update; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Acceptance Criteria

- [x] AC1: `.claude/settings.json` SessionStart invokes `memory-backstop-resolve.sh`; no registry binds `memory-backstop.sh` directly (asserted by Guard 3; verified `.devin`/`.codex` never did).
- [x] AC2: Given fixture candidates with revisions checkout=1, managed=3, resolver execs managed; managed=3 + plugin=5 → execs plugin copy; equal revisions → execs checkout; newest candidate failing `bash -n` → falls to next. All asserted in `memory-backstop-resolve.test.sh`.
- [x] AC3: Running the resolver when checkout revision > managed revision atomically installs checkout → `${XDG_DATA_HOME:-~/.local/share}/soleur/hooks/` (mode 0755, `lib/log-rotation.sh` carried when present) BEFORE exec; a second stale-checkout run resolves the managed copy.
- [x] AC4: `plugins/soleur/hooks/memory-backstop.sh` is byte-equal to the repo hook and unregistered in `hooks.json`; `backstop-parity.test.ts` enforces both.
- [x] AC5: `memory-backstop.sh` exec'd from a managed path writes `.claude/.memory-backstop.jsonl` under `$CLAUDE_PROJECT_DIR`, not under the managed dir — a fixture test pins `_repo_root`'s pre-existing env preference (`memory-backstop.sh:87`).
- [x] AC6: Ledger lines carry `schema:2`, `backstop_revision`, `resolved_from`, `repaired`; README documents the fields.
- [x] AC7: `repair_stale_scopes` issues `SetUnitProperties` (runtime) only on `soleur-agent-*.scope` units whose caps differ from current constants — never touches BindsTo — and a deliberately-miscapped `soleurtest-*` scope is repaired in the live arm.
- [x] AC8: `check-backstop-revision.sh` fails a synthetic diff that edits the hook without bumping `BACKSTOP_REVISION`, and the workflow step runs it (Guard 1 matrix green).
- [x] AC9: Resolver exits 0 on: no candidates beyond checkout, unreadable managed dir, unwritable publish target, absent `HOME` fallbacks — never blocks SessionStart.
- [x] AC10: `memory-backstop.test.sh` and `memory-backstop-mutation-battery.sh` stay green (existing arms preserved; `live_mark` placement for new live arms follows #8008's emission-vs-reachability guidance).
- [x] AC11: ADR-261 committed; `model.c4` description updated; c4 tests pass.
- [x] AC12: `bash -n` and the repo's shell-lint gates pass on the shim, and `bun test`/`test-all` plugin suites pass with the vendored file present (no component-census regression).

## Test Scenarios

- Given a checkout copy (rev 1) and a managed copy (rev 3), when SessionStart fires the resolver, then the managed copy execs and the ledger records `resolved_from` = managed path, `backstop_revision` = 3.
- Given a checkout rev 4 vs managed rev 1, when the resolver runs, then managed is atomically replaced with the rev-4 copy before exec, and the next run from a rev-1 checkout resolves managed (rev 4).
- Given the plugin cache contains rev 9, when the resolver runs from a rev-4 checkout, then the plugin copy wins and is published to the managed path.
- Given the newest candidate is truncated mid-write, when `bash -n` fails, then the resolver falls to the next candidate and still exits 0.
- Given no `systemd` user bus (CI/macOS), when the resolved hook runs, then it exits 0 with `reason:"no_bus"` — unchanged.
- Given a scope adopted with `TasksMax=37984` (stale), when any session fires SessionStart under the new hook, then that scope's TasksMax/Memory caps are corrected in place and `repaired>=1` is logged.
- Given a PR edits `memory-backstop.sh` without touching `BACKSTOP_REVISION`, when `check-backstop-revision.sh` runs, then it exits non-zero naming the missing bump.
- Given a session in a plugin-less checkout with no managed copy, when SessionStart fires, then the checkout copy runs — plugin-less development path preserved (P4).

## Success Metrics

- Post-merge ledger lines on this host show `resolved_from` = managed or plugin path for stale-branch sessions — the failure shape in the issue's evidence (missing `scope_tasks`/`swept`) becomes impossible to express silently because `backstop_revision` is always present.
- Zero `pids.max` saturation recurrences attributable to stale-adopted scopes; any scope created with old caps is repaired at the next SessionStart on the host (`repaired` count observable).
- `claude plugin update` demonstrably changes which hook copy executes for a plugin-cached install (plugin cache candidate resolves).

## Dependencies & Risks

- **Shim cannot self-upgrade.** A stale checkout keeps its stale resolver; only the *hook* it selects is version-independent. Accepted: the resolver contract (candidate set + revision ordering + publish) is deliberately tiny and stable; ADR-261 records this limit.
- **`BACKSTOP_REVISION` is human discipline.** Guard 1 makes a missing bump a CI failure; a bumped-but-wrong ordering is impossible to produce silently (integer compare).
- **Plugin-cache glob fragility.** If the cache layout changes, the glob matches nothing and the managed/checkout paths still resolve — degrade, not failure. A plugin installed from a *local-path* marketplace source (`.claude-plugin/marketplace.json` pointing at `./plugins/soleur`) may not appear under `plugins/cache` at all; the managed path covers that shape, so the glob is supplementary, never load-bearing.
- **Precedent base for the shim's primitives** (Phase 4.4 precedent-diff): the `flock -w N -x 9` serialize-with-timeout idiom is already the repo's pattern (`agent-token-tee.sh:179`; the hook itself cites it at `:85`); atomic tmp+`mv` publish matches `scripts/lib/scratch-root.sh`/`scripts/ensure-doppler.sh` conventions. The shim adds no novel pattern.
- **Managed-path trust.** Same-uid writable, same class as the checkout copy — no new privilege boundary; recorded in the ADR.
- **Repair blast radius.** `repair_stale_scopes` writes runtime caps to `soleur-agent-*.scope` units only — the units this system owns; it never touches foreign units (guard: name filter) and never writes persistent config (busctl `SetUnitProperties ... true`).

### Sharp Edges

- Never `source`/`eval` a candidate — grep the marker only (ADR-156 posture).
- Portability (the shim runs on every host a checkout runs on, incl. macOS): binaries used are `bash`, `grep -oE` (BSD-safe), `mkdir -p`, `install -m` (BSD-safe for file→file), `mv`, `flock` (Linux-only — `command -v`-guarded publish lock). No `timeout`, `sed -i`, `readlink -f`, `stat -c`.
- `exec bash <path>`, not direct exec — mode-bit immunity (#7151).
- Publish before exec; publish is `tmp`+`mv`+`install -m 0755` — a half-written managed copy must never exist (#8288-class cleanup-window lesson: the write window, not the failure arms, is the property).
- Never `set-property` without runtime scope — persistent mutation of the operator's systemd config is the thing this hook is designed never to do.
- Never re-derive BindsTo in the repair path — that is the kill-switch destruction the re-entry comment documents.
- New `readonly` constants belong beside the existing block (:69-80); `MAX_REPAIR` follows `MAX_SWEEP`'s bound-and-continue convention.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — Task spawn unavailable in this pipeline subagent context; assessment performed by the planning orchestrator against the CTO assessment question)
**Assessment:** The change is architectural in the dispatch sense (a new resolution boundary over hook copies) but narrow in blast radius: repo-local SessionStart machinery, never-blocks contract preserved, all candidates same-uid trust class. The architectural decision is recorded per the ADR gate. Main devex risk: `BACKSTOP_REVISION` discipline — mitigated by Guard 1. Devex benefit: local hook edits continue to take effect via checkout-preferred tie-break.

## References & Research

- Issue: #9239; the protection that isn't reaching stale checkouts: #9230, #9231; backstop origin: #7166 (ADR-161); prior unmerged attempt: #7151.
- `.claude/hooks/memory-backstop.sh` — cap constants :69-80, `_repo_root` :86, `sweep_unadopted_agents` :301 (skips `soleur-agent-*.scope`), `main` :447, re-entry refresh ~:715, exec guard :942.
- `.claude/settings.json` SessionStart block; `.claude/hooks/devin-dispositions.tsv`:111 (backstop is dispatch-true/functionally-void under Devin); `.codex/config.toml` binds rules-loader only.
- `plugins/soleur/hooks/` inventory (no backstop); cache layouts verified live under `~/.claude/plugins/cache/` and `~/.local/share/devin/cli/plugins/cache/`.
- ADR-156 (hook input untrusted), ADR-159 (delivery ≠ activation → reconcile units), ADR-161 (backstop design), ADR-178 (plugin ships executable primitives — precedent for the vendored payload), ADR-179 (plugin-root resolution by identity — precedent for the glob candidates).
- `scripts/plugin-legacy-resolver-probe.sh` — existing plugin-resolution probe precedent.
- Open scope-outs touching these files: #7208 (acknowledged), #8008 (acknowledged).
