---
title: "The Map That Only Records What the Agent Saw"
type: pillar
publish_date:
channels: x, bluesky, discord, linkedin-personal
status: draft
issue_reference: "#10737"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
Your AI checks your product by clicking around — and forgets the map it built the moment the session ends. We shipped a convention for a map that can never fabricate: it records only what the agent saw.

**Tweet 2:**
2/ Without a map, every run re-derives how your pages fit together and throws it away. The agent mistakes wrong turns for missing features — or takes shortcuts no customer could take. That's flailing, not testing.

**Tweet 3:**
3/ The convention: one committed map file at one pinned location. Each reachable page gets an entry — how a user reaches it, stable landmarks, what they should see, sign-in needs, gotchas — plus a written reason for every page left unmapped.

**Tweet 4:**
4/ The trust rule: the map may only seed routes the run actually exercised. An entry for a page never visited fabricates the exact fields that make it trustworthy. Zero exercised routes means no seed is written at all.

**Tweet 5:**
5/ Refresh is field-scoped: a run corrects only the fields it contradicted and appends newly visited pages — your annotations survive. And the guard is the update contract itself: presence, not conformance.

**Tweet 6:**
6/ Review caught the checker too: a control meant to prove the doc's link could be removed couldn't go red — the census counted the file's name anywhere in the text, not the link. It "passed" either way.

**Tweet 7:**
7/ A record is trustworthy in proportion to how hard it is to fabricate. The full convention — entry grammar, seed contract, field-scoped refresh:

https://soleur.ai/blog/map-that-only-records-what-the-agent-saw/?utm_source=x&utm_medium=social&utm_campaign=map-that-only-records-what-the-agent-saw

#buildinpublic

---

## Bluesky

An agent without a map re-derives your product on every run — and a map it writes can describe pages it never visited. Our convention: seed only exercised routes, refresh only contradicted fields. https://soleur.ai/blog/map-that-only-records-what-the-agent-saw/

---

## Discord

**The map that only records what the agent saw.**

An AI that checks your product without a map pays for discovery on every run — then throws the map away at session end. We shipped a convention built around one rule: the map can never fabricate.

→ One committed map file at a pinned location; each reachable page gets an entry (how a user reaches it, stable landmarks, expected outcome, sign-in needs, gotchas)
→ The map seeds only routes the run actually exercised — zero exercised routes means no seed at all; an entry for an unvisited page fabricates the fields that make it trustworthy
→ Refresh is field-scoped: a run corrects only what it contradicted, so your annotations survive; the guard is the update contract itself, not a separate checker
→ Review caught the check meant to protect it: a "remove the link" control couldn't go red because the census counted the file's name anywhere, not the link

Full post: https://soleur.ai/blog/map-that-only-records-what-the-agent-saw/?utm_source=discord&utm_medium=community&utm_campaign=map-that-only-records-what-the-agent-saw

---

## LinkedIn Personal

Ask your AI to check your product and it starts clicking — and next week it starts from zero, re-deriving how your pages fit together and discarding the map at session end. That's flailing, not testing.

The fix is a feature map: a written inventory of what your product does from the user's side of the screen. But a map an agent writes carries a failure no paper map had — it can describe, in confident detail, pages the author never visited.

So the convention we shipped draws the line where trust lives: the map may only seed routes a run actually exercised, and if a run exercised nothing, no map is written at all. Refresh is field-scoped — a run corrects only the fields it contradicted, so your own annotations survive. And review caught the check that was supposed to guard it: a control meant to prove the document's link could be removed couldn't go red, because the census counted the file's name anywhere in the text, not the link.

A record is trustworthy in proportion to how hard it is to fabricate.

Full post: https://soleur.ai/blog/map-that-only-records-what-the-agent-saw/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=map-that-only-records-what-the-agent-saw

#buildinpublic #AIagents
