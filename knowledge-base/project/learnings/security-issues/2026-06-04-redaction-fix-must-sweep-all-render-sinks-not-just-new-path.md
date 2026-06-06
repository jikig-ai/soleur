# Learning: a credential-redaction fix must sweep EVERY sink that renders the raw value — not just the new path

## Problem

A leak-fix PR (`feat-one-shot-concierge-stream-commands-hide-approval-cards`) was created
because a Bash command containing an installation token (`curl … ghs_…`) rendered verbatim
in a Concierge approval card (screenshot). The plan correctly identified
`permission-callback.ts:459-460` — where `review_gate` builds `preview = command.slice(0,200)`
raw — as "the screenshot leak's exact origin."

But the implementation added redaction ONLY on the **new** `command_stream` streaming path
(autonomous posture) and left `permission-callback.ts` **untouched**. The `review_gate` question
(and the `notifyOfflineUser` sink that reuses the same `question` string) still shipped the raw
token-bearing command — and `review_gate` is the DEFAULT, fail-closed (`bashAutonomous=false`)
posture, i.e. the majority path and the literal screenshot scenario. tsc + the full unit suite
were green; the new path's own redaction tests passed. The gap was invisible to every
implementation-side check.

`user-impact-reviewer` (fired because the plan declared `Brand-survival threshold: single-user
incident`) caught it by enumerating leak vectors per user-role and noticing the plan ASSERTED a
fix to `:459` that the diff never made.

## Solution

Redact at the `question`/`preview` construction site so BOTH consumers (`sendToClient` review_gate
+ `notifyOfflineUser`) inherit the redacted form from one fix:

```ts
import { redactCommandForDisplay } from "@/lib/safety/redaction-allowlist";
const redactedCommand = redactCommandForDisplay(command);
const preview = redactedCommand.length > 200 ? `${redactedCommand.slice(0,200)}…` : redactedCommand;
```

(The fix function already existed and was imported elsewhere — the leak was purely a missed call site.)

## Key Insight

When a PR fixes a credential/PII leak by adding a redaction/scrub on path A, the bug's ACTUAL
observed leak site is frequently a DIFFERENT, pre-existing sink B that renders the same raw value.
"Add redaction to the new feature" ≠ "fix the leak." Before declaring a redaction fix done, run a
**render-sink sweep**: `git grep` every site that places the untrusted value (`command`, `output`,
`token`, the offending variable) onto a wire / into a notification / into a persisted row, and
confirm each is gated. This is the display-time analogue of `hr-write-boundary-sentinel-sweep-all-write-sites`
(which sweeps all DB write sites for a tenant-integrity sentinel) — here the boundary is
"value reaches a user-visible or external sink," and the sentinel is the redactor.

Corollary for planners: if the plan names a specific file:line as "the leak origin," an Acceptance
Criterion MUST assert that exact line is redacted — not just that the new path is. The diff silently
not touching the cited origin is the tell.

## Prevention

- **Review-spawn prompt** for any leak/redaction PR: instruct the security/user-impact agent to
  enumerate EVERY sink rendering the offending value and confirm each is redacted — explicitly
  including pre-existing paths the diff does not touch.
- **Plan AC**: when the plan cites a concrete `file:line` leak origin, add an AC that greps that
  exact site for the redactor call.
- Redaction lives at the value-construction site (so all downstream consumers inherit it), not
  per-consumer.

## Session Errors

- **Implementation redacted only the new path, missed the cited legacy sink (`permission-callback.ts:459`).**
  Recovery: `user-impact-reviewer` flagged it; redacted at the `question` construction site, covering
  both the review_gate and offline-notify sinks. Prevention: render-sink sweep before declaring a
  redaction fix complete (this learning); route-to-definition bullet added to the review defect-classes.
- **Task tool unavailable in the planning subagent env** — domain/plan-review fan-out ran inline.
  Recovery: assessments authored inline + re-run as agents at review. Prevention: known environmental
  constraint; already documented.
- **Pencil Desktop AppImage crashed (headless)** — Recovery: fell back to Pencil CLI with Doppler
  `PENCIL_CLI_KEY`. Prevention: known; CLI fallback is the documented path.

## Tags
category: security-issues
module: apps/web-platform/server/permission-callback.ts, lib/safety/redaction-allowlist.ts
related: [[2026-05-12-type-widening-cascades-and-write-boundary-sentinels]]
