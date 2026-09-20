# Decision Challenges — feat-one-shot-8289-kb-glossary-rejected-register

Issue: #8289. Plan: `knowledge-base/project/plans/2026-09-20-feat-kb-glossary-rejected-register-plan.md`

Headless pipeline run. Every entry below is a challenge to the operator's **stated direction**, so per
`plugins/soleur/skills/brainstorm-techniques/references/decision-principles.md` (ADR-084) the operator's
direction is the **default** and none of them has been applied. `ship` Phase 6 renders this file into the
PR body and files it as an `action-required` issue.

---

## DC-1 — Cut the two intake pre-checks from `plugins/soleur/skills/triage/SKILL.md`

**Context.** The issue body scopes item B11 to two surfaces: `plugins/soleur/skills/triage/SKILL.md` and
`plugins/soleur/agents/support/ticket-triage.md`.

**What the pipeline could not do.** Decide unilaterally to drop one of the three surfaces the issue
names, because that is a scope reduction rather than a technical fork.

**Default if unchallenged.** Both pre-checks land in `triage/SKILL.md` Step 1, scoped to what a `todos/`
finding actually is — an internally-generated review finding that can legitimately restate an
already-built or already-refused concept.

**Challenge if** you accept the measurement. Two domain leaders reached this independently:

- That file is not an issue-intake surface. Its own description reads *"This skill should be used when
  triaging legacy local todo files in todos/. For GitHub issues, use soleur:support:ticket-triage
  agent"*, and its body states *"The `soleur:review` skill now creates GitHub issues directly for all new
  findings. This triage skill handles only legacy local `todos/*.md` files that predate the GitHub issue
  integration."*
