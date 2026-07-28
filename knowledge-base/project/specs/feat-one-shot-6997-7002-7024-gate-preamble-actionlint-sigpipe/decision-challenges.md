# Decision Challenges — feat-one-shot-6997-7002-7024-gate-preamble-actionlint-sigpipe

Recorded per ADR-084 / `decision-principles.md`. This session ran **headless** (plan invoked inside a
one-shot Task subagent), so challenges are persisted here rather than raised interactively. `/ship`
renders these into the PR body and files them as `action-required` issues.

**The operator's stated direction is the default in every entry below.** Nothing here has been applied
against that direction; each entry states what would change and what evidence would settle it.

---

## DC-1 — Should `cutover-inngest.yml`'s run-block split land in this PR? (User-Challenge — **RESOLVED, no operator decision needed**)

> **Resolution.** The challenge was raised, and then **dissolved by a third option** rather than
> adjudicated. The body contains **zero `${{ }}` GitHub expressions**, so it can be moved **wholesale into
> `.github/scripts/cutover-inngest.sh`** as a verbatim one-file change. Extraction achieves the same size
> reduction as the split while paying none of its costs — the body stays in **one step and one process**,
> so cross-step state loss, `set -o` inheritance, `if:`-arm completeness and helper drift all cease to
> exist as risks — and it is *strictly more fail-closed* than the status quo, because the script carries an
> explicit `set -euo pipefail` where the inline step inherited `bash -e {0}` (neither `-u` nor `pipefail`).
> It also removes the need for a permanent lint exclusion on the very file that exposed the bug.
> **`Closes #7002` holds, matching the operator's stated direction.** The history below is retained because
> the evidence that motivated the challenge is what selected extraction over the split.

**Operator's stated direction (the default):** the PR closes all three issues —
`Closes #6997`, `Closes #7002`, `Closes #7024`. #7002's stated fix is *"identify the offending `run:`
block and split or shrink it, AND pin a documented actionlint invocation with a timeout."*

**The challenge.** The session model and the CTO consult independently converged on: ship #7002's
tooling half now, and move the **split** to its own PR.

**Evidence gathered (all verified in-worktree, 2026-07-28):**

1. `gh run list --workflow=cutover-inngest.yml` shows the workflow was dispatched **twice on
   2026-07-24**, titled *"Cutover Inngest (durable-backend Phase 2)"*, and **both runs concluded
   `failure`**. The Inngest Phase-2 cutover is live and currently failing.
2. Four follow-up issues are **open** against it: **#6940** (post-#6178 follow-ups), **#6921**
   (op=execute re-capture), **#6753** (deferred refactors + cutover workflow test census), **#6488**
   (post-cutover table drop).
3. The workflow is **`workflow_dispatch`-only and operator-triggered**. No CI signal exists that could
   detect a defect introduced by restructuring it — a bad split surfaces at the **next cutover attempt**.
4. The step is one `set -euo pipefail` preamble, **three helper functions** communicating through an
   `FSM_FAIL_REASON` global, then a `case` with **13 mutually exclusive arms**. `confirm_flip_state` is
   called from both the `arm` and `rollback` arms.
5. **Every failure mode of the split fails OPEN, in the same direction as the three bugs this PR fixes:**
   an `if: inputs.op == …` typo makes an op run **nothing** while the job reports **success**; GitHub's
   default shell is `bash -e {0}` so a dropped `set -o pipefail` silently converts a fail-closed pipeline
   to fail-open; a duplicated `confirm_flip_state` drifts between `arm` and `rollback` undetectably until
   rollback day.
6. `actionlint` runs in **zero** CI workflows (`grep -rn actionlint .github/workflows/` → no matches),
   asserted in prose at two existing sites. It is a local-only pre-ship tool.

**What the challenge would change.** #7002's *linter usability* is fully restored by the tooling half
alone — the timeout-wrapped invocation, the `-shellcheck=` escape hatch, and the run-block-size guard with
`cutover-inngest.yml` recorded as an exclusion citing #7002. That combination lets the other 68 workflows
be linted today and permanently prevents a **new** file from crossing the 65536-byte cliff. Only the
1597-line re-partition of a mid-flight production cutover would be deferred.

**How it was actually resolved.** Neither "split now" nor "defer the split" — a third option that makes the
trade-off unnecessary. Measured: the run body contains **zero `${{ … }}` expressions**, so it reads only
process env supplied by the step's `env:` map, which a child `bash` inherits. Moving it to
`.github/scripts/cutover-inngest.sh` and reducing the step to
`run: bash "${GITHUB_WORKSPACE}/.github/scripts/cutover-inngest.sh"` is therefore a **verbatim, single-file
move**, provable by one whitespace-normalized diff to empty. Repo precedent exists
(`apply-sentry-infra.yml:299/308/321/605`; `apply-web-platform-infra.yml:712`), and `actions/checkout`
runs unconditionally in the cutover job.

