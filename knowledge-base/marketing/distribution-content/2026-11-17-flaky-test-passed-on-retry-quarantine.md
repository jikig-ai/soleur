---
title: "A Flaky Test Passed on Retry and the Loop Called It Fixed"
type: pillar
publish_date:
channels: x, bluesky, discord, linkedin-personal
status: draft
issue_reference: "#10739"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
A flaky test passed on retry — and our fix loop called it fixed. So we taught it the opposite: a pass on retry is a flake signature, not a fix.

Here's the quarantine protocol we shipped.

**Tweet 2:**
2/ Every newly failed check now gets exactly one isolated re-run on the unchanged work. Pass there and it's quarantined — never counted as fixed, never allowed to spend fix budget.

**Tweet 3:**
3/ Three acts per quarantined flake: pulled off the failure list, a tracker ticket filed (deduped on a marker inside the ticket, not a title search), and named in the final report — never a bare green.

**Tweet 4:**
4/ Review caught the machinery lying twice. The "all failures were flakes" row could fire on a run with no readable results — zero quarantines read as green. Now it requires at least one real quarantine.

**Tweet 5:**
5/ And a warning flag whose trigger was empty by construction — it compared the flaked check's file against files the loop never edits. Decoration that reads as coverage, re-specified on signals that can actually fire.

**Tweet 6:**
6/ The root-cause checklist is six axes any suite can be audited against: seeds, clocks, network, state isolation, output terseness, contention.

**Tweet 7:**
7/ A pass on retry is not a pass — it's a flake asking to be quarantined, tracked, and fixed properly. Full story:

https://soleur.ai/blog/flaky-test-passed-on-retry-quarantine/?utm_source=x&utm_medium=social&utm_campaign=flaky-test-passed-on-retry-quarantine

#buildinpublic

---

## Bluesky

A flaky test passed on retry and our fix loop called it fixed — so we shipped deterministic quarantine: one isolated re-run, then the flake is pulled, ticketed, and named in the report. Review caught the success row firing on zero quarantines.

https://soleur.ai/blog/flaky-test-passed-on-retry-quarantine/

---

## Discord

**A flaky test passed on retry and the loop called it fixed.**

We shipped a deterministic quarantine protocol into the fix loop our users' workflows run — and review caught it lying twice:

→ Every newly failed check gets exactly one isolated re-run on unchanged work; a pass there is a flake signature, not a fix
→ Three acts per quarantined flake: pulled off the failure list, a tracker ticket filed and deduped on a marker inside the ticket (not a title search), and named in the final report — never a bare green
→ Review catch 1: the "all failures were flakes" row could fire on a run with no readable results — zero quarantines read as green; it now requires at least one real quarantine
→ Review catch 2: a warning flag whose trigger was empty by construction — it compared the flaked check's file against files the loop never edits; re-specified on signals that can actually fire
→ The root-cause checklist: six axes — seeds, clocks, network, state isolation, output terseness, contention

A pass on retry is not a pass. It's a flake asking to be quarantined, tracked, and fixed properly.

Full post: https://soleur.ai/blog/flaky-test-passed-on-retry-quarantine/?utm_source=discord&utm_medium=community&utm_campaign=flaky-test-passed-on-retry-quarantine

---

## LinkedIn Personal

A check that fails sometimes and passes other times on unchanged work does different damage in an AI workflow than in a human one. A person sees a vanished failure and gets suspicious. An agent sees a strategy that works: run it again until green.

So the fix loop our users' workflows run now treats a pass on retry as a flake signature, not a fix. Every newly failed check gets exactly one isolated re-run on the unchanged work — and a pass triggers three acts: quarantine (never counted as fixed, never spending fix budget), a tracker ticket deduped on a marker inside the ticket rather than a title search, and a named line in the final report. Never a bare green over quarantined flakes.

Review caught the machinery lying twice. The "everything that failed was a flake" success row could fire on a run that produced no readable results — zero quarantines read as green — so it now requires at least one real quarantine. And a warning flag meant to catch quarantined regressions had a trigger that was empty by construction: it compared the flaked check's file against files the loop never edits. Re-specified on the two signals that can actually fire.

The root-cause checklist that shipped with it is six axes any founder can audit a suite against: seeds, clocks, network, state isolation, output terseness, contention. Most flakes resolve to exactly one.

The full story: https://soleur.ai/blog/flaky-test-passed-on-retry-quarantine/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=flaky-test-passed-on-retry-quarantine

#buildinpublic #AIagents
