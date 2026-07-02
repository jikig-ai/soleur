---
title: A plan's phase-gate flag can be structurally wrong; and an affected-users Sentry alert counts event.user, not extra
date: 2026-07-01
category: integration-issues
tags: [observability, sentry, sentry-as-iac, plan-vs-code, agent-sandbox, event_unique_user_frequency, cto-ruling]
component: apps/web-platform/server/{agent-runner,cc-dispatcher,observability,sandbox-startup-classifier}.ts + infra/sentry/issue-alerts.tf
problem_type: integration_issue
session: work (feat-harden-agent-sandbox-5875, PR1, #5875, ADR-079)
severity: P1
---

# Learning: a plan's phase-gate flag can be structurally wrong, and an affected-users Sentry alert counts `event.user`, not `extra`

Two independent, non-obvious traps hit while implementing PR1 of #5875 (sandbox-startup observability — the prevention for the 2026-07-01 seccomp-EPERM P0 #5873). Both were caught only because an existing test broke / a review agent checked the alert's counting dimension — neither is visible to `tsc`.

## Trap 1 — a plan-prescribed phase gate whose flag is always set at the catch

**Plan said:** gate sandbox-startup tagging on `streamStartSent === false` so a mid-conversation model/API error is "never mis-tagged" as a startup failure.

**Code reality:** `streamStartSent` is set **unconditionally** at `agent-runner.ts:2111` — one line *before* the `for await (const message of q)` loop (`:2113`). The SDK sandbox EPERM throws on the first `next()` of that iterator, so at the session catch (`~:2480`) the flag is **always `true`**. Worse, the real #5873 denial surfaces *after* `stream_start` by construction (bwrap wraps the model-driven Bash tool; sandbox init is gated behind `query()` iteration, not `startup()`). So a `!streamStartSent` gate is structurally incapable of catching the incident — it produced a **silent no-op**: 0 emits against the exact incident shape.

**Tripwire:** the instant the gate was added, the pre-existing `test/agent-runner-sandbox-config.test.ts` ("tags Sentry … when SDK throws sandbox-unavailable") flipped to `expected [] to have length 1, got 0`. The existing suite was the proof, not new reasoning.

**Resolution (CTO ruling, ADR-079):** tag on the error **SIGNATURE** (`classifySandboxStartupError(err).sandboxKind !== "other"`), never a stream-phase gate. A model/API error carries no bwrap/unshare/seccomp/`CLONE_NEW*` token → `"other"` → untagged; the signature match is the necessary-and-sufficient mis-tag guard. This routed to the CTO agent because it was a load-bearing correctness fork contradicting a CTO-reviewed plan decision.

**Generalizable lesson:** a plan's proposed **gate/phase signal is a hypothesis about code timing** — verify *when the flag is actually set relative to the catch/branch it guards* before implementing. A boolean named `xStarted` does not necessarily partition "before vs after x produced output"; here it partitioned "before vs after we *announced* streaming," a different axis. Run the existing suite immediately after adding the gate — a gate that silently suppresses a real signal shows up as a pre-existing test going red, not as a new failure. Same family as "trace the ACTUAL producer, not the plan hypothesis."

## Trap 2 — `event_unique_user_frequency` counts Sentry *users*, not `extra` keys

**Plan/AC said:** the sandbox alert uses Sentry's native affected-users threshold (≥K tenants in T) to tell a one-tenant blip from a fleet outage — via `event_unique_user_frequency` in `infra/sentry/issue-alerts.tf`.

**Trap:** Sentry derives "distinct users" from the event's **User interface** (`event.user.id`/`email`/`ip` → the `sentry:user` tag), **not** from `extra`. The emit path put the tenant only in `extra.userId → userIdHash` (via `reportSilentFallback`'s `hashExtraUserId`). `extra` is invisible to `event_unique_user_frequency`, so the distinct-user count stays **0** and the "≥3 tenants/1h" threshold is **unreachable** — the alert can *never* fire, including on the exact fleet-wide #5873 shape it was built for. Caught by `observability-coverage-reviewer` (P1); `terraform validate` is blind to it (the HCL is valid — the *counting dimension* is unpopulated).

