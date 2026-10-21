# OpenCode Adapter — Shape Note (ADR-274 Support Bar)

This shape note records the four-point bar measurements for the OpenCode harness adapter (slice 2).

## 7.1.1 — `/go` classifies the intent as `opencode` (not `unknown`)

Measured in a **live OpenCode session** (this environment):

```json
{
  "detectHarness(process.env)": "opencode",
  "markers": {
    "OPENCODE": "1",
    "AI_AGENT": "opencode",
    "OPENCODE_SESSION_ID": "ses_eb832230dffenhEfi6NEWvyp6P"
  },
  "formatSkillInvocation(plan)": "plan",
  "resolveGoRoute(\"plan\")": {"kind":"skill","skill":"brainstorm"},
  "dispatchGoRoute(plan,... )": {
    "harness": "opencode",
    "tool": "skill",
    "command": "brainstorm",
    "args": "add a --dry-run flag"
  }
}
```

**Conclusion:** Classification is correct and produces OpenCode-specific invocation forms (bare skill id, not the unknown fallback). §1.0/§7.0 in `measurements.md` already record the detection predicate and marker precedence.

## 7.1.2 — One pipeline skill completes its gates end to end

Measured (§12.5): in a hermetic installed adapter session, a model presented with a guard message (`agent-browser snapshot` blocked by the credential guard) **read the block and ran the routed variant, which `completed`**. The end-to-end delivery path exercised the installed plugin module, the generated config, and the canonical guard script; the model corrected its course and completed the routed call.

This constitutes an end-to-end execution through the plugin's guard path to completion (a pipeline-adjacent completion observed in the live message stream).

**What this does not demonstrate (added at review, 2026-10-19):** a full pipeline skill running *its own* gate sequence on OpenCode — e.g. `/go <task>` through `plan` → `work` → `review` → `ship`. The capture above is one routed call completing after a guard block, which exercises the guard path but not a skill's internal gates. The probe host carries no provider credentials for a hermetic OpenCode session, so the full run cannot be reproduced there. The support-bar point is ticked on the substituted evidence, disclosed rather than restated as full: live reproduction is tracked in #10591 item 1.

**Live reproduction (2026-10-21):** the full gate sequence was reproduced on a credentialed host — see §7.1.6.

## 7.1.3 — One agent spawn runs, or is refused in words (never silently absent)

**Scope of this capture (added at review, 2026-10-19):** the JSON below is `spawnAgent()`'s returned dispatch — the tool name, id and prompt a live spawn would carry — plus the generated stubs' `mode: subagent` field. A live `subagent` invocation was not observed on the wire: that needs a model request, and this host has no credentials for a hermetic session. Tracked with §7.1.2 in #10591 item 1.

**Live reproduction (2026-10-21):** live `subagent` dispatches — including the literal `engineering/cto` spawn — were observed on a credentialed host — see §7.1.6.

Measured (live session, harness.ts dispatch):

```json
{
  "spawnAgent(cto)": {
    "harness": "opencode",
    "tool": "subagent",
    "agent": "engineering/cto",
    "prompt": "... (includes canonical agent path + opencode/INSTRUCTIONS.md)"
  }
}
```

The runtime returns the OpenCode form: `subagent` tool with `subagent_type` `engineering/cto` (path-derived). The generated stubs carry `mode: subagent`, which the INSTRUCTIONS require (§3.0). The presence of the correct spawn form is the structural evidence the path exists and is reachable; refusal-in-words was observed for unsafe actions (§12.5).

## 7.1.4 — Both guards fire (credential and destructive-command)

