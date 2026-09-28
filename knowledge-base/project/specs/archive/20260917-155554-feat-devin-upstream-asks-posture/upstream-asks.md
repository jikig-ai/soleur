# Upstream asks to Cognition — Devin Cloud capability parity

**Tracking:** jikig-ai/soleur issue #8160. Parent: #8159 (Soleur Cloud Mode,
shipped via PR #8155). Residual probe arms: #8172.
**Filing channels:** `support@cognition.ai` (all sections); Devin `/bug`
for the defect-class items (Section 3, items 2–4).

**Section-to-filing mapping:**

| Package section | support@cognition.ai | Devin `/bug` |
|---|---|---|
| §1 hook-dispatch parity | yes | — |
| §2 plugin-subagent parity | yes | — |
| §3 items 1, 5, 6 (contract asks) | yes | — |
| §3 items 2–4 (defect-class items) | yes | yes |

**Evidence conventions:** *measured* means observed in a live Devin Cloud
session during a two-arm probe run on 2026-09-15 (a `devin cloud drs` sandbox
session and a user-facing web-app session, both on this repository at `main`).
*Documented* means asserted on `docs.devin.ai` as fetched on 2026-09-17. The
full probe record is committed at
`knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md`;
the capability matrix this filing supports is `plugins/soleur/devin/INSTRUCTIONS.md`
§Cloud Mode. This package states capability deltas only — no session
identifiers, absolute paths, environment values, or personal data beyond the
filing repository identity `jikig-ai/soleur`, which the filing requires (see
the disclosure note at the foot).

---

## Section 1 — Cloud hook dispatch: capability request

*(This section was drafted as a documentation-versus-measurement defect; the
discrepancy resolved as a documentation correction while this package was
being assembled. The timeline is recorded because it is itself evidence.)*

**Timeline.** At probe time (2026-09-15) the docs.devin.ai plugin-ecosystem
page asserted: *"cloud sessions run `command` hooks for every event except
`SessionStart` and `SessionEnd` — including `PreToolUse`, `PostToolUse`,
`PermissionRequest`, `UserPromptSubmit`, `Stop`, and `PostCompaction`"* (the
plugins overview already scoped hooks to local sessions — our own doc sweep
on 2026-09-14 records it reading *"in local Devin sessions (the CLI and Devin
Desktop)"*). Our probe (below) measured zero dispatch — a direct
doc-versus-product discrepancy on the page carrying the broader claim.
Re-fetching the same pages for this filing (2026-09-17) shows the ecosystem
claim **corrected**: both plugin pages now scope hooks to local sessions, and
both warn that plugin hooks are *"best effort and fail open — a hook that
fails to load or run doesn't stop the session — so don't rely on them for
crucial guardrails yet."* The documentation now matches our measurement —
credit for the correction, which also independently validates the probe.

**What we measured** (2026-09-15, both arms agree):

- **Zero hook dispatch on every registry and every event tested.** Neither a
  plugin `hooks.json` hook, nor a repo `.devin/config.json` hook, nor a
  `.claude/settings.json` hook produced any execution. A gitignored
  `.devin/config.local.json` registering `PreToolUse` with `matcher: ""` — a
  catch-all that matches every tool name — wrote a marker file on no
  invocation; the marker was never created.
- **Repo `SessionStart` produced no `additionalContext`.** The repo registers
  a SessionStart hook on `startup|resume|clear|compact`; its injected rule
  corpus was absent from session context. Control: running the same script by
  hand in the same cloud shell with a synthesized SessionStart envelope
  succeeded — the hook script is cloud-capable; the **dispatcher** is what is
  absent.
- Both arms agree the surface is a **no-hook environment**, not a
  degraded-hook one. Probe items: web-app arm items 1, 2, 4, 11, 13, 14;
  sandbox arm items 1, 2, 4, 11, 13, 14 (`cloud-probe.md`).

**Ask:**

1. Dispatch `command` hooks in cloud sessions across all three registries
   (plugin `hooks.json`, repo `.devin/config.json`, `.claude/settings.json`)
   and all hook events, including `PostCompaction`. If only a subset ships,
   please document which registries and which events dispatch.
2. The corrected docs warn hooks are *"best effort and fail open"* — a hook
   that silently does not run is a guardrail that reports healthy while
   absent, which is precisely the failure mode hooks exist to prevent. If
   cloud dispatch ships, please make non-dispatch observable (a surfaced
   signal, not a silent skip) or document the observability boundary.

---

## Section 2 — Feature request: plugin-defined subagents in cloud sessions

