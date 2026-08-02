# ADR-156 — A hook that cannot fully parse its input asks

- **Status:** Accepted
- **Date:** 2026-08-02
- **PR:** #7168
- **Issue:** #7164
- **Related:** [ADR-155](./ADR-155-hook-stdin-is-model-controlled-and-untrusted.md) (the trust
  boundary this implements), [ADR-070](./ADR-070-l3-phase-tool-scoping-two-tier-fail-open.md) (the
  only prior sanction of fail-open in a hook, and the complement of this case),
  `.claude/hooks/lib/hook-input.sh`, `.claude/hooks/README.md` ("Parsing hook input"),
  `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` (the probe establishing `ask` is honored)
- **Supersedes:** the silent-absorb reading of
  `knowledge-base/project/learnings/2026-03-18-stop-hook-jq-invalid-json-guard.md` — see below

> **Ordinal.** ADR-156 is the next free ordinal after ADR-155 against a freshly fetched `origin/main`,
> verified at `/work` time. Provisional until `/ship` re-checks at merge.

## Context

[ADR-155](./ADR-155-hook-stdin-is-model-controlled-and-untrusted.md) requires a hook to verify the
input invariants it depends on. It does not say what happens when verification fails, and that
question turned out to carry the whole design.

The ten `eval` hooks already had an answer, and it is the second defect in #7164:

```
... 2>/dev/null || echo 'COMMAND="" TOOL_NAME=""'
```

On a parse failure every field is emptied. Every guard in the file is keyed on those fields, so
every guard no-ops, the hook exits 0, the tool proceeds, and **nothing is recorded**. The direction
is defensible — a `PreToolUse` hook that denies every command on a `jq` hiccup bricks the session
with no way out, because the fix is itself a Bash call. The defect is that the disarm is invisible.

An earlier iteration of this design tried to keep fail-open and make it loud: emit an incident, cap
the input size, scrub hostile bytes, and bound the resulting oracle with a per-session counter. Six
review passes falsified most of it. The decisive objection was that "loud" was not achievable on
that channel: a `PreToolUse` hook is operator-blind — stdout is consumed by the harness, stderr is
usually swallowed, and the headless log has no reader — so the operator whose gates had just gone
dark learned nothing *at the time it mattered*.

## Decision

**A hook that cannot fully parse its input emits `permissionDecision: "ask"`. It never continues
silently, and it never denies.**

| Input | Outcome |
|---|---|
| parses **and** every contracted field is a string | run the guards, values byte-exact |
| anything else | **`ask`**, with a `reason` classifier, plus an incident row |

"Anything else" is: a non-string contracted field, a non-object `tool_input`, a non-object root, a
value carrying the field separator, an unparseable or truncated document, a lone surrogate, an
oversize payload, `jq` missing, or our own jq program broken.

`ask` is what makes the rest of the design collapse to something small. It is not `deny`: the
operator can approve and proceed, so nothing bricks — which was the *only* reason fail-open was
needed. Once `ask` covers every failure, the size cap has no denial-of-service left to mitigate, the
per-session counter has no oracle left to bound, and the surrogate scrub has no silent disarm left
to prevent. All three were cut.

`ask` is also **synchronous and in-band** — the one channel a `PreToolUse` hook provably owns. It is
therefore the primary report, and the incident row is the forensic record, not the alert.

Three supporting clauses:

- **Designated responder.** `guardrails.sh` emits the `ask`; the other hooks report and exit 0.
  All-emit would turn a persistent condition (`jq` missing) into an unrecoverable loop, since 18
  hooks fire per Bash call and repairing `PATH` is itself a Bash call. This makes `guardrails.sh`
  load-bearing for the others, so the invariant "every `PreToolUse` matcher containing a migrated
  hook also contains `guardrails.sh`" is asserted against `.claude/settings.json` by the contract
  test.
- **Kill switch.** `SOLEUR_DISABLE_HOOK_INPUT_ASK=1` suppresses escalation only, never parsing.
  Without an in-band escape hatch there is no recovery if the posture proves noisy. Precedent:
  `SOLEUR_DISABLE_SESSION_STATE`.
- **Telemetry carries no payload content.** Field name, JSON type, and length. The jq program emits
  failure-path values **empty by construction**, so no rendering of attacker content exists to log.
  This is structural, not a promise: an earlier draft logged a `tojson` rendering while asserting the
  opposite, which would have written `["curl","-H","Authorization: Bearer sk-…"]` to disk.

