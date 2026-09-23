# Harness-parity gate map

Which gate owns which property, what a RED usually means, and where the remaining
work is tracked. This table lives here rather than in an ADR (ADR-240) because it
changes every time a gate is added, and an ADR is not the home for a table with
that lifecycle.

Soleur ships ONE plugin tree to four harnesses — Claude Code, Grok Build, Codex and
Devin — each with its own invocation syntax and its own tool vocabulary. Every gate
below exists because some part of that tree is read by an agent on a harness the
author was not using.

| Gate | Property | A RED usually means | Tracker |
|---|---|---|---|
| `grok-harness-invoke.test.ts` | Every `skills/*/SKILL.md` carries exactly one canonical Grok invoke block, before the first heading, outside fences | A new skill shipped without the block. The failure message prints the insertion point and the block to paste; `init_skill.py` carries it so new skills are born compliant | #8390 (closed) |
| `harness-tool-map.test.ts` | Every Claude Code tool name a doc uses has a row in BOTH the Codex and Devin `## Tools` tables | A doc started naming a tool neither adapter table translates. Add a row per table, or "no equivalent; report the unsupported gate" | #8318 (closed) |
| `harness-parity-tree.test.ts` + `harness-parity.test.ts` | Every component reference in agent-read prose is the canonical `soleur:<name>` / registry id — skills, commands, the Codex/Devin shims, and `skills/*/references/**` | A harness-specific form (`/plan`, `$soleur:plan`) or a bare agent leaf (dead on Grok) entered the corpus. `harness-parity-census.ts --fix` repairs the mechanical shapes on a clean tree | ADR-226; agent bodies still on #8317 |
| `plugin-root-anchoring.test.ts` (command + secret-gate axes) | No customer-facing command or secret-gate script is reached through a CWD-controllable anchor | Zero tolerance — rewrite as `"${CLAUDE_PLUGIN_ROOT}/…"` with no default | #7450 |
| `plugin-root-anchoring.test.ts` (skills ratchet axis) | The non-gate CWD-controllable anchors cannot GROW | A NEW anchor, or an existing one gaining occurrences. Do NOT add a baseline row — fix the anchor | #7453 owns migrating the existing rows |
| `harness-discovery-smoke.test.ts` + the `harness-discovery` CI job | Codex and Devin, installed hermetically from the checkout, register every skill their manifest's roots declare, with ONE multiplicity mode per run | Exit 1 = a real set or multiplicity mismatch. Exit 3 = UNRESOLVED (CLI absent, install failed, version drift, or a structurally unreadable listing) and is never a pass | ADR-240; #8574 owns promoting the job to required |
| `components.test.ts` (`ACKED_CROSS_ROOT_DUPES`) | Slash-name uniqueness across harness component namespaces | A new cross-root duplicate. The discovery gate above proves REGISTRATION, not uniqueness — this is where uniqueness lives | ADR-224 decision 5; #8236 |
| `devin-cloud-mode.test.ts` | The cloud-mode marker fleet is byte-identical across its curated set | A skill's cloud-mode block drifted | ADR-221 |
| `workflow-fidelity.test.ts` | Grok routing semantics, asserted without reading the invoke block's bytes | The routing contract changed. This is the anchor OUTSIDE the Grok block's own md5 pin | #6320 |

## Vendor-CLI pins

`harness-discovery` drives two third-party CLIs, pinned exactly and asserted at
install time (ADR-240):

| CLI | Pin | Install path |
|---|---|---|
| Codex | `0.156.1` | `npm i -g @openai/codex@<pin>` |
| Devin | `3000.11.1` | `https://static.devin.ai/cli/<pin>/setup.sh` — the top-level `install.sh` leaves `PINNED_VERSION` empty and installs latest |

A pin is stale the day the vendor ships. **#8574 owns the freshness criterion**: a
monthly comparison against `npm view @openai/codex version` and Devin's current
release, before the job is promoted to a required check. The drift is not
hypothetical — this work was planned against Codex 0.155.1 and npm was at 0.156.1
one day later.
