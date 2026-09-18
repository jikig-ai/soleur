---
title: Cross-harness parity gate — a skill edit is an edit to four harnesses
date: 2026-09-18
issue: 8299
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Cross-harness parity gate (#8299)

## What We're Building

A **born-blocking, trigger-scoped census** asserting that every Soleur skill which
instructs an agent to invoke another skill or agent names the invocation form for
each supported harness — or holds a dated, issue-linked exemption.

Host: `plugins/soleur/test/harness-parity.test.ts`. It auto-runs under
`run_suite "plugins/soleur" bun test plugins/soleur/` (`scripts/test-all.sh:2634`),
so no `ci.yml` or `lefthook.yml` wiring is required.

**Population is derived by content, never listed** (ADR-193 §5): the skills whose
body contains an invocation instruction. Measured 2026-09-18: **38 of 98**.

| Verdict | Predicate | Today |
| --- | --- | --- |
| QUALIFIED | carries a harness marker block, OR names the forms for the required harness set adjacently, OR cites `plugins/soleur/lib/harness.ts` | 12 |
| EXEMPT | a row in the disposition ledger carrying date + issue + falsifiable reason | 0 |
| UNCLASSIFIED | neither | **26 → RED** |

A **coverage floor** (inverted `.highwater`, the
`scripts/lint-supabase-deprecated-endpoints.highwater` shape) pins the size of the
derived population. A *drop* is the failure condition — it means the extractor went
blind, which is the way this class of gate dies green.

## Why This Approach

The issue proposed a whole-tree census over all 98 skills plus a backfill of the
unmarked ones. Measured, that yields ~60 ledger rows asserting nothing real and 34
copy-paste blocks with no maintainer. Scoping the population to skills that
*actually carry an invocation instruction* makes every row load-bearing: the gate's
floor is "zero unclassified", not "98/98 marked".

Three repo constraints forced the shape:

- **ADR-193 §5** — "The population is DERIVED, never listed… A hand-maintained list
  is the snapshot that goes stale." The existing `UNION` array in
  `plugins/soleur/test/devin-cloud-mode.test.ts` is exactly that banned hand-list;
  this work absorbs and deletes it.
- **Advisory→blocking has never once happened in this repo** (zero-for-N;
  `knowledge-base/project/learnings/2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim.md`).
  So: born blocking, with the ledger as the recorded escape hatch.
- **Diff-scoping goes vacuously green** on shallow `actions/checkout`
  (`.../learnings/test-failures/2026-07-20-git-diff-scoped-lint-rules-go-vacuous-in-ci-and-on-merge.md`).
  Whole-tree census only.

## Premise Corrections

Every measured claim in the issue body is wrong. Re-derived against `origin/main`:

| Issue body | Measured 2026-09-18 |
| --- | --- |
| 99 skills; 64 marked; 35 unmarked | **98**; 64; **34** |
| "64 carry a harness marker block" | The 64 is a **Devin/cloud** number. `grok-harness-invoke` = **12** (pipeline skills only), a strict subset. **Codex is named by zero markers and zero skills.** |
| "0 tests asserting marker-block parity" | False — `devin-cloud-mode.test.ts:450` `describe("soleur-cloud-mode marker fleet")` asserts byte-identical blocks and pins `expect(marked.length).toBe(67)` |
| "32 skills using the bare `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` fallback" | **28** SKILL.md carry the `:-` form. The 74 figure counts files mentioning the variable at all — most use the *correct* bare anchor. 105 occurrences tree-wide. |
| "`GROK_PLUGIN_ROOT` … today it is unexamined" | False — **ADR-179** (accepted 2026-08-11) decided it; the ~105 residual sites are tracked by **open #7453**. |
| "four harnesses" | **Six trees, three kinds** (below). |

### The harness map the "four harnesses" framing hides

| Kind | Trees | Drift |
| --- | --- | --- |
| Path-shared (symlink / `paths=`) | Grok (`.grok/config.toml` → `../../plugins/soleur`), Codex (`.codex/config.toml`), Devin (`.devin/config.json`) | impossible for skills — same tree |
| **Generated** | `.grok/agents/` (67/68) via `plugins/soleur/scripts/sync-grok-agent-compat.ts`, drift-checked by `grok-inspect-contract.test.ts:54` (`--check`) | detected |
| **Hand-ported, no generator** | `.openhands/skills/` (63/68 agents), `.gemini/` (1/68 agents, 3 skills) | **by construction** |

**No tree mirrors the 98 skills.** `.grok/` holds zero skills; `.openhands/skills/`
are agent ports; Codex and Devin carry three shims each (`go`, `help`, `sync`).
There is no 98 × 6 matrix to ratchet against — which is why the census is scoped to
the skill tree's own prose, not to mirror completeness.

## Key Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| 1 | Scope = the census only | Mirror completeness and the `:-` migration are separate, already-owned concerns |
| 2 | Born blocking, ledger as escape hatch | Advisory→blocking is zero-for-N in this repo |
| 3 | Population derived by content (38), not directory (98) | ADR-193 §5; keeps every ledger row load-bearing |
| 4 | Host = `plugins/soleur/test/harness-parity.test.ts` | Auto-registers via `test-all.sh:2634`; needs frontmatter parsing the `.py` lints lack |
| 5 | Delete the `UNION` hand-list from `devin-cloud-mode.test.ts` | It is the ADR-193 §5 anti-pattern, and this gate supersedes it |
| 6 | Ledger = TSV, `devin-dispositions.tsv` shape | `.claude/hooks/devin-dispositions.tsv` (ADR-223 §5): disposition enum + mandatory reason + evidence |
| 7 | Floor = inverted `.highwater` on population size | Coverage floor, not offender ceiling; a drop means the extractor went blind |
| 8 | **Item 4 (placement) — resolved, not built** | `cq-agents-md-tier-gate`: harness parity has a single-file trigger (a SKILL.md edit) → domain-scoped → owning skills, **never AGENTS.rules.md** |
| 9 | **Item 5 (`GROK_PLUGIN_ROOT`) — out of scope** | ADR-179 decided it; open #7453 owns the residual. This work must not bless `:-`, and must not introduce `${GROK_PLUGIN_ROOT:-…}` as a second vector |
| 10 | No single convergent rule bullet | **ADR-224 §1** (accepted 2026-09-17): "No rule in this repository may say 'declaring a skills root is safe' without naming the harness it holds for." An unqualified bullet is the anti-pattern it names |
| 11 | Required harness set is declared explicitly by the gate | No marker names Codex today; the predicate must state which harnesses it requires rather than inferring it |
| 12 | Fenced examples resolve to ledger rows, not regex carve-outs | Keeps the exemption surface auditable; `cq-assert-anchor-not-bare-token` binds the anchoring |

## User-Brand Impact

- **Artifact:** the cross-harness parity census over `plugins/soleur/skills/**` and
  its disposition ledger.
- **Vector:** a self-hosted operator on a non-Claude harness follows plugin-shipped
  prose naming a Claude-only invocation form, hits a dead command at the moment they
  are trying to act, concludes the plugin is broken, and uninstalls without filing
  anything. The harm is **silent churn** — no error surfaced, no signal back.
- **Threshold:** `single-user incident`. Confirmed by CPO and CLO; ADR-179's own
  frontmatter carries the same threshold for this class.
- **Note for `user-impact-reviewer`:** enumerate *uninstall-without-report* paths,
  not visible-incident paths. The failure mode here is quiet.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

CMO omitted per `hr-new-skills-agents-or-user-facing`'s one-line-rationale allowance:
this is operator-facing dev tooling / agent infrastructure with no user-facing
surface to amplify.

### Product (CPO)

A hand-listed set of four harnesses "is a snapshot that was already wrong before the
issue was filed — that is the failure mode repeating itself one level up." Recommends
deriving the harness set and making an unrecognised tree RED rather than absent. The
operator is the *detector*, not the user; the user is a self-hosted installer on a
non-Claude harness, and the outcome is silent churn. On backfill: "the registry does
the real work" — the floor is zero unclassified, not 98/98 markers.

### Engineering (CTO)

Resolves the host to TypeScript (census needs frontmatter parsing the `.py`/`.sh`
linters lack). Diff-scoping is unreachable as designed; must be whole-tree. A naive
regex is unshippable — `Skill tool` appears in 14 skills, `/soleur:` in 32,
`skill: soleur:` in 16 — so the classifier, not the regex, is the whole design.
Confirms `devin-cloud-mode.test.ts:450` is the extension point, not greenfield.
Flags the 105 `:-` sites as standing ADR-179 violations that must be their own issue
(they are: #7453). Blast radius of a miss: all operators on non-Claude harnesses.

### Legal (CLO)

**No material legal surface** — no personal data, no processing activity, no Article 30
row, no DPIA. One watch-item: the repo is BUSL with two vendored MIT works
(`LICENSES/hallmark.MIT.txt`, `LICENSES/skill-security-auditor.MIT.txt`) backing
`frontend-anti-slop` and `skill-security-scan`. Neither is mirrored today; **if a future
backfill widens the mirrors to those two skills, MIT notice must travel with the copy.**
Harness directory names are nominative interoperability use; no vendor ToS surface in
`.gemini/settings.json`, `.openhands/hooks.json`, or `.grok/config.toml`. Binding
constraint: the ledger and any harness-root decision must not bless a `:-` form.
Ledger reasons must be dated, issue-linked and falsifiable — no bare "temporary".

## Capability Gaps

None blocking. Every primitive this gate needs already exists in-repo:

- Derived-population + 0-checked guard — `scripts/lint-credential-path-literals.py:417`
  (walks `plugins/soleur/skills/` at `:225`)
- Anti-vacuity floor contract — `ADR-193-anti-vacuity-floor-contract.md` (Decision 1:
  report `printf >&2` + `exit 1` directly, never through a suite helper; increment the
  case counter at the call site, never inside `$( … )`)
- Inverted coverage floor — `scripts/lint-supabase-deprecated-endpoints.highwater`
- Reasoned exemption ledger — `.claude/hooks/devin-dispositions.tsv` (ADR-223 §5)
- Generator + `--check` drift pattern — `plugins/soleur/scripts/sync-grok-agent-compat.ts`
- Per-skill enumeration precedent — `plugins/soleur/test/components.test.ts`

One **absence**, verified: there is no reusable census/floor/ledger helper. Each lint
is bespoke (`ls scripts/lib/` holds domain helpers only). Recorded as a productize
candidate rather than built here.

## Open Questions

1. **Which harnesses does the predicate require?** Codex is named by zero markers and
   zero skills today, so requiring it REDs all 12 currently-qualified skills until the
   canonical marker block gains a Codex line. Because `devin-cloud-mode.test.ts` pins
   the block byte-identical across 64 files, that is one edit propagated 64 times —
   mechanical, but it must be sequenced *with* the gate, not after it.
2. **Does the 38-skill trigger regex miss a real invocation shape?** It keys on
   `Skill tool`, `skill: soleur:`, `/soleur:<name>`, `spawn_subagent`, `run_subagent`,
   `subagent_type`. Mutation-test it: delete the guard and confirm the suite goes RED
   (`2026-09-11-the-linter-i-cited-as-my-oracle-passed-with-the-guard-deleted.md`).
3. **Ordering of the `UNION` deletion.** Removing it from `devin-cloud-mode.test.ts`
   while that file still asserts `expect(marked.length).toBe(67)` needs care — the
   backfill changes that count, so the two must move together or the suite REDs mid-PR.

## Productize Candidate

`census-floor-ledger` — a shared helper for the derive-population / assert-floor /
read-exemption-ledger triple. This is its **third** independent instance
(`devin-dispositions.tsv` + `devin-matcher-parity.test.sh`,
`lint-supabase-deprecated-endpoints.highwater`, and now harness parity), and
repo-research confirmed no reusable helper exists. Filed as a follow-up, not built here.

## Session Errors

1. **My own first measurement of the `:-` population was wrong** — I reported 74 skills
   using the fallback. 74 is the count of SKILL.md files *mentioning*
   `CLAUDE_PLUGIN_ROOT` at all; most use the correct bare anchor. The fallback
   population is 28 SKILL.md / 32 files / 105 occurrences. Caught by CLO reporting 32
   against my 74 and reconciling the denominators. This is the `N of M is two claims`
   rule applied to my own work: I had verified the numerator and inherited the
   denominator.
2. **The issue's `#8281` citation is a stale premise.** Its body says the correction
   "landed in that PR"; PR #8276 is **OPEN, not merged** (`mergedAt: null`). The
   correction is on a branch.
