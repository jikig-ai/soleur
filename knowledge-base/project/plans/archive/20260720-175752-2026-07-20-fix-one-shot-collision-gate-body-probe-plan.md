---
title: "fix: one-shot collision gate body probe fails silently open (#6786)"
date: 2026-07-20
type: fix
issue: 6786
branch: feat-one-shot-6786-collision-gate-body-probe
lane: cross-domain
requires_cpo_signoff: false
---

<!-- No spec.md exists for this branch, so there is no `lane:` to carry forward — defaulted to
     cross-domain (TR2 fail-closed). -->

# fix: one-shot collision-gate body probe fails silently open

`Closes #6786`

> **Revision note (v2, post-plan-review).** A 6-agent panel found the v1 plan's guard was
> disarmed by its own Phase 1 output, and that its invariant under-fit the defect class it
> named. Both were reproduced empirically and are fixed below. Sections marked **[v2]** changed.

## Overview

`plugins/soleur/skills/one-shot/SKILL.md` Step 0a.5 item 3 specifies a prose-`Ref #N`
blind-spot probe that returns **empty for every input**. It fails **silently open**: an empty
result is indistinguishable from "no collision", so the gate reports clean. The probe has
never fired since it was added (2026-07-18, PR #6674).

**The issue's stated diagnosis is wrong, and the fix it proposes is right for the wrong
reason.** GitHub does **not** strip the leading `#`. The defect is a `gh` CLI state-qualifier
conflict. This changes the fix from "drop the `#`" to "pass an explicit `--state merged`", and
changes the self-test's invariant from a `#`-prefix check to a `--state` check.

**Scope beyond the probe string [v2].** Plan review established that fixing the query alone
does not close the blind spot: once the probe fires, nothing in the surrounding prose *consumes*
its hits on the one path the probe exists for, and the nearest mechanical discriminator would
actively wave through the true positive. The fix is therefore query **+ disposition prose**, and
the lint is scoped to the defect *class* rather than this one call site.

## Premise Validation

Every premise the issue cites was re-measured against live GitHub on 2026-07-20 from this
worktree (`gh` 2.92.0, repo `jikig-ai/soleur`).

**Held:** #6786 is OPEN with no closing PR; `SKILL.md:57` contains the probe verbatim as
quoted; the probe as written returns **empty** (silent-open confirmed); the 2026-07-18 learning
exists and its reasoning is sound; PRs #6664 (`Ref #6608`) and #6209 (`Ref #6197`) are merged
and genuinely cite those issues.

**STALE — the issue's root-cause diagnosis is falsified.** Measured matrix:

| query | `--state` flag | hits |
|---|---|---|
| `#6608 in:body is:merged` | *(omitted → gh default)* | **0** |
| `6608 in:body is:merged` | *(omitted)* | 2 |
| `#6608 in:body is:merged` | `--state all` / `--state merged` | 2 |
| `#6608 in:body` | `--state merged` | 2 |
| `#6608 in:body` / `6608 in:body` | *(omitted)* | 0 |

Decisive discriminator — `gh search prs`, which does **not** apply `gh pr list`'s client-side
state defaulting:

```
gh search prs --repo jikig-ai/soleur "#6608 in:body is:merged"  -> [6664, 6639]
gh search prs --repo jikig-ai/soleur "6608 in:body is:merged"   -> [6664, 6639]
```

Identical. GitHub matches `#6608` in a PR body fine; the `#` is not stripped.

**Actual mechanism (confirmed).** `gh pr list --search` defaults to `--state open` and appends
an open-state filter *unless* it detects a state qualifier already in the query. A leading `#`
on the first token defeats that client-side detection, so `gh` appends the open filter anyway;
`is:merged` AND an open filter is a contradiction → zero rows, always. Corroborated:
`--search "… is:merged is:open" --state all` → 0, and `--search "… is:merged" --state open` → 0.

**Consequence.** Dropping the `#` works only because `gh` then successfully sniffs `is:merged`
and suppresses its default — undocumented client-side behaviour, the same fragility class that
caused this bug. The robust fix is an explicit `--state merged`, mirroring the sibling
`linked:issue` probe's existing `--state all`.

**Item 2 (the sibling probe) — resolved, no change.** Verified against two issues with genuine
formal links: `linked:issue #6737` → `[6743, 6726]` and `linked:issue #6724` → `[6727, 6717]`,
identical with and without `#`. It is immune because it already passes `--state all`.

## Research Reconciliation — Issue Claims vs. Measured Reality

| Issue claim | Measured reality | Plan response |
|---|---|---|
| "GitHub's search tokenizer strips the leading `#`" | False — `gh search prs` identical with/without `#` | Correct the diagnosis in SKILL.md, the learning, and the PR body |
| Fix = drop the `#` | Works only via `gh`'s undocumented qualifier sniffing | Fix = explicit `--state merged`; drop the redundant `is:merged` |
| "`linked:issue` may also be dead" | **Not dead** — verified on two formally-linked pairs | No change; record in PR body so it is not re-litigated |
| Self-test = assert no `#` prefix | Guards the wrong invariant; `#` is harmless | Invariant = every skill `--search` carries an explicit `--state` |

## User-Brand Impact

**If this lands broken, the user experiences:** the collision gate keeps passing clean on
issues whose work already merged under a prose `Ref`. Each occurrence burns a worktree, a
dependency install, an empty draft PR, and a ~147k-token planning subagent before `/plan`
Phase 0.6 catches the stale premise.

**If this leaks:** no data exposure. Cost is wasted API spend and operator attention.

**Brand-survival threshold:** `none` — internal developer-workflow gate, no user-facing
surface, no regulated data, no production runtime path.
`threshold: none, reason: the change edits skill documentation and a hermetic form-lint test; it touches no user-facing surface, no persisted data, and no production runtime code path.`

## Files to Edit

1. `plugins/soleur/skills/one-shot/SKILL.md` — Step 0a.5 item 3: fix the probe command and
   rewrite the disposition prose (Phase 1).
2. `plugins/soleur/skills/triage/SKILL.md` — line 32: add `--state all` to the orphan-alert
   probe. **[v2]** This is a live third instance of the same defect class (Phase 1b).
3. `knowledge-base/project/learnings/workflow-patterns/2026-07-18-one-shot-collision-gate-misses-prose-ref-merged-prs.md`
   — append a `## Follow-up (2026-07-20)` section (Phase 2).
4. `plugins/soleur/test/components.test.ts` — add the class-level form-lint (Phase 3).

## Files to Create

None.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200`; matched each planned path
against issue bodies. No matches on `one-shot/SKILL.md`, `triage/SKILL.md`, or the learning file.
Three matches on `plugins/soleur/test` — #4133 (observability schema-parity test), #3531
(marketing-content-drift flake), #3216 (historical review findings) — all unrelated concerns in
different suites. Disposition for all three: **acknowledge**; they remain open. No fold-ins.

## Implementation Phases

### Phase 1 — Fix the probe and its disposition (SKILL.md)

**1a — the command.** In `plugins/soleur/skills/one-shot/SKILL.md`, item 3 bullet 2, replace:

```
gh pr list --search "#<N> in:body is:merged" --json number,title,url --jq '.[] | "  #\(.number): \(.title)"'
```

with:

```
gh pr list --search "#<N> in:body" --state merged -L 100 --json number,title,url --jq '.[] | "  #\(.number): \(.title)"'
```

- **`--state merged` added** — the actual fix; removes the dependency on `gh`'s client-side
  qualifier sniffing and mirrors line 55's `--state all`.
- **`is:merged` removed from the query** — now redundant, and leaving it in preserves the
  contradiction surface that caused the bug.
- **`-L 100` added [v2]** — `gh pr list` pages at 30 by default (measured), and truncation is
  indistinguishable from a complete result set, which is the same silent-open shape.
- The `#` is **kept** — harmless (measured) and it is the form a reader transcribes naturally.

Verified at plan time: `#6608 in:body --state merged` → `6664, 6639`; `#6197 in:body
--state merged` → `6674, 6664, 6209, 6180` — surfacing #6209, the exact PR the broken probe
missed.

**1b — the disposition prose [v2].** Fixing the query alone converts a silent-open into a
*logged*-open. Four prose defects must be fixed in the same bullet:

- **Make the bullet self-contained.** The bullet currently says "interactive mode names the hits
  in the AskUserQuestion" — but item 3's two AskUserQuestions are both conditional on
  `linked:issue` returning something, and the body probe's entire reason to exist is the case
  where `linked:issue` is empty *by construction*. On that path there is no prompt to name hits
  in. Specify that when the body probe returns ≥1 hit and the other two signals are empty,
  interactive mode raises **its own** AskUserQuestion (verify / continue / abort) and headless
  mode logs under a distinct marker. Keep **surface-for-verification, not auto-abort** framing.
- **Disarm the wrong discriminator.** Bullet 1's cited-predecessor discriminator
  (`closingIssuesReferences` ABSENT → "citation, continue") is **structurally non-discriminating
  here**: a body-probe hit has no closing ref by definition. Measured on the motivating case —
  all four `#6197` hits return `[]`, *including the true positive #6209*, so a reader reaching
  for the nearest mechanical test is told to continue past the exact collision the gate exists
  to catch. State explicitly that it does not apply, say why, and give the bounded alternative:
  `gh pr diff <PR> --name-only` intersected against the issue's stated file targets, defaulting
  to "abort and verify" when uncertain.
- **Add fail-open error handling.** Item 1 handles `gh` non-zero explicitly; item 3's probes have
  none, so an auth expiry or rate-limit produces empty stdout that reads as "no collision" — the
  same silent-open, one layer up. Mirror item 1's one-sentence warn-and-continue clause.
- **Add a dedupe clause.** The body probe re-surfaces PRs already reported by `linked:issue`
  (both hit `6664` on `#6608`); instruct the agent to dedupe across the three signals so one PR
  cannot inflate apparent collision weight.

**1c — the mechanism note.** Add two tight sentences explaining the `gh` default-`--state`
conflict so the flag is not later "simplified" away. Keep it short: Step 0a.5 is read on every
dispatch, so prose here is a recurring token cost.

**1d — scope the claim.** Note the known-remaining escapes so this fix is not later read as
having closed more than it did: PR **title-only** references (`in:body` excludes titles —
measured: `#6608 in:title` → `6664`), and **search-index lag** (`_cron-shared.ts:900` documents
minutes of lag; a just-merged PR is invisible).

### Phase 1b — Fix the live third instance (triage/SKILL.md) [v2]

`plugins/soleur/skills/triage/SKILL.md:32` reads:

```
close it with a pointer to the dismissing PR (search via `gh pr list --search "alert #<N>"`)
```

No `--state`, so it defaults to open — while hunting a **dismissing** PR, which has almost
always merged. Same defect class, live in the repo today. Add `--state all`.

Measured: `gh pr list --search "alert #6786"` → 0 hits; the same search with `--state all`
returns rows. This is a one-token fix that closes the class rather than leaving a known
instance behind for the lint to flag on the next unrelated PR.

### Phase 2 — Update the learning file

Append a `## Follow-up (2026-07-20)` section. Do **not** edit the existing body — its reasoning
stands and it is a point-in-time record.

Content:

1. **The meta-lesson:** a probe added to close a blind spot must be **proven to fire** —
   demonstrated returning a non-empty result against a known-positive case — before the PR that
   adds it merges. An unverified probe is worse than no probe: it manufactures false confidence.
2. **The silent-open framing:** any probe whose "all clear" is an *empty result* cannot
   distinguish "no hits" from "malformed query", "auth failure", or "truncated page". Such
   probes need a positive control and explicit error handling.
3. **The corrected mechanism**, so the wrong diagnosis does not propagate.
4. **The repeat-offence note.** `2026-05-29-one-shot-collision-gate-must-probe-merged-prs.md`
   already fixed a `--state` blind spot on the sibling probe; the 2026-07-18 body probe
   reintroduced the same class at a new call site because the fix was a one-line patch, not an
   invariant. **[v2]** Note that a third instance (`triage/SKILL.md:32`) was found live during
   this work — the class had already spread twice before anyone linted for it.
5. **Move the grep sharp edge here [v2]:** a path-exclusion filter must be anchored on the
   filename field (`awk -F:` on `$1`), never matched against the whole grep output line. While
   writing this plan, `grep -v 'knowledge-base/project/learnings/'` matched the learnings path
   cited *in the offending line's own prose* and silently filtered out the one real violation,
   reporting a clean sweep — the plan's own subject matter, reproduced in its own tooling.
6. **Scope the original claim** to *body-text prose refs*, naming title-only refs and index lag
   as known-remaining.

### Phase 3 — Class-level form-lint [v2, substantially revised]

#### Decision: form-lint, not a live-API test

The issue suggests asserting the probe returns ≥1 hit for a known-good pair. **Rejected for
required CI**, on measured repo evidence:

- **The plugin suite is hermetic by construction and this is codified.** No test in
  `plugins/soleur/test/` makes a live HTTP call; network-shaped code is tested by injection or
  offline flags (`SKILL_SECURITY_SCAN_OFFLINE=1`, `SOLEUR_DOCS_OFFLINE=1`). AGENTS.md
  `[id: cq-test-fixtures-synthesized-only]` requires synthesized fixtures. A live test here
  would be both unprecedented and rule-violating.
- **The repo already engineered live network *out* of this exact shard** —
  `seo-aeo-drift-guard.test.ts` and `marketing-content-drift.test.ts` set `SOLEUR_DOCS_OFFLINE=1`
  specifically so a transient GitHub rate-limit "cannot fail the build … and surface as a flaky
  test." Adding one back reverses a deliberate decision.
- **The search index lags** (`_cron-shared.ts:900`, a measured cause of a prior miss), so a live
  search assertion is inherently racy.
- **Blast radius** — this lands in `test-bun`, feeding the **required** `test` aggregator. A
  flaky network assertion there blocks every PR in the repo.
- **The fixture is not durable** — merged PR bodies remain editable.

Accepted residual, named rather than hidden: the lint proves the probe is **well-formed**, not
that it **works**. A GitHub/`gh` semantic change would pass the lint. That is a low-rate,
externally-triggered event; `/plan` Phase 0.6 premise-validation remains the load-bearing
backstop, as the 2026-07-18 learning already concluded. No scheduled live-probe workflow is
added — new always-on infrastructure to guard a low-rate external event, with no repo precedent.

#### The invariant

v1 proposed "any `--search` carrying an in-query state qualifier must also carry `--state`".
**Plan review proved this under-fits.** The original 2026-05-29 defect had *no* in-query
qualifier — just a missing `--state` — so the v1 lint would not have caught occurrence #1. And
Phase 1 removes `is:merged`, so post-fix the v1 trigger has **zero population** in the linted
file: a required check that can never fire. Corrected:

> Every `gh pr list --search` / `gh issue list --search` command in any
> `plugins/soleur/skills/*/SKILL.md` MUST carry an explicit `--state` flag.

This subsumes both prior occurrences and the live third instance. **Measured offenders today: 2**
— `one-shot/SKILL.md:57` (Phase 1) and `triage/SKILL.md:32` (Phase 1b). Zero after both.

#### Lint on extracted commands, not raw lines

v1 filtered raw lines. SKILL.md bullets are single ~1,900-char lines mixing prose and command,
and Phase 1c's mechanism note necessarily contains the literal `--state` — so a line filter
excludes the line unconditionally. **Reproduced:** with the note present and the probe reverted
to the bug, the v1 line filter reported **0 offenders (vacuous — bug walks past)** while
command-extraction reported **1 (caught)**. v1's AC7 negative control would have recorded a
false green as proof.

Extract backtick command spans and assert on those:

```ts
const CMD = /`(gh (?:pr|issue) list --search[^`]*)`/g;

export function findStatelessProbes(
  files: { file: string; raw: string }[],
): { file: string; cmd: string }[] {
  return files.flatMap(({ file, raw }) =>
    [...raw.matchAll(CMD)]
      .map((m) => ({ file, cmd: m[1] }))
      .filter(({ cmd }) => !/--state\b/.test(cmd)),
  );
}
```

`findStatelessProbes` is exported as a **pure function** so the negative control is a permanent
synthesized-fixture test rather than a one-time manual ritual (this also satisfies
`cq-test-fixtures-synthesized-only` more cleanly than asserting against the live file alone):

```ts
describe("collision-gate probes carry an explicit --state", () => {
  // Permanent negative control — synthesized, no file I/O.
  test("detector flags a stateless probe", () => {
    expect(findStatelessProbes([
      { file: "f", raw: '`gh pr list --search "#1 in:body is:merged" --json number`' },
    ])).toHaveLength(1);
  });
  test("detector accepts a state-explicit probe", () => {
    expect(findStatelessProbes([
      { file: "f", raw: '`gh pr list --search "#1 in:body" --state merged --json number`' },
    ])).toHaveLength(0);
  });

  const files = [...new Glob("skills/*/SKILL.md").scanSync(PLUGIN_ROOT)].map((f) => ({
    file: f,
    raw: readFileSync(resolve(PLUGIN_ROOT, f), "utf-8"),
  }));

  // Anti-vacuity: a silently-empty glob must not turn the gate green.
  test("probe population is non-empty", () => {
    const n = files.flatMap(({ raw }) => [...raw.matchAll(CMD)]).length;
    expect(n, "no gh --search commands found — glob or regex broke").toBeGreaterThan(0);
  });

  test("no skill probe omits --state", () => {
    expect(
      findStatelessProbes(files).map((o) => `${o.file}: ${o.cmd.slice(0, 70)}`),
      "gh pr list --search defaults to --state open, so a probe without an explicit " +
        "--state silently misses MERGED PRs and the collision gate fails open. See #6786.",
    ).toEqual([]);
  });
});
```

**Pre-verified at plan time (2026-07-20).** This design was run from a scratch file:

- Against the **current** tree (bug present): `commands scanned: 6 | offenders: 1` → **FAIL**.
- Against a **fixed** simulation *with the Phase 1c mechanism note in prose*:
  `commands scanned: 6 | offenders: 0` → **PASS**.

So the lint is known to red-line on the defect and to survive the prose note — the precise
failure that killed the v1 design. The two-arg `expect(value, message)` signature was also
confirmed valid in `bun:test` (already used ~7× in `components.test.ts`).

**Placement:** `plugins/soleur/test/components.test.ts` — the canonical home for SKILL.md form
lints, already carrying named-skill sentinel probes over `one-shot/SKILL.md`. Lands in the
`test-bun` shard and gates on the required `test` check with **zero CI wiring changes**. Do not
add a `*.test.sh` (extra `test-all.sh` + `lint-orphan-test-suites.sh` registration for no gain).

## Acceptance Criteria

### Pre-merge (PR)

1. The `one-shot/SKILL.md` body probe reads
   `gh pr list --search "#<N> in:body" --state merged -L 100 …`, with **no** `is:merged` inside
   the `--search` string.
2. The bullet is self-contained: it specifies its own interactive prompt and headless marker for
   the case where the other two signals are empty, retains the `surface-for-verification` phrase,
   and is explicitly not an auto-abort.
3. The bullet states that `closingIssuesReferences` does **not** discriminate body-probe hits,
   and gives the `gh pr diff --name-only` alternative.
4. The bullet carries a fail-open `gh`-non-zero clause and a cross-signal dedupe clause.
5. The `linked:issue` probe at line 55 is **unchanged** (`git diff` shows no edit to that line).
6. `triage/SKILL.md:32` carries `--state all`.
7. `bun test plugins/soleur/test/components.test.ts` passes, including all four new tests.
8. `bun test plugins/soleur/test/` passes (no collateral breakage).
9. Test written **before** the fix and observed RED on the unfixed probe, per
   `cq-write-failing-tests-before` — the negative control is obtained in the natural TDD order,
   with no revert-and-restore dance.
10. The learning file gained an additive `## Follow-up (2026-07-20)` section (`git diff` shows
    additions only) that cites
    `knowledge-base/project/learnings/workflow-patterns/2026-05-29-one-shot-collision-gate-must-probe-merged-prs.md`.
11. PR body records that the `linked:issue #<N>` probe was **verified working** and needs no
    change, naming the pairs tested (#6737→#6743, #6724→#6727), **and** that the issue's
    `#`-stripping diagnosis was falsified with the `gh search prs` evidence — so neither is
    re-litigated.
12. PR body uses `Closes #6786`.
13. `npx --yes markdownlint-cli` clean on the edited markdown files.

### Post-merge (operator)

None. Documentation plus a hermetic test — no deploy, migration, infrastructure apply, or vendor
configuration. The fixed probe takes effect on the next `/soleur:one-shot` dispatch.

## Test Strategy

- **Runner:** `bun test` (`bun:test`). No vitest — vitest is `apps/web-platform`-only.
- **Local:** `bun test plugins/soleur/test/components.test.ts`, then `bun test plugins/soleur/test/`.
- **Shard-equivalent:** `bash scripts/test-all.sh bun`.
- **CI:** `test-bun` job in `.github/workflows/ci.yml`, feeding the required `test` aggregator.
  **No CI changes needed.**
- Never run bare `bun test` from the repo root (Bun FPE crash on recursive discovery —
  `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The lint proves well-formedness, not that the probe works. | Named explicitly here, in the learning follow-up, and in the PR body. `/plan` Phase 0.6 remains the load-bearing backstop. Not hidden. |
| The fixed probe now returns hits, creating a false-positive burden (measured: 3 of 4 hits on `#6197` are citations). | Phase 1b mandates a bounded discriminator (`gh pr diff --name-only` vs the issue's file targets), an explicit uncertain-case default, `-L 100`, and cross-signal dedupe. |
| Regex-based command extraction could miss a probe written outside a backtick span. | The anti-vacuity population test fails loudly if the extracted set empties. Backtick-fenced commands are the universal convention in these SKILL.md files (measured: 6 of 6). |
| Folding `triage/SKILL.md` in widens the PR beyond the issue's stated scope. | One token, same defect class, verified live. Leaving it would ship a lint that red-lines the next unrelated PR touching that file. |
| `--state merged` depends on `gh` behaviour that could change. | `--state` is a documented public flag; the alternative depends on undocumented client-side sniffing. The consumer is an agent re-reading the doc each dispatch, so drift is self-correcting on the next edit. |

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Drop the `#` (the issue's proposal) | Works only via `gh`'s undocumented in-query qualifier sniffing, and leaves the `is:merged`-without-`--state` contradiction surface armed. |
| Live-GitHub-API test in required CI | Rejected on measured evidence — see Phase 3: hermetic-suite convention, `cq-test-fixtures-synthesized-only`, documented index lag, and required-check blast radius. |
| Repo-wide lint script (`scripts/lint-gh-search-state.py`) covering all ~19 call sites | Genuinely better coverage, but most non-skill hits are prose *about* the command or negative-test fixtures, so it needs context restriction or a waiver token — real work beyond this fix. Scoped here to `skills/*/SKILL.md` (the executable-instruction surface where both prior occurrences happened). Deferred with a tracking issue. |
| Migrate to `gh search prs` | Sidesteps the bug (no client-side state defaulting) but changes output shape, needs explicit `--repo`, and diverges from line 55. Larger blast radius than one flag for no added safety. |

## Deferrals

**One deferral [v2].** The class-level lint covers `plugins/soleur/skills/*/SKILL.md`. Plan
review measured ~19 `gh …list --search` call sites repo-wide, including
`plugins/soleur/commands/sync.md:165`, `scripts/rule-prune.sh:239`, and
`knowledge-base/engineering/operations/runbooks/inngest-server.md:990`. Some legitimately want
open-only semantics — but should then say `--state open` explicitly, which is the same point.
Extending coverage needs prose-vs-command context restriction or a waiver token.

**Action:** file a tracking issue ("extend the `--state` explicitness lint beyond
`skills/*/SKILL.md`") with the enumerated call sites and re-evaluation criteria, milestone
`Post-MVP / Later`. Recorded here so the narrowing is deliberate and visible rather than an
unmentioned gap.

## Domain Review

**Domains relevant:** none. Infrastructure/tooling change — an internal developer-workflow gate.
The mechanical UI-surface override did not fire: no path in Files to Edit/Create matches any
UI-surface glob. Product/UX Gate: **NONE**.

## Observability

Plan Phase 2.9's trigger set (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`,
`plugins/*/scripts/`) does not fire — `components.test.ts` lives under `plugins/soleur/test/`.
But deepen-plan Phase 4.7's skip rule requires *every* Files-to-Edit path to be pure-docs, and a
`.ts` file is not. **Filled fail-closed rather than argued away** — a plan about silent-open
failures should not skip a gate on a technicality.

```yaml
liveness_signal:
  what: the `test` aggregator check on every PR (the form-lint runs in the `test-bun` shard)
  cadence: every push to any PR, and on merge to main
  alert_target: GitHub required-check failure on the PR; blocks merge
  configured_in: .github/workflows/ci.yml (`test-bun` job -> `bash scripts/test-all.sh bun`)
error_reporting:
  destination: CI job log + the PR's failed-check annotation; the assertion message names the
    mechanism, the consequence ("collision gate fails silently open"), and issue #6786
  fail_loud: true — the offender assertion is `toEqual([])` on a named list, so the failure
    output enumerates the offending file and command verbatim
failure_modes:
  - mode: a future probe is added without an explicit --state (the recurrence vector)
    detection: the offender test enumerates it from the extracted command set
    alert_route: required `test` check fails on that PR
  - mode: the glob or the extraction regex silently stops matching (lint goes vacuous)
    detection: the anti-vacuity population test asserts the extracted command count > 0
    alert_route: required `test` check fails
  - mode: GitHub/`gh` semantics change so the now-correct form stops returning hits
    detection: NOT covered by CI — accepted residual, named in Phase 3 and the learning
    alert_route: `/plan` Phase 0.6 premise-validation (the load-bearing backstop)
logs:
  where: GitHub Actions run logs for the `test-bun` job; retained per repo Actions settings
  retention: GitHub default (90 days)
discoverability_test:
  command: bun test plugins/soleur/test/components.test.ts -t "collision-gate probes"
  expected_output: 4 tests pass; on regression, the offender assertion prints the offending
    file and command plus the #6786 mechanism note
```

No SSH anywhere in the verification path.

## Architecture Decision (ADR/C4)

**Skipped — justified.** No architectural decision: no ownership/tenancy boundary moves, no new
substrate or trust boundary, no existing ADR reversed or extended. A competent engineer reading
the existing ADRs and C4 model would not be misled after this ships.

**C4 completeness:** no external human actor, external system/vendor, container, data store, or
actor↔surface access relationship is introduced or changed. GitHub is a pre-existing dependency
of the one-shot workflow; only a flag on an existing call changes. No `.c4` edit required.

## Enhancement Summary

**Deepened on:** 2026-07-20
**Plan-review panel:** 6 agents (dhh, kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, cto)

### Key improvements over v1

1. **The guard was disarmed by its own fix.** v1's line-based lint would have been excluded
   unconditionally once Phase 1's mechanism note put the literal `--state` in the same line's
   prose. Reproduced empirically (line filter: 0 offenders / command extraction: 1). Now lints
   extracted backtick command spans.
2. **The invariant under-fit its own defect class.** v1 required an in-query state qualifier
   before checking for `--state` — but the original 2026-05-29 occurrence had no qualifier, and
   Phase 1 removes the only one in the file, so the v1 trigger would have had zero population.
   Now: every skill `--search` carries an explicit `--state`.
3. **A live third instance was found.** `triage/SKILL.md:32` hunts a *dismissing* (merged) PR
   with no `--state`. Folded in — one token.
4. **The probe's hits had no consumer.** The bullet pointed at an AskUserQuestion that does not
   exist on the path the probe fires on. Now self-contained.
5. **The nearest discriminator inverts the verdict.** `closingIssuesReferences` is empty by
   construction for body-probe hits — measured `[]` for all four `#6197` hits *including the
   true positive #6209*, so it would say "citation, continue" on the real collision.
6. **Negative control moved from ritual to structure.** A pure exported detector with
   synthesized fixtures replaces v1's revert-and-restore dance, satisfying
   `cq-test-fixtures-synthesized-only` and `cq-write-failing-tests-before`.

### Verification performed during deepen

- All 14 cited PR/issue numbers resolved live; states match the plan's claims.
- Both cited rule IDs (`cq-write-failing-tests-before`, `cq-test-fixtures-synthesized-only`)
  confirmed active in `AGENTS.md` — no fabricated or retired IDs.
- All knowledge-base / plugins / scripts path citations resolve on disk.
- Gates 4.5 (no network keywords), 4.6 (threshold + scope-out valid, no sensitive paths),
  4.8 (no PAT-shaped variables), 4.9 (no UI surface) — all pass.
- The Edit anchor in Phase 1a is unique in the target file (1 occurrence).
- `markdownlint` clean on plan and tasks.
