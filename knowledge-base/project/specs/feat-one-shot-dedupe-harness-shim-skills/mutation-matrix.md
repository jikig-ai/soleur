# Mutation matrix — plugin slash-name uniqueness guard

Walked 2026-09-17 against commit `513133d32`. Restore was from a **pristine copy**, not
`git checkout`: the fix under test was uncommitted while the battery ran, so a checkout
restore would have reverted it and every later row would have scored the defect against
itself.

Each row: apply → assert the mutation **landed** → run → record → revert → verify the
revert restored byte-for-byte. A mutation that does not land reports the BASELINE, which is
indistinguishable from a pass. That check earned its place on the first run: M1's landed-check
was written as `grep -q 'user-invocable'`, which still matched the explanatory *comment* left
behind after the frontmatter line was removed, and the battery refused to continue.

Suites: `plugins/soleur/test/components.test.ts` + `plugins/soleur/test/slash-name-uniqueness.test.ts`.

| # | Mutation | Want | Got | Reddening test | Message |
|---|----------|------|-----|----------------|---------|
| M0 | none (control) | GREEN | GREEN | — | a RED baseline would void every row below |
| M1 | remove `user-invocable: false` from `skills/go/SKILL.md` | RED | RED | `user-invocable skills under skills/ are disjoint from command stems` | `…render TWICE… : go` |
| M2 | create `commands/flag-bootstrap.md` (valid frontmatter) | **GREEN** | GREEN | — | `skills/flag-bootstrap/` holds no `SKILL.md`, so it is not a skill — proves the guard does not over-reject |
| M3 | create `commands/qa.md` | RED | RED | same as M1 | `…: qa` |
| M4 | M3 + `commands/review.md` | RED | RED | same as M1 | `…: qa, review` — reports the whole set, not the first |
| M5 | add `"skills": ["./devin/skills"]` to `.claude-plugin/plugin.json` | RED | RED | `.claude-plugin/plugin.json declares no \`skills\` key at all` | `…key is ADDITIVE…` |
| M6 | create `devin/skills/review/SKILL.md` duplicating `skills/review/` | RED | RED | `.devin-plugin: no skill name is contributed by more than one root` | `resolves these skill names from more than one root: review` |
| M7 | point command discovery at a non-matching glob | RED | RED | `discovers the manifests and components it is asserting over` | bounded floor refuses a clean sweep over an empty corpus |
| M8 | delete the guard's `describe` block | RED | RED | `guard presence > components.test.ts still declares the live slash-name uniqueness block` | reds in the **other** file |

Pristine restore verified after every row.

## Why M6 matters most

`ACKED_CROSS_ROOT_DUPES` exempts `go`, `help` and `sync` from clause (a), because Codex and
Devin each declare two skill roots and all three names live in both. M6 adds a **fourth**
name to that condition and requires a RED, which is what proves the ack narrows the clause
to three names rather than disabling it.

## Axes NOT mutated

Stated plainly, because a battery's value is the number of distinct things it perturbs:

- **Harness-side.** Every row scores the guard, not the harnesses. Whether Devin honours
  `user-invocable: false` is unmeasured here (see ADR-224 §Verification).
- **Fixture direction for clause (a).** No row asserts the clause stays quiet when it should;
  the synthesized fixtures in `slash-name-uniqueness.test.ts` carry that direction instead.
- **The ack's own operand.** No row empties `ACKED_CROSS_ROOT_DUPES` to confirm the clause
  reds without it. M1 covers the equivalent for clause (b).
