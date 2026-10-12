---
title: "A mode decided in one step and re-derived in the next is two sources of truth"
date: 2026-10-12
category: workflow-patterns
tags: [github-actions, step-outputs, terraform-plan-json, guard-design, mutation-testing, git-data]
issue: 10137
pr: 10155
---

# Learning: a mode decided in one step and re-derived in the next is two sources of truth

## Problem

The git-data rotate dispatch applied successfully and then failed its own job: the post-apply
backstop asserted both data volumes preserved in every mode, and rotate replaces the LUKS volume on
purpose (#10137). Making the assert mode-aware looked like a one-line change. It produced 29 deduped
review findings across 13 seats, none P1, and two of the avoidable ones were my own design choices.

## Solution

- The backstop moved into a sourced lib function with a per-mode preserved-volume set (replace:
  plaintext + LUKS; rotate: plaintext only). Empty or unknown mode, empty `resource_changes`, and a
  missing NIC or attachment create all fail closed.
- The mode is **published by the step that decided it** (`printf 'gate_mode=%s\n' … >> "$GITHUB_OUTPUT"`
  directly after the plan gate accepts the plan) and read by the apply step through `env:`. My first
  design added a second `apply_target -> mode` helper plus a test policing that the two maps agree; two
  design seats independently asked for the output instead, and the CTO agent reversed its own earlier
  ruling.
- Volumes are matched by the plan's native `.type` + `.name` (root, indexed and module-prefixed alike),
  not by an address regex: the regex missed index keys containing `.` or `]`, and a zero count here
  reads as "preserved", so the wide net is the fail-closed direction.
- The wiring pins run on comment-stripped, line-anchored text: lib sourced by a real top-level line,
  the `if !` call immediately after it, nothing between the apply and the call reassigning the mode,
  the publish directly after the gate block, and no `continue-on-error` in any quoting.

## Key Insight

When one step makes a decision that a later step in the same job must obey, re-deriving it in the
later step is a second source of truth, and the test that "keeps them equal" is a substring grep that
only knows the spellings it already knows. Publish the decision from the deciding step and let the
consumer fail closed on an absent value. Then pin the *wire*, not the endpoints: a presence check on
raw step text survived six of my own workflow mutants (removing the refusal's `exit 1`, a conditional
publish, a mode reassignment between gate and publish, a bare call, a step-level `continue-on-error`);
the comment-stripped, anchored form killed all twelve I tried.

A second, smaller lesson: the plan-phase CTO ruling was made without the step-scoping view, so it chose
between two *helpers*. The review-phase view saw that the right answer removed the helper. A ruling
made at plan time is a hypothesis about a design that does not exist yet.

## Session Errors

1. **Scripted workflow edit anchored on text that occurs in three sibling jobs** (the stock-preflight
   comment). The `assert count == 1` guard raised before any write, so nothing landed silently. —
   Recovery: scope each replacement to the git-data step's own region. — **Prevention:** slice the
   edit to the step (`index` of the step header to the next step header) before asserting uniqueness.
2. **Empty `$TMPDIR` sent a redirect to `/x.log`** (permission denied). — Recovery: used the session
   scratchpad. — **Prevention:** write logs to the scratchpad path, never `$TMPDIR/…` without checking it.
3. **Shared fixture builder emitted invalid JSON** for an address with embedded double quotes. —
   Recovery: escape them the way the suite already does for `web["web-1"]`. — **Prevention:** build
   addresses containing `"` with the escaped form from the start, or via `jq -n`.
4. **First wiring pins were presence checks on raw text.** Six workflow mutants survived. — Recovery:
   comment-stripped, anchored pins plus a 12-mutant battery. — **Prevention:** any pin over workflow
   text strips comments first and anchors on a line start; run the mutation battery before the panel.
5. **A thin `pa_check` wrapper around `gate_check`** that no harness self-test drove, so replacing its
   body left the suite green. — Recovery: removed it. — **Prevention:** call the self-tested helper directly.
6. **Second apply_target-to-mode mapping** (`git_data_gate_mode`). — Recovery: step output. —
   **Prevention:** a decision a later step must obey is published, not re-derived.
7. **Mutation-sed anchors drifted** (PM3-PM5) when the function was rewritten. — Recovery: the harness's
   "matched nothing" refusal caught every one; re-anchored. — **Prevention:** none needed, the
   refusal is the control; keep it.
8. **A killed affected-gate run left an rc file (143) that a watcher then reported.** — Recovery:
   recognised the exit as my own kill. — **Prevention:** after killing a run, delete its rc file.
9. **Anti-vacuity floor miscalibrated several times** (terraform present adds the HK13 assertion). —
   Recovery: floor = measured with terraform minus one. — **Prevention:** set it from the final green run.
10. **Address regex missed index keys containing `.` or `]`.** — Recovery: native `.type`/`.name`. —
    **Prevention:** match plan resources by their native fields, not by parsing the address string.
11. **Sanitizer test whose fixture the 16-char cap truncated away**, so it could not tell the sanitizer
    was present. — Recovery: shorter fixture plus a 40-char truncation row. — **Prevention:** a
    transform-under-test row must survive every later transform in the pipeline it runs through.
12. **Three Stop-hook interruptions** on closing sentences that named a future action while seats were
    running. — Recovery: ended with an explicit `Paused:` sentence. — **Prevention:** when waiting on
    background work, state the wait as a `Paused:` line instead of describing the next step.
13. **The flip gate's comment says the "rotate confirm token" step succeeds only on rotate; it exits 0
    "n/a" on a plain replace** (found at CONCUR, not by any gate). — Recovery: recorded as an operator
    scope decision in `decision-challenges.md`; not widened into this PR. — **Prevention:** a claim
    about a sibling step's conclusion needs the step's own exit paths read, not its name.
14. **The mid-replace annotation defaulted to the plain-replace claim** ("BOTH volumes are preserved")
    for any non-rotate mode. — Recovery: replace / rotate / neutral arms. — **Prevention:** a message
    that asserts a fact about user data takes the neutral arm on an unknown input.

## Operator note

A fresh `git-data-host-rotate` dispatch after this merges would re-replace the LUKS volume that run
38140050880 already created (ADR-239 amendment 2026-10-12). Confirm the target and the `served_repos=0`
precondition before naming the command; this PR does not dispatch anything.

## Tags

category: workflow-patterns
module: infra/ci (git-data replace and rotate dispatch)
