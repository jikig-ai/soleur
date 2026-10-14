# Decision Challenges — feat-one-shot-7956-7957-backstop-e2e-guard-and-work-skill-lint

Recorded headless by `plan-review` (ADR-084). Each entry is a decision the panel argued
should differ from the operator's stated direction. **None has been auto-applied.**

---

## UC-1 — #7956's assigned scope is already implemented, better, in open PR #7879

**Class:** `user-challenge` (dropping operator-requested scope is never Mechanical).
**Raised by:** `soleur:engineering:cto` (devex lens). **Verified independently** before recording.

**The operator's stated direction:** implement and ship both #7956 and #7957.

**What the panel found, and what verification confirmed:**

- **PR #7879** (`feat-one-shot-7849-7853-7854-fixture-env-ledger-ancestry`) is **OPEN,
  non-draft, MERGEABLE**, last updated 2026-09-09, and touches
  `.claude/hooks/memory-backstop.test.sh` and `.claude/hooks/memory-backstop-mutation-battery.sh`.
  It closes #7849, #7853 and **#7854 — "the ancestry walk"**.
- It **deletes the second ancestry walk outright**. The end-to-end gate now reads the hook's
  own logged outcome instead of re-deriving the precondition.
- Its skip message states this plan's diagnosis verbatim: *"the hook runs one process deeper
  than this suite, so at lefthook depth claude sits outside its `${MAX_WALK_HOPS}`-hop limit"*.
- It discriminates a **set** of decline reasons (`claude_pid_not_found`, `no_terminal_scope`,
  `concurrent_apply`, …), which is strictly broader than this plan's single-reason arm, and
  notes that `claude_pid_not_found` alone would still fail for the documented case.
- It adds **T5c**, a standing drift guard that greps this suite for `for +_hop +in` and PPid
  reads and **FAILS** if an independent ancestry walk reappears — plus a companion arm that
  fails if the rationale comment explaining why there is no second walk is deleted.
- **#7956 is a duplicate of #7886** (OPEN — *"memory-backstop.test.sh fails under lefthook and
  passes standalone"*), which is the issue #7879's #7854 half addresses.

**Consequence for the plan as written:** its Phase 2.2 — *"replace the hard-coded `for _hop`
with a walk to PID 1, written independently of the hook"* — **reintroduces exactly what T5c
exists to reject**, and its AC9 codifies the opposite of #7879's adopted design. Landing both
means one deletes the other's guard. An archived plan
(`knowledge-base/project/plans/archive/20260907-211732-2026-09-07-fix-betterstack-roundtrip-credfwd-lefthook-plan.md`)
had already adjudicated and **demoted** the align-the-two-walks approach; this plan re-derived
the demoted fallback without citing the decision that demoted it.

**The challenge:** do not implement the #7956 half as filed. Three options:

1. **Close #7956 as a duplicate of #7886**, note that #7879 covers it, and ship only #7957.
2. **Ship #7957 now; re-cut #7956 on top of #7879** once it merges, reduced to the residue
   #7879 does not cover (below).
3. Implement as filed — **not recommended**: it trips T5c and reverts an adopted design.

**The genuine residue #7879 leaves uncovered** (verified against its head):

