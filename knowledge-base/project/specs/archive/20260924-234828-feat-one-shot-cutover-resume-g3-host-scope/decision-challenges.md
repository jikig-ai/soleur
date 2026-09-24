# Decision Challenges — feat-one-shot-cutover-resume-g3-host-scope (plan-review, 2026-09-24)

The plan-review panel was DHH, Kieran, code-simplicity and the CTO (devex lens). It reviewed
`knowledge-base/project/plans/2026-09-24-fix-cutover-resume-g3-current-host-scope-plan.md`.
Headless run: every Mechanical finding was applied to the plan, and its §Plan Review Revisions
lists them. The items below are recorded for visibility.

## DC-1 — Scope widened past op=resume: op=arm G3.7 H and LUKS G3 are floored too

**Classification:** Taste (scope). The ask named op=resume G3 only. The plan also applies the floor
to the two other write-gating liveness gates that share the same identity-only filter.

**Default taken:** fold in. The floor lives inside the two shared readers
(`_flip_liveness_count`, `_luks_liveness_count`), so all three gates get it, and no call site
changes.

**Why:**

- `_flip_liveness_count` is one reader with two callers. Scoping the fix to one caller would make
  it mean two things.
- LUKS G3 has the same stranding shape as resume.
- For op=arm G3.7, H exists to make an L = 0 absence meaningful. A replacement that flipped while
  its Vector was down leaves L = 0 and an unfloored H counting the predecessor's rows. The result
  is `clear`, which is the #7674 fail-open reopened by a replace.
- Narrowing a count can only ADD refusals.

**Dissent (DHH):** leave arm H unfloored, for parity with the unfloored L. Both are about the same
surviving volume, and flooring H adds a Hetzner dependency to op=arm with no incident behind it.
The plan's rebuttal: the two signals answer different questions. L counts presence evidence,
which any server's rows supply. H must prove the server that could have flushed unseen is
audible, and only the current server can do that.

**Cost of the default:** op=arm and op=luks-* now refuse, fail-closed, during a Hetzner API outage.
They are rare, reviewer-gated dispatches, and the refusal's `::warning::` says re-dispatch is safe.

**To reverse:** have arm's G3.7 read an unfloored count. That needs a separate reader, or a flag
parameter on `_flip_liveness_count`.
