---
title: "My A/B could not resolve the effect I concluded from it — and the battery it guarded was deletable"
date: 2026-07-27
category: test-failures
module: apps/web-platform/infra
issue: 7001
tags: [measurement, noise-floor, mutation-testing, vacuity, anti-vacuity, pipefail, bash]
---

# My A/B could not resolve the effect I concluded from it

## Problem

A perf task asked me to stop `credential-persist-home-guard.test.sh` copying a 162 MB
`.terraform` provider cache into each of its 24 mutation sandboxes. The fix was small and the
numbers were dramatic (peak 3,980 MB → ~5 MB). Two things went wrong anyway, and neither was
visible from inside the work.

**1. I overrode a plan prescription on a measurement that could not support it.** The plan
mandated a `.terraform`-absent fast path, citing a cold-root regression of 9.8s → 11.0s without
it. I re-measured with an interleaved A/B (5 pairs) and got **6.86s WITH vs 6.60s WITHOUT**, then
concluded "no saving" and removed the line.

That conclusion is unsupportable, and worse, its **sign is impossible**. The fast path is
*strictly less work* — no subshell fork, no 235-way glob expansion, no 235-argument `execve`. It
cannot be slower. Measured at the primitive level it saves ~3.7 ms per copy = **~89 ms per suite**,
against a whole-suite noise floor of **~±590 ms (1σ)**. Resolving an 89 ms effect whole-suite needs
**~160 interleaved pairs**; I ran 5. My harness could never have seen it in either direction.

I had correctly identified that the plan's sequential 3-run blocks did not control for drift, and
built an interleaved harness to fix that. Interleaving was the right correction — it just doesn't
buy resolution. I fixed the *bias* and then read a number dominated by *variance* as if the bias
fix had made it trustworthy.

**2. Six guards in the file were asserting nothing, and I added a seventh.** An 8-agent review
proved, by mutation on sandbox copies, that the suite shipped green under:

