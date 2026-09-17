# ADR-224: Slash-name uniqueness across harness component namespaces

- **Date:** 2026-09-17

## Status

Accepted.

## Context

Soleur ships the same component tree to four harnesses that do not agree on how
a component becomes a slash name. Two facts collided.

Claude Code loads plugin **commands** (`commands/*.md`) and plugin **skills**
(`skills/*/SKILL.md`) into one slash menu. A name present on both sides renders
twice. Three names do: `go`, `help` and `sync` exist as canonical commands and,
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
is written.

ADR-215 is the wrong home for that qualification on grounds of **scope**, not of
dating. ADR-215 decides "Codex reuses canonical Soleur components"; the rule
recorded here governs four harnesses' namespaces, two of which (Claude Code,
Grok) ADR-215 never addresses. A four-harness placement rule filed inside a
single-harness ADR is mis-filed whatever its §Verification says.

An earlier draft of this section argued instead that ADR-215 *could not* be
amended because its §Verification is a dated measurement. That is wrong and is
recorded here so it is not repeated: this repo amends accepted ADRs in place as
a matter of course, annotating them with dated supersede blockquotes beside the
stale text (ADR-194 carries six, ADR-213 three). Dated records are annotated
here, not frozen.

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

4. **Command-stem disjointness is asserted over the roots the CLAUDE manifest
   resolves, derived from that manifest rather than restated.** `commands/`
   shares a menu namespace only where a harness has a command surface, so the
   guard reads `.claude-plugin/plugin.json` and asserts over
   `["skills", ...(claude.skills ?? [])]`.

   Per-harness roots are then out of scope *as a consequence*, not as a
   hand-written carve-out: `codex/skills/` and `devin/skills/` are not in the
   Claude manifest. That matters because those roots exist precisely to expose a
   canonical `commands/go.md` on a harness with no command surface — each shim's
   body reads the canonical command and follows it — so asserting disjointness
   there could only be satisfied by breaking the Codex and Devin entry points.

   Deriving rather than hardcoding `"skills"` also keeps the guard correct if
   decision 2 is ever relaxed: a hardcoded root set would silently keep asserting
   over one root and stop covering a newly declared one, going quiet exactly when
   the risk it exists for materialises.

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

Collapsing it means deleting the shared copies. **An earlier version of this
paragraph said `plugins/soleur/skills/go/` is the SOLE model-invocable
`Skill(soleur:go)` handle and that `commands/go.md` is user-typed only. Both are
FALSE on Claude Code, and the correction is recorded rather than silently
applied because the false version was used to justify deferring #8236.**

Measured: with all three shims deleted from a scratch plugin tree,
`claude --plugin-dir <tree> -p '…Skill(soleur:help)…'` still succeeds and returns
`# Soleur Help` — the heading of `commands/help.md`. Commands are model-invocable
and SHADOW the same-named skill, so on Claude Code the command supplies the handle
and the skill sits behind it as a fallback.

What remains true, harness-qualified per decision 1: the OTHER three harnesses do
resolve these paths — `devin skills list` reports `/soleur:go` from both roots,
`.codex-plugin` declares `./skills`, and `.grok/config.toml` loads this tree. So
deleting the shims is a real change on three harnesses that Claude Code happens to
absorb. `server/prompt-injection-wrap.ts` does dispatch `Invoke /soleur:go` on
every Command Center message and `server/soleur-go-runner.ts` does key
sticky-workflow detection on `toolName === "Skill"` — both verified — but neither
depends on the SKILL file, because the command answers that dispatch. The ack is
by name, so the condition is guarded rather than invisible.

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
reds via decision 2, and — because decision 4 derives its root set from that
same manifest — would additionally bring the declared root inside clause (b)'s
scope rather than leaving it unasserted. Adding `devin/skills/review/` reds via decision 5 naming
`review`, which proves the ack does not blind the clause. Emptying discovery
reds against a bounded floor rather than passing over an empty corpus.

`commands/flag-bootstrap.md` is the must-PASS row: `skills/flag-bootstrap/` holds
no `SKILL.md`, so it is not a skill and this is not a collision. It pins the
loader's own derivation rule and proves the guard does not over-reject.

Per-harness discovery, stated at the strength the evidence actually carries.

**Devin — measured.** `devin skills list` reports `/soleur:go`, `/soleur:help` and
`/soleur:sync` from `skills/` **and** `devin/skills/`, each `[user,model]`. That is
decision 5's condition observed live on a real harness.

**Grok — measured.** `grok inspect` reports the soleur plugin at **98 skills** both
with and without `user-invocable: false` present (branch vs `origin/main`), so
Grok's loader does not act on the key: it cannot break Grok's `/go`, and Grok keeps
whatever duplication it had. Caveat: the `origin/main` reading was taken in a fresh
clone, which Grok reports as an untrusted `(project, disabled)` plugin; the skill
COUNT is what is being compared and it is identical.

**Codex — inferred, NOT measured.** An earlier version of this section cited
`node scripts/codex-plugin-smoke.mjs` reporting "101 skills" as live proof. That
figure is `expectedSkills`, which the script computes locally as the 98 `SKILL.md`
directories plus an unconditional `push("go","help","sync")` — three names already
in the 98 — before it contacts Codex at all. Only `discoveredSkills` would prove
anything, and nothing in the repo captures it. Codex's additive-vs-replace
behaviour here rests on the manifest declaring `./skills` explicitly, which is
inference from configuration, not measurement.

ADR-215's `98` figures are a dated record of a 95-canonical tree and are left
unchanged.

**Scope of the dedup claim.** Decision 3 is verified for **Claude Code**, whose
frontmatter key this is.

**Grok is in the same collision class and is now MEASURED — see §Verification.** `.grok/config.toml`
points at this same `plugins/soleur` tree, so Grok has Claude Code's shape — the
default `skills/` root, a live command surface, one namespace, and no
per-harness root, hence no decision-4 exemption. `/go` duplicates there for the
same reason it duplicated in Claude Code, and whether Grok honours
`user-invocable: false` was probed with `grok inspect`: 98 skills with the key and
98 without, so the key changes nothing there. Naming this is decision 1 applied
to this ADR itself: a placement rule that silently drops one of the four
harnesses it governs is the "not checked collapsed into not applicable" failure.
The exposure is bounded — if the key is ignored, Grok keeps today's duplicate and
nothing regresses, which the measurement confirms. Decision 4's derived root set is
correct for Grok by the same mechanism — `.grok/config.toml` sets
`paths = ["./plugins/soleur"]` and symlinks the tree — though that Grok reads
`.claude-plugin/plugin.json` specifically is unverified. Whether Devin honours `user-invocable: false` is
UNMEASURED: the `devin skills list` reading above was taken against a pre-PR
plugin cache, so it shows the duplication but cannot show the fix. Re-run
`devin skills list --trigger user` after a `devin plugins install` refresh to
settle it. If Devin honours the key, its double-resolution of these three names
closes as a side effect; if not, it persists and the decision-5 ack keeps doing
real work.
