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
| `${CLAUDE_PLUGIN_ROOT}/scripts/…` | `/scripts/…` | root-anchored, nonexistent, not writable by a non-root user → the preflight refuses |
| `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…` | `./plugins/soleur/…` | resolves into the customer's tree → **fail-open, executes their file** |
| `${CLAUDE_PLUGIN_ROOT:?msg}/…` | — | exit 127 |

The bare form's failure mode is safe whether or not the harness substitutes the token. If
substitution is real, it yields the correct installed root on all three surfaces. If it is
not, it yields a root-anchored nonexistent path that the mandated preflight converts into a
refusal.

**Correction (review, measured).** An earlier draft of this ADR said "under no hypothesis
does it resolve into customer-controlled bytes." **That is false**, and the error is the
same class this ADR diagnoses in the `:-` form — treating an *environmental* property as a
*construction* guarantee. `CLAUDE_PLUGIN_ROOT` is an ordinary environment variable and the
Bash tool is initialized from the user's profile, so a `direnv` `.envrc` in the customer's
repo, a `~/.bashrc` line, or a package `postinstall` can export it. Measured: with an
ambient `CLAUDE_PLUGIN_ROOT` pointing at an attacker-chosen directory, a
`test -d "$X/scripts"` preflight **passed** and the hostile payload **executed**.

Two consequences, both binding:

1. **The preflight must verify plugin IDENTITY, not directory shape.** `test -d "$X/scripts"`
   is satisfied by any directory with a `scripts/` child. The shipped gate requires the
   payload manifest to exist AND to name this plugin, which raises the bar from "export one
   variable" to "plant a complete fake plugin".
2. **The correct claim is comparative, not absolute.** The bare form is *strictly better*
   than a `:-` default — which needs no attacker precondition at all and resolves into the
   customer's tree on every ordinary run — but it is **not safe by construction**, and the
   preflight is what carries it. That is why decision 2 below is mandatory rather than
   defence-in-depth, and why it is asserted by an executing test (T0i) rather than a
   presence grep.

**Separately, distinguish two properties of different strength** that the earlier draft
conflated under "fail-closed":

- **Hard, by construction:** the emitted operand never resolves into a path the customer's
  *working directory* controls. This holds under every substitution hypothesis.
- **Soft:** the run stops. `exit 1` halts the bash subprocess, not the agent — the same
  caveat recorded at §R2 for the rule-prune gate. An agent that sees the refusal can
  improvise (locate the script itself, read the payload-relative path from the prose two
  lines below). That is why the gate is paired with an explicit STOP instruction and
  verbatim user-facing wording, mirroring `go.md`'s readiness gate.

The path is **payload-relative** — the root already *is* `plugins/soleur`, so
`${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh`, never
`${CLAUDE_PLUGIN_ROOT}/plugins/soleur/scripts/foo.sh`. This is the highest-frequency way to
get the migration wrong.

Mandatory companion, one per command file, before the first producer:

```bash
test -d "${CLAUDE_PLUGIN_ROOT}/scripts" || {
  echo "soleur:sync — plugin root unresolved; refusing to run producers CWD-relative (ADR-179)." >&2
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
   directory.** This is a **necessary** condition, not a sufficient one — the relocation
   this PR performed needed three things, and only the first is about the data root:
   (a) the data root is caller-supplied; (b) the code root (`lib/`) moves atomically with
   it; (c) every consumer is repointed in the same commit. Applying only (a) will
   under-scope the next move. The test to apply:
   - `domain-model-drift.sh` takes `--repo <path>` from the caller and sources its lib as
     `$SCRIPT_DIR/lib/` — location-independent data root, location-dependent code root.
     **Relocatable**, and relocated.
   - `rule-prune.sh:52` (`ROOT="${RULE_METRICS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`) and
     `rule-metrics-aggregate.sh:34` (`REPO_ROOT="${INCIDENTS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`)
     derive their data root from their **own location**. **Not relocatable** — a move
     silently repoints them.

   Note the shape honestly: both rule-metrics scripts *are* parameterized
   (`RULE_METRICS_ROOT`, `INCIDENTS_REPO_ROOT`) with a **location-derived default**. So the
   precise reading is "relocatable, with a fail-open default" — and that default is the same
   construct this ADR rejects one level up in markdown: a `:-` fallback that resolves
   somewhere plausible instead of failing closed. Naming it that way strengthens decision 4
   rather than weakening it, and keeps the ADR from treating one construct as a hazard in
   one language and as evidence of safety in another.
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

   **Reason 1 is independently dispositive.** Reasons 2 and 3 are **migration cost, not
   justification** — an earlier draft framed them as "why not even if you wanted to", which
   is wrong in a way that invites exactly the outcome it was trying to prevent: labelling
   something a blocker is what invites clearing it. Reason 2 is a one-line change to a
   parameter that already exists; reason 3 is a 4-consumer repoint, and this very PR paid a
   ~19-occurrence one for `domain-model-drift.sh`. Neither is a barrier. The area is
   monorepo-only because its **input cannot exist** on a customer machine, and that is the
   whole argument.
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
  the payload, and refuses rather than silently executing customer files for the one area
  that cannot. **The "becomes runnable" half is conditional on the substitution branch of
  §R3** (see §R3a); the "refuses rather than executes" half holds unconditionally, and is
  the part this issue was filed about.