Against every axis that motivated the challenge: cross-step state loss — **does not arise** (one process);
`set -o` inheritance — **improved** (explicit `set -euo pipefail` replaces inherited `bash -e {0}`);
`if:`-arm completeness — **does not arise** (no per-arm conditions added); helper drift — **does not
arise** (one file); actionlint — the step's `run:` is one line, so **no exclusion is needed** and the body
is *still* linted, now by plain `shellcheck <file>`, which handles it without the stdin pipe that caused
the deadlock.

**No operator decision is required.** The plan's Phase 6 prescribes extraction; the multi-step split is
recorded as an explicitly-rejected alternative in the new ADR, with the reason (its failure modes all fail
OPEN and are undetectable by CI on a `workflow_dispatch`-only workflow).

**Residual note for the operator, informational only:** the Inngest Phase-2 cutover appears still pending
(two failed dispatches on 2026-07-24; #6940 / #6921 / #6753 / #6488 open). Nothing in this PR blocks or
alters it, and the extraction is behaviour-preserving by construction — but the next cutover attempt is the
first execution of the extracted script, so it is worth knowing that is when the move gets its live proof.

---

## DC-2 — #7024 overlaps an already-open issue (#7005), and a guard already exists

**Operator's stated direction (the default):** #7024 says *"Fix by replacing the piped forms … Sweep the
whole file and the sibling suites … never `grep -q` on a pipe, per AGENTS.rest.md."*

**Two premises in that direction are factually wrong, verified:**

1. **No AGENTS rule exists.** `grep -rn 'grep -q' AGENTS*.md` returns **zero hits**. The authority is the
   learning file `knowledge-base/project/learnings/test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`.
2. **A durable guard already exists** — `.claude/hooks/grep-q-pipe-guard.test.sh`, shipped by #6992 /
   PR #6998, with the wide pattern and its own non-vacuity probe. Its header states the scope it left
   open: *"scripts/ and plugins/ are NOT in scope yet — tracked in #7005."*

**And the scope is far larger than stated.** #7024's suggested sweep pattern yields 38 hits; the **wide**
flag-cluster pattern yields **818** repo-wide. **#7005 is OPEN** and already measures the remainder
precisely (`scripts/` 52 sites / 27 files, `plugins/` 35 / 17, `*.test.sh` 157). **#7024 is a slice of
#7005, not a peer of it.**

**What the plan does (no operator decision required, but recorded for visibility):** fixes #7024's two
named files, **extends** the existing guard rather than creating a second one, adds a highwater ratchet
for the corpus that cannot reach zero in this PR, and cross-links #7005 — commenting there with the sites
removed and re-scoping the remainder. Two open issues sweeping the same corpus is a real collision risk;
whichever ships first must re-scope the other.

**No AGENTS rule is added.** Measured headroom is **100 bytes** (`B_ALWAYS=22900` against a 23000
ceiling, already at WARN). A rule would have to be paid for by retiring another via
`scripts/retired-rule-ids.txt` — a deliberate act, not a rider on this PR. The repo already made the
lint-not-rule call once, in #6992.

---

## DC-3 — ADR-149 and the issue prose both assert something the code disproves

**Stated in both the task brief and `ADR-149` `## Consequences`:** the three gates
`stock-preflight` / `web-host-birth` / `web-host-replace` *"carry equivalent INLINE checks, so their
retrofit is pure deletion and changes no safety property"*, and are therefore a lower-priority
readability tier.

**Reading them disproves it:**

- All three lack the helper's `length > 0` empty-actions conjunct — the shape the preamble's own header
  records as **measured**, where an `hcloud_server.web["web-1"]` destroy carrying `"actions": []` and
  `"after": null` scored `destroys=0, out_of_scope=0` and **PASSED**.
- `web-host-birth` and `stock-preflight` use the negative-search form (`if jq -e '[…select(bad)] | length > 0'`),
  which reads a jq **error** as "condition false" — the exact failure mode the helper's `all(…)` form was
  written to close.
- `stock-preflight`'s readability check is `jq -e '.resource_changes'`, a truthiness test rather than a
  type test.
- **`web-host-replace-gate.sh` carries a check the helper does NOT** — `all(.change.actions[]; type == "string")`,
  closing a nested-array case. Retrofitting it onto the helper as it stands would have been a **regression**.

**Priority is also inverted.** `stock-preflight-gate.sh` is sourced **8×** by
`apply-web-platform-infra.yml` — more call sites than any Tier-1 gate — while `web2-retire-gate.sh`, named
in #6997's priority set, is sourced by **no workflow at all** and is documented in-repo as *"test-only"*.

**What the plan does:** strengthens the helper first (blocking precondition), folds `web-host-birth-gate.sh`
into scope, defers the other two with a tracked issue whose body records the 8× call-site count so the
"tier 2" label does not understate the blast radius, and **corrects the ADR-149 sentence in this PR**
rather than leaving a disproved claim in the architecture record.

**No operator decision required** — this is a factual correction, not a direction change. Recorded because
the false claim was load-bearing in the original scoping and is worth knowing was wrong.

---

## DC-4 — #7024's sweep was narrowed from "the whole file and the sibling suites" to two files (User-Challenge)

**Operator's stated direction (the default):** *"Sweep the whole file and the sibling suites for the same
shape: `grep -rn 'echo "\$[A-Z_]*" | grep -q' plugins/soleur/skills/*/test/`."*

**The challenge.** The plan fixes only `plugins/soleur/skills/compound/test/phase-16.test.sh` and
`tests/scripts/test-sentry-full-root-apply.sh`, and defers the rest.

**Evidence:**

1. The suggested pattern returns 38 hits. The **wide** flag-cluster pattern the repo actually mandates
   (`-[A-Za-z]*q`, because the narrow `-q` misses `-Eq`/`-iq`/`-Fq` — the exact miss that let two live sites
   survive PR #6998's first conversion pass) returns **~800 repo-wide**, of which **583 are in `*.test.sh`**.
2. **#7005 is OPEN and already owns that corpus** — *"review: sweep the remaining pipefail + grep -q
   fail-open sites in scripts/ and plugins/"*. It was filed deliberately when PR #6998 took `.claude/hooks/`
   to zero, and `.claude/hooks/grep-q-pipe-guard.test.sh`'s own header records the hand-off:
   *"scripts/ and plugins/ are NOT in scope yet — tracked in #7005."*
3. Sweeping 583 sites here would silently absorb another open issue's scope into a PR already closing three.

**What the plan does instead:** fixes the two named files, extends the existing guard's pathspec to hold them
at zero, and **comments on #7005** with the sites removed, the remainder re-scoped, and — importantly —
**corrected corpus numbers**, because #7005's own figures (157 `*.test.sh`) predate the wide pattern and are
low by 3.7×.

**Open question for the operator:** none blocking. If the intent was to close #7005 as well, that is a
separate PR of a different size, and this plan's Non-Goal 3 is the place it is recorded.

---

## DC-5 — #7024's issue text asserts two things the measurements contradict

Recorded as a factual correction, not a direction change. No operator decision required.

1. **The title has the fail-open/fail-closed direction backwards.** #7024 is titled *"…makes assertions fail
   OPEN (phase-16) and CLOSED (sentry-full-root-apply)"*. The mechanism is the inverse: a **negated**
   assertion (`if ! … | grep -q`) turns SIGPIPE's 141 into a spurious *failure* — that is phase-16's flake,
   i.e. fail-**closed**; a **positive** predicate (`if _has_target …`) reads 141 as "not found" — that is
   sentry-full-root-apply's shape, i.e. fail-**open**. The plan's mechanism analysis is the correct one.

2. **The sentry case is not a live fail-open today.** Measured: `apply-sentry-infra.yml` is 39,221 bytes and
   16,892 bytes after comment-stripping, against a **65,536-byte** pipe buffer. Ten runs with `-target=`
   injected at the *top* of the copy returned `0 0 0 0 0 0 0 0 0 0` — never 141. The producer's entire output
   fits the buffer with 48 KB to spare, so `grep -v` finishes writing before `grep -q` can close the pipe.
   **SIGPIPE is structurally unreachable there at current file sizes.**

   The fix is still worth making — the shape is one file-growth away from live, it is free to convert, and
   `apply-sentry-infra.yml` is the #6074 guard on `terraform destroy` reachability — but the plan must not
   claim a measured live defect, and no acceptance criterion may demand an `rc=141` observation that the real
   inputs cannot produce. AC18 therefore requires 141 from a **synthetic** >65,536-byte producer and requires
   the real-site non-reproduction to be recorded.

**Why this is recorded rather than silently fixed:** an earlier revision of this plan did assert the sentry
case was a live fail-open and wrote an AC demanding `rc=141` from it. That AC was unachievable. Asserting an
unmeasured property is precisely the defect class all three issues are about, so the correction is logged
rather than quietly edited.