Measured (§12.5):
- `agent-browser snapshot` → `shell` returned `permission.rejected` from the browser-snapshot-credential-guard; the model reacted to the block and completed the routed variant.
- `terraform destroy` → `shell` stayed `status:"running"` (the guard's `ask` effect held open, awaiting a person). This is the **destructive-command guard** firing with `effect="ask"` (not downgraded to allow; per D10 the ask is a real blocking prompt).

The guard dispositions ledger is in `.claude/hooks/opencode-dispositions.tsv` (13 rows, Phase 3), and both guards are present and reached via the installed adapter.

## 7.1.5 — Evidence captured

Evidence sources:
- `knowledge-base/project/specs/feat-opencode-harness/measurements.md` §1.0, §6.6, §11.1–§11.6, §12.1–§12.8
- `knowledge-base/project/specs/feat-opencode-harness/SHAPE-NOTE.md` (this file)
- `.claude/hooks/opencode-dispositions.tsv` (Phase 3 guard dispositions)
- Live detection output above (in-session probe)
- Test suite: `harness.test.ts` (50/50), `harness-parity(+tree)` (474/474), `harness-tool-map.test.ts` (7/7), `opencode-adapter-drift.test.ts` (16/16) — 547 pass in the targeted parity/drift set

All four points are measured. No public claim of "support" is made here; this note quotes the bar as required by ADR-274.

**Date:** Mon Oct 19 2026

## 7.1.6 — Live reproduction of the two substituted points (2026-10-21)

Added per #10591 item 1's closing action ("quote both captures in SHAPE-NOTE as a new dated section"). Both points that rested on substituted evidence (§7.1.2, §7.1.3) were reproduced live on a host with provider credentials: OpenCode v2.1.1, adapter installed `bun plugins/soleur/scripts/install-opencode-adapter.ts` on 2026-10-20 21:14:39 (74 written; `install-opencode-adapter.ts --check` → `opencode-install ok`, rc=0).

### Capture 1 — §7.1.2: pipeline gates end to end

Parent session `ses_ea52a8fc0ffeRai0PcxRs6eVC6` (OpenCode session store; directory = the soleur checkout) ran the `/go` feature-work path — which dispatches `one-shot` — to completion: planning-phase child session → worktree implementation → 5-seat review panel → ship.

- PR #10725's body carries the pipeline's own gate artifacts: the `<!-- Maintained by the /one-shot pipeline. -->` marker, the `screenshot-gate.mjs` PASS row (critical-css, 20 routes; caught and fixed a 320px overflow on `/getting-started/`), and the brand-survival self-review row.
- Six PRs shipped through this path after the install — #10722, #10725, #10726, #10727, #10735, #10738 (plus #10679) — branches `feat-one-shot-*`, all merged.

### Capture 2 — §7.1.3: live agent spawns

`subagent` tool-call records from the same parent (`state.status: "completed"` in `session_message` rows):

| agent id dispatched | result |
| --- | --- |
| `engineering/review/security-sentinel` | completed (child session, `parent_id` set) |
| `engineering/review/pattern-recognition-specialist` | completed (child session) |
| `engineering/review/code-quality-analyst` | completed (child session) |
| `engineering/review/architecture-strategist` | completed (child session) |
| `engineering/research/git-history-analyzer` | completed (child session) |
| `general` ×2 (incl. the one-shot planning phase) | completed (child session) |
| `build` ×4 | completed |

Literal `engineering/cto` spawn per #10591 item 1's recipe, captured 2026-10-21 09:46 in session `ses_eb832230dffenhEfi6NEWvyp6P` (the §7.1.1 evidence session): dispatch `ses_ea29339b4ffeRVkyRTd5K3K20H`, `parent_id` recorded, status `completed`. The dispatch replied: "Confirmed: I received this dispatch as a subagent spawned in an OpenCode session with the Soleur plugin loaded, using the `engineering/cto` agent id."

Disclosure: the five review-agent spawns are from the shipping sessions; the `engineering/cto` dispatch was captured separately (2026-10-21) to match this item's recipe literally — no `engineering/cto` dispatch occurred in the shipping sessions.

### What this retires

The substituted-evidence caveat for §7.1.2/§7.1.3. With §7.1.1 and §7.1.4 already live-measured, all four ADR-274 points now rest on live captures. Per ADR-291 §Status, the public "supports OpenCode" claim unblocks — its flip is a separate, deliberate change.

**Date:** Wed Oct 21 2026
