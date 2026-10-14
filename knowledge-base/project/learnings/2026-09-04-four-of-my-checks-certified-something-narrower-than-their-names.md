---
title: "Four of my checks certified something narrower than their names — in the PR that closes that class"
date: 2026-09-04
category: workflow-patterns
tags: [vacuous-guards, acceptance-criteria, measurement, legal-register, review, compound]
issue: 7625
pr: 7803
component: knowledge-base/legal
severity: high
---

# Four of my checks certified something narrower than their names

## Problem

PR #7803 amends Art. 30 Processing Activity 7 — a statutory GDPR register — and nothing in CI
validates that file. No test checks its table integrity, its cell completeness, its PA numbering, or
`audits/` frontmatter at all. The plan says so explicitly: **when CI checks nothing, the acceptance
criteria ARE the CI.**

Nineteen ACs were written on that premise. Four of them certified something narrower than the claim
they carried, and a review panel of four agents found all four. The PR's own subject is a register
cell that asserted `None.` over a field nobody had checked — so the defect class the work exists to
close recurred inside the work's own verification layer.

## The four

**AC1 — the keystone, falsified by the PR's own row.** It asserted `pa7 | grep -c '^|'` returns
**11** and that "this change rewrites cells and adds no rows". The change adds the `(h) DSAR` row, so
it returns 12 — and the plan said so in four other places (`## Files to Edit`, addendum A4,
`tasks.md`, `session-state.md`). A number from a draft written before A4 minted that row. Every other
scoped AC declares a dependency on AC1, so the set's foundation was the stalest thing in it.

**AC9 — label-scoped where the property is activity-scoped.** Its allowlist keyed on the row LABEL:

```
grep -vE '^[+-]\| \*\*((\(c\) )?Categories of (data subjects|personal data)|Special categories.*|Lawful basis|\(h\).*)\*\* \|'
```

`Special categories.*` and `Lawful basis` match those rows in **all 35** Processing Activities. The
constraint it was written for is "touch only PA-7's rows". Mutation-proven rather than argued: a
semantically mutated **PA-31** row **PASSES** the old form and **FAILS** the replacement, which
compares the register's whole changed-line count against PA-7's extracted-block count (9 and 9).

**The placeholder guard — a regex that cannot match the thing it names.** Written as
`grep -cE '#<[a-z0-9-]+>'`, lower-case-only, so it structurally cannot match `PR-B`, the exact
placeholder it exists to catch. Measured: **0 case-sensitive, 4 case-insensitive.** The register was
genuinely clean, so the guard's OUTPUT was correct and its REASONING was not — it would have returned
0 against a register full of unsubstituted markers spelled with a capital. Its scope was wrong in the
other direction too: it claimed to cover "the register or this record", while the record's four live
markers sit inside transcriptions that must keep them.

**The citation set — broken by the commit that moved the lines.** The attestation cites seven
"precedent cells" by line number. Inserting `(h)` at line 165 shifted everything below it, so five of
the seven now land on `(c) Categories of personal data` rows instead of the `Special categories`
cells meant. `cq-cite-content-anchor-not-line-number`, violated by the same commit, inside a record
that argues for content anchors elsewhere.

## Key insight

**A check answers a question about the SET you handed it. Name that set before believing the answer.**

Every one of the four was a correctly-executed check over the wrong domain — a label set instead of
an activity set, a case-sensitive class instead of the placeholder alphabet, a row count from before
the row existed, a line number from before the line moved. None of them is a bug in the predicate.
All four are the predicate pointed somewhere narrower than the sentence above it.

The tell is uniform and cheap to test: **name an implementation a reasonable engineer might write
next that satisfies this check while violating the property.** If you can name one in under a minute,
the check is a proxy. For AC9 that implementation is "rewrite PA-31's cell"; for the placeholder
guard it is "spell the placeholder with a capital"; for AC1 it is "add a row".

## Second insight: an instrument that fails toward clean

Four measurements I ran to check my own work were themselves broken, and **all four failed in the
reassuring direction**:

