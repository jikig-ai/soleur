# ADR-162 — What `ask` means on a harness that has no `ask` state

- **Status:** accepted
- **Date:** 2026-08-03
- **Extends:** [ADR-156](ADR-156-hook-stdin-is-model-controlled-and-untrusted.md),
  [ADR-157](ADR-157-a-hook-that-cannot-parse-its-input-asks.md)
- **Supersedes:** nothing. ADR-156 says it "must never be superseded, it may be
  extended"; this extends it to the second harness.
- **Issue:** #7173

## Context

ADR-157 fixed the `.claude` harness's posture: a PreToolUse hook that cannot
fully parse its input **asks**. It never continues silently and it never denies.

`.openhands/hooks/` mirrors three of those hooks — `guardrails.sh`,
`pre-merge-rebase.sh`, `worktree-write-guard.sh` — for a different runtime, and
that runtime's protocol has only **two** states:

| | `.claude` (Claude Code) | `.openhands` (OpenHands) |
|---|---|---|
| envelope keys | `.cwd`, `.tool_input.file_path` | `.working_dir`, `.tool_input.path` |
| block | `exit 0` + `permissionDecision: "deny"` | `exit 2` + `{"decision":"deny"}` |
| prompt the operator | `permissionDecision: "ask"` | **does not exist** |
| kill switch | `SOLEUR_DISABLE_HOOK_INPUT_ASK` | **does not exist** |

#7173 asked for this decision to be made deliberately rather than as a side
effect. Making it required first establishing what the mirror actually did,
which turned out not to be what its own comments claimed.

### What was measured

Two defects, both present in all three mirror hooks, both since fixed in the PR
that carries this ADR.

**A bypass.** Every raw extraction ran under `set -euo pipefail` with no failure
branch:

```console
$ printf '{"tool_input":' | bash .openhands/hooks/guardrails.sh
jq: parse error: Unfinished JSON term at EOF at line 2, column 0
  rc=5
```

Any document jq rejected killed the script at the first extraction — **rc 5, no
deny, no decision JSON, no incident row** — *before* the ADR-156 shape check
that exists to catch anomalous envelopes. A lone high surrogate in a **sibling**
field induces it while `.tool_input.command` stays a clean, fully-armed
`rm -rf $HOME`; OpenHands is Python, `json.dumps` re-emits `\ud800`, and the
document is valid to its parser and invalid to jq. The `.claude` side asks on
the identical payload.

Whether that was a silent bypass or a loud abort depended entirely on how the
OpenHands runtime treats a non-0/2 exit code. **This repo does not define that
invariant**, which is precisely the class of dependency ADR-156 forbids. The fix
below removes the dependency rather than resolving it.

**An availability failure.** The type conjunct read `$t == null`, but jq's
`type` returns the **string** `"null"`:

```console
$ echo '{}' | jq -r '(.tool_input? | type) as $t | "\($t == null)  \($t == "null")"'
false  true
```

So the comparison was unsatisfiable and the guard **denied every payload with an
absent or null `tool_input`** — on the harness with no `ask` and no recovery
path, while `.claude` parsed the same payloads cleanly. It also falsified the
mirror's own comment that the guard "fires only when the document PARSES and a
contracted field is the wrong TYPE" — those documents parse fine and carry no
wrong-typed field. That sentence was the foundation the convergence rationale
had been resting on.

## Decision

**The mirror splits by reason class. It does not map ADR-157's `ask` onto a
single OpenHands state.**

| reason class | `.claude` | `.openhands` | why |
|---|---|---|---|
| `nonstring` | ask | **deny** | No legitimate caller sends a non-string. |
| `unparseable` | ask | **deny** | Model-controlled and recoverable in-band. |
| `jq_missing` | ask | **fail open, pattern-scoped** (stderr + `exit 0`, unless the RAW document matches a protected pattern → deny) | See below. |
| `internal` | ask | **fail OPEN, loudly** (stderr + `exit 0`) | Our bug, never blamed on the payload. |
| `separator` | ask | **n/a — cannot arise** | The mirror does three independent per-field `jq -r` extractions. It has no RS-delimited multi-record encoding, so there is no record boundary to forge. This row becomes live only if a future change converges the harnesses onto the shared extractor. |

**Two corrections the review forced, both measured.** An earlier draft of this
table listed `separator` as a class the mirror *denies* and `internal` as
failing open *loudly*. Neither was true: `grep -c separator` over all three
mirrors returns 0, and the `internal` path fell through a fallback assignment
nothing branched on, so a broken shape program disarmed every guard with **no
stdout, no stderr and no record** — verified by breaking one token in the shape
program and feeding it an array `command`. `internal` now emits a stderr line
before failing open; `separator` is marked inapplicable rather than decided.

**Recoverability is an ASSUMPTION here, not an established fact.** Three rows
above say a deny is "recoverable in-band" because the reason string returns to
the agent. This repo does not establish that:
`knowledge-base/project/specs/openhands-portability/critical-unknowns.md`
still carries *"Verification needed: … Confirm PreToolUse blocking with JSON
output injects `additionalContext` into agent prompt."* The decision is sound
either way — a deny with an unread reason is still strictly better than the
abort-with-no-decision it replaced — but the recoverability argument rests on an
unowned runtime invariant, which is the dependency class ADR-156 exists to
forbid. It is recorded as an assumption with the probe named rather than
asserted.

