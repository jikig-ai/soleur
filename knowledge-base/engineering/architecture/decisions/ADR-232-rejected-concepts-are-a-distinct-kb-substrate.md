# ADR-232: Rejected concepts are a distinct KB substrate from a `not-planned` close

- **Date:** 2026-09-20
- **Issue:** #8289

## Status

Accepted. The decision is true the moment the directory and its reader land in the PR that carries
this ADR — there is no soak period and no `adopting` interim, because a record with no reader is the
failure mode this ADR exists to avoid (see the fourth alternative).

## Context

Soleur keeps decisions (ADRs), learnings (`knowledge-base/project/learnings/`) and deferrals (the
`deferred-scope-out` label). It keeps no record of what was decided **against**. The consequence is
that a concept refused once is re-proposed from scratch, and whoever handles the next request has no
way to find the refusal or the reason behind it.

Four existing mechanisms look like they already answer *"was this concept refused?"*. All four were
measured on 2026-09-20 and none of them does, for reasons that are properties of the mechanism rather
than of how well it is used.

The decisive measurement is the fifth alternative below, and it settles the question on the seed
concept itself: the server-side, Soleur-hosted Playwright refusal recorded at
`knowledge-base/product/roadmap.md` §*Architecture Decision: 3-Tier Service Automation (Brainstorm
2026-03-23)* — *"Server-side Playwright was rejected (HIGH risk from CTO, CLO, CFO)"* — was
**never filed as an issue**. `gh issue list --state all --search "server-side playwright in:title"`
returns `[]`. The refusal is real, dated and recorded by three domain leaders, and there is no issue
for an issue-search to find, however good its keywords. A substrate keyed on issues cannot hold a
refusal that never became one.

The naming is part of the decision, not a presentational choice. `register` has **eight live
compliance senses** in this repository — the seven `knowledge-base/legal/*-register.md` documents
(Article 30, Article 30(2), breach, CCLA, side-letter, tenant-DPA, T&C-contradiction) plus
`knowledge-base/engineering/architecture/nfr-register.md`, most of them counsel-reviewed with an
inclusion predicate. A change whose whole purpose is one shared vocabulary cannot ship by overloading
a compliance noun; it would commit the defect it claims to cure. So the artifact is **"the no-list"**
in prose and **"rejected-concepts record"** where a formal noun is required. "Store" is banned
alongside "register": it is datastore jargon, and a three-word hyphenated name gets shortened in
speech to *"the register"* — the exact word this constraint exists to ban.

## Decision

Rejected concepts are recorded as durable, **concept-keyed** files under
`knowledge-base/project/rejected/`, one file per concept, named `YYYY-MM-DD-<concept-slug>.md`. The
concept file is the authority the intake pre-check queries before a request is re-proposed.

The entry key is **the concept plus its `aliases`** — never a label, never the request's wording. This
is what makes matching mechanical rather than aspirational: without an alias set, "night theme" never
reaches `dark-mode`, and a concept-similarity lookup degrades into the keyword search this ADR
rejects.

Three clauses are normative, not commentary.

**Precedence.** An entry is evidence that a refusal was **recorded**; it is never the refusal itself.
Where an entry conflicts with a GitHub closure or with an ADR, the closure or the ADR wins and the
entry is STALE. This keeps the no-list a derived index rather than a competing authority.

**Advisory-only.** A rejected-concepts entry may never be the sole basis for closing, labelling or
auto-closing an issue. A prior-rejection hit is **reported to a human and escalates; it never acts.**
In particular `deferred-scope-out` must never be applied on the basis of a record hit, and an
uncertain concept match fails **open** — escalate, never auto-close.

The reason is a complete, already-built amplification path that the commit-time lint cannot see,
made concrete by the second alternative's measurement. A false entry that is internally consistent
passes the lint → an agent holding `gh issue edit` applies `deferred-scope-out` →
`apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` auto-closes the issue
after its 90-day window (`STALE_WINDOW_MS`, line 56) with `state_reason: "not_planned"` (line 568),
with no human in the loop → `scripts/sweep-followthroughs.sh` thereafter refuses to reopen it,
because *"NOT_PLANNED is a deliberate wontfix. Reopening it would override a human decision"*
(line 884). Two automated hops turn a false entry into a permanently-closed issue attributed to a
human decision that never happened. Three lines of prose retire the whole chain regardless of what
the scheduled triage pass later gains, which is why this clause is also a named **precondition on
the tracking issue for the deferred unattended-triage work** — that issue asks for the very
capability that opens the first hop.

**Built is not rejected.** An already-implemented request closed as unwanted is a **redundancy
finding**, and its record is the closing comment naming where the implementation lives. It is never
an entry here. Writing one would seed concept-dedup with refusals that never happened, and the
mechanism that would catch the error is the one the error disables.

## Enforcement sites

1. `scripts/lint-rejected-register.sh` — walks every file matching
   `knowledge-base/project/rejected/*.md` except `README.md`, discovered by walking the directory
   rather than reading a manifest. Three dispatches, because there is **not** one write chokepoint:
   a `lefthook.yml` pre-commit hook on the glob with `{staged_files}`, a pre-push mirror (the shape
   `client-pii-grep` already uses, for the `--no-verify` and merge-resolution-commit cases the
   repository already knows about), and a CI step over the **full** glob rather than the staged set.
2. `plugins/soleur/test/lint-rejected-register.test.sh` — the lint's own behavioural battery, with
   direct anti-vacuity floors per [ADR-193](ADR-193-anti-vacuity-floor-contract.md).
