# Learning: `terraform show -json` carries two namespaces — a probe that descends the whole document reads declaration as state, and a sourced global does not survive `$(...)`

## Problem

PR #9634 (#9510, class-aware stock-gate closing + post-destroy recovery read) added a
`stock_recovery_report` that asks, after a failed apply, "did the planned `hcloud_server`
create land in state?" The first implementation ran jq over the whole serialized document:

```jq
[.. | objects | select(.address? == $a)]
```

`terraform show -json` emits BOTH `.configuration` (what the root module *declares*) and
`.values` (what the last apply *recorded*). After a destroy-first `-replace` whose create
failed, the address still exists under `.configuration` — it is in the source — so the
probe reported **present** for a resource that state had already destroyed. A recovery
read whose whole job is distinguishing "create never landed" from "create landed and a
later step failed" would have prescribed the wrong re-dispatch arm. The inline review
caught it before merge; the regression fixture puts the address under `.configuration`
only and requires the report to say absent.

The same session surfaced a second, subtler propagation failure: the gate communicates
its verdict class through a sourced-shell global (`_STOCK_LAST_CLASS`). The first test
and the first workflow probe captured the call with `$(...)` — a subshell — so the global
never propagated and the caller silently read an empty class. No error fired; the wrapper
just rendered the generic message the refactor existed to eliminate.

## Solution

- Scope any applied-state probe to `.values` and pin the resource type:
  `[.values | .. | objects | select(.address? == $a and .type? == "hcloud_server")]`.
  `.configuration` answers "what did we ask for," never "what exists."
- A function whose contract includes a sourced global must be invoked in the current
  shell: `stock_preflight_gate "$plan" > "$TMP/out" 2>&1; rc=$?` — never `out=$(...)`.
  The workflow advisory probe uses the same redirect-to-tempfile shape.