- A mutation test reported PASS/PASS. `git diff main...HEAD` reads the **committed** tree and the
  mutation was in the working tree, so the mutation never landed and both arms measured the baseline.
  Caught only because the check compares two numbers and they contradicted (`whole=0` against
  `pa7=9`); a single-number assertion would have reported clean.
- `git diff main` ran against a **stale local `main` ref** (2 commits behind `origin/main`), listing
  six sibling-branch files as mine.
- A markdownlint baseline probe hit an out-of-tree path, tripped the ignore filter, and returned
  **`0`** — indistinguishable from a clean file.
- A history-verification agent read the register's `(#7100)` amendment citations as **pull-request**
  numbers and compared them against PR #7110, which closed issue #7100. Two of its three findings
  were false positives; applying them would have written errors into a statutory record.

**Verify the instrument before reading its output, and prefer checks that compare two independently
derived numbers** — a contradiction is legible where a single wrong number is not.

## Third insight: markdown structure is a correctness surface in generated prose

Three defects were markdown parsing, not content, and each would have shipped a document that renders
wrong while grepping right:

- A literal `|` inside a table cell's prose made an 8-field row. **GFM discards the overflow**, so
  the row renders with a dropped cell — the same mechanism that once shipped an Art. 30 amendment
  displaying as unamended.
- A nested backtick made one code span into two (MD038).
- `#7815` at line start parsed as an `<h1>`.

After any generated table row, count pipes against a sibling row. After any edit, sweep the diff for
`^#[0-9]` — an issue reference at line start is a heading.

## What was NOT wrong, and why it matters

The panel verified ~60 implementation-detail claims in the amended cells against `schema.ts`,
`build-record.ts`, `allowlist-bypass.ts`, `gdpr-override.sh`, `inspect-evidence.sh`,
`dsar-export-allowlist.ts`, both workflows and the published corpus. The capture predicate — that the
evidence write gates on the PERSISTING `license/cla` head-SHA status and never on comment content —
is confirmed **byte-exact**, as are the schema's 13 fields and enum, the tombstone shape, the DSAR
allowlist's table-keying, AUP § 4.7's scoping, § 8.1's four carve-outs, and § 0's cross-references.

The two P1s both landed in **the sentences that reason about people rather than code**: a claim that
allowlisted natural persons sign nothing and hold no account (the only such person is the operator,
who signed), and a divergence block that enumerated three superseded corpus statements where there
are four. Prose about mechanisms gets checked against the mechanism. Prose about populations gets
checked against nothing, because there is no file to grep.

## Prevention

- **State the property in one sentence, then state the check's scope in another, and ask whether the
  second covers the first.** Do this per AC, at authoring time. Three of the four defects are visible
  from that pairing alone.
- **Mutation-prove any check whose subject is a scope constraint** — mutate a thing OUTSIDE the scope
  and confirm it reds. AC9's label limb passes a full semantic rewrite of another activity's cell.
- **Re-derive every plan-quoted count at implementation**, including the ones other sections of the
  same plan contradict. AC1's `11` was contradicted four times in its own file.
- **Use `git diff origin/main`, never `main`,** and never three-dot for a working-tree measurement.
- **A finding is a hypothesis in both directions.** Two of the history pass's three findings were
  false; applying them would have introduced errors into a statutory record to satisfy a misread.
- **When prose reasons about a population rather than a mechanism, find the file that would falsify
  it** — here `origin/cla-signatures:signatures/cla.json`, which names every signer.

## Session Errors

- **AC5 was unsatisfiable by a correct implementation.** It forbade the superseded limb-(iii) string
  anywhere in PA-7, while this register's amendment convention REQUIRES every block to quote the text
  it supersedes. Measured 1 occurrence in PA-7, 0 in live cell text. — Recovery: rescoped the AC to
  live cell text (0 on HEAD, 1 on `main`, so non-vacuous) and recorded why. — **Prevention:** when an
  AC fails on a correct implementation, fix the AC explicitly; never satisfy a looser variant at run
  time. Fixing the artifact here would have meant deleting a block the binding advisory mandates.
