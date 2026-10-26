---
title: "A Map That Can't Drift"
type: pillar
publish_date:
channels: x, bluesky, discord, linkedin-personal
status: draft
issue_reference: "#10694"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
We gave our product's feature map a guard that fails the moment the map and the product disagree.

Then our review panel found four ways the guard itself could lie.

**Tweet 2:**
2/ The map: every page a visitor can reach in the product — 32 of them. 27 get full entries: how a real user arrives, what they should find. 5 sit on a deliberate exemption list, each with a written reason.

**Tweet 3:**
3/ The guard checks both directions. A page missing from the map fails. A map entry for a deleted page fails. And every entry must carry its required fields — presence is not conformance.

**Tweet 4:**
4/ First defect: the guard's file listing counted 31 of 32 pages. The listing pattern skipped the one file sitting at the front door — the homepage. A census that under-counts doesn't look broken. It stays green forever.

**Tweet 5:**
5/ Three more: a completeness check a mere mention could satisfy. An example inside the document that could count as a real entry. Two separate scoreboards for "did it pass" — a finding could print and the run still come back green.

**Tweet 6:**
6/ The honest scope: it runs in our full local test suite, where a map/product mismatch fails the run. In CI it reports rather than blocks — deliberate staging, not oversight. Enforcement that reports is still enforcement.

**Tweet 7:**
7/ The lesson generalizes: any check built on a listing can under-count and stay green. Count a second way and compare — and prove a check can go red before you trust it to guard anything.

**Tweet 8:**
8/ Four ways "the map is correct" could have been a lie — each caught before a single agent relied on it. The full story:

https://soleur.ai/blog/map-that-cant-drift/?utm_source=x&utm_medium=social&utm_campaign=map-that-cant-drift

#buildinpublic

---

## Bluesky

We gave our product's feature map a guard that fails when the map and the product disagree — then review found four ways the guard itself could lie, from a file listing that skipped the homepage to two scoreboards for "did it pass."

The story: https://soleur.ai/blog/map-that-cant-drift/

---

## Discord

**A map that can't drift.**

We shipped a feature map for the platform — every reachable page, how a real user gets there, what they should find — plus a guard that fails when map and product disagree in either direction. Then the review panel graded the guard:

→ Its file listing counted 31 of 32 pages — the pattern skipped the file at the front door (the homepage); a census that under-counts stays green forever
→ A completeness check a prose mention could satisfy — presence is not conformance
→ An example inside the document could be counted as a real entry — the convention now forbids example blocks entirely
→ Two separate scoreboards for "did it pass" — now one ledger every check feeds

Honest scope: it runs in the full local test suite where a mismatch fails the run; in CI it reports rather than blocks — a deliberate staging choice.

Full post: https://soleur.ai/blog/map-that-cant-drift/?utm_source=discord&utm_medium=community&utm_campaign=map-that-cant-drift

---

## LinkedIn Personal

Every founder's documentation drifts — the onboarding tour naming a screen you renamed, the help page walking through a flow you removed. Nothing makes those documents true, so they lie politely.

We hit this building our own platform and shipped a feature map that carries its own enforcement: 32 reachable pages — 27 fully mapped, 5 deliberately exempt with written reasons — plus a guard that checks both directions. A page missing from the map fails. A map entry for a deleted page fails.

Then our review panel found four ways the guard itself could lie. Its file listing counted 31 of 32 — the pattern skipped the file sitting at the front door, so the census stayed green forever. A completeness check could be satisfied by a sentence merely mentioning a field. An example inside the document could count as a real entry. And the guard kept two separate scoreboards for "did it pass" — a finding could print and the run still come back green.

The honest scope: it runs in our full local test suite where a mismatch fails the run; in CI it reports rather than blocks — a deliberate staging choice. Enforcement that reports is still enforcement.

The lesson for any founder: a check built on a listing can under-count and stay green. Count a second way — and prove every check can go red before you trust it.

The full story: https://soleur.ai/blog/map-that-cant-drift/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=map-that-cant-drift

#buildinpublic #AIagents
