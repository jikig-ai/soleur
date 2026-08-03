# ADR-158 — PreToolUse hooks may rewrite tool input, under a single-rewriter invariant

- **Status:** Accepted
- **Date:** 2026-08-03
- **PR:** #7167
- **Issue:** #7165
- **Related:** [ADR-156](./ADR-156-hook-stdin-is-model-controlled-and-untrusted.md) (the trust
  boundary this reads across), [ADR-157](./ADR-157-a-hook-that-cannot-parse-its-input-asks.md)
  (what a hook does when it cannot parse — this ADR carves the rewriter exception),
  `.claude/hooks/grep-rewrite.sh`, `.claude/hooks/UPDATED-INPUT-PAYLOAD-SHAPE.md`,
  `.claude/hooks/README.md` (§Hook contract, §Escape-hatch inventory)
- **Refuted cost models:** see
  `knowledge-base/project/learnings/2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md`
  — three pattern-cost heuristics were measured and refuted there. They are **linked, not
  restated**; the point of this ADR is the authority, not that history.

> **Ordinal.** Planned as ADR-155. Renumbered to 158 at implementation time: ADR-155, ADR-156 and
> ADR-157 all landed on `origin/main` between plan approval and this branch's rebase.

## Context

Claude Code's shell snapshot installs a bash **function** named `grep` that re-execs the `claude`
binary with `argv[0]=ugrep`. For patterns whose cost depends on literal reachability, ugrep built a
DFA that reached **9.5 GB RSS in 171 s at 99% CPU** against a single 21 kB file, froze a 31 GB
desktop, and killed six concurrent sessions (#7163).

Every guard this repo has is a **deny** gate. Denying the pathological patterns was tried first and
abandoned: three successive cost models were measured and all three were wrong in *both*
directions — denying UUID, ISO-timestamp and conflict-marker regexes that cost ~7 MB, while
allowing genuine blowups. The decisive refutation is that the same pattern with the same bound
product costs 7 MB or 1.67 GB depending only on whether its literal **occurs in the subject**,
which no static analysis of the command can know.

So the fix cannot be a decision about the command. It has to be a change to *what the command
runs* — which is an authority no hook in this repo had.

## Decision

**A PreToolUse hook MAY rewrite `tool_input`**, bounded by the clauses below. This ADR grants the
authority, not merely its first use.

1. **Single rewriter.** At most **one** hook source may emit `updatedInput`. Two rewriters for the
   same call have undefined precedence and one rewrite is silently discarded. Enforced by a
   one-entry allowlist in `.claude/hooks/hookeventname-coverage.test.sh`; a second goes RED
   pointing here.
2. **Never emit `permissionDecision`.** Not at any depth, and no top-level `decision` / `continue`.
   An `allow` from this hook would bypass the permission system for every Bash call carrying a
   `grep` substring — measured at roughly half of them.
3. **Build from the whole `tool_input`.** `updatedInput` **REPLACES** `tool_input`; it does not
   merge (measured — see below). Emitting only the changed key silently drops `timeout`,
   `run_in_background`, `description` and `sandbox`.
4. **Idempotent.** Applying the rewrite to its own output must be a fixed point.
5. **Fail open at `exit 0`.** A PreToolUse hook exiting non-zero blocks the call. A rewriter runs
   on 100% of calls, not just the ones it acts on, so every exit path is 0 and the worst failure it
   can produce is "no rewrite happened".
6. **Permission matching happens on the ORIGINAL command.** Measured. Rewriting cannot be used to
   dodge a deny rule, and cannot be used to satisfy an allow rule either.
7. **A rewriter does not ASK.** [ADR-157](./ADR-157-a-hook-that-cannot-parse-its-input-asks.md)
   requires a hook that cannot parse its input to escalate. That rule protects *guards*: a
   disarmed guard is a missing safety check. A disarmed rewriter is a missing optimization, so
   escalating would spend an operator prompt on a non-event. The fault is still recorded — the
   shared helper emits `hook-input-<reason>` carrying `hook=grep-rewrite`.

### The mechanic

The hook prepends a `grep()` redefinition and leaves the command **byte-identical**:

```
grep(){ …command grep… }; <original command, untouched>
```

Bash resolves the name at execution time. Nothing is parsed, so nothing can be mis-parsed.

## Measurements

Measured 2026-08-03 in an isolated `claude -p` (2.1.220) against a throwaway `--settings` file;
full evidence in `knowledge-base/project/specs/feat-7165-grep-rewrite-updatedinput/`.

| Question | Result |
|---|---|
| Does `updatedInput` apply with no `permissionDecision`? | yes |
| Does a sibling `deny` still beat `updatedInput`? | **yes — deny wins** |
| Does `updatedInput` merge or replace `tool_input`? | **replaces, wholesale** |
| Is the rewritten command re-submitted to PreToolUse? | **no** — one invocation per call |
| Do permission rules match pre- or post-rewrite? | **pre** (the original) |

The replace-not-merge result is the one that shapes the implementation: a hook emitting
`updatedInput: {"command": …}` against a call carrying `run_in_background: true`, `timeout: 45000`
and a `description` dropped all three, and the command ran in the **foreground**.

**Corpus replay.** 12,057 unique real Bash commands from session transcripts. Every rewrite differed
from its original by exactly the prefix, byte-for-byte, remainder unchanged. **Zero commands were
corrupted.** 4 (0.03%) were *declined* — each contains a literal RS byte (0x1E), the field separator
`lib/hook-input.sh` uses, so the shared parser correctly reports a boundary forge and the hook fails
open. All four are fixtures from the PR that authored that parser. A decline leaves the command
untouched; it is a missed optimization, not a defect.

**Rewrite-inertness.** 144 (sibling hook, command) pairs: the original and the prefixed form produce
**identical decisions** from every other PreToolUse Bash hook. No sibling's trigger regex contains a
`grep` token, so nothing flips — this measurement makes that an enforced property rather than an
accident.

## Accepted divergences

The shim passes `-G --ignore-files --hidden -I --exclude-dir={.git,.svn,.hg,.bzr,.jj,.sl}` to
ugrep. The replacement passes `-I --exclude-dir={…the same six…,node_modules,dist,.next}` to GNU
grep. `-G` is GNU grep's default and `--hidden` names behavior GNU grep already has, so both drop as
no-ops. Measured on a synthesized tree containing `.git`, a binary file, a gitignored dir and hidden
files:

1. **`.gitignore` is no longer respected.** `--ignore-files` has no GNU grep equivalent. Gitignored
   files outside the excluded dirs now appear in results. **This includes files a repo hides on
   purpose** — `.env`, local credential files, build logs — whose contents could previously not
   surface in a recursive grep and now can. Accepted: GNU grep's behavior is the POSIX-standard one
   and the one the flags on screen describe, whereas the shim's silent `.gitignore` filtering was
   itself a surprise that has bitten this repo before (`grep -z` no-op, 2026-05-29). Operators who
   need the old scoping should pass an explicit path or `--exclude`.
2. **`node_modules`, `dist` and `.next` are now always excluded**, even when not gitignored — where
   ugrep searched them if `.gitignore` did not list them. This is the D3 trade and it is what buys
   back (1): re-measured on this repo (101,104 files, 87,988 under `node_modules`), a recursive grep
   costs **~3,600 ms** without these excludes and **~590 ms** with them — **~6.0×** against a
   ~230 ms run-to-run spread. (The plan claimed 12.9×; the "with" figure reproduces exactly, the
   baseline differs by machine state. The decision is unchanged.)
3. **A bare directory argument whose basename is an excluded name returns nothing.**
   `grep -r PAT node_modules` is empty; `node_modules/`, `node_modules/pkg` and an explicit file
   path all work. For the six shim excludes this is already today's behavior; it is new only for the
   three build dirs. Workaround: a trailing slash.
4. **Path rendering.** ugrep prints `src/a.ts` where GNU grep given `.` prints `./src/a.ts`.
   Cosmetic, but real for a script parsing the output.

Bypass-flag calls diverge in none of these ways: all 12 of the shim's bypass arms are mirrored
byte-exact and receive `command grep "$@"` with no injected flags — exactly what they receive today.

## Alternatives considered

- **Deny the pathological patterns.** Refuted three times by measurement; see the linked learning.
  The cost is not a function of the pattern alone.
- **Parse the command and splice `command grep` over each `grep` token** (this plan's v1). A
  5-agent panel reproduced **seven** corruption failures, four of which break commands that work
  today: quoted data containing the word, `git grep`, `pgrep`, `xargs grep`, brace expansion,
  heredoc bodies, and byte-vs-character offset desync. It also could not fix `G=grep; $G …` or
  `eval "grep …"`. The prefix design dissolves all seven — the command is never edited — and solves
  both residuals for free, because those forms resolve the name through the shell too.
- **A memory cap (cgroup `memory.max`) instead.** Complementary, not a substitute, and tracked
  separately in #7166. With the rewrite landed the residual coverage gap it was scoped to close no
  longer exists, so it shrinks from "covers the gap" to defense in depth: a *bound* rather than a
  lexical bet.
- **Observe-only permanently.** The soak mode is retained behind
  `SOLEUR_GREP_REWRITE_OBSERVE=1`, but shipping it as the steady state leaves the freeze
  reachable.

## Consequences

- Roughly half of all Bash commands carry a ~450-byte prefix. Accepted; transcript noise only.
- A command that inspects `type grep` or defines its own `grep` sees ours. Ours is overridden by any
  later user definition. Vanishingly rare.
- **Kill switch:** `SOLEUR_DISABLE_GREP_REWRITE=1`, read as the hook's first executable statement,
  before any subprocess or library sourcing. Recorded in §Escape-hatch inventory.
- Telemetry ids are `grep-rewrite-*`, exempted from the weekly aggregator's orphan gate — an
  untagged id exits it 5 and, on the post-write path, skips jsonl rotation.