## What this supersedes

`2026-03-18-stop-hook-jq-invalid-json-guard.md` established that a hook must **absorb** a jq failure
rather than crash. That remains correct and is not reversed. What is superseded is the reading that
absorbing implies staying silent: a hook may absorb the error, and must then announce that it did.
The learning is a Stop-hook finding being over-applied to a blocking `PreToolUse` gate.

[ADR-070](./ADR-070-l3-phase-tool-scoping-two-tier-fail-open.md) is the only prior sanction of
fail-open in a hook and is the **complement** of this case, not a precedent for it: it governs an
*additive advisory* hook, where failing open costs a hint. Here failing open costs every delete,
commit, and stash guard on the call.

## Known limitations

- **A scrubbed value is a different value.** Neutralizing a lone surrogate and running the guards
  armed was measured and rejected: `git ␦ stash` does not match the stash guard, so the hook would
  have reported "handled" while allowing the command. Surrogates therefore ask. If surrogate rows
  actually appear in telemetry, the upstream emitter is the bug to file.
- **Reachability of the original RCE stays open.** Whether the harness type-validates `tool_input`
  before dispatch could not be established from inside this repo. That is precisely ADR-155's
  rationale and is not resolved here; it must be neither upgraded to "confirmed exploitable" nor
  downgraded to "theoretical."
- **`ask` is honored** per a CC-2.1.142 probe recorded in `DEFER-DECISION-PAYLOAD-SHAPE.md`, and is
  in production use today in `kb-domain-allowlist-guard.sh` (verified live on CC 2.1.220). Re-probe
  on a CC **major** bump. The envelope must carry `hookEventName` in the same object or CC silently
  ignores it and the tool runs.
- **Non-object `tool_input`** is classified `nonstring` and asks. No legitimate tool shape observed
  in this repo sends one; if an MCP tool is found that does, asking is still the right outcome, but
  the finding belongs in this ADR.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **Fail closed** (deny on parse failure) | **Rejected.** Bricks the session with no in-band recovery — the repair for a broken `PATH` or a missing `jq` is itself a Bash call, which would also be denied. |
| **Fail open with a loud incident** | **Rejected.** Not achievable as "loud": a `PreToolUse` hook is operator-blind at the moment of the fault, so the operator whose guards just went dark learns nothing until an aggregator runs later. This is the shape the ten hooks already had. |
| **Coerce non-strings with `tojson` and continue** (the issue's first suggestion) | **Rejected — falsified by measurement.** Closes the RCE and leaves every anchored guard evaded: the coerced `["git","stash"]` matches no guard regex. Would have closed #7164 on a false negative. |
| **Per-field `jq -r` extraction** (the OpenHands mirror's shape) | **Rejected.** N forks per hook per call, reverting the single-fork optimization of #2253 across 20 hooks — and it still needs the type assertion, so it buys nothing. |
| **NUL separator with `--raw-output0` / `mapfile -d ''`** (the issue's second suggestion) | **Rejected as written.** jq drops NUL from string values and cannot emit it from a literal; `--raw-output0` needs jq ≥ 1.7 and `mapfile -d` needs bash ≥ 4.4. Both delimited-read forms measured ~2.5× slower at 200 KB. The direction — drop `eval` — is adopted; the mechanism is a record-separator plus `$( )` capture and an `IFS` split. |
| **Per-session counter to bound the fail-open oracle** | **Rejected.** No session identity is available on the path that would increment it, the key is circular, and 18 parallel hooks cross any small threshold on the first payload. With no fail-open cell there is no oracle to bound. |
| **Scrub lone surrogates and run the guards armed** | **Rejected — measured.** See Known limitations. |
| **Size cap, oversize ⇒ fail-open** | **Rejected.** A one-line padded payload disarms it by construction, and it fires on routine large `Write` payloads (this repo tracks an 806 KB lockfile). Any ceiling now asks. |
| **Every hook emits the `ask`** | **Rejected.** Turns a persistent fault into an unrecoverable loop; see Designated responder. |
| **A new AGENTS.md rule instead of a lint** | **Rejected.** It would fit the always-loaded budget, but a red CI check is fail-closed and costs zero always-loaded bytes. Prose is what failed for four months. |
