# The reason I deferred was the one claim nobody measured

- **Date:** 2026-09-17
- **PR:** #8233 · **Follow-up:** #8236
- **Category:** workflow-patterns

## Problem

A three-line frontmatter fix (`user-invocable: false` on three duplicate plugin
skills) shipped with an ADR, a standing guard, and a deferred follow-up. The fix
was right. Almost everything asserted *around* it was not, and the two defects
that mattered were both in claims that justified **not** doing something.

## The two classes, neither of which the corpus covered

### 1. A claim that justifies a DEFERRAL gets none of the scrutiny a claim that justifies a CHANGE gets

This sentence was written into ADR-224, a test failure message, a guard comment,
four commit messages and a GitHub issue:

> `plugins/soleur/skills/go/` is the sole model-invocable `Skill(soleur:go)`
> handle; `commands/go.md` is user-typed only.

It was the entire stated reason #8236 was deferred — deletion "would break the
Command Center dispatch path". One probe falsified it:

```bash
cp -r plugins/soleur /tmp/probe && rm -rf /tmp/probe/skills/{go,help,sync}
claude --plugin-dir /tmp/probe -p 'Invoke the Skill tool once with skill="soleur:help" …'
# -> "# Soleur Help"   (the heading of commands/help.md)
```

With all three skills deleted, the dispatch still resolved. **Commands are
model-invocable and shadow same-named skills**, so the command was supplying the
handle the whole time.

The asymmetry is the lesson. Every gate in this repo points at claims that
license an action — plan-quoted numbers get re-derived, measurements get
verified before they propagate, a fix's assertions get mutation-tested. Nothing
points at the claim that licenses *inaction*, because deferring feels like the
conservative choice and its justification reads as caution rather than as an
assertion. It is an assertion, it had five carriers, and it survived a plan
phase, an implementation phase and two design-review seats before anyone ran the
one command that settles it.

**Gate:** when a deferral, a scope-out, or a "blocked on X" rests on a claim
about how the system behaves, name the command that would falsify it and run it
*before* filing. If the answer is "nobody can run that", say so in the filing
rather than stating the claim flatly.

### 2. A fixture that passes is not a fixture that discriminates

A review found `.sort()` → `.reverse()` surviving with the suite green. I wrote a
fixture specifically to kill it:

```ts
commandNames: ["zeta-cmd", "alpha-cmd"],
skills: [inv("zeta-cmd"), inv("alpha-cmd")],
expect(r.commandCollisions).toEqual(["alpha-cmd", "zeta-cmd"]);
```

Re-run, the mutation **still survived**. Encounter order is `zeta, alpha`, so
`.reverse()` yields `alpha, zeta` — which is exactly the sorted answer. The
fixture asserted the right thing and could not tell the two implementations
apart. It passes under both.

Inserting the names *already sorted* makes them diverge, and the mutation then
fails 2. The general form: for any fixture written to kill a specific mutation,
ask **what does the mutated implementation return for this input** — not "is my
expected value correct". Ordering, identity and idempotence properties are the
ones where a plausible input accidentally satisfies both branches.

This is the mutation-testing analogue of a known class (an assertion satisfiable
by the correct answer *and* by a broken one), but at the fixture layer, where no
amount of mutating the implementation can surface it — the gap is in the input.

## Measured platform fact, recorded because nothing in the repo had it

On Claude Code, for a plugin shipping both `commands/<n>.md` and
`skills/<n>/SKILL.md`:

| | User-typed `/soleur:n` | Model `Skill(soleur:n)` |
|---|---|---|
| Both present | command | **command** (shadows the skill) |
| Skill has `user-invocable: false` | command | command |
| Skill deleted | command | command |

The skill is a fallback *behind* the command on both paths, not a separate
handle. `user-invocable: false` removes the duplicate `/` menu row and changes
neither column.

## Deliberately NOT written up

Checked against the corpus first; these were all already covered, and restating
them would add near-duplicates:

- a guard whose name quantifies over more than its assembly collects — 3 files
- a red control voiding a mutation battery — 14 files
- an errored gate reading like a clean one (`rc=2` from argparse) — 1 file
- bare-token vs anchored greps, and narrower-pattern refutations — documented,
  and this session hit both *from the reviewer's side*: two agent findings were
  themselves wrong in exactly those two ways

## Session Errors

1. **Asserted a platform behaviour five times without probing it once.**
   Recovery: probed it; retracted in place with the measurement in all five
   carriers rather than quietly editing. Prevention: class 1 above.

2. **Wrote a fixture to kill a mutation; the mutation survived the fixture.**
   Recovery: re-ran every closed row against a valid control and caught it.
   Prevention: class 2 above — re-run the mutation after adding its fixture, and
   treat "the fixture passes" as no evidence at all.

3. **Ran a re-closure battery against a red control.** The sandbox copied only
   `plugins/` and `scripts/`, so the suites failed to collect and the control
   read `0 pass / 2 fail`; all eight rows under it were meaningless. Recovery:
   discarded unread, redone in place with a pristine backup. Prevention: already
   corpus-documented — read the control first, always.

4. **Read `rc=2` from two repo lints as a result.** It was an argparse usage
   error from passing file arguments to tools that scan the repo themselves.
   Recovery: re-invoked correctly; both clean. Prevention: already documented.

5. **Cited a locally-computed constant as a live third-party measurement.**
   ADR-224 claimed `codex-plugin-smoke.mjs` reporting "101 skills" proved Codex
   resolves both roots; that figure is `expectedSkills`, computed as 98
   directories plus an unconditional push of three names already among the 98,
   before the script contacts Codex. Recovery: downgraded to "inferred, not
   measured". Prevention: for any cited number, name which variable in the
   producing script it is.

6. **Two missing dev dependencies each voided a whole gate run.** `bun` absent
   meant the plugin suite silently did not run; PyYAML absent produced 43 failing
   suites that read as a broken diff. Both were environment. Recovery: installed
   both (pinned `bun@1.3.14` from `.bun-version`; `pip3 install pyyaml` per the
   repo's own cutover workflow), re-ran clean. Prevention: below.

7. **Combined a file write with a hook-gated `gh issue create` in one Bash
   call.** The gate denied the call, so the write never ran and the retry failed
   on a missing file — the exact trap `work/SKILL.md` documents. Recovery: split
   into separate calls. Prevention: already documented; I had read it.

## Tags

category: workflow-patterns
module: plugins/soleur/test, knowledge-base/engineering/architecture/decisions
