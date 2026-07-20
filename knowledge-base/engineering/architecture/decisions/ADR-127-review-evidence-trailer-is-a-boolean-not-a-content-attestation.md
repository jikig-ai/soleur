---
title: "Review-evidence trailer is a boolean, not a content attestation"
status: accepted
date: 2026-07-20
issue: 6724
supersedes: null
---

# ADR-127: the review-evidence trailer is a boolean, not a content attestation

## Context

Issue #6724: the pre-merge review-evidence gate was structurally incapable of
denying. Check 1 was a repo-global `grep -rl "code-review" todos/`, and `todos/`
is a tracked directory that lives on `main` — so one long-lived review todo
satisfied the gate for every branch, forever, including branches where review
had never run.

Branch-scoping that check exposed a second defect: a review that finds nothing
produces no artifacts and no commit (review/SKILL.md explicitly says to skip the
artifact commit when there are no local changes), so the cleanest branches would
have been denied with no escape hatch. PR #6727 closes that with a new
primitive, `plugins/soleur/skills/review/scripts/emit-review-trailer.sh`, which
commits `--allow-empty` carrying a `Reviewed-By-Soleur:` trailer.

Post-implementation review then demonstrated that the trailer is satisfiable
without the merged content having been reviewed: run `/review` on a one-line
branch, then push arbitrary further commits — the trailer is still in
`origin/main..HEAD` and the gate passes. That is a real gap between what the
primitive does and what the PR's framing ("make the gate capable of denying")
implies. It needed a decision rather than a silent default, because three
consumers read the key and it lands permanently in `main`'s squash-merged
history.

## Decision

**`Reviewed-By-Soleur:` is a BOOLEAN — "a review ran on this branch". It is NOT
an attestation that the merged tree is the reviewed tree.** This is deliberate
and documented rather than an unowned gap.

`Reviewed-Commit: <sha>` is emitted alongside it, recording the sha under review.
**No consumer reads it.**

Consequences of that split are stated in the script header and in
`plugins/soleur/skills/ship/SKILL.md`, and the PR's overclaiming language was
corrected: the gate went from *structurally incapable of denying* to *capable of
denying*, which is the whole of what #6724 required. It did not become
unfalsifiable, and nothing shipping says it did.

## Rejected alternatives

**Content-bind and enforce (`Reviewed-Commit` compared against `HEAD`, deny on
drift).** Rejected on two grounds.

The decisive one: it closes nothing as scoped. The gate is a three-signal **OR**
and every leg is a boolean. The legacy `review: ` subject pattern is checked
*before* the trailer, so content-binding the trailer leaves the demonstrated
bypass working verbatim as `git commit --allow-empty -m "review: x"`. Signal 1
is a boolean over the branch diff; Signal 3 (a `code-review`-labelled issue
citing the PR) is a boolean over remote state that cannot be bound to a tree at
all. Making the binding mean anything requires deleting both legacy patterns —
stranding every branch reviewed before this shipped — and re-architecting
Signal 3 to carry a sha.

The second: cost. Enforcement puts a re-review treadmill on a gate that already
denies 17 of 18 currently-open PRs (measured; see the PR's
`mutation-evidence.md` §AC18). Gates that block constantly get bypassed — that
is precisely how #6724 came to exist.

**Keep the boolean and change nothing.** Rejected. The mechanism is right; the
shipped framing was false. Leaving "structurally unfailable" in `main`'s history
means the next reader reasons from a wrong premise about what the gate
guarantees. Zero work is not zero cost when the artifact misdescribes itself.

## Consequences

- The gate guards against **a review never having run**. It does not guard
  against review running early and unreviewed commits landing after.
- These hooks live in the operator's own checkout and are editable by the same
  agent they constrain, so there is no enforcement boundary to build on. The
  threat model is agent forgetfulness on a trusted single-operator repo, and a
  boolean is the honest instrument for it. The trailer is a compliance aid, not
  a security control.
- `Reviewed-Commit:` gives the forensic data now, at near-zero cost. Adding a
  field once the key is in permanent history and read by three consumers is the
  expensive part; enforcing a field already present is cheap. It also allows
  measuring real post-review drift instead of guessing whether enforcement was
  ever warranted.
- Trailer parsing is key-scoped (`%(trailers:key=...)`), so the extra line
  breaks no existing consumer.

**Revisit trigger:** if the threat model changes to untrusted committers —
external contributors merging without operator review — content-binding becomes
necessary, and `Reviewed-Commit:` will already be present to build on. Revisiting
also requires addressing the other two OR legs; binding the trailer alone will
still close nothing.

## References

- Issue #6724, PR #6727
- `plugins/soleur/skills/review/scripts/emit-review-trailer.sh` (producer)
- `.claude/hooks/pre-merge-rebase.sh`, `.openhands/hooks/pre-merge-rebase.sh`,
  `plugins/soleur/skills/ship/SKILL.md` (consumers)
- ADR-015 (decoupled work/ship for review gates) — same domain, prior art
