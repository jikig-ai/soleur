---
name: harvest-debt
description: "This skill should be used when harvesting inline SOLEUR-DEBT: markers from the codebase into a ledger grouped by file, flagging markers with no upgrade trigger."
---

# Harvest Inline Deferral Markers

Read-only harvester for inline `SOLEUR-DEBT:` deferral markers. It makes the
deliberate shortcuts left in code grep-discoverable so a deferral cannot quietly
become permanent. It complements — never duplicates — the reactive
[technical-debt ledger](../../../../knowledge-base/project/learnings/technical-debt/README.md):

- **harvest-debt (this skill)** — SURFACE inline markers where they live, in code.
- [/soleur:compound](../compound-capture/SKILL.md) — PROMOTE a worth-tracking marker into a ledger entry.
- [/soleur:resolve-debt](../resolve-debt/SKILL.md) — CLOSE a ledger entry with a linked GitHub issue.

It writes nothing and closes nothing; promotion and closure stay deliberate acts.

## The marker convention

A deliberate shortcut is annotated inline, in a code comment, with the ceiling it
tops out at and the observable trigger that says "do the real thing now":

```text
// SOLEUR-DEBT: <ceiling>; <upgrade trigger>
```

- Use the all-caps `SOLEUR-DEBT:` marker — never a bare `soleur:` prefix, which
  collides with skill references like `soleur:go` throughout the docs.
- The text before the first `;` is the **ceiling** (the shortcut / current limit);
  the text after is the **upgrade trigger**.
- Example: `// SOLEUR-DEBT: global lock; switch to per-account locks if throughput matters`.
- A marker with no `;`-delimited trigger is the rot-prone case — the harvest flags
  it `no-trigger`.

This marker is the canonical, grep-discoverable form of the in-place deferral that
the `wg-when-deferring-a-capability` gate prefers over filing speculative backlog
issues. Document a deferral here, in code, and harvest makes it visible without
converting every shortcut into phantom backlog.

## Run

```bash
bash plugins/soleur/skills/harvest-debt/scripts/harvest-debt.sh
```

Run from the repo root. The harvester ([harvest-debt.sh](./scripts/harvest-debt.sh)):

1. Greps tracked source for `SOLEUR-DEBT:` markers.
2. Groups hits by file and splits each on the first `;` into ceiling + trigger.
3. Flags any marker with no trigger as `no-trigger`.
4. Prints a markdown report ending with `<N> markers, <M> with no trigger.`, or
   `No SOLEUR-DEBT markers found.` when the tree is clean.

`--help` prints usage. The script is idempotent and read-only.

## After harvesting

For each surfaced marker, decide:

- **Worth tracking** → run [/soleur:compound](../compound-capture/SKILL.md) to promote it
  into a `technical-debt/` ledger entry, then [/soleur:resolve-debt](../resolve-debt/SKILL.md)
  to close it with a linked issue once the upgrade trigger fires.
- **`no-trigger`** → add the missing upgrade trigger to the comment, or delete the
  marker if the shortcut is now permanent and accepted.

## Scope (and its one limitation)

The harvest scans CODE comments only. Prose (`*.md` — the convention doc, plans,
specs, SKILL bodies), `node_modules`, and build output (`_site`, `dist`, `*.min.*`)
are excluded so the marker DEFINITION never self-reports as debt. This is a **path
denylist, not a semantic check**: a `SOLEUR-DEBT:` literal placed in a non-`.md`
source file purely as documentation would still be reported. Keep marker examples
in markdown.
