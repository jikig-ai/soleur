# Four guards were satisfied by the comment I wrote to explain them

**Date:** 2026-08-03 · **PR:** #7197 · **Issue:** #7204 · **ADR:** ADR-163

## Problem

The git-data birth ran `mkfs.ext4 -q -O quota,project`, setting an ext4 feature whose mount
needs a `quota_v2` module the target image does not ship. Every boot died at
`stage:luks_open` with `-ESRCH`. The fix is one flag. Everything below is about the guards
written around it, four of which were satisfiable by their own rationale prose.

## The generalisable failure: a body-grep over a body that is not comment-stripped

The test extracted the LUKS stage from the rendered cloud-init and asserted properties of it
with `grep`. It carried this comment:

> ADR-152 strips whole-line comments at render, so the collision disappears here for free.

**False.** ADR-152's strip applies only to the nine injected `write_files` scripts, and the
repo states it verbatim in the module the comment cites — `modules/git-data-userdata/main.tf`:
*"cloud-init-git-data.yml itself is NOT stripped."* Measured on the real render: **81 of the
stage's 117 lines are comments**, and this PR added the largest block of them, because the
same PR was required to *document* the defect it was *asserting against*.

That collision is structural, not incidental. **The moment a task requires both "assert X" and
"document X", they collide** — and the richer the rationale, the more surface the grep has to
false-match on. Demonstrated end-to-end by `test-design-reviewer` at **33/33 green with the
boot-critical property violated**:

- **R3(2)** — the *ordering* arm, carrying a three-paragraph "co-presence is NOT ordering"
  rationale — was satisfied by a comment. Seed relocated below every append with prose left
  behind: `seed=22, first-append=55, PASS`, while all four early failure modes appended to an
  unset variable.
- **R3(3b)** — delete the real `[ -r ]` guard, leave a comment naming it → `GUARDED`.

**The fix is to strip at EXTRACTION time, not per-predicate.** One stripped artifact
(`luks-stage.code.sh`) that every downstream predicate reads, so a future arm inherits the
immunity instead of having to remember it. The sibling file in the same directory
(`git-data-luks.test.sh`'s `_luks_slice`) had always done this — which is exactly why the
B16/B17 family was never exposed to the class. **The discipline was applied to one of two
suites, in the direction where the new comment block was largest.**

## The root cause underneath it: an unverified capability claim

The comment was not a slip; it was an inherited belief stated as fact. `hr-verify-repo-
capability-claim-before-assert` exists for exactly this, and **I invoked that same rule
earlier in the same session** to correct someone *else's* false capability claim in
`git-data-rung2-evidence-capture.sh` ("Sentry has no search capability wired in this repo" —
also false, verified with a 200 from the org issues endpoint).

Applying a rule outward and not inward is the pattern worth naming. A capability claim in a
*comment you are writing* is a claim to verify against the producer, at the moment you write
it — not one to inherit from an ADR's title.

## Probes that cannot fail, and stubs that answer the question you wanted

Two instrument failures in one session, both of which produced the answer I was hoping for:

```sh
doppler secrets get HCLOUD_TOKEN --project prd_terraform --config prd --plain \
  | head -c 8 >/dev/null && echo "reachable"     # prints "reachable" ALWAYS
```
`head` succeeds on empty input, so the `&&` fires regardless. The token was empty — the
project name was wrong (`prd_terraform` is a *config* of project `soleur`, not a project).

```sh
curl -sS -o "$M" https://cloud-images.ubuntu.com/releases/24.04/.../manifest   # no -L
grep -c 'linux-modules-extra' "$M"   # => 0
```
The URL 302-redirects. Without `-L` the body is a 372-byte HTML stub, and `0` reads exactly
like the genuine absence I was trying to establish. The re-fetch with `-L` returned 664
packages — and only *then* is `count=0` evidence, because a **positive control** (13 `linux-*`
rows must be present) proves the grep works and the file is the right shape.

**Rule:** every absence measurement needs a positive control in the same command. "Zero hits"
and "I queried nothing" are byte-identical outputs.

## A mutation that does not mutate reports a false PASS

`assert_mutation` ran `sed -E "$expr" "$file" > "$tmp"` and went straight to the predicate.
A sed that **errors** (a BRE `\(...\)` written for an ERE, a `|` delimiter around `||`) leaves
`$tmp` **empty** — and most predicates return `0` on an empty file, which the wrapper reads as
"the mutation flipped the check". Two arms added in this PR did exactly that and reported
PASS while asserting nothing.

Hardened to fail loud on both a sed error and a byte-identical mutant, naming which — they
demand opposite fixes. It paid for itself immediately: it caught a **pre-existing** arm
(`A28b`) the moment an unrelated template edit moved its anchor.

## `[ -r file ]` accepts an empty file

The diagnostic fallback chain was `[ -r "$_detail" ] || _detail="$GIT_DATA_LUKS_DETAIL"` —
falling back to a path *itself never proven readable*, guarded by a test that passes on a
zero-byte file (measured: `DETAIL=[]`). On a read-only `/run` both candidates fail and the
emitter ships **the path string** as the cause: the exact defect the PR existed to fix,
reachable inside its own fix.

**My own test's failure message named that scenario verbatim while the assertion passed.**
Writing the words is not writing the assertion.

Fix: `-s` twice, and make the terminal fallback a self-describing **literal**, never a path —
so a degraded diagnostic announces itself instead of impersonating one.

## Right verdict, wrong mechanism

`user-impact-reviewer` reported B17 too weak and cited `|| mount "$DEV"` as the evasion. I
re-ran the predicate: that shape is **caught** (by the `||` arm, not the raw-device arm it
blamed). Three *other* evasions were real — backslash-continuation, `set +e`, and a sibling
mount line. **Fixing only the cited mechanism would have left all three open.**

Two agent reports also contained confident falsehoods that would have misdirected the fix:
that the diff would *delete* main's ADR-159 (three-dot status is `A` — both files would
coexist), and that a renumber commit already existed on this branch (`git branch --contains`
puts it on a sibling). Verify before acting, especially when the report agrees with you.

