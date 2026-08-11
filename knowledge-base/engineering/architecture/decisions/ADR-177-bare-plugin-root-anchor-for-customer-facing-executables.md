---
title: The bare ${CLAUDE_PLUGIN_ROOT} is the canonical anchor for customer-facing plugin executables; a :- default is the vector
status: accepted
date: 2026-08-11
amends: [ADR-093]
related_adrs: [ADR-074, ADR-091, ADR-093, ADR-151, ADR-155, ADR-171]
related: [7442, 7450, 6222]
related_plans:
  - knowledge-base/project/plans/2026-08-11-fix-sync-plugin-root-anchoring-plan.md
related_specs:
  - knowledge-base/project/specs/feat-one-shot-7442-sync-plugin-root-anchoring/tasks.md
brand_survival_threshold: single-user incident
---

# The bare `${CLAUDE_PLUGIN_ROOT}` is the canonical anchor for customer-facing plugin executables; a `:-` default is the vector

## Context

`/soleur:sync` was reported (#7442) as unrunnable for 4 of 8 areas on a real customer
repo. `plugins/soleur/commands/sync.md` invoked its producers with paths relative to the
caller's working directory. That is correct in this monorepo, which self-hosts the plugin.
From a customer repo, `plugins/soleur/scripts/` does not exist and `scripts/` is **the
customer's own scripts directory** — so a name collision executes *their* file under an
agent that files GitHub issues from parsed sentinels.

The issue proposed the convention already used at ~100 sites under `plugins/soleur/`:
prefix each invocation with `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}`.

**Measured, that remedy is a no-op on the surface it targets.** `CLAUDE_PLUGIN_ROOT` is
UNSET in the bash tool environment — verified three ways (`${VAR+SET}` empty, `env | grep -c`
returning 0, and the fallback expanding to `./plugins/soleur`), from inside a
plugin-provided *skill* execution context, not merely a plain session. So the `:-` default
fires and expands to a path the customer controls. The proposed fix **is** the vector.

ADR-093 established the `${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}` form as the migration
target. That was correct for the surfaces it was written against and is unsafe on a third
that has since appeared:

| Surface | `CLAUDE_PLUGIN_ROOT` | `:-` default behaviour |
| --- | --- | --- |
| Concierge server | exported fail-closed per dispatch (`agent-env.ts`) | never fires — correct |
| CLI in this monorepo (dogfooding operator) | unset | falls back to `./plugins/soleur`, which happens to exist — correct *by accident* |
| **Marketplace customer** (#7442's reporter) | unset | resolves into the customer's tree — **executes their file** |

ADR-093 was not wrong. It was scoped to two surfaces and a third appeared.

## Considered Options

### (a) Bare `${CLAUDE_PLUGIN_ROOT}/<payload-relative-path>` — **CHOSEN**

The decisive property is the failure mode with the variable unset:

| Form | Expands to (unset) | Failure mode |
| --- | --- | --- |
| `${CLAUDE_PLUGIN_ROOT}/scripts/…` | `/scripts/…` | root-anchored, nonexistent, not writable by a non-root user → **fail-closed by construction** |
| `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…` | `./plugins/soleur/…` | resolves into the customer's tree → **fail-open, executes their file** |
| `${CLAUDE_PLUGIN_ROOT:?msg}/…` | — | exit 127 |

**The bare form is safe whether or not the harness substitutes the token.** If substitution
is real, it yields the correct installed root on all three surfaces. If it is not, it
yields a root-anchored nonexistent path that the mandated preflight converts into a clean
refusal. Under no hypothesis does it resolve into customer-controlled bytes.

The path is **payload-relative** — the root already *is* `plugins/soleur`, so
`${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh`, never
`${CLAUDE_PLUGIN_ROOT}/plugins/soleur/scripts/foo.sh`. This is the highest-frequency way to
get the migration wrong.

Mandatory companion, one per command file, before the first producer:

```bash
test -d "${CLAUDE_PLUGIN_ROOT}/scripts" || {
  echo "soleur:sync — plugin root unresolved; refusing to run producers CWD-relative (ADR-177)." >&2
  exit 1
}
```

### (b) `${CLAUDE_PLUGIN_ROOT:?<message>}` — rejected

Fail-closed is the right instinct and the wrong instrument. `:?` is not the literal token
either, so it is not substituted, reaches bash, finds the variable unset, and hard-fails on
**exactly the marketplace surface #7442 exists to repair** — converting a silent-wrong into
a loud-broken without ever producing a working `/soleur:sync`. It also hard-fails the
dogfooding CLI, which works today. Fail-closed belongs in the guard, not the expansion.

### (c) Keep `:-`, declare the marketplace surface unsupported — rejected

`brand_survival_threshold: single-user incident`, and the incident already happened to a
real customer. Declaring the surface unsupported does not un-execute their file.

### (d) `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}` — rejected

This is #7450's exact vector: after `gh pr checkout` the git root **is** the contributor's
tree. Strictly worse than `./plugins/soleur` because it looks anchored.

### (e) A `resolve-git-root.sh`-style shim — rejected

Same class as (d). Any resolver that consults the *workspace* rather than the *installation*
is CWD-shadowable. The plugin root is the only trusted anchor and must arrive from outside
the workspace.

## Decision

1. **Canonical form** for every customer-facing executable path in plugin markdown is the
   bare `${CLAUDE_PLUGIN_ROOT}/<payload-relative-path>`. `:-` and `:?` are rejected.
2. **A preflight guard** per command file, before the first producer, converts an
   unresolved root into a refusal rather than a CWD-relative run.
3. **Relocatability is a property of where a script gets its DATA root, not of its
   directory.** This is the test to apply before any future payload relocation:
   - `domain-model-drift.sh` takes `--repo <path>` from the caller and sources its lib as
     `$SCRIPT_DIR/lib/` — location-independent data root, location-dependent code root.
     **Relocatable**, and relocated.
   - `rule-prune.sh:52` (`ROOT="${RULE_METRICS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`) and
     `rule-metrics-aggregate.sh:34` (`REPO_ROOT="${INCIDENTS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`)
     derive their data root from their **own location**. **Not relocatable** — a move
     silently repoints them.
4. **`rule-prune` is a maintenance area of the Soleur repository, not a product
   capability.** It is de-advertised from `argument-hint` and `**Valid areas:**`, and both
   call sites are gated by an executable monorepo sentinel. Ranked reasons:
   1. **The area is monorepo-only by construction** — its input derives from
      `.claude/.rule-incidents.jsonl`, written by `emit_incident()` in
      `.claude/hooks/lib/incidents.sh` (ADR-091), which is outside the payload and is
      Soleur's own rule-corpus telemetry. It does not and should not exist on a customer
      machine. *This is why.*
   2. Both scripts derive their data root from `$SCRIPT_DIR/..` (see 3).
   3. Four production consumers pin `scripts/rule-prune.sh`, one a fail-loud sentinel at
      `cron-rule-prune.ts:117`.

   Reasons 2 and 3 are why not *even if you wanted to* — recorded so a future reader who
   clears those blockers does not conclude the move became correct.
5. **The gated invocation must be fail-closed in isolation.** The operand is
   `"$SOLEUR_MONOREPO/scripts/…"`, and `SOLEUR_MONOREPO` is assigned from the sentinel with
   `|| true` so `set -e` cannot abort before the message prints. If the invocation line is
   ever separated from its gate — a reader that takes the last line of a block, a tool that
   extracts invocations line-wise — the variable is unset and the operand degrades to
   `/scripts/…` rather than resolving into the customer's tree. This was not theoretical:
   the reachability suite caught the decoys executing under exactly that separation.
6. **The exemption is keyed to a closed set inside the guard file**
   (`MONOREPO_ONLY_AREAS`), not to a syntactic marker in the markdown. A syntactic marker
   is self-serve — if the predicate is "wrapped in an `if`", then wrapping *is* the
   laundering. ADR-155 already declined a free-form `reason=` token for the same reason;
   this reuses that shape rather than inventing one.

## Consequences

- `/soleur:sync` becomes runnable on a customer repo for the areas whose producers ship in
  the payload, and refuses cleanly rather than silently executing customer files for the
  one area that cannot.
- The `~100` `${CLAUDE_PLUGIN_ROOT:-…}` sites under `plugins/soleur/skills/**` are **not**
  migrated here. That migration requires changing `server/safe-bash.ts`'s exact-literal set
  and `plugin-root-list-carveout-coupling.test.ts`'s regex, which does not belong behind a
  P1 customer bug fix — bundling an allowlist edit with a bug fix is how allowlist
  regressions ship. Deferred, blocked on this ADR.
- `EXACT_LITERAL_SAFE_COMMANDS` in `safe-bash.ts` is **prompt-suppression, not an execution
  gate** — the committed docstring at `plugin-root-list-carveout-coupling.test.ts:26-29`
  says trust comes from the path anchor and that drift is "UX friction, never untrusted-code
  execution." When the deferred migration lands, the constant moves to the bare literal and
  **exact-string equality is retained**; do not add a `^bash` regex, which would reintroduce
  the injection surface exact equality avoids.

### Residuals — recorded, deliberately not fixed here

- **R1.** The monorepo sentinel is CWD-relative and therefore shares #7450's threat model:
  any tree containing `plugins/soleur/.claude-plugin/plugin.json` satisfies it, including a
  `gh pr checkout` of a contributor PR. Correct for the marketplace customer (who never
  satisfies it); **not** a defense on the review path. Tracked in #7450.
- **R2.** `exit 2` halts the bash subprocess, not the agent. The "run the block, not the
  bare command" construction is what makes the halt load-bearing; guard condition 5 keeps it
  from being edited away.
- **R3.** **The substitution mechanism is UNRESOLVED.** An in-session A/B suggested the
  harness substitutes the bare token in plugin markdown while leaving `:-` literal, but the
  two arms differed in *two* variables (bare-vs-`:-` **and** prose-inline-span-vs-bash-fence),
  so it does not separate them. The decision above holds under both hypotheses and does not
  depend on resolving it. Resolving it — a bare token *inside a bash fence*, the arm the A/B
  lacked — is a prerequisite for the deferred `safe-bash.ts` migration only.
- **R4.** #6222 **narrows but does not close.** sync.md's two instances of the repo-root
  `scripts/` class are now gated rather than migrated; the class itself
  (`architecture:282`, `compound:254`, `review:272`, `preflight:909`, `kb-search`,
  `compound-capture`) is untouched. Gating is a cheaper disposition than migration and
  likely applies to several of those sites.

## Relationship to prior decisions

- **Amends ADR-093.** Its `${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}` guidance remains
  correct for the server surface it was written against; this ADR scopes it out of the
  customer-facing command surface. ADR-093 §Amendment's premise that "git-root = the
  operator's own checkout" is falsified on the review path — see #7450.
- **ADR-091** establishes the rule-metrics producer as local, which is the substantive
  reason `rule-prune` is monorepo-only.
- **ADR-155** supplies the closed-vocabulary-over-free-form-token precedent reused in
  decision 6.
- **ADR-171** (observability layer 7) is why the unreachable-producer case matters beyond
  availability: when the coverage producer cannot run, the customer gets neither the
  artifact nor the `SOLEUR_KB_SYNC_PRODUCERS` marker, so the failure layer 7 exists to make
  durable is exactly the failure that leaves no trace.

## Principle Alignment

- **Fail closed on an unresolved trust anchor.** The chosen form's unset-expansion is
  root-anchored and nonexistent; every rejected form either executes customer bytes or
  breaks the surface being repaired.
- **Verify the remedy, not just the diagnosis.** The reported bug was real and the proposed
  fix was a no-op on its own target; measuring the fix before shipping it is what surfaced
  that.
- **State what is out of scope rather than implying closure.** The guard's docstring names
  its blind spots (skills corpus, shipped payload scripts) instead of reading as full
  coverage.
