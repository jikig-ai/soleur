---
module: web-platform-infra
date: 2026-09-03
problem_type: logic_error
component: terraform_infra
symptoms:
  - "a type-shaped precondition passed while the set it guards had shrunk"
  - "de-proxying an HSTS-preloaded apex became one-way with every gate green"
  - "a guard reported 11/11 with its own defect planted"
  - "four test suites reported green when one was rc=1"
root_cause: guard_axis_mismatch
severity: critical
tags: [guard-vacuity, cardinality-vs-type, mutation-testing, instrument-error, adr-194, cutover]
issue: 7640
pr: 7780
synced_to: [review, work]
---

# A type check cannot protect against a count change, and my instrument said green

## Problem

ADR-194 PR4a shrinks the `soleur.ai` apex `for_each` from four GitHub Pages
A-records to one, so the cutover's `A`→`CNAME` flip becomes a single-address
replace that Terraform core serialises. The change is three lines of HCL.

It armed a live-site outage in a file it does not touch, and every gate I had
was green.

## Root cause

`cron-gh-pages-cert-reissue.ts` gates its de-proxy on `apexTopologyIsA`:

```ts
const addressTypes = inputs.apexRecordTypes
  .map((t) => t.toUpperCase())
  .filter((t) => APEX_ADDRESS_RECORD_TYPES.has(t));
return addressTypes.length > 0 && addressTypes.every((t) => t === "A");
```

That is **type-shaped**. PR4a's change is **cardinality-shaped**. After the
shrink the apex is still an `A`, so the precondition returns `true` — while
`listToggleRecords()` (which queries exactly `[apex,"A"]` + `[www,"CNAME"]`)
now returns 2 against `EXPECTED_TOGGLE_RECORDS = 5`.

The sequence that follows has no other brake:

1. every precondition passes
2. `setRecordsProxied(deps, records, false)` runs **unconditionally**
3. `restoreStateInner` reads `2 < 5` and refuses to restore a subset

So the de-proxy is **one-way**. Unproxied, the apex resolves straight to
`185.199.108.153`, whose GitHub Pages origin certificate expired 2026-08-16 and
is never renewed. The `ssl = "full"` Configuration Rule that holds the site up
acts at the Cloudflare **edge**, which de-proxying bypasses — so on an
HSTS-preloaded apex every visitor gets a hard TLS failure with no edge left to
rescue them, and no `http://` fallback available to them either.

Reachability is manual-trigger only, but three retained surfaces hand an agent
that exact event: the cert-renewal runbook, the `soleur:trigger-cron` skill, and
`cron-gh-pages-cert-state`'s own issue body, whose `remediation` field names it.

**The sharp part.** Line 86 of that same file already carries a ‼️ warning that
a COUNT cannot protect against a record TYPE. They reasoned about the axis in
one direction. The converse is what shipped.

## Solution

A cardinality precondition, asserted before any mutation, so the routine refuses
instead of silently flipping:

```ts
toggleSetIsComplete: (() => {
  const apexAddressCount = inputs.apexRecordTypes
    .map((t) => t.toUpperCase())
    .filter((t) => APEX_ADDRESS_RECORD_TYPES.has(t)).length;
  return apexAddressCount + 1 === EXPECTED_TOGGLE_RECORDS;  // +1 = the www CNAME
})(),
```

Mutation-proven: neutering it to `apexAddressCount >= 0` reds 2 tests.

## Key insight

**When a guard asserts a property of a set's MEMBERS, ask separately what
protects the set's CARDINALITY — and vice versa. The two axes are independent,
and a guard covering one reads as covering both.**

The tell is a guard whose predicate quantifies (`every`, `all`, `none`) without
anything nearby constraining *how many* it quantified over. `every(t => t ===
"A")` is vacuously true of a one-element array and of an empty one.

## Three more instances from the same session

### A guard's assembly is narrower than the property it names

`apex-single-node-replace.test.sh` claimed a structural quantifier over "every
`cloudflare_record` whose name resolves to the apex". Eight measured fail-opens:

| escape | why it worked |
|---|---|
| `pages_apex` relocated to `cf-pages.tf` | the guard read `dns.tf`; Terraform reads the DIRECTORY |
| `name = local.apex_host` | non-literal values dropped out of the filter — "could not measure" read as "not an apex record" |
| `soleur.ai.` / `@` / `SOLEUR.AI` | exact-string match; all three address the zone root |
| one leading space before `resource` | `^resource` was column-0 anchored |
| a second www record under any other label | www was read at the block *labelled* `www` |
| an `if: false` decoy job | the `-target` grep ran file-globally over a workflow with ~15 other jobs |
| `-target` in runbook prose inside a block scalar | same |
| `# DISABLED: …apex-single-node-replace.test.sh` | the registration case was a bare substring over the ONE input never comment-stripped |

That last one is the sharpest: the guard's own `strip_comments` header describes
exactly that failure — applied everywhere except its own registration.

### An anti-vacuity identity cannot see a mis-routed verdict

Rewriting the wrapper from a branch to `CASES=$((CASES+1)); pass "$2"` left all
9 assertions reporting PASS **with `create_before_destroy` planted on the live
apex**, exit 0. Both mechanisms were satisfied: `CASES` still reached its exact
floor, and `PASS+FAIL` still equalled it.

