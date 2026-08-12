# Phase 1 — Loader-substitution measurement (ADR-179 §R3 halt gate)

Date: 2026-08-12. Session: `/soleur:go` → `soleur:one-shot` → `soleur:work`, Claude Code CLI,
plugin installed at `/home/jean/git-repositories/jikig-ai/soleur/plugins/soleur`.

**VERDICT: POSITIVE for the measured construction.** Proceed to Phase 2.

## What was measured

The question ADR-179 §R3 left as "CORROBORATED, not proven": does the plugin loader substitute
a **bare** `${CLAUDE_PLUGIN_ROOT}` in plugin markdown, such that the token never reaches bash as
a shell variable?

### Arm 1 — bare token, COMMAND surface, fenced `bash` block. SUBSTITUTED.

Committed source, `plugins/soleur/commands/go.md` (Step 0.0 fence):

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"; then
  bash "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/git-repo-readiness-diag.sh" 2>&1
```

Text as **delivered to the agent** by the loader in this session:

```bash
if [ -f "/home/jean/git-repositories/jikig-ai/soleur/plugins/soleur/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "/home/jean/git-repositories/jikig-ai/soleur/plugins/soleur/.claude-plugin/plugin.json"; then
  bash "/home/jean/git-repositories/jikig-ai/soleur/plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh" 2>&1
```

### Arm 2 — shell baseline. UNSET.

```
$ echo "[${CLAUDE_PLUGIN_ROOT:-<UNSET>}]"
[<UNSET>]
$ env | grep -i claude_plugin
(no output)
```

**The inference Arm 1 + Arm 2 license, and it is the load-bearing one:** substitution is a
**loader text-transform performed before the text is ever executed**, not a shell expansion. The
delivered command text carried the absolute installed root *while the shell environment had no
such variable at all*.

### Arm 3 — negative control: the `:-` form is NOT substituted. SKILL surface.

`one-shot/SKILL.md` and `work/SKILL.md` were delivered in this same session carrying
`${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` **literally, unsubstituted**.

Two things follow. (a) The transform is **exact-literal on `${CLAUDE_PLUGIN_ROOT}`** — which is
the empirical confirmation of ADR-179's rejection of option (b) `:?` and option (d) `:-` ("not
the literal token, so it is never substituted"). That reasoning was previously an argument; it is
now measured. (b) The transform pass demonstrably **runs over SKILL.md text** — it examined this
text and correctly declined a non-matching literal.

## Arm A / Arm B collapse — the plan's F14 concern is dissolved, not merely mitigated

Plan finding F14 worried that the identity preflight "halts on an unset variable *regardless* of
whether the loader substitutes correctly inside a fence", making Arm B (plain monorepo session,
variable unset) a second independent unknown.

**Measurement dissolves this.** Because substitution happens at delivery, there is no
"unset variable" state at the point the preflight executes: the preflight's own text already
carries the absolute root, so it stats a real file. The shell environment being unset — which
Arm 2 confirms it is, in exactly this repo's own operator session — is irrelevant to the
delivered text. Arm A and Arm B are the same arm.

This is also why `/soleur:go`'s Step 0.0 gate ran successfully in this very session with the
shell variable unset.

## Residual — stated, not hidden

The **direct** bare-token-inside-a-SKILL.md arm was attempted and could not be executed. A
throwaway skill (`zzz-probe-7450`) carrying a bare token in a fenced `bash` block was written
into the live plugin root and invoked; the Skill tool returned `Unknown skill:
zzz-probe-7450`. The skill registry is built at session start, so a mid-session addition is not
discoverable. That arm requires a fresh session. The probe was removed immediately
(verified absent).

The SKILL-surface bare-token claim therefore rests on Arm 3 (the transform pass runs over
SKILL.md text) plus the two independent precedents below — not on a direct execution.

**§R3 is upgraded to "proven for the measured construction"** — a bare token, in a fenced `bash`
block, in plugin markdown on the command surface — **never to "proven" flatly**, per the plan's
§Sharp Edges.

## Correction to the plan's evidence list (a defect it did not catch)

The plan's §"Is the bare anchor safe for the CLI operator?" retracted evidence item 3
(`preflight`/`review` SKILL.md) as **circular**, because both landed in `98ad03aa8` — the ADR-179
commit. Measured here: **evidence item 2 has the identical defect and was not retracted.**

```
$ git log -1 -S'${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json' -- plugins/soleur/commands/go.md
98ad03aa8 2026-08-11 fix(sync): anchor plugin producers to the bare plugin root ...
```

`commands/go.md` and `commands/sync.md` are **not** independent corroboration either — they are
the same commit as the ADR that cites them.

**The genuinely independent precedents are these two, and the amendment should cite these
instead:**

| Precedent | Date | Independent? |
| --- | --- | --- |
| `plugins/soleur/hooks/hooks.json` — 3 bare `${CLAUDE_PLUGIN_ROOT}` command paths | **2026-04-03** (`6893c7941`, #1480) | **Yes** — 4 months before ADR-179. And its hooks **fired successfully in this session** (SessionStart rules-loader: `loaded: 103 of 103 rules`) with the shell variable unset. |
| `learnings/implementation-patterns/2026-02-22-bundle-external-plugin-into-soleur.md` — "`${CLAUDE_PLUGIN_ROOT}` is expanded by the plugin loader in **all command/skill text**, not just `!` blocks" | **2026-02-22** | **Yes** — ~6 months before ADR-179, and names the skill surface explicitly. |

## Why a negative would not have changed the security conclusion

Recorded for completeness, since the halt gate exists to catch it: under no-substitution the bare
form expands to a root-anchored `/skills/incident/scripts/redact-sentinel.sh`, which does not
exist, so the `[[ -r ]]` guard fails and the gate halts at its documented exit 2. For a control
whose exit code authorises secret emission, **refusing is the correct unresolved-root outcome**.
The negative branch would have changed the operator-experience calculus and the amendment's
claims — not the direction of the fix.
