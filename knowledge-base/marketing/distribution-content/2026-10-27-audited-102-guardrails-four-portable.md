---
title: "We Audited 102 Guardrails. Only Four Belong in Every Repository."
type: pillar
publish_date: 2026-10-29
channels: x, bluesky, discord, linkedin-personal
status: scheduled
issue_reference: "#10903"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
We audited all 102 automated safety checks on our own codebase before shipping any of them into yours.

Only four belonged in every repository.

Here's the honest count — and the one question worth asking about every check you rely on.

**Tweet 2:**
2/ The corpus: 102 checks in two families. 56 tripwires that fire the moment work is about to be saved, and 46 sweeps that read the whole repo and flag drift. Each got a verdict: portable, portable after repackaging, or welded to our machinery.

**Tweet 3:**
3/ The honest count:

Tripwires (56): 0 portable, 10 repackagable, 46 welded
Sweeps (46): 9 portable, 8 repackagable, 29 welded

Of the checks guarding the exact moment work gets saved, not one was portable as it stood.

**Tweet 4:**
4/ Why so few? A check earns its place by knowing the codebase it guards — your rules, your file layout, your vendors. That knowledge is exactly what doesn't transfer. The reusable fraction of a mature safety practice is startlingly small.

**Tweet 5:**
5/ The four that shipped: a secrets scan before work saves, a check that work never lands on the main line, a check against shelving unfinished work forever, and a check that a test suite nothing runs can't pass silently.

**Tweet 6:**
6/ Each arrives advisory — warns, doesn't block — and installs only after a rehearsal on a throwaway copy of your repo proves it catches a planted violation, then goes quiet once it's removed. A guard that can't be proven to fire is a document, not a guard.

**Tweet 7:**
7/ And the checks had defects too — review found an edge case that could wave everything through, a log that erased its own evidence, and a report that claimed cleanup it never did. Verification machinery needs verification.

**Tweet 8:**
8/ The full count — every check named, every verdict explained:

https://soleur.ai/blog/audited-102-guardrails-four-portable/?utm_source=x&utm_medium=social&utm_campaign=audited-102-guardrails-four-portable

#buildinpublic

---

## Bluesky

We audited all 102 automated safety checks on our own codebase. Only four belonged in every repository — and each had to prove it catches a real violation before it was allowed to activate.

The honest count: https://soleur.ai/blog/audited-102-guardrails-four-portable/

---

## Discord

**We audited 102 guardrails. Only four belong in every repository.**

Before shipping safety checks into user repositories, we classified every check in our own corpus: 56 that fire the moment work is about to be saved, 46 that sweep the whole repo.

→ Of the 56 before-save checks, zero were portable as they stood; of the 46 sweeps, nine were
→ Exactly four shipped: a secrets scan, main-line protection, a check against forgotten shelved work, and a check that an empty test suite can't pass silently
→ Every check installs advisory-first, and must catch a planted violation on a throwaway copy of your repo before it activates
→ Review found real defects in the guards themselves — all filed and fixed before release

A guard that can't be proven to fire is a document, not a guard.

Full post: https://soleur.ai/blog/audited-102-guardrails-four-portable/?utm_source=discord&utm_medium=community&utm_campaign=audited-102-guardrails-four-portable

---

## LinkedIn Personal

We audited all 102 automated safety checks on our own codebase. Only four belonged in every repository.

Before shipping guardrails into the repositories our users work in, we asked the uncomfortable question of ourselves: how much of our own safety corpus is actually portable? The answer required grading every check — 56 tripwires that fire before work is saved, 46 repo-wide sweeps — as portable, repackagable, or welded to our machinery.

The honest count: zero of the 56 before-save checks were portable as they stood. Nine of the 46 sweeps were. A check earns its place by knowing the codebase it guards, and that knowledge is exactly what doesn't transfer.

The four that shipped each had to prove themselves first: a rehearsal on a throwaway copy of the repository must catch a planted violation, then go quiet when it's removed. And the review found real defects in the verification machinery itself — every one filed and fixed before release.

A guard that can't be proven to fire is a document, not a guard.

The full audit: https://soleur.ai/blog/audited-102-guardrails-four-portable/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=audited-102-guardrails-four-portable

#buildinpublic #AIagents
