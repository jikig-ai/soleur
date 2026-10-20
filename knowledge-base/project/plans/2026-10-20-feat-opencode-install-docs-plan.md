---
title: "docs: accurate multi-harness installation instructions for the README and the Soleur.ai website"
type: docs
date: 2026-10-20
slug: feat-opencode-install-docs
branch: feat-one-shot-opencode-install-docs
issue: 10591
---

# docs: accurate multi-harness installation instructions for the README and the Soleur.ai website

## Overview

The repo-root `README.md`, `plugins/soleur/README.md`, and the Soleur.ai install surface
(`plugins/soleur/docs/pages/getting-started.njk`) describe how to install Soleur in a
harness. They are accurate for the harnesses named today — Claude Code, Grok Build, Codex,
Devin CLI — and they present the Claude Code install as *the* install ("Install in Claude
Code", "install it in two commands"). Nothing on any public page claims OpenCode, Cursor,
or Antigravity support, which is deliberate and ADR-recorded: ADR-291 (accepted 2026-10-20)
and ADR-274 (adopting) keep the README, getting-started, comparison, blog, and battlecard
pages **unchanged** until a per-harness support bar is met on live evidence, and ADR-291's
own record states "no public 'supports OpenCode' claim is made."

This plan therefore does **not** add an OpenCode/Cursor/Antigravity support claim to any
public surface. It fixes the install instructions that are *already* public and already
wrong-or-incomplete for the harnesses those pages name, and it removes the "there is one
install, and it is Claude Code" framing that makes the multi-harness reality undiscoverable
to a reader on Devin, Codex, or Grok Build. The OpenCode adapter — the subject the branch
name points at — is documented where the ADRs already authorize it: the in-repo,
agent-read `plugins/soleur/opencode/INSTRUCTIONS.md` and the `go.md` routing table. Any
change that would *add* a public support sentence is routed as a decision to the CTO
(technical) or the operator (brand/scope), not taken by this plan.

## Problem Statement

### The public install surface omits harnesses it already supports

The root `README.md` `## Installation` section documents **Devin CLI** and **Codex**, then
presents the Claude Code marketplace install under **"From the marketplace (recommended)"**
with no harness label. A reader cannot tell that "recommended" means "recommended *for
Claude Code*", and a Grok Build reader finds no install block at all even though Grok Build
is a first-class supported harness (`Harness` union includes `grok`; the routing table at
`plugins/soleur/commands/go.md` Step 2.0 and both READMEs carry a Claude-Code/Grok-Build
comparison table). The "From the marketplace" block is thus the Claude install with a
harness-neutral heading.

`plugins/soleur/docs/pages/getting-started.njk` is worse: its section label reads
**"Source-available. Install in Claude Code."**, the hero of the self-hosted section says
`Soleur ... works in Claude Code today`, and the page's `seoTitle` promises
*"Install Your AI Organization in Two Commands"*. Its entry-point table has only two
columns — Claude Code and Grok Build — so Devin, Codex, Cursor, OpenCode, and Antigravity
sessions have no row and no link to their own `INSTRUCTIONS.md`. The FAQ JSON-LD block
duplicates every prose answer verbatim, so each such edit must land in two places or the
structured data silently drifts from the page.

### `plugins/soleur/README.md` mirrors the same gap

`plugins/soleur/README.md` (the "full component reference" the root README points at)
repeats the Devin/Codex/Claude install content and the two-column harness table. It is a
second copy of the same stale prose, and nothing keeps the two in sync.

### The in-repo per-harness docs exist but are undiscoverable from the public pages

Six harnesses have committed, agent-read instruction docs:

| Harness | Instruction doc | Public install link today? |
|---|---|---|
| Claude Code | (root README marketplace block) | Yes |
| Grok Build | `knowledge-base/engineering/grok-onboarding.md` | No — only a table column |
| Codex | `knowledge-base/engineering/codex-onboarding.md` | Yes (root README) |
| Devin CLI | `plugins/soleur/devin/INSTRUCTIONS.md` | Yes (root README) |
| OpenCode | `plugins/soleur/opencode/INSTRUCTIONS.md` | No |
| Cursor CLI | `plugins/soleur/cursor/INSTRUCTIONS.md` | No (and `adopting`, per ADR-274) |
| Antigravity | `plugins/soleur/antigravity/INSTRUCTIONS.md` | No |

The three missing links (Grok Build is only a table column and has no install command in
the README at all; OpenCode and Antigravity have docs but no pointer) are the concrete
"missing installation instructions" surface.

### The stale-premise trap this plan must not fall into

The obvious reading of "add the OpenCode install to the README" *contradicts a live,
accepted ADR*. ADR-291's Status section, the `## Consequences` section, and the
`Public README ... stay unchanged` sentence all forbid a public support claim for OpenCode
on the current evidence; ADR-274's `## Consequences` says the same for Cursor. The
OpenCode adapter's two support-bar acceptance criteria rest partly on **substituted**
evidence pending the live reproduction in #10591 item 1 (open, `priority/p3-low`). A plan
that wrote the OpenCode install into `README.md` would ship a public claim the architecture
record explicitly withholds.

## Research Insights

### Premise Validation

- **Cited issue #10591** (`gh issue view`): **OPEN**, `priority/p3-low`, `type/bug`,
  `domain/engineering`. Its four items are OpenCode-adapter post-merge residuals; item 1 is
  the live-surface support-bar evidence, item 4 notes **"No uninstall path"** — the installer
  has no `--uninstall` and removal is documented by hand in `plugins/soleur/commands/sync.md`.
  This is a real, live, in-scope finding that shapes the plan's OpenCode-doc scope (see Cut
  List): the *install* doc is accurate and the *uninstall* half is the gap.
