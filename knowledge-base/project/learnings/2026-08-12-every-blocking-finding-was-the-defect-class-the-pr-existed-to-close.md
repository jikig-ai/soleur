---
module: Legal Corpus
date: 2026-08-12
problem_type: logic_error
component: documentation
symptoms:
  - "PR fixing a legal-doc 404 shipped three new 404s on the published mirror; every gate stayed green"
  - "A correction landed in prose while the machine-readable field asserting the same claim kept the old value"
  - "A guard's own fail-closed branch was unreachable under set -e"
root_cause: incomplete_propagation
severity: high
tags: [legal-corpus, mirror-drift, set-e, propagation, gates, second-order-defects]
related_issues: [7349, 7465, 7477, 7478, 7479, 7486]
synced_to: [review, work]
---

# Every blocking finding was the defect class the PR existed to close

## Problem

PR #7349 consolidated eleven legal-corpus defects: guards that could not fire, contradictions
between documents, stale records, and mirror divergence between the internal record
(`docs/legal/`) and the published surface (`plugins/soleur/docs/pages/legal/`, served at
soleur.ai/legal/).

Review returned six findings. **Every blocking one was a second-order instance of the exact
defect class the PR existed to close.** Not a coincidence of a bad session — a structural
property of how the fixes were made, worth naming because the same shape will recur on any
PR whose subject is "make two representations of one fact agree."

## The six, and what each one teaches

### 1. Fixed one 404, shipped three (the headline case)

The PR's user-facing bullet was "we fixed a legal-doc 404". It introduced **three new ones**
on the *more public* surface. `main` had zero relative `.md` links on those published pages;
HEAD had three, all created by this PR's port work.

Both link forms are correct — in their own place:

| Surface | Correct form | Why |
|---|---|---|
| `docs/legal/*.md` | `](gdpr-policy.md)` | read on GitHub, where the relative path resolves |
| `plugins/soleur/docs/pages/legal/*.md` | `](/legal/gdpr-policy/)` | served at `/legal/<slug>/`, where a relative `.md` resolves *under that route* and 404s |

The port copied canonical text verbatim, which carried the canonical link form onto a surface
where it is broken.

**Why no gate saw it.** `scripts/lib/legal-normalise.sh` deliberately collapses
`(gdpr-policy.md)` and `(/legal/gdpr-policy/)` to the same `LINK_GDPR` token. That is *correct*
for body equivalence — the two say the same thing about content — and it is exactly what makes
the drift check structurally blind to link **form**. The normalisation that makes one check
sound is what blinds it to a different failure mode on the same bytes.

Fixed, and added an independent published-link-form check to the same gate, verified to red on
the tree as it stood before the fix.

> **Generalisable:** when a gate normalises away a dimension to compare a different one, ask
> what *else* lived in the normalised dimension. That is a blind spot with a precise shape, and
> you can enumerate it.

### 2. The product was more honest than the policy

Published privacy-policy §8.1 stated the self-serve DSAR route unconditionally. The client only
ever sends `mode:"password"`; the in-app dialog already told users that SSO-only accounts must
email the legal address for manual fulfilment. So an SSO-only user could not complete step 1 of
their own Art. 15 request, and the newly published policy did not say so — while the running
product did.

**Generalisable:** when publishing a fulfilment route, diff the promise against the UI that
implements it. The UI's own caveats are a free specification of the preconditions.

### 3. "Propagated" was asserted, not measured

The beta-CRM LIA's prose was corrected to name Jikigai as controller. Three sites kept the
superseded position: the YAML `controller:` frontmatter **fifteen lines above** the correcting
paragraph, the operative balancing conclusion, and a sibling LIA that cited the old posture as
its own contrast case.

The counsel audit had already recorded that propagation as **DISCHARGED**.

A superseded claim survives exactly where prose review does not look: machine-readable
frontmatter, an operative conclusion far from the edit, and a *different* document that cites
the old position. A corrected document containing an uncorrected field clears both the gates
and the review.

**Generalisable:** "propagated" is a measurement over every site asserting the claim, not an
observation about the site you edited. Grep for the old claim, not the new one.

### 4. A guard whose fail-closed branch was dead code

The guard added to stop a stale version row from passing silently captured a `grep` whose
non-zero exit is a normal answer, under `set -e`:

```bash
# WRONG — under set -e the script dies on "no match", so the error below never runs
POSTURE_VERSION=$(grep -oE '...' "$REGISTER" | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
if [ -z "$POSTURE_VERSION" ]; then
  echo "::error::no parseable version cell" >&2   # UNREACHABLE
```

```bash
# RIGHT
POSTURE_VERSION=$(grep -oE '...' "$REGISTER" | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
```

This is not merely "a spurious death risk". The guard would have died **in the one case it was
written for** — an unparseable cell — so its refusal path was decorative. The repo's own
`lint-shell-capture-exit` caught it; second time the same trap bit this PR.

**Generalisable:** after writing a fail-closed branch, mutate the input to reach it. A refusal
path that has never executed is a claim, not a guard.

