# Mutation matrix — plugin slash-name uniqueness guard

Rows M0–M8 walked 2026-09-17 against commit `513133d32` (§round 1); rows S1b–S11 against
the post-review tree (§Round 2); rows M9–M10 at ship time (§Round 3). This line previously
pointed M9–M10 at §Round 2, which never carried rows under those labels. Restore was from a **pristine copy**, not
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
| M1 | remove `user-invocable: false` from `skills/go/SKILL.md` | RED | RED | `user-invocable skills in Claude's roots are disjoint from command stems` | `…render TWICE… : go` |
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

---

## Round 2 — what the round-1 battery could not see

Round 1 reported all-caught. A `test-design-reviewer` pass then found **11 surviving
mutations across 6 axes round 1 never edited**, which is the honest measure of what
that matrix established: it was evidence about the mutations imagined, not about the
tests. Every survivor below was re-run to closure against a control with **0 fails**
(a red control voids every row — the first attempt at this used a partial sandbox,
came back `0 pass / 2 fail`, and was discarded unread).

| # | Axis round 1 skipped | Mutation | Round-1 result | Now |
|---|---|---|---|---|
| S1b | dispatch | comment the whole guard block out (`s/^/\/\/ /`) | GREEN — the guard-presence regex matched `// describe("plugin slash-name uniqueness"` | CLOSED — haystack comment-stripped, cardinality pinned to exactly 1 |
| S2 | dispatch | `for (const name of [])` on the dispatch-handle loop | GREEN, then `skills/go` deletable green | CLOSED — loop derived from `ACKED_CROSS_ROOT_DUPES`, whose membership is pinned |
| S11 | floor operand | point `claudeRoots` at a nonexistent directory | GREEN — the floor read the literal `"skills"`, not the operand clause (b) consumes | CLOSED — floor sweeps every `claudeRoots` member |
| S3 | escape hatch | `declared = []` → every manifest takes the single-root early return | GREEN — the early return emits a PASSING `expect()` | CLOSED — ≥2 manifests must reach the multi-root path |
| S4 | set cardinality | narrow the dirent regex to `.claude-plugin` | GREEN — `>= 1` cannot tell one manifest from all | CLOSED — `manifestDirs` pinned, not floored |
| S6 | identity vs count | `commandNames` + `".md"` | GREEN — three WRONG stems satisfy a length floor | CLOSED — `arrayContaining(["go","help","sync"])` |
| S8 | ack APPLICATION | ack filter → `() => false` | GREEN — the only ack assertion inspected the SET, not the filter | CLOSED — filter extracted as `unackedDuplicates`, fixtured |
| S5 | fixture cardinality | `roots.slice(0, 1)` | GREEN — every clause-(b) fixture had ONE root | CLOSED — two-root fixture with the collision in the second |
| S7 | fixture DIRECTION | exact match → `startsWith` | GREEN — no must-NOT-flag row for an over-aggressive matcher | CLOSED — `alpha-cmd-extra` must not flag |
| S10 | result arity | `.sort()` → `.reverse()` | GREEN — no fixture asserted a 2-element result | CLOSED, on the **second** attempt |
| S9 | dead code | delete the `seen` dedupe in `collidingNames` | GREEN — it was unreachable-in-effect, and a fixture comment claimed otherwise | Dead code removed; the comment corrected |

**S10 is worth its own note.** The first fixture written to close it asserted
`["alpha-cmd","zeta-cmd"]` from encounter order `zeta, alpha` — under which
`.reverse()` coincidentally produces the sorted answer, so the mutation survived a
fixture written specifically to catch it. Re-run with already-sorted encounter
order, it fails 2. A fixture that passes is not a fixture that discriminates.

## Axes still NOT mutated, after round 2

- **The harnesses themselves.** Every row scores the guard. Per ADR-224
  §Verification: Devin's LOADING of both roots is measured; Codex's is inferred; and
  Grok's handling of `user-invocable: false` is **unmeasured** — the `grok inspect`
  reading compares skill counts, which the key cannot change on any harness, so it
  does not discriminate. No harness has a measured post-fix menu enumeration.
- **Population growth beyond the guarded set** — a structural enumeration found the
  guard reads two of roughly ten paths by which a name reaches a user's menu
  (`commands`/`agents`/`workflows` manifest keys, nested and symlinked components,
  repo-root harness configs). Clause (c) now refuses the three REPLACE keys; the rest
  is filed, not fixed, and ADR-224's property statement is scoped to match.

## Round 3 — ship-phase advisor consult (2026-09-17)

Two rows that went GREEN with the property violated. Both were found by the ADR-083
advisor consult at `/ship` Phase 5.5, both measured before being reported, and both
re-driven here against a GREEN control with a byte-compared pristine restore.

Control M0: **1349 pass / 0 fail**, before and after the battery.

| Row | Mutation | Landed-check | Before fix | After fix |
|---|---|---|---|---|
| M9 | `declared = ["./skills"]` in `rootsFor`, **plus** a real `devin/skills/review/SKILL.md` | `grep -c 'const declared = \["./skills"\];'` = 1; probe dir present | **1348 pass / 0 fail** — clean sweep while `.devin-plugin` resolved `review` from two roots | **1348 pass / 1 fail** — floor test reds |
| M10 | `return;` appended to the live block's opening line | `grep -A1 'describe("plugin slash-name uniqueness"'` shows `return;` | **1338 pass / 0 fail** — ten clauses gone, presence guard green | **1338 pass / 1 fail** — presence guard reds |

**M9 — a floor that measured a different operand than the assertion it backstops.**
`rootsFor` returns `["skills", ...declared]` verbatim; `collidingNames()` normalizes
spellings before comparing. So `["skills", "./skills"]` is ONE directory that counts
as two, and `manifestDirs.filter((d) => rootsFor(d).length >= 2)` was satisfied by a
manifest whose clause (a) took the single-root early return. The floor existed
precisely to stop clause (a) asserting nothing, and could be satisfied while clause
(a) asserted nothing. Fixed by flooring on `new Set(...map(normalizeSkillRoot)).size`.

**M10 — presence is not liveness.** The cross-file guard counted executable
`describe("plugin slash-name uniqueness"` occurrences, so every neutering that keeps
the call syntax survived it. This is the same class as the round-2 comment-stripping
correction, one level up: that fix moved the SEARCH SPACE, this one moves the
PROPERTY. Fixed by scoping to the block's brace extent and asserting a clause floor
(6 static `test(` clauses, which register ~10 tests because three sit in loops) plus
a depth-scoped top-level-`return` refusal.

**A false RED found while fixing M10, worth its own line.** The first version of the
`return` refusal was a flat regex over the block preamble. It reds the UNMUTATED tree,
because the live block defines its `rootsFor` helper above the first clause and that
helper contains an ordinary `return`. A check that reds a healthy guard is the shape
that gets deleted rather than repaired — the refusal is depth-scoped for that reason,
not for tidiness.

### Axes still NOT mutated, after round 3

Unchanged from round 2, plus: no row mutates the brace-walk that scopes M10's clause
count. A brace inside a string or regex literal could unbalance it. The failure is
loud (wrong extent produces a wrong count and reds), so it degrades toward a false
RED rather than a false GREEN, but it is not pinned.
