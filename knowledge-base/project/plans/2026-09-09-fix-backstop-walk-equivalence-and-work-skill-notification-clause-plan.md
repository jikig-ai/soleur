---
title: "Correct work/SKILL.md's false notification clause, and reconcile #7956 against the open PR that already fixes it"
date: 2026-09-09
slug: fix-backstop-walk-equivalence-and-work-skill-notification-clause
branch: feat-one-shot-7956-7957-backstop-e2e-guard-and-work-skill-lint
issue: 7957
closes: [7957]
type: bug
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-09-09. **Panel:** `dhh-rails-reviewer`, `kieran-rails-reviewer`,
`code-simplicity-reviewer`, `architecture-strategist`, `cto` (devex), `spec-flow-analyzer` — all six
run at plan-review, plus the deepen-plan halt gates (4.6–4.11) and two round-1 realism passes.

### Key improvements

1. **The #7956 half was cut entirely.** `cto` found open PR #7879 already implements it — better —
   and adds a `T5c` guard that would have failed the approach this plan originally proposed.
   Independently confirmed by `kieran` and `architecture-strategist`. #7956 is also a duplicate of
   open issue #7886, which #7879 closes.
2. **A design defect was caught that would have shipped a silent regression.** `spec-flow-analyzer`
   established that the original Phase 3 (skip on `reason == claude_pid_not_found`) would make a
   *broken* `discover_claude_pid` report GREEN — that reason is the only one a broken discovery
   function emits, and the plan's own risk table wrongly claimed AC7 bounded it.
3. **AC6 was corrected from asserting a mechanism to asserting the property.** `kieran` caught that
   the original filter encoded single-backtick repair. Re-measuring produced a genuine reversal:
   the naive double-backtick form **loses** the trailing space.
4. **Two learning files were added to scope** so the corrected paragraph does not cite sources that
   restate the error, and so a forward-pointing "ready to apply" note does not go stale on merge.
5. **A process gap was identified and closed in the plan itself**: Phase 0.6 validates what an issue
   *cites*, never what is already *in flight* against the same files. Two `gh` commands, now Phase 2
   step 1.

### Claims verified during the deepen pass

| Claim | How it was verified | Result |
|---|---|---|
| The hook's walk is one hop deeper than the suite's | Drove the real `discover_claude_pid` against a synthetic `procroot` at depths 6/8/9/12 | **Confirmed** — hop 8 → `107 comm`, hop 9 → `NOT_FOUND` |
| The failing arm is already inside the E2E guard | Structural map of the `if`/`else`/`fi` nesting | **Confirmed** — closes at `fi   # end E2E gate` |
| Nothing skipped in the reported run | The issue's own `[live: yes]` tag against the suite's `_livetag` logic | **Confirmed** — `skipped_live == 0` |
| markdownlint is clean on `work/SKILL.md` | `bash scripts/markdown-lint.sh` | **Confirmed** — `1 file(s) clean` |
| AC4 alone is vacuous | Mutated `` `## ` `` → `` `##` ``, ran both checks | **Confirmed** — linter exit 0, AC6 exit 1 |
| The double-backtick repair form preserves the space | Rendered all three forms through CommonMark's stripping rule | **Refuted** — symmetric padding renders `##`, losing it |
| MD052 `[i][0]` resolved as a consequence of the backtick repair | Read `ae44051a8`'s diff at that line | **Confirmed** — the `[i][0]` text is byte-identical on both sides; only the span delimiters changed |
| The 2026-05-20 learning is about liveness, not verdict | Read its findings and Solution sections | **Confirmed** — it concerns "is the process dead?", so it is correctly scoped out of AC3 |
| `AGENTS.rules.md` has no room for a new rule | `python3 scripts/lint-agents-rule-budget.py` | **Confirmed** — 1 byte of headroom |
| `MAX_WALK_HOPS` cannot be reassigned in the suite | `readonly` reassignment probe | **Confirmed** — exits 1; moot now that the half is cut |

### Gates

