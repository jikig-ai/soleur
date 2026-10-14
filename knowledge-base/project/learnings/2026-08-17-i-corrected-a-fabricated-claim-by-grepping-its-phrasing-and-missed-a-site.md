---
date: 2026-08-17
issue: 7539
pr: 7568
category: workflow-patterns
component: web-platform-infra-apply-workflow
problem_type: process_issue
tags: [review, fabricated-claims, correction-sweep, guard-design, mutation-testing, terraform-target, derived-set]
---

# I corrected a fabricated claim by grepping its phrasing, and missed a site

## Problem

PR #7568 moved one `-target=` line out of a bridge-less stage-1 plan step into the post-bridge
stage-2 apply step. The fix is one line. Everything else in the PR is the guard that stops it
recurring — plus corrections to statements the move falsified.

Three of those statements I had written myself, from recollection, and never re-derived. One of
them I propagated into four artifacts. And **the correction pass for it missed a fifth site,
because I grepped for the claim's phrasing instead of for the claim.**

That last sentence is the finding. The corpus already knows that unmeasured claims are a defect
class (#7310) and that blanket sweeps can rewrite too much (#7162). This is the inverse and it is
not yet written down: **a remediation sweep that indexes on wording rewrites too little, and its
residual-zero count certifies the miss.**

## The three claims I fabricated

| Claim | What was true | Where it had spread |
|---|---|---|
| The violation was appended "six lines beneath" the ALLOW-LIST MAINTENANCE comment | Measured in `0d6443960`: the gap is **138 lines** | workflow comment, ADR-154, plan, `tasks.md` |
| The recovery lever `-F reason=...` was broken and needed `apply_target` | `apply_target` declares `default: manual-rerun`, which already satisfies the job's gate. The original instruction was correct — I "corrected" a working instruction into a broken one | workflow recovery comment |
| `SENTRY_USERID_PEPPER` must be injected or `vector validate` false-fails | `vector.toml`'s only `${...}` is `BETTERSTACK_LOGS_TOKEN`. The pepper is a VRL `get_env_var()` read at **runtime**, which `--no-environment` never reaches. The injection mirrors CI; it is not required | workflow comment |

All three are retracted **in place** rather than deleted, so the retraction is visible to the next
reader instead of the claim silently vanishing.

## The miss that matters: I indexed the sweep by phrasing

Having measured the 138-line gap, I swept the four sites carrying "six lines beneath". The sweep
came back clean. It was clean — of that string.

`tasks.md:51` said "six lines **below**".

The sweep was keyed on the sentence I remembered writing, not on the claim the sentence made. A
residual count (`grep -c 'beneath' == 0`) is structurally blind to a synonym, so the count reported
green on an uncorrected file. **This is the same defect one level up:** the fabricated claim came
from indexing memory instead of measurement; the correction came from indexing phrasing instead of
measurement.

And the same pass left four further stale counts alive — "the 80 non-SSH resources" (measured
**122**), "these 7", and "the 8 `server.tf` siblings" (twice) — plus a plan claiming 45 infra `.tf`
files where there are **46**.

### The rule

When correcting a factual claim, **sweep for the subject, not for the sentence.** Grep the noun the
claim is about (`ALLOW-LIST MAINTENANCE`, the resource name, the count's referent), read every hit,
and decide each one. Then replace the corrected text with **derived-set language** so the next
reader gets a number that cannot go stale, rather than a freshly-correct number that can.

A residual-zero count is evidence about a string. It is never evidence about a claim.

## The guard insight: pin the premise, do not widen the line

Guard 1 asserts that no `terraform_data` is `-target`ed before the SSH bridge in a job. That bright
line is strictly stronger than an SSH-provisioned-only check — **but only while `terraform_data` is
the sole resource type carrying provisioners.** That premise was unstated.

The reflex was to widen: teach the parser every resource type, handle `hcloud_server.web`, extract
an HCL module. That is ~100 lines and a new parser to maintain.

The cheaper and stronger move is to **pin the premise with its own assertion**:
`resourceTypesWithProvisioners()` walks every resource block of any type and asserts the set is
exactly `{terraform_data}`.

Pinning beats widening because it fails **in the PR that introduces the violation**, names the
offending resource, and needs no parser edit. Widening would have to anticipate the shape; pinning
only has to notice the premise changed.

## Derive the guarded set; never restate it

Guard 1 originally read the job literally named `apply`. Five workflows use `cf-tunnel-ssh-bridge`
— `vector_redeliver` has the identical two-stage shape, is compliant only by step order, and was
entirely outside the guard.

The fix walks **every** bridge-using workflow, derived by scanning `.github/workflows` for the
bridge's `uses:` value, rather than a restated list of five.

A hardcoded five would reproduce the exact defect the file exists to catch: a set embedded in code
going stale the moment the set grows. Deriving means a sixth workflow is guarded on arrival.

This bit twice more in the same PR. The green-skip notify arm made a **thirteenth** Resend emitter
while `model.c4` still read "one of twelve" — caught only because `c4-count-parity` derives that
number and fails **closed** on an unmapped number-word. The plan's own "no C4 impact" finding was
correct for the original scope and became false when a phase was folded in afterwards; nothing
re-ran the plan-time gate that the scope widening falsified.

## A scope-out filing is a claim, and claims get measured

I filed a `cross-cutting-refactor` scope-out for widening the SSH predicate. The CONCUR gate
rejected it and was right on every count:

- The criterion requires ≥3 files **materially unrelated** to the core change. Every edit lands in
  `terraform-target-parity.test.ts`, the file this PR rewrote. Unrelated files: **zero**.
- The >100-line estimate was real only because the proposal bundled a module extraction nothing
  imports. It measured **the chosen fix**, not the finding.
- The trigger read "when a **third** workflow adopts the shape" — already satisfied when I wrote it,
  since five workflows use the bridge. **A trigger whose condition is already true is a decision not
  to look.**
- The proposed probe could not fire: `grep -L 'resource "terraform_data"'` is **file**-granular
  against a **resource**-granular invariant, so a provisioner added to `hcloud_server.web` inside
  `server.tf` leaves the file matching the exclusion and the probe silent.

Both findings were fixed inline in ~15 lines. The deferral was more expensive than the fix.

## Session Errors

- **Fabricated the "six lines beneath" gap (actual: 138) and propagated it to four artifacts.**
  Recovery: measured in `0d6443960`, corrected in all four, retraction left visible in ADR-154.
  Prevention: for every causal or quantitative claim the diff's prose *adds*, name the command that
  would falsify it and run it before writing it.
- **Corrected a working recovery instruction into a broken one.** Recovery: reverted; retraction
  recorded inline. Prevention: before "fixing" an instruction, run it — a `default:` on a
  `workflow_dispatch` input can already satisfy the gate you think is unsatisfied.
- **Asserted `SENTRY_USERID_PEPPER` was required for `vector validate`.** Recovery: corrected; the
  comment now states injection mirrors CI and is not required. Prevention: distinguish
  build-time `${...}` interpolation from runtime `get_env_var()` before claiming a validation
  dependency.
- **Correction sweep keyed on "beneath" missed `tasks.md:51`'s "below".** Recovery: found on a
  second pass. Prevention: sweep for the claim's *subject*, not its wording; replace with
  derived-set language so the site cannot go stale again.
- **Four further stale counts survived the sweep** (80→122, "these 7", "the 8 siblings" ×2; 45→46
  infra `.tf`). Recovery: all replaced with derived-set language. Prevention: same as above.
- **First-draft guard matched only bare, line-leading `-target=`** while the file's majority style is
  quoted (69 single-quoted, 14 double-quoted, 139 bare, 13 `-replace=`). Two review agents proved by
  execution that the exact #7539 regression, single-quoted, passed **117/117 green**. Recovery:
  token-shape, job-scope, fail-closed and allowlist repairs, each with a fixture that reds without
  it. Prevention: when sibling helpers in the same file already carry quoting tolerance with a
  comment explaining why, do not write a narrower matcher beneath them.
- **A mutation proof silently no-opped** — the replacement pattern escaped a backslash the YAML does
  not have, so it reported a surviving mutant against an unmutated file. Recovery: anchor asserted;
  landing confirmed by diff against a pristine backup **before** the result is read. Prevention:
  never read a mutation result without first proving the mutation landed.
- **An assertion matched its own explanatory comment** (`not.toContain("always()")` matched the
  comment saying why the step does not use `always()`). Recovery: re-anchored on the `if:` line,
  which a comment cannot occupy. Prevention: anchor negative assertions on syntax positions, not on
  free text.
- **Two false claims in the test file's own header** ("comment-stripping is load-bearing" — false for
  the first draft, whose `^\s*` anchor already rejected commented lines, making the strip a measured
  no-op; and "Guard 1 intersects `collectSshProvisioned()`"). Recovery: both corrected; the strip is
  now genuinely load-bearing under an unanchored matcher and H1 pins it. Prevention: a header that
  explains *why* code is load-bearing is itself a claim — re-derive it when the code changes.
- **Plan drifted from what shipped**: 3 files listed vs 7 touched; a spent Risks row; a spent
  merge-conflict row; AC9-11 cited where the ACs are AC11-14; a stale line coordinate after a
  sibling PR shifted every line. Recovery: reconciled in `240a7e1c4`. Prevention: cite sites by
  **content anchor**, never by line number (`cq-cite-content-anchor-not-line-number`).
- **Scope-out filing contained a factual error and an unfireable probe.** Recovery: gate DISSENTed;
  both findings fixed inline in ~15 lines. Prevention: a deferral trigger whose condition is already
  satisfied is not a trigger — measure the condition before filing.

## Key Insight

Three lessons, in the order they cost the most:

1. **A correction sweep indexed by phrasing reproduces the defect it is correcting.** Sweep the
   claim's subject; a residual-zero count is evidence about a string, never about a claim.
2. **When a bright line's strength rests on an unstated premise, pin the premise — do not widen the
   line.** Pinning fails in the PR that breaks it, names the offender, and costs ~15 lines instead
   of ~100.
3. **Derive the guarded set from the tree; never restate it.** A hardcoded list inside a guard
   reproduces the staleness class the guard exists to catch.

## Related

- `knowledge-base/engineering/architecture/decisions/ADR-154-repair-the-credential-channel-not-the-host.md` — proposition 3 amended: a stage with no channel must not plan over it
- `knowledge-base/project/learnings/2026-08-06-i-shipped-two-unmeasured-causal-claims-inside-the-lint-that-forbids-them.md`
- `knowledge-base/project/learnings/workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md`
- `knowledge-base/project/learnings/2026-08-12-every-fix-i-shipped-reintroduced-the-class-it-closed.md`
- Rules: `cq-cite-content-anchor-not-line-number`, `cq-assert-anchor-not-bare-token`
