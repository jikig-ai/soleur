---
title: "The First Property Test We Wrote Found a Real Bug"
type: pillar
publish_date: 2026-11-03
channels: x, bluesky, discord, linkedin-personal
status: scheduled
issue_reference: "#10636"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
The first property test we ever wrote caught a real bug on day one — a defect that had sat in production for months, behind a documented promise and a dedicated check that never once saw it.

**Tweet 2:**
2/ A property test states a rule that must always hold — "running a cleanup twice changes nothing the second time" — and a generator throws thousands of random inputs at it, trying to break it.

**Tweet 3:**
3/ The first generated run produced an address with a space hiding just before its file suffix — an input no human picks. The cleanup stripped the suffix, exposed the space, and running it twice gave a third answer. The docs said impossible.

**Tweet 4:**
4/ Once we knew the shape to look for, the same defect was living in the database's own copy of the cleanup — the third time the two implementations of one idea had drifted apart. Both are fixed now.

**Tweet 5:**
5/ The test machinery itself needed fixing too: it was watching 31 of 39 rules while green, malformed test inputs silently became permanent no-ops, and a random-number trap turned "a hundred draws" into one draw repeated.

**Tweet 6:**
6/ Example tests sample the cases you remembered. Rules plus generation find the one you didn't. The first run already paid for the practice.

**Tweet 7:**
7/ The full story — the bug, the twin, and the harness fixes:

https://soleur.ai/blog/first-property-test-found-real-bug/?utm_source=x&utm_medium=social&utm_campaign=first-property-test-found-real-bug

#buildinpublic

---

## Bluesky

The first property test we ever wrote caught a real bug on day one — an invisible trailing space the docs called impossible, a twin defect hiding in the database, and a test harness lying green.

The full story: https://soleur.ai/blog/first-property-test-found-real-bug/

---

## Discord

**The first property test we wrote found a real bug.**

We adopted property testing — state a rule that must always hold, let a generator throw thousands of random inputs at it — and its very first run caught a defect no hand-picked example ever had:

→ A repository-address cleanup could leave an invisible trailing space: run it once, get one answer; run it again, get a third — the documentation promised that was impossible
→ The same defect lived in the database's own copy of the cleanup — the third drift between two implementations of one idea; both now fixed
→ The harness needed fixing too: watching 31 of 39 rules while green, malformed inputs folding into permanent no-ops, and a random-number trap that turned "a hundred draws" into one
→ Example tests sample the cases you remembered; rules plus generation find the one you didn't

Full post: https://soleur.ai/blog/first-property-test-found-real-bug/?utm_source=discord&utm_medium=community&utm_campaign=first-property-test-found-real-bug

---

## LinkedIn Personal

We adopted property testing — instead of a list of remembered cases, you state a rule that must always hold, and a generator throws thousands of random inputs at it trying to break it. The practice earned its place immediately: the very first generated run caught a real bug.

The defect was an invisible one. A utility that tidies repository addresses could leave a trailing space behind when a stripped suffix had been hiding it — so running the cleanup twice produced a third answer, breaking a documented promise. No human would have hand-picked that input; months of example tests had walked around it. And once we knew the shape, the same defect turned up in the database's own copy of the cleanup — the third drift between two implementations of one idea. Both are fixed now.

The honest half of the story: the generated-input machinery arrived with defects of its own, all failing toward green. It was watching 31 of 39 rules while reporting clean, malformed test inputs folded into permanent no-ops, and a random-number trap turned a claimed hundred draws into one repeated. Every instrument that measures coverage has to prove what it covers.

Example tests sample the cases you remembered. Rules plus generation find the one you didn't.

The full story: https://soleur.ai/blog/first-property-test-found-real-bug/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=first-property-test-found-real-bug

#buildinpublic #AIagents
