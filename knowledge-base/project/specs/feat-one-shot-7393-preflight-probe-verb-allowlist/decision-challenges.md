# Decision Challenges — feat-one-shot-7393-preflight-probe-verb-allowlist

Recorded headless during `/soleur:plan` (ADR-084). Each item is a challenge to the
operator's stated direction, surfaced rather than silently applied. `ship` renders these
into the PR body and files them as an `action-required` issue.

## DC-1 — Split into two PRs? (Taste / User-Challenge)

**Operator's stated direction (the default):** issue #7393 names *both* halves of the fix —
the probe-verb allowlist **and** a sanctioned path for credentialed probes — and the pipeline
brief says "plan BOTH", with the deliverable being "a merged PR that closes #7393".

**The challenge (code-simplicity-reviewer, P-high):** the actual security vulnerability is
closed entirely by one line — `HOME="$HOME"` → `HOME="$(mktemp -d)"` in Step 10.5. Everything
else is a *quality* change to an advisory local check, riding in the same PR as a security fix
and delaying it behind a substantial test rewrite and four hand-synced schema surfaces. The
reviewer recommends PR-1 (ephemeral `$HOME` + ADR + C4) shipped immediately, PR-2 (allowlist +
declaration field) after.

**Why the plan declines it:** splitting leaves #7393 open, which contradicts the explicit
deliverable. More substantively, shipping Layer 1 alone would make every currently-declared
credentialed probe fail with an *opaque* credential error and no declared path to a legible
SKIP — a worse operator experience than today's explicit FAIL. The two halves are
complementary: Layer 1 removes the authority, Layer 3 gives the honest probes somewhere to go.

**Cost of the decision:** the security-relevant one-line change merges on the same timeline as
the larger quality change, so it lands later than it strictly had to.

**If the operator disagrees:** the split is cheap to execute — Layer 1 is self-contained in
Step 10.5 and its two Sharp Edges, with no dependency on the allowlist or the schema field.
