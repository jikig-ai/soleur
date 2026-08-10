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

### Addendum — 2026-08-10 (#7393, at `/work`): DC-1's central premise was falsified

Appended rather than edited — the record above is what the challenge actually said, and
destroying it would destroy the evidence for why the split looked attractive.

DC-1 rests on "the actual security vulnerability is closed entirely by one line —
`HOME="$HOME"` → `HOME="$(mktemp -d)"`". **That is false**, and the plan's own v1 → v2
revision is what established it: an ephemeral `$HOME` changes where a CLI *looks*, not what
is *readable*. Measured, an absolute-path read returns the live 294-byte Doppler token
regardless of `$HOME`, as does a `/home/*/…` glob, as does `awk 'BEGIN{system(…)}'`.

So the "ship the one-line security fix immediately" arm of the recommended split would have
shipped **no security fix at all** — it would have shipped a control that reads as one. The
decision to decline the split is unchanged, but the reasoning above understates it: the
split was not merely inconvenient, its fast arm was empty.

What survives from DC-1 is the cost note, and it now points the other way: the real
security-relevant change (the bwrap boundary) is *not* one line and could not have shipped
ahead of the rest on the timeline the challenge assumed.
