---
date: 2026-07-16
category: test-failures
module: apps/web-platform/infra
issue: 6497
pr: 6528
tags: [mutation-testing, vacuous-assertions, anchoring, false-comments, credential-leak, observability]
---

# A mutation battery only covers what you mutate — and 164/165 green said otherwise

## Problem

PR #6528 instruments `ci-deploy.sh`'s docker-login gate so it can name its own failure
(`class=unclassified` was measured to hold ≥4 distinct modes). The security property the whole
change rests on is that the emitters are **Form B**: every `printf` takes a hardcoded literal, so
they are *structurally incapable* of echoing the registry stderr — which can contain a username or
a token, and which ships to journald → Vector → Better Stack **unscrubbed**.

I wrote 12 assertions and an **AC9 mutation battery** — 7 mutations, each *relocating* a sibling
attribute rather than deleting the anchor (the stronger form). Every one went RED for its predicted
reason. Suite 153 → 164, all green. I reported that as high confidence.

`test-design-reviewer` then proved a hole the battery could not see:

```
_login_kw call sites in the entire test file : 0
kw=<value> assertions in the entire test file: 0
```

**`_login_kw` — an entire emitter that receives the raw credential-adjacent stderr — was never
called by any test.** Mutating its H-C disk-full arm into a Form-A disclosure:

```bash
# real
case "${1:-}" in *'no space left on device'*)   printf 'nospace,' ;; esac
# mutated — ships raw stderr (username + token) to a third-party log store
case "${1:-}" in *'no space left on device'*)   echo -n "nospace:${1}," ;; esac
```

left the suite **byte-identical** — same pass count, same failures, zero new RED. That arm is the
H-C disk-full path: one of the two live hypotheses the instrument exists to diagnose.

## Root cause

All 7 mutations aimed at `_login_tok`, the hatch, or the call sites. None touched `_login_kw`.
**A mutation battery measures the tests you have against the mutations you thought of.** It cannot
report on a function you did not think to mutate — and its green is *indistinguishable* from the
green of a fully-covered SUT. The battery converts "I believe these tests work" into "these
tests catch these seven things," which reads like the former.

Three further defects shared one root, and it is the same root:

| assertion | anchored on | evaded by |
|---|---|---|
| T-5B-15 "no printf takes an expansion" | the **verb** `printf`, line-wise | `echo -n "$1"`; a `\`-continuation carrying `"$1"` on line 2 |
| T-5B-19 "all hatch calls are contained" | `_login_hatch[[:space:]]+"` — first arg **starts with a quote** | `_login_hatch $E 0 1` → counted 0 → green with an unwrapped 4th site |
| T-5B-16 "tok ∈ closed set" | a **hand-copied** member list | add an arm → fuzz never emits it → green while the claim stops describing the set |

**Each was anchored on the shape the code happens to have today, not on the property.**
`cq-assert-anchor-not-bare-token` says "anchor on syntax" — *today's* syntax is a narrower thing
than the syntax the property permits. The tell is uniform: every one would pass against an
implementation a reasonable engineer might write next.

## Solution

**Enumerate the SUT's functions and confirm each appears on the LEFT of a call in the test file,
BEFORE trusting the battery.** One grep:

```bash
for fn in $(grep -oE '^_[a-z_]+\(\)' src.sh | tr -d '()'); do
  printf '%-28s %s\n' "$fn" "$(grep -c "${fn} \"" test.sh)"
done   # any 0 is an untested function, whatever the battery reported
```

**Invert the anchor from blacklist to whitelist.** Instead of "no `printf` line contains `$`"
(which knows one verb and one line), strip comments, strip the ONE permitted expansion, and assert
no `$` survives anywhere:

```bash
_residue() { printf '%s\n' "$1" | sed 's/#.*$//' | sed 's/\${1:-}//g' | grep -n '\$' || true; }
```

Verb-blind, line-blind, comment-blind — it forbids the input *reaching any line at all*, which is
the actual property. `echo`, `cat`, a variable-indirect call, a continuation: all caught.

