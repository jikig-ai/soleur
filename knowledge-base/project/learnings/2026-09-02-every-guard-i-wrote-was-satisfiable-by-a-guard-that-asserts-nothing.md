---
title: "Every guard I wrote was satisfiable by a guard that asserts nothing"
date: 2026-09-02
category: best-practices
module: infra
issues: [7395, 7749, 7714]
tags: [guards, mutation-testing, fail-open, cloudflare, collision-gate]
---

# Every guard I wrote was satisfiable by a guard that asserts nothing

## Problem

Two pieces of work, one session. A production deploy freeze (#7395), and the
control that turned out to be holding the apex up (#7749). The freeze was fixed by
a parallel session while this one was mid-review; the second piece shipped a guard
whose first three revisions each had a hole that reading it could not find.

## What actually generalizes

### 1. A guard's own verification is where its defects live

The guard was green on the real tree at every revision. Everything wrong with it was
found by *running* something, never by reading:

| Defect | Found by |
|---|---|
| Shadow check compared indices against a mitigation defined as the *first* match — a lower index was impossible by construction, so the check could never fire | mutation row MISROUTED |
| `fail()` neutered left the suite green (`PASS+FAIL` still equalled `CASES` while everything passed) | dispatch-axis mutation |
| Two host assertions were tautologies — the selector already required both hosts | structural enumeration |
| Greedy `sub(/.*=[[:space:]]*/)` captured from the LAST `=`, so any expression containing `=` truncated to garbage and stopped being counted | enumeration, measured |
| Count keyed on host literals missed a rule matching the apex *without naming it* | enumeration, measured |
| `count`/`for_each`/`lifecycle` on the resource destroy every rule without touching the rule block | enumeration |
| Stage read one file, so a `git mv` / parameterization / AAAA switch silently retired the guard | enumeration, measured |
| Dead `m_idx` capture left by a replaced check | `shellcheck` SC2034 |

Note the instruments are *disjoint*. Mutation found the dispatch and ordering holes;
enumeration found the population and stage holes; shellcheck found the dead code. No
single instrument found more than three. A review that runs only one ships the rest.

### 2. An exclusion keyed on a literal is bypassable by the form that matches without naming it

The count excluded `app.soleur.ai` by substring. But `(http.host ne "app.soleur.ai")`
*contains* that literal while matching the apex — the negation slipped through the
exclusion that was meant to remove it. `(true)` matches everything and names nothing.

The fix is not a better substring. It is to stop keying on the expression's spelling
at all: count by the **presence of the key being set**, and exclude the one known rule
by **exact expression equality**. Ask of any allowlist/denylist predicate: *what input
satisfies this while doing the thing it is meant to prevent?*

### 3. A stage predicate that reads ONE file self-retires on ordinary refactors

The guard resolved pre- vs post-cutover from `dns.tf`. Three ordinary refactors — none
with any intent to touch TLS — flipped it to post-cutover, and post-cutover it stops
requiring the rule:

- move the record blocks to a sibling `.tf`
- replace the IP literals with a variable
- switch the A records to AAAA

Each is a *silent self-retirement of a production guard*. Fixed by scanning every `.tf`
in the directory and accepting three independent signals, one of which is the resource
block the sibling guard already used — which also removed a divergence where two guards
in one directory resolved the same fact differently.

The narrowing that matters: the record-block signal matches only
`cloudflare_record.github_pages`, not `www`. A `www` record *survives* the cutover
re-pointed at Pages, so matching it would keep the guard armed forever and defeat the
self-retirement the removal condition depends on.

### 4. Asserting cardinality beats asserting position — including against your own wrong model

I wrote "first-match-wins" in four places. Cloudflare's ruleset engine is
**last-match-wins for non-terminating actions**, and `set_config` is one. So the
dangerous position for a competing rule is *below*, and my mutation row inserted
*above* — testing the harmless side while describing it as the fatal one.

The assertion survived my being wrong, because it asserts *exactly one such rule exists*
rather than *no rule exists above*. A position-agnostic predicate is immune to the author
having the direction backwards. That is a better argument for the design than the one I
originally wrote for it.

Sibling caution: `seo-bulk-redirects.tf` reasons first-match-wins and is **correct** —
redirects terminate. Two files in one directory, opposite rules, both right. Do not carry
the reasoning across.

### 5. A commit existing is not the file existing

`git-history-analyzer` reported that commit `bdef12ceb` added
`test/docker-context-import-containment.test.ts`. `git cat-file -t bdef12ceb` → `commit`.
`ls` on the file → absent. `git ls-files` → absent.

The commit was real and on an **unmerged branch**. Verifying it is what surfaced that a
parallel session was fixing the same bug — but the claim as stated was false. For any
agent claim of the form "commit X added file Y", `git cat-file -t` confirms the commit and
proves nothing about the file; `git ls-files` / `git show <ref>:<path>` is the check.

### 6. The collision gate quantifies over what you typed, not what happens next

`one-shot` Step 0a.5 probes for collisions at invocation and re-probes after planning.
Both cleared. #7714 was created ~23 hours *after* the last probe, while this session sat
idle across two day boundaries, and merged while an 8-agent panel reviewed the now-
redundant diff. The full cost of that PR — planning plus panel, ~1.2M subagent tokens —
bought findings that survived and a diff that did not.

The gap is structural: there is no re-probe between review and ship, and a long-lived
session is exactly where one is needed.

### 7. `/tmp` is not durable across a day boundary

The session scratchpad was reaped overnight, taking a test log and four drafted issue
bodies. The commit survived, so nothing was lost that mattered — but drafts and logs
belong in `/var/tmp`, which the reaper does not clear.

## Session Errors

**Collision gate cleared 23h before the colliding PR existed** — Recovery: caught only
by verifying an agent's history claim. Prevention: re-probe for collisions before ship,
not only after planning. Recurring; see §6.

**Filed #7749 on a false premise** — I asserted the origin cert was unobservable behind
the proxy and at risk of expiring. It is observable (SNI to the Pages IP) and it expired
on 2026-08-16. Recovery: CTO falsified it by measurement; I re-verified, appended a
correction and retitled rather than editing the body. Prevention: for any claim of the
form "X is unobservable", write the command that would observe it before asserting.

**Inverted rule-ordering semantics in four sites** — Recovery: claims-verification seat
caught it; confirmed against Cloudflare docs. Prevention: when a comment asserts an
evaluation order, name the vendor doc sentence in the comment.

**Shipped a guard whose shadow check could never fire, and two tautological assertions** —
Recovery: mutation + enumeration. Prevention: for each assertion, name an implementation
that satisfies it while violating the property; if you cannot construct the failing input,
the assertion is decorative.

**Greedy RHS split truncated any expression containing `=`** — fail-open. Recovery:
enumeration measured it. Prevention: split config attributes on the FIRST `=`.

**Asserted the zone default is Full (STRICT) as fact** — it is dashboard-managed and
unpinned in Terraform. Recovery: restated as the inference it is, and recorded as a gap
one level above the guard. Prevention: before asserting a config default, grep for the
resource that sets it.

**ADR cadence claim wrong** (said 180s for all three probes; two are 300s with a
3-interval threshold) — Recovery: read the resources. Prevention: never restate a cadence
from memory when the `.tf` is one grep away.

**Left a backwards claim in a block I was rewriting** (`apex 301s to www`; it is the
reverse, since #4577) — Prevention: when rewriting a comment block, verify every claim in
it, not only the one you came to fix.

**`/tmp` scratchpad reaped overnight** — Recovery: re-created in `/var/tmp`. Prevention:
durable artifacts never go in `/tmp`.

**Mechanical slips** (missing scratchpad dir; a `%` format collision in an edit script;
a mutation anchor whose spacing did not match the file; untrimmed whitespace in an awk
RHS capture; dead code left by a replaced check) — all one-off, each caught immediately by
the failing command. No prevention warranted beyond what already fired.
