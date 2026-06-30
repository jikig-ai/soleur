# Learning: A recurring symptom that survives a fix means the fix is in the wrong LAYER — prove the code path executes on the affected surface (Sentry/logs) before shipping

## Problem

The operator's Concierge `/soleur:go` kept stranding on `fatal: not a git repository`. Over one session I shipped **two** fixes to the workspace-clone **cc-dispatcher** path:
- #5716 — warm-dispatch await for an *absent* `.git`.
- #5584 — validity-not-presence for a *corrupt* `.git`.

Both were real, reviewed, merged, and deployed. **The operator still hit the exact same failure after each.** I had diagnosed both from indirect evidence (DB rows + the debug-stream symptom) and code-reading — never confirming the code I was changing actually *runs* on the operator's surface.

## Solution

Only on the third report did I query **production Sentry** for the breadcrumbs my fixes emit (`repo_resolver_divergence`, `corrupt-worktree-at-dispatch`, `reprovision-on-dispatch`, `ensure-workspace-repo`): **zero events in 24h**, while `Server startup v0.162.0` proved the deploy was live. That zero was decisive — the cc-dispatcher self-heal **never executes on the operator's surface**. The operator's containerized agent (`/workspaces/<id>` + `/opt/soleur/plugin`) has its workspace managed by **Inngest** functions, and the one *proven* to fire on the affected workspace was `workspace-reconcile-on-push` (26× on `754ee124`). Its readiness gated on directory *existence*, not `.git` validity, and `workspace-sync` only pulls/resets — never re-clones. That was the real fix site (#5730).

## Key Insight

**When a production symptom recurs after a fix, suspect the LAYER, not just the logic.** A merged-and-deployed fix that doesn't change the symptom is evidence the changed code isn't on the failing path. Before shipping a fix for a *recurring* production symptom, **prove the targeted code executes on the affected surface using production observability** — search Sentry/logs for the breadcrumbs/log lines the path emits (or that the *fix itself* will emit). **Zero events from the path you're "fixing" = wrong layer; stop and re-trace which code actually runs.** Code-reading establishes that a path *could* be wrong; only runtime evidence establishes which path *is* exercised. This is the runtime-evidence companion to "trace the ACTUAL producer" — and the cheapest version (one Sentry search) would have caught the misdiagnosis before the *first* ship, not the third. Corollary: a PIR's root cause is only as good as the layer evidence behind it — #5716's PIR mis-attributed the cause because it was written from the symptom, not from runtime signal.

## Session Errors

- **Shipped two fixes (#5716, #5584) to a layer that emits zero events on the operator's surface.** Recovery: a Sentry breadcrumb search revealed the wrong layer; re-traced to the Inngest reconcile path (#5730). **Prevention:** for a recurring production symptom, before `/ship`, run a Sentry/log search confirming the path you changed actually fires on the affected entity (the fix's own observability is the verification) — zero events ⇒ wrong layer.
- **#5716 PIR mis-attributed the operator's root cause** (warm-race vs the actual corrupt-`.git` validity gap). Recovery: accurate PIR in #5584 + a correction note on #5716's. **Prevention:** anchor a PIR's root cause on runtime evidence (which function fired, per Sentry), not on the symptom shape.
- **`subagent_type:"fork"` no-op'd a delegated implementation** (0 tool uses, confabulated a result). Recovery: re-launched as `general-purpose`; verified commits exist before trusting. **Prevention:** prefer `general-purpose` for multi-step implementation; verify a delegated agent produced the expected commits/files before trusting its summary. (Also captured in [[2026-06-29-recurring-failure-root-cause-is-residual-bad-data-not-patched-code]].)
- **Nearly ran a destructive de-dup on a stale issue premise** (#5591 said "same repo"; live data showed different repos). Recovery: pulled live prod before mutating. **Prevention:** re-verify a tracking issue's premise against live state before any destructive remediation.
- (one-off) `psql` not installed → used Supabase REST; guessed `owner_id` column → `select=*` to learn the schema; a plan-phase infra-gate false-positive on "operator-driven" phrasing → reworded.

## Tags
category: bug-fixes
module: web-platform/workspace-provisioning
related: "[[2026-06-29-recurring-failure-root-cause-is-residual-bad-data-not-patched-code]]"
issues: "#5730 #5716 #5584 #5591"
