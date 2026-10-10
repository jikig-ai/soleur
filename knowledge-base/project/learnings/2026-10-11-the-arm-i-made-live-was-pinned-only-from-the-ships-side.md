# Learning: an arm made live was pinned only from the "ships" side, and my review fixes un-pinned the production defaults

## Problem

#9373: the registry zot log shipper's `is_cap_exempt` keyed the PatchBlobUpload error line on a
message prefix real traffic never carries, so the line was rate-capped while the suite stayed green
over a dead arm. The fix (classify on the parsed top-level `func`, tri-state return, upload
sub-quota) was small and correct. The VERIFICATION of it was not: a 12-seat review plus a 4-seat
fix round found 41 findings, none in the production code, all in what pinned it.

What the first round of tests pinned: the real line ships; one off-class row (`GetBlob`) is capped;
forged rows are capped. What it did not pin, each shown by a surviving mutant: the suffix anchor,
the receiver qualifier, top-level-only extraction, that the error row and the paired HTTP 5xx row
share ONE 8-slot sub-quota, arm precedence against crash-class messages, the probe counters'
conditions, and the suite's own assertion floor (174 against 186 actually run, so all of T21 was
deletable green).

The first batch of fixes then introduced three more defects of the same class: every T21 scenario
was moved to explicit `CAP_EXEMPT=17` / `CAP_UPLOAD_EVIDENCE=8` overrides, so the shipped defaults
(`:-17`, `:-8`) could be changed to 20 and 12 at 198/0 green; S10 (crash message from the upload
handler keeps the shared lane) shipped its row through a free ordinary slot, so demoting the arm
stayed green; and the boundary of the `< 800` payload bound in the two probe counters was pinned
by a 950-character decoy that no shipper can emit.

## Solution

- Pin a newly-live arm from the FAR side, one fixture per property the predicate could be widened
  past: a trailing glob, a dropped receiver, a lookalike receiver (`(*FooRouteHandler)`), the retired
  shape, a nested key, and a precedence case that must NOT take the sub-quota. Each paired with a
  positive control so a deny-everything arm cannot satisfy it.
- Exercise production defaults: only pin the knob that is not under test (here the ordinary cap);
  pin the shipped defaults structurally as well, so a retune is a deliberate edit.
- A fixture at a size bound must sit AT the bound the producer can emit (exactly 800 and 799 here),
  derived by computing the pad from the fixed text, not a comfortable oversize.
- Ratchet the suite's assertion floor in the same edit that adds a section; it equals the measured
  count, and a section deletion then trips it.
- Close a "closing probe" that greps a bare token (`\bfunc\b` is satisfied by `local func="$2"`)
  by requiring the arm itself, and give it three-row coverage (pristine, arm returns 1, arm deleted).
- A mutation fixture on a jq/regex extraction must lack the thing the mutant would fall back to: a
  recursive-descent `..|.func?` mutant is equivalent when the row has a top-level `func` (root is
  visited first).

## Key Insight

When a fix makes a dead path live, the review's yield is in the verification, and the verification
of a fix inherits the framing of the defect: the author pins "it now ships" and one far-side row.
Count what the predicate could be widened or narrowed past and demand a fixture on each side. And
treat every review fix as new code: removing an override to "simplify" a test is how a production
default loses its only exerciser. Run the mutation that undoes THE FIX YOU JUST MADE before
committing it, not only the mutations that undo the original change.

## Session Errors

1. **Hook denials: `pgrep -f` typed twice in a row, then a foreground `sleep 240`.** Recovery: used
   `pgrep <name>` / `list_runs`, and waited for the completion notification. **Prevention:** the
   hook text already names the alternatives; read it once, do not retype the shape.
2. **Hand-copied mutation sandbox under `/var/tmp` was reaped mid-battery; rows 3-4 never ran.**
   Recovery: rebuilt the sandbox inside the worktree and re-ran. **Prevention:** allocate with
   `scripts/soleur-sandbox.sh new`, never a hand-made `mktemp -d` tree; a battery whose rows can
   vanish must assert each row's log exists before reading its verdict.
3. **Mutation row "drop `$zfunc` at the call site" crashed the shipper (unbound `$2` under `set -u`)
   and read as 78 failures.** Recovery: mutated the argument to `"-"`. **Prevention:** a mutant that
   crashes the SUT is not a kill of the guard; mutate to the value the guard would not match.
4. **A T21 helper writing `>> "$param"` moved the fixture-relative ratchet 2002 to 2003.** Recovery:
   helpers write to stdout, callers redirect into a `$TMP`-rooted path. **Prevention:** run
   `fixture-scan.py --rule relative <file>` after adding any writer helper to a `.test.sh`.
5. **An apostrophe in a comment inside the single-quoted `python3 -c '...'` block broke the whole
   7341 probe (7/30 passed).** Recovery: removed it. **Prevention:** no `'` in any comment inside a
   single-quoted interpreter block; grep the added lines for `'` before running.
6. **A multi-edit python script aborted at an assertion after writing some files.** Recovery: the
   next run's counts contradicted the expectation, so the remainder was re-applied. **Prevention:**
   write the edits in one pass per file and assert the artifact after (`git diff --stat`), never
   infer the batch landed from the suite alone.
7. **A recursive-descent jq mutant survived because my fixture had a top-level `func`.** Recovery:
   removed the top-level `func` from the nested-key fixture. **Prevention:** a mutant that "survives"
   gets labelled fixture-gap or equivalent before the guard is touched.
8. **The suite's assertion floor (174 vs 186) was never raised with the new T21 section.** Found by
   review (P1). **Prevention:** raise the floor in the same edit; the floor equals the measured count.
9. **My review fixes dropped the production-default exercisers (overrides in S3/S3b/S4/S10) and S10
   passed through a free ordinary slot.** Found by the fix-round seats. **Prevention:** mutate each
   review fix back out before committing; keep the knob under test unpinned.
10. **The plan asserted "No ADR conflict" while ADR-184 pinned consumers to `message`.** Found by the
    history seat. **Prevention:** grep the ADR corpus for the PINNED FIELD NAME, not for the feature.
11. **`ensure-semgrep.sh` accepts a semgrep binary whose interpreter lacks its module.** Found by the
    SAST seat. **Prevention:** the bootstrap should run `semgrep --version`, not `command -v`.
    Tracked as its own issue (#9957, different subsystem).

## Tags
category: test-failures
module: apps/web-platform/infra, scripts/followthroughs
