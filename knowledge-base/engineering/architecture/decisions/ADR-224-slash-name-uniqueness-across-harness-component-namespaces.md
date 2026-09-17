# ADR-224: Slash-name uniqueness across harness component namespaces

- **Date:** 2026-09-17

## Status

Accepted.

## Context

Soleur ships the same component tree to four harnesses that do not agree on how
a component becomes a slash name. Two facts collided.

Claude Code loads plugin **commands** (`commands/*.md`) and plugin **skills**
(`skills/*/SKILL.md`) into one slash menu. A name present on both sides renders
twice. Three names are: `go`, `help` and `sync` exist as canonical commands and,
since the Devin slash-command work, also as skill shims under `skills/`. `qa`,
which is skill-only, renders once — the control that identifies the mechanism.

The `skills` manifest key does not mean the same thing on every harness, and the
difference is load-bearing rather than incidental:

- **Claude Code** — `.claude-plugin/plugin.json` has no `skills` key. The
  default `skills/` scan always runs, and a declared root would be **additive**
  to it, not a replacement.
- **Codex** — ADR-215 §Verification records the opposite: a single custom root
  **hid** the canonical skills, so the key is **replace-default** there, which is
  why `.codex-plugin/plugin.json` must name `./skills` explicitly alongside
  `./codex/skills`.

Because the semantics differ per harness, a single unqualified rule about
"registering a skills root" is wrong for at least one harness whichever way it
is written. ADR-215 cannot carry that qualification: its §Verification is a
dated record of the Codex replace-default measurement, and an "additive"
addendum would make that document contradict itself.

A second collision class had nothing guarding it. `.codex-plugin` and
`.devin-plugin` each declare **two** roots, and `go`/`help`/`sync` exist in both,
so both harnesses resolve those three names twice today. A guard written only
against commands-vs-skills would be green on that, because `review` — the next
name anyone would add to a per-harness root — is not a command.

## Decision

1. **A component's placement is a claim about which harness menus it appears in,
   and every such claim is harness-qualified.** No rule in this repository may
   say "declaring a skills root is safe" without naming the harness it holds for.

2. **`.claude-plugin/plugin.json` declares no `skills` key at all.** Claude Code
   is the one harness whose default skills scan shares a namespace with
   `commands/`, and it offers no denylist, so the only safe number of additive
   roots there is zero. This is asserted even for a *non-colliding* addition,
   because the next addition is what collides.

3. **A name that must reach the model but not the user's menu is suppressed with
   `user-invocable: false`, not deleted.** The key is documented Claude Code
   frontmatter: it removes the `/` row while leaving the skill model-invocable
   and its description in context. Deletion is not equivalent — `Skill(soleur:go)`
   is dispatched on every Command Center message, and the ADR-113 note beside
   that dispatch records a measured user-facing failure when the skill is out of
   scope.

4. **A per-harness skills root may mirror a command stem, and that is not a
   collision.** `codex/skills/go/` and `devin/skills/go/` exist precisely to
   expose a canonical `commands/go.md` on a harness with no command surface;
   each shim's body reads the canonical command and follows it. Disjointness
   between command stems and skill names is therefore asserted over the **default
   `skills/` root only**, not over per-harness roots — asserting it there could
   only be satisfied by breaking the Codex and Devin entry points.

5. **Within one manifest, no skill name may be contributed by more than one
   root.** Two roots resolving one name is a loader ambiguity for every harness,
   independent of menus. Deliberate exceptions are acked **by name** with a
   reason, never by relaxing the clause.

6. **Manifests are discovered, never enumerated.** The guard scans for
   `plugins/soleur/.*-plugin/plugin.json` by directory entry, so a future
   `.grok-plugin` is covered by construction. Bun's `Glob` does not match
   dot-directories — a `.*-plugin` glob returns `[]`, which would report a clean
   sweep having examined nothing.

## Consequences