**Documented limitation** (both pages, fetched 2026-09-17): *"Subagents
(`agents/<name>.md` or `agents/<name>/AGENT.md`) load in local Devin agents
only (CLI and Devin Desktop), not in cloud sessions."*

**Measured substrate divergence:** the user-facing web-app arm exposes
`run_subagent` (plus `read_subagent` and the `run_workflow` orchestrator), so
a fan-out substrate exists on that cloud surface — but it cannot load
plugin-defined agent profiles. The DRS sandbox arm's tool catalog lacks
`run_subagent` entirely. So:

1. the fan-out substrate itself diverges between cloud surfaces (web-app vs
   DRS sandbox), which is currently undocumented; and
2. on no cloud surface can a session spawn a plugin-defined subagent, so our
   68-agent roster is unavailable in cloud and skills that fan out must
   degrade to sequential inline execution.

**Ask:** support plugin-defined `agents/**/*.md` as subagent types in cloud
sessions, and document which cloud surfaces expose subagent fan-out at all
(the web-app vs sandbox divergence above). If rostered subagents are not on
the roadmap, that answer is also useful — we would rather document a
permanent degradation than a temporary one.

---

## Section 3 — Contract-semantics documentation bundle

These are documentation/contract asks: semantics we could not establish from
docs or measurement. Each is listed with what we observed and what a
documented answer would unlock.

1. **`ask_user_question` in cloud — absent.** The tool is not in the cloud
   tool catalog (sandbox arm item 3); `message_user` (`user_question`) is the
   only interactive primitive and it **blocks indefinitely** when unanswered
   — no timeout, no auto-approve (web-app arm item 3). If an interactive
   question primitive is added to cloud, its unattended semantics need
   documenting: an auto-approve path would silently fail any
   acknowledgement-gated workflow open.
2. **Hook envelope parity.** In the local CLI the tool envelope omits `.cwd`;
   hooks resolve the working directory via `DEVIN_PROJECT_DIR` →
   `CLAUDE_PROJECT_DIR` → `$PWD` (measured locally; a guard that relied on
   `.cwd` resolved the wrong repository — our issue #8254). If cloud hook
   dispatch ships (Section 1), please publish the envelope schema for each
   event so hooks do not have to discover fields by capture.
3. **`permissionDecision` values `"ask"` and `"defer"`.** `"deny"` and
   `updatedInput` are measured live locally; `"ask"` and `"defer"` are
   registered but we have never observed them driven — a hook emitting either
   may be ignored or misrouted. The `PermissionRequest` hook event itself is
   likewise unverified. Please document which decision values and events are
   honored on each surface.
4. **`SessionStart` source matchers.** Locally, `startup`, `resume`, `clear`,
   and `compact` source matchers never dispatch; only the empty matcher `""`
   fires. Please document which matchers are honored per event (this also
   determines whether a cloud SessionStart — if it ever ships — could
   distinguish cold-start from resume).
5. **`requiredPlugins` precedence.** The repo-level key is documented
   (plugins overview, "Inheritance and levels", level 3) as honored "in cloud
   sessions, from each cloned repository". Its marginal effect is unobservable
   on our account because the managed manifest already installs the plugin —
   we cannot tell whether repo-level `requiredPlugins` would install it
   alone. Please document precedence among account manifest, org manifest,
   and repo-level keys.
6. **`PostCompaction` in cloud.** The pre-correction docs listed it among
   cloud-capable hook events; the corrected docs scope hooks to local
   sessions entirely, so its cloud status is now simply undocumented. It was
   never observed — no compaction occurred in the probe window, and no
   dispatcher was observed for any event. Please confirm whether
   `PostCompaction` dispatches in cloud (or will, if Section 1 lands): a
   hook re-emitting context after compaction would materially improve long
   unattended sessions.

---

## Disclosure and data-protection note

- This filing contains **capability deltas only**: no session identifiers,
  absolute paths, environment-variable values, VM internals, or personal
  data. The only organization identifier is the filing repository identity
  `jikig-ai/soleur`, which the filing requires so the request can be routed.
  It was passed through a mechanical scrub gate before submission.
- This filing is **not** framed as a security vulnerability; the hook
  discrepancy is reported as a doc-versus-product defect.
- **DPA disclaimer:** capability-parity request only; any personal-data
  workflows remain subject to a separate Art. 28 DPA. This request does not
  engage Cognition as a processor of personal data; any future processing
  relationship is tracked separately and would be gated on an Art. 28
  data-processing agreement before any personal-data workflow is enabled.
- Delivery of an emailed copy of this document is operator-attested; the
  posting log and any vendor responses are tracked on issue #8160.
