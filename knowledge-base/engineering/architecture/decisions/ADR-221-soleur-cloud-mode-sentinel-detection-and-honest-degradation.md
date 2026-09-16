---
title: "ADR-221: Soleur Cloud Mode — sentinel-based surface detection and the honest-degradation contract"
status: Proposed
date: 2026-09-14
supersedes: []
amends: []
tags: [devin, cloud, plugin, detection, degradation, hooks, subagents]
---

# ADR-221: Soleur Cloud Mode — sentinel-based surface detection and the honest-degradation contract

## Status

Proposed — 2026-09-14; probe-measured 2026-09-15. Provisional ordinal;
re-derived against `origin/*` at merge time. Implements #8159. The Phase 0
probe ran on two arms (DRS sandbox `devin-b9cf2c02cc8f49debdbc49ed72cdf2b5`;
user-facing web-app session, absorbed from PR #8196) — matrix rows, FR4
mechanism, and FR5 scope are now measured, not provisional. Residual
verification (user-facing re-check, clean-account `requiredPlugins`, `/handoff`
`.devin/` sync, post-merge SC1/SC3/SC4) tracks on #8172.

## Context

Soleur runs on the Devin harness in two substrates with different enforcement
surfaces. Locally (CLI/Desktop) the full plugin surface exists: skills, plugin
`AGENTS.md` rules, MCP, plugin subagents (`agents/**/*.md` via `run_subagent`),
and plugin hooks. In a Devin Cloud session (Cognition-managed VM) the measured
surface is narrower — and narrower than the documentation suggested: skills and
plugin `AGENTS.md` rules load, MCP loads (auth via the web-app connection),
plugin subagents are local-only (`run_subagent` exists in the web-app tool
catalog but plugin `agents/**` do not load), and **no hook class fires on any
registration surface** — plugin `hooks.json`, repo `.devin/config.json`, and
`.claude/settings.json` were all probed inert, including a `matcher: ""`
catch-all. `ask_user_question` is absent; `message_user` blocks and stalls,
never auto-approves. The probe also caught a real defect: `hooks.json`
registered `matcher: "Bash"`, which never binds Devin's `exec` tool — the
credential guard was a silent no-op on every Devin surface including local
(fixed; the wider `.claude/settings.json` `"Bash"` matcher class is #8205).

The failure class this addresses is **silent degradation**: an operator runs
`/soleur:one-shot` or `/soleur:review` in a cloud session, the agent fan-out
and hook backstops never execute, and the deliverable is
downstream-indistinguishable from a fully-reviewed one (the
`2026-08-03-the-degraded-review-labelled-itself-and-i-still-nearly-shipped-on-it`
learning: prose self-disclosure never reaches a boolean gate — only the trailer
does). The posture chosen at brainstorm was *workflow-complete, gate-disclosed —
never capability-equivalent*.

Detection cannot sniff undocumented env markers, and an existence-only sentinel
fails three ways: `/handoff` copies the worktree to the cloud VM, a sentinel can
be committed in a user repo that does not gitignore `.devin/`, and — the severe
one found in plan-review — if repo-level SessionStart hooks fire in cloud, a
repo-sourced sentinel on the cloud host would read as local and disable every
safeguard.

## Decision

1. **Detection is a content-bearing sentinel plus one fail-closed classifier.**
   `devin-session-start.sh` writes `.devin/soleur-local-session` containing
   `{"host","ts","hook_source"}` unconditionally under Devin env (no
   `plugins/soleur/` scope guard — user repos consuming via `requiredPlugins`
   are the primary audience, and a scope guard inverts detection into
   permanent false-cloud). The write is atomic (tmp+`mv`), ordered BEFORE the
   `additionalContext` JSON emit so a `jq`-less host still leaves the sentinel,
   and failure-isolated with `|| true`. `plugins/soleur/scripts/cloud-detect.sh`
   is the ONE classifier, and it is **sentinel-first**: a valid sentinel alone
   means `local` because local Devin exec shells export *zero* `DEVIN*`
   variables (measured on this machine — the env gate the first draft led
   with made `local` unreachable). `local` requires the sentinel to exist,
   `host` to match `hostname`, and `hook_source` = `plugin`; every other
   outcome emits `not-local:<reason>` (`no-devin-env | sentinel-absent |
   malformed | foreign-host | non-plugin-source | conflicting-evidence`) and
   consumers fail closed. `no-devin-env` means *not a Devin session* — it
   proceeds normally and suppresses the banner; the cloud-only marker set
   (`DEVIN_DIR`, `DEVIN_DISABLE_HISTEXPAND`) distinguishes a Devin box from a
   Claude Code shell. `conflicting-evidence` closes the upstream-convergence
   hole: a valid plugin-sourced sentinel *plus* a cloud-only env marker means
   plugin hooks have started firing in cloud before subagents exist — fail
   closed, not open. No `jq` dependency; a `not-local` result is never a
   usage error (exit 0).
2. **Dual-registration ordering is pinned.** This repo registers
   `devin-session-start.sh` twice (plugin `hooks.json` and repo
   `.devin/config.json`), so the hook can fire twice locally with undefined
   order. A `repo`-sourced write must never mask an existing `plugin`-sourced
   sentinel on the same host — the plugin sentinel is proof-of-local, and
   masking it reads as permanent false-cloud on the primary development repo.
3. **Degradation is disclosed through three load-bearing surfaces.** (a) A
   capability banner (`--banner`, stderr, reason-aware) emitted on every
   `not-local` classification at pipeline start. (b) Sequential fallback:
   skills that fan out execute each role definition sequentially inline and
   mark deliverables/PR trailers `Reviewed-Coverage: sequential-fallback`
   (`emit-review-trailer.sh --mode` — the explicit mode survives count-based
   derivation, since N/N sequential roles are NOT `full` independent-agent
   coverage); `/ship` blocks that coverage value on `single-user incident`
   plans unless the operator explicitly acknowledges — interactive sessions
   get a structured ask (`message_user` in cloud; `ask_user_question` is
   absent there), headless sessions abort.
   (c) A session-scoped acknowledgement gate before secrets reads or
   production mutation — conversation context only, never a persisted ack
   file (a stale file replays into a new session); if the session is
   unattended and no answer is obtainable, the step defers or aborts.
4. **The contract lives on guaranteed-load surfaces only.** The canonical
   text is `devin/INSTRUCTIONS.md` §Cloud Mode + a `[id:]`-tagged rules
   section in `plugins/soleur/AGENTS.md` — the two surfaces documented to
   load in cloud. Each of the 64 union-set SKILL.md files (spawn-sites ∪
   secrets/prod ∪ pipeline skills) carries one composite
   `<!-- soleur-cloud-mode:start/end -->` pointer block, plus the 3
   `devin/skills/*` shims and `commands/go.md` — a single byte-identical
   marker per skill, drift-pinned in `devin-cloud-mode.test.ts`.
5. **One structural guardrail is restored skill-side; the rest are disclosed
   absent.** `plugins/soleur/scripts/precommit-guard.sh` (self-contained, no
   vendored `.claude/hooks/lib` — those paths resolve relative to the repo and
   land in the plugin install cache when vendored, ADR-178) refuses
   commit-on-main/master across chained/piped/env-prefixed/`-C`/`--git-dir`
   command shapes, invoked directly by work/ship/one-shot skill text and the
   marker block; `.claude/hooks/guardrails.sh` delegates its commit-on-main
   block to it (plugin = canonical source, repo reaches in, with the inline
   check retained as an unreachable-plugin fallback) and the `.openhands`
   port carries the same detection width + segment-scoped resolution inline.
   The DONE-marker stop-gate is deliberately NOT extracted — it reads
   hook-stdin transcript data a standalone script cannot see. All other repo
   guardrails (prod-write-defer-gate, worktree-write-guard, secret-scan,
   freeze-lock, …) are enumerated as *not restored* in the capability matrix.
6. **`requiredPlugins` is added to `.devin/config.json`** so cloud sessions on
   this repo install the plugin from the cloned repository; unknown-key
   tolerance verified locally (`devin doctor` parses clean) and the repo-level
   key is documented in plugins overview §Inheritance level 3. Its marginal
   effect is unmeasured — the org managed manifest already installs Soleur, so
   a clean-account arm stays on #8172.
7. **The empirical probe ran (two arms) — results are folded into the
   decisions above.** FR4 froze on the hard-defer `message_user` mechanism
   (it blocks and stalls; never auto-approves). FR5 is maximal scope: zero
   hook dispatch on any registration surface. A GDPR pre-probe credential
   determination preceded both sessions (all limbs personal — D10 not
   engaged); the residual user-facing verification set tracks on #8172.

## Consequences

- **A `not-local` classification is never silent.** Banner + trailer value +
  ship gate form the three-point disclosure: the session knows, the
  deliverable carries it, and the merge gate enforces it.
- **Guard Contract 1:** no Devin session classifies `local` without positive
  this-host, plugin-sourced evidence — pinned by
  `plugins/soleur/test/devin-cloud-mode.test.ts` (all reasons, both priority
  pairs, dual-registration ordering arms, the banner never-value).
- **Honest but not parity.** Cloud sessions are workflow-complete under the
  contract; they are never claimed capability-equivalent. `sequential-fallback`
  coverage on a `single-user incident` plan blocks `/ship` absent explicit
  acknowledgement.
- **Residual probe debt:** the two-arm probe measured the surfaces this design
  depends on; what remains on #8172 is confirmatory (user-facing re-check of
  the sandbox findings, a clean-account `requiredPlugins` arm, `/handoff`
  `.devin/` sync, post-merge SC1/SC3/SC4 verification). If upstream later ships
  plugin hooks in cloud before subagents (#8160's own sequence), the
  `conflicting-evidence` arm keeps detection fail-closed instead of reading
  the new sentinel writes as `local`.
- **Legal surface:** the cloud substrate is a third configuration (third-party
  machine + user credential + user purpose) the two-category taxonomy did not
  name; the disclosure floor (DPD corrections, fifth classification row) is
  non-negotiable and CLO sizes the ceiling.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Env-var detection (`DEVIN_CLOUD`-style marker) | No documented cloud marker exists; invented env sniffing fails the moment the platform changes. Sentinel = positive evidence, not heuristic. |
| Existence-only sentinel | Fails on `/handoff` worktree copies, committed sentinels in user repos, and repo-level SessionStart firing in cloud (the false-local hole `hook_source` closes). |
| TypeScript classifier in `harness.ts` | `harness.ts` functions are consumed only by tests; a second classifier would be split-brain — bash is the runtime surface skills invoke. |
| Persisted ack file for the secrets/prod gate | Replay-hole class — a stale ack satisfies a new session. Ack is session-scoped conversation state, re-asked after compaction. |
| Vendored `.claude/hooks/lib` in `precommit-guard.sh` | `BASH_SOURCE`-relative paths resolve to the plugin install cache, not the repo — a drift-prone fork. Self-contained instead. |
| Extracting the DONE-marker check | It reads hook-stdin transcript data; a script cannot interpose turn-end. Stays prose + plugin Stop hook where hooks run. |
| Verify-first on repo-config leverage (Approach B) | Doesn't help Soleur users' repos; hooks fail open. Folded into the Phase 0 probe. |
| Docs + upstream request only (Approach C) | Leaves undisclosed in-band degradation — the exact failure class this feature kills. |

## References

- #8159 (feature), #8155 (PR), #8160 (upstream request: plugin subagents +
  plugin hooks in cloud), #8161 (Jikigai-credentialed cloud sessions),
  #8162 (full-parity posture), #8172 (operator-gated probe — two arms landed),
  #8205 (the wider `.claude/settings.json` `"Bash"` matcher class — per-hook
  review, not a sweep).
- Plan: `knowledge-base/project/plans/2026-09-14-feat-devin-cloud-session-parity-plan.md`;
  spec: `knowledge-base/project/specs/feat-devin-cloud-session-parity/spec.md`;
  probe record: `knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md`.
- ADR-089 (repo-root gitignored runtime state), ADR-093 (never write the plugin
  root), ADR-178/179 (plugin-shipped bash primitives, bare-root anchors),
  ADR-215 (per-file Claude hook parity is not implied — Codex precedent).
- Learning:
  `2026-08-03-the-degraded-review-labelled-itself-and-i-still-nearly-shipped-on-it`;
  Cloud Routines incident
  `2026-04-21-cloud-routine-subagent-auth-inheritance-H6`.
