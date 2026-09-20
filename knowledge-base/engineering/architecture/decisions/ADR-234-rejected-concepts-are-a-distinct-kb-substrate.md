# ADR-234: Rejected concepts are a distinct KB substrate from a `not-planned` close

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
**never filed as its own issue, and was never closed `not-planned`**. It lives in the body of a
*sibling* issue, #1050 (*"feat: service automation"*), which is closed **COMPLETED** — and which
carries the refusal in more structured detail than the roadmap does, under its own
§*Domain Review Findings (why server-side was rejected)* with the per-leader risk table.

The scoping matters, and an earlier revision of this ADR got it wrong. It asserted the refusal was
never filed at all, on the strength of
`gh issue list --state all --search "server-side playwright in:title"` returning `[]` — which it
does. Dropping `in:title` returns #1050 on the first hit. So the claim that no issue-search can
reach this refusal is **false as originally stated**, and the true one is narrower and still
decisive: a substrate keyed on `not-planned` closures cannot reach a refusal recorded inside an
issue closed COMPLETED, and a concept lookup would never rank a "feat: service automation" title
against the concept *server-side browser automation*. The refusal is durable; what is missing is a
concept key, and that is the gap this ADR closes.

The naming is part of the decision, not a presentational choice. `register` already names **eight
compliance artifacts** in this repository, carrying one settled compliance sense between them — the
seven `knowledge-base/legal/*-register.md` documents
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

1. `scripts/lint-rejected-register.sh` — walks the record **recursively**, symlinks included, every
   extension, discovered by walking rather than by reading a manifest; only the record's own root
   `README.md` is exempt. The over-inclusive walk is the decision, not an accident: the checks are
   stated over *no file in the record*, so every predicate narrowing the walk carves a hole in that
   claim, and a file in the hole is a member for every consumer (`generate-kb-index.sh` walks the
   record with no depth bound, so `soleur:kb-search` reaches it) while being a non-member for the
   guard. Measured on an earlier depth-1, regular-file, lower-case-`.md` walk: one clean entry plus
   three poisoned members reported *1 file(s) checked, clean*, rc=0.

   Three dispatches, because there is **not** one write chokepoint: a `lefthook.yml` pre-commit hook
   on the glob with `{staged_files}`, a pre-push mirror (the shape `client-pii-grep` already uses,
   for the `--no-verify`, `LEFTHOOK=0` and no-lefthook-installed cases), and a CI step over the
   **whole** record rather than the staged set.

   **None of the three blocks a merge, and this ADR does not claim otherwise.** The CI arm — the one
   that exists to cover the local bypasses — runs in the `lint-bot-statuses` job, which declares
   itself advisory and is absent from `scripts/required-checks.txt`, so a PR merges with it red.
   Promotion is a separate change, and its path is precedented rather than hypothetical: #6883 /
   [ADR-139](ADR-139-earned-green-required-for-reachable-surface-content-gates.md) promoted the
   credential-path guard by EXTRACTING it out of this same advisory job into its own required
   context, listed in `required-checks.txt`, the canonical ruleset JSON and
   `infra/github/ruleset-ci-required.tf`. The trap that makes the naive version wrong is the #6049
   auto-fabrication guard: the bot-PR composite action posts an unconditional green for every listed
   name and cannot reproduce a content-scoped scan over the bot diff, so adding this name would
   fabricate a pass for exactly the PRs the guard exists to police. ADR-139 is explicit that the
   unreachability argument is per-gate and never inheritable, so this guard needs its own derivation
   and cannot ride on that one. Until that work lands the guard is advisory at every dispatch, and
   the record's correctness rests on review. One rationale corrected rather than
   deleted: earlier text here cited "merge-resolution commits" as an uncovered case. Lefthook keys
   `merge` on `MERGE_HEAD` and this entry carries no `skip: merge`, so those DO run the guard; the
   genuinely uncovered merges are the clean one and the server-side one.
2. `plugins/soleur/test/lint-rejected-register.test.sh` — the lint's own behavioural battery, with
   direct anti-vacuity floors per [ADR-193](ADR-193-anti-vacuity-floor-contract.md).
3. The intake pre-checks in `plugins/soleur/skills/triage/SKILL.md`,
   `plugins/soleur/agents/support/ticket-triage.md` and `.openhands/skills/ticket-triage/SKILL.md` —
   the reader. The agent's pre-checks are read-only by its own declaration; the **write** path is the
   attended `triage` skill, behind the machine gate (the lint) and then a typed confirmation naming
   the concept.
4. `knowledge-base/project/rejected/README.md` — the convention, co-located with the record, carrying
   the advisory-only clause and the precedence rule in founder-facing prose.

The lint proves **internal consistency, not truth**, and it is worth being exact about how little
that is. It does **not** compare the entry's claim against its evidence — an earlier revision of this
paragraph said it does, and nothing in the guard reads a `searched` result and weighs it against
`redundancy_check`. What the guard checks is that each required field is present and non-empty, that
several of them have the right *shape* (the enum is a whole-value match; every `searched` line carries
a `-> <result>`; `public_note` is not a copy of `why`; a `superseded_by` resolves to a file that
exists), that no forbidden field appears under any spelling, that the filename's slug appears in the
entry's own `scope`, that no entry claims an authority it does not have, and that no two entries claim
one concept key.

