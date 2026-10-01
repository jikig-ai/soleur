---
date: 2026-09-18
tags: [review, guards, mutation-testing, followthrough, tooling, telemetry]
category: best-practices
refs: [7960, 7500, 7954, 8244, 8272]
---

# Every P1 was in my verification, and a failed edit batch looks exactly like a landed one

## What happened

PR #8272 gave the registry heartbeat a positive delivery field (`err_redact_rev`)
so the #7960 follow-through could stop refusing to grade. The *fix* was one
literal in one emitter. The nine-seat review found **zero P1s in the fix** and
several in the machinery built to prove it:

- `expect()` in the probe harness and `assert()` / `assert_emit()` in the producer
  suite are **verdict-owning** helpers — they decide pass/fail internally and then
  call `pass()`/`fail()`. The existing positive control drove `pass()`/`fail()`, so
  it proved *dispatch* while the deciders decided nothing. Five separate one-line
  edits (neuter the comparisons; never run the probe; rewrite `assert()` to always
  pass; invert both `assert_emit` branches; replace `assert()` wholesale) each left
  its suite **fully green**.
- The fixture set was built case-by-case from failure modes and so never
  instantiated the **success** mode: after delivery the host emits BOTH proofs, and
  `PROOF_SRC="err_redact_rev+suppressed"` — the exact string the closing run prints —
  had no fixture at all.
- Nothing covered `[REDACTED`, which is *the producer's own redaction output*. Drop
  that half of the mask exclusion and every correctly-redacted host posts a daily
  public FAIL.
- Every credential fixture carried one header, so `1-of-1` could not distinguish the
  scanning loop from a single `if` — and the loop exists precisely so a masked header
  cannot shadow a real one later in the same map.

## Two process errors worth as much as the code findings

**A batch edit that fails to parse applies NOTHING, and the suite still shows its
previous green.** A Python heredoc with a trailing `\"` before `"""` raised
`SyntaxError`; the interpreter exited before writing any file. The suite then
reported `37/37 PASS` — which is *the same output as a successful edit that changed
no behaviour*. I reported the fixes as applied. The tell was the assertion count not
moving. Gate: after any scripted batch edit, assert the **artifact** changed
(`grep` the new anchor, or diff against a pre-edit copy), never infer it from a
green suite. A test run answers "does the tree pass", never "did my edit land".

**A repo-global ratchet moved and I nearly attributed it to my own diff.**
`guard-vacuity-floor` went 125 → 124 firing floors. The reflex reading is "my edit
dropped a suite out of the population". Measuring `origin/main` in a clean worktree
showed **186/139/124 there too**: a sibling PR had retired a probe script. My branch
changed the population by zero. Gate: a ratchet is a property of the *tree*, so
before explaining its movement, measure the same ratchet on the base you rebased
onto — the branch's own history is not the only thing that moved.

## Key insight

On a guard-shaped PR the fix is small and the verification is large, so that is
where the defects are — and the author writes the verification while holding the
defect in mind, which is exactly the frame that produces assertions shaped like the
bug rather than like the property.

Two questions did all the work here:

1. **Which helper actually DECIDES?** An anti-vacuity floor dispatched *through* the
   decider cannot see the decider failing open. Every verdict-owning helper needs a
   control that drives it with an input that MUST fail, checks the counter moved, and
   reports via `printf` + `exit` rather than through the helper under test.
   `registry-boot-guard.test.sh` already had this pattern; the two suites this PR
   changed did not adopt it.
2. **Which member does no fixture instantiate?** Not "does a mutation redden" — a
   mutation battery perturbs the SUT and is structurally blind to a gap in the input
   space. The missing member here was the *success* state, the one an operator will
   actually read.

## Prevention

- Verdict-owning helper ⇒ reject control. Litmus: *if this helper always said yes,
  what would notice?* If the answer is "the floor", check whether the floor is
  counted by that same helper.
- Sweep the fixture set by **population and direction**, not by count: which shapes
  can the producer emit that no fixture carries, and which mutation makes the guard
  *more* aggressive (that direction usually has no fixture at all).
- A survivor is fixture-inadequate **or** equivalent — label which. The
  three-asterisk mask survived here; it was fixture-inadequate, and adding one case
  killed it. Leaving it unlabelled is how a guard merely adjacent to a working one
  ships.
- Assert an edit landed in the **artifact**. A green suite after a no-op batch is
  indistinguishable from a green suite after a real one.
- Before attributing a repo-global ratchet's movement to your diff, run it on the
  base.

## Session Errors

- **A Python heredoc `SyntaxError` silently applied nothing, twice.** Recovery: re-ran
  with safer quoting and verified the anchors by grep. **Prevention:** assert the
  artifact changed after a scripted batch edit; never read a green suite as proof the
  edit landed.
- **An apostrophe inside `awk '…'` closed the program** (`jq's @tsv` in a comment I was
  adding), turning the probe into a bash syntax error and the suite 4/38. Recovery:
  rewrote the comments apostrophe-free. **Prevention:** the class is already in
  `work/SKILL.md`; hitting it anyway argues for a mechanical check — `bash -n` after
  every edit to a file containing a single-quoted awk program (which is what caught it).
- **Two assertions of my own were wrong before the SUT was.** `G2-n` compared a JSON-
  tailed value against `none`, and the `last_err_of` helper I reached for next was also
  wrong. **Prevention:** when a brand-new assertion reds, suspect the assertion before
  the subject — print the value once.
- **A debug copy run from `/var/tmp` broke `SCRIPT_DIR`** and produced 32 phantom
  failures. **Prevention:** instrument in place, or carry the resolved paths.
- **A filed issue (#8278) asserted a search "is empty" when it returned 1.** Recovery:
  measured, then corrected the issue body. **Prevention:** run the command before
  quoting its result in a public artifact.
- **`ls | tail -4` truncated a directory listing** and I briefly read two rc files as
  missing. **Prevention:** do not bound the output of a listing you are using to decide
  whether something exists.
- **`bc` is absent on this host**, so a budget check read 0 declarations and false-RED.
  Fixed inline (sums with `awk`). **Prevention:** in a portability-sensitive check,
  prefer the tool the rest of the file already depends on.
- **Two `TEST_GROUP` shard runs returned `rc=4` (REFUSED, nothing ran)** under sibling
  contention, and two background tasks were OOM-killed. **Prevention:** already
  documented; `rc=4` is neither pass nor fail and the substitute is the per-suite set.
- **`git stash list` was denied by a hook** because I chained it into an unrelated
  probe. **Prevention:** keep read-only probes free of stash verbs in this repo.
- **Non-fast-forward push** after rebasing a branch whose draft PR had pinned its base.
  Expected per `work/SKILL.md`; resolved with `--force-with-lease` after confirming the
  remote held only my own commits.