3. The intake pre-checks in `plugins/soleur/skills/triage/SKILL.md`,
   `plugins/soleur/agents/support/ticket-triage.md` and `.openhands/skills/ticket-triage/SKILL.md` —
   the reader. The agent's pre-checks are read-only by its own declaration; the **write** path is the
   attended `triage` skill, behind the machine gate (the lint) and then a typed confirmation naming
   the concept.
4. `knowledge-base/project/rejected/README.md` — the convention, co-located with the record, carrying
   the advisory-only clause and the precedence rule in founder-facing prose.

The lint proves **internal consistency, not truth**: within one commit it compares an entry's claim
(`redundancy_check: not-implemented`) against the evidence the same file carries (`searched:`). That
gap closes outside the commit, because each `searched` line is a command plus its result count and is
re-runnable by a reviewer or a later session. The assertion that needs the network — *no number in
`prior_requests` resolves to an issue closed as `completed`* — is deliberately **not** in the
pre-commit tier.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| `gh issue list --state all --search <keywords>` over `not-planned` closures — already treated as authoritative by `scripts/sweep-followthroughs.sh:884`, which refuses to reopen one | Keyed on the **request's wording**, not the concept: GitHub search performs no synonym expansion, so "night theme" never reaches `dark-mode`. Carries a decision but no concept key, no alias set, and no durable reason surviving the issue's closure. Measured 2026-09-20: **187** `not-planned` closures against **3,193** closed issues, and the `wontfix` label has been applied to **0** issues in repository history — so the label carries no signal either |
| The `deferred-scope-out` label plus `cron-stale-deferred-scope-outs.ts` | Not an opposite — it **converges**. The live label description is *"Review-origin issue that meets a scope-out criterion — does not block ship Phase 5.5"*, and that cron auto-closes a stale scope-out after a 90-day window (`STALE_WINDOW_MS`, line 56) with `state_reason: "not_planned"` (line 568), with no human in the loop. It is therefore a **delayed refusal reached by timeout**, which is precisely why the advisory-only clause above is load-bearing rather than decorative |
| ADR `## Alternatives Considered` tables — this very section, at scale | Records alternatives rejected **inside** an accepted decision, scoped to mechanisms rather than concepts, and unqueryable by concept. Measured across **234** ADRs: **nine** distinct live heading spellings (`## Alternatives Considered` 71, `## Alternatives considered` 54, `## Rejected alternatives` 18, `## Alternatives rejected` 3, plus five one-off suffixed variants) — no canonical form and no index. These tables are cited as a **sibling store the lookup also checks**; nothing is imported from them |
| `knowledge-base/project/learnings/technical-debt/` as the shape to copy | It is the **cautionary precedent, not the model**: structured frontmatter, **11** entries, and effectively no drain (#2723) — a record with no reader. This is why the no-list's reader ships in the same increment as the no-list, or neither ships |
| Any issue-search substrate at all, however well keyed | **The load-bearing row.** A rejected-concepts record can hold a refusal that was never filed as an issue, so no issue-search alternative can reach it at any keyword quality. Verified on the seed concept: the server-side-Playwright refusal is recorded at `knowledge-base/product/roadmap.md` and `gh issue list --state all --search "server-side playwright in:title"` returns `[]`. There is no issue for the first alternative to find |

## Consequences

- An entry carries a fixed required field set — `aliases`, `scope`, `why`, `public_note`, `instead`,
  `revisit_if`, `searched`, `redundancy_check` — and each field buys a named failure mode. `aliases`
  makes concept matching mechanical. `scope` stops a narrower incoming request from being closed
  against a broader refusal. The `why` / `public_note` split exists so the blunt internal reason is
  never the only quotable text. `instead` distinguishes a *mechanism* refusal from a
  category-level never. `revisit_if` is the only thing that reopens the question.
- Three keys are **forbidden outright** and rejected by the lint: `implemented_at` (it can only be
  true of a built feature), `requester` and `requested_by`. The requester field is removed from the
  schema **entirely** rather than restricted to a role vocabulary: this repository is public, so an
  entry naming a person is a permanent personal-data record in git history, and with zero external
  filers measured there is nobody to record. A forbidden-key check is strictly safer than a
  closed-vocabulary check at the same cost.
- The `YYYY-MM-DD-<concept-slug>.md` convention is mechanical, not advisory: without it a
  concept-similarity lookup over the directory matches `README.md` itself and manufactures exactly
  the false rejection the record exists to prevent. Anything not matching the pattern is not an entry.
- The filename is the claim to an external reader, so the lint asserts the filename's concept slug
  appears in the entry's own `scope:`. `rejected/2026-09-20-browser-automation.md` would read as
  "Soleur does not do browser automation" whatever the body said.
- Reopening is `superseded_by`, and superseded entries are excluded from matching. An entry is never
  edited out of existence; the reversal is appended and the original stays readable.
- Entries are **pointers to the definer, never restatements** — a second copy of a reason drifts from
  the first, and the drifting copy is the one a future session reads.
- The record is publicly readable, because the repository is. Its `why` fields read as a
  roadmap-negative to an outside reader, which is why `public_note` exists and why `README.md` opens
  for that reader rather than for a Soleur engineer.
- What becomes harder: every rejection now costs a file with eight fields and a passing lint, and the
  record needs pruning as `revisit_if` triggers fire. That cost is deliberate — a rejection cheap
  enough to record carelessly is a rejection cheap enough to be wrong.
