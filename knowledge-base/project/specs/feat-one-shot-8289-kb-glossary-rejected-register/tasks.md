# Tasks — feat(kb): domain glossary + rejected-concepts record wired into triage

Issue: #8289 · Plan: `knowledge-base/project/plans/2026-09-20-feat-kb-glossary-rejected-register-plan.md`
Lane: `cross-domain` · Threshold: `single-user incident` · `requires_cpo_signoff: true`

Derived from the plan **after** the six-reviewer panel and its R1–R27 revisions. Read the plan's
`## Plan Review Revisions` before starting: three of its mechanisms were unreachable or vacuous as first
written, and the corrections are load-bearing.

Naming: the store is **the no-list** in prose, **rejected-concepts record** where a formal noun is
needed. Never "register" — that word has eight live compliance senses in this repo (D1).

---

## Phase 0 — Preconditions (no writes to shipped files)

- [ ] 0.1 Re-run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`; record `B_ALWAYS`.
- [ ] 0.2 Re-measure the description budget through `discoverSkills()`/`parseComponent()`. Record
      `<consumed>/<budget>`. Expect zero headroom.
- [ ] 0.3 Re-measure the skill count with `find plugins/soleur/skills -type f -name SKILL.md | wc -l`
      (**not** `ls -d`, which over-counts `flag-bootstrap/`). Expect 100 → 102.
- [ ] 0.4 `git fetch origin`, then re-derive the free ADR ordinal across **every** `origin/*` ref.
      Provisional: ADR-232.
- [ ] 0.5 Re-fetch the five peer blobs at `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` into the scratchpad.
      Read-only inputs; never committed.
- [ ] 0.6 Run `/soleur:gdpr-gate` against the plan document.
- [ ] 0.7 **Gate on Phase 4:** grep `docs/legal/` and `plugins/soleur/docs/pages/legal/` (9 documents
      each) for affirmative claims the questionnaire component would falsify. A published disclaimer's
      wording is a genuine veto candidate.
- [ ] 0.8 Confirm `plugins/soleur/skills/kb-glossary/` and `questionnaire-generate/` are free, and that no
      `questionnaire-*` family exists.

## Phase 1 — ADR first (the go/no-go gate for Phases 2 and 3)

- [ ] 1.1 Author the ADR via `/soleur:architecture`.
- [ ] 1.2 Write `## Alternatives Considered` with **five** rows, each carrying its measurement:
  - [ ] 1.2a `not-planned` closure sweep — keyword index, no synonym expansion, no concept key.
  - [ ] 1.2b `deferred-scope-out` — **converges** on `not_planned` after 90 days via
        `cron-stale-deferred-scope-outs.ts`; a delayed refusal, not an opposite (R9).
  - [ ] 1.2c ADR alternatives tables — mechanism-scoped, five live spellings, no index.
  - [ ] 1.2d `learnings/technical-debt/` — the cautionary precedent, not the model.
  - [ ] 1.2e **The load-bearing row:** the record can hold a refusal that was never filed as an issue.
        Verify on the seed concept itself.
- [ ] 1.3 Add the **precedence rule** (R10): an entry is evidence a refusal was recorded, never the
      refusal. On conflict the closure or the ADR wins and the entry is STALE.
- [ ] 1.4 Add the **advisory-only clause**: an entry may never be the sole basis for closing, labelling or
      auto-closing an issue; `deferred-scope-out` is never applied on a record hit.
- [ ] 1.5 **Stop-and-re-scope check:** if 1.2a turns out to answer "was this concept refused", halt and
      record a decision challenge rather than shipping a third store.

## Phase 2 — The glossary (PR-1, PR-2)

- [ ] 2.0 **Bump `SKILL_DESCRIPTION_WORD_BUDGET` FIRST** (R23) for `kb-glossary`'s description, in the
      established comment shape naming #8289 and the re-measured baseline. Writing a description before
      the bump leaves `components.test.ts` red for three phases.
- [ ] 2.1 `plugins/soleur/skills/kb-glossary/references/glossary-format.md` — entry format, the four-part
      inclusion test, the pointer-not-restatement rule, and the **miss path** (a materially ambiguous term
      absent from the glossary is a candidate entry; the consumer hedges and names the ambiguity in the
      committed artifact). Attribution comment after the frontmatter fence.
- [ ] 2.2 `knowledge-base/project/glossary.md`:
  - [ ] 2.2a Header: `review_cadence: biannual`, `last_reviewed`, the four-part inclusion test, and the
        **negative clause** naming `plugins/soleur/docs/pages/glossary.njk` and
        `knowledge-base/marketing/brand-guide.md` by path and stating it is neither.
  - [ ] 2.2b Seed only terms with an existing definer to point at. `lane` →
        `brainstorm/references/brainstorm-domain-config.md` `## Lane Inference` is the worked example.
  - [ ] 2.2c `register` as the first entry, as a **pointer with four disambiguated senses** (R17):
        compliance (the eight `knowledge-base/legal/*-register.md`), domain-model
        (`preflight/SKILL.md` Check 11), prose/voice (`operator-digest/SKILL.md` `## Register (how to
        write)`), and the verb. `_Avoid_` names both the banned synonym and "store".
  - [ ] 2.2d No attribution comment anywhere under `knowledge-base/`.
- [ ] 2.3 `plugins/soleur/skills/kb-glossary/SKILL.md` — the write discipline plus a
      `## When to self-invoke` section in the `operator-rephrase/SKILL.md` shape. Attribution comment.
- [ ] 2.4 Read-pointers, one line each, with the instruction text defined once in 2.1 and cited:
      `brainstorm`, `plan`, `spec-templates`, `architecture`, `operator-digest`.
- [ ] 2.5 `knowledge-base/project/constitution.md` — the inherited pointer (R18).
- [ ] 2.6 Rewrite `operator-rephrase` `## Vocabulary` as a **stop-list serving rule 5** (D3), not an
      approved-terms source. The string `ships with no vocabulary source` must be gone and the glossary
      cited.
- [ ] 2.7 `plugins/soleur/skills/compound/SKILL.md` + `compound-capture/SKILL.md` — the sharpening trigger
      at compound's existing "could a rule, hook or skill instruction have prevented this?" pass (R3).
      Without this the write discipline has no producer.

## Phase 3 — The no-list and its reader, one increment (PR-3, PR-4, PR-5)

- [ ] 3.1 **Battery before guard.** Write `plugins/soleur/test/lint-rejected-register.test.sh` from the
      design — RED. Note the path: `scripts/*.test.sh` is **not** glob-registered (R20).
  - [ ] 3.1a 16 rows across 5 axes (SUT, fixture shape, fixture direction, dispatch, cardinality). Rows
        1–11 and 13–16 RED; **row 12 is the must-PASS row** and is labelled as such.
  - [ ] 3.1b Harness rows H1–H3 + P1, including the `bad()`-misrouted-to-pass self-test (direction, not
        presence).
  - [ ] 3.1c Two direct floors in the ADR-193 shape; `MIN_AXES` counts axes, `MIN_CASES` counts rows.
  - [ ] 3.1d Stable case id per row; the emitted id set **equals** the matrix id set (AC-42).
  - [ ] 3.1e Source `plugins/soleur/test/lib/git-fixture-env.sh` by choice — the adoption gate does not
        cover this root (R21). Do not claim it does.
- [ ] 3.2 `scripts/lint-rejected-register.sh` — GREEN. Whole-value enum comparison
      (`not-implemented` **contains** `implemented`); forbidden keys `implemented_at`, `requester`,
      `requested_by`; required `aliases`, `scope`, `why`, `public_note`, `instead`, `revisit_if`,
      `searched`; slug-inside-`scope`; the advisory-only assertion; `superseded_by` entries excluded from
      matching.
- [ ] 3.3 Wire three dispatches (R14): `lefthook.yml` pre-commit on the glob with `{staged_files}`, a
      pre-push mirror in the `client-pii-grep` shape, and a CI step over the **full** glob.
- [ ] 3.4 `plugins/soleur/skills/kb-glossary/references/rejected-request-register.md` — the derived
      convention. Attribution comment. (See DC-4.)
- [ ] 3.5 `knowledge-base/project/rejected/README.md`:
  - [ ] 3.5a Opens with one paragraph **for the external reader**, in brand voice — GitHub renders it
        first on a directory listing.
  - [ ] 3.5b The field set, the `why`/`public_note` split, `instead:`, `revisit_if`, `aliases`, `scope`.
  - [ ] 3.5c The `YYYY-MM-DD-<concept-slug>.md` entry convention, so the lookup cannot match this file.
  - [ ] 3.5d Built-is-not-rejected stated **as a pointer**: an already-implemented `wontfix` is a
        redundancy finding whose record names where the implementation lives.
  - [ ] 3.5e The published `searched:` line format, the precedence rule, the advisory-only clause, the
        `superseded_by` reopen path, and ADR tables cited as a sibling store (imported from: nothing).
- [ ] 3.6 The **seed entry** `knowledge-base/project/rejected/2026-09-20-server-side-browser-automation.md`
      — narrowed to server-side, Soleur-hosted Playwright for tenant service automation, `instead:` naming
      the 3-tier answer, `scope:` naming `soleur:agent-browser`, the `playwright` MCP server and
      `soleur:ux-audit` as implemented and **not** refused (R24). This entry is the copyable shape.
- [ ] 3.7 The reader — two pre-check bullets in `plugins/soleur/agents/support/ticket-triage.md` **outside**
      the severity eval-gate markers, plus the per-issue detail block appended to `## Output Format`. The
      6-column table stays byte-identical.
- [ ] 3.8 The same bullets and block in `.openhands/skills/ticket-triage/SKILL.md`, anchored on `## Scope`
      — the eval-gate markers **do not exist** in the mirror. Cite #8306 for mirror completeness.
- [ ] 3.9 `plugins/soleur/skills/triage/SKILL.md` — pre-checks in Step 1, and a **fourth branch in Step 2**
      ("reject: record why") which becomes the only branch that removes a finding (R4). See DC-1.
- [ ] 3.10 Specify the redundancy pre-check **by reference** to `brainstorm/SKILL.md`
      `#### 1.1 Research (Context Gathering)`. Never restate its sweep.

## Phase 4 — `questionnaire-generate` (PR-6, PR-7) — gated on 0.7

- [ ] 4.1 Top up the description budget for this skill's description.
- [ ] 4.2 `references/questionnaire.template` — attribution comment on **line 1, above frontmatter**
      (the emitter strips the first line). Do not use the after-the-fence placement here.
- [ ] 4.3 `knowledge-base/project/questionnaires/README.md` — the emission path
      `YYYY-MM-DD-<recipient-role>-<topic>.md`, the frontmatter contract (`recipient_role`, `needed_by`,
      `blocked_decision`, `status: sent|answered`), the `## Answers` section and the `## Blocked on`
      back-pointer (R5, R6).
- [ ] 4.4 `plugins/soleur/skills/questionnaire-generate/SKILL.md` — G1–G7:
  - [ ] 4.4a G1 interview the send, never the subject (three questions: who, what back, by when).
  - [ ] 4.4b G2 **allowlist** the `## Context` paragraph — no knowledge-base read on the drafting path.
        Never draft-then-redact.
  - [ ] 4.4c G3 compute-then-preview + typed confirmation before the file is sendable.
  - [ ] 4.4d G4 `redact-sentinel.sh` as a floor; fail closed on exit 2.
  - [ ] 4.4e G5 self-describe as a list of questions, not a position or advice.
  - [ ] 4.4f G6 the glossary stop-list on the outbound path.
  - [ ] 4.4g G7 **voice**: brand-guide General register, first-person singular, Jikigai where an entity is
        required, the word "Soleur" absent.
  - [ ] 4.4h The refusals: no fact the founder did not say out loud this session; no claimed knowledge they
        lack; no forged attribution; no question whose answer they are obliged to hold.
  - [ ] 4.4i The strip-the-first-line emitter rule.
- [ ] 4.5 `.claude/hooks/pre-ask-technical-fork-gate.sh` — rung 5 **and** the `EXTERNAL_EXPERT_RE` arm
      evaluated **before** the `AUTHORITY_RE` short-circuit at line 84 (R1). Rung 5 alone is unreachable.
- [ ] 4.6 `.claude/hooks/pre-ask-technical-fork-gate.test.sh` — a **behavioural** case: an external-expert
      question returns `permissionDecision: "deny"` with a reason naming the skill. Bump the inventory.
- [ ] 4.7 `scripts/followthroughs/questionnaire-unanswered-8289.sh` — notify-only, exits 2/3/5, never 0/1.

## Phase 5 — Wiring, then the ratchets, then the panel

- [ ] 5.1 `plugins/soleur/commands/go.md` — one routing row per new skill, before `default`, inside the
      eval-gate markers. Specify the `kb-glossary` row's trigger signals.
- [ ] 5.2 `plugins/soleur/commands/help.md` — the `questionnaire-*` family token in **all three** harness
      blocks. Note the Grok block uses a paren form, not brackets.
- [ ] 5.3 `plugins/soleur/docs/_data/skills.js` — a `SKILL_CATEGORIES` row per new skill (R15).
- [ ] 5.4 `plugins/soleur/test/lib/shingles.ts` — extract `neutralize`/`shingles`/`jaccard`; import from
      `agent-originality.test.ts` and the new check (R22).
- [ ] 5.5 `plugins/soleur/NOTICE` — the `(#8289)` `Used in:` group with real host files, the bundle-3
      `Portions adopted:` paragraph, all four deliberately-not-adopted items, the narrowed emission
      sentence. Pinned SHA unchanged.
- [ ] 5.6 `bash scripts/generate-kb-index.sh`; `soleur:release-docs` +
      `bash scripts/sync-readme-counts.sh --check`.
- [ ] 5.7 `soleur:eval-harness` — `--dry-run --target go-routing` first (0 API calls), then the gated run.
      **Disclose ~144 Anthropic API calls.** Attach the verdict.
- [ ] 5.8 The nine repo-global ratchets, each by its own invocation (see the plan's Phase 5 block).
      `lint-skill-body-budget.py` **requires** `--base`.
- [ ] 5.9 `python3 scripts/lint-guard-contract.py` on the plan; `plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 5.10 The vendor-mark grep, **path-scoped to the payload tree** and excluding
      `knowledge-base/project/{plans,specs}/**` (R26), with the sanctioned-form `grep -v` retained. Then
      the AC-L1/L2 shingle comparison.
- [ ] 5.11 Only then `soleur:review` / the panel.

## Phase 6 — Immediately before merge

- [ ] 6.1 Re-fetch and re-derive the ADR ordinal across every `origin/*` ref.
- [ ] 6.2 On renumber, sweep the whole artifact set in the same edit:
      `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/` plus the ADR body and every AC naming it.
- [ ] 6.3 File the three tracking issues (Non-Goal 1, Non-Goal 3, the `soleur:review` intake surface), each
      with its triple-test justification. Non-Goals 2, 5, 6 stay documented in place.
- [ ] 6.4 Confirm `decision-challenges.md` carries DC-1…DC-6 and that `ship` Phase 6 will render it.
- [ ] 6.5 PR body: `Closes #8289` only. Do not touch #8290 or #8292.
