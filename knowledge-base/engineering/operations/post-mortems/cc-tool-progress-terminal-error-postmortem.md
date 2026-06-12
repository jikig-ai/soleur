---
title: "Concierge cc surface flips chat bubble to terminal error on >90s single tool (tool_progress not forwarded)"
date: 2026-06-12
incident_pr: "#5223"
incident_window: "Latent since the cc/soleur-go surface shipped without tool_progress client-forwarding; user-reachability raised by PR #5208 (server idle-watchdog re-arm). No discrete outage window — defect identified in review, not via a production alert."
recovery_at: "On merge of #5223 (2026-06-12)."
suspected_change: "cc-dispatcher.ts delegates the SDK stream to soleur-go-runner.ts, whose tool_progress branch was a pure server-watchdog re-arm that emitted no client event. PR #5208 kept the server stream alive longer, raising how often the >90s path reaches the client's second-timeout terminal logic."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - "Surfaced during PR #5208 review by user-impact-reviewer; deferred as review-origin scope-out #5214 with re-eval by 2026-07-12."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data confidentiality/availability breach; this is a UI-correctness defect on the conversation surface (no data exposure, loss, or unauthorized access)."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

On the Concierge (cc / `soleur-go`) chat surface, the server did not forward SDK `tool_progress` heartbeats to the client. The client-side stuck-watchdog (`STUCK_TIMEOUT_MS`, 45s) was therefore not heartbeat-fed during a long single-tool execution. On a >90s single tool (routine `Read`/`Bash`/web-search on large input) the client timed out twice and drove the chat bubble to a terminal `error` state, evicting the leader from `activeStreams`; the eventual real answer then rendered as a new bubble appended below the orphaned error bubble — the user saw "the agent failed" immediately followed by the answer.

The defect was a latent residual identified in PR #5208's review (user-impact-reviewer) and deferred as scope-out #5214 — it was never reported as a live production incident, but it is reachable on routine traffic on the product's core conversation surface, so it meets the operator's "any detected incident gets a post-mortem" standing rule.

## Status

