---
title: "A Property Test That Cannot Fail Teaches Nothing"
type: pillar
publish_date:
channels: x, bluesky, discord, linkedin-personal
status: draft
issue_reference: "#10904"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
We taught our AI to test rules instead of examples — then reviewers caught that the guide teaching it contained a worked example that could never fail.

Here's the two-round post-mortem.

**Tweet 2:**
2/ A property test states a rule that must always hold — "running this twice changes nothing the second time" — and a generator throws thousands of random inputs at it trying to break it. The practice caught a real bug on day one.

**Tweet 3:**
3/ To hand the practice to our users' workflows we wrote a guide with a worked example. Three reviewers independently flagged it: the example's "test" passed every possible answer — including a completely wrong one.

**Tweet 4:**
4/ An example that cannot fail teaches a practice that cannot catch anything. Worse: in a guide it reads as endorsement — "this is how we do it."

**Tweet 5:**
5/ Removing the tautology was not enough. The fixed example checked "same items out as went in" and "running it twice changes nothing" — both also true of a program that returns its input untouched. A do-nothing program still passed.

**Tweet 6:**
6/ Only a third rule closed it: the output must actually be in order. A check isn't cleansed by removing the obviously broken assertion — it's sound only when nothing lazy survives it.

**Tweet 7:**
7/ The review found the same disease twice more: a check whose expected answer came from the machinery under test (consistently wrong passes on both sides), and tool claims nobody had verified — now labelled unverified.

**Tweet 8:**
8/ Guidance you hand an AI is graded like code — an example executes in the reader's head. The full post-mortem:

https://soleur.ai/blog/property-test-cannot-fail-teaches-nothing/?utm_source=x&utm_medium=social&utm_campaign=property-test-cannot-fail-teaches-nothing

#buildinpublic

---

## Bluesky

We taught our AI to test rules instead of examples — then reviewers caught that the guide's own worked example could never fail. The first fix still let a do-nothing program pass; only a third rule closed it.

The post-mortem: https://soleur.ai/blog/property-test-cannot-fail-teaches-nothing/

---

## Discord

**A property test that cannot fail teaches nothing.**

We shipped a guide teaching property-based testing to our users' workflows — and the review panel's sharpest finding was about the guide itself:

→ The worked example's "test" passed every possible answer, including a completely wrong one — three reviewers flagged it independently
→ The first fix still admitted a do-nothing program: "same items out as went in" and "running it twice changes nothing" are both true of returning the input untouched
→ Only a third rule — the output must actually be in order — closed it
→ The same disease twice more: an expected answer produced by the machinery under test, and tool claims nobody had verified (now labelled unverified)

Guidance handed to an AI is graded like code. An example executes in the reader's head — a vacuous one is a defect in the teaching, not a typo.

Full post: https://soleur.ai/blog/property-test-cannot-fail-teaches-nothing/?utm_source=discord&utm_medium=community&utm_campaign=property-test-cannot-fail-teaches-nothing

---

## LinkedIn Personal

We taught the AI in our workflows property testing — state a rule that must always hold, and a generator throws thousands of random inputs at it trying to break it. The practice earned its place immediately: the first rule it ran caught a real bug on day one.

Then the teaching failed. The guide we wrote to hand that practice to our users' workflows carried a worked example that could never fail — written so every possible answer, including a completely wrong one, would pass it. Three reviewers caught it independently.

The fix needed a second round. "Same items out as went in" and "running it twice changes nothing" are both true of a program that returns its input untouched — a do-nothing program still passed. Only a third rule, "the output must actually be in order," closed the example to trivial implementations.

The lesson generalizes past testing: instructions you hand to an AI are graded like code. A worked example executes in the reader's head, and whatever it permits becomes the practice it teaches. Ask of any check or example: what would make this fail?

The full post-mortem: https://soleur.ai/blog/property-test-cannot-fail-teaches-nothing/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=property-test-cannot-fail-teaches-nothing

#buildinpublic #AIagents