An identity can only detect a verdict that goes **nowhere**, never one that goes
to the **wrong arm**. A positive control on `pass`/`fail` directly does not catch
it either — the control must drive the **wrapper**.

### My own instrument reported green over a red suite

```bash
for t in ...; do bash "$t" > log 2>&1; echo "$(basename $t) EXIT=$?"; done
```

`$(basename $t)` is a command that runs while the `echo` arguments are expanded,
and it **resets `$?`**. The loop reported EXIT=0 for four suites; one was rc=1
from my own edit. The tell was a `FAIL` line in a log belonging to a suite I had
just recorded as passing.

Same family, same session: `git push … | grep -v remote; echo "rc=$?"` reports
`grep`'s status, and masked a non-fast-forward push failure.

**Capture rc into a variable on its own line, before any expansion that can run
a command.**

## Prevention

- For any guard with a quantifier, write down both axes explicitly: what
  constrains the members, and what constrains the count.
- On a guard-shaped PR, run the cheap deterministic gates (shellcheck, the
  repo's `lint-*` scripts) **before** the agent panel. Their yields are disjoint
  and the lints are orders of magnitude cheaper.
- Never read a suite's verdict from an `echo` containing a command substitution.
- Index a documentation sweep by **claim**, not by hunk.

## Session Errors

- **Planning subagent spliced corrected ADR items to the TOP of the plan file**,
  breaking the YAML frontmatter, while the in-place copy still prescribed the
  SUPERSEDED two-pass design — `/work` would have built the dead mechanism. Its
  own duplicate-heading sweep could not see it because the stranded text carries
  no headings. Recovery: relocated the corrected block over the stale items and
  restored the frontmatter to line 1. **Prevention:** after any splice, assert
  the file still begins with `---` and that the superseded text occurs 0 times.
- **An earlier `s.index()` splice duplicated ~1,150 lines** (subagent
  self-reported and recovered). **Prevention:** assert `start < end` before any
  index-based splice.
- **PR4a armed a one-way de-proxy** in a file it does not touch. Recovery: the
  `toggleSetIsComplete` precondition above. **Prevention:** the key insight.
- **The guard shipped 8 fail-opens**; **its anti-vacuity comment overclaimed**;
  **its positive control drove the helpers rather than the wrapper**. Recovery:
  all fixed inline and mutation-proven. **Prevention:** ask per guard "name an
  implementation a reasonable engineer writes next that satisfies this while
  violating the property".
- **The runbook sweep was hunk-indexed**, leaving 10 stale "PR4 is one merge"
  sentences in the file being edited — two of them safety defects (a forward-fix
  path prescribing "re-merge PR3 and PR4" as one act, which is the exact hazard
  the design removes; and a "red publish leg is benign" paragraph that inverts
  during the PR4a window because GitHub Pages is still the live origin).
  **Prevention:** index by claim.
- **The runbook table cell was factually wrong** ("two of the three surviving"
  for a change that removes three of four) **and inverted the column's
  direction** ("Reverting it removes"). **Prevention:** re-read a table's column
  header before adding a row to it.
- **The runbook cited a script that does not exist until PR4b.** **Prevention:**
  when a doc lands a merge before its tooling, say so at the citation and give
  the hand-written fallback.
- **`domains.md` carried three false claims** and appeared in no task — drift
  owned by nobody. **Prevention:** a file that declares itself a mirror needs
  either a gate or an owner.
- **My `test-all.sh` infra-prefix widening broke a sibling suite that pinned
  that exact line.** The "edits a guarded literal" side of the documented
  add-a-copy class. Recovery: the neuter now locates the block from the
  assignment backwards. **Prevention:** `git grep` a literal before editing it.
- **The first repair regex over-matched** — `^if …then` non-greedy starts at the
  FIRST `if` in the file and swallowed everything, producing 89 failures from a
  syntactically broken sandbox. **Prevention:** anchor from the unique marker
  backwards, never from an unanchored keyword forwards.
- **My measurement instrument was broken** (the `$(basename …)` `$?` reset).
  **Prevention:** as above.
- **`git stash list` is hook-blocked even read-only**, and it takes down the
  WHOLE Bash call it appears in — twice, each time discarding real work queued
  after it. **Prevention:** never place a possibly-blocked command in a compound
  Bash call ahead of work you want to keep.
- **Unresolved, carried not hidden:** the deferred-cleanup issue AC24 cites
  could not be found by number. Carried as AC52 (PF-DEFER) for PR4.

## Process finding

An 8-agent panel found ~30 findings on a PR already self-verified green across
6 guards, 2 mutation batteries, `tsc`, shellcheck and actionlint. The instrument
yields were **disjoint**: structural enumeration found the window/assembly gaps,
test-design mutation found the verdict routing, shellcheck found a real
captured-but-unasserted variable (SC2034), and the repo's own deterministic
lints found their own class. **No single instrument found more than about a
third.**

## See also

- `2026-08-10-six-times-a-check-certified-something-other-than-what-it-named.md`
- `2026-08-12-i-reused-a-monitored-marker-name-and-inherited-its-paging-severity.md`
- `2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md`
- `2026-08-14-my-gate-reserved-its-reassuring-message-for-its-alarming-condition.md`
