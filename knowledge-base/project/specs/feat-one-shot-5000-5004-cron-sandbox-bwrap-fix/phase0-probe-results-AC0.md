# Phase 0 Gating Probe Results (AC0) — v2 plan premise FALSIFIED

**Date:** 2026-06-08 (resume after Warp crash)
**CLI under test:** `claude` 2.1.168 (plan assumed 2.1.142)
**Probe method:** real `claude --print --settings <tmp> --allowedTools 'Bash(echo SOLEUR_ALLOWED_OK:*),Glob,Grep'` issuing one allowlisted command + several non-allowlisted commands; observed actual execution vs denial. Auth via local session credentials (no ANTHROPIC_API_KEY needed; nested `claude --print` works).

## Verdict: D0a FAIL · D0b FAIL · D0c PASS → Tier-1 design (L1 allowlist primary) is NOT shippable as written.

### D0a — does any `defaultMode` make `--allowedTools` fail-CLOSED in headless `--print`? **NO.**

| defaultMode | `echo` (allowed) | `uname -a` (not allowlisted) | `cat /proc/self/environ` | `curl` (in `deny`) |
|---|---|---|---|---|
| `dontAsk`  | ok | **RAN** ❌ | **RAN — env leaked** ❌ | DENIED ✓ |
| `default`  | ok | **RAN** ❌ | **RAN — env leaked** ❌ | DENIED ✓ |
| `auto`     | ok | **RAN** ❌ | **RAN — env leaked** ❌ | (not tested; curl deny consistent) |

**Finding:** In headless `claude --print` with `sandbox.enabled:false`, the permission system is **deny-list-driven, not allow-list-driven**. `--allowedTools` + `defaultMode` do NOT fail-close non-listed Bash commands — they execute. Only explicit `permissions.deny` rules block. This is exactly the premise the plan's AC0 said to verify, and it is false for all three modes. The plan's escalation clause fires: *"If neither fail-closes in `--print`, escalate (the Tier-1 fix is not shippable as designed)."*

### D0b — does `Read(/proc/**)` deny stop `cat /proc/self/environ`? **NO.**

`cat /proc/self/environ` ran and leaked the full environment under a settings file containing `"deny": ["Read(/proc/**)", "Read(/proc/*/environ)"]`. The `Read(...)` deny governs the **Read tool**, not a `cat` invocation through the **Bash** tool. The plan's L2 ("Read(/proc/**) deny overrides the always-on read-only bash set") is invalid against 2.1.168.

### D0c — can a `PreToolUse` hook deny a Bash command by content? **YES.**

A `PreToolUse` `matcher:"Bash"` hook returning `{"hookSpecificOutput":{"permissionDecision":"deny",...}}` for commands matching `/proc/|/environ|printenv|curl|...` produced:

| command | result |
|---|---|
| `echo SOLEUR_ALLOWED_OK` | ok |
| `cat /proc/self/environ` | **DENIED by hook** ✓ |
| `printenv` | **DENIED by hook** ✓ |

## Implication for the design

The plan's load-bearing control was L1 (per-producer `--allowedTools` allowlist, fail-closed). That control **does not exist** in headless `--print`. The only empirically-working controls are:

1. **`permissions.deny` rules** — best-effort blocklist (the plan already documented this as best-effort).
2. **A `PreToolUse` hook** — the ONLY mechanism that can implement a true **deny-by-default allowlist** (the hook sees every `tool_input.command` and can deny anything not matching a per-cron allow pattern + the read-only safe set).

**Viable redesign (needs re-plan + security review before implementation):** promote the L3 hook from "backstop" to **primary fail-closed control** — a deny-by-default PreToolUse hook enforcing the per-cron allowlist itself, plus the secret/egress/interpreter denials. `--allowedTools` stays for documentation but is NOT relied upon. `sandbox:false` retained (the host-independence bug fix). This inverts the plan's L1/L3 roles.

**Status:** ESCALATED to operator. Not proceeding to Phase 1 (RED) until the hook-primary redesign is reviewed — shipping an on-the-spot security redesign without the 5-agent panel the v2 plan received would repeat the v1 unverified-premise failure.

---

## v3.1 re-probe against the PROD-PINNED CLI (P0-D — 2026-06-08)

The probes above ran on `claude` 2.1.168; `Dockerfile:45` pins `@anthropic-ai/claude-code@2.1.79`. The architecture-strategist panel flagged the version skew (P0-D). Re-ran the load-bearing v3.1 mechanics against 2.1.79 (installed to `/tmp/claude279`):

| Probe (2.1.79) | Result | Confirms |
|---|---|---|
| Bash deny-by-default (allowlist) | `echo`(allowlisted)=ok; `cat /proc/self/environ`(not)=DENIED | hook is fail-closed allowlist on 79 |
| **Read tool** matcher on secret path | `Read(.git/config-shaped)`=DENIED | P0-A fix mechanism (Read matcher) works on 79 |
| **Grep tool** matcher on secret path | `Grep(token, fake-git-config)`=DENIED | P0-A fix mechanism (Grep matcher) works on 79 |
| D-new-1 (missing hook) | `uname`=ran (fail-OPEN) | spawn-time self-test still required on 79 |
| Unhooked tool (only Bash matcher; Read available) | `Read(secretfile)`=read (NOT denied) | catch-all + explicit Read/Grep/Glob matchers required on 79 |

**P0-D RESOLVED:** the v3.1 design (tool-class deny-by-default hook + catch-all + spawn-time self-test) is validated against the production-pinned 2.1.79. No Dockerfile bump required.