- **AC9 certified something narrower than its name.** — Recovery: AC9-STRONG, mutation-proven. —
  **Prevention:** the property/scope pairing above.
- **AC1 asserted a row count from before the PR's own row existed.** — Recovery: corrected to 12. —
  **Prevention:** re-derive plan-quoted counts; cross-check against the same plan's other sections.
- **The placeholder guard was vacuous.** — Recovery: case-insensitive + correctly scoped. —
  **Prevention:** for any character-class guard, feed it the literal it names and confirm it matches.
- **A mutation test reported PASS/PASS because the mutation never landed.** — Recovery: redone with a
  diff that sees the working tree. — **Prevention:** assert the mutation landed (`git diff --numstat`)
  before scoring any row; treat baseline-identical as UN-RUN.
- **Measured against a stale local `main`** (2 behind `origin/main`), listing six sibling files as
  mine. — Recovery: fetched, rebased, re-ran every AC against `origin/main`. — **Prevention:** always
  `origin/main`.
- **A markdownlint baseline probe returned 0 because the path was out-of-tree**, not because the file
  was clean. — Recovery: re-measured in-tree. — **Prevention:** a probe that can fail silently needs a
  known-positive control.
- **A literal shell pipe in a posture row's Notes made an 8-field row.** — Recovery: escaped. —
  **Prevention:** count pipes against a sibling row after any generated table row.
- **A nested backtick (MD038) and `#7815` at line start (MD025), both in my own review edits.** —
  Recovery: fixed; swept the whole diff for `^#[0-9]`. — **Prevention:** re-run the linter after review
  edits, not only after the implementation.
- **Five of seven precedent-cell citations broken by my own row insertion.** — Recovery: A13.1,
  content anchors, no new line numbers. — **Prevention:** after inserting a line, grep every artifact
  for citations into that file below the insertion point.
- **A7.1's provenance claim was false** — the citation predates the counsel recommendation by nine
  days, and that recommendation was explicitly deferred. — Recovery: A12; the surviving ground (the
  clause sits inside an ATTESTED balancing test) is stronger. — **Prevention:** for any "X implements
  Y" claim, check the dates in both directions.
- **The register asserted falsehoods about a named natural person**, and the divergence block
  undercounted three-vs-four. — Recovery: both corrected; consequences routed to #7812 and #7814. —
  **Prevention:** prose about populations needs a file that falsifies it.
- **`gh issue create` was denied for a missing `--milestone`, taking its inline heredoc down with
  it** — the hook rejects the whole Bash call, so the body file was never written. — Recovery: wrote
  the body with the Write tool first. — **Prevention:** already documented; never heredoc a body into
  the same call as a hook-gated command.
- **17 markdownlint errors in two new spec files**, where sibling spec files on `main` are clean. —
  Recovery: auto-fixed. — **Prevention:** lint new artifacts against the directory's norm, not against
  zero expectations.
- **Environmental, no defect:** the `scripts` shard exited `rc=4` REFUSED (a sibling full-gate run in
  another worktree, #7553) — nothing ran, so targeted suites stood in; and the `playwright` and
  `github` MCP servers failed to connect, neither needed.
- **Forwarded from the planning phase** (`session-state.md`): a premature Session Summary issued while
  a background sweep was still running (it then returned six stale cross-references); nine factual
  errors in the planner's own research, every one from paraphrasing a plausible mirror instead of
  reading the source; and a false statement inside the CLO's own Ruling 3, caught by two reviewers and
  corrected in addendum A1.

## Related

- `2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried.md` — the same class, one day earlier, on a different subsystem
- `2026-08-12-every-blocking-finding-was-the-defect-class-the-pr-existed-to-close.md`
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `2026-08-06-a-wrong-measurement-propagated-into-three-artifacts-and-my-fix-reproduced-its-defect.md`
