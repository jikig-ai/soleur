---
title: "ADR-219: Soleur Cloud Mode — sentinel-based surface detection and the honest-degradation contract"
status: Proposed
date: 2026-09-14
supersedes: []
amends: []
tags: [devin, cloud, plugin, detection, degradation, hooks, subagents]
---

# ADR-219: Soleur Cloud Mode — sentinel-based surface detection and the honest-degradation contract

## Status

Proposed — 2026-09-14. Provisional ordinal; re-derived against `origin/*` at merge
time. Implements #8159. Merge-readiness is frozen on the Phase 0 empirical cloud
probe (#8172) or an explicit recorded deferral — this ADR records the *design*
as implemented for Phases 1–3; matrix rows, FR4 mechanism, and FR5 scope may be
revised by measured probe data.

## Context

Soleur runs on the Devin harness in two substrates with different enforcement
surfaces. Locally (CLI/Desktop) the full plugin surface exists: skills, plugin
`AGENTS.md` rules, MCP, plugin subagents (`agents/**/*.md` via `run_subagent`),
and plugin hooks. In a Devin Cloud session (Cognition-managed VM) the
documented surface is narrower: skills and plugin `AGENTS.md` rules load, MCP
loads (auth via the web-app connection), plugin subagents are local-only, and
plugin `SessionStart`/`SessionEnd` hooks never fire. Plugin `command` hooks are
documented cloud-capable for other events, but per-matcher binding
(`hooks.json` registers `matcher: "Bash"` while Devin's shell tool is `exec`)
is unverified; repo-level `.devin/config.json` hooks are undocumented.

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
   permanent false-cloud). The write is ordered after the `additionalContext`
   JSON emit and failure-isolated with `|| true`, so a write failure can never
   kill context injection. `plugins/soleur/scripts/cloud-detect.sh` is the
   ONE classifier: `local` only when the sentinel exists, `host` matches
   `hostname` (same invocation on write and compare sides), and
   `hook_source` is `plugin`; every other outcome emits
   `not-local:<reason>` (`no-devin-env | sentinel-absent | malformed |
   foreign-host | non-plugin-source`) and consumers fail closed. No `jq`
   dependency; a `not-local` result is never a usage error (exit 0).
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
   (`emit-review-trailer.sh --mode`); `/ship` blocks that coverage value on
   `single-user incident` plans unless the operator explicitly acknowledges —
   interactive sessions get a structured ask, headless sessions abort.
   (c) A session-scoped acknowledgement gate before secrets reads or
   production mutation — conversation context only, never a persisted ack
   file (a stale file replays into a new session); if the session is
   unattended and no answer is obtainable, the step defers or aborts.
4. **The contract lives on guaranteed-load surfaces only.** The canonical
   text is `devin/INSTRUCTIONS.md` §Cloud Mode + a `[id:]`-tagged rules
   section in `plugins/soleur/AGENTS.md` — the two surfaces documented to
   load in cloud. Each of the 59 grep-derived union-set SKILL.md files
   (spawn-sites ∪ secrets/prod ∪ pipeline skills) carries one composite
   `<!-- soleur-cloud-mode:start/end -->` pointer block — a single marker per
   skill, grep-verifiable, no per-skill detection logic.
5. **One structural guardrail is restored skill-side; the rest are disclosed
   absent.** `plugins/soleur/scripts/precommit-guard.sh` (self-contained, no
   vendored `.claude/hooks/lib` — those paths resolve relative to the repo and
   land in the plugin install cache when vendored, ADR-178) refuses
   commit-on-main/master including chained commands, invoked directly by
   work/ship/one-shot; `.claude/hooks/guardrails.sh` delegates its
   commit-on-main block to it (plugin = canonical source, repo reaches in,
   with the inline check retained as an unreachable-plugin fallback). The
   DONE-marker stop-gate is deliberately NOT extracted — it reads hook-stdin
   transcript data a standalone script cannot see. All other repo guardrails
   (prod-write-defer-gate, worktree-write-guard, secret-scan, freeze-lock, …)
   are enumerated as *not restored* in the capability matrix.
6. **`requiredPlugins` is added to `.devin/config.json`** so cloud sessions on
   this repo install the plugin from the cloned repository; unknown-key
   tolerance verified locally (`devin doctor` parses clean). Cloud install
   behavior is a Phase 0 probe item.
7. **The empirical probe is an operator-gated Phase 0, not a verification
   tail.** Probe results freeze the FR4 ack mechanism (does
   `ask_user_question` auto-approve, stall, or return distinguishable
   unanswered in unattended sessions), the FR5 extraction scope (which
   repo-level guardrails already fire in cloud), capability-matrix rows, and
   Art. 30 wording. A GDPR pre-probe credential determination precedes the
   session; any Jikigai limb escalates to CLO first (D10 pre-emptive).

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
- **Probe debt:** FR4 mechanism, FR5 scope beyond commit-on-main, matrix rows,
  and Art. 30 wording are measured-data decisions parked on #8172. If the probe
  shows plugin `command` hooks fully working in cloud, FR5's remaining
  extraction narrows; if repo hooks fire in cloud, `hook_source` already keeps
  detection correct either way — the design is stable under both outcomes.
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
  #8162 (full-parity posture), #8172 (operator-gated probe).
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
