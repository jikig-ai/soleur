---
title: "feat: Ship the proxy-wrapped Playwright MCP path by default so P7 holds on customer browser skills"
date: 2026-09-18
slug: feat-proxy-wrapped-playwright-mcp-default
branch: feat-one-shot-8156-8250-mcp-proxy-time-port
issue: 8156
closes: [8156]
type: security
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Overview

GitHub issue #8156 (type/security, p1-high, deferred from #7980). The plugin
ships `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`
— the stdio relay that closes ADR-213's Playwright-MCP residual — but registers
no Playwright server, so property P7 ("the guard holds without the acting agent
having to remember it") holds only on registrations an operator wired through
the proxy by hand. This plan makes the wrapped path the default on every
customer session without any `.mcp.json` edit, and reconciles the tool-prefix,
profile-lock, per-session `npx` cost, and cross-harness-manifest consequences
that motivated the deferral.

## Enhancement Summary

**Deepened on:** 2026-09-18
**Sections enhanced:** Proposed Solution (flag semantics), Research Insights
(loader/roster + upstream-issue corrections), Alternative Approaches (Option C),
Acceptance Criteria (AC3, AC7), Deferrals.
**Coverage:** `Reviewed-Coverage: sequential-fallback` — deepen-plan's
agent fan-out ran inline/sequential (no Task agents in this subagent context);
mechanical halts 4.6/4.7/4.8/4.10/4.11 all passed
(`lint-guard-contract.py`: 3 guard entries, green).

### Key Improvements
1. `--user-data-dir-name` resolution now mirrors `scripts/lib/scratch-root.sh`'s
   XDG semantics (the in-repo precedent): refuse on RELATIVE `XDG_CACHE_HOME`
   and on unresolvable `~` (HOME unset) — two edge cases the original spec
   silently misresolved.
2. Upstream verification (`gh api`, 2026-09-18): #36914 (stdio deferred-tools),
   #47859 (hook output discarded), #54161, #24788 are all CLOSED — the
   engines-floor probe now confirms rather than gambles, and Option C's
   deferral is scoped-coverage economics, not mechanism viability.
3. Corrected `session-rules-loader.sh` read-set claim (it reads repo
   `.mcp.json` ∪ `.claude-plugin/plugin.json` — `plugins/soleur/.mcp.json` is
   outside; harmless since `playwright` is already rostered and the field is
   display-only) and the `components.test.ts` clause-(c) key set
   (`commands`/`agents`/`workflows`).

### New Considerations Discovered
- `plugin-root-anchoring.test.ts` G2/G2b reject bare-basename gate-script
  invocations in SKILL.md fences → preference prose must name the SERVER, not
  the script path (folded into AC7).
- `codex-plugin.test.ts` deep-equality and `devin-plugin.test.ts`
  `.url`/`transport:"http"` loop verified by reading both files — the
  dedicated-`.mcp.json` decision rests on measured blast radius.
- Proxy refusal surface re-verified at source (`--port`, `--host`, `--caps`,
  `--output-mode`, `--config` existence + `server.*`/`saveSession`/`saveVideo`
  keys, `DEBUG`/`DEBUG_FILE`) — every "the proxy already refuses" claim in the
  plan resolves to a code line.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited artifact | Verified |
|---|---|
| #8156 OPEN, `type/security`, `priority/p1-high`, `deferred-scope-out`, milestone "Phase 4: Validate + Scale" | Holds (`gh issue view 8156`) |
| #7980 CLOSED ("P7 is not achieved on the Playwright-MCP path…") | Holds |
| `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py` | Exists; header documents the three fail-closed arms |
| `plugins/soleur/.claude-plugin/plugin.json` registers no Playwright server; all `mcpServers` HTTP | Holds — 4 HTTP entries (context7, cloudflare, vercel, stripe), no stdio |
| This repo's `.mcp.json` routes `playwright` through the proxy in front of `npx @playwright/mcp@0.0.78` | Holds, incl. the Linux-only `pkill`/`env -u WAYLAND_DISPLAY` prelude and `--user-data-dir=$HOME/.cache/playwright-mcp-profile` + `--config=.claude/playwright-mcp.config.json` |
| Issue's cited plan path `knowledge-base/project/plans/2026-09-14-feat-playwright-mcp-snapshot-redaction-proxy-plan.md` | MOVED — archived at `knowledge-base/project/plans/archive/20260914-230848-2026-09-14-feat-playwright-mcp-snapshot-redaction-proxy-plan.md`; content intact |
| `knowledge-base/project/learnings/workflow-patterns/2026-07-05-playwright-mcp-orphan-server-profile-lock-contention.md` | Exists — 15 orphaned `playwright-mcp` processes contended on ONE `--user-data-dir`; Chrome `SingletonLock` tears down the losing server's pages |
| "11 prefix lines across 5 skill files" (`mcp__playwright__`/`mcp__plugin_soleur_pw__`) | Drifted: now **13 lines across 5 files** — `agent-browser/SKILL.md` (3), `reproduce-bug/SKILL.md` (6), `cf-token-scope/references/widen-playbook.md` (1), `plan/SKILL.md` (1), `work/SKILL.md` (1). Zero `mcp__plugin_soleur_pw__` occurrences |
| `scripts/lint-credential-path-literals.py` S2 rule | Exists; `S2_CANONICAL` paragraph is whitespace-tolerantly DERIVED into `MCP_GAP_MARKER_RE` and carried verbatim (line-wrapped) in `qa`, `ux-audit`, `cf-token-scope/widen-playbook`, `agent-browser` |
| ADR-213 (`knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md`) | Exists; the 2026-09-14 addendum records reach (b) — "a customer's own registration … tracked at #8156" — and a **corrected premise with direct consequence for this issue**: PostToolUse CAN rewrite MCP tool output on Claude Code 2.1.270 (`updatedMCPToolOutput`), for the transcript sink only |

**Stale/none:** the only stale premise is the archived plan path (noted). No cited
issue is already-resolved; no mechanism this plan proposes sits in an ADR's
rejected-alternatives table (checked ADR corpus for plugin-registration and
hook-wrapping mechanisms — ADR-213's addendum explicitly carries reach (b) as
the open #8156 item, and ADR-162's one-PreToolUse-rewriter rule constrains only
Bash matchers, which this plan does not touch).

### Property List (Phase 0.6b)

1. A Playwright-MCP registration whose `tools/call` results are redacted in
   flight **exists by default** on every customer session — zero `.mcp.json`
   edits (the issue's product requirement).
2. The shipped skills' browser instructions resolve to the wrapped
   registration — P7 holds on the path the skills prescribe, not only on a
   registration the customer happened to wire.
3. A customer's own `playwright` registration (if any) keeps working and keeps
   its documented fallback (the `filename:` + redactor + shred form) — no
   regression, no tool-name collision.
4. The wrapped path closes the same sinks the proxy closes on the repo
   registration — transcript AND disk sinks (`--snapshot-mode none`, `filename`
   refusal, `_meta` refusal, startup sink refusals). A transcript-only control
   is not a substitute.
5. The wrapped server's browser profile does not contend on a profile lock
   with a customer's own registration (the orphan-server class).

### Cut List (Phase 0.6b)

| Mechanism named in the ask | Property it would buy | Disposition |
|---|---|---|
| Auto-wrap the user's existing `playwright` entry by rewriting their config | P1 on the user's own server | **Cut** — no plugin-manifest mechanism wraps an existing registration. The only implementable form is a SessionStart hook that edits customer-owned `.mcp.json`/`.claude.json` files, an unconsented mutation that additionally loads only after a full restart. Rejected outright. |
| Auto-wrap via plugin-shipped PostToolUse hook on `mcp__playwright__.*` (`updatedMCPToolOutput`) | P7-transcript on ANY customer registration named `playwright` | **Deferred, not cut** — buys transcript-only coverage (fails P4: the tool's own disk writes happen before the hook sees output, and a hook cannot append `--snapshot-mode none` to a launch it does not own). Kept as a complementary control with re-evaluation criteria (see Alternative Approaches); a deferral issue is a plan deliverable. |
| Pre-register `playwright` inline in `plugin.json` `mcpServers` | P1–P4 | **Reshaped** — inline forces the `.codex-plugin` deep-equality test (`codex.mcpServers` must equal canonical) and the `.devin-plugin` parity loop (reads `.url` on every canonical entry) to carry a stdio entry those harnesses cannot run. The dedicated `plugins/soleur/.mcp.json` at plugin root is the docs-recommended shape and scopes delivery to Claude Code, which is the only harness this control exists for. |

### Repo research (inline — Reviewed-Coverage: sequential-fallback)

- **Plugin MCP packaging is supported for stdio.** Official Claude Code docs:
  plugins define MCP servers "in `.mcp.json` at the plugin root or inline in
  `plugin.json`"; `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PROJECT_DIR}` ARE
  expanded in plugin-provided server `command`/`args`/`env` (unlike a project
  `.mcp.json`, where they are not — `agent-browser/SKILL.md` §Wrapping already
  documents the customer-side substitution that motivated this issue).
- **Tool prefix verified in-repo.** Plugin MCP tools are namespaced
  `mcp__plugin_<plugin>_<server>__<tool>` — established by our own
  `mcp__plugin_soleur_context7__*`, `mcp__plugin_soleur_stripe__*`,
  `mcp__plugin_soleur_cloudflare__*` references. A plugin server named
  `playwright` yields `mcp__plugin_soleur_playwright__*`, which cannot collide
  with a user's own `mcp__playwright__*` — the collision the issue feared is
  at the browser-profile layer, not the tool-name layer.
- **Profile-lock hazard is real and priced.** The orphan-server learning shows
  two servers on one `--user-data-dir` tearing each other's pages down. A
  plugin registration MUST NOT share the repo profile
  (`$HOME/.cache/playwright-mcp-profile`) or `@playwright/mcp`'s default
  persistent profile — it needs a soleur-namespaced dir.
- **`$HOME` does not expand inside JSON `args`.** The plugin entry cannot pass
  `--user-data-dir=$HOME/...` literally; options are a `bash -c` wrapper (zero
  new code, same shape as the repo `.mcp.json`) or a proxy-side flag that
  injects a default `--user-data-dir` resolved via `os.path.expanduser`
  (POSIX-portable, matches the proxy's existing launch-argv management of
  `--snapshot-mode none`). This plan chooses the proxy flag — see Proposed
  Solution.
- **Blast radius beyond the issue's file list, enumerated:**
  `plugins/soleur/test/codex-plugin.test.ts` (deep-equality on `mcpServers`) and
  `plugins/soleur/test/devin-plugin.test.ts` (`.url`/`transport:"http"` parity
  loop) both read `.claude-plugin/plugin.json` — both are why inline
  `plugin.json` registration was reshaped into the dedicated `.mcp.json`.
  `plugins/soleur/test/components.test.ts` clause (c) forbids
  `commands`/`agents`/`workflows` keys in the manifest (each REPLACES its
  default directory) but NOT `mcpServers`, and does not scan plugin-root
  files. `.claude/hooks/session-rules-loader.sh` builds the display-only
  committed-config MCP roster from repo `.mcp.json` ∪
  `plugins/soleur/.claude-plugin/plugin.json` — `plugins/soleur/.mcp.json`
  is outside its read set (deepen-pass correction), which is harmless: the
  server name `playwright` is already in the roster via the repo entry and
  the field feeds a `[session-context]` display line, not a vetting gate;
  no edit needed.
  `apps/web-platform/test/plugin-root-anchoring.test.ts` `EXPECTED_GATE_REFS`
  is an identity set over SKILL.md `${CLAUDE_PLUGIN_ROOT}` references — any NEW
  anchored `playwright-mcp-redact-proxy.py` mention in a SKILL.md must update
  it. The proxy suite (`plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh`,
  a `PROMOTED_FILES` guard-contract suite) already derives its fixture dir
  from the `.mcp.json` pin and carries an executable `.mcp.json` Guard-2 row —
  the natural home for the plugin-registration + pin-parity rows.
  `.gitignore` does NOT ignore `plugins/soleur/.mcp.json` (checked —
  `.mcp.local.json` and `.playwright-mcp/` only); the marketplace `git-subdir`
  source (`plugins/soleur`) ships it.
- **S2 prescription already survives the change unchanged.** The canonical
  paragraph keys on the proxy-unique refusal `refused by
  playwright-mcp-redact-proxy:` and scopes "call it bare" to "that server" —
  correct on the plugin registration too (the proxy refuses `filename`
  regardless of registrant). Updating `S2_CANONICAL` is NOT required; each
  carrier file instead gets preference prose pointing at
  `mcp__plugin_soleur_playwright__*`.
- **C4 + register coupling.** `model.c4` `snapshotGuard` description states
  "plugin.json registers no Playwright server — #8156" and `playwrightMcp`
  says "a customer's own registration does not until #8156" — both falsified
  by this change; regeneration via `scripts/regenerate-c4-model.sh` + four C4
  gates. The ADR-213 addendum's reach (b) and PA-8 §(g) / PA-31 §(g) register
  brackets need amendment.
- **Engines floor is a probe, not an assumption.** `engines.claude-code:
  >=2.1.139`. Plugin stdio MCP registration and the `mcp__plugin_*` tool
  prefix must be verified on that floor (upstream bug class: local stdio
  server tools failing to register as deferred tools,
  anthropics/claude-code#36914, reported on 2.1.81 — CLOSED 2026-03-30, so
  the declared floor very likely postdates the fix; the probe confirms
  rather than gambles). If the floor cannot register the server, the
  `engines` floor moves — a one-line manifest edit, flagged for CPO since
  it raises the install bar.

### Learnings that apply

- `2026-07-05-playwright-mcp-orphan-server-profile-lock-contention.md` — one
  profile, two servers → context teardown; drives the dedicated profile dir.
- `2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md` /
  `.claude/playwright-mcp.config.json` `_regression_2026_07_18` — the
  `@latest` float already bit once; the plugin entry pins
  `@playwright/mcp@0.0.78` and a suite row enforces pin parity with the repo
  `.mcp.json`.
- `2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md` — a
  guard comparing a stored value to the thing it protects needs an outside
  anchor; the pin-parity row compares two files in the same commit, so its
  anchor is the fixture directory derived from ONE of them (the repo
  `.mcp.json`, per the existing suite derivation).
- ADR-213 addendum (in-repo, cited above) — the corrected premise naming
  `updatedMCPToolOutput` as "a design input for #8156, not a change to this
  decision: the proxy also closes the disk sinks, which a PostToolUse hook
  cannot."

### External research

- Claude Code plugin MCP docs (code.claude.com/docs/en/mcp-servers): plugin
  `.mcp.json` / inline `plugin.json` stdio entries, `${CLAUDE_PLUGIN_ROOT}` +
  `${CLAUDE_PROJECT_DIR}` substitution in plugin server configs, plugin tools
  offered alongside user-configured tools, `/mcp` toggle can disable a plugin
  server without uninstalling.
- Hooks docs / anthropics/claude-code#54161, #47859, #24788 — all three
  CLOSED upstream (verified 2026-09-18 via `gh api`): `updatedMCPToolOutput`
  (MCP-only) / `updatedToolOutput` (all tools, ~2.1.121+) replace what the
  model sees on PostToolUse; #47859 (hook return value silently discarded on
  the JS-callback fast path — i.e. rewrite never persisted) was the
  transcript-persistence defect and is resolved; #24788
  (`additionalContext` dropped for MCP events) likewise closed. Option C's
  mechanism is therefore MORE viable than the #7980-era premise — its
  deferral stands on the disk-sink limitation, not on hook mechanics.
- anthropics/claude-code#36914: local stdio plugin `.mcp.json` servers
  failing to register deferred tools on 2.1.81 — CLOSED 2026-03-30; the
  engines-floor probe confirms on the declared floor rather than assuming.

### Community discovery / functional overlap

No uncovered stacks (the surface is our own plugin manifest + our own proxy —
repo expertise is deep). No community artifact wraps a customer's existing
Playwright-MCP registration through a shipped redactor; functional overlap
check returns nothing installable. Both checks ran per
`plan-community-discovery.md` / `plan-functional-overlap.md` criteria.

### Skill description budget (Phase 1.8)

No `description:` edit to any `plugins/soleur/skills/*/SKILL.md` is proposed —
`SKILL_DESCRIPTION_WORD_BUDGET` not engaged.

## Problem Statement

Property P7 — the browser-snapshot credential guard holds without the acting
agent having to remember it — is achieved on the Playwright-MCP path **only on
registrations routed through `playwright-mcp-redact-proxy.py`** (ADR-213,
#7980). The proxy ships inside the plugin but nothing registers it for a
customer: `plugins/soleur/.claude-plugin/plugin.json` declares four HTTP
servers and no Playwright server, so a customer's own `playwright` registration
is wrapped only if they adopt a documented `.mcp.json` shape — including
substituting `${CLAUDE_PLUGIN_ROOT}` by hand, which a project `.mcp.json` does
not expand. Meanwhile the shipped skills (`qa`, `reproduce-bug`, `ux-audit`,
`cf-token-scope`) instruct `browser_snapshot` on the customer's own session —
the CPO sign-off on #7980 ruled the default wrapped path a prerequisite of
skills that already ship, not a Phase 5 capability.

The product requirement is one sentence: **the customer never edits
`.mcp.json`.**

## Proposed Solution

**Register a wrapped `playwright` stdio server in a dedicated
`plugins/soleur/.mcp.json` at the plugin root** — the docs-recommended plugin
MCP surface — whose command is the already-shipped proxy wrapping the same
`@playwright/mcp@0.0.78` pin the repository's own `.mcp.json` uses:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "python3",
      "args": [
        "${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py",
        "--user-data-dir-name", "soleur-playwright-mcp-profile",
        "--",
        "npx", "@playwright/mcp@0.0.78"
      ]
    }
  }
}
```

On every customer session where the plugin is enabled, Claude Code starts this
server automatically; its tools appear as `mcp__plugin_soleur_playwright__*`
(the same `mcp__plugin_soleur_<server>__*` namespace our context7/stripe/
cloudflare servers already produce). Every `tools/call` result is redacted in
flight by construction — P7 holds on the default path with zero customer
configuration.

**Why the dedicated `.mcp.json` and not inline `plugin.json`:** the canonical
manifest is parity-checked into two sibling harness manifests —
`plugins/soleur/test/codex-plugin.test.ts` deep-equals `codex.mcpServers`
against it and `plugins/soleur/test/devin-plugin.test.ts` iterates every
canonical server asserting `.url`/`transport: "http"`. An inline stdio entry
would either force a broken registration onto harnesses that cannot run it or
force a parity-test restructure that hides real drift. The plugin-root
`.mcp.json` is read by Claude Code only, which is the one harness this control
exists for (ADR-213's whole threat model is the Claude Code stdio/transcript
path).

**Why a proxy-side `--user-data-dir-name` flag and not `bash -c`:** the
registration needs a soleur-namespaced persistent profile (property 5 — the
orphan-server profile-lock class), and `$HOME` does not expand inside JSON
`args`. The proxy already manages child launch argv (it appends
`--snapshot-mode none`); resolving a basename under the user cache dir via
`os.path.expanduser`/`$XDG_CACHE_HOME` is the same class of work, keeps the
manifest declarative (`command: python3`, no shell string for a guard to
audit), and is exercisable by the existing suite's argv-assertion machinery.
Semantics: `--user-data-dir-name <basename>` resolves to
`$XDG_CACHE_HOME/<basename>` (default `~/.cache/<basename>`) and injects
`--user-data-dir=<abs>` into the child argv **only when the child argv does not
already carry `--user-data-dir`**; carrying both is a refuse-to-start
ambiguity, and a `<basename>` containing a path separator or `..` is refused.
Absent the flag, behaviour is unchanged (the repo `.mcp.json` is untouched).

**Resolution precedents and edge cases** (deepen-pass: `scripts/lib/scratch-root.sh`
is the in-repo precedent for this exact resolution — it resolves
`${XDG_CACHE_HOME:-${HOME:-}/.cache}` and refuses when (a) neither
`HOME` nor `XDG_CACHE_HOME` is set and (b) `XDG_CACHE_HOME` is set but
RELATIVE — only an absolute path is meaningful per the XDG spec). The flag
mirrors it: a relative `XDG_CACHE_HOME` value is a refuse-to-start (do not
silently fall through to `~/.cache` — the operator set the var; a wrong dir
under it is worse than a clear refusal); when `XDG_CACHE_HOME` is unset and
`HOME` is unset, `os.path.expanduser("~")` returns `"~"` unexpanded — detect
the non-absolute result and refuse to start rather than create a literal `~/`
directory under CWD. Both edges get suite rows.

**Deliberately absent from the plugin entry** (each is dogfood-specific):

- `--config=.claude/playwright-mcp.config.json` — repo-relative, headed-Chrome
  credential-handoff settings; absent means `@playwright/mcp` defaults
  (headless, bundled Chromium) which is what the skills need on customer
  machines. The proxy refuses a `--config` that does not exist, so it must not
  be named.
- The `pkill` reaper and `env -u WAYLAND_DISPLAY`/X11 prelude — Linux-only
  (the proxy itself is POSIX). With a soleur-namespaced profile there is no
  shared-profile population to reap; orphan accumulation on customer machines
  is bounded to one plugin server per session. The residual is
  orphan-on-own-profile: a SIGKILLed session leaking its `playwright-mcp`
  child, which the next session's server then contends with on the same
  profile's `SingletonLock`. Whether Claude Code's exit path reaps the child
  is measured in Phase-0 probe item 5; the failure mode and playbook entry
  are named in `failure_modes`.
- The `bash -c` wrapper entirely.

## Technical Considerations

- **Preconditions degrade gracefully.** The plugin entry requires `python3`
  and `npx` on PATH on a POSIX host (the proxy does not run on Windows — an
  existing, documented constraint). If either is absent the server fails to
  connect; `/mcp` shows it down and the skills' existing "server fails to
  connect" playbook (`agent-browser/SKILL.md` §end, extended to name the
  plugin log directory) is the remediation. A failed plugin server must not
  block the session — plugin MCP failures already behave this way.
- **Two-server coexistence.** A customer with their own `playwright`
  registration ends up with `mcp__playwright__*` (unwrapped, theirs) AND
  `mcp__plugin_soleur_playwright__*` (wrapped, ours). No tool-name collision
  (namespaces differ); no profile collision (distinct `--user-data-dir`). The
  skills gain explicit preference prose: call the plugin-registered server;
  treat any other `mcp__<server>__` prefix as a separate, unwrapped
  registration (the S2 canonical sentence already says exactly this).
- **S2 prescription survives unchanged.** `S2_CANONICAL` keys on the
  proxy-unique refusal and scopes "call it bare" to "that server" — correct on
  the plugin registration by construction. The skills get an added preference
  clause OUTSIDE the verbatim paragraph, so `MCP_GAP_MARKER_RE` carriers need
  no re-pinning of the canonical text.
- **`/mcp` toggle-off.** A customer can disable the plugin server without
  uninstalling — then the skills' fallback (file-form on their own
  registration, or `agent-browser`) is the path; the prose must not assume the
  plugin server exists.
- **Non-Claude-Code harnesses.** `.codex-plugin` and `.devin-plugin` do not
  read a plugin-root `.mcp.json`, so on Codex/Devin sessions
  `mcp__plugin_soleur_playwright__*` simply does not exist — the same
  degradation shape as a missing precondition, routed by the same fallback
  prose (separate registration → file-form). Harness parity is deliberately
  NOT claimed; the control is Claude-Code-shaped end to end.
- **`npx` on every session start** — accepted cost, named in the issue.
  Bounded: the pin hits the npx cache after first install; no `@latest` float
  (the 0.0.78 pin is load-bearing — the float already regressed once, see the
  config file's `_regression_2026_07_18` note).
- **Engines floor probe.** `engines.claude-code: >=2.1.139` predates neither
  plugin-MCP support nor the `mcp__plugin_*` namespace; the recorded local
  stdio plugin-server registration bug class (upstream #36914, reported on
  2.1.81) was CLOSED upstream 2026-03-30. Phase 0 still measures the floor —
  a closed issue is not a shipped fix on every install — before the prose
  ships.

### Attack surface enumeration

What changes for a customer: one additional spawned process per session
(`python3` proxy → `npx @playwright/mcp`), one new persistent directory
(`~/.cache/soleur-playwright-mcp-profile` or `$XDG_CACHE_HOME` equivalent),
one new plugin-payload file (`plugins/soleur/.mcp.json`).

- The proxy's own attack surface is unchanged — same fail-closed arms, same
  predicate, same refusal set. The new flag is input to the launcher, not to
  the relay; its hazard is path injection via `<basename>`, closed by the
  basename-only + refuse-on-conflict semantics above, each with a suite row.
- The plugin `.mcp.json` is a committed-config content surface read into
  session state (`session-rules-loader.sh` treats it as such for the repo
  files) — no executable content beyond the argv it declares.
- The new profile dir inherits Chrome's own storage security; it is a NEW
  persistent store on the customer machine (see Encryption Posture).
- Not a new network surface — the relay is stdio-only; the proxy already
  refuses `--port`/`--host` and config `server.*`.

## Implementation Phases

### Phase 0 — Floor probe (before any manifest edit)

Measure, on the declared `engines.claude-code >=2.1.139` floor and on the
installed CLI, with a scratch plugin dir:

1. A plugin-root `.mcp.json` stdio entry registers tools as
   `mcp__plugin_soleur_playwright__*` — `claude --plugin-dir <scratch>` +
   `ToolSearch`/deferred-tools visibility, plus `claude mcp list`/`/mcp`
   evidence. If the floor cannot register it (the #36914 class), record the
   minimum working version and move the `engines` floor in the manifest —
   flagged for CPO since it raises the install bar.
2. `${CLAUDE_PLUGIN_ROOT}` expands inside the plugin `.mcp.json` `command` and
   `args` (docs claim it; measure it — this is the expansion that does NOT
   happen in a project `.mcp.json`).
3. Name-collision behaviour: a user-scoped `playwright` plus the plugin's —
   both servers listed, both tool namespaces live, no silent override.
4. macOS sanity of the launch argv (BSD userland; no bash prelude needed).
5. **Orphan-on-own-profile reaping** (user-impact sign-off condition): SIGKILL
   the CLI parent while the plugin server holds the soleur profile, restart,
   and measure whether the leaked `playwright-mcp` child contends on
   `SingletonLock` (the 2026-07-05 mechanism, self-inflicted). If reaping
   fails, the connect-failure playbook must name the stale-profile symptom —
   record which arm held in the probe record.

Evidence lands in `knowledge-base/project/specs/feat-one-shot-8156-8250-mcp-proxy-time-port/plan-time-probe-record.md`
(same convention as the #7980 probe record).

### Phase 1 — The wrapped registration

1. `playwright-mcp-redact-proxy.py`: add `--user-data-dir-name <basename>`
   (resolution + conflict/path refusal as specced; update the module header).
2. `plugins/soleur/.mcp.json` (new): the entry above, pin derived from the
   repo `.mcp.json`.
3. Proxy suite: new rows — flag injects `--user-data-dir=$XDG_CACHE_HOME/<name>`;
   `~/.cache` fallback; `..`/separator basename refused; flag+explicit
   `--user-data-dir` refused; flag absent ⇒ argv untouched (regression). A
   **plugin-registration Guard-3 row** beside Guard 2: parse
   `plugins/soleur/.mcp.json`, assert `command == "python3"`, argv carries the
   `${CLAUDE_PLUGIN_ROOT}`-anchored proxy + `@playwright/mcp@$PIN` where `$PIN`
   is derived from the repo `.mcp.json` (pin parity — a bump in one without the
   other reddens), no `--config`, no `bash`. A mutant per clause.
4. `agent-browser/SKILL.md` §"Wrapping the server": rewrite — plugin-registered
   default (tools `mcp__plugin_soleur_playwright__*`, preconditions, `/mcp`
   toggle, separate-profile note), the manual `.mcp.json` shape demoted to
   "wrap your own registration (advanced)", the connect-failure playbook
   extended to the plugin server's log directory name (measured in Phase 0).

### Phase 2 — Skills resolve to the wrapped server

1. Sweep the 13 `mcp__playwright__*` literals (5 files: `agent-browser`,
   `reproduce-bug`, `cf-token-scope/references/widen-playbook.md`, `plan`,
   `work`) to `mcp__plugin_soleur_playwright__*`, with "a different
   `mcp__<server>__` prefix is a separate registration" carried where the
   context is about which server to call.
2. `qa`, `ux-audit`, `cf-token-scope/widen-playbook`, `reproduce-bug`: add a
   preference clause OUTSIDE the verbatim S2 paragraph — "the plugin-registered
   `mcp__plugin_soleur_playwright__*` server is already wrapped; call its
   `browser_snapshot` bare; fall back to the file-form on any other
   registration." `S2_CANONICAL` unchanged.
3. `EXPECTED_GATE_REFS` in `plugin-root-anchoring.test.ts`: update only if a
   SKILL.md gains a NEW `${CLAUDE_PLUGIN_ROOT}`-anchored proxy reference
   (audit during implementation — likely zero new refs).
4. `mcp__plugin_soleur_pw__` defensive grep: zero today; the suite greps both
   old prefixes to catch strays.

### Phase 3 — Records, register, and deferral

1. ADR-213: append a `## Addendum — 2026-09-XX (#8156)` — reach (b) closed by
   default via plugin-root `.mcp.json`; the dedicated-file-over-inline
   rationale; profile-dir isolation; the Option-C deferral with its
   re-evaluation criteria; `/mcp` toggle-off caveat; preconditions.