### 5. The ratchet's mechanical remedy was also the correct legal fix

The per-activity lawful-basis fix edited a line on both surfaces identically — but that line was
**already positionally drifting**: canonical ended with the exercise-channel marker
`Email channel.` and the published page did not. Editing an already-drifting line in place is
precisely the shape the mirror ratchet forbids, and it is the one shape that an identical edit
to both surfaces does not repair.

The gate's prescribed remedy — *port the enclosing passage, which reduces drift and always
passes* — turned out to be the right answer legally too: the published §5.3 rights bullets
lacked every channel marker canonical carried (`Email channel.`, `Self-serve at …`), so a data
subject was told a right existed but not how to exercise it.

Deliberately **not** ported: the rest of that section's gap (the whole Art. 15(4) redaction
disclosure is absent from the published page). That is #7465's tracked scope with a 2026-09-30
target. The ratchet exists to keep crossing into it a deliberate act, not a side effect.

**Generalisable:** a drift ratchet's "reduce drift instead" remedy is often the substantive fix
in disguise, because pre-existing drift on a *published* surface usually means the public copy
is the impoverished one.

### 6. A count labelled "re-derived from the live API" that matched nothing

`roadmap.md` carried `88 open, 207 closed (milestone; re-derived from the live API 2026-08-11)`.
Re-deriving returned **0** — the query named `Phase 4 (Validate + Scale)` while the milestone is
`Phase 4: Validate + Scale`. It had matched nothing and returned a stale figure wearing a
freshness label. Two further re-derivations minutes apart disagreed with each other (1024/1554,
then 1023/1555) and with the milestone API (1024/1561).

Rather than write a fourth number false by merge time, applied the contradiction register's own
E9 remedy — *"A fixed count in a versioned instrument is false the day the next agent lands"* —
which the roadmap had exempted itself from: cite the derivation command, do not freeze the count.

**Generalisable:** a provenance label ("re-derived from the live API") is not evidence. Re-run
the command. A query that silently matches nothing is worse than no query, because the zero
gets written down as a measurement.

## Session Errors

**Planning subagent stalled ~19 min in with nothing persisted to disk** (forwarded from
session-state). Recovery: resumed the subagent's live context and made it write the plan file
before further fan-out. **Prevention:** `soleur:plan` completes its whole Phase 1 research
fan-out before its first write — filed as #7418.

**First plan draft carried four false claims inherited from the issue body** plus two
unshippable acceptance criteria (forwarded). Recovery: CLO review caught all six; reversals
recorded in the plan rather than silently absorbed. **Prevention:** treat an issue body's
factual claims as premises to verify, never as findings — already the CLO gate's job, and it
worked.

**A hook blocked one edit on manual-infrastructure phrasing** (forwarded). Recovery: Phase 2.8
genuinely did not apply; recorded the sanctioned `iac-routing-ack` with written justification.
**Prevention:** none needed — recording the ack rather than rephrasing to evade the check is
the intended path.

**A `sed` written to test the link gate rewrote a *correct* link as collateral.** The gate
caught it (it reported two sites where I expected one). **Prevention:** never mutate the live
tree to test a gate — copy to a sandbox and mutate there.

**A `git checkout <file>` to undo that mutation reverted three unrelated edits** made earlier in
the same session to the same file. Recovery: re-applied all three. **Prevention:** same rule —
sandbox mutations never require an undo against the working tree.

**The `set -e` capture trap bit twice in one PR** (the guard suite earlier, then the
compliance-posture guard). **Prevention:** `x=$(cmd) || true` whenever a non-zero exit is a
normal answer; `lint-shell-capture-exit` enforces it, and both instances were caught by it
rather than by me.

**Filing #7486 was blocked by a hook matching a CC-memory path *quoted as evidence* in the
issue body.** Recovery: redacted the literal paths and filed via `--body-file`. **Prevention:**
the guard reads a payload with no notion of citation-versus-write; noted inside #7486 itself,
alongside the fix direction for the same class.

**22 of 41 hook test suites write fixture denials into the operator's real incident log** —
found while reading `.rule-incidents.jsonl` for this compound's own Deviation Analyst step.
1,149 deny/bypass rows since session start, overwhelmingly fixtures. Corrupts both the
Deviation Analyst's evidence and `rules_unused_over_8w` (a rule exercised only by its own test
registers as used). Filed #7486. **Prevention:** make the emitter fail-safe rather than
opt-in — 22 of 41 opting out is the signature of a default pointed the wrong way.

## The pattern worth keeping

Every one of these is the same shape: **a fix applied at the site you were looking at, while the
same claim lived somewhere you were not.**

- the link form lived on a second surface
- the precondition lived in the UI
- the controllership lived in frontmatter
- the refusal branch lived behind a `set -e` exit
- the channel marker lived only in the record, not the publication
- the count lived behind a query that matched nothing

Gates caught five of six. That is the argument for having built them — and not a flattering
observation about the review passes that preceded them.
