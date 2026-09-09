---
title: "Every defect was in the guard, and the command it prescribes defeated it"
date: 2026-09-09
issue: 7947
pr: 7975
category: security-issues
tags: [guards, credentials, browser-automation, mutation-testing, measurement, vacuity]
---

# Every defect was in the guard, and the command it prescribes defeated it

#7947 shipped three controls against one hazard: a browser accessibility snapshot
serializes the **value** of input fields, including a value the acting agent
never supplied. The multi-agent review returned 19 P1s. **Every one was inside
the three guards. None was in the code they protect.**

## The measurement gate is what made the design possible, and it falsified the issue twice

Phase 0.1 was a hard gate: probe both surfaces against a synthesized page before
writing anything. Three results, each contradicting something asserted before
anything was measured:

- **Neither surface serializes `type=`.** A password box, a readonly token box
  and an email box all render as `textbox`. The plan's structural "is this a
  password input" predicate had nothing to read and was unimplementable; the
  accessible NAME is the only signal, which is a ceiling, not a shortcut.
- **`agent-browser` already masks `type=password`.** The one node it leaks is
  the readonly `type=text` credential panel — the class with a recorded in-repo
  incident. A guard keyed on "password" would have missed the only thing that
  surface leaks.
- **"Use a screenshot instead" is false** for that same panel, which the browser
  renders in clear. The issue's own remedy leaks the one class that has actually
  fired here.

Cost: about twenty minutes and a `python3 -m http.server`. Without it the PR
ships a predicate that cannot work and advice that leaks.

## The sharpest defect: the guard's prescribed command defeated the guard

The approved form is `agent-browser snapshot -i 2>&1 | python3 <redactor>`. That
`2>&1` merges any diagnostic line ahead of the JSON payload, which defeated the
redactor's whole-stream `startswith` JSON detection — so the credential passed
through **verbatim at exit 0**, on the exact shape every agent is steered onto.

The plan had reasoned about `2>&1` carefully, in the OPPOSITE direction (whether
stderr could reach the transcript un-redacted). The direction it did not consider
was the one that mattered.

**Generalisable:** when a guard prescribes a command shape, run the guard against
that shape. The prescribed form is the highest-traffic input it will ever see and
the one least likely to be in the fixture set, because it reads as the safe case.

## A document-scoped anchor is not a routing guarantee

The lint's stated property was "no committed instruction directs an unrouted
snapshot." Its implemented predicate was "the string `redact-a11y-snapshot`
appears somewhere in this file." Those are different properties, and the gap was
live: one mention exempted **26 unrouted instructions across five shipped files,
19 of which the runtime hook DENIES.** The plugin shipped commands its own guard
blocks, with the required check green — and because the PR *added* that mention
to each browser skill, it turned the guard off for exactly the files it was
written for.

Worse, the compliance record asserted the stronger property. A legal cell
describing a technical measure must describe the measure that exists.

Two corollaries worth carrying:

- **A lint narrower than the runtime gate is teeth for a different rule.** The
  hook denies every unrouted snapshot unconditionally; the lint narrowed by auth
  context, so `feature-video/SKILL.md` shipped two commands its own hook blocks
  with no CI signal. Align the corpus rule with what the runtime actually
  enforces, or say plainly that they differ.
- **Requiring an inapplicable remedy makes a guard manufacture its own
  compliance.** Four documents describing Playwright-MCP steps were given an
  `agent-browser` shell pipe as the remedy. An MCP tool result is not a shell
  stream, so those blocks' only functional effect was inserting the anchor string
  that turned the lint green. Where routing is impossible, the honest control is
  **disclosure**, named as disclosure.

## On a guard PR the verification is the least-audited surface — and it recurs

Round 1's fixes introduced two new defects: a role (`textarea`) silently left the
guarded set while I was refactoring the child-role handling, and the repaired
JSON arm gained a fresh fail-open on an envelope truncated before its key. Both
were green.

The same shape hit the anti-vacuity floor **twice**: my first floor keyed on the
post-archive-filter file list and red-lined a legitimately empty repo; the fix
for it, applied to a second population, made the identical mistake. A population
floor must distinguish **empty** from **absent**. The pre-existing C3 case caught
both attempts, which is the argument for not weakening an inherited test when
your new gate trips it.