## ADR ordinals: check every remote branch, not main's maximum

Collided **five times** on one branch: 158 at plan, 159 at `/work`, 161 at review, then 162 AND
163 during ship — two consecutive syncs each pulled in a freshly-merged ADR at the ordinal I had
just taken. The second happened because I verified "next free" against `origin/main`'s maximum only —
`ADR-160` was already claimed by an unmerged sibling branch. So I widened the check to
`origin/main ∪ every remote branch`, and it collided **again** anyway, when a BEHIND auto-sync
pulled a freshly-merged `ADR-161` in during the ship phase.

The real lesson is not "check harder before you start." On a repo merging this fast, **an ADR
ordinal cannot be reserved at all** — any pre-merge check has a shelf life measured in minutes.
It has to be re-verified after *every* sync, right up to the merge — and 'every' is literal: two
syncs eight minutes apart each invalidated the previous answer. `/ship` Phase 7 already says
this, and following it is the only reason the fourth collision was caught instead of landing a
duplicate ordinal on `main`.

Related: 3 of 4 ADR cross-link filenames I wrote were guesses and were broken. `ls ADR-NNN-*`
is one command.

## Session Errors

1. **Ended the turn on `## Work Phase Complete` instead of invoking `/review`.** The user had
   to ask "why did you stop?". — *Recovery:* resumed immediately. — **Prevention:** a phase
   marker is a checkpoint; the next tool call in the SAME response must be the successor
   skill. Stating an intention is not performing it.
2. **Asserted an unverified capability claim** ("ADR-152 strips comments"), the root cause of
   four vacuous guards. — *Recovery:* strip at extraction. — **Prevention:**
   `hr-verify-repo-capability-claim-before-assert` applies to claims you WRITE, not only ones
   you read.
3. **Probe that cannot fail** (`| head -c 8 >/dev/null && echo reachable`) over an empty
   token from a wrong project name. — **Prevention:** assert the value (`${#T}`), never the
   exit status of a truncating filter.
4. **Redirect stub read as absence** (manifest fetched without `-L`). — **Prevention:**
   positive control in the same command as every absence claim.
5. **BRE seds under `sed -E`** → empty mutants → silent false PASS on two arms. — *Recovery:*
   hardened `assert_mutation`. — **Prevention:** the wrapper now fails loud; this is fixed
   mechanically, not by memory.
6. **`awk 'NR==FNR{next}' /dev/null <file>`** emits nothing. — *Recovery:* caught by my own
   mutation-landed assertion. — **Prevention:** none needed; the guard worked.
7. R1 extraction took the trailing `2>>` redirect as the device operand. — one-off, caught by
   the arm.
8. R3(3) initially asserted the emitter's behaviour rather than the stage's. — one-off.
9. 20d's body match missed shell-escaped quotes → failed closed on a correct emitter. —
   one-off, caught by the run.
10. **Guessed 3 of 4 ADR cross-link filenames.** — **Prevention:** `ls ADR-NNN-*` before
    writing a link.
11. **ADR ordinal collided twice more.** — **Prevention:** verify against every remote branch.
12. CWD drift from a persisted `cd`. — already documented in-repo; used absolute paths after.
13. Scratchpad file swept by a concurrent process. — one-off; re-fetched from GitHub.
14. `T17` transient `exit 100` (apt-get, no network). — flake, confirmed by re-run.
15. WebFetch blocked by Anubis (bootlin, patchwork, git.kernel.org). — recovered via the
    GitHub contents API, which also allowed a precise grep instead of trusting a summary.
16. *(forwarded)* `gh issue create` blocked for a missing `--milestone`, taking its bundled
    heredoc down with it. — **Prevention:** write the body with Write first, then create.
17. *(forwarded)* Plan asserted a `.tf`-free merge does not fire the infra apply. False.
18. *(forwarded)* No local repro of the kernel condition possible — recorded as an open
    assumption rather than papered over.

## Key insight

Every defect in this session's guards reduces to one shape: **a check that certifies something
other than what its name claims.** A grep that reads its own rationale. A probe whose success
is unconditional. A mutation that never lands. A `-r` that passes on empty. A control that
falls through to `pass` on `NOFEATURES`.

The litmus that finds all of them is the same: *name an implementation a reasonable engineer
might write next that satisfies this check while violating the property.* If you cannot, the
check is probably fine. If you can, it is already broken — you just have not met the input yet.

## Tags

category: test-failures
module: apps/web-platform/infra
