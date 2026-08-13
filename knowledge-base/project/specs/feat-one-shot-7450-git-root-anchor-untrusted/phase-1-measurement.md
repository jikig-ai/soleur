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

## Arm 4 — the deferred direct arm, EXECUTED (2026-08-12, review-remediation session)

Review finding **D6** correctly held that Arm 3's inference was logically void: non-substitution
of a *non-matching* literal cannot distinguish "the pass ran and declined" from "the pass never
ran on this surface" — both predict identical bytes. D6 also held that the recorded blocker was
wrong, and it was: a headless `claude -p` builds its own skill registry, so no fresh interactive
session is needed.

**The arm was run. It is POSITIVE, and it is stronger than the inference it replaces.**

Method — a synthetic single-skill plugin outside the tracked tree, loaded via `--plugin-dir`, whose
fence writes the text **as delivered** through a *quoted* heredoc (so bash performs no expansion of
its own and the file records the loader's output, not a model paraphrase):

```bash
CLAUDE_PLUGIN_ROOT=/tmp/DECOY-EVIL-ROOT claude -p \
  --plugin-dir <sandbox>/probe-plugin --allowedTools "Bash,Skill" \
  "Invoke the zzzprobe skill and run its bash block exactly as delivered."
```

| Arm | Delivered / resolved to |
| --- | --- |
| bare `${CLAUDE_PLUGIN_ROOT}/x.sh`, SKILL.md fence | `<sandbox>/probe-plugin/x.sh` — **substituted with the real install root** |
| `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…` , same fence | literal, **unsubstituted** |
| control: runtime env inside the Bash tool | `RUNTIME_ENV_RAW=[/tmp/DECOY-EVIL-ROOT]`, `ENV_GREP=[1]` |
| control: what the `:-` form expands to at runtime | **`/tmp/DECOY-EVIL-ROOT/skills/incident/scripts/redact-sentinel.sh`** |

**Three things this establishes that the inference could not.**

1. **The transform applies to the SKILL surface directly** — not merely "runs over SKILL.md text".
   Arm 3 is superseded, not merely corroborated.
2. **The substituted value comes from the install path, not from the environment.** The decoy was
   simultaneously live in the very subprocess that executed the fence (`ENV_GREP=[1]`) and was
   ignored. So the bare form's operand is **not an environment variable at execution time**; it is
   a literal fixed by the trusted loader before bash ever sees the text. This is the control that
   makes the claim non-confoundable — without it, "ambient ignored" and "ambient never propagated"
   are indistinguishable.
3. **The pre-fix `:-` form expands to an attacker-chosen root** — observed, not modelled. In the
   same session and environment it produced
   `/tmp/DECOY-EVIL-ROOT/skills/incident/scripts/redact-sentinel.sh`.

**Scope of that third claim, stated precisely because an earlier draft overstated it.** It first
read *"a reproduced exploit … it resolved this repo's own redaction gate to an attacker-chosen
root."* Two corrections:

- What executed was a **synthetic single-skill probe plugin** carrying the same construction, not
  `incident/SKILL.md`. The real gate was never run and no script was planted at the decoy path, so
  what was measured is the **expansion**, not an end-to-end compromise.
- The vector reproduced is the **ambient-environment** variant (an attacker exports
  `CLAUDE_PLUGIN_ROOT`). The **`gh pr checkout` git-root** variant — the one #7450 is titled for,
  where `$(git rev-parse --show-toplevel)` becomes the reviewed party's tree — is **not** what this
  arm executed. It remains modelled, and its premise (`review/SKILL.md` instructs `gh pr checkout`)
  is verifiable by reading that file rather than by this measurement.

Both vectors are closed by the same change, because both reach the operand through the removed
default arm. But they are different vectors and only one was run.

**Re-runnable.** The probe is committed at [`arm4-probe/`](./arm4-probe/) rather than described —
`<sandbox>` in the table above was a placeholder path, and a measurement nobody can re-execute is
a claim.

**§R3 is upgraded to "proven for the measured construction" on BOTH surfaces** — a bare token in a
fenced `bash` block in plugin markdown, on the command surface (Arm 1) and on the skill surface
(Arm 4). Still never "proven" flatly: unmeasured delivery surfaces are enumerated in
[`b1-disposition.md`](./b1-disposition.md).

The two independent precedents below are retained — they are no longer load-bearing for the skill
surface, but they remain the evidence that the behaviour predates ADR-179 rather than being
introduced by it.

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