**Derive oracles from the SUT, never hand-copy.** `_login_kw`'s entire output vocabulary is
`^([a-z]+,)*$`, so the closed-form regex needs no member list and no parity test — any splice emits
a colon/space/slash and fails it, whatever the arm. Where a member list is unavoidable, extract it
from the SUT body (the `T-PARITY` precedent) and pin a member-count floor so a collapsed extraction
fails loud.

Result: the previously-invisible M-B mutation now goes RED on **two independent guards**. Suite
153 → 166.

## Key insight

**A green mutation battery is evidence about the mutations, not about the tests.** Before trusting
one, enumerate the SUT's surface and confirm the battery's mutations touch all of it. The cheapest
version of this is a grep for each function on the left of a call.

And the anchoring corollary, which is the same lesson at assertion scale: **if you can name an
implementation a reasonable engineer might write next that satisfies your assertion while violating
your property, the assertion is anchored on today's syntax, not on the property.** Anchor on what
the property forbids (input reaching any line), not on the shape it currently takes (`printf` with
a `$`).

## Also caught, all by execution

- **A line-number citation rots INSIDE its own PR, before merge.** Every new `:NNN` this PR added
  to `ci-deploy.sh` was already stale at HEAD — written against `origin/main`'s coordinates and
  invalidated by the PR's own +449 lines. It happened in the same file where I wrote a comment
  citing `cq-cite-content-anchor-not-line-number` as "the same lesson for coordinates". **I cited
  the rule and violated it three lines later.** Two agents converged independently. Corollary
  caught live: while re-anchoring, I asserted `wait_for_cron_trigger()` from memory; verification
  showed `verify_inngest_health()` — the rule paid for itself inside the fix for the rule.
- **A predicted test ID is a false comment the moment it is written.** The instrument commit's
  comments cited `T-5B-10/11/12` for properties whose tests did not exist yet. All were wrong once
  written — including the sentence carrying the single most load-bearing security claim in the
  change (it cited T-5B-10 for a property T-5B-15 pins). Same for counts: the AC9 fractions
  (`161/164`) were stale within the hour. **Do not cite an artifact that does not exist yet; write
  the citation after the artifact.**
- **A multi-state telemetry AC derived from ONE emitter's sites reads RED on correct code.** AC13
  — the criterion that *closes* #6497 — was RED twice more: state (b) keyed on `reason=`, emitted
  only by the zot emitter, so the GHCR parity the same PR delivers matched no state; state (c)
  demanded a "populated `kw`", but `kw` is EMPTY exactly on the novel shape the hatch exists to
  capture (empty IS the H-D datum). The plan's own callout box congratulates itself on fixing this
  defect twice. **Re-check a multi-state AC against every emitter the same PR adds.**
- **We designed out one failure class and enumerated only the side we traded away.** Replacing
  `>/dev/null 2>&1` (no pipe) with an fd3-coupled `$( )` trades a `mktemp` abort vector for a HANG
  vector: the capture blocks until **EOF on fd3**, not until the command exits, so a forked
  grandchild holding the inherited fd blocks it forever — and `timeout <cmd>` does NOT rescue it
  (the kill reaps the command; the grandchild still holds the pipe). No subshell contains a hang.
  The containment table had two columns, both abort classes. **When a change swaps a redirect for
  a pipe/capture, add HANG to the enumeration.** Measured: mechanism real; unreachable via
  `docker login` 29.4.3 (both failure shapes return cleanly, no fd-holder outlives docker).
- **A safety trigger written in the CONSUMER, whose firing condition is already scheduled by a spec
  that does not list the consumer.** `_login_hatch`'s `stderr_chars` length-oracle trigger fires
  "if either token becomes variable-length"; `specs/feat-registry-oidc-migration` FR2/FR3 replace
  both tokens with JWTs and its credential touch-point list does not include `ci-deploy.sh`. Fix:
  reverse-citations at BOTH producers. Also: fixed-length is necessary but NOT sufficient — the
  alphabet must be escape-invariant (`special = false`), and the trigger must fire on a plain
  ROTATION to a different length (the likeliest event, which "becomes variable-length" does not
  describe).