- Enumerate every consumer when a wrapper's contract changes: `git grep -n
  'stock_preflight_gate' .github/` found the sibling `web2-luks-rebirth.yml` call site
  that the diff's own file list could not show; the T32 parity test now greps all call
  sites repo-wide so a fourth consumer cannot regress silently.
- A mutation that does not change the tested behavior scores as "survived" for the wrong
  reason — verify the mutant diff is non-empty *in the asserted surface* before counting
  the row (M2.3's first edit left the doctrine echo in place).

## Key Insight

A serialized Terraform document is not one fact — it is a plan joined to a state, and the
two disagree precisely in the failure windows a recovery probe exists for. Any probe over
such a document must name which subtree is authoritative for its question, and the
regression that pins it must place the fixture in the *wrong* subtree, not merely omit it.
The second lesson is mechanical: a sourced global is a side-channel that `$(...)` amputates
without an error — the only safe call shapes are direct invocation or a tempfile bridge,
and the test must call the function the same way the workflow does.

## Session Errors

1. **`_STOCK_LAST_CLASS: unbound variable` under `set -u`** — new tests referenced the
   sourced global before any call populated it. Recovery: `${_STOCK_LAST_CLASS:-}` at
   test read sites.
   **Prevention:** when a lib introduces a global, write the empty-value read as
   `${VAR:-}` in tests by reflex; `set -u` makes the unwritten read the crash.
2. **Command substitution dropped the sourced global** — T29 and the workflow advisory
   probe first used `$(stock_preflight_gate ...)`, silently losing `_STOCK_LAST_CLASS`.
   Recovery: direct call with output redirected to a tempfile, in both the test and the
   workflow `run:` block.
   **Prevention:** any function that returns data via a sourced global must never be
   invoked in a subshell; the suite now pins the direct-call shape (T29, T32).
3. **Recovery doctrine wording mismatch** — T31 asserted "retained"/"preserved" while the
   first implementation wrote only "survive." Recovery: emit "RETAINED across the failed
   create."
   **Prevention:** write the assertion's vocabulary into the implementation first, or
   assert on the mechanism (the retention token) rather than a paraphrase.
4. **Edit `old_string` mismatches on the workflow YAML** — several replacements were
   drafted from memory of the file rather than its bytes. Recovery: read each call site,
   then exact-replace.
   **Prevention:** already covered by `hr-always-read-a-file-before-editing-it`; the cost
   here was re-reading after the fact.
5. **State probe read `.configuration` as state** — whole-document jq descent reported a
   declared-but-destroyed server as present. Recovery: scope to `.values`, require
   `type == "hcloud_server"`, add a configuration-only regression fixture.
   **Prevention:** for any `terraform show -json` probe, ask "declared or applied?" and
   place the regression fixture in the subtree the probe must ignore.
6. **Shallow mutant M2.3 scored as surviving** — the edit did not actually remove the
   doctrine line, so the surviving row measured nothing. Recovery: re-ran M2.3 with the
   doctrine genuinely removed; all intended mutants then went red.
   **Prevention:** before scoring a mutation row, diff the mutant against the asserted
   surface — a mutant that leaves the assertion's referent intact is equivalent, not
   surviving.
7. **`git stash` attempt in the worktree** — blocked by hook (deny fired as designed);
   no stash was used, WIP was committed incrementally instead.
   **Prevention:** already hook-enforced (`hr-never-git-stash-in-worktrees`); the hook
   worked — no proposal.
8. **Sibling workflow call site missed in the first propagation pass** —
   `.github/workflows/web2-luks-rebirth.yml` carried the same class-blind closing and
   had no recovery read; found by enumerating `stock_preflight_gate` call sites, not by
   the diff. Recovery: both pre/post closings routed through `stock_abort_closing` and
   its apply failure wired to `stock_recovery_report` (commit 9a2d84a35e).
   **Prevention:** T32 now greps every call site repo-wide — a new consumer fails the
   suite until it uses the shared helpers.
9. **Full-tree infra lint returned 518 pre-existing hits** — obscured whether the plan
   itself was clean. Recovery: ran the plan-scoped lint (0 hits).
   **Prevention:** scoped-lint is the established practice; a dirty-tree lint number is
   noise unless diff-scoped.
10. **Pre-existing shellcheck warnings (SC2034/SC2015 in the suite, SC2153 in web2)**
    surfaced during the review pass — none introduced by this change.
    **Prevention:** none — pre-existing; note only that new code must shellcheck clean
    even when the file-level report is noisy.

## Related Issues

- #9510 — the parent issue this work closes
- #6393 — the historical stranding incident the recovery read defends against
- #6453 — stock preflight gate introduction
- #7146 — degraded-review disclosure precedent (this PR ships `inline-fallback 0/10`)
- #7490 — archived spec read at live path; this session deliberately deferred Step E
  because ship Phase 6 step 2.5 reads `decision-challenges.md` from the live spec dir

## Tags

category: workflow-issues
module: stock-preflight-gate / terraform

## Ship-Phase Addendum (CI reds on the pushed head)

Three more session errors surfaced only when CI ran the repo-wide ratchets the
file-scoped suites cannot see:

11. **`lint-trap-tempfile-ownership` rule (c) flagged the new `mktemp`** — a sourced
    library cannot own `trap ... EXIT` (it would replace the caller's), so the site
    needed the `lint-trap-ownership: ok` annotation AND the escape fires only when the
    marker sits on the offending line or the ONE above it — a multi-line comment block
    whose `ok` line is three lines up reads as unannotated.
    **Prevention:** when annotating, keep the marker a single line directly above (or
    trailing) the allocation, and run the repo lint, not just the file suite.
12. **Class-b high-water ratchet** — the annotation satisfies rule (c) but the census
    still counts the entrant; `scripts/lint-trap-tempfile-ownership.highwater` must be
    raised DELIBERATELY in the same commit (69→70 with a dated entrant note).
    **Prevention:** after any `lint-trap-ownership: ok` addition, run
    `--check-highwater` — the escape and the ratchet are two different ledgers.
13. **`|| true` on an unconditional-0 diagnostic tripped the S12e/S12p swallow ban** on
    web2-luks-rebirth — the `|| true` was redundant AND masked the stub-suite's real
    failure (the stub lib lacked `stock_recovery_report`, so `bash -e` died before the
    re-dispatch line). Removing it surfaced the actual stub gap.
    **Prevention:** a function that returns 0 by contract takes no `|| true`; when a
    test harness stubs a sourced lib, extending the stub's function surface is part of
    the contract change, and a swallow on the call site hides the mismatch.