**`jq_missing` must not deny, and the reason is ADR-157's, not a new one.**
ADR-157 rejected a fail-closed posture because *"the repair for a broken `PATH`
or a missing `jq` is itself a Bash call, which would also be denied."* That is
an argument from **self-referential repair**, not from hook count — a
misreading this ADR's first draft made and the review corrected. It transfers to
OpenHands unchanged and **bites harder**: this harness has no `ask`, no
operator-in-the-loop escalation, and no kill-switch equivalent. A deny on the
class that means "the tool needed to fix this is unavailable" blocks its own
repair with no way out.

The `unparseable` deny is the deliberate divergence from the mirror's previous
behaviour, and it is a **strict improvement over what it replaced**: not a
fall-through, but an abort with no decision at all.

**But `jq_missing` must not fail open UNCONDITIONALLY either, and the first
draft of this ADR did.** Review measured the consequence: on `origin/main` a
jq-less PATH produced rc 127 — undefined, whatever the runtime makes of it — and
the draft's blanket `exit 0` resolved that ambiguity *toward open*, turning
"remove jq" into a one-call disarm of every guard in the file. `rm -f
/usr/bin/jq` is not matched by the mirror's own `rm -rf` regex, so the chain
`rm -f /usr/bin/jq` → `rm -rf $HOME` ran clean.

The resolution is not a choice between denying everything and allowing
everything: **the raw document is still in hand when jq is gone.** The
`jq_missing` branch now matches `$INPUT` against the narrow set of patterns
whose guards are this hook's reason for existing (`rm -r`/`rm -f`, `git stash`,
`--delete-branch`, `git commit`) and denies on a hit. Measured: every repair
command the self-referential-repair argument depends on — `apt-get install jq`,
`export PATH=…`, `ln -s /opt/jq /usr/bin/jq` — matches none of them and still
passes. It is deliberately over-broad in the other direction; on a branch that
only executes when the parser is gone, a false deny is the correct error.

### Scope

This ADR decides the **protocol semantics** question #7173 raised. It does
**not** decide whether the two harnesses converge on one extractor. The mirror
keeps its in-place assertion, and the reason is recorded in
`.claude/hooks/README.md` rather than left as residue. Convergence would buy DRY
and three jq forks to one on a non-primary harness, and would pay for it with a
cross-tree fail-hard `source` — the riskiest single line in that change set,
and one whose own precedent in that file (`freeze-lock.sh`) is deliberately
fail-*soft* for reasons that do not apply to an input helper.

## Consequences

- The mirror no longer has a path where a model-controlled document produces no
  decision. Every reason class the mirror can **reach** now has a defined
  outcome; `separator` is inapplicable by construction (see the table).
- The three divergence classes are asserted by
  `.claude/hooks/pre-merge-rebase-parity.test.sh`, which is where they belong:
  that suite's header records that silent divergence between the two harnesses
  has already happened twice, both times undetected because nothing executed the
  comparison.
- `unparseable` denying is a behaviour change on the mirror. It is bounded: the
  class is reachable only by a document jq rejects, and the agent can re-send.
- The dependency on OpenHands' non-0/2 exit-code semantics is **removed**, not
  resolved — but establishing that took three more fixes than the first draft of
  this ADR assumed, and the draft asserted it before they existed. Review
  measured `welcome-hook.sh` exiting **rc 5** on a malformed document,
  `guardrails.sh`'s `git worktree list` exiting **rc 128** from a non-git cwd on
  a *clean* payload, and the same shape in `pre-merge-rebase.sh`. All three are
  now guarded. The claim is a **measured property over a probed matrix**, not a
  proof over all inputs; the matrix is 5 hooks × 9 payload classes (malformed,
  lone surrogate, array command, absent `tool_input`, benign, empty stdin,
  non-object root, deny-path, and jq-absent), all landing in {0, 2}. Re-derive
  with that matrix rather than trusting this sentence.
- **Not decided here:** extending the type assertion to the four **gating**
  `.claude` hooks (#7173's other half — the six genuinely-advisory hooks and
  `security_reminder_hook.py` are exempt with per-hook reasons in the README,
  which is a different disposition and should not be collapsed into "the ten
  advisory hooks"). That needs a widened jq program and a
  responder-set change whose design has open findings, and it needs a probe of
  Claude Code's `allow`-vs-`ask` resolution order that cannot be run without a
  live hook registration. Tracked separately; see the follow-up issue linked
  from #7173.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| **Deny uniformly on helper rc 1** (the first draft) | A behaviour change on **three of five** reason classes, with a hard brick on `jq_missing` where the deny blocks its own repair. Rejected on ADR-157:115's rationale. |
| **Keep the pre-existing "transport failure falls through"** | Measured false. There was no fall-through — the script aborted at rc 5 with no decision, and the `unparseable` branch it would have taken is unreachable code (it requires the shape program to fail on a document the three simpler extractions already parsed). |
| **Converge both harnesses on `lib/hook-input.sh`** | Requires a cross-tree fail-hard `source` on a harness whose only existing cross-tree source is deliberately fail-soft. Buys DRY on a non-primary harness; deferred, with the reason recorded in the README so it does not become silent residue. |
| **Probe the runtime's non-0/2 exit semantics, then decide** | Would make the decision depend on an invariant this repo does not own — the thing ADR-156 exists to forbid. Removing the dependency is strictly better than measuring it once. |
