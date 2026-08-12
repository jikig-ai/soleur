---
title: The remediation committed every defect class it was remediating — and the class is now documented six times
date: 2026-08-13
category: workflow-patterns
module: guards, review, mutation-testing
issue: 7450
pr: 7482
synced_to: [review, work, compound]
tags: [guards, mutation-testing, review, measurement-hygiene, recurring-class]
---

# The remediation committed every defect class it was remediating

## Problem

PR #7482 (#7450, P0 security) migrated five secret gates off an untrusted git-root anchor. A
10-agent panel found ~15 P1s. I remediated them. A **second** panel then ran against the
remediation, and every blocking defect it found was **the defect class the PR exists to close,
committed while closing it**.

Three were introduced by the remediation commits. Two of those landed inside the single commit
titled *"stop three records asserting the pre-fix state as current"*.

## The honest headline: this class is now documented SIX times

Before adding anything, I checked. These already exist:

- `2026-08-11-my-battery-reported-all-caught-and-eight-axes-were-untouched.md`
- `2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md`
- `2026-08-11-the-pr-that-fixed-unmeasured-verdicts-shipped-unmeasured-verdicts.md`
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- `2026-08-10-my-verification-was-narrower-than-the-claim-it-certified.md`
- `2026-08-12-i-propagated-an-unmeasured-mechanism-and-the-guard-i-built-to-catch-it-was-a-control-shaped-object.md`

**So the useful contribution of this entry is not another restatement.** `review/SKILL.md` already
says it: *"the disposition for a recurring documented class is a mechanical gate, not another
learning."* Six entries and the class recurred anyway — which is evidence the prose layer is
saturated. The deliverable is the gate (filed; see §Disposition), and the two findings below that
are genuinely NEW.

## What was actually new

### 1. A guard suite can be deletable at green, and the fix already existed in-repo

Deleting every assertion in `redact-sentinel.test.sh` left it exiting **0** at
`Total: 0 pass, 0 fail`, which `test-all.sh` reads as a passing suite — in the file whose entire
purpose is proving OTHER files are not deletable at green.

`scripts/lint-guard-contract.test.sh` has shipped the `EXPECTED_MIN` dispatch floor for months.
It was not reused. Measured after adding it: 51 counters neutered → 7 dispatched → rc=1.

**This is the mechanisable one.** Every `*.test.sh` whose final gate is `[[ "$FAIL" -eq 0 ]]`
needs an assertion-count floor, and that is a five-line grep to check across the repo.

### 2. "Executable content" has to mean executable, not merely fenced

Tests 22, 23 and 24 were written in the same two commits as Test 21. Test 21 alone built a fence
extractor, and its own 20-line comment argues why that scoping is load-bearing. **All three
siblings were defeated by a comment.**

