---
title: "ADR-213: Browser-snapshot credential guard, split across three controls"
status: accepted
date: 2026-09-09
issue: 7947
supersedes: []
tags: [security, credentials, browser-automation, hooks, adr]
---

# ADR-213: Browser-snapshot credential guard, split across three controls

## Status

Accepted — 2026-09-09. Closes #7947.

## Context

An accessibility snapshot serializes the **value** of input fields. A value the
acting agent never supplied — a browser password manager's autofill, a static
`value=` attribute, a JS assignment, or a freshly-minted credential displayed in
a panel — is therefore rendered into the agent transcript and into any snapshot
file the tooling writes to disk. Nothing about the call looks credential-adjacent:
the natural reason to snapshot a login page is to find out whether the flow
advanced.

This matters more for a Soleur operator than for us. A non-technical operator
running a browser-automation skill has no reason to suspect that "take a snapshot
of the page" means "print my password into the log".

### What was measured, before anything was built

Phase 0.1 of the implementation plan is a gate: nothing was written until both
surfaces were probed against a synthesized page. The full record, including the
raw serializations, is
[the Phase 0.1 measurement](../../../project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md).

| Node | `agent-browser` 0.22.3 | Playwright MCP | Screenshot |
|---|---|---|---|
| `type=password`, static `value=` | masked (bullets) | **leaks** | safe (dots) |
| `type=password`, JS-set | masked (bullets) | **leaks** | safe (dots) |
| `type=text` readonly, named "Token" | **leaks** | **leaks** | **leaks** |
| `type=email`, benign | rendered | rendered | rendered |

Three consequences drove every decision below, and each contradicts something the
issue or the plan asserted before measurement:

1. **Neither surface serializes `type=`.** A password box, a readonly token box
   and an email box all render as `textbox`. A *structural* "is this a password
   input" predicate has nothing to read, so the accessible **name** is the only
   available signal.
2. **`agent-browser` already masks `type=password`.** The single node it leaks is
   the readonly `type=text` credential panel — which is the class with a recorded
   in-repo incident
   ([2026-05-19 Sentry token scope probe divergence](../../../legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md)).
   A guard keyed on the word "password" would have missed the only thing that
   surface leaks.
3. **A screenshot is not the safe alternative it is assumed to be.** It is safe
   for `type=password`, and it renders a readonly `type=text` credential panel in
   clear, exactly as the snapshot does.

## Decision

Ship three controls with different reaches, and state what each does and does not
buy rather than implying a single solved property.

### 1. A redactor — defense-in-depth on one enumerated sink

[`redact-a11y-snapshot.py`](../../../../plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py)
rewrites credential-shaped node values to `<redacted>`. It ships inside the plugin
and runs on the customer's machine.

Its predicate is **name-based, not structural**, forced by measurement (1) above.
It also suppresses the nested `StaticText` child, because the no-flag and `-d N`
shapes emit the value twice, and it handles `--json` via `data.snapshot`.

It is defense-in-depth on one sink. It is **not** a control that makes
snapshotting a credential page safe, and the module header enumerates the
bypasses: a localised accessible name, a credential outside a text-input role, a
value split across segmented inputs, and the whole Playwright-MCP runtime path.

### 2. A PreToolUse interceptor — the control that does not depend on memory

[`browser-snapshot-credential-guard.sh`](../../../../plugins/soleur/hooks/browser-snapshot-credential-guard.sh)
denies a Bash-invoked `agent-browser snapshot` that is not routed through the
redactor, judging **per shell segment** so a chained command with one piped and
one unpiped invocation is caught.

Two placement decisions are load-bearing:

- **It lives in `plugins/soleur/hooks/`, not `.claude/hooks/`.**
  `${CLAUDE_PLUGIN_ROOT}` resolves into the installed plugin directory, so a hook
  under `.claude/` is repo-local and never reaches a customer. Placing it there
  would have shipped the operator prose and no enforcement — the exact failure the
  plan's own risk table named.
- **The disposition is deny, not rewrite.** ADR-162 permits exactly one PreToolUse
  rewriter and `grep-rewrite.sh` holds it; two hooks emitting `updatedInput` for
  one call have undefined precedence and one rewrite is silently discarded.

### 3. A corpus walker — regression teeth on what the plugin instructs

A second rule family inside
[`lint-credential-path-literals.py`](../../../../scripts/lint-credential-path-literals.py),
which already walks this population and already backs a required CI check, so the
rule is blocking from its first run.

Its population is deliberately **narrower** than the host walk: only
`plugins/soleur/{skills,agents}/`. The property is about what the shipped plugin
*instructs*, and a knowledge-base plan, spec or post-mortem is a *record*.
Measured, the unscoped walk produced 65 hits, 8 of them in this issue's own
evidence files — gating those would mean the only way to satisfy the guard is to
stop writing incidents down.

## Consequences

**P7 — "the guards hold without the acting agent having to remember them" — is
achieved on the `agent-browser` Bash path and is NOT achieved on the
Playwright-MCP runtime path.** That is the principal recorded consequence and it
is stated plainly because an unstated gap is the failure mode, not the gap itself.
On the MCP path the walker gates what the corpus *instructs* and never what an
agent *does*; the `.mcp.json` stdio proxy that would close it is deferred.

`@playwright/mcp`'s own `--secrets` option does not close it either: it masks
values named in advance, its README calls that "a convenience and not a security
feature", and it cannot reach a password the agent never supplied — which is
precisely this mechanism.

### Relationship to ADR-202

ADR-202 does not cleanly apply, and this record says so rather than force-fitting
it. For `bash -x` the carried refusal was `case "$-" in *x*)` — a state predicate,
complete by construction, carried by the artifact that would leak. #7947 has no
analogue: the artifact that leaks is a live browser page, which is not a member of
any committed population, and markdown prose is advisory. ADR-202's own
alternatives table already classifies the redactor-pipe shape as "defense-in-depth
on one enumerated sink, not a substitute for the carried refusal".

### Corrections this ADR records

- The issue's claim that a screenshot is safe holds only for `type=password`.
- The issue's framing of the mechanism is true of the Playwright MCP surface and
  false of `agent-browser`, which masks `type=password` already.
- Both `cf-token-scope` files shipped an **inverted** rule — "never call
  `browser_evaluate` with a `filename`" — in a credential-mint playbook. Without a
  `filename` the value is returned into the transcript; with one it is written to
  a file that can be shredded. Corrected in the same change.

## Alternatives considered

| Alternative | Property | Why not |
|---|---|---|
| A content-shaped secret detector over snapshot output | P5 | `redact-engine.py` (ADR-095) never rewrites in place, and an operator password carries no vendor prefix or format anchor — ADR-095 names prefix-agnostic entropy detection an explicit non-goal. |
| A PostToolUse hook that redacts snapshot output | P5, P7 | Structurally impossible: PostToolUse runs after the tool's write and cannot rewrite tool output (`.claude/hooks/README.md` §PostToolUse hooks). |
| A structural `type=password` predicate | P5 | Measured unimplementable — no surface serializes `type`. |
| Prose guidance in the browser skills alone | P7 | Fails this plan's own test: it holds only when the agent remembers, and the operator it protects cannot audit an accessibility tree. |