- A `todos/` finding is a per-file code defect ("Missing transaction boundaries at
  `<file>:<lines>`"), so there is no domain concept to redundancy-search and no concept that could
  have been previously refused.

- `grep -cniE 'dedup|duplicate|reject|declin'` over that file returns 0 today, so nothing is being
  extended — this would be net-new prose on a deprecated surface.


**One supporting claim in the challenge does NOT survive measurement, and it is recorded here rather
than quietly dropped.** The engineering lens argued the corpus is "effectively frozen: 59 committed
files, roughly 3 still pending". The file count and the last-commit date hold — `git ls-files todos/ |
wc -l` is 59, and the last commit touching the directory is `ae44051a8` (2026-09-09, a linter-corpus
cleanup). But **33 of those 59 carry `status: pending`**, not three
(`grep -rl '^status: pending' todos/ | wc -l` → 33). A corpus with a third of its entries unprocessed
is not frozen; the triage skill has a live backlog. This materially weakens the challenge and
correspondingly strengthens the operator's default. The remaining argument — that a per-file code defect
has no domain concept to match on — stands on its own and is the part worth ruling on.
**What changes if you accept.** The pre-checks land on `ticket-triage.md` and its `.openhands/` mirror
only. Acceptance criteria 9 and 10 lose their third surface; nothing else in the plan moves.

**What it costs to accept.** One of the three surfaces the issue explicitly names goes unedited, so the
PR no longer matches the issue body line-for-line.

---

## DC-2 — Cut the `kb-glossary` skill; keep the glossary file and its read-pointers

**Context.** The issue names G3 as a skill and its naming contract mandates the name: *"`domain-modeling`
(glossary half) → `kb-glossary`"*.

**What the pipeline could not do.** Delete a deliverable the issue names and whose name the operator's
own rename table fixes.

**Default if unchallenged.** `plugins/soleur/skills/kb-glossary/SKILL.md` ships, carrying the write
discipline, with `references/glossary-format.md` and `references/rejected-request-register.md` beneath
it.

**Challenge if** you accept the product lens's argument:

- The glossary needs a **file** and a **read wiring**. The consumers — `brainstorm`, `plan`,
  `spec-templates`, `architecture`, `operator-rephrase` — read the *artifact*, not the skill.
- A skill costs a `/soleur:go` routing row behind an eval-gated block, a `help.md` family entry, a
  `plugin.json` + README count bump, and a permanent row in a freshness tracker that reports
  `never_invoked` forever (measured: 67 of 67 existing skills read `never_invoked`, because the producing
  cron reads a gitignored JSONL from an ephemeral clone).
- By the issue's own contract, *"a skill nothing invokes is an orphan"*. `kb-glossary` would be invoked
  only when somebody deliberately remembers to sharpen a term — which is the write-mostly failure mode
  wearing a skill's clothes, and this repository has already produced that outcome once
  (`knowledge-base/project/learnings/technical-debt/`: 11 entries, 0 closures, #2723).
- Proposed alternative: put the four-part inclusion test in the glossary's own header, and put the
  sharpening trigger in `compound`, which already writes to the knowledge base after a fix ships. A term
  then gets sharpened when a real session proves it was ambiguous, rather than when someone recalls that
  a skill exists.

**What changes if you accept.** The bundle goes from four deliverables to three and from two new skills
to one, which removes `kb-glossary` from the routing / help / manifest / description-budget contract
entirely. `questionnaire-generate` — the deliverable that actually reaches the founder, *"a document to
send instead of a stalled session"* — absorbs the review budget.

**What it costs to accept.** G3 as written is not delivered as a skill, and the name `kb-glossary` the
operator fixed in the rename table goes unused.

---

## DC-3 — Defer the whole rejected-concepts record until the first external filer

**Context.** The issue scopes G2 as a deliverable of this bundle.

**What the pipeline could not do.** Drop an operator-named deliverable on measurement alone.

**Default if unchallenged.** The record ships in this PR with its reader, one narrowed seed entry, and
the advisory-only clause.

**Challenge if** you accept the measurement, which two lenses raised independently. There are **zero
external issue filers** (300-issue sample: `deruelle` 215, `app/soleur-ai` 68, `app/github-actions` 17),
`wontfix` has been applied to **zero issues in 3,182 closures**, and `NOT_PLANNED` across the last 400
closures is 14 — all machinery (`decision-challenge:`, `[gdpr-gate]`, a test name), none a refused
product concept. Non-Goal 2 already defers the requester-facing half on exactly this evidence; the
challenge is to apply the same criterion to the whole store rather than to half of it. The plan's own
cautionary precedent (`learnings/technical-debt/`: structured frontmatter, 11 entries, **0** closures,
#2723) had *two* owning skills and still rotted; this ships with the write path as a branch in a skill
whose corpus is a `todos/` backlog.

**What changes if you accept.** One issue is filed with the criterion Non-Goal 2 already wrote — *the
first rejection request from an author outside the org* — applied to the store as a whole. The bundle
ships the glossary, the two intake pre-checks (redundancy only), and `questionnaire-generate`. ADR-232,
the lint, its battery, the `lefthook`/pre-push/CI wiring, the README and the seed all come out.

**What it costs to accept.** G2 and half of B11 are not delivered, and the issue's second outcome clause
("'no' only has to be said once") ships as nothing.

---

## DC-4 — Cut `plugins/soleur/skills/kb-glossary/references/rejected-request-register.md`

**Default if unchallenged.** Two convention documents ship: the derived one in the skill (carrying the
attribution comment) and the founder-facing one at `knowledge-base/project/rejected/README.md`.

**Challenge if** you accept that a file created to host an attribution comment is a mechanism serving
another mechanism's constraint rather than a requirement — especially since the plan establishes twice
that the comment is **not** the licence discharge (`plugins/soleur/NOTICE` is). Writing the convention
once, Soleur-authored, in the README would satisfy G2 with one file.

**What it costs to accept.** The operator's contract says every file taking peer prose carries the
attribution comment; with no derived file for G2, there is no attribution target for the
`OUT-OF-SCOPE.md` port, and provenance for that half rests on the `NOTICE` stanza alone.

---

## DC-5 — Drop AC-L1 and AC-L2 (the shingle and Jaccard apparatus)

**Default if unchallenged.** Both ship, with the non-vacuity floor and positive control the legal lens
added.

**Challenge if** you accept that they serve no stated requirement. The operative authority — the
constitution's vendored-content clause — requires that *"the diff is grepped for the vendor's marks"*,
which is AC-24 and already in the plan. The source is MIT, which permits verbatim copying **with**
attribution, and `NOTICE` provides it; AC-L3 concedes in its own words that L1 and L2 are *"originality
hygiene, **not** the licence discharge"*. Cost to keep: a scorer extraction, a three-part AC, two test
scenarios, a Sharp Edge, and a `### Cut:` subsection.

**What it costs to accept.** The operator's constraints name this AC explicitly as bundle 2's precedent
("an 8-word shingle comparison … must return 0 shared shingles"), so dropping it drops a named
acceptance requirement.

---

## DC-6 — Cut the `spec-templates` and `architecture` glossary read-pointers

**Default if unchallenged.** All five named consumers get explicit pointers, plus the constitution
pointer added at R18.

**Challenge if** you accept that `spec-templates` and `architecture` are downstream of `plan` in the same
session and buy nothing `plan`'s pointer does not, and that the R18 constitution pointer now reaches them
anyway. The architecture lens separately showed the five-consumer set was bounded by the lifecycle byte
ceiling rather than by a property — `work` (82 hits), `ship` (57, and `soak`'s only definer *is* `ship`),
`review` (26) and `preflight` (19) all outrank the two proposed for cutting and none was wired.

**What it costs to accept.** Two of the consumers the issue names by name go unedited.

---

## Panel findings deliberately NOT recorded as challenges

- **Folding ADR-232 into the README** was recommended by the simplicity lens and is **declined on a
  workflow gate, not on taste**: `wg-architecture-decision-is-a-plan-deliverable` (migrated to plan
  Phase 2.10, still ACTIVE in `scripts/migrated-rule-ids.txt`) requires the ADR write to be a deliverable
  of the plan that makes the decision. Folding it would violate that gate.
- Every other panel finding was **Mechanical** — a falsified claim, an unreachable mechanism, a missing
  producer or a vacuous assertion — and is applied directly to the plan and logged there as R1–R27.
