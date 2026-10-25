---
title: "Test the Migration, Not Just the Schema"
type: pillar
publish_date:
channels: x, bluesky, discord, linkedin-personal
status: draft
issue_reference: "#10730"
---

## X/Twitter Thread

**Tweet 1 (Hook):**
A database change applied cleanly — every check said so. Then our chat feature quietly broke for three weeks while everything looked green.

Here's what it taught us about testing the migration, not just the schema.

**Tweet 2:**
2/ A routine access-rule change made one field required. Every place a person's typed message got saved omitted it — each save was silently refused behind a generic error. But background jobs bypassed the rule, so data kept flowing and monitors stayed green.

**Tweet 3:**
3/ The lesson: users never relied on the specification. They relied on what the old thing actually did. "It applied cleanly" proves the change landed — it says nothing about whether anything downstream still works.

**Tweet 4:**
4/ The answer is differential testing: the old system is the oracle. Feed old and new the same inputs — generated plus real recorded traffic — normalize the differences a human declared meaningless, and compare the outputs in both directions.

**Tweet 5:**
5/ Every difference is exactly one of two things: a bug in the new system, or an intended change written into a ledger with a reason. A difference with no ledger entry is a bug by definition. When the comparison is clean modulo the ledger, you delete the old system.

**Tweet 6:**
6/ That recipe now lives in our users' planning workflow: any change that rewrites, ports, or replaces a running system must prescribe before-and-after evidence — routed so only migration-shaped plans pick it up.

**Tweet 7:**
7/ Honest scope: the recipe governs replacing a runnable system, not the schema scripts that reshape a live database. And it was only trusted after a negative control proved the coverage check could go red.

**Tweet 8:**
8/ The full recipe — normalization contract, replayed-traffic corpus, approved-changes ledger, delete-the-old exit:

https://soleur.ai/blog/test-the-migration-not-just-the-schema/?utm_source=x&utm_medium=social&utm_campaign=test-the-migration-not-just-the-schema

#buildinpublic

---

## Bluesky

A change applied cleanly — then quietly broke our chat feature for three weeks while background jobs kept everything looking green. The fix we shipped: the old system is the oracle; feed both sides the same inputs and account for every difference.

The story: https://soleur.ai/blog/test-the-migration-not-just-the-schema/

---

## Discord

**Test the migration, not just the schema.**

Our own measured incident: a routine database change applied cleanly — and every interactive write path it broke stayed silently broken for about three weeks, because background jobs bypassed the rule and kept the product looking green.

→ The lesson: users never relied on the specification; they relied on what the old thing actually did. "It applied cleanly" proves nothing downstream.
→ The answer: the old system is the oracle — same inputs through old and new, normalize the meaningless differences, compare outputs in both directions.
→ Every difference is a bug or a deliberate change written into a ledger with a reason. No third option. When the comparison is clean modulo the ledger, delete the old system.
→ The recipe now ships in the planning workflow our users' agents run — routed so only migration-shaped plans pick it up. Honest scope: it governs replacing a runnable system, not the schema scripts that reshape a live database.

Full post: https://soleur.ai/blog/test-the-migration-not-just-the-schema/?utm_source=discord&utm_medium=community&utm_campaign=test-the-migration-not-just-the-schema

---

## LinkedIn Personal

Our product's chat feature was broken for about three weeks, and nothing looked broken.

A routine database change had applied cleanly — every check said so. What it also did was make one field required, and every place where a person's typed message got saved omitted it. Each save was silently refused behind a generic error bubble. Meanwhile, background jobs ran under an access level that bypassed the rule, so data kept flowing and the monitors stayed green.

The lesson underneath: users never relied on the specification. They relied on what the old thing actually did. "It applied cleanly" is evidence the change landed — never evidence that anything downstream still works.

The discipline we shipped for this is differential testing: the old system is the oracle. Feed old and new the same inputs — generated plus real recorded traffic — normalize the differences a human declared meaningless, and compare the full output set in both directions. Every difference is a bug or a written-down deliberate change; there is no third option. The exit criterion is not "clean for a while" — it is deleting the old system.

That recipe now lives in the planning workflow our users' agents run: any plan that replaces a running system must prescribe the before-and-after evidence. Honest scope — it governs replacing a runnable system, not the schema scripts that reshape a live database; the title's "schema" is the cheap test everyone already runs.

The full story: https://soleur.ai/blog/test-the-migration-not-just-the-schema/?utm_source=linkedin-personal&utm_medium=social&utm_campaign=test-the-migration-not-just-the-schema

#buildinpublic #AIagents