| Mutation | Result before fix |
|---|---|
| delete **every** `expect_red`/`expect_green` call | `PASS=6 FAIL=0`, **exit 0** |
| revert `copy_scan_tree` to a full copy (162 MB back) | `PASS=29 FAIL=0` |
| drop `--exclude` from `expect_red`'s diff | `PASS=29 FAIL=0` |
| delete the scanner's `dirs[:]` walk prune | green on every shape |
| break `fresh_sbx` reclamation (the PR's own memory bound) | green on every shape |

The first row is the root cause: the only merge gate is `[[ "$FAIL" -eq 0 ]] || exit 1`, and CI
reads only the exit code. **In a file whose header declares "ANTI-VACUITY IS THE WHOLE POINT",
nothing asserted that the battery ran.** Every other anti-vacuity mechanism in it — the census
floor, the scanner's own `min=`, the per-mutation attribution greps — is defeated by simply not
calling the function.

Then my own fix for the walk prune used `python3 "$SCANNER" "$_dsrc" | grep -qF '<unit>'`. The
scanner exits 4 on a 1-unit decoy, so under `set -o pipefail` the pipeline is non-zero **even when
grep matches** — the failure branch was unreachable. My mutation battery caught it; reading the
code did not.

## Solution

- **Report an unresolved effect as unresolved, never as zero.** State the noise floor next to the
  delta. If `|delta| < noise`, the honest finding is "this harness cannot see it" — and if the
  sign is physically impossible, that is proof the harness is noise-dominated, not a result.
- **Measure the primitive when the primitive is what changed.** A ~3.7 ms/copy difference is
  trivially measurable in isolation (25 reps, negligible variance) and invisible whole-suite.
- **Keep the decision, fix the justification.** Removing the fast path was still correct — for a
  *coverage* reason that needs no timing at all: CI never runs `terraform init`, so with a fast
  path CI would never execute the `GLOBIGNORE` line, and the pins guarding it could never fire.
- **Assert that the battery ran.** A `MIN_ASSERTIONS` floor at the chokepoint. A floor, not
  equality — the count is developer-incremented, so `-eq` turns every new assertion into a
  spurious failure.
- **Make the coverage gap testable instead of documenting it.** CI is always cold, so every
  real-root assertion pinned nothing on the only shape that gates merges. A ~2 ms synthetic
  **decoy root** (`.terraform/` + `.gitignore` + `.terraform.lock.hcl` + a vendored unit under
  `.terraform/modules/`) asserts both `GLOBIGNORE` properties *and* the walk prune on every run.
- **Single-source a literal that must agree across call sites.** `scan_diff()` collapsed three
  `--exclude=.terraform` sites to one, so "the copy and the diff drift apart" became
  unexpressible rather than merely documented.
- **No pipe when the producer's exit code is meaningful.** Redirect to a file and grep the file.

## Key Insight

**Interleaving removes bias; it does not add resolution.** Fixing the *known* flaw in a harness
makes its output feel trustworthy, which is exactly when an unrelated flaw — insufficient power —
goes unchallenged. Before reading any A/B, ask two questions the numbers cannot answer for you:

1. *What is this harness's noise floor, and is my delta bigger than it?*
2. *Does the sign make physical sense?* A result that contradicts "strictly less work is not
   slower" is a broken instrument, not a discovery.

And the structural sibling: **a guard's assertions are only as good as the assertion that the
guard ran.** Anti-vacuity mechanisms compose downward — a census floor inside a function is
defeated by not calling the function, so the outermost claim ("N assertions executed") needs its
own pin or none of the inner ones bind.

## Session Errors

1. **CWD drift silently emptied my search space.** An earlier `cd knowledge-base/project/specs/…`
   persisted across Bash calls, so `git ls-files` / `git grep` searched only that subtree and
   returned nothing. I briefly concluded the plan cited two non-existent files. Caught only when
   `head apps/web-platform/infra/run-registered-suites.sh` failed on a file I had run minutes
   earlier. **Prevention:** the known CWD-drift class has a new symptom worth naming — `git
   ls-files`/`git grep` are CWD-scoped, so drift degrades them to *silently empty* rather than to
   an error. Treat any "the file does not exist" conclusion from a repo-wide grep as requiring a
   `pwd` check first.
2. **Concluded "no saving" from an underpowered A/B with an impossible sign.** See above.
   **Prevention:** state the noise floor beside every measured delta; treat an impossible sign as
   an instrument fault.
3. **Shipped a pin that could never fire** (`python3 | grep -q` under `pipefail`). **Prevention:**
   this class is already documented in `work/SKILL.md` and it recurred anyway — the disposition
   for a recurring documented class is a mechanical check, so the sweep
   `grep -nE '\|[[:space:]]*grep -[a-zA-Z]*q'` now runs over any suite I touch.
4. **A benchmark arm silently ran the wrong shape.** The "warm" battery arm's provider cache had
   vanished, so `cp -al` failed and every warm result was actually cold — identical numbers in
   both columns were the only tell. **Prevention:** the committed harness now **FATALs** when
   `--mode warm` cannot find a cache, instead of degrading to a silent no-measurement.
5. **Set the assertion floor to 33 when the real count was 34.** A floor below the count cannot
   catch a single deleted assertion. **Prevention:** derive the floor from a green run, never from
   the number you expected.
6. **Embedded a superseded figure in shipped source** — `8.3s` was the *with-fast-path* median,
   quoted as "this form's median". **Prevention:** committed the benchmark harness so every
   measured claim in a comment is re-derivable rather than resolving to a PR description.
7. **An agent-prescribed fix was wrong.** `GLOBIGNORE="$1/.terraform:$1/*/.terraform"` cannot
   exclude a nested cache — `GLOBIGNORE` filters glob *expansion*, and `cp -r` recurses on its own
   (verified empirically). **Prevention:** the existing "verify reviewer-prescribed fixes before
   applying" rule held; testing it cost one command and avoided shipping a no-op.
8. **CI lint failed on a line asserting the opposite of what it matched** — a "Post-merge
   (operator): *None*" line that enumerated `terraform apply` / credential mint / dashboard visit
   while ruling them out. **Prevention:** state what is not needed without naming the forbidden
   actions; the actor+imperative co-occurrence is what the linter sees.
9. Scratch-harness bugs (sampler arithmetic on multi-line `du` output; bench root derived from the
   mutant's own directory; nested-quote syntax error) — one-offs in throwaway scripts, each caught
   immediately by its own output.
10. `rm -rf` inside a compound Bash command was blocked twice by the guardrail. The guardrail
    behaved correctly; the fix was moving the logic into a script file.

## Related

- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — the panel found the vacuity my
  own battery missed, which is the pattern that rule predicts.
- `2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md` — same `pipefail` class,
  recurred here in a *new* form (non-zero producer rather than SIGPIPE).
- `2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`
- #6665 — the actual lever for the infra runner's 8.5 min; this PR is explicitly not it.