**A mutation battery is bounded by the axes it edits.** Mine reported 8/8 twice
and was silent on: dispatch (a stubbed `assert_preserved`, and a MISROUTED
`assert_redacted` taking the wrong branch and then calling the correct-looking
helper — counters reconcile, floor satisfied, over-redaction detection off in one
line), member cardinality, fixture direction, fixture **path shape**, and
population growth. The instrument self-test one level up cannot see a helper that
OWNS a verdict; each such helper needs a control driving it with an input it MUST
reject.

**Fixture path shape is a coverage axis.** Every lint row passed an absolute
`mktemp` path while CI runs full-scan over relative ones, so the rule could have
been disabled on the only path CI uses with the whole suite green.

## Instrument yields are disjoint; the cheapest one is the best

On this PR: `shellcheck` found a dead variable, the repo lints found three
things, `semgrep` (153 rules) found none, the six-agent panel found 19 P1s — and
the single highest-value check took two minutes:

**Write the trivial implementations that pass your own suite.** Passthrough,
redact-everything, always-exit-2, always-allow, always-deny. A suite of
all-must-FAIL rows cannot distinguish a working guard from one that rejects
everything, and the must-PASS rows are what catch the over-aggressive stub.

## Placement decides whether a guard ships at all

`${CLAUDE_PLUGIN_ROOT}` resolves into the *installed plugin*, so a hook under
`.claude/hooks/` is repo-local and reaches no customer. The enforcement had to
live in `plugins/soleur/hooks/`; its suite stays in `.claude/hooks/` because that
is the auto-globbed suite path. The same reasoning applies to every path the
guard PRINTS: a repo-relative remedy resolves on no customer machine, so the
operator gets `can't open file` and the only remaining move is the screenshot the
same message says is unsafe.

## Session Errors

**`markdownlint` absent in the worktree blocked two commits, and I had been using
the unpinned `npx markdownlint-cli2` form.** The `markdown-lint` hook refuses an
npx fallback by design (#7927) — an unpinned binary is the defect it exists to
close. Recovery: `npm install --ignore-scripts` in the worktree.
**Prevention:** run `npm install --ignore-scripts` at worktree creation, and use
`./node_modules/.bin/markdownlint` from the first invocation.

**My anti-vacuity floor red-lined a correct repo, twice.** First keyed on the
post-archive-filter list; the fix, applied to a second population, repeated it.
**Prevention:** a population floor must distinguish "the directories exist and
hold nothing" from "this repo has no such directories" — key on discovery, and
run the existing suite before believing a new gate.

**jq detection keyed on `command -v`.** The failure mode is jq present and
exiting non-zero, which passes a presence check and then fails identically to
absence. Caught by the test row I had just written for it.
**Prevention:** detect an unusable dependency by RESULT, never by presence.

**Making the accessible name optional crashed on every unnamed node.** A real
snapshot is full of `- generic [ref=e1]:`.
**Prevention:** when relaxing a regex group to optional, grep the emit sites for
unguarded uses of that group in the same edit.

**The probe HTTP server survived my kill: I recorded `$!` from a `setsid`
wrapper, not the python child.** **Prevention:** for a backgrounded server,
resolve the owner by port (`ss -lptn 'sport = :N'`) rather than trusting a
recorded PID.

**A 20-day-old orphan `agent-browser` daemon, whose `cwd` resolved to a DELETED
worktree, wedged the CLI for the whole session.** Every invocation failed
`Resource temporarily unavailable (os error 11)`; it survived SIGTERM and needed
SIGKILL plus clearing `/tmp/agent-browser/*`. Nothing in the error names the
cause. **Prevention:** filed as its own issue — a stale daemon from a reaped
worktree is inherited by every later session on the machine.

**I inserted prose blocks inside nested and numbered lists twice**, breaking
markdown structure. **Prevention:** after inserting a block near a list, run the
pinned `markdownlint` on that file before moving on.

**The MCP-gap disclosure marker broke across a line wrap**, so the guard checking
for it went silently green while the disclosure was present to a human reader.
**Prevention:** any prose marker a guard greps must be whitespace-tolerant, or a
reflow disarms it while it keeps looking alive.

**One `Edit` call used a wrong path and a placeholder.** Corrected in the same
turn; the tool's identical-string check caught it.
**Prevention:** construct worktree-absolute paths from a variable, not by hand.

**Two review rounds found 19 P1s in my own guards, and round 2 found two defects
introduced by round 1's fixes.** **Prevention:** on a guard-shaped PR, review the
new ASSERTIONS before the new code, and re-run the deterministic lints after each
guard-shaped commit rather than once at session start — they only fire on new
code, so a session-start run measures nothing.
