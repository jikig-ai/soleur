---
title: "I measured the right thing on the wrong instance"
date: 2026-09-08
category: workflow-patterns
module: knowledge-base/legal
issue: 7797
pr: 7944
tags: [instruments, verification, secrets, corrections, evidence]
---

## Problem

A P0 credential exposure sat un-remediated for four days behind a blocking gate,
and the gate was built on a field that does not exist.

The remediation sequence read: *capture the token's last-used timestamp before
deleting it, because deletion destroys the datum.* Everything downstream was
ordered around that. It was written into a post-mortem, into a signed CLO
determination, and into the canonical Art. 33(5) breach register.

Measured on 2026-09-08, in about ninety seconds once anyone looked: **Sentry
exposes no last-used field for personal tokens on any surface reachable to us** —
not the token list, not the per-token Edit view, not `GET /api/0/api-tokens/`
under session auth. The constraint could never have been satisfied. The
credential stayed live roughly 4 days 19 hours.

Worse, the determination carried a *self-criticism* about that field: that a
liveness probe had "already overwritten the scalar with a controller use — a
real, self-inflicted degradation of the instrument". A mea culpa, written into a
signed legal record, about damage to something that was never there.

## Root cause

Every one of these was an assertion about a **property of a named thing** — a
field, a credential, an endpoint, a document — made without addressing that
thing.

That is not a new lesson. `scripts/sentry-issue.sh` already carries the correct
form one function above one of the wrong ones: *"NOTE: SENTRY_AUTH_TOKEN also
reads this endpoint (measured 200, 2026-09-03)"*. The rule existed. What this
session adds is the discovery that **the corrections repeat the defect**, and
that they repeat it in a specific, predictable way.

## The shape that actually bites: a true measurement on the wrong subject

The most instructive failure was not a missing measurement. It was a real one,
correctly performed, attached to the wrong instance.

Correcting the incident record, I found `postmerge/SKILL.md` claiming
`SENTRY_AUTH_TOKEN` is read-only and `403`s on the single-issue endpoint. I
measured: **200**. I called the skill false, edited it, and wrote a fallback into
the pipeline.

`SENTRY_AUTH_TOKEN` names **two different tokens**:

| Doppler location | Result |
|---|---|
| `soleur/prd` — what that phase actually resolves | **403** |
| `soleur/prd_terraform` — the leaked personal token | **200** |

The skill was right about the credential it reads. I measured the other one. Had
it shipped, the phase would have 403'd in production — a correction that breaks
the thing it corrects.

The post-mortem I was editing at that moment warns about exactly this collision,
and says conflating the two "would send the operator to rotate an uninvolved
credential". I had the warning open and still generalised across the boundary.

**A measurement is evidence about the instance you addressed, not about the name
you used to reach it.** Where one name resolves differently by environment,
config, or account, the name is not the subject — the resolved instance is.

## Three corrections of my own, in one incident

1. Claimed the post-mortem and the determination both characterise the token as
   "read-scoped". Both say "org read **and write**", and the determination
   engages the integrity limb on it. Asserted from the shape of the documents
   without reading their capability rows.
2. Named `postmerge/SKILL.md` as "the genuinely false site" and edited it. The
   credential-boundary error above.
3. Corrected the prose of that skill while leaving the code below it enacting the
   claim I had just called false — prose and script disagreeing inside one file,
   in a PR whose subject is claims that do not match reality.

Each was made while explicitly trying to be careful, immediately after
documenting the same failure class.

## The instrument that consumed its own evidence

A second, quieter instance: to check whether a page had advanced past a login
step, I took accessibility snapshots of it. Playwright's snapshot **includes
input field values**, and a password manager had auto-filled the password field.
The value went into the transcript.

A screenshot renders that field as dots. The accessibility tree is the leaky
surface, and it is the one you reach for by default because it is cheaper and
more precise. Nothing about "snapshot the page" looks credential-adjacent.

Same shape as the rest: I used an instrument without asking what it renders.
Filed as #7947.

## Key insight