- **Cited mechanism (`add a public OpenCode install instruction`) vs. the ADR corpus**
  (`grep -rn "OpenCode" knowledge-base/engineering/architecture/decisions/`): **stale /
  explicitly-rejected.** ADR-291 (`status: accepted`, 2026-10-20) states verbatim: *"it is why
  this record can be `accepted` while **no public "supports OpenCode" claim is made**: the
  README, getting-started, comparison, blog, and battlecard pages are unchanged"*, and
  *"Public README, getting-started, comparison, blog, and battlecard pages stay unchanged."*
  ADR-274 (`status: adopting`) states the same for Cursor. The mechanism "write the OpenCode
  install into README/getting-started" is **not an unconsidered idea — it is a deferred one
  gated on #10591 item 1.** The plan re-scopes to the gap the ADRs *leave open* (below).
- **Cited capability claim ("the repo has no per-harness install docs for OpenCode"):** FALSE.
  `plugins/soleur/opencode/INSTRUCTIONS.md`, `cursor/INSTRUCTIONS.md`,
  `antigravity/INSTRUCTIONS.md`, `devin/INSTRUCTIONS.md`, `codex/INSTRUCTIONS.md` all exist on
  `origin/main`, and `knowledge-base/engineering/grok-onboarding.md` exists on disk. The real
  gap is *pointer coverage from the public pages*, not document existence. (Grep authority:
  `ls plugins/soleur/{opencode,cursor,antigravity,codex,devin}/`, `find . -name grok-onboarding.md`.)
- **Cited public-surface claim ("the README/website claim OpenCode support"):** FALSE. A repo-
  wide grep for support sentences over `*.md`/`*.njk` returned exactly **one** hit, and it is
  ADR-291's own prose (`no public "supports OpenCode" claim is made`). There is no public claim
  to correct; there is a *missing* harness-neutral frame and three missing pointers.
- **File-location premise:** the parent ask placed `opencode/` at the repo root. It is at
  `plugins/soleur/opencode/`. Recorded so no phase writes to a nonexistent root path.

### Property List

The ask ("fix inaccurate/stale/missing install instructions for OpenCode and other harnesses")
restated as observable outcomes:

1. **P1 — A reader on a supported-but-unnamed harness can find the install commands for it.**
   (A Grok Build reader, a Devin reader, a Codex reader each reach their own install block.)
2. **P2 — The install framing names the harness each install block targets**, so "recommended"
   is not read as harness-neutral.
3. **P3 — No public page contradicts a live ADR** by asserting support for an `adopting`/bar-
   unmet harness (OpenCode, Cursor).
4. **P4 — Each harness's instruction doc is reachable by a documented pointer** (README link
   or getting-started link), including the harnesses the pages already name.