4.6 User-Brand Impact **pass** (threshold `none`, no sensitive path, scope-out present) · 4.7
Observability **skip** (reconciled with Phase 2.9; reasoning recorded) · 4.8 PAT-shaped **pass** (no
matches) · 4.9 UI wireframe **skip** (no UI surface) · 4.10 Encryption posture **skip** (no store or
connection) · 4.11 Guard Contract **skip** (deliverable contains no guard once #7956 was cut).

---

## Overview

Two issues were assigned. Verification moved both, and one of them out of scope entirely.

**#7957 is real, unblocked, and is this plan's deliverable.** The `work` skill contains a
measurably false sentence: it tells the reader a backgrounded command's completion notification is
a trustworthy verdict. A background task's exit code is the last command in the backgrounded
string, so a trailing convenience line becomes the verdict. The correction is one paragraph,
supplied verbatim by the issue. The issue's second half — twelve markdownlint violations said to
block editing the file — was already resolved by PR #7955, so that half converts from a repair task
into a regression check.

**#7956 is a duplicate of #7886, and is already fixed — better — in open PR #7879.** That PR
deletes the suite's second ancestry walk outright, replaces the precondition with a read of the
hook's own logged outcome, and adds a standing drift guard (`T5c`) whose failure text names this
exact defect. Implementing #7956 as filed would trip that guard and revert an adopted design. This
plan therefore does **not** implement it; it reconciles it and captures the genuine residue #7879
leaves behind.

The first draft of this plan did implement #7956, with a five-row mutation matrix and a
depth-independent rewrite of both walks. A six-reviewer panel found that design superseded,
internally contradictory, and — in its central relaxation — actively wrong. That history is
recorded rather than quietly dropped, because the cheap probe that would have caught it (*is
anything already open against this file?*) is the process gap worth keeping.

No `spec.md` exists for this branch, so `lane:` could not be carried forward and defaults to
`cross-domain` (TR2 fail-closed). The Domain Review below nonetheless concluded engineering-only
on the merits: the diff is two markdown files.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality on this branch | Plan response |
|---|---|---|
| #7956 is an open, unaddressed defect | **Duplicate of #7886** (OPEN — *"memory-backstop.test.sh fails under lefthook and passes standalone"*), which is the `#7854` half of **open PR #7879** (`feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry`, non-draft, MERGEABLE, updated 2026-09-09, touching `memory-backstop.test.sh` and the mutation battery). | Do not implement. Reconcile: comment, dedupe, file the residue. |
| #7956: "one T8 arm sits **outside** the skip guard" | **False.** The failing `fail "T8 real hook did not apply"` sits in the `else` arm of `if [[ "$outcome" == "applied" …`, and the E2E gate closes *after* it at `fi   # end E2E gate`. The arm is already inside. | The issue's preferred fix is a no-op. |
| #7956: "`E2E=no` and the suite correctly skips seven live arms" | **Not what happened.** The issue's own pasted output ends `[live: yes]`; the suite renders `"yes, e2e SKIPPED"` whenever `skipped_live > 0`, so `[live: yes]` proves `skipped_live == 0`. Nothing skipped. The seven arms live inside the `outcome == applied` branch and simply never emitted. | Diagnosis corrected — and #7879 already encodes the corrected one. |
| The real mechanism | **Measured.** `MAX_WALK_HOPS=8`; the suite walks from its own `$$`, the hook from the hook's `$$` — a direct child — so the hook's chain is one hop longer. Probed against the real `discover_claude_pid` with a synthetic `procroot`: claude at hop 6 → `105 comm`; hop 8 → `107 comm`; hop **9** → `NOT_FOUND`. #7879's skip text states the same thing: *"the hook runs one process deeper than this suite, so at lefthook depth claude sits outside its `${MAX_WALK_HOPS}`-hop limit"*. | Confirms the diagnosis and confirms #7879 owns it. |
| #7957 §2: "12 markdownlint violations block editing the file" | **Already resolved.** `bash scripts/markdown-lint.sh plugins/soleur/skills/work/SKILL.md` → `markdown-lint: 1 file(s) clean.` PR #7955 (`ae44051a8`) repaired them per-site, as #7957 prescribed. | Converted to a regression AC. |
| #7957 §2: use double-backtick spans for trailing-space sites | **Measured, and it reverses the suggestion.** CommonMark strips one space from *each* end when the content both begins and ends with a space — so the natural double-backtick spelling `` `` ## `` `` renders as `##` and **loses** the space, while the repo's `` `## ` `` renders as `## ` and keeps it. #7955 used the single-backtick-plus-`disable-line` idiom documented in `scripts/markdown-lint.sh`'s remediation block, at three lines covering all four contexts. | Assert the **rendered** property (content ends in a space), never a source form. Full three-form table in AC6. |
| #7957 §1: the false clause exists only in `work/SKILL.md` | **Understated.** The same claim sits in the learning that paragraph cites — `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`. Correcting only the skill leaves it citing a source that restates the error. | Folded in. |

## Research Insights

### Premise Validation (Phase 0.6)

Every cited artifact was probed. **#7957** is `OPEN`. **PR #7912** (`MERGED` 2026-09-09) and **PR
#7828** (`MERGED` 2026-09-07) are contextual citations; #7912 also appears inside the replacement
prose as literal file content, not a work target. **#7909** and **#7910** are `CLOSED`, consistent
with the provenance note. Every cited path exists.

**Two premises failed, and a third probe was missing entirely.** #7956's preferred fix is a no-op
against `HEAD`; #7957 §2's blocker was cleared by PR #7955. Neither was discoverable from the issue
text — only from the files.

The missing probe is the one that mattered most: **nothing checked whether an open PR or a sibling
issue already owned the same surface.** Phase 0.6 validates artifacts the issue *cites*; it does not
ask what else is in flight against the files the plan will edit. That gap let a full design reach
plan-review before `cto` found #7879. The cheap version is two commands, and they are now the first
step of Phase 2 below:

```bash
gh pr list --state open --search "memory-backstop"          # open PRs on the surface
gh issue list --state open --search "memory-backstop.test.sh in:title,body"
```

One **option-bounding capability claim** was verified rather than assumed
(`hr-verify-repo-capability-claim-before-assert`): the 2026-09-08 learning asserts `AGENTS.rules.md`
sits at its ratchet, which would block adding a rule for this class. Measured —
`python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` returns
`[WARN] B_ALWAYS=45999 >= 44000` against the 46000-byte ratchet: **1 byte of headroom**. The claim
holds; this plan adds no AGENTS rule.

### Property List (Phase 0.6b)

1. The `work` skill's wrapper-as-guard paragraph contains no false claim about completion
   notifications, and records the #7912 two-writers recurrence route.
2. **No file in the repo states the notification-as-verdict claim as live guidance** (widened from
   "the paragraph" so the cited learning has a home — a `code-simplicity` finding).
3. `plugins/soleur/skills/work/SKILL.md` passes markdownlint.
4. Each deliberate-trailing-space code span in that file still renders content that **ends in a
   space**.
5. #7956's defect is resolved, its duplicate relationship is recorded, and the part no in-flight
   work covers is tracked.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Why it is cut |
|---|---|---|
| Rewrite both `/proc` walks to be depth-independent | 5 | **Already bought, better, by open PR #7879** — which deletes the second walk entirely rather than aligning two. Its `T5c` guard actively **fails** if an independent walk reappears, so building this would trip a standing guard and revert an adopted design. An archived plan had already adjudicated and *demoted* the align-the-two-walks approach. |
| Discriminate `reason == claude_pid_not_found` → skip | 5 | Cut as **wrong**, not merely redundant. That reason is the only one a *broken* `discover_claude_pid` can emit, so skipping on it makes a genuine discovery regression report GREEN. #7879 classifies a *set* of reasons and, by deleting the second walk, removes the disagreement state altogether. |
| A five-row mutation matrix + two harness rows | 5 | Cut. An executable mutation battery already exists (`.claude/hooks/memory-backstop-mutation-battery.sh`, with `run_synthetic`, `mutated_or_die`, killed/survived counters and a non-zero exit), and #7879 adds to it. Hand-writing a prose matrix beside it produces unrepeatable PR-body evidence. |
| A `${#LIVE_LABELS[@]}` count floor | — | Cut: maps to no property, and reintroduces the snapshot count the plan's own Assembly section forbade one paragraph earlier. |
| "Fix the 12 markdownlint violations" as a repair task | 3 | **Already bought** by PR #7955. Measured. Retained as verification. |
| A standing drift-guard test for the four trailing-space spans | 4 | Cut per minimality: the sites are self-marking via their `disable-line` comments, and the check is a one-time PR-gate concern. |
| A new `AGENTS.md` rule for the notification class | 1 | Cut on measured budget (1 byte of headroom). `work/SKILL.md` is the issue's own chosen home. |

### Value-Proposition Measurement (Phase 0.6c)

Not applicable — neither issue's justification is a cost or performance saving. No saving is
claimed, so none is quantified.

### Relevant institutional learnings

Worktree-relative paths (`hr-when-in-a-worktree-never-read-from-bare`).

- `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`
  — the #7828 source learning. **Carries the same false clause**; folded into scope.
- `knowledge-base/project/learnings/2026-09-08-the-rule-propagated-the-distrust-stopped-at-commands-i-wrote.md`
  — records that the correction is tracked as #7957 and names both blockers. Both re-measured.
- `knowledge-base/project/learnings/2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`
  and `knowledge-base/project/learnings/best-practices/2026-07-03-live-cap-rpc-test-aged-seed-daily-isolation-and-audit-equals-K.md`
  — both independently measure the trailing-echo exit-masking class the correction describes.
- `knowledge-base/project/learnings/2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md`
  — why a linter must not rewrite bytes a suite asserts on; why MD038 is silenced at the site
  rather than "fixed".
- `knowledge-base/project/learnings/security-issues/2026-09-06-the-file-i-added-to-fix-a-p1-shipped-a-p1.md`
  — `guard_narrower_than_the_property_it_names`, the shape of the #7956 defect and of the first
  draft's own ledger fix.

### Codebase facts established

- `lefthook.yml` runs `bash scripts/markdown-lint.sh {staged_files}`; that script is the single
  invoker, pins both the CLI and the rules engine, and derives scope from `.markdownlintignore`.
- `.markdownlint.json` disables MD013, MD024, MD025, MD018, MD028, MD026, MD029, MD033, MD036,
  MD040, MD041, MD056, MD060 — **MD038 and MD052 are active**.
- `work/SKILL.md` carries three `markdownlint-disable-line MD038` directives, covering four
  deliberate-trailing-space spans (`bash `, `attr = `, `## `, `### `).
- `lefthook.yml`'s `plugin-component-test` fires on `plugins/soleur/**/*.md`, so editing the body
  runs `bun test plugins/soleur/test/`. The edit does not touch the frontmatter `description:`, so
  the cumulative `SKILL_DESCRIPTION_WORD_BUDGET` (2400) is unmoved and no sibling trim is needed
  (Phase 1.8: no `description:` edit appears in the final `## Files to Edit`).

## Open Code-Review Overlap

- **#7208** — *memory backstop (#7166): post-merge hardening from the PR #7169 review panel*. Names
  both backstop files. **Acknowledge / defer:** this plan no longer edits either file, so the
  overlap is dissolved rather than managed. The residue issue filed in Phase 2 should cross-link
  #7208 §B (mutation coverage of `discover_claude_pid` / `read_ppid`) so the two are not worked
  twice.
- **PR #7879** is not a `code-review` issue but is the dominant overlap; it is handled as the
  subject of Phase 2 rather than as a footnote.

## User-Brand Impact

**If this lands broken, the user experiences:** documentation that still tells them to trust a
signal that is measurably wrong — the direct cause of a green gate reported over a failed commit.
No runtime surface changes.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The change
edits two markdown files; nothing processes user data, holds a credential, or reaches a network.

**Brand-survival threshold:** `none`.

Scope-out bullet: `threshold: none, reason: the diff is confined to documentation prose in a plugin
skill and a learning file — no user data, no credential, no network, no production surface.`

## Implementation Phases

### Phase 1 — #7957: correct the false clause (the deliverable)

1. Apply the issue's two hunks **verbatim** to the wrapper-as-guard paragraph in
   `plugins/soleur/skills/work/SKILL.md` — the replacement prose and the `**Why:**` addition,
   exactly as #7957 quotes them. The embedded `#7912` reference is literal file content.
2. Repair the citation the correction creates: add a correction note to the Prevention bullet of
   `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`,
   which states the same false claim and is the file the corrected paragraph cites. Correct the
   **prescriptive rule**; leave the session narrative intact.
3. Verify per `## Acceptance Criteria`. Take every verdict from a redirected log's own `RC=` line —
   never a pipe, never a background task's completion notification. This PR's subject forbids it.

### Phase 2 — #7956: reconcile, do not implement

1. **Run the in-flight probe first** (the step whose absence produced the first draft):
   `gh pr list --state open --search "memory-backstop"` and
   `gh issue list --state open --search "memory-backstop.test.sh in:title,body"`. Confirm #7879 is
   still open and #7886 still names the same defect; if #7879 has merged, verify the fix on `main`
   instead.
2. **Comment on #7956** recording that it duplicates **#7886**, that **PR #7879** implements the
   fix by deleting the second walk rather than aligning two, and that the diagnosis in #7956's
   "Fix, in preference order" is inverted — option (1) is a no-op because the arm is already inside
   the guard, and the measured mechanism is that the *hook's* walk fails while the suite's
   succeeds. Include the measured depth probe (hop 8 → found, hop 9 → `NOT_FOUND`).
3. **Close #7956 as a duplicate of #7886** — or, if the operator prefers to keep it open as the
   better-diagnosed record, close #7886 into it. Either is fine; leaving both open is not.
4. **File the residue** #7879 does not cover, as one issue against the post-#7879 file, labelled
   `code-review` and cross-linked to #7208 §B:
   - Six live arms are still marked at **declaration**, not emission (`T8-adoption`,
     `T9-tree-adoption`, `T9-grandchild`, `T15-idempotency`, `T15-terminal-scope-stable`,
     `AC18-reentry-resweep`), so the anti-vacuity ledger stays satisfiable by intent for those six.
     #7879 moved only `T10-ac7-sweep`.
   - `passes` is never asserted — only printed in the `RESULT:` line — so an arm marked SEEN that
     emits nothing reddens nothing.
   - The end-to-end arm reads `tail -1` of the **real repo** `.claude/.memory-backstop.jsonl` with
     no correlation to the invocation, so a stale line can decide a live gate.
   - `disabled` (a supported configuration, first-class-tested by T6) and `no_terminal_scope` still
     hard-fail, so the false-red class has live members beyond the one #7879 fixes.
> **Correction 2026-09-09 (at /work, verified against #7879's head, not `main`):** two of the
> four residue items above do **not** hold, and the first is broader than stated. Filed as #8008
> in corrected form.
>
> - **Item 1 restated.** It is not six-of-seven. **Every** `live_mark` sits at its arm's opening,
>   before any `pass`/`fail` — including `T10-ac7-sweep` at line 871, which this plan claimed
>   #7879 had moved to emission. It has not; no arm is marked at emission. The ledger records
>   reachability, never emission.
> - **Item 2 holds.** `passes` is initialised at 61, incremented by `pass()` at 84, and read only
>   at 1187/1191 to render `RESULT:`. No floor compares against it.
> - **Item 3 REFUTED.** The e2e arm does not read the real repo ledger CWD-relatively: `E2E_LOG`
>   is scratch-scoped at line 906, and T5c actively asserts the absence of a CWD-relative read.
> - **Item 4 REFUTED.** `disabled` / `no_terminal_scope` no longer hard-fail: the `else` branch
>   skips all six live arms on **any** decline outcome, not only `claude_pid_not_found`.
>
> Recorded rather than silently narrowed: filing items 3 and 4 would have put two false claims
> about someone else's open PR on a public issue. This is the plan's own
> "verify a measurement before it propagates" rule catching the plan.

5. **Do not edit either backstop file in this PR.** Concurrent edits to a file #7879 changes by
   `+281/-46` guarantee a conflict, and Phase 2's whole finding is that the design there is better.

## Acceptance Criteria

### Pre-merge (PR)

**#7957 — the false clause**

- **AC1** The replacement sentence is present and the superseded clause is gone:
  `grep -c 'need not infer from a tail' plugins/soleur/skills/work/SKILL.md` returns **0**, and
  `grep -c 'never from the completion NOTIFICATION either' …` returns **1**.
- **AC2** The `**Why:**` addition is present: `grep -c 'a reaped task does not imply a reaped process tree' …`
  returns **1**.
- **AC3 — full-class sweep (property 2).** *(Amended 2026-09-09: the literal grep below is
  necessary and NOT sufficient — it asserts a STRING where the property is a CLAIM. It
  returned 0 for `2026-09-07-…-never-ran.md` while that file's `## Session Errors` item 1
  still prescribed "wait for the completion notification" as the fix for a VERDICT misread.
  The property-shaped sweep is
  `grep -rniE "(wait for|trust)\s+(the\s+)?(harness'?s?\s+)?(task-)?(completion\s+)?notification" --include=*.md .`
  plus a wrap-insensitive pass; both were run at review.)* `grep -rn 'infer from a tail' --include=*.md .` returns
  matches only in (a) this feature's own `knowledge-base/project/{plans,specs}/**` artifacts and
  (b) lines that quote the claim **in order to refute it**. No file states it as live guidance. In
  particular the Prevention bullet of the 2026-09-07 learning carries a correction note referencing
  #7957. The `knowledge-base/project/learnings/workflow-issues/2026-05-20-long-running-bench-verify-process-before-relaunch.md`
  hit is dispositioned in the PR body — expected **scoped out**, because its claim is about
  *liveness* ("has the task finished?"), for which the notification is authoritative, not about
  *verdict* ("did it succeed?"). If the check finds it makes the verdict claim, it is folded in.

**#7957 §2 — markdownlint regression (repair already landed in #7955)**

- **AC4** `bash scripts/markdown-lint.sh plugins/soleur/skills/work/SKILL.md` exits **0** and
  reports `1 file(s) clean` — *after* the Phase 1 edit, not only before.
- **AC5 — the four deliberate spans are untouched.** One line, and it cannot false-negative:

  ```bash
  git diff -U0 -- plugins/soleur/skills/work/SKILL.md | grep -c 'markdownlint-disable-line MD038'
  # must be 0 — the Phase 1 edit is in a different paragraph
  ```

  This subsumes any directive-adjacency check: a directive cannot drift from its span if neither
  line changed.
- **AC6 — per-site meaning preservation, demonstrated RED-able.** AC4 is vacuous on its own and
  AC5 only proves *this* PR did not touch the sites; AC6 asserts the property itself. For each of
  the four spans, the **rendered** code-span content must still end in a space. Assert the rendered
  string, never the source form — an earlier draft filtered on `not c.startswith(" ")`, which
  encodes *single-backtick repair* and would drive RED on a correct re-repair in another form. That
  is asserting the mechanism, which this plan forbids two rows earlier:

  ```bash
  python3 - <<'PY'
  import re, sys
  p = "plugins/soleur/skills/work/SKILL.md"
  want = {"bash ", "attr = ", "## ", "### "}
  def rendered(c):
      # CommonMark strips ONE space from each end iff the content both begins and
      # ends with a space and is not all spaces. Otherwise it is literal.
      if len(c) >= 2 and c[0] == " " and c[-1] == " " and c.strip():
          return c[1:-1]
      return c
  found = set()
  for line in open(p, encoding="utf-8"):
      for m in re.finditer(r'(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)', line):
          r = rendered(m.group(2))
          if r.endswith(" "):
              found.add(r)
  missing = want - found
  print("PRESERVED:", sorted(found & want)); print("MISSING:", sorted(missing))
  sys.exit(1 if missing else 0)
  PY
  ```

  **Why the rendered form is load-bearing — measured, and it reverses an assumption.** The three
  candidate repair forms do not agree, and the most natural double-backtick spelling is *wrong*:

  | Source | Raw content | Renders as | Trailing space? |
  |---|---|---|---|
  | `` `## ` `` (single backtick — what #7955 used) | `'## '` | `'## '` | **yes** |
  | `` `` ## `` `` (double backtick, symmetric padding) | `' ## '` | `'##'` | **no — the space is lost** |
  | `` ``## `` `` (double backtick, trailing pad only) | `'## '` | `'## '` | yes |
  | `` `` ##  `` `` (double backtick, two trailing spaces) | `' ##  '` | `'## '` | yes |

  So a repair in the obvious double-backtick form would silently change the documented meaning
  while leaving markdownlint clean — precisely the failure this criterion exists to catch. The
  repo's single-backtick-plus-`disable-line` idiom is the correct one, and the checker must
  recognise any form that actually preserves the space rather than pattern-matching the one in use.

  **Measured at plan time, not left as an instruction:**

  | Mutation | Result | Reported |
  |---|---|---|
  | none (file as it stands) | exit **0** | `PRESERVED: ['## ', '### ', 'attr = ', 'bash ']` |
  | `` `bash ` `` → `` `bash` `` | exit **1** | `MISSING: ['bash ']` |
  | `` `attr = ` `` → `` `attr =` `` | exit **1** | `MISSING: ['attr = ']` |
  | `` `## ` `` → `` `##` `` | exit **1** | `MISSING: ['## ']` |
  | `` `### ` `` → `` `###` `` | exit **1** | `MISSING: ['### ']` |

  Each mutation reddens **only** its own site, so the four VALUES are independently pinned.

  > **Corrected 2026-09-09 (review) — it is NOT "per-site", and the gap is recorded rather
  > than papered over.** AC6 is a file-global SET-MEMBERSHIP test: `found` accumulates
  > rendered spans from anywhere in the file, so `want - found` cannot know which LINE
  > supplied a member. "Each mutation reddens only its own site" shows the four values are
  > independent; it does not show any site is pinned. Three demonstrated ways to satisfy
  > AC6 while violating the property, all measured at review:
  >
  > 1. **Relocation.** Delete the real `` `bash ` `` bullet and add a throwaway mention of
  >    the same span elsewhere in the file → AC6 rc=0, site gone.
  > 2. **Fences.** The regex is fence-unaware, so an illustrative ```` ```markdown ```` block
  >    containing the span satisfies it — and this file is a document *about* markdown idioms.
  > 3. **Snapshot `want`.** The four literals are hardcoded, so a FIFTH deliberate
  >    trailing-space span is unguarded and nothing goes red.
  >
  > The property-shaped form is: every line carrying an MD038 `disable-line` directive must
  > hold at least one code span whose RENDERED content ends in a space, with a non-empty
  > floor on such lines and a fence toggle. That is not committed here — AC6 is a
  > **plan-time measurement only**, and `scripts/markdown-lint.sh` is measurably vacuous for
  > this property (see the AC4 demonstration above), so the guard gap stands on `main`.

  **And AC4 alone is measurably vacuous.** With `` `## ` `` mutated to `` `##` `` — a change that
  makes the documentation say something different, since a heading prefix without its space is not
  one — `bash scripts/markdown-lint.sh …` reported `1 file(s) clean.` at **exit 0** while this
  check exited **1** naming `## `. MD038 fires on a space *present* in a span, so *removing* the
  space silences the rule and changes the meaning in one stroke. Criterion 1 alone would certify
  the exact repair #7957 forbids.

- **AC7 — repair-class classification, recorded as documentation, not as a gate.** The PR body
  carries the per-site table in `## Appendix — the 12 violations and how #7955 repaired them`
  below. It is reference material for a reader of #7957; it gates nothing and is deliberately not
  phrased as a pass/fail criterion.

**#7956 — reconciliation**

- **AC8** #7956 carries a comment naming **#7886** as its duplicate and **PR #7879** as the fix,
  correcting the inverted diagnosis and including the measured depth probe.
- **AC9** Exactly one of #7956 / #7886 remains open.
- **AC10** *(amended 2026-09-09 — the original read "lists the four uncovered items", which the
  Phase 2.4 Correction block above makes unsatisfiable.)* The residue issue exists, lists the
  **two** items that survived measurement against #7879's head, records the two refuted items
  so nobody re-files them, and
  cross-links #7208 §B.
- **AC11** `git diff --name-only origin/main...HEAD` contains **no** path under `.claude/hooks/` —
  this PR does not touch the surface #7879 is rewriting.

**Both**

- **AC12** `bun test plugins/soleur/test/` is green (the shard `plugins/soleur/**/*.md` triggers),
  and `bash scripts/markdown-lint.sh --repo-sweep` is green. Verdicts read from a redirected log's
  own `RC=` line — never a pipe, never a completion notification.
- **AC13** PR body contains `Closes #7957` (body, not title — `wg-use-closes-n-in-pr-body-not-title-to`).
  It must **not** contain `Closes #7956`: that issue is resolved by dedupe and by #7879, not by this
  diff.
- **AC14** PR body records the premise corrections — #7956 superseded by #7879 and duplicating
  #7886; #7957 §2 resolved by #7955 — so a reader of either issue sees why the shipped work differs
  from the filed proposal.

### Post-merge

None required of a human. The Phase 2 issue operations run in-session with `gh`.

## Test Scenarios

1. **Clause removed, replacement present** — AC1/AC2 greps over the edited paragraph.
2. **Class sweep** — AC3: the claim survives nowhere as live guidance.
3. **Linter still clean after the edit** — AC4.
4. **Deliberate spans untouched by this diff** — AC5, one line.
5. **Trailing-space property holds, and the checker reddens per site** — AC6, five runs (one clean,
   four single-site mutations), already measured.
6. **The linter cannot see the meaning change** — AC6's vacuity demonstration: linter green, checker
   red, on the same bytes.
7. **No backstop file touched** — AC11.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| #7879 merges while this PR is open and conflicts. | AC11: this PR touches no file under `.claude/hooks/`. The two are disjoint by construction. |
| #7879 is closed unmerged, leaving #7956 genuinely unfixed. | Phase 2.1 re-probes before acting. If #7879 dies, the residue issue becomes the tracker for the whole defect, and this plan's Research Reconciliation carries the corrected diagnosis and the measured depth probe so no analysis is lost. |
| Closing #7956 as a duplicate loses its better diagnosis. | Phase 2.2 writes the diagnosis into a comment *before* Phase 2.3 closes anything, and Phase 2.3 explicitly permits closing #7886 into #7956 instead. |
| Correcting the 2026-09-07 learning reads as rewriting history. | Only the **prescriptive** Prevention bullet is corrected, with a note referencing #7957; the narrative is untouched. |
| A future `--fix` sweep strips the four deliberate spaces. | AC6 catches it at this PR; `scripts/markdown-lint.sh`'s remediation block already warns against `--fix` for MD038, and each site carries a `disable-line` marker. Standing enforcement was considered and cut (Alternatives). |
| The `work/SKILL.md` edit trips a gate other than markdownlint. | `plugin-component-test` fires on the glob; the body edit leaves the frontmatter `description:` untouched, so the 2400-word cumulative budget is unmoved. AC12 runs the shard regardless. |

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Implement #7956 as filed (align the two walks, depth-independent). | Trips #7879's `T5c` standing guard, which fails if an independent ancestry walk reappears; reverts an adopted design; and re-derives an approach an archived plan had already **demoted**. |
| Implement #7956's option (1) verbatim (move the arm inside the guard). | It is already inside — measured against the file. |
| Discriminate `claude_pid_not_found` → skip. | Wrong, not merely redundant: that reason is the only one a *broken* `discover_claude_pid` emits, so it would make a genuine discovery regression green. |
| Land the residue fixes in this PR. | The file is being rewritten `+281/-46` by #7879; concurrent edits guarantee a conflict and would be rebased away. |
| Replace AC6's checker with only the AC5 diff grep. | Both simplification reviewers proposed it and it is a good check — adopted as AC5. AC6 is **kept alongside** because a per-site RED-able assertion was explicitly requested; the substitution is recorded as UC-2 in `decision-challenges.md` rather than applied unilaterally. |
| A standing drift-guard test for the four spans. | Cut per minimality — self-marking sites, one-time concern. |
| A new `AGENTS.md` rule for the notification class. | 1 byte of headroom against the ratchet, measured. |

## Files to Edit

- `plugins/soleur/skills/work/SKILL.md` — the two #7957 §1 hunks.
- `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`
  — correction note on the Prevention bullet carrying the same false clause.
- `knowledge-base/project/learnings/2026-09-08-the-rule-propagated-the-distrust-stopped-at-commands-i-wrote.md`
  — its Prevention section says the correction is *"tracked as #7957 … ready to apply"* and names the
  two blockers. Both statements go stale the moment this ships: the clause is applied, and #7955
  already cleared the markdownlint blocker. Update it to record that the correction landed, so the
  file stops pointing forward at work that is done.

## Files to Create

None. (`knowledge-base/project/specs/<branch>/decision-challenges.md` already exists — written by
`plan-review`.)

## Appendix — the 12 violations and how #7955 repaired them

Reference material for a reader of #7957, recording the per-site classification the issue asked for.
Verified against `ae44051a8`; gates nothing.

| Site(s) | Rule | Class | How #7955 repaired it |
|---|---|---|---|
| `` `bash ` ``, `` `attr = ` ``, `` `## ` ``, `` `### ` `` | MD038 | **(a) the trailing space IS the content** | Single-backtick span retained, silenced at the site with `<!-- markdownlint-disable-line MD038 -->` — the idiom `scripts/markdown-lint.sh`'s remediation block documents. Stripping the space would have changed the meaning (`` `## ` `` is a heading prefix; without the space it is not). |
| the runs on the two prose lines (six MD038 hits) | MD038 | **(b) unbalanced backticks in prose** | Root cause was a **backslash-escaped backtick used as a code-span delimiter** — CommonMark has no such escape, so each span closed at its first escaped tick and every later backtick on the line paired one position off. Repaired with an outer double-backtick run and real inner backticks. The issue named two sites; a grep for the construct found three, and the third was fixed with them. |
| `[i][0]` | MD052 | **(c) reference-link false positive** | Dissolved by (b): once the span boundaries were correct, `array[i][0]` fell back inside a code span and the missing-reference-definition warning disappeared. It was never an independent defect. |

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed
**Assessment:** A documentation correction in a plugin skill plus a matching correction in the
learning it cites, and issue reconciliation. No product surface, no user data, no infrastructure, no
vendor, no runtime code. The engineering judgment that mattered was not in the diff but in the
scoping: a six-reviewer panel established that the larger half of the original plan was superseded
by in-flight work and, in its central relaxation, would have converted a real regression into a
silent pass.

No Product/UX Gate: the mechanical UI-surface scan over `## Files to Edit` and `## Files to Create`
matches no UI path and no UI-surface term. Product is NONE by both the mechanical override and the
semantic sweep.

## Gates Assessed and Skipped

No product, infra, data, vendor, or runtime surface — two markdown files only. Phases 1.4
(network-outage), 2.7 (GDPR), 2.8 (IaC), 2.11 (encryption posture) and 2.12 (Guard Contract — the
deliverable now contains no guard) therefore skip. Two are recorded with reasoning because each
makes a contestable claim:

- **Phase 2.9 / deepen-plan 4.7 Observability** — skipped, and the ambiguity is recorded rather than
  glossed. Plan Phase 2.9's trigger set is `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`,
  `plugins/*/scripts/`, or a new infrastructure surface; `## Files to Edit` matches none.
  deepen-plan 4.7's Step-1 *skip* list is narrower — it exempts `\.md$` only **outside**
  `plugins/*/skills/`, so `work/SKILL.md` is not literally covered by that exemption. The two are
  reconciled in favour of 2.9, which is the contract 4.7 exists to enforce ("this gate is what makes
  plan Phase 2.9 load-bearing"): 2.9 lists `plugins/*/scripts/` and deliberately not
  `plugins/*/skills/`, distinguishing executable plugin code from plugin prose. A SKILL.md body is
  documentation an agent reads, not an execution surface, so it emits no liveness signal and has no
  failure mode to route — a 5-field observability schema over a prose edit would be ceremony, not
  coverage. `hr-observability-layer-citation`'s layer-7 wording is not engaged. No soak-gated or
  time-gated close criterion exists, so 2.9.1 does not fire.
- **Phase 2.10 ADR / C4** — skipped, and the conclusion is not drawn from a keyword grep. The change
  introduces no external human actor, no external system or vendor, no container or data store, and
  no actor↔surface access relationship; it adds and removes no cron monitor, heartbeat slug, or
  workflow, so no derived cardinality in `model.c4` edge prose moves. Correcting a sentence in a
  skill body falsifies nothing an ADR or a C4 view records.

## Sharp Edges

- **Do not verify this PR from a background task's completion notification.** The PR's own subject
  is that the notification's exit code is the last command in the backgrounded string. Redirect to a
  file, write `RC=$?` yourself, and read that. Committing the error while correcting it is the one
  failure mode this work cannot afford.
- **AC4 without AC6 is a vacuous gate, and this was measured rather than argued.** "The linter
  reports 0 violations" is satisfied by *stripping* the trailing spaces — the meaning-changing
  repair #7957 explicitly forbids. Linter green and checker red on the same bytes is recorded in
  AC6.
- **Do not touch `.claude/hooks/` in this PR.** PR #7879 is rewriting `memory-backstop.test.sh` by
  `+281/-46` and adds a standing `T5c` guard that **fails** if an independent ancestry walk
  reappears. A well-meaning "while I'm here" edit either conflicts or reverts an adopted design.
  AC11 is the mechanical check.
- **Phase 0.6 validates what an issue cites, not what is already in flight against the same files.**
  That gap is why a full design for #7956 reached plan-review before being cut. Two `gh` commands
  close it, and they are Phase 2 step 1 — worth running at the *start* of any plan whose files are
  named by an issue somebody else may also have read.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled and
  carries its `threshold: none, reason: …` scope-out bullet.