The three shims stay on disk and stay model-invocable; the Claude Code menu
shows one row per name. Because nothing is deleted, the skill count stays 98,
the description word budget stays 2442, and the cloud-mode marker fleet is
unchanged — this ADR costs no counter churn.

Decision 5 is satisfied today only with an ack. Codex and Devin each resolve
`go`, `help` and `sync` from two roots, and that is **not** fixed here. It is
measured on both harnesses rather than inferred from the manifests:
`node scripts/codex-plugin-smoke.mjs` reports 101 skills, and `devin skills list`
reports `/soleur:go` from both `skills/go` and `devin/skills/go`, each
`[user,model]`.

Collapsing it means deleting the shared copies, and the blocker is **dispatch,
not discovery**. `plugins/soleur/skills/go/` is the sole model-invocable
`Skill(soleur:go)` handle: `commands/go.md` is user-typed only, `apps/web-platform`
wires no `SlashCommand` tool, `server/prompt-injection-wrap.ts` sends
`Invoke /soleur:go` on every Command Center message, and
`server/soleur-go-runner.ts` keys sticky-workflow detection on
`toolName === "Skill"`. Deleting the shim removes the mechanism on the hottest
path in the product, against the regression ADR-113 already recorded once. The
ack is by name, so the condition is guarded rather than invisible.

Decision 4 draws the boundary that keeps decisions 2 and 5 satisfiable together.
Without it the only way to make the guard green would be to remove the
per-harness shims, which is the outcome decision 3 exists to prevent.

## Verification

The guard lives in `plugins/soleur/test/components.test.ts` under
`describe("plugin slash-name uniqueness")`, over a pure `collidingNames()` in
`plugins/soleur/test/helpers.ts` pinned by synthesized fixtures in
`plugins/soleur/test/slash-name-uniqueness.test.ts`. A cross-file assertion in
that fixture suite fails if the live block is deleted, so the deletion is
detected from outside the file it deletes from.

Walked as a mutation matrix against a pristine-copy restore, with an unmutated
control row and a per-row landed-check (a mutation that does not land reports
the baseline, which is indistinguishable from a pass). Control GREEN. Removing
the key from `skills/go/SKILL.md` reds naming `go`. Adding `commands/qa.md` reds
naming `qa`; adding `commands/review.md` as well reds naming both, so the guard
reports the whole set. Declaring a `skills` key in `.claude-plugin/plugin.json`
reds via decision 2. Adding `devin/skills/review/` reds via decision 5 naming
`review`, which proves the ack does not blind the clause. Emptying discovery
reds against a bounded floor rather than passing over an empty corpus.

`commands/flag-bootstrap.md` is the must-PASS row: `skills/flag-bootstrap/` holds
no `SKILL.md`, so it is not a skill and this is not a collision. It pins the
loader's own derivation rule and proves the guard does not over-reject.

Per-harness discovery is verified mechanically rather than argued, on both
harnesses that declare two roots. `node scripts/codex-plugin-smoke.mjs` reports
101 skills — 98 canonical plus the three Codex wrappers — which is the additive
behaviour decision 4 depends on. `devin skills list` reports `/soleur:go`,
`/soleur:help` and `/soleur:sync` from `skills/` **and** `devin/skills/`, each
`[user,model]`, which is decision 5's condition observed live. ADR-215's `98`
figures are a dated record of a 95-canonical tree and are left unchanged.

**Scope of the dedup claim.** Decision 3 is verified for **Claude Code**, whose
frontmatter key this is. Whether Devin honours `user-invocable: false` is
UNMEASURED: the `devin skills list` reading above was taken against a pre-PR
plugin cache, so it shows the duplication but cannot show the fix. Re-run
`devin skills list --trigger user` after a `devin plugins install` refresh to
settle it. If Devin honours the key, its double-resolution of these three names
closes as a side effect; if not, it persists and the decision-5 ack keeps doing
real work.