2. C4: update `model.c4` `snapshotGuard` description (SHIPS vs WIRES — now
   wired by the plugin manifest for every enabled customer) and
   `playwrightMcp` description (the "until #8156" clause); regenerate
   `model.likec4.json` via `scripts/regenerate-c4-model.sh`; four C4 gates
   green (`c4-code-syntax`, `c4-render`, `c4-count-parity`,
   `c4-model-freshness`).
3. `knowledge-base/legal/article-30-register.md` PA-8 §(g): re-APPEND (never
   edit — the CLO attestation pinned this) reach (b) — a customer registration
   is now wrapped by default through the plugin manifest; state what the
   plugin server does and does not cover (own-registration residual stands).
   PA-31 §(g): assess whether its fleet-path statements are falsified (they
   are not — the fleet overlay is unchanged) and record the assessment.
4. File the Option-C deferral issue (see Deferrals).
5. `compliance-posture.md` Active Items / CLO attestation follow-up: the 2026-09-14
   audit's row-18 evidence ("no `plugins/soleur/.mcp.json` exists") is
   superseded by this change — a dated audit addendum noting the new fact is
   in scope, not a re-attestation of the whole control.

## Files to Create

- `plugins/soleur/.mcp.json` — plugin-root MCP config; the wrapped `playwright` entry.
- `knowledge-base/project/specs/feat-one-shot-8156-8250-mcp-proxy-time-port/plan-time-probe-record.md` — Phase 0 measurement record.

