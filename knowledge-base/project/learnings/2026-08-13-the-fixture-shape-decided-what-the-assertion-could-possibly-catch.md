---
title: "The fixture's shape decided what the assertion could possibly catch"
date: 2026-08-13
category: best-practices
module: scripts/plugin-legacy-resolver-probe.test.sh
issue: 7490
pr: 7550
tags: [guards, vacuity, mutation-testing, fixtures, equivalent-mutants]
---

# The fixture's shape decided what the assertion could possibly catch

## Problem

Closing #7505's four guard-vacuity gaps meant writing assertions for code that had none.
Three were ordinary. The fourth — `redact_path` — exposed something sharper than a missing
test: **an assertion that could not have caught the bug no matter how it was written, because
of how every existing fixture was shaped.**

`redact_path` tries the project prefix *before* the home prefix. The code says why: a project
normally lives *under* the home directory, so a home-first substitution would consume it and
the project branch could never match. That ordering is load-bearing and it is commented as
such.

Every fixture in the suite builds `<root>/home` and `<root>/project` as **siblings**. Under
that shape both orders produce identical output. So a reviewer could have added an assertion
per site, per field, per status — dozens of them — and not one could have detected a swapped
prefix order. The gap was not in the assertions. It was in the fixture's topology.

## Root cause

A fixture instantiates *one point* in the space of shapes the code accepts. Assertions can only
discriminate between behaviours the fixture actually distinguishes. When the fixture collapses
two cases into one — siblings collapsing "project-first" and "home-first" into the same answer
— every assertion downstream inherits that blindness, silently.

This is the same family as the session's other findings but a distinct member. The others were
predicates that were *wrong*:

- a jq program that compiled only on the author's jq version;
- an unbound-variable lint that captured only the first name in `local a=1 b=2`;
- an AC asserting "`test-all.sh` is untouched" when it meant "this suite is not hand-registered".

Those are fixable by reading the predicate. This one is not visible in any predicate at all —
only in the fixture that feeds it.

## Solution

Add a fixture whose topology makes the two orders disagree, then mutate to prove it:

```bash
mkdir -p "$r/home/nested-project/.claude"
out="$(HOME="$r/home" bash "$PROBE" --json --redact \
  --home "$r/home" --project "$r/home/nested-project" ...)"
assert_jq "redact: a nested project is redacted as <project>, not swallowed by <home>" \
  "$out" '...' "<project>/.claude/settings.json"
```

Swapping the prefix order now fails with exactly the documented symptom —
`<home>/nested-project/.claude/settings.json`.

Two further disciplines this PR settled on:

- **Pin lists literally, never derive them from the source under test.** The site-chain check
  compares the probe's `--json` output against a hard-coded list of seven. Deriving that list
  from the probe's own `site_json` calls would make a *deletion* shrink both sides at once and
  pass. A second assertion pins the probe's declarations against the same literal, so an
  *addition* fails until someone updates the test deliberately. Cardinality alone is not
  enough either: a rename keeps the count, which is why the arms compare joined names.
  (Verified by hand during review. An earlier draft said a rename mutation lived in the
  suite; that was false — only a comment does.)
- **A floor must not route through the machinery it audits.** Both suites' anti-vacuity floors
  called `fail`, whose increment the exit status reads — so neutering `fail` silenced the rows
  *and* the floor. They now `exit 1` directly. But the floor alone is NOT sufficient, and
  review measured why: `cases` is incremented by the assert helpers, never by `fail`, so
  neutering `fail` in the real suite leaves `cases` at full value, the floor is satisfied, and
  the run exits 0 with failures silenced (`45 passed, 0 failed (48 assertions)`, RC=0). The
  meta-suite only ever exercised the conjunction *`fail` neutered AND `cases=0`*, which its own
  mutant-builder manufactures and no real edit produces. The arm that actually catches it is an
  accounting conservation check — `passes + fails` MUST equal `cases` — reported directly for
  the same reason as the floor. The detector was in the output the whole time: every survivor
  printed its own contradiction and nothing read it.

## Key insight

**Before writing an assertion, ask what the fixture makes indistinguishable.** A guard's
sensitivity is bounded above by the variety in its inputs, and that bound is invisible from the
assertion side — every test still passes, the count still climbs, the mutation matrix still
reads full. The question "is this asserted?" has a different answer from "*could* this be
asserted, given what I feed it?", and only the second one is about coverage.

The corollary is that mutation testing must mutate the *code*, not the assertions. Every real
finding this session came from breaking the implementation and watching whether anything went
red. Note what that does NOT license: the one mutant I concluded was unkillable turned out
to be killable, twice over — see below.

## I called a mutant equivalent twice, and it was killable both times

Removing `[[ -d "$dest/${PLUGIN_SUBDIR}" ]] || return 1` from `materialize_reference`
reddens nothing in the suite as shipped. I first claimed a new row (a commit with no
plugin subdir) killed it — it does not. I then claimed it was an **equivalent mutant**,
reasoning that `reference_list` checks `[[ -d "$REFERENCE_DIR" ]]` against the same path
a few lines later, so the two are redundant.

Review refuted that too, and the refutation is the interesting part:

- **With** the check, `materialize_reference` returns 1, `REFERENCE_DIR` stays empty, and
  control falls through to the **trees-API transport**.
- **Without** it, `REFERENCE_DIR` is set to a non-existent path and `reference_list`
  returns 1 before reaching the fallback.

Those are different observable behaviours, so the mutant is killable — and the suite
already owns the seam to kill it (`mk_curl_shim`, which serves `*/git/trees/*` from a
fixture). "No test can kill it" was false about machinery in the same file I was editing.

The lesson is not about this mutant. It is that **"equivalent mutant" is a claim requiring
proof, and it is the most comfortable possible conclusion** — it converts a gap in your
tests into a property of the code, at zero cost, with no command to run. I reached for it
immediately after a wrong kill-claim, which is exactly when a comfortable conclusion should
be least trusted. The discipline: before writing "equivalent", trace both branches to a
difference in OBSERVABLE output, and grep the test file for a seam that would discriminate
them. Both steps here would have taken a minute and both would have refuted me.

## Session Errors

1. **The redaction leak sweep over-reached on first run** — it failed on the managed-settings
   path. That default is a fixed system location (`/etc/claude-code/managed-settings.json`),
   byte-identical on every machine, disclosing nothing about the operator; it is correctly
   unredacted and is not one of the four categories redaction covers. The fixture was aiming
   `--managed` at a temp dir no production run produces, so the assertion failed on the
   harness's own artefact. **Prevention:** when a sweep asserts "nothing real leaks", check
   that every input the fixture supplies is one production actually supplies — otherwise the
   sweep tests the harness.

2. **Claimed a new row closed a surviving mutant without re-running the mutation.** It did not.
   **Prevention:** a kill-claim is a measurement; re-run the mutant after adding the row that
   supposedly kills it, and if it survives, say so.

3. **Set the new meta-suite's own vacuity floor one above its assertion count**, so the suite
   failed itself on first run (7 assertions, floor of 8). Harmless, and arguably the floor
   demonstrating it works — but the number should be derived by counting the arms, not guessed.

## Tags

category: best-practices
module: scripts/plugin-legacy-resolver-probe.test.sh