resolved — fixed in the source PR (#5223) before reaching a user-reported failure.

## Symptom

A >90s single-tool Concierge turn paints a terminal "the agent failed" error bubble, immediately followed by the correct answer rendered as a separate orphaned bubble below it.

## Incident Timeline

- **Start time (detected):** 2026-06-11 (PR #5208 review, user-impact-reviewer flagged the residual)
- **End time (recovered):** 2026-06-12 (merge of #5223)
- **Duration (MTTR):** ~1 day from detection-in-review to fix (no live-outage clock — defect never fired a production alert).

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-06-11 | PR #5208 review (user-impact-reviewer) surfaces the client-side 45s-watchdog residual on the cc surface; filed as deferred-scope-out #5214. |
| agent | 2026-06-12 | Root-caused via 2-file code trace: cc-dispatcher delegates to soleur-go-runner whose tool_progress branch is a pure re-arm (no client emit). |
| agent | 2026-06-12 | Two-layer fix implemented (runner emits onToolProgress; cc-dispatcher forwards debounced) and merged via #5223. |

## Participants and Systems Involved

Concierge (cc / `soleur-go`) chat surface: `apps/web-platform/server/cc-dispatcher.ts`, `apps/web-platform/server/soleur-go-runner.ts`, `apps/web-platform/server/tool-labels.ts`, and the client reducer `apps/web-platform/lib/chat-state-machine.ts` (consumer — unchanged). Driven autonomously by Claude Code (`agent`).

## Detection (+ MTTD)

- **How detected:** code review (PR #5208 user-impact-reviewer), NOT a monitoring alert or external user report. The defect is silent to Sentry — it manifests only as a transient UI bubble-state flip.
- **MTTD (mean time to detect):** the residual existed since the cc surface shipped without tool_progress forwarding; it was detected the first time a reviewer enumerated the >90s-single-tool failure mode against the cc surface (PR #5208).

## Triggered by

system — an architectural gap (the cc runner consumed `tool_progress` for a server-side re-arm only and never emitted a client event), with reachability amplified by an upstream fix (PR #5208's server idle-watchdog re-arm keeping the stream alive longer).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| cc-dispatcher never forwards tool_progress; the runner swallows it | `git grep tool_progress cc-dispatcher.ts` returned zero forward sites; runner branch comment said "reads NO fields (a pure re-arm)" | none | confirmed |
| The issue's prescribed "one-line forward at cc-dispatcher.ts:2107" would fix it | — | cc-dispatcher wires DispatchEvents callbacks; it does not iterate SDK messages — a lone sendToClient line would have nothing to call | rejected (two-layer fix required) |

## Resolution

Two-layer fix mirroring the legacy `agent-runner.ts:1889-1948` forward, split across the runner/dispatcher seam: the runner emits a shape-guarded `onToolProgress` DispatchEvent (after the existing `armRunaway` re-arm); `cc-dispatcher.ts` forwards it via `buildToolProgressWSMessage` (routing the raw tool name through `buildToolLabel`, #2138) debounced 5s per `toolUseId`. The client consumer, `tool_progress` WS variant, and zod schema already existed for the agent-runner surface and were reused unchanged.

## Recovery verification

7 new tests green (4 server: runner emit, dispatcher WS-shape, debounce clock-drive, shape-guard + positive-control; 3 client consumer-contract guards) + full `apps/web-platform` vitest suite green (9681 passed) + `tsc --noEmit` clean. Control test #7 proves a genuinely hung tool (no heartbeat) STILL flips to terminal error after two timeouts — genuine-failure detection is preserved, not relaxed.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the bubble flip to terminal error? The client watchdog timed out twice on a >90s tool. → 2. Why did it time out? It received no heartbeat to reset `STUCK_TIMEOUT_MS`. → 3. Why no heartbeat? The cc surface never forwarded SDK `tool_progress` to the client. → 4. Why not? The cc runner's `tool_progress` branch was a pure server-side watchdog re-arm that read no fields and emitted no DispatchEvent, and cc-dispatcher had no `onToolProgress` wiring. → 5. Why was this only now reachable? PR #5208's server idle-watchdog re-arm kept the stream alive past the point where the server previously tore it down, so the >90s path now reaches the client's second-timeout terminal logic more often (the residual code was unchanged; its user-reachability rose).

## Versions of Components

- **Version(s) that triggered the outage:** every cc-surface build since the surface shipped without tool_progress forwarding (reachability amplified post-PR #5208).
- **Version(s) that restored the service:** the release cut from #5223.

## Impact details

### Services Impacted

The Concierge (cc / `soleur-go`) conversation surface only. No data, auth, billing, or infra surface touched.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface.

- Prospect: none.
- Authenticated app user: on a >90s single-tool Concierge turn, a spurious terminal "the agent failed" bubble appears, immediately followed by the real answer as a separate orphaned bubble — confusing but non-destructive (the answer is delivered; no data is lost).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

None beyond the engineering time to fix.

## Lessons Learned

### Where we got lucky

The residual was caught by a reviewer (user-impact-reviewer) enumerating the >90s failure mode during an adjacent PR (#5208), before a user filed a confused "the agent failed but then answered" report.

### What went well

The fix reused an already-complete client contract (the `tool_progress` WS variant + reducer shipped for agent-runner under #2861), so the change was confined to the server forward path with no client-side risk; AC10 git-diff-gated `chat-state-machine.ts`/`ws-constants.ts` as unchanged.

### What went wrong

The cc surface mirrored the agent-runner *consumer* contract but never wired the *producer* — a feature-wiring composition gap where the runner consumed `tool_progress` for one purpose (server re-arm) and silently dropped its client-facing half.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur (save logs, add tests, set up alerts, automation, documentation, code sweeps, PRs).

_No action items — incident fully resolved in the source PR with no residual work._