- Six live arms are still marked at **declaration**, not emission (`T8-adoption`,
  `T9-tree-adoption`, `T9-grandchild`, `T15-idempotency`, `T15-terminal-scope-stable`,
  `AC18-reentry-resweep`), so the anti-vacuity ledger remains satisfiable by intent for those
  six. #7879 moved only `T10-ac7-sweep`.

  > **Corrected 2026-09-09 (measured against #7879's head `fa6539a4`):** this sentence is
  > wrong and is left standing as the claim that was checked. It is NOT a six-of-seven
  > split: `live_mark T10-ac7-sweep` sits at line 871, before its own snapshot/invoke/read
  > sequence, exactly like the other six. #7879 split it OUT of the old three-line block and
  > re-sited it, still at the arm's opening. No arm is marked at emission. Filed in corrected
  > form as #8008.
- `passes` is never asserted — only printed in the `RESULT:` line — so an arm that is marked
  SEEN but emits nothing reddens nothing.

**Recommendation:** option 2. #7957 is fully independent of all of this and is ready.

---

**RESOLUTION (operator, 2026-09-09):** Option 2 — **descope #7956 to reconcile-only**.
Asked and answered via `AskUserQuestion` after the pipeline independently re-verified every
claim above: the failing arm at `memory-backstop.test.sh` line 901 sits in the `else` branch of
the `E2E` gate that closes at line 926 (`fi   # end E2E gate`), so the issue's preferred fix is a
measured no-op; #7886 is OPEN with the same symptom; #7879 is OPEN, non-draft, deletes the
`for _hop in 1 2 3 4 5 6 7 8` walk and adds `T5c` to fail any reappearance of one.

Scope for this PR: `closes: [7957]` only. The #7956 half is discharged as reconciliation —
comment the measured correction on #7956, dedupe it against #7886, point both at #7879, and
file the residue #7879 leaves uncovered. No code under `.claude/hooks/` is touched by this PR,
so nothing here can conflict with #7879 or trip `T5c`.

## UC-2 — replace the per-site trailing-space checker with a one-line diff assertion

**Class:** `user-challenge` (it narrows an explicitly operator-requested acceptance criterion).
**Raised by:** `dhh-rails-reviewer` and `code-simplicity-reviewer`, independently and convergently.

**The operator's stated direction:** the markdownlint acceptance criteria must assert BOTH that
the linter reports 0 violations AND that meaning is preserved **per site**, in a form that can
go RED on a stripped trailing space.

**The panel's argument:** the four deliberate-trailing-space spans live on three
`markdownlint-disable-line MD038` lines that **this PR does not touch** — the #7957 edit lands
in a different paragraph. So the property is bought outright by one line:

```bash
git diff -U0 -- plugins/soleur/skills/work/SKILL.md | grep -c 'markdownlint-disable-line MD038'   # must be 0
```

This cannot false-negative, needs no CommonMark emulation, and subsumes the directive-adjacency
criterion. Both reviewers noted the proposed 16-line Python span-parser carries a hardcoded
four-element member list — the snapshot shape this repo's own learnings reject, since a fifth
deliberate span added later stays silently green.

**Why it was NOT auto-applied:** the per-site, RED-able form was explicitly requested. The
plan therefore **keeps** the per-site checker (measured GREEN on the file and RED on all four
single-site mutations) and **adds** the diff assertion alongside it as AC5, rather than
substituting one for the other. If the operator prefers the reviewers' cut, the Python block comes
out and AC5 stands alone.

**A measured correction to the steer's suggested mechanism.** The steer proposed repairing
trailing-space sites in "double-backtick form (`` `` `## ` `` ``)". Measured against CommonMark's
actual rule — one space is stripped from *each* end only when the content both begins and ends with
a space:

| Source | Renders as | Trailing space? |
|---|---|---|
| `` `## ` `` (single backtick — what #7955 used) | `'## '` | **yes** |
| `` `` ## `` `` (double backtick, symmetric padding) | `'##'` | **no — silently lost** |
| `` `` ##  `` `` (double backtick, two trailing spaces) | `'## '` | yes |

So the natural double-backtick spelling would have produced exactly the meaning change the steer
was written to prevent. The repo's single-backtick-plus-`disable-line` idiom is correct, and AC6
now asserts the **rendered** content so it accepts any form that genuinely preserves the space —
a `code-simplicity`/Kieran finding that the first draft asserted the mechanism instead.

---

## UC-3 — `#7956` half: the panel's structural findings, held pending UC-1

Recorded so they are not lost if option 3 is chosen. Each was verified.

- **A `passes` floor is missing, so the "move a mark back to declaration" mutation cannot go
  RED.** Confirmed: `grep -n '\bpasses\b'` shows `passes` is incremented in `pass()` and printed
  in the `RESULT:` line, and asserted nowhere.
- **The ledger fix must cover 12 labels, not 7.** `LIVE_LABELS` holds 12; scoping the repair to
  the seven end-to-end arms reproduces the `guard_narrower_than_the_property_it_names` shape the
  plan itself cites.
- **A `LIVE_LABELS` count floor buys nothing** and reintroduces the snapshot count the plan's own
  Assembly section forbids one paragraph earlier.
- **The suite already `source`s the hook**, so `discover_claude_pid` and `MAX_WALK_HOPS` are
  already in lexical scope. The independence property is therefore narrower than the plan claimed:
  the gate must not be *decided by* `discover_claude_pid` — not that the function must be
  unreachable.
- **The suite's walk has no `CLAUDE_CODE_EXECPATH` arm** while the hook accepts three identity
  signals, so "the two agree exactly" would remain false even after aligning depth.
- **A prescribed comment would have shipped a falsehood:** "termination is guaranteed by the
  existing `pid <= 1` return" does not hold for a synthetic `procroot` fixture with a cycle —
  which is precisely what the proposed depth rows construct. A PR whose subject is deleting a
  false comment must not ship one.

---

## UC-4 — the discriminant in the original Phase 3 was wrong, and would have made a real
## regression green

**Class:** `mechanical` (a correctness defect in the plan's own design — recorded here for the
record, and resolved by descoping to #7879's design rather than by patching it).
**Raised by:** `spec-flow-analyzer` (P0-1), corroborated by the reason-set breadth in #7879.

`reason="claude_pid_not_found"` is emitted at exactly **one** site in `memory-backstop.sh`
(`if ! found=$(discover_claude_pid "$$" /proc); then`), and it is the only reason a **broken**
`discover_claude_pid` can produce — identity match deleted, walk terminating early, wrong
`procroot`. The original Phase 3 converted that single enum into `skip` + `exit 0`, so a genuine
discovery regression would have reported GREEN. The plan's Risks table claimed AC7 bounded this;
AC7 covers every reason **except** the one being relaxed.

The correct discriminant is the **conjunction**, not the reason: with two independent walks,
`E2E == yes && reason == claude_pid_not_found` *is* a disagreement between two implementations of
one predicate — the #7956 defect class itself — and must be loud. The genuine environment case is
already covered one gate earlier, at the `E2E` gate.

**#7879 dissolves this entirely** by deleting the second walk, so the disagreement state cannot
exist, and by classifying a *set* of decline reasons rather than one. This is the clearest
evidence for UC-1's recommendation.

Related findings against the original design, all verified, all dissolved by #7879's approach:

- The `T10/AC7` sweep emits **outside** the `outcome == applied` gate, so the original Phase 3
  would have marked `T10-ac7-sweep` SKIPPED while its three assertions still ran and passed
  vacuously — and AC6 (`skipped_live == 7`, `fails == 0`) was satisfied *by that wrong state*.
- No mutation row covered the suite's own walk — the one site the plan proposed to rewrite. A
  regression there yields `PASSED … [live: yes, e2e SKIPPED]`, exit 0, forever.
- `AC1`'s literal grep (`for _hop in 1 2 3 4 5 6 7 8`) is satisfied by `for _hop in $(seq 1 8)` —
  the `cq-assert-anchor-not-bare-token` shape.
- The end-to-end arm reads `tail -1` of the **real repo** `.claude/.memory-backstop.jsonl`, with
  no correlation to the invocation, so a stale line from a previous `nohup` run would have made a
  healthy run skip seven arms and exit 0.
- `disabled` (a supported configuration, first-class-tested by T6) and `no_terminal_scope` remain
  hard-fails, so the false-red class the plan exists to remove still has live members.
