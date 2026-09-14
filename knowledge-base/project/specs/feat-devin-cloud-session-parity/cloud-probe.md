# Devin Cloud Probe — feat-devin-cloud-session-parity

**Status:** PENDING — operator-gated (plan Phase 0, TR7). Requires an
operator-credentialed Devin Cloud session (`/handoff` or web app) on this
repository. Implementers cannot run it; cloud sessions may be access-limited.

Part of #8159. Tracked by #8172. Plan:
`knowledge-base/project/plans/2026-09-14-feat-devin-cloud-session-parity-plan.md`
§Phase 0.

## Pre-probe credential determination (GDPR gate — REQUIRED FIRST)

Record before the session runs. If ANY limb is Jikigai's, escalate to CLO
*before* probing — D10 is pre-emptive, not post-hoc.

| Limb | Owner | Notes |
|---|---|---|
| Devin account (whose login runs the session) | _unrecorded_ | |
| Billing entity (whose seat/subscription) | _unrecorded_ | Jikigai seat → CLO escalation |
| API keys reachable in-session (`ANTHROPIC_API_KEY`, Doppler creds, `GH_TOKEN`) | _unrecorded_ | Jikigai-issued key → CLO escalation |

**Implementer-side partial observation (local session, 2026-09-14):** this
Devin CLI session's process env carries zero `DOPPLER`/`ANTHROPIC_API_KEY`/
`GH_TOKEN`/`GITHUB_TOKEN` variables. This says nothing about the cloud VM's
reachable creds or the account's billing entity — the operator must complete
the table.

## Art. 30 determination

The probe satisfies the register's purpose limb (Jikigai engineering purpose,
PA-35 precedent). Record ONE of:

- [ ] New PA-37 register entry (appended, per register convention)
- [ ] Written out-of-scope determination (record reasoning here)

## DPIA-screening note

One paragraph required: systematic description of the processing, necessity,
risk to third-party data subjects in repo content (git authorship, committed
digests), compensating measures. The probe must capture **non-identifying
environment signals only** — no personal data, no credential values, no
operator-identifying output beyond what git history already carries.

## Probe session scope

- One `/handoff` or web-app Devin Cloud session on this repo.
- Operator-credentialed test scope only.
- No personal data. No production mutations. Read-only probes + marker files.

## Checklist (record each item with evidence)

1. **Repo-level `SessionStart` hook** — does a `.devin/config.json`
   SessionStart hook fire in cloud? (Plugin SessionStart is
   documented-absent; repo-level is the unknown.) Evidence: marker file
   written by a test repo hook.
2. **Repo-level `PostToolUse`/`Stop` hooks** — same test with marker files.
3. **`ask_user_question` in an unattended cloud session** — auto-approve
   (fail-open), stall, or distinguishable unanswered/timeout? **Freezes the
   FR4 ack mechanism.**
4. **Per-hook, per-matcher binding** — `hooks.json` registers
   `matcher: "Bash"`; Devin's shell tool is `exec`. Verify each registered
   plugin hook individually — a matcher that never matches is a silent no-op.
5. **`requiredPlugins`** — does `.devin/config.json` `requiredPlugins`
   install the plugin in a fresh-repo cloud session? Does an unknown key
   break local hook registration? **Freezes FR6 placement.**
6. **`/handoff` worktree sync** — does handoff carry gitignored `.devin/`
   files to the cloud VM? (Determines whether a local sentinel can arrive
   foreign.)
7. **`run_subagent` built-in profiles** — do `subagent_explore`/
   `subagent_general` exist and produce artifacts? Artifact output, not
   invocation success (Cloud Routines lesson).
8. **`DEVIN*` env signals** — which markers exist in cloud and propagate to
   `exec` tool shells? Session-id env var available in exec context (banner
   session-boundary oracle)?
9. **Exec-shell propagation** — do env markers reach `exec` subshells?
10. **Session ID availability** — env var or otherwise reachable.
11. **`.claude/settings.json` hooks** — do repo-level Claude-format hooks
    fire?
12. **`PostCompaction` hooks** — documented cloud-capable; confirm. A
    PostCompaction hook re-emitting cloud-mode context would structurally
    solve banner loss + ack re-priming (requires spec NG5 revision —
    escalate, don't inherit).
13. **Plugin command hooks** — confirm actual execution (docs say yes —
    verify, don't assume).
14. **`hook_source`** — record `hook_source` from any sentinel written;
    distinguishes repo-config vs plugin registration.
15. **Unknown-key tolerance** — `.devin/config.json` parse behavior with
    `requiredPlugins` present, locally (can verify pre-merge without cloud).

## What the probe freezes

- **FR4** acknowledgement mechanism (interactive ask vs. hard-defer).
- **FR5** extraction scope (which guardrails actually need skill-internal
  restoration).
- **Capability-matrix rows** (Phase 4 — every row cites a doc anchor or a
  probe result).
- **Art. 30 amendment wording** (probe-informed keying by where each measure
  executes).
- **Banner session-boundary mechanism** (env oracle vs. stateless
  per-invocation).

## Deferral record

_If deferred:_ record the deferral issue number and the merge-readiness
consequence here (Phase 3 extraction scope, Phase 4 matrix rows, Phase 5
Art. 30 wording, and PR-ready status are all frozen on this file's
completion — `wg-block-pr-ready-on-undeferred-operator-steps`).