## Files to Edit

- `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py` — `--user-data-dir-name` flag.
- `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` — flag rows + plugin-registration Guard-3 row + pin-parity.
- `plugins/soleur/skills/agent-browser/SKILL.md` — §"Wrapping the server" rewrite; `mcp__playwright__` literals (3).
- `plugins/soleur/skills/reproduce-bug/SKILL.md` — 6 prefix literals + preference clause.
- `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md` — 1 literal + preference clause.
- `plugins/soleur/skills/qa/SKILL.md` — preference clause beside the S2 paragraph.
- `plugins/soleur/skills/ux-audit/SKILL.md` — preference clause beside the S2 paragraph.
- `plugins/soleur/skills/plan/SKILL.md` — 1 literal (`mcp__playwright__*` routing note).
- `plugins/soleur/skills/work/SKILL.md` — 1 literal (same routing note).
- `apps/web-platform/test/plugin-root-anchoring.test.ts` — `EXPECTED_GATE_REFS` only if a new anchored reference lands (conditional).
- `knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md` — #8156 addendum.
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `model.likec4.json` — description updates + regen.
- `knowledge-base/legal/article-30-register.md` — PA-8 §(g) re-append; PA-31 §(g) assessment.
- `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` — dated addendum superseding row-18 evidence. (Append-only convention applies to audit files; do not rewrite findings.)
- `knowledge-base/legal/compliance-posture.md` — changelog comment, `last_updated`, and a dated in-cell correction on the #7980 Completed row's reach (b).
- `plugins/soleur/.claude-plugin/plugin.json` — `engines` floor ONLY if the Phase-0 probe fails the floor (conditional, CPO-flagged).