- **The durability half of #7442 is NOT closed.** When the plugin root does not verify, the
  customer gets a `SOLEUR_SYNC_ROOT_UNRESOLVED` marker on stdout and no artifact; when `bun`
  is absent they get `SOLEUR_SYNC_TOOLCHAIN_MISSING`. Both are session-scoped. The
  `--producer-unreachable` degraded-artifact mode designed in the plan was **not built**, so
  on observability layer 7 (ADR-171) — where the durable artifact IS the queryable surface —
  the failure still leaves no trace after the session ends. Tracked in #7452. Stated here
  because the issue explicitly raised it and a reader would otherwise take the marker work
  for the whole fix.
- **Amendment 2026-08-11 (#7474) — a third marker, and decision 5 binds the freshness axis.**
  The marker set enumerated above is now three: `SOLEUR_SYNC_ROOT_UNRESOLVED` (identity),
  `SOLEUR_SYNC_TOOLCHAIN_MISSING` (the runner binary), and
  `SOLEUR_SYNC_PRODUCER_MISSING producer=<payload-relative-path> affects=<area>
  reason=absent-from-verified-root` (the producer FILE). The third closes an axis this ADR
  did not separate: the preflight answers whether a root is genuinely ours — *identity* —
  and a root that is authentically Soleur but does not carry a producer satisfies every
  predicate it tests, after which the invocation dies as an unattributed interpreter error.
  Identity and freshness are different questions, and adding path predicates to the identity
  gate would answer neither well (it is exactly the `test -d "$X/scripts"` shape §Considered
  Options rejects), so the freshness check lives at the invocation sites instead.

  **Decision 5 (fail-closed in isolation) binds this axis, and is why.** The rejected design
  put a presence loop in Phase 0 and then instructed the agent, in prose, to skip the
  affected area three phases later. Bash shares no state across fences, so that guard could
  only ever *ask* — and a marker printed above a bare death is still a bare death. Each
  producer invocation is therefore wrapped in its own presence check, sharing a subprocess
  with the invocation it guards, so separating the two is not possible without deleting
  both. `reason=` states the observation, never the cause, matching the two pre-existing
  `reason=` tokens. Pinned by `plugin-root-anchoring.test.ts` P6 (parity + closed `affects=`
  set) and `test-sync-producer-reachability.sh` T0j/T0k/T0l/T0m.

  This does **not** close the durability residual above: a run whose missing producer is
  `write-kb-coverage.ts` still has no durable channel by construction.
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
- **R3.** **The substitution mechanism is CORROBORATED, not proven.** An in-session A/B
  observed the harness substituting a bare token in plugin markdown while leaving `:-`
  literal, but its two arms differed in *two* variables (bare-vs-`:-` **and**
  prose-inline-span-vs-bash-fence), so that observation alone does not separate them. The
  missing cell is supplied by a committed prior finding:
  `knowledge-base/project/learnings/implementation-patterns/2026-02-22-bundle-external-plugin-into-soleur.md`
  — *"`${CLAUDE_PLUGIN_ROOT}` is expanded by the plugin loader in all command/skill text,
  not just `!` blocks"* — whose worked example is a **bare token inside a ```bash fence in a
  command file**, recorded as the fix that made `/soleur:one-shot` self-contained. Together
  the two observations cover both cells of the confound.

  This also **reframes the ADR's own headline measurement**: `CLAUDE_PLUGIN_ROOT` being
  unset in the bash environment is the *predicted benign observation* under load-time loader
  substitution — the token never survives to bash, so nothing needs to set it. It is not
  evidence of a hazard. And it explains #7442 in one sentence: the loader performs **plain
  token replacement**, so `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` is not its token, passes
  through literally, reaches bash, and expands against the customer's tree.

  Why "corroborated" and not "proven": the learning is a recorded prior result, not a
  measurement taken for this decision. A direct run of a bare token inside a bash fence in a
  command file would close it outright, and remains a prerequisite for the deferred
  `safe-bash.ts` migration (#7453), where the emitted string determines whether the
  exact-literal carve-out still matches.

- **R3a.** **Two claims in this ADR depended on R3 and are now scoped.** (i) The Consequences
  claim that `/soleur:sync` "becomes runnable on a customer repo" holds under substitution;
  without it, sync refuses on every surface. (ii) Option (b)'s rejection — that `:?`
  "hard-fails the dogfooding CLI, which works today" — applies to option (a) equally under
  the no-substitution branch, so (a)'s advantage lives entirely in the substitution branch.
  Both are stated here rather than left implicit, because a reader who takes R3 seriously
  would otherwise find the options table quietly assuming what R3 declines to assume.
- **R4.** #6222 **narrows but does not close.** sync.md's two instances of the repo-root
  `scripts/` class are now gated rather than migrated; the class itself is untouched, and
  gating is a cheaper disposition than migration that likely applies to several of its
  members.

  *An earlier draft of this residual copied a month-old citation list verbatim without
  re-verification; 3 of its 4 line numbers pointed at unrelated prose. Re-derived here with
  content anchors per `cq-cite-content-anchor-not-line-number`, and the class is materially
  larger than that list suggested:*

  | Skill | Content anchor |
  | --- | --- |
  | `architecture` | `bash scripts/regenerate-c4-model.sh` |
  | `compound` | `python3 scripts/lint-agents-rule-budget.py` |
  | `review` | `bash scripts/rule-metrics-aggregate.sh` |
  | `preflight` | `python3 scripts/lint-encryption-posture.py` |
  | `kb-search` | `bash scripts/generate-kb-index.sh` |
  | `ship` | `bash scripts/sync-readme-counts.sh`, `bash scripts/check-adr-ordinals.sh` |
  | `legal-audit`, `legal-generate` | `bash scripts/lint-legal-*.sh` |
  | `feature-tweet`, `postmerge` | `bash scripts/lib/tweet-eligibility.sh` |
  | `social-distribute` | `bash scripts/lint-distribution-content.sh` |
  | `release-docs` | `bash scripts/sync-readme-counts.sh` |

- **R5.** **A severity-distinct subset of #7453, called out so it is not processed in file
  order.** Four shipped sites plus one test carry the **rejected option (d)** form
  `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}` — not merely the
  `:-` form, but the git-root variant this ADR rejects as strictly worse because it *looks*
  anchored:

  - `skills/incident/SKILL.md` and `skills/legal-generate/SKILL.md` — `redact-sentinel.sh`
  - `skills/linear-fetch/SKILL.md` — the `uploads.linear.app` URL scrubber
  - `skills/compound/SKILL.md` — `token-efficiency-report.sh`
  - `skills/incident/test/redact-sentinel.test.sh` — pins the unsafe form as expected

  These are **secret-handling gates whose exit code decides whether secrets are emitted**,
  and after `gh pr checkout` the git root is the contributor's tree. Tracked at #7450 (P0).
  #7453's framing as a "~98-site convention migration" flattens that severity; this subset
  goes first.

- **R6.** **Deferrals are tracked at #7452** (remaining follow-ups, incl. the unmodelled
  self-hosted-CLI C4 topology) **and #7453** (the `skills/**` convention migration). Named
  here and in the guard's docstring so a reader can find them from either.

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