Fence-scoping alone was not enough either: with the extractor in place, deleting the real
`[ -n "$PERSIST_SAFE" ]` arm and leaving a comment quoting it still passed, because the comment
sits *inside* the ```bash fence.

The generalisable move, and the one I missed twice: **when you solve this class once in a file,
sweep the siblings in the same commit.** Both fixes here already existed — the extractor pattern in
Test 21, required-membership in Test 24's floor — and neither was carried across. Test 21's floor
was left at `>= 3` against a real population of 15, so one gate could go dark while its siblings
carried the total. That is finding A10 reintroduced *by the commit that fixed A10 elsewhere*.

### 3. A stakes-keyed predicate must key on the ACT, not the NAME

Keying "handles a credential" on credential-shaped **names** matched `$SESSION_TOKENS` (LLM
tokens), `$TRAILER_KEY` (a map key) and `${LINEAR_CDN_PATTERNS}` (via `_PAT`) — enrolling four
redaction engines that acquire nothing, **because token names are their needles**.

And keying the *violation* side on a syntax (`:-`) missed 16 credential scripts invoked through a
**bare** repo-relative path, which is strictly worse (CWD-relative unconditionally). Assert the
**invariant** — *no credential-acquiring script is reachable through a path that resolves relative
to CWD* — and `:-`, bare and `./` become three instances of one class, with no clause needed for a
fourth spelling.

Four containment rules were needed, each added because it fired on real code: comments are
mentions; a script naming its own path is not calling itself; a path read or written as **content**
is a data root (one script edits a map *inside* another and that is not a call); and
`$SCRIPT_DIR`/`$BASH_SOURCE` prefixes satisfy the invariant as fully as `${CLAUDE_PLUGIN_ROOT}`.

### 4. Shell state does not persist across fenced blocks

`$SCRUBBER` was defined in one fence and used in another. Each fence is a separate Bash call, so
the expansion was **empty on every invocation** — the skill was bricked, `persist_safe_summary`
could never be produced, and every caller is contractually required to treat its absence as a hard
stop. It failed *closed* only because the anchor was quoted; unquoted, `bash $SCRUBBER <<'BLOB'`
executes the heredoc, i.e. runs issue text as a script.

The skill's own comment said shell state does not persist — **eleven lines below the use**.

## Measurement hygiene: three rules that each caught a wrong result here

1. **A mutation that does not LAND reports the baseline**, which is indistinguishable from a pass.
   Six rows read `NOT APPLIED` across runs and were repaired, not dropped.
2. **`restore()` must be total.** It omitted one file, so one mutation leaked into the next and the
   next row reported RED *for the previous row's reason* — a fake row that looks exactly like a
   real one, in a harness whose whole purpose is to be believed.
3. **An unexplained ±1 is worth chasing.** A guard's population read 23/24/25 across runs. It was a
   mid-edit transient — but "probably fine" is not an acceptable answer for a security guard's
   population, and confirming it took one in-place re-derivation plus a sandbox comparison.

Also: **a right verdict can rest on a wrong evidence row.** My write-up credited mutation M-H for
surviving a count floor; re-measurement showed M-H *empties* the population (trivially caught) and
M-I is the row that survives. The conclusion held; the cited evidence was wrong — and the battery
script's own comment contradicted my narrative.

## What went right, and is worth repeating

- **Report-only panels above ~3 agents.** `review/SKILL.md`'s sharp edge says concurrent mutating
  agents contaminate each other's reads. Six agents were spawned report-only and I applied every
  fix myself from a known SHA. No contamination, and no finding had to be re-derived.
- **Routing the scope fork instead of deciding it.** Widening the assertion collided with the
  ruling's own "#7453 owns git-worktree" clause. The CTO seat corrected my framing: the ruling says
  *"reads a secret"* — **acquisition** — where two reviewers and I had keyed on **adjacency**. Under
  an acquisition predicate `worktree-manager.sh` never enters the population, so the clause conflict
  dissolved **by definition rather than precedence**, and the naive widening I was about to ship
  would have added 9 false positives.
- **Rejecting a P1 by measurement, and pinning the result.** Finding §B1 prescribed a
  root-outside-worktree `case`. It guards an operand the adversary cannot reach, breaks dogfooding
  on every plain clone, and re-adds `git rev-parse` to the three files the PR de-git-roots. Not
  implemented — and the invariant is now *pinned* (a test), so a future literal implementation
  reddens instead of landing quietly. Rejecting a finding is only safe if you pin what you chose
  instead.

## Session Errors

1. **Asserted a full-suite result that did not exist.** The PR body's §Verification cited a run
   recorded in `session-state.md`; there was none, and the suite was executing as I wrote it.
   **Prevention:** never write into a verification section from intent — fill it from the `rc` file
   and the terminal marker, after the run lands.
2. **Reinstated a retracted claim.** ADR-093 gained "`compound` received a non-blocking guard"
   inside the commit whose purpose was removing false-state claims. **Prevention:** when correcting
   a record, grep the sibling record for the claim you are about to write — the retraction may
   already exist there.
3. **Over-claimed a measurement.** Arm 4 was written as "a reproduced exploit … resolved this
   repo's own redaction gate"; a synthetic probe ran, reproducing the ambient-env variant, not the
   git-root variant the issue is titled for. **Prevention:** state what executed, not what it
   implies; commit the probe so the claim is re-runnable.
4. **Cited the wrong evidence row** (M-H vs M-I) for a correct conclusion. **Prevention:** re-run
   the specific row before naming it in prose.
5. **Two unscoped claims** in `b1-disposition` ("zero occurrences"; "because the install is bare" —
   it is the linked worktree). **Prevention:** scope every count to the surface it was measured on.
6. **A guard reddened on my own prose** — an unscoped grep flagged the rationale explaining a ban
   as a violation of it. **Prevention:** the moment a task requires both "assert X" and "document
   X", they collide; scope the assertion to executable content first, not after.
7. **Reintroduced a count floor** (`>= 5` against 21) in the same commit that replaced a count floor
   elsewhere. **Prevention:** sweep siblings when you fix this class in a file.
8. **Fence-scoping without comment-stripping.** **Prevention:** "executable" means executable.
9. **Missed assign-then-invoke and bare quoted-path** in an execution-context check — the corpus's
   dominant shape. **Prevention:** enumerate invocation SHAPES from the corpus, not from memory.
10. **Battery cross-row contamination** from a partial `restore()`. **Prevention:** restore every
    mutable file every row.
11. **Six battery rows failed to LAND** (perl quoting, stale anchors, a variable used before
    declaration, escaped quotes from a generated edit). **Prevention:** the landing check is what
    made these visible — keep it, and treat `NOT APPLIED` as un-run, never as a result.
12. **Edited the tree while `test-all.sh` was running** — killed and restarted, ~30 minutes lost.
    This is a documented hard constraint I violated. **Prevention:** finish tree edits, verify
    clean, then launch.
13. **Debugged a guard by copying it to `/tmp`**, which broke its `REPO_ROOT` derivation and made
    the measurement invalid. **Prevention:** a script that derives paths from `BASH_SOURCE` cannot
    be relocated for debugging; instrument in place and revert.
14. **Chased an unexplained ±1** in a guard's population. **Prevention:** keep chasing them.

## Disposition

The mechanical gate this class actually needs — *every `*.test.sh` whose final gate is
`[[ "$FAIL" -eq 0 ]]` must also carry an assertion-count floor* — is a new repo-root lint over all
guard suites. That is a different subsystem and its own PR, so it is **file-tracked**, not inlined
here (per `compound`'s recurring-vs-one-off triage).

Everything else above was fixed inline in #7482.