Not edited: repo `.mcp.json` (dogfood keeps its headed credential-handoff
entry and its own profile dir); `.codex-plugin/plugin.json` /
`.devin-plugin/plugin.json` (harness-scoped delivery is the point);
`hooks/hooks.json` (no new hooks — Option C is deferred);
`scripts/lint-credential-path-literals.py` (`S2_CANONICAL` unchanged);
`.claude/playwright-mcp.config.json` (dogfood-only).

## Alternative Approaches Considered

| Alternative | Properties it buys | Why not chosen |
|---|---|---|
| **B — auto-wrap the user's `playwright` entry** (the issue's second option) | P1 on the user's own server | No plugin-manifest mechanism wraps an existing registration. The only implementable form — a SessionStart hook rewriting customer `.mcp.json`/`.claude.json` — is an unconsented mutation of customer-owned config AND loads only after a full restart, so it satisfies neither "never edits" in spirit nor P7 in the session it lands. Cut. |
| **C — plugin PostToolUse hook on `mcp__playwright__.*` emitting `updatedToolOutput`/`updatedMCPToolOutput`** (+ PreToolUse denying `filename`/`_meta`) | P7-transcript on ANY registration named `playwright`, incl. the customer's own | Reaches the sink the proxy already covers but NOT the disk sinks (the tool's `filename:`/`page-*.yml` writes complete before the hook sees output; a hook cannot append `--snapshot-mode none` to a launch it does not own) — fails property 4. Its remaining unique value is covering the customer's own unwrapped registration; bounded residual, deferred with re-evaluation criteria (below). Deepen-pass correction: the transcript-persistence defect (upstream #47859) is CLOSED — the mechanism is viable; the deferral is scoped-coverage economics, not feasibility. |
| **A-inline — register inside `plugin.json` `mcpServers`** | P1–P4 | Forces the codex deep-equality and devin `.url`-parity tests to carry a stdio entry on harnesses that cannot run it. Reshaped into the dedicated `.mcp.json` — same property, smaller blast radius. |
| **Do nothing — keep documenting the manual shape** | None | The issue exists because documentation is not P7. Rejected by the CPO ruling on #7980. |
| **`bash -c` launch inside the plugin entry** (mirrors repo `.mcp.json`) | P5 without a proxy code change | Trades a testable argv-management flag for an unauditable shell string inside a JSON manifest; the flag is ~15 lines in the file that already owns child argv. The flag also fixes the same problem for any future wrapped registration. |
| **Name the server something other than `playwright`** (e.g. `soleur-browser`) | Same, plus zero prefix sweep | Breaks the issue's expected `mcp__plugin_soleur_playwright__*` shape and makes the skills' story harder ("use playwright, but not the one named playwright"). The `plugin_soleur` namespace already disambiguates. |