- **A review finding is a claim to verify against the right basis.** An agent flagged
  `cq-cite-content-anchor-not-line-number` as a fabricated rule ID — twice, emphatically. It is
  real (`origin/main`, `385da5d14`, #6527, landed the same day). The agent grepped the **worktree**,
  11 commits behind, which predates it: true of the worktree, false of reality. Apply the same
  verify-the-premise discipline to review output as to a plan.
- **The stale-`origin/main` workaround was unnecessary.** The session opened with "diff the
  commits, NOT `git diff origin/main` — the bare repo's ref is stale and shows false deletions".
  A plain `git fetch origin main` fixed it permanently; the three-dot diff was clean thereafter.
  Prefer refreshing the ref over inheriting a workaround.

## Worth keeping

The **comment-as-falsifier convention** — each test block naming the mutation that proved it RED —
is what made these findings possible. T-5B-19's comment claimed "the equality is what catches a
FOURTH site"; a reviewer could check that claim *because it was written down explicitly enough to
be falsified*, and it was false. A test that states its own falsifier is auditable; one that does
not can only be re-derived. Keep writing them.

## Session Errors

1. **My AC9 battery reported 164/165 confidence while an entire emitter had zero coverage.**
   Recovery: review proved the gap; added `_login_kw` fuzz + 10 per-arm canary fixtures.
   **Prevention:** enumerate the SUT's functions and confirm each is called by the test file before
   trusting a battery (routed to `review` + `work` SKILL.md).
2. **Cited `cq-cite-content-anchor-not-line-number`, then violated it three lines later** — every
   new `:NNN` was stale at HEAD. Recovery: re-anchored all to `<file> › <symbol>()`.
   **Prevention:** re-anchor citations after the diff settles; a coordinate written mid-PR is
   already stale (routed to `review` SKILL.md).
3. **Asserted `wait_for_cron_trigger()` from memory** while fixing the citation rule. Recovery:
   verified → `verify_inngest_health()`. **Prevention:** the rule itself; caught in-flight.
4. **`session-state.md` recorded a `#6416` correcting comment as accomplished; it was never
   posted.** Recovery: verified with `gh issue view` (0 comments citing #6497); Phase 6 re-opened.
   **Prevention:** on resume, treat session-state `### Decisions` as INTENT, not as done — verify
   each against the live artifact (routed to `work` SKILL.md).
5. **Swept 2 of 3 falsified-causation sites** — `zot-registry.tf:60` survived. Recovery: found by
   code-quality-analyst. **Prevention:** grep the literal claim repo-wide, not just the file the
   plan names.
6. **The AC9 fractions I wrote (`161/164`) were stale within the hour** (battery ran at 164; suite
   is 166). **Prevention:** state what went RED, never a denominator.
7. **Dumped a 219-case fuzz failure inline** — violated `hr-never-run-commands-with-unbounded-output`.
   **Prevention:** cap with `cut -c1-N | head`; already hard-ruled.
8. **Bash CWD silently drifted to the bare root** (`fatal: this operation must be run in a work
   tree`). **Prevention:** chain `cd <worktree-abs> && <cmd>` in one call; already documented.
9. **Ran the battery under `| tail -45`**, which buffered ALL output until exit — the Monitor I
   armed then watched an empty file and timed out. Recovery: read the per-mutation logs directly.
   **Prevention:** never pipe a long-running battery's stdout through `tail`; write per-step logs
   and poll those (routed to `review` SKILL.md).
10. **A review agent was confidently wrong twice** about a fabricated rule ID, from a stale base.
    **Prevention:** verify a review finding against the merge target, not the worktree.
11. *(forwarded, plan phase)* An `Edit` failed on a typo in the match string — recovered.
12. *(forwarded, plan phase)* An unaccounted file state was resolved by diffing against HEAD rather
    than proceeding on assumption.
13. **The prior subagent died mid-test-authoring (API stream timeout)** — the reason this session
    exists. One-off; no recurrence vector.

## Related

- [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]] —
  the anchoring class; this is its mutation-battery-scale sibling.
- [[2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again]] —
  "mutation-test the property it names, not where the code sits."
- [[2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it]] —
  the false comment that started this thread.
- [[2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code]] — why the
  battery was committed as a script, and why the restore ran in a separate call.