Every one of those is a property of the text. An entry can satisfy all of them and be false. The gap
narrows outside the commit rather than inside it, because each `searched` line is a command plus its
result and is therefore re-runnable by a reviewer or a later session — the shape check is what makes
that re-run possible, and it is the whole of what the guard contributes to truth. The assertion that
needs the network — *no number in `prior_requests` resolves to an issue closed as `completed`* — is
deliberately **not** in the pre-commit tier. It is UNFILED, and named here rather than left implied:
the cost-of-filing arithmetic in `plugins/soleur/skills/review/SKILL.md` puts a tracker for it below
the crossover, so recording the residual with its trigger IS the disposition. The trigger is
concrete — the first entry carrying a `prior_requests` number, which the seed entry now does (#1050).
The unattended-triage precondition named in the advisory-only clause above is the same shape: it is a
precondition on work that has no tracker yet, so it is stated here and carried into whichever issue
eventually proposes that work.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| `gh issue list --state all --search <keywords>` over `not-planned` closures — already treated as authoritative by `scripts/sweep-followthroughs.sh:884`, which refuses to reopen one | Keyed on the **request's wording**, not the concept: GitHub search performs no synonym expansion, so "night theme" never reaches `dark-mode`. Carries a decision and no concept key or alias set. It does **not** lose the reason — a closed issue's body and comments persist, and #1050 above is the counterexample, its full per-leader risk table intact six months after closure. (An earlier revision of this row claimed otherwise; the durable-reason clause is withdrawn, and what survives is the keyword-index limit, which is sufficient.) Measured 2026-09-20: **187** `not-planned` closures against **3,193** closed issues |
| The `wontfix-stale` label plus `apps/web-platform/server/inngest/functions/sla-issue-process.ts` — the **fifth** mechanism, and the one this ADR nearly missed | The *default* `wontfix` label has been applied to **0** issues in repository history, which reads as "the label family carries no signal" and is the wrong reading: Soleur built its own in July 2026 and `wontfix-stale` now carries **30**. It is machine-driven (`WONTFIX_STALE_LABEL`, `action-required-sla-policy.ts:25`) and closes `state_reason: "not_planned"` at ≥30d inactivity. So it is a live refusal signal — but an **inactivity** one: it records that nobody answered, never that a concept was considered and declined, and it is keyed on an issue rather than a concept. It is also a second unattended `not_planned` closer, which the advisory-only clause above accounts for |
| The `deferred-scope-out` label plus `cron-stale-deferred-scope-outs.ts` | Not an opposite — it **converges**. The live label description is *"Review-origin issue that meets a scope-out criterion — does not block ship Phase 5.5"*, and that cron auto-closes a stale scope-out after a 90-day window (`STALE_WINDOW_MS`, line 56) with `state_reason: "not_planned"` (line 568), with no human in the loop. It is therefore a **delayed refusal reached by timeout**, which is precisely why the advisory-only clause above is load-bearing rather than decorative |
| ADR `## Alternatives Considered` tables — this very section, at scale | Records alternatives rejected **inside** an accepted decision, scoped to mechanisms rather than concepts, and unqueryable by concept. Measured at this branch's HEAD across **236** ADR files (**230** distinct ordinals — five are duplicated across eleven files and two are missing, which is itself the point): **nine** distinct live heading spellings (`## Alternatives Considered` 72, `## Alternatives considered` 55, `## Rejected alternatives` 18, `## Alternatives rejected` 3, plus five one-off suffixed variants) — no canonical form and no index. These tables are cited as a **sibling store the lookup also checks**; nothing is imported from them |
| `knowledge-base/project/learnings/technical-debt/` as the shape to copy | It is the **cautionary precedent, not the model**: structured frontmatter, **11** entries (9 live plus 2 archived), all `status: open`, none carrying a `linked_issue` — effectively no drain (#2723). The sharper point, and the reason this row is a warning rather than a recipe: that record is **not** readerless. `/soleur:resolve-debt` shipped as its reader in `7fba89d5a` (#3645, 2026-05-12), which is *exactly* the remedy this ADR adopts — ship the lifecycle reader in the same increment — and **131 days later the drain is still zero**. So shipping the reader alongside the record is necessary and demonstrably not sufficient; the no-list's kill test is therefore stated as a dated, falsifiable condition in Consequences rather than assumed from the reader's existence |
| Any issue-search substrate at all, however well keyed | **The load-bearing row.** A rejected-concepts record can hold a refusal that no *issue's own disposition* records — one embedded in a sibling issue that closed for an unrelated reason, or never filed at all — so no substrate keyed on issue state can reach it at any keyword quality. Verified on the seed concept: the server-side-Playwright refusal lives in the body of #1050, which is closed **COMPLETED**, so every `not-planned`-keyed alternative above misses it by construction while the issue itself remains perfectly searchable. The gap is the concept key, not the text. This is why the seed entry's `searched:` records an issue search alongside its `git grep` lines — an entry whose evidence never looked for a prior request is how #1050 came to be missed in the first place |

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