**Option C re-evaluation criteria** (for the deferral issue): the agent-side
misroute rate matters if skills keep landing on customers' own `playwright`
servers despite the preference prose; OR the transcript-persistence question
is measured benign (hook rewrite provably persists); OR upstream ships a way
to wrap/ veto a user registration at the manifest layer. Until then the
file-form fallback plus this change's preference prose is the stated residual.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Soleur browser skill
  (`/soleur:qa`, `/soleur:reproduce-bug`, `/soleur:ux-audit`,
  `/soleur:cf-token-scope`) driving an unwrapped Playwright registration —
  today that is the *default* — so a bare `browser_snapshot` on a login page
  or credential panel puts a password, a freshly-minted token, or a 2FA code
  into the tool result. Broken-in-the-other-direction: the plugin server fails
  to start on a customer machine missing `python3`/`npx`, and every browser
  skill degrades to the file-form path with a confusing `/mcp` failure line.
- **If this leaks, the user's data (credentials) is exposed via:** the tool
  result entering the model request (off the customer's machine) and the local
  session transcript — the exact sinks ADR-213 enumerates. A customer whose
  own `playwright` registration stays unwrapped retains today's exposure on
  THAT server only (named residual, Option C deferred).
- **Brand-survival threshold:** `single-user incident` — a single founder's
  leaked credential via a marketed browser skill is the incident class the
  whole ADR-213 control set exists to prevent.

CPO sign-off is required at plan time before `/work` begins (threshold rule).
In this headless pipeline run no CPO Task agent could be spawned — the
requirement is recorded here and flagged in `decision-challenges.md` for the
ship stage to render; the sign-off question for CPO is narrow: "the fix for
#8156 ships a stdio MCP server that spawns `python3`+`npx` on every customer
session, with a persistent browser profile under the user cache dir."

## Observability

```yaml
liveness_signal:
  what: "Plugin MCP server connect state — the proxy's startup refusal line `playwright-mcp-redact-proxy: refusing to start: <reason>` in `mcp-logs-*/` (Claude Code persists MCP server stderr there), plus the `tools/list` description marker ` [Soleur: output is redacted in flight …]` on `browser_snapshot` as the positive liveness signal"
  cadence: "per session start"
  alert_target: "the acting agent (reads the marker / the failure playbook); no paged route — customer-side surface"
  configured_in: "plugins/soleur/.mcp.json (registration); playwright-mcp-redact-proxy.py (emission)"

error_reporting:
  destination: "Claude Code MCP log dir `~/.cache/claude-cli-nodejs/*/mcp-logs-*/` (measured name recorded in the Phase-0 probe) and the `isError` tool result the proxy substitutes"
  fail_loud: "`refusing to start:` stderr line + exit 2 (server down in /mcp); `refused by`/`withheld by playwright-mcp-redact-proxy:` result prefixes; suite reddens on any regressing arm"

failure_modes:
  - mode: "python3 or npx absent on customer PATH → server fails to connect"
    detection: "`/mcp` shows the plugin server down; skills' connect-failure playbook routes to the newest mcp-logs file"
    alert_route: "agent-facing (skill prose), not paged"
  - mode: "pin drift between repo `.mcp.json` and `plugins/soleur/.mcp.json`"
    detection: "Guard-3 pin-parity row in playwright-mcp-redact-proxy.test.sh reddens in CI"
    alert_route: "required CI suite"
  - mode: "flag misconfiguration (`..`/separator basename, or flag + explicit `--user-data-dir`)"
    detection: "proxy refuse-to-start, exit 2, reason names the setting"
    alert_route: "agent-facing via mcp-logs + skills playbook"
  - mode: "customer toggles the plugin server off in /mcp"
    detection: "`mcp__plugin_soleur_playwright__*` tools absent; skills' fallback prose"
    alert_route: "agent-facing (file-form path), not paged"
  - mode: "orphan-on-own-profile: SIGKILLed session leaks the plugin's playwright-mcp child; next session's server contends on the soleur profile SingletonLock and Chrome tears its pages down"
    detection: "Phase-0 probe item 5 measures exit-path reaping; live symptom is a refused/half-dead connect whose playbook entry names the stale-profile check (`pgrep -f soleur-playwright-mcp-profile` class)"
    alert_route: "agent-facing via extended connect-failure playbook (Phase 1.4), not paged"

logs:
  where: "Claude Code per-project MCP log dir (jsonl); proxy inherits server stderr there"
  retention: "Claude Code-managed rotation; not Jikigai-operated"

discoverability_test:
  command: "python3 plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh"
  expected_output: "all suite rows PASS including the plugin-registration Guard-3 row and the pin-parity assertion"
```

## Encryption Posture

```yaml
at_rest:
  - store: "soleur playwright-mcp browser profile dir ($XDG_CACHE_HOME/soleur-playwright-mcp-profile or ~/.cache/...) on the customer machine"
    mechanism: "Chrome's own profile storage — cookie/session values encrypted by Chrome via the OS keychain where available; plaintext-exception for the remainder (cache, history, localStorage) on a customer-managed disk"
    evidence: "proxy argv injection at playwright-mcp-redact-proxy.py (--user-data-dir-name resolution); the dir is new, created by this registration"
    defends_against: "casual file-read of stored session cookies on keychain-backed platforms"
    does_not_defend: "any process running as the customer user reading the profile dir; a seized disk on a non-keychain platform; an agent instructed to exfiltrate it"
    disclosed_as: "docs-claimed on merge — Phase 1.4 adds the separate-profile note to agent-browser/SKILL.md (user-impact Finding 2); no docs/legal/** surface makes an at-rest protection claim"
    live_verification: "unavailable:customer-machine store — verified indirectly by the suite asserting the argv the proxy injects"
in_transit:
  - connection: "Claude Code stdio client -> proxy -> @playwright/mcp child (pipes, same host)"
    enforced_at: "plugins/soleur/.mcp.json command/args; proxy selectors loop"
    tls: "none — local pipes, no network transport; the proxy already refuses --port/--host/server.* that would open a network listener"
    cert_verification: "off"
    does_not_defend: "nothing to defend — no bytes leave the host on this leg; the model-request leg to Anthropic is the redactor's job, unchanged"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "browser profile plaintext residue is Chrome's standard store on a customer-managed disk; the feature adds no new egress for it"
  tracking_issue: "#8156"
  reevaluate_when: "the plugin profile gains sync/upload behaviour, or a docs/legal surface makes an at-rest claim for it"
  expires_on: "2026-12-17"
```

## Guard Contract

### Guard 1 — `--user-data-dir-name` launch-argv rule (proxy)

**Property.** The plugin-registered child always launches on a
soleur-namespaced, basename-only profile dir; no child argv ever carries both
an explicit `--user-data-dir` and the flag, and no `<basename>` escapes the
user cache dir.

**Assembly.** Every argv the proxy can spawn flows through one chokepoint —
the child-argv assembly in `playwright-mcp-redact-proxy.py` (where
`--snapshot-mode none` is already appended). The flag's only input surfaces
are the proxy's own argv (before `--`) and the child argv (after `--`); the
plugin `.mcp.json` is the first caller, the repo `.mcp.json` deliberately does
not pass it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the injection — child argv carries no `--user-data-dir` despite the flag | RED |
| 2 | Drop the basename guard — `--user-data-dir-name ../x` resolves outside the cache dir | RED |
| 3 | Accept flag + explicit `--user-data-dir` — refuse-to-start bypassed | RED |
| 4 | Ignore `$XDG_CACHE_HOME` and always use `~/.cache` | RED |
| 5 | Suite-side: drop the "flag absent ⇒ argv untouched" regression row while breaking it | RED |

### Guard 2 — plugin-registration + pin parity (suite row)

**Property.** `plugins/soleur/.mcp.json` registers exactly one wrapped
Playwright server on the same `@playwright/mcp` pin as the repo `.mcp.json` —
a bump in either file without the other is a release defect.

**Assembly.** Both committed manifests, parsed (not grepped): the Guard-3 row
reads `plugins/soleur/.mcp.json` for shape (command `python3`,
`${CLAUDE_PLUGIN_ROOT}`-anchored proxy argv, pin token, no `--config`, no
`bash`) and derives `$PIN` from the repo `.mcp.json` — the same derivation the
suite already uses for its fixture directory, so the anchor is one pin, not
two.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Bump the pin in `plugins/soleur/.mcp.json` only | RED |
| 2 | Delete the `playwright` entry or rename it (guard reports 0 servers and exits 0 otherwise) | RED |
| 3 | Change `command` to `bash`/`npx` or drop the proxy from argv | RED |
| 4 | Add `--config=` (a customer machine cannot satisfy it) | RED |
| 5 | Suite-side: point the row at a fixture file instead of the real manifest | RED |

### Guard 3 — skills-prefix residual sweep

**Property.** No shipped skill/agents file prescribes the un-namespaced
`mcp__playwright__*` (or the never-shipped `mcp__plugin_soleur_pw__*`) form as
the call to make; the plugin prefix is the only one instructed.

**Assembly.** `git grep -n 'mcp__playwright__\|mcp__plugin_soleur_pw__' --
plugins/soleur/skills plugins/soleur/agents` — the whole instruction corpus
the S2 walk already scopes to; the only permitted survivors are prose
describing the separate-registration rule (a sentinel word bounds them — see
Acceptance Criteria).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce `mcp__playwright__browser_snapshot` as an instruction in `reproduce-bug` | RED |
| 2 | Sweep script greps only `mcp__playwright__` — `mcp__plugin_soleur_pw__` reintroduced unchecked | RED |
| 3 | Sweep exempts the file it lives in (if the check is a suite row, remove its self-grep exemption) | RED |

## Architecture Decision (ADR/C4)

This plan changes who WIRES the trust boundary — the plugin manifest now
registers a stdio MCP server on every customer machine, where previously only
this repository's `.mcp.json` did. That is a packaging-shape and
reach-boundary change a future engineer must find recorded.

- **ADR** — amend `ADR-213` (no new ordinal — same decision extended, per the
  #7980 precedent): append `## Addendum — 2026-09-XX (#8156)` recording the
  plugin-root `.mcp.json` registration, the dedicated-file-over-inline
  rationale (codex/devin parity constraints), the `--user-data-dir-name`
  profile isolation, the Option-C deferral with re-evaluation criteria, the
  `/mcp` toggle-off and precondition caveats, and the corrected-premise
  disposition (`updatedMCPToolOutput` considered and deferred).
- **C4 views** — `model.c4` component descriptions: `snapshotGuard` (SHIPS vs
  WIRES — now wired by `plugins/soleur/.mcp.json` for every enabled customer)
  and `playwrightMcp` (remove/quote the "until #8156" clause; note the plugin
  registration uses a separate soleur-namespaced profile and headless
  defaults). Enumerated per the completeness mandate: no new external actor
  (the customer operator is already modeled), no new external system
  (`playwrightMcp` already exists), no new container — the change is a
  reach/reach-description delta on existing elements; `views.c4` membership
  unchanged. Regenerate `model.likec4.json` via
  `scripts/regenerate-c4-model.sh`; run all four C4 gates.
- **Sequencing** — the ADR addendum describes the state that lands in THIS PR;
  no `status: adopting` needed.

## Acceptance Criteria

- [x] AC1 — `plugins/soleur/.mcp.json` exists, parses, and registers `playwright` with `command: "python3"`, an argv carrying `${CLAUDE_PLUGIN_ROOT}/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`, `--user-data-dir-name soleur-playwright-mcp-profile`, `--`, `npx`, `@playwright/mcp@0.0.78` — and no `bash`, no `--config`, no `--user-data-dir` literal.
- [x] AC2 — Phase-0 probe record exists at `knowledge-base/project/specs/feat-one-shot-8156-8250-mcp-proxy-time-port/plan-time-probe-record.md` evidencing (a) `mcp__plugin_soleur_playwright__*` tools registered on the engines floor (or the floor bump taken, with the minimum version named), (b) `${CLAUDE_PLUGIN_ROOT}` expansion inside the plugin `.mcp.json`, (c) coexistence with a user-scoped `playwright`.
- [x] AC3 — Proxy `--user-data-dir-name`: child argv gains `--user-data-dir=<resolved>` under `$XDG_CACHE_HOME`/`~/.cache`; `..`/separator basenames, flag+explicit-`--user-data-dir`, a RELATIVE `XDG_CACHE_HOME` value, and unresolvable `~` (HOME unset) all refuse to start (exit 2, reason names the setting, never the value); absent the flag, argv is byte-identical to today.
- [x] AC4 — `git grep -n 'mcp__playwright__\|mcp__plugin_soleur_pw__' -- plugins/soleur/skills plugins/soleur/agents` returns zero lines that instruct a call on that prefix. Permitted survivors are literals inside prose explicitly scoped to a customer's OWN `playwright` registration (e.g. agent-browser's "verify your manual wrap" `ToolSearch select:mcp__playwright__browser_snapshot` line and the separate-registration rule itself); every call site the skills prescribe resolves to `mcp__plugin_soleur_playwright__*`. The survivor set is pinned by file:line in the PR body.
- [x] AC5 — `qa`, `ux-audit`, `reproduce-bug`, `cf-token-scope` each instruct preference for `mcp__plugin_soleur_playwright__*` beside (not inside) the verbatim S2 paragraph; `MCP_GAP_MARKER_RE` still matches each carrier (`scripts/lint-credential-path-literals.test.sh` green).
- [x] AC6 — Proxy suite green including: all new flag rows, the Guard-3 plugin-registration row, and pin parity derived from the repo `.mcp.json` (mutating either manifest's pin independently reddens).
- [x] AC7 — `EXPECTED_GATE_REFS` still matches the tree (`plugin-root-anchoring.test.ts` green) — updated iff a SKILL.md gained a new anchored `(file, playwright-mcp-redact-proxy.py)` pair (G3 is a deduped identity set; the existing `agent-browser` pair is already pinned). New proxy mentions in SKILL.md must be `${CLAUDE_PLUGIN_ROOT}`-anchored — G2/G2b reject bare-basename invocations — so preference prose should name the SERVER (`mcp__plugin_soleur_playwright__*`), not the script path.
- [x] AC8 — ADR-213 carries the dated `#8156` addendum; `model.c4`/`model.likec4.json` updated and all four C4 gates green; PA-8 §(g) re-appended (append-only); the 2026-09-14 CLO audit carries a dated addendum on row-18 evidence.
- [x] AC9 — Option-C deferral issue filed (`deferred-scope-out`, `domain/engineering`, `type/security`), referenced from the ADR addendum and this plan's Alternatives table.
- [x] AC10 — `plugin.json` unchanged unless the Phase-0 probe forced the `engines` bump (then exactly that one key, with the probe record cited in the PR body). `codex-plugin.test.ts` and `devin-plugin.test.ts` green unmodified.
- [x] AC11 — The diff's file set is a subset of Files to Create/Edit above plus this plan's own artifacts (`plans/`, `specs/<branch>/`, `INDEX.md` if regenerated, `decision-challenges.md`).
- [x] AC12 — PR body carries `Closes #8156`, a `## Changelog` section (semver label guidance: MINOR — new plugin MCP surface), and names the Option-C deferral issue.

## Test Scenarios

- Given a plugin dir with the new `.mcp.json`, when Claude Code loads the plugin on the engines floor, then `mcp__plugin_soleur_playwright__browser_snapshot` is discoverable and its `tools/list` description ends with the redaction marker.
- Given a user-scoped `playwright` AND the plugin server, when both connect, then `mcp__playwright__*` and `mcp__plugin_soleur_playwright__*` both list and the plugin server's profile dir is not the user's.
- Given `--user-data-dir-name ../evil`, when the proxy starts, then exit 2 and stderr names the flag.
- Given flag + child `--user-data-dir`, when the proxy starts, then exit 2 (ambiguity refusal).
- Given a page with a credential-named textbox behind the plugin server, when `browser_snapshot` is called bare, then the value is `<redacted>` and the trailer is appended (existing predicate parity — no new predicate).
- Given the plugin server disabled in `/mcp` (or failed to connect), when a skill prescribes a snapshot, then the file-form fallback on the other registration applies unchanged.
- `python3 plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` — full suite green locally.
- `bun test plugins/soleur/test/codex-plugin.test.ts plugins/soleur/test/devin-plugin.test.ts` — green unmodified (the dedicated-file decision holds).
- `bun test apps/web-platform/test/plugin-root-anchoring.test.ts` — green.
- `bash scripts/lint-credential-path-literals.test.sh` — green (S2 carriers unchanged).

## Success Metrics

- On a customer session with the plugin enabled and NO `.mcp.json` edits: a
  `browser_snapshot` call returns `<redacted>` credential values — P7 holds by
  default (measured in Phase 0 evidence; asserted as the AC2 probe outcome).
- Zero residual `mcp__playwright__*` instructions in shipped prose (AC4).
- Pin drift impossible-to-merge silently (Guard-3 parity row in the required suite).

## Dependencies & Risks

- **Engines floor may be too low** (upstream #36914 class) → Phase-0 probe decides; remedy is an `engines` bump (install-bar change → CPO).
- **`python3`/`npx` absent on a customer machine** → graceful degradation to the file-form path; the connect-failure playbook is extended, not invented.
- **Two-server ambiguity** → mitigated by preference prose + distinct profile dir; the residual (agent picks the user's unwrapped server anyway) is the named Option-C deferral.
- **`npx` first-run latency** on every session start → accepted per the issue; pin (not `@latest`) bounds version drift; the 0.0.78 pin is parity-guarded.
- **Persistent profile on customer disk** → new store, documented in Encryption Posture; cookies/session data benefit from Chrome's OS-keychain encryption where available.
- **Guard-code defect risk** → the proxy suite is the repo's most adversarially-reviewed surface (ADR-213 round-3 lesson: fixtures from the surface, not the author); every new row is mutation-proven per the Guard Contract.

## Domain Review

**Domains relevant:** engineering, legal/compliance

### Engineering

**Status:** reviewed (sequential-fallback — no Task agents available in this
subagent context; assessment performed inline by the planning orchestrator)
**Assessment:** Packaging-shape decision resolved for the dedicated plugin
`.mcp.json` over inline `plugin.json` on measured parity-test blast radius;
the CTO-decision the issue reserves (register vs auto-wrap) is decided here
for registration because auto-wrap has no implementable, consented mechanism
(auto-wrap = config mutation, cut in Phase 0.6b). Preconditions (`python3`,
`npx`, POSIX) degrade gracefully to the already-shipped fallback.

### Legal/Compliance (CLO surface)

**Status:** reviewed (sequential-fallback, inline)
**Assessment:** GDPR gate fires on trigger (d) — new artifact distribution
surface (plugin update changing runtime behaviour on customer machines). No
new processing activity: the proxy and profile dir live on the customer's own
machine under their credentials; the change strictly reduces off-machine
credential exposure. Register obligations are mechanical and specified: PA-8
§(g) re-append (append-only per the CLO attestation), PA-31 §(g) assessment,
dated addendum on the 2026-09-14 audit's row-18 evidence.

### Product/UX Gate

**Tier:** none — no user-facing pages or UI components; the change is
manifest + guard + prose. The mechanical UI-surface override did not fire (no
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` in Files to
Create/Edit).
**Decision:** N/A (no UI surface)
**Pencil available:** N/A (no UI surface)

## Open Code-Review Overlap

Two open code-review issues touch planned files:

- **#2349** (`qa/SKILL.md` — port-probe fallback + ESM loader cache): **Acknowledge** — disjoint concern; this plan edits the Playwright-MCP prescription region only. Left open.
- **#4133** (`plan/SKILL.md` — Observability-block schema parity test): **Acknowledge** — disjoint concern; this plan edits the `mcp__playwright__*` routing literal only. Left open.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue/spec) | Codebase reality | Plan response |
|---|---|---|
| Cited plan `plans/2026-09-14-…-plan.md` | Archived at `plans/archive/20260914-230848-…` | Cite the archive path |
| "11 prefix lines across 5 skill files" | 13 lines / 5 files today | Sweep enumerated per-file (Phase 2.1) |
| "plugin.json registers no Playwright server" | True for `plugin.json`; additionally no `plugins/soleur/.mcp.json` exists (CLO audit row 18) | Both registrations surfaces considered; `.mcp.json` chosen |
| "it collides with an operator's own `playwright` entry (two servers, one profile lock)" | Tool namespaces cannot collide (`mcp__plugin_soleur_playwright__*` vs `mcp__playwright__*`); the REAL collision is the browser profile dir | Dedicated `--user-data-dir-name` profile; orphan-server learning cited |
| "auto-wrap the user's existing entry" is an available mechanism | No manifest mechanism exists; only config-mutation hooks could approximate it | Cut; Option C (hook interception, transcript-only) deferred with criteria |

## Deferrals

- **Option C — plugin PostToolUse/PreToolUse hook net on `mcp__playwright__.*`**
  (transcript-only coverage of a customer's own unwrapped registration).
  Deferred per the Alternatives table; filed as **#8286** (`deferred-scope-out`,
  `domain/engineering`, `type/security`) — the AC9 deliverable, carrying the
  re-evaluation criteria and the note that
  ADR-162's one-rewriter rule does not constrain it (it constrains
  `updatedInput` rewrites on PreToolUse, not `updatedToolOutput` on
  PostToolUse). Deepen-pass: upstream #47859 (hook output silently
  discarded) and #24788 (`additionalContext` dropped for MCP events) are
  both CLOSED — the deferral stands on coverage scope (transcript only,
  never disk sinks), not mechanism viability; the deferral issue should say
  so explicitly so a future evaluator does not re-derive it.

## References & Research

- Issue: #8156 (parent: #7980; ADR: `knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md`)
- Prior plan: `knowledge-base/project/plans/archive/20260914-230848-2026-09-14-feat-playwright-mcp-snapshot-redaction-proxy-plan.md`
- Prior spec artifacts: `knowledge-base/project/specs/feat-one-shot-7980-playwright-mcp-snapshot-redaction-proxy/` (probe-record convention reused)
- CLO attestation: `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` (row 18; re-append rule for reach (b))
- Orphan-server learning: `knowledge-base/project/learnings/workflow-patterns/2026-07-05-playwright-mcp-orphan-server-profile-lock-contention.md`
- External: code.claude.com/docs/en/mcp-servers (plugin `.mcp.json` + `${CLAUDE_PLUGIN_ROOT}` substitution); anthropics/claude-code#36914, #54161, #47859, #24788 (stdio-registration bug class + hook-output semantics)