The failures were not carelessness about *whether* to verify. In every case
something **was** measured, read, or documented. The defect was in what the
measurement was attached to:

- a constraint attached to a field nobody had addressed;
- a self-criticism attached to damage to that field;
- a capability attached to a name that resolves to two different credentials;
- a correction attached to prose while the code went unchanged;
- a page-state check attached to a tool whose output surface nobody had asked
  about.

So the operative question is not *"did I verify this?"* — the answer kept being
yes. It is **"what exact instance did I address, and is that the instance the
claim is about?"**

The tell is a claim whose subject is a *name*: an env var, a field, an endpoint,
a document. Names resolve. Resolve them before asserting about them.

## Prevention

- **When a plan is BLOCKED on capturing a datum, address the datum before
  accepting the block.** A gate that cannot be satisfied is worse than no gate:
  it holds remediation and looks like diligence. Cost here: ~4d19h of live
  exposure.
- **A correction must name the exact instance measured and the command that
  measured it.** "Measured 200" is not evidence; "`soleur/prd_terraform`,
  `GET /organizations/<org>/issues/<id>/`, 200, 2026-09-08" is. If the claim is
  about a variable name that resolves per environment, the config is part of the
  claim.
- **After correcting prose, grep the file for the code that enacts it.** Prose
  and script disagreeing inside one file is invisible to every gate.
- **Before using an instrument on a sensitive surface, ask what it renders.** For
  browser automation specifically: never take an accessibility snapshot of a page
  with a password input — screenshot instead.
- **Never write a self-criticism about a thing you have not verified exists.** It
  reads as rigour, it is quoted downstream as established, and it is harder to
  withdraw from a signed record than a plain error would have been.

## Session Errors

- **Accepted a four-day blocking gate without addressing its instrument.**
  Nobody, across three documents and several sessions, checked that the
  last-used field existed. **Prevention:** when a step is marked BLOCKING on
  capturing a datum, the first action is to look at the datum; if it cannot be
  addressed, the gate is void and remediation proceeds.
- **Wrote a self-criticism into a signed legal record about a nonexistent
  field.** **Prevention:** a mea culpa is a factual claim; verify its subject
  exists before entering it, and never in a record that others will quote.
- **Asserted what two documents said without reading the relevant rows.**
  **Prevention:** quote the line, or do not characterise the document. A claim
  about a file's contents must carry the fragment it rests on.
- **Measured a capability on `prd_terraform` and asserted it about `prd`.**
  Would have shipped a 403 into the pipeline. **Prevention:** the resolved
  instance is the subject; name the config in the claim.
- **Corrected prose and left the code enacting the withdrawn claim.**
  **Prevention:** after editing a claim in a file that also contains executable
  steps, grep that file for the behaviour and reconcile both in one edit.
- **Swept for the corrected claim once, believed it done, and a subject-grep
  found a third site.** The canonical breach register — higher authority than
  either file I had edited — still asserted four withdrawn things.
  **Prevention:** sweep by the claim's SUBJECT across the whole repo, and check
  the highest-authority surface first rather than the file you happen to have
  open.
- **Rendered a password into the transcript by snapshotting a login page.**
  **Prevention:** screenshot, never accessibility-snapshot, any page carrying a
  password input. Tracked as #7947.
- **Reported a push as successful when it had not happened** — the exit code came
  from a `grep` that filtered the output away, not from the push.
  **Prevention:** never read a pipeline's exit status as the first command's;
  verify the state directly (`git rev-list @{u}..HEAD --count`), not the rc.

## Related

- [the post-mortem this session corrected](../../engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md)
- [the CLO determination and its 2026-09-08 addendum](../../legal/audits/2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md)
- [i wrote the next action down and treated that as doing it](2026-09-07-i-wrote-the-next-action-down-and-treated-that-as-doing-it.md)
  — the same session's predecessor. That one is about a stated action never
  taken; this one is about an action taken against the wrong subject.
- [every check i shipped was narrower than the name it carried](2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried.md)