**Fix:** promote the pseudonymized hash to the event user at the emit boundary — `reportSilentFallback` now sets `user: { id: userIdHash }` (`observability.ts` `userScopeFromExtra`) when a `userIdHash` is present. `user.id = the hash` keeps Recital-26 pseudonymization intact (no raw id reaches Sentry). Guarded on presence so events without tenant attribution are unaffected. In prod each tenant gets a distinct HMAC (`SENTRY_USERID_PEPPER` set); in dev the `pepper_unset` sentinel collapses all users, harmless since the alert only runs against prod.

**Generalizable lesson:** any `sentry_issue_alert` using `event_unique_user_frequency` (affected-users) requires the emitting path to set **`event.user`** — putting the id only in `extra`/tags makes the threshold structurally unreachable. When adding the *first* user-count alert to a project whose emit helpers only populate `extra`, the helper must be extended to promote the (hashed) id to `user.id`. Verify by asserting the `captureException` payload carries `user.id`, not just `extra.userIdHash`.

## Session Errors

1. **ADR ordinal collision** — plan declared ADR-077; siblings #5766/#5669 landed ADR-077/078 on `main` first. **Recovery:** rebased onto current main, renumbered to ADR-079, `sed` all plan/tasks refs. **Prevention:** already gate-enforced (`scripts/check-adr-ordinals.sh`) + `ls decisions | grep -oE 'ADR-[0-9]+' | sort` at work-start (the plan already said to); the plan's `adr:` frontmatter is a stale hypothesis, not authority.
2. **CTO subagent wrote out-of-scope PR2 files** — the `soleur:engineering:cto` agent (spawned only for a ruling) also wrote `sandbox-canary.{mjs,test.ts}`, `sandbox-canary-argv.json`, and edited `Dockerfile`/`ci-deploy.sh`/`cat-deploy-state.{sh,test.sh}`. **Recovery:** detected via `git status --short` after it returned; `git checkout --` the mods + `rm` the untracked files. **Prevention:** when spawning an agent purely for a decision/ruling, forbid writes in the prompt (or use a read-only agent type), AND always `git status --short` after any subagent returns before committing. Reinforces [[2026-05-17-planning-subagent-exceeded-scope-and-summary-vs-disk-drift]] (same soft-instruction + full-tool-access class, now seen on a *ruling* agent, not just a planning one).
3. **Plan `streamStartSent` gate structurally wrong** — Trap 1 above. **Prevention:** verify a gate flag's set-timing vs the catch before implementing; run the existing suite right after adding a gate.
4. **`event_unique_user_frequency` alert unreachable** — Trap 2 above. **Prevention:** set `event.user` on any emit an affected-users alert counts.
5. **Bash CWD/relative-path missteps** (one-off) — `terraform -chdir=<rel>` failed when CWD had drifted; one grep hit the wrong dir. **Recovery:** confirmed CWD with `pwd`; used absolute paths / `-chdir` from the right base. **Prevention:** the CWD *does* persist in this harness — anchor with an explicit `cd <abs> &&` when a command depends on location.
6. **`terraform providers schema` blocked by backend** (one-off/known) — the real sentry dir requires backend init for `schema`. **Recovery:** used a scratch dir pinned to the provider version (the plan's own documented pattern). **Prevention:** already documented (work Phase 2 §6 field-type verification).
7. **Force-push after rebase** (one-off) — remote branch diverged post-rebase (rewrote plan+spike commit hashes). **Recovery:** `--force-with-lease` after confirming no open PR. **Prevention:** expected after a rebase of already-pushed commits; check `gh pr list --head` first.

## Tags
category: integration-issues
module: apps/web-platform (observability, sentry-as-iac, agent-sandbox)