5. **P5 — The install and uninstall instructions for a harness whose adapter ships are both
   present and accurate** (the #10591 item-4 gap: no uninstall path).
6. **P6 — The FAQ prose and its JSON-LD structured-data twin do not drift** when edited.

### Cut List

- **Mechanism: add an OpenCode/Cursor/Antigravity support claim to `README.md` /
  `getting-started.njk`.** → property it *would* buy: P1 for those harnesses. → **cut**, because
  P1-for-those-harnesses is owned by a *different* mechanism that is currently **withheld by
  ADR-291/ADR-274** (live support-bar evidence, #10591 item 1). Adding the claim here is the
  explicitly-deferred alternative. The plan addresses P1 for the **already-claimed** harnesses
  (Grok Build, Devin, Codex) and routes the OpenCode/Cursor/Antigravity public-claim decision
  to the CTO/operator (see Domain Review → Engineering).
- **Mechanism: a new docs-site page for OpenCode install.** → property: P1-for-OpenCode. → **cut**,
  same reason; also it is a new public surface the ADRs do not authorize, and the operator-typed
  entry `/go` already appears in the in-repo doc.
- **Mechanism: hand-maintain a second copy of the harness table in `plugins/soleur/README.md`.**
  → property: P1. → **partially cut**: the table stays, but the plan requires it to be an
  *identical* edit to the root README's table in the same PR, so the two cannot diverge; no new
  sync script is built (the repo already has `scripts/sync-readme-counts.sh --check` as its
  drift authority for counts, and a prose-table sync tool would be new machinery buying nothing
  a same-PR edit does not).
- **Mechanism: hardcode the component counts** (67 agents / 103 skills / 4 commands) into the
  edited prose. → property: none (accuracy). → **cut**: counts are computed at build time
  (`plugins/soleur/docs/_data/stats.js`) and `scripts/sync-readme-counts.sh --check` +
  `plugins/soleur/test/marketing-content-drift.test.ts` gate drift. Edited prose must use the
  existing placeholders/values, not introduce new literals.

### Repo facts the plan relies on (grep authority named per `hr-verify-repo-capability-claim-before-assert`)

- `plugins/soleur/lib/harness.ts:29` — `Harness` union =
  `claude | grok | codex | devin | cursor | opencode | antigravity | unknown`.
- `plugins/soleur/commands/go.md` Step 2.0 routing table — six harness rows (Grok Build, Codex,
  Devin CLI, Cursor CLI, OpenCode) each with a per-harness `INSTRUCTIONS.md` link; the
  `source=none` paragraph names **Codex, Devin CLI, Grok Build, OpenCode** as the read-from-disk
  harnesses.
- `plugins/soleur/opencode/INSTRUCTIONS.md` — install via
  `bun plugins/soleur/scripts/install-opencode-adapter.ts` (`--check`, `--force`); skills
  register from the canonical tree (no copy); bare skill ids; `subagent` tool keyed on the
  path id.
- `plugins/soleur/scripts/install-opencode-adapter.ts` — install/`--check`/`--force`/`--target`;
  merges `skills` + `instructions` into `~/.config/opencode/opencode.json`.
- `plugins/soleur/docs/_data/stats.js` — build-time agent/skill/command/department counts.
- `scripts/sync-readme-counts.sh --check` — README component-count drift gate.
- `plugins/soleur/test/marketing-content-drift.test.ts` — prose-numeral drift guard over
  `knowledge-base/marketing` + docs (has an allowlist).
- `.claude/hooks/docs-cli-verification.sh` — PostToolUse advisory hook flagging unverified CLI
  invocations in `.md`/`.njk`/README; a verified CLI claim needs a
  `<!-- verified: YYYY-MM-DD source: <url> -->` marker.
- `plugins/soleur/docs/_includes/page-freshness.njk` — renders `last_updated`; pages carrying it
  include getting-started, pricing, agents, skills, about, vision, index, both compare pages.

### Institutional learnings

- ADR-291 §Consequences and ADR-274 §Consequences both make the *grep-the-legal-corpus* step a
  precondition of a status flip, not of a docs edit. This plan edits docs for harnesses whose
  status is already `accepted`/claimed, so the flip-gated sweep does not fire — but the
  *principle* (public claim follows recorded status) is the plan's spine.
- `hr-weigh-every-decision-against-target-user-impact` — the target user here is a founder
  reading the install page; the decision under `## User-Brand Impact` is framed against them.
- `cq-cite-content-anchor-not-line-number` — this plan cites `plugins/soleur/lib/harness.ts:29`
  by symbol (`Harness` union) and `go.md` Step 2.0 by heading, not by brittle line number.

### Property / Cut reconciliation (what the plan actually builds)

| Property | Mechanism in this plan | Harness scope |
|---|---|---|
| P1 | Add/label install blocks + one "all harnesses" pointer row per public page | Grok Build, Codex, Devin (claimed) |
| P2 | Harness-name every install block heading | all named |
| P3 | Add **no** support sentence; add a CTO/operator-routed decision item | OpenCode, Cursor, Antigravity |
| P4 | Link every named harness's `INSTRUCTIONS.md` from both public surfaces | Grok, Codex, Devin + the agent-read docs |
| P5 | Add the missing uninstall pointer to the OpenCode **in-repo** doc + `sync.md` | OpenCode |
| P6 | Edit FAQ prose and JSON-LD in the same change; verify both | getting-started |

## Proposed Solution

Two coordinated surfaces, no new public support claim:

**A. Repo-root `README.md` and `plugins/soleur/README.md` — label and complete the install blocks.**
Rename the harness-neutral "From the marketplace (recommended)" heading to name Claude Code,
add a **Grok Build** install block (today Grok Build is a table column with no install command),
and link each named harness to its committed instruction doc (`grok-onboarding.md`,
`codex-onboarding.md`, `devin/INSTRUCTIONS.md`). Underline that the marketplace block is the
Claude Code install. Apply the identical harness-table edit to `plugins/soleur/README.md` in the
same PR.

**B. `plugins/soleur/docs/pages/getting-started.njk` — de-monopolize the framing and add pointers.**
Change the section label from "Install in Claude Code." to a harness-neutral instruction, add a
row/link per harness including the ones the page already names, and link the harnesses whose
adapters ship with a committed doc **only where a public claim is already authorized**. Extend the
harness table to the harnesses the page may name publicly (Claude Code, Grok Build; and Devin,
Codex which are named on the README today). Keep the FAQ prose and its JSON-LD twin in sync in a
single edit.

**C. OpenCode (in-repo only, per ADR-291).** Improve `plugins/soleur/opencode/INSTRUCTIONS.md`
and `plugins/soleur/commands/sync.md` for the #10591 item-4 gap (**no uninstall path**): document
removal accurately, and note `--check` drift. **No public-page OpenCode install block.**

**D. Route, do not decide, the public-claim question.** Record a plan item that the
"should the README/getting-started name OpenCode/Cursor/Antigravity as installable harnesses?"
decision requires (i) the live support-bar evidence in #10591 item 1 and (ii) a CTO ruling, and
is therefore out of scope for this docs PR. This is the honest disposition of an ask whose
literal form conflicts with an accepted ADR.

## Technical Approach

### Implementation Phases

#### Phase 1: Label and complete the repo READMEs (surface A)

- Edit `README.md` `## Installation`:
  - Rename `**From the marketplace (recommended):**` to name Claude Code explicitly
    (e.g. `**Claude Code (recommended):**`), preserving the existing command block.
  - Add a `**Grok Build:**` install block with the correct install command, cross-checked
    against `knowledge-base/engineering/grok-onboarding.md` (do **not** invent a command; if the
    onboarding doc gives no install command, add only the pointer and note the gap).
  - Add a one-line pointer from each named harness block to its instruction doc.
- Apply the identical harness-table edit to `plugins/soleur/README.md`.
- Success: both READMEs name Claude Code, Grok Build, Codex, Devin as install targets, each
  linking its doc; no new component-count literals.

#### Phase 2: De-monopolize the getting-started page (surface B)

- Edit `plugins/soleur/docs/pages/getting-started.njk`:
  - Section label "Source-available. Install in Claude Code." → harness-neutral.
  - Self-hosted prose: "works in Claude Code today" → acknowledge the supported harness set
    (Claude Code, Grok Build, Codex, Devin — the ADR-245 supported set), not Claude Code alone.
  - Harness table: add rows/columns for the harnesses the page may publicly name.
  - Add a `Learn More`-style link (or per-harness links) to the committed instruction docs.
  - Update the FAQ answer **and** its JSON-LD twin in the same edit (P6).
  - Bump `last_updated:` frontmatter.
- Success: no page prose says "Claude Code" as if it were the only harness; every named harness
  has a pointer; FAQ and JSON-LD match.

#### Phase 3: OpenCode in-repo doc completeness (surface C, ADR-291-bounded)

- Edit `plugins/soleur/opencode/INSTRUCTIONS.md`: add an accurate **Uninstall / removal**
  subsection (the #10591 item-4 gap), and confirm the install/`--check` instructions match
  `plugins/soleur/scripts/install-opencode-adapter.ts`'s actual flags.
- Edit `plugins/soleur/commands/sync.md`: replace the manual removal prose with a pointer to the
  new subsection (keep it a single authority).
- Success: a reader can install **and** uninstall the OpenCode adapter from committed docs.

#### Phase 4: Record the routed decision and verify gates

- Add the routed-decision item (surface D) so the public-claim question is visible, not lost.
- Run the docs gates: `scripts/sync-readme-counts.sh --check`,
  `plugins/soleur/test/marketing-content-drift.test.ts`, the Eleventy build, and the
  `docs-cli-verification.sh` marker check on any edited CLI claim.
- Success: all gates green; every edited CLI command carries a `verified:` marker.

## Files to Edit

- `README.md` — `## Installation` section: label the Claude Code block, add a Grok Build block,
  add per-harness doc pointers.
- `plugins/soleur/README.md` — mirror the identical install/harness-table edit.
- `plugins/soleur/docs/pages/getting-started.njk` — section label, self-hosted prose, harness
  table, instruction-doc links, FAQ prose **and** JSON-LD twin, `last_updated` frontmatter.
- `plugins/soleur/opencode/INSTRUCTIONS.md` — add an accurate uninstall/removal subsection;
  confirm install flags.
- `plugins/soleur/commands/sync.md` — point the manual-removal prose at the new subsection.
- (Conditional) `knowledge-base/engineering/grok-onboarding.md` — only if it lacks an install
  command the README needs; otherwise read-only as the pointer target.

## Files to Create

- None. This is a docs-accuracy change; no new page, script, or gate is introduced (see Cut List).

## Research Reconciliation — Spec vs. Codebase

| Spec / ask claim | Codebase reality | Plan response |
|---|---|---|
| "OpenCode installation instructions are missing/stale in the README and website." | `plugins/soleur/opencode/INSTRUCTIONS.md` exists and is accurate; the README/website **deliberately** name no OpenCode claim (ADR-291). | Re-scope: fix the *claimed*-harness gaps; keep OpenCode public claims withheld; add the in-repo uninstall gap (#10591 item 4). |
| "`opencode/` is at the repo root." | It is at `plugins/soleur/opencode/`. | Corrected throughout. |
| "The install instructions are inaccurate." | They are accurate for the harnesses named; they are *incomplete* (Grok Build has no README install block) and *monopolized* (Claude Code framed as the install). | Edit for completeness + framing, not correctness-against-a-claim. |
| "The website duplicates prose in JSON-LD that must be synced." | Confirmed in `getting-started.njk` (7 FAQ answers duplicated verbatim). | P6 is a first-class property; the FAQ edit lands in both places in one change. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder reaches the install page, the page's
  prose or its JSON-LD twin (surfaced by Google/AI answer engines) states a harness claim that
  does not match the adapter's actual support status — installing Soleur on a harness that is
  not yet supported and hitting a session that mis-routes or refuses.
- **If this leaks, the user's [workflow / reputation] is exposed via:** a stale or duplicated
  install instruction that leads a founder to run a `devin plugins install` / `bun …install-opencode-adapter`
  flow from a page that has drifted from the in-repo doc, installing a half-configured adapter
  into their own `~/.config/opencode/opencode.json`.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** A docs-only change alters no data surface, runs no
  migration, and exposes no credential; the worst outcome is a confused reader, not a breach.
  The "single-user incident" tier would be wrong here because the failure is recoverable
  instruction text, not a user-data or workflow-loss event. It stops short of `aggregate pattern`
  because there is no repeated per-user exposure mechanism — the surface is public prose, fixed
  by a single edit.

## Scope Check

### Ask Mapping

| Ask (parent brief) | Plan item |
|---|---|
| Fix inaccurate/stale/missing install instructions for OpenCode | Surface C (in-repo OpenCode doc + uninstall gap); public claim **routed** (surface D) — not taken, per ADR-291 |
| …and other non-Claude harnesses (Grok Build, Codex, Devin CLI, Cursor CLI, Antigravity) | Surface A (Grok Build install block + pointers), Surface B (de-Westernize getting-started, add rows/links) |
| Repo-root `README.md` | Surface A, `Files to Edit` |
| Soleur.ai website (Eleventy docs site) | Surface B, `Files to Edit` |

Every ask maps to an item. The one ask whose literal form conflicts with an accepted ADR
(add an OpenCode claim) is mapped to surface D (a routed decision), not silently dropped and not
silently executed.

### Plan-Item Provenance

- Surfaces A, B: `cited` (parent ask names README and website; the "two commands"/"Install in
  Claude Code" framing is observed in the files).
- Surface C: `inferred` — derived from #10591 item 4 ("No uninstall path") found during Phase 0.6
  premise validation. Justified: it is a live, filed, domain/engineering gap in the OpenCode
  install surface, the exact subject of this plan, and it is the only OpenCode-public-safe work
  the ADR leaves open.
- Surface D: `inferred` — derived from the ADR-291/ADR-274 conflict discovered in premise
  validation. Justified: without it, the plan either silently drops part of the ask or silently
  violates an ADR; recording the routed decision is the only honest disposition.

### Split Assessment

**No split.** The change is one coherent docs-accuracy unit across two public surfaces plus one
in-repo doc. Splitting the README from the website would double the review surface for identical
prose and risk the two drifting mid-flight; splitting OpenCode out would strand surface D
unowned. Single PR.

## Open Code-Review Overlap

`None` — files to edit are docs/prose only (`README.md`, `plugins/soleur/README.md`,
`getting-started.njk`, `opencode/INSTRUCTIONS.md`, `sync.md`); no open `code-review` issue names
them (checked against open issues at plan time). Opencode-adapter code-review residuals live in
#10591 (not labeled `code-review`), and surface C only *references* that issue, it does not
re-open its engineering items.

## Domain Review

### Engineering

- **Relevance:** Direct — the OpenCode adapter, the `Harness` union, and the ADR-recorded support
  bar are engineering-owned. The public-claim question is a **technical ruling**.
- **Summary:** The plan's scope is bounded by ADR-291 (accepted) and ADR-274 (adopting), which
  both withhold public support claims for OpenCode/Cursor until live evidence (#10591 item 1).
  The plan edits only the install surfaces for harnesses already named publicly and the in-repo
  OpenCode doc. Adding any public OpenCode/Cursor/Antigravity install claim is **explicitly out
  of scope** and routed to the CTO: `Ruled by: pending — assumed default: withhold the public
  claim until the support bar's live evidence lands in #10591 item 1, because ADR-291 §Status and
  §Consequences state it verbatim and the ADR is `accepted`.` (A CTO subagent cannot be spawned
  from this Code Mode runtime; the ruling is recorded here as the conservative default matching
  the accepted record, and re-confirmed at implementation time.)
- **Risk:** Low. The only way to violate an ADR here is to *add* a sentence; the plan adds none.

### Legal

- **Relevance:** Low. ADR-291 §Consequences makes the legal-corpus sweep a precondition of a
  *status flip*, which this plan does not perform.
- **Summary:** No future-tense support sentence exists to route (verified — the repo-wide grep
  returned only ADR-291's own prose). No legal-corpus edit is proposed. No privacy/terms surface
  is touched.

### Product/UX Gate

- **Product-relevant:** yes (public docs-site page + README are user-facing surfaces).
- **Tier:** ADVISORY. The change is prose/labels on a page whose structure already exists; no new
  UI component, no layout change, no `## Files to Create` with a UI-surface path. The page's
  existing section/table structure is edited in place.

#### Findings

- The getting-started page's harness table gains rows; keep the table's existing column/cell
  visual convention (the page uses a plain `<table>` with `<code>` cells) rather than introducing
  a new component.
- Keep the FAQ answer wording and its JSON-LD twin byte-identical where possible, for P6.

## Acceptance Criteria

### Functional Requirements

1. `README.md` `## Installation` labels the Claude Code marketplace block as the Claude Code
   install, and contains an install block for **Grok Build** (command cross-checked against
   `knowledge-base/engineering/grok-onboarding.md`) or, if the onboarding doc provides none, a
   documented pointer plus a note. — P1, P2
2. `README.md` and `plugins/soleur/README.md` carry the **same** harness table and the same
   per-harness instruction-doc links. — P1, P4
3. Each of Claude Code, Grok Build, Codex, Devin in both READMEs links to its committed
   instruction doc. — P4
4. `plugins/soleur/docs/pages/getting-started.njk` no longer states or implies that the
   self-hosted install is Claude-Code-only (section label and self-hosted prose both changed).
   — P1, P2
5. The getting-started harness table names the publicly-claimed harness set (Claude Code,
   Grok Build, Codex, Devin) with a per-harness pointer. — P1, P4
6. The getting-started FAQ prose and its JSON-LD `mainEntity` twin are identical for every edited
   answer. — P6
7. `plugins/soleur/opencode/INSTRUCTIONS.md` documents an accurate **uninstall/removal** path and
   its install instructions match `install-opencode-adapter.ts`'s flags. — P5
8. `plugins/soleur/commands/sync.md` points manual removal at that subsection. — P5
9. **No public surface (`README.md`, `plugins/soleur/README.md`, `getting-started.njk`) gains a
   sentence claiming OpenCode, Cursor, or Antigravity install support.** — P3

### Non-Functional Requirements

10. No edited file introduces a hardcoded component count; existing placeholders
    (`{{ stats.agents }}` etc.) and existing literals are preserved. — Cut List
11. Each edited or added CLI command carries a `<!-- verified: YYYY-MM-DD source: <url> -->`
    marker where the surrounding file already uses that convention, satisfying
    `docs-cli-verification.sh`. — gates
12. `getting-started.njk` `last_updated:` frontmatter is bumped to the edit date.

### Quality Gates

13. `scripts/sync-readme-counts.sh --check` passes.
14. `plugins/soleur/test/marketing-content-drift.test.ts` passes.
15. The Eleventy docs build succeeds.

## Test Scenarios

### Acceptance Tests (RED phase targets)

1. **Grep: no new public claim.** `grep -rniE "support(s|ed)? (the )?(opencode|cursor|antigravity)" README.md plugins/soleur/README.md plugins/soleur/docs/pages/getting-started.njk`
   → returns no line that this PR added. (RED before: the AC is written before the edit; a naive
   implementer adding the OpenCode block reds here.)
2. **Grep: Grok Build install present.** `grep -n "Grok Build" README.md` shows an install block
   (or documented pointer) in `## Installation`. (RED before edit.)
3. **Grep: both READMEs' harness tables match.**
   `diff <(sed -n '/| Step | Claude Code | Grok Build |/,/^$/p' README.md) <(sed -n '/| Step | Claude Code | Grok Build |/,/^$/p' plugins/soleur/README.md)`
   → empty. (RED before sync edit.)
4. **Grep: getting-started de-monopolized.**
   `grep -n "Install in Claude Code" plugins/soleur/docs/pages/getting-started.njk` → no match.
   (RED before edit.)
5. **JSON-LD parity.** A small check comparing each FAQ prose answer to its JSON-LD `text`
   counterpart in `getting-started.njk` → all equal. (RED before the twin edit.)
6. **Uninstall documented.** `grep -niE "uninstall|removal" plugins/soleur/opencode/INSTRUCTIONS.md`
   → a subsection exists; `grep -n "opencode/INSTRUCTIONS" plugins/soleur/commands/sync.md`
   → pointer present. (RED before edit.)
7. **Counts gate.** `bash scripts/sync-readme-counts.sh --check` → exit 0.
8. **Content-drift gate.** `bun test plugins/soleur/test/marketing-content-drift.test.ts` → pass.

### Manual Verification

- Render `plugins/soleur/docs/pages/getting-started.njk` via the Eleventy build and read the
  self-hosted section as a Grok Build reader and as a Devin reader: each reaches its own install
  or pointer within the section.

## Architecture Decision (ADR/C4)

**No new architectural decision.** This plan makes no ownership/tenancy move, no new substrate
or trust boundary, and does not reverse or extend an existing ADR — it *conforms* to ADR-291 and
ADR-274 by withholding the public claim they withhold. Detection in plan Phase 2.10 does not
fire.

- **`### ADR`** — none to create. (If surface D is later acted on — i.e. the CTO rules to publish
  the OpenCode claim — that ruling would *amend ADR-291's* Status/Consequences, and is a separate
  change with its own evidence; it is not this plan.)
- **`### C4 views`** — no C4 impact. Enumerated against the change: no external human actor
  changes, no external system/vendor is added (OpenCode is the operator's own tool, not a Soleur
  processor — ADR-291 §Principle Alignment AP-012), no container/data-store is touched, and no
  actor↔surface access relationship changes. The change is prose on two public pages and two
  in-repo docs; `model.c4`/`views.c4`/`spec.c4` carry no harness-install or docs-page element.

## Dependencies & Risks

- **Dependency:** #10591 item 1 (live support-bar evidence) gates the *withheld* public OpenCode
  claim. This plan does not depend on it; it depends only on the ADR statuses that exist today.
- **Risk (low):** a later implementer reads "add OpenCode install docs" literally and adds the
  public claim. Mitigated by AC 9 and Test Scenario 1 (a RED-before grep) and by the explicit
  routed-decision item.
- **Risk (low):** the FAQ JSON-LD drifts from prose. Mitigated by P6 + Test Scenario 5.
- **Risk (low):** README and `plugins/soleur/README.md` diverge. Mitigated by AC 2 + Test
  Scenario 3 (a diff, not a new sync script).

## References & Research

- `README.md` — `## Installation` (Devin CLI, Codex, unlabeled Claude Code marketplace block).
- `plugins/soleur/README.md` — mirrored install content.
- `plugins/soleur/docs/pages/getting-started.njk` — install page, harness table, FAQ + JSON-LD.
- `plugins/soleur/lib/harness.ts:29` — `Harness` union (authority for the supported set).
- `plugins/soleur/commands/go.md` — Step 2.0 routing table; per-harness `INSTRUCTIONS.md` links.
- `plugins/soleur/opencode/INSTRUCTIONS.md`, `plugins/soleur/scripts/install-opencode-adapter.ts`
  — OpenCode adapter install surface.
- `knowledge-base/engineering/grok-onboarding.md`, `knowledge-base/engineering/codex-onboarding.md`,
  `plugins/soleur/{devin,cursor,antigravity}/INSTRUCTIONS.md` — per-harness docs.
- `knowledge-base/engineering/architecture/decisions/ADR-291-add-an-opencode-plugin-adapter.md`
  — accepted; withholds the public OpenCode claim.
- `knowledge-base/engineering/architecture/decisions/ADR-274-add-a-cursor-cli-plugin-adapter.md`
  — adopting; withholds the public Cursor claim.
- `knowledge-base/engineering/architecture/decisions/ADR-245-retire-openhands-gemini-ports-and-prove-codex-devin-discovery-in-ci.md`
  — supported set + re-entry rule.
- `scripts/sync-readme-counts.sh`, `plugins/soleur/test/marketing-content-drift.test.ts`,
  `.claude/hooks/docs-cli-verification.sh`, `plugins/soleur/docs/_data/stats.js` — gates.
- GitHub issue #10591 (`OPEN`, `priority/p3-low`, `type/bug`, `domain/engineering`) — OpenCode
  post-merge residuals; item 4 is the uninstall gap surface C closes.

## Session Summary

### Plan File

`knowledge-base/project/plans/2026-10-20-feat-opencode-install-docs-plan.md`

### Errors

None fatal. Recorded limitations: the `subagent` tool is unavailable in this Code Mode runtime,
so the Phase 1 research fan-out and the CTO/domain-leader spawns could not run as written —
research was performed inline by direct file reads and greps, and the one technical ruling is
recorded as `pending - assumed:` per the technical-ruling delegation rule. No `todo` tool exists
on this harness; steps are tracked in the skill's own Markdown.

### Decisions

- **Do not add a public OpenCode/Cursor/Antigravity support claim** to `README.md` or
  `getting-started.njk`. `Ruled by: pending — assumed default (CTO unreachable from this
  runtime): withhold until the support bar's live evidence lands in #10591 item 1; ADR-291
  §Status/§Consequences and ADR-274 §Consequences state this verbatim and ADR-291 is `accepted`.`
- Re-scope the ask to the work the ADRs leave open: completeness/labeling for the
  already-claimed harnesses, de-monopolized framing, pointer coverage, and the OpenCode
  in-repo uninstall gap (#10591 item 4).
- No ADR/C4 deliverable: this plan conforms to existing ADRs and makes no architectural decision.
- No split; single docs-accuracy PR.

### Components Invoked

- `plan` skill (inline, on this harness) — Phase 0 context load, Phase 0.6 premise validation,
  Phase 0.6b mechanism-minimality gate, Phase 0.7 skeleton, Phase 1.7 consolidation, Step 2/2.4/
  2.6/2.10/2.9 gates.
- Inline research (no `subagent` fan-out available): reads of `README.md`,
  `plugins/soleur/README.md`, `getting-started.njk`, ADR-291/ADR-274/ADR-245, `harness.ts`,
  `go.md`, the per-harness `INSTRUCTIONS.md` set, `stats.js`, and the docs gates; `gh issue view
  10591`.
