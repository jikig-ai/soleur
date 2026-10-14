# B1 disposition — the root-outside-worktree assertion is NOT implemented

Review finding **§B1** prescribed adding, at all three secret gates:

```bash
case "$(cd "${CLAUDE_PLUGIN_ROOT}" && pwd -P)/" in "$(git rev-parse --show-toplevel 2>/dev/null)/"*) halt;; esac
```

**Verdict: do not implement.** The finding's *diagnosis* of the preflight is correct — manifest
plus name is a shape check, and a `gh pr checkout` tree satisfies it byte-for-byte. Its
*prescription* is wrong, because it guards an operand the adversary cannot reach at the migrated
sites, and it pays three real costs to do so.

This is a scope reduction settled by measurement, not a deferral. It is recorded here because it
contradicts a P1 finding from a 10-agent panel, and that contradiction must be auditable.

## Why the vector B1 names does not reach the migrated sites

§B1's residual is the *ambient*-`CLAUDE_PLUGIN_ROOT` vector — direnv, `.bashrc`, a hostile
`postinstall`. [`phase-1-measurement.md` Arm 4](./phase-1-measurement.md) executed it directly:

- The loader substitutes a bare `${CLAUDE_PLUGIN_ROOT}` **on the skill surface**, at delivery,
  before the text reaches bash.
- The value it substitutes is the **install path**, not the environment. A decoy
  `CLAUDE_PLUGIN_ROOT=/tmp/DECOY-EVIL-ROOT` was live in the same Bash subprocess that ran the
  fence (`ENV_GREP=[1]`) and was ignored.

So at a migrated site there is **no shell variable to poison** — the path is a literal fixed by the
trusted loader. `case` would test a constant against a constant.

The same session reproduced the *pre-fix* form resolving to
`/tmp/DECOY-EVIL-ROOT/skills/incident/scripts/redact-sentinel.sh`. That is what this PR closes, and
it is closed by the migration itself, not by any added assertion.

## Surface map — all three delivery surfaces, measured or stated

| Surface | Resolution at a migrated gate | Ambient poisoning |
| --- | --- | --- |
| **Claude Code CLI** | loader substitutes a literal at delivery; env decoy demonstrably ignored | **No** — no operand exists |
| **Concierge / hosted** | `agent-env.ts` injects the per-dispatch platform path, validated by `assertTrustedPluginPath`, and is **deliberately excluded from `AGENT_ENV_ALLOWLIST`** precisely so an ambient `process.env.CLAUDE_PLUGIN_ROOT` cannot leak in | **No** — blocked in server code |
| **Grok Build** | no `CLAUDE_PLUGIN_ROOT` handling in `plugins/soleur/lib/harness.ts` or `.grok/` | **Unmeasured residual** — stated, not closed |

On the two measured surfaces the operand is untouchable. On the unmeasured third, `case` is still
the wrong instrument — see cost 1, which lands hardest on exactly the population that runs it.

## The three costs

1. **It breaks dogfooding on any plain clone.** On a normal `git clone` of this repo the plugin
   root *is* inside the working tree, so the assertion halts every invocation.
   *(Corrected at round-2 review: it appeared to pass on the machine where §B1 was measured
   because review runs in a **linked worktree** whose toplevel does not contain the install path —
   NOT because that install root is **bare**, which the first draft claimed. An ordinary non-bare
   clone using `.worktrees/` passes on the review path too. The conclusion is unaffected: a session
   rooted at the clone top level, which is the common entry point, halts on every invocation.)*
2. **It reintroduces the banned construct into the exact files this PR de-git-roots.** The three
   gate files carry **zero `git rev-parse` in executable (fenced `bash`) positions** — the single
   textual occurrence is the prose *documenting* the ban, which is why Test 21 is fence-scoped.
   *(An earlier draft said "zero occurrences", flatly, which is false and contradicted the PR
   body's own correctly-scoped wording.)* `case` puts
   `git rev-parse --show-toplevel` back into all three, forcing the guard to allowlist its own
   subjects — the "guard that must exempt the thing it guards" shape.
3. **It re-adds a CWD-resident trust decision that the binding ruling removed.** The CTO ruling §4
   settled §R1 as: *"not a stronger sentinel but the removal of trust decisions from CWD-resident
   operands."* The bare anchor achieves that. `case` re-introduces a CWD-resident operand
   (`git rev-parse`, resolved against wherever the session happens to sit) in order to
   re-authenticate the tree — the instrument §R1 rules out as unfixable in-tree.

## What is done instead

- **The overstated prose is retracted**, as §B1 itself asks. The preflight is defence-in-depth for
  surfaces where substitution does not govern, not the load-bearing control. The bare anchor is the
  load-bearing control.
- **The invariant is pinned, not merely satisfied.** A guard assertion fixes the three gates at zero
  git-root anchors, so a future literal implementation of §B1 reddens rather than landing quietly.
  This is the constructive half: it converts §B1 from "add a check" into "pin the absence".
- **The Grok residual is stated** here and in ADR-179 §Consequences rather than being claimed away.

## What would reopen this

A delivery surface where a bare `${CLAUDE_PLUGIN_ROOT}` in plugin markdown reaches bash **as a
shell variable**. Grok Build is the open candidate. Re-run
[`phase-1-measurement.md`](./phase-1-measurement.md) Arm 4 against that harness; if it comes back
negative, the operand becomes attacker-reachable there and the disposition must be revisited — with
cost 1 solved first, since a naive `case` would halt every contributor on that surface too.
