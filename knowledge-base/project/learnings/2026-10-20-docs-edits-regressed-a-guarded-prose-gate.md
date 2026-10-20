# Learning: A docs edit can regress a blocking prose gate the edited file never mentions

## Problem

The install-docs change edited marketing prose across `getting-started.njk`,
`index.njk`, `pricing.njk`, and `llms.txt.njk` to stop framing the self-hosted
version as Claude-Code-only. Every gate the plan named was green —
`sync-readme-counts.sh --check` (rc=0), `marketing-content-drift.test.ts`
(8 pass), the Eleventy build, and the JSON-LD re-parse.

The **blocking** `plugins/soleur/test/seo-aeo-drift-guard.test.ts` suite was
not in the plan's verification list, and it went from **113 pass on
`origin/main` to 110 pass / 3 fail** on the branch. All three failures were
real content regressions, not stale pins:

1. `getting-started.njk` — the `https://docs.claude.com/` citation had to live
   **inside `<div class="page-citations">`**. Restructuring the definition
   paragraph moved the anchor out of that block, so the `#4410`/`#4754` AEO
   contract (`hostMatched(/^https:\/\/docs\.claude\.com\//)` over the citation
   block's hrefs, `:1232`) failed even though the same href still existed
   elsewhere on the page.
2. `getting-started.njk` — the Claude Code block's plan sentence carried no
   `self-host` token. The `#9584` Guard 1 rule (`:2390`) flags any marketing
   sentence with Claude-plan wording that is not **both** self-host-scoped and
   free of a hosted token; a bare `<p>Signed in with your Claude plan ...</p>`
   reads as a hosted claim.
3. `index.njk:41` — the hero plan line must open `Self-hosted runs inside your
   own Claude Code` (`:3102`), pinned by the committed hero wireframe `.pen`
   and the `#9584`/`#9579` counsel audit. A de-monopolizing rewrite to "your own
   harness" broke that literal while satisfying the sentence's *intent*.

## Solution

Repair the **content**, never the test, and satisfy each contract literally:

- Keep the Claude Code citation host anchor inside `.page-citations` (it may
  also appear elsewhere, but the block must carry one).
- Scope the plan sentence to its harness: `Self-hosted in Claude Code: signed
  in with your Claude plan or an Anthropic API key.`
- Keep the hero's required opening literal `Self-hosted runs inside your own
  Claude Code`, and carry the de-monopolizing harness list **after** it:
  `Self-hosted runs inside your own Claude Code, Grok Build, Codex, or Devin
  CLI — signed in with your Claude plan or an Anthropic API key; each harness
  has its own setup guide ...`

Then re-run the suite and record the before/after count (`113 on origin/main →
110/3 on HEAD → 113/0 fixed`) in the PR's verification table, so the reviewer
can see the gate was measured rather than assumed.

## Key Insight

**A prose gate's assertions are invisible from the file being edited, so "every
gate I know about is green" is not evidence about the gates I do not know
about.** Two habits generalize:

- **Run the repo's *named* gates, not the plan's list.** A plan's verification
  section is a hypothesis about which gates matter; a checked-in test that
  asserts on the exact surface being edited is the authority. When the diff
  touches guarded content, grep the test tree for the file's path before
  editing (`grep -rl '<filename>' plugins/soleur/test/`) and run those suites.
- **When an assertion encodes a literal, satisfy the literal and carry the
  intent alongside it.** Here the drift-guard pinned a *string* (the hero's
  opening clause, the citation block's host) for reasons of audit provenance
  (`#4754`, `#9579`, `#9584`) — a rewrite that serves the same intent but
  changes the string is a regression, not an improvement. Read what the
  assertion is *for* before deciding the string is incidental.

The generator-owned doc has a matching rule: when the shipped artifact is
generated, a claim defect is fixed in the generator and the artifact
regenerated, because a hand-edit to the generated file reds its `--check`. The
`--check` mis-claim in this PR (an idempotence check for an *installed* adapter,
not an uninstall confirmation) had to be corrected at
`sync-opencode-adapter.ts`'s `instructions()` and re-emitted, never patched into
`opencode/INSTRUCTIONS.md` directly.

## Session Errors

1. **Plan subagent reported the `subagent` tool unavailable**, so the research
   fan-out and CTO spawn could not run as written (research done inline; one
   technical ruling recorded `pending - assumed:`). *Prevention:* a skill that
   fans out should state the inline fallback and the disclosure it carries
   (`Reviewed-Coverage: sequential-fallback`) at the fan-out step, not leave the
   degraded path to be improvised — the existing Cloud-Mode rule is the
   precedent to generalize.
2. **Wrong test runner.** `npx vitest run <suite>` → `Cannot find package
   'bun:test'`. *Prevention:* read the suite's own import line — a `bun:test`
   import means `bun test`, not vitest; do not infer the runner from the file
   extension.
3. **Wrong script paths.** `plugins/soleur/scripts/sync-readme-counts.sh` and
   `plugins/soleur/scripts/docs-cli-verification.sh` → rc=127. *Prevention:*
   the repo-root `scripts/` and `.claude/hooks/` are the homes for repo-level
   gates; `find . -name '<script>'` before prescribing a path.
4. **Ad-hoc Eleventy flags bypassed the root config**, giving `filter not
   found: dateToShort`. *Prevention:* use the repo's documented build command
   (`npm run docs:build`) rather than hand-rolled `--input`/`--output` flags,
   which skip `eleventy.config.js`.
5. **I regressed a blocking prose gate.** `seo-aeo-drift-guard.test.ts` went
   113 pass (origin/main) → 110 pass / 3 fail on my HEAD; all three were real
   content regressions. Recovery: repaired the content (`getting-started.njk`
   citation host anchor + self-host re-scope; `index.njk` hero literal) and
   re-ran to 113/0. *Prevention:* before editing guarded marketing prose, grep
   `plugins/soleur/test/` for the file path and run every suite that asserts on
   it — a plan's verification list is not the gate set. **This is the
   load-bearing error of the round and feeds Error-to-Workflow Feedback below.**
6. **Shipped a false `--check` claim.** The uninstall section asserted
   `install-opencode-adapter.ts --check` reports "an uninstalled state"; measured,
   it reports `MISSING:` per expected path and exits 1 after a correct removal.
   Recovery: corrected the generator's `instructions()` and regenerated.
   *Prevention:* a doc claim about a command's behavior is a measurement — run
   the command in the state the sentence describes before writing it.
7. **Malformed `**` bold** spanning `<configdir>/opencode.json` in the uninstall
   section. Recovery: fixed in the generator, regenerated the artifact.
   *Prevention:* after editing generator prose that builds markdown from
   string arrays, render and read the emitted file rather than eyeballing the
   TS source, because the `**` boundaries are only visible in the output.
8. **Command-accuracy defect:** `index.njk`'s FAQ (+ JSON-LD twin) named four
   harnesses but prescribed only `/soleur:go`. Recovery: kept the harness list
   and pointed the entry command at the setup guide. *Prevention:* when a
   sentence names a set, check that every prescribed token in it is true for
   every member — a list and a command in one sentence must have the same
   domain.
9. **My QA parity script produced a false positive** on a curly `’` vs straight
   `'` apostrophe on a line this PR never touched. Recovery: restricted the
   comparison to pairs this PR edited. *Prevention:* a parity probe should
   normalize typography AND scope to the diff before reporting a mismatch as
   drift.

## Tags

category: docs-accuracy
module: plugins/soleur/docs, plugins/soleur/test, plugins/soleur/scripts
