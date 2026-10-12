---
title: "A text grep over a grammar is never closed — pin the canonical form by negation, and verify every claimed edit landed before committing"
date: 2026-10-12
category: workflow-issues
module: apps/web-platform/infra/journald-config.test.sh + scripts/followthroughs/inngest-provision-rehearsal-capture.sh (#9963, PR #10128)
issues: [9963]
tags: [guard-contracts, text-grep, canonical-form, mutation-testing, eval-escaping, fix-round]
---

# The guard's window was narrower than the property — three times running

## Problem

PR #10128 pins that a `SOLEUR_SYSTEMD_JOURNALD_CONTROL` row is emitted
unconditionally, exactly once, with argv `logger -t systemd -p err`, and that
`systemd` never enters a journald exact-tag allowlist. Every pin was written as
a **text grep over a grammar** — and every one was escaped by review:

- A keyword-list unconditionality check (`exit`/`if`/`fi` between the emits)
  missed `return`, mid-line `; if`, indented `if`/`fi` pairs, brace groups,
  `&&` continuations, `<<'X'` heredoc swallows, `>` redirects, suffix code on
  the emit line, openers before the scan window with closers after it, and
  `exit`/`kill` *above* the window entirely.
- A `-t systemd -p err` substring pin matched the pair quoted inside the
  message, a `-t doppler` emit carrying the literal, trailing `--socket`
  flags, and an embedded full-argv forgery.
- A `SYSLOG_IDENTIFIER.{0,8}systemd` serialized-fragment pin matched
  `=`-prose, `SYSLOG_IDENTIFIER_X` suffix keys, `systemd-journald` prefixes,
  doppler/webhook payload quoting, and marker-less rows.
- An `include_matches.SYSLOG_IDENTIFIER` dotted-literal pin missed every
  TOML-equivalent spelling: whitespace around the dot (either side), quoted
  keys, inline tables (single AND multiline), `[sources.X.include_matches]`
  sub-table bodies, and unicode-escaped members.

The structural cause was the same each time: **the guard enumerated spellings
of what it forbade, while the escape lived in spellings of the grammar it
didn't list.** A regex over text cannot close a grammar-shaped property.

## What worked

Four moves closed the class:

1. **Canonical-form negation.** Instead of listing forbidden spellings, pin
   that every comment-stripped occurrence of the token lives on ONE canonical
   line form (`include_matches.SYSLOG_IDENTIFIER = [`). Whitespace, quoted
   keys, inline tables, sub-tables, VRL assignments, and merge-literal forges
   are all "not canonical" — the pin survives spellings nobody enumerated.
   (9963i)
2. **Closed-form set pins.** For "exactly N code lines between A and B", count
   non-comment code lines and require == N — don't list forbidden constructs.
   Any new line shape fails the count. (9963e REGION_CODE/TAIL_CODE)
3. **Own-field binding.** The control count was hardened from text fragments
   to `jq .raw | fromjson | .SYSLOG_IDENTIFIER` — read the field, not the
   serialization. A payload quoting the pair can no longer forge it.
   (ADR-192 invariant I-2)
4. **Discrimination witnesses.** A `--since` arm that "passes either way"
   proves nothing — the fixture needs a row that fails ONLY when the bound is
   dropped (non-iid-joinable `Failed to start` row inside the fallback
   window), plus a second arm asserting the failure actually happens.

## Session Errors

**Commit message claimed edits a mid-aborted batch never applied**

- The python batch died at an `assert old in s` (row-iv escape level); the
  r-since edit later in the script never ran, but the commit message listed it.
  git-history review caught it at round 2.
- **Prevention:** a multi-edit script that aborts mid-way must either be
  idempotent-restartable or produce a per-edit landed/not-landed report —
  and the commit message gets written AFTER a `git diff` re-read of every
  claimed site, not before.

**`$`-expansion inside eval'd assert strings**

- `\"$PROBE_BODY\"` (unescaped `$`) injected the probe body INTO the eval —
  its quotes broke out and `http_code` hit set -u. `match($0` unescaped became
  the script path, producing a vacuous PASS on 9963l. `""` inside the eval'd
  awk was eaten (`sub(...,,src)`).
- **Prevention:** inside an assert's double-quoted condition, every `$` meant
  for eval-time must be written `\$`, and awk programs with `$0`/`$1`/`""`
  belong in pre-computed shell variables at file level, never inside the
  eval'd string. Precompute; assert the variable.

**Assert description text executes**

- `$(date -u +%s)` inside the assert title evaluated at print time; a
  backtick-quoted `;`/`&`/`|` list ran as command substitution.
- **Prevention:** assert titles are still double-quoted strings — no `$(` or
  backticks in prose either.

**Escape-level arithmetic needs a round-trip guard, not counting**

- Three attempts to hand-count `\\\\\\"` for an inner-JSON-escaped fixture
  row. The fix was to printf-append the row AND add a python `json.loads`
  round-trip that asserts the inner object decodes with the intended field.
- **Prevention:** never ship a hand-escaped fixture that hasn't been decoded
  back to the intended structure; the decode IS the fixture's contract.

**Floor placed mid-suite**

- `MIN_TOTAL` sat between assert blocks — it fired at 96 before the last 3
  arms ran.
- **Prevention:** the floor is the LAST statement before the results block,
  and its constant gets re-derived from `grep -c '^assert '`, not remembered.

**`10#_win_n` arithmetic**

- `10#` binds the literal following text, not the variable — `10#${_win_n}`.
  And any `[0-9]+`-validated integer is still an octal hazard (`08` crashes
  `$(( ))`) — `10#` belongs on every derived arithmetic.
- **Prevention:** arithmetic on parsed numerics gets `10#${var}` by default;
  add a leading-zero test arm when the input is user/flag-shaped.

**Affected-shard capacity contended**

- `CAPACITY_CONTENDED` (3-4 sibling worktree runs, ~2h deep); a queued run
  exited silently with an empty log.
- **Prevention:** check `--capacity` BEFORE queuing; a queued run that dies
  produces nothing to cite — record the earlier drained run + focused suites
  as evidence instead of pretending the shard ran.

## Prevention (workflow-level)

- Mutation-verify every pin the same session it lands: the seats' escape
  class (wrap-around, mid-line, alternate-spelling) is cheaper to probe as a
  live mutant than to reason about. Every pin added this PR was only trusted
  after its named mutants went red.
- For grammar-shaped properties, write the pin as canonical-form negation or
  a set-size pin FIRST — enumerating forbidden spellings is the default that
  always loses.

## Cross-references

- ADR-192 invariant I-2 (no marker predicate satisfiable by attacker-influenced rows)
- ADR-117 (unconditional emitter invariant)
- ADR-286 (the #9963 journald mechanism record)
- 2026-10-12-a-gc-check-whose-claimants-include-its-own-definitions-is-vacuous (sibling same-day, same canonical-form lesson)
