---
title: "A Checklist for Trusting AI Work Was Just Published. We Shipped All of It."
type: pillar
publish_date: 2026-10-24
channels: discord, x, bluesky, linkedin-personal
status: published
issue_reference: "#10902"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
A checklist for trusting AI work was just published by one of the most-read voices in engineering.

We shipped all of it in four days.

The interesting part isn't the speed. It's what the reviews found wrong with the verifiers.

**Tweet 2:**
2/ The checklist is Addy Osmani's agentic-verification essay: property tests that generate thousands of inputs, a maintained feature map, old-vs-new differential testing, flake quarantine, installable guardrails.

Every row: shipped.

**Tweet 3:**
3/ The first property test we ever ran caught a real bug on day one — a utility that cleans up web addresses could leave an invisible trailing space, so cleaning twice changed the answer. No human would have picked that input. A generator found it instantly.

**Tweet 4:**
4/ The feature map covers 32 screens and fails the build if map and product disagree. Review found 4 defects in the guard itself — including a counter that silently missed the homepage. A check that under-counts looks green forever.

**Tweet 5:**
5/ The guide teaching the practice had its own worked example flagged by three reviewers: it was written so every possible answer passed — including a wrong one. An example that can't fail teaches a practice that can't catch anything.

**Tweet 6:**
6/ The flake-quarantine rule's "all clear" row could fire on a run with zero readable results — nothing quarantined, read as green. The success row proved nothing. Review caught it before it shipped.

**Tweet 7:**
7/ The checklist is table stakes. The deeper row is underneath it: verification machinery needs verification. A check that cannot fail is worse than no check — it converts "unverified" into "verified-looking."

**Tweet 8:**
8/ We audited all 102 of our own automated checks. Four were generic enough to belong in any repo — each proven to catch a real violation before it's allowed to activate. A guard that can't be proven to fire is a document, not a guard.

**Tweet 9:**
9/ Full build log — every defect the reviews caught in the verifiers, every fix:

https://soleur.ai/blog/agentic-verification-checklist-shipped/?utm_source=x&utm_medium=social&utm_campaign=agentic-verification-checklist-shipped

#buildinpublic

---

## Bluesky

A checklist for trusting AI work was just published. We shipped all of it in four days — and the reviews found real bugs in the verifiers themselves.

Build log, defects and all: https://soleur.ai/blog/agentic-verification-checklist-shipped/

---

## Discord

**A checklist for trusting AI work was just published. We shipped all of it in four days.**

Addy Osmani's agentic-verification checklist — property-based testing, a maintained feature map, differential testing for migrations, flake quarantine, reusable guardrails — is now live in our codebase and in the workflows Soleur ships.

The part worth reading isn't the speed. It's what review caught inside the verifiers:
→ the first property test found a real bug on day one
→ the feature-map guard had 4 defects — including a counter that silently missed the homepage
→ the teaching example could never fail — a wrong answer passed it
→ the flake rule's "all clear" could fire on zero readable results
→ of 102 automated checks audited, exactly 4 were portable — each proven to fire before it activates

The checklist is table stakes. Verification machinery needs verification.

Full post: https://soleur.ai/blog/agentic-verification-checklist-shipped/?utm_source=discord&utm_medium=community&utm_campaign=agentic-verification-checklist-shipped

---

## LinkedIn Personal

A checklist for trusting AI work was just published. We shipped all of it in four days — and the reviews found real bugs in the verifiers.

Addy Osmani's agentic-verification essay is the clearest answer I've seen to the question every founder asks about AI: "what if it's wrong?" Property-based testing. A maintained feature map. Old-versus-new differential testing. Flake quarantine. Guardrails you can install.

I measured Soleur against every row and we shipped the missing pieces — seven changes across our own codebase and the workflows our users get.

The humbling part: nearly every verifier arrived with a defect in the verifier. The feature-map guard silently missed the homepage. The teaching guide's own example could never fail. The flake rule's "all clear" could fire on a run with nothing to read. Reviewers caught every one before a single user saw them.

The checklist is table stakes. Trustworthy AI needs verification machinery that was itself verified. You stay the decision-maker; the system shows its work.

The full build log — every defect named, every fix shown: https://soleur.ai/blog/agentic-verification-checklist-shipped/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=agentic-verification-checklist-shipped

#buildinpublic #AIagents
