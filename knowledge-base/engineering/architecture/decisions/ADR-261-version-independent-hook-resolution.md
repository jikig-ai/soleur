---
title: "ADR-261: Version-independent hook resolution via managed-path newest-copy selection"
status: Accepted
date: 2026-09-29
supersedes: []
amends: []
issue: 9239
related: [7166, 9230, 9231]
related_adrs: [ADR-161, ADR-159, ADR-156, ADR-178]
tags: [hooks, session-start, systemd, delivery-channel, memory-backstop]
brand_survival_threshold: none
---

# ADR-261: Version-independent hook resolution via managed-path newest-copy selection

## Status

Accepted — 2026-09-29. Delivers the decision record for #9239.

## Context

`.claude/settings.json` invoked `"$CLAUDE_PROJECT_DIR"/.claude/hooks/memory-backstop.sh`
— whichever copy the session's checkout or worktree happens to carry. A merged
protection upgrade therefore only reached sessions launched from a checkout
containing it. On 2026-09-29 this produced a third herdr crash: the TasksMax +
multi-agent adoption fix (the two merged PRs the issue cites) was already on
`main`, yet sessions resumed into the fresh herdr ran the **stale hook from an
older checked-out branch**, were adopted with default `TasksMax=37984`, and a
detached `gh api` storm inside an unadopted pane re-saturated the terminal
scope's `pids.max` at 22:53:47. The ledger evidence was five `schema:1`
adoptions at 20:54:21Z missing the `scope_tasks`/`swept` fields the new hook
emits.

Two further defects composed the same failure:

- **Plugin updates could not deliver the hook at all.** The plugin shipped no
  `memory-backstop.sh`, so the operator's remediation action
  (`plugin update`) was a no-op — the plugin cache was not on the hook's exec
  path.
- **Stale-adopted scopes were never repaired.** `sweep_unadopted_agents` skips
  `soleur-agent-*.scope` members by construction, so a session adopted under
  old caps kept them until its own next SessionStart — and a running session
  fires SessionStart only on `startup|resume|clear|compact`.

ADR-159's proposition — delivery is not activation — names the general shape:
a channel that delivers protection must also reconcile the units it protects.

## Decision

The dispatch boundary moves from checkout-pinned to **newest-installed**:

1. **A stable resolver shim becomes the settings.json entry point.**
   `.claude/settings.json` binds `bash
   "$CLAUDE_PROJECT_DIR"/.claude/hooks/memory-backstop-resolve.sh` — a thin
   (~120-line), rarely-changing shim invoked through `bash` for mode-bit
   immunity (the #7151 EACCES defect). The shim is the one component that
   cannot self-upgrade — a stale checkout keeps its stale resolver — so its
   contract is deliberately minimal and stable: a fixed candidate set and a
   revision ordering.
2. **`BACKSTOP_REVISION` is the ordering key.** The hook carries a
   `readonly BACKSTOP_REVISION=<n>` marker beside its cap constants, bumped on
   every behavioral change. The resolver reads candidates' markers by **grep,
   never `source`** — sourcing a candidate to learn its version would execute
   unverified code in the resolver (ADR-156's untrusted-input posture applied
   to hook bodies).
3. **Candidate precedence:** the checkout copy, then the managed path
   `${XDG_DATA_HOME:-$HOME/.local/share}/soleur/hooks/`, then both plugin
   caches (`~/.claude/plugins/cache/*/…`, `~/.local/share/devin/cli/plugins/cache/*/…`).
   Highest revision wins; ties prefer the checkout copy so an in-progress
   local edit is never silently overridden.
4. **Self-publish converges the host on one fresh session.** When the winner
   is strictly newer than the managed copy, the resolver atomically installs
   it (`install -m 0755` to a tmp sibling, then `mv`; `flock`-serialized with
   an in-lock revision re-check for the TOCTOU window) **before** exec — a
   hook that crashes still leaves the upgrade installed.
5. **`repair_stale_scopes` reconciles the units** (ADR-159 applied): inside
   the existing apply flock, any `soleur-agent-*.scope` whose runtime caps
   differ from current constants receives a runtime-only
   `SetUnitProperties` — bounded (`MAX_REPAIR=32`), per-scope non-fatal, and
   never touching `BindsTo` (the kill-switch preservation the re-entry branch
   documents). Any new-version SessionStart on the host converges every
   stale-adopted scope, no restart required.
6. **The ledger becomes the evidence channel.** Schema `1` → `2` adds
   `backstop_revision`, `resolved_from`, and `repaired`, so "a stale copy
   ran" is a recorded fact rather than an inference from missing fields — the
   exact evidence shape the issue used.
7. **The plugin ships the payload.** `plugins/soleur/hooks/memory-backstop.sh`
   is a byte-equal vendored copy (pinned by a parity test; deliberately not
   registered in `hooks.json` — payload only, the backstop stays
   repo-scoped), making `plugin update` an independent delivery channel for
   hosts whose checkouts are all stale.
8. **Guard 1 makes the discipline mechanical.** `scripts/check-backstop-revision.sh`
   (wired into `pr-quality-guards.yml`, self-skipping with an explicit `NO-OP`
   verdict when the hook is untouched) fails any PR that edits the hook
   without changing its `BACKSTOP_REVISION=` line.

## Alternatives considered

| Alternative | Why not |
|---|---|
| **Per-checkout copy only (status quo)** | The defect itself: protection upgrades reach only checkouts containing them, and every stale worktree would need a rebase per upgrade. |
| **`systemd --user` path-unit/timer sweeper** | Coverage is indistinguishable from `repair_stale_scopes` on any host with session activity (10–14 worktrees fire SessionStart constantly), at the cost of persistent lifecycle infrastructure — an install step that cannot ship by merging a PR, the same disqualifier ADR-161 recorded for static unit files. |
| **Advisory "outdated protection" message** | The issue offered it as the *alternative* to the sweeper. With the resolver, the running hook is already the newest installed copy at event time; with sweep-repair, the stale-caps harm is corrected regardless of which version adopted the session. The residual signal is carried by the ledger's `resolved_from`/`backstop_revision` fields. |
| **`source` the candidate to read its version** | Executes unverified code inside the resolver (ADR-156 posture). A `grep`-able marker carries the same information with no evaluation. |
| **Managed path under `~/.config/devin/`** | Config dirs are for configuration, not executable payloads; `${XDG_DATA_HOME}/soleur/` is the data-directory convention and harness-agnostic (the hook serves Claude, Devin and Codex sessions alike). |

## Consequences

- A merged protection upgrade reaches sessions regardless of checkout
  freshness, without rebasing worktrees — the third herdr crash's mechanism is
  closed. One fresh session upgrades the whole host via self-publish.
- `plugin update` stops being a no-op for this control; the plugin caches are
  resolution candidates and the vendored copy is parity-pinned.
- A scope adopted under stale caps is brought to current caps at the next
  SessionStart of *any* session on the host — the upgrade-lag window shrinks
  from "until each session restarts" to "until any session starts."
- **Bootstrap limit, stated plainly:** checkouts predating this change still
  run their old `settings.json` → old hook; nothing can reach their hook
  *code*. Their *caps* are repaired by sweep-repair the next time any session
  fires SessionStart, and the branch ages out on rebase.
- Equal-revision divergence is a deliberate dev-flow choice: tie-break prefers
  the checkout, so a same-revision local edit runs where it was made and stays
  invisible elsewhere until the author bumps the revision — which Guard 1 then
  forces at PR time.
- New trust surface: `${XDG_DATA_HOME}/soleur/hooks/` is same-uid writable —
  the identical trust class as the checkout copy today. A planted newer
  revision confers no privilege the planter did not already have.

## Verification

- `.claude/hooks/memory-backstop-resolve.test.sh` — fixture candidates,
  revision parsing (absent/non-numeric → 0), precedence + tie-break,
  `bash -n` demotion, atomic publish, never-sourcing assertion, never-blocks
  exit 0, `--print-resolution`.
- `.claude/hooks/memory-backstop.test.sh` — new arms pin `_repo_root`'s
  `CLAUDE_PROJECT_DIR` preference under a managed-path exec, the `schema:2`
  ledger fields, and `repair_stale_scopes` (fixture + live `soleurtest`-class
  scope repair).
- `plugins/soleur/test/backstop-parity.test.ts` — vendored-copy byte parity,
  marker presence, settings wiring (Guards 2–3).
- `scripts/check-backstop-revision.sh` + `pr-quality-guards.yml` — Guard 1.
- `.claude/hooks/memory-backstop-mutation-battery.sh` — two resolver-era
  mutants (strip `BACKSTOP_REVISION`; drop `TasksMax` from the repair call).
