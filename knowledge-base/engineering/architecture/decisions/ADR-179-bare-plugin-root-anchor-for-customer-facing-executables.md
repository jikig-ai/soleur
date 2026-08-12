---
title: The bare ${CLAUDE_PLUGIN_ROOT} is the canonical anchor for customer-facing plugin executables; a :- default is the vector
status: accepted
date: 2026-08-11
amends: [ADR-093]
related_adrs: [ADR-074, ADR-091, ADR-093, ADR-151, ADR-155, ADR-171]
related: [7442, 7450, 6222, 7474, 7452]
amended_by:
  - "#7474 (2026-08-11) — producer presence as a fourth precondition; see ## Amendment 2026-08-11"
related_plans:
  - knowledge-base/project/plans/2026-08-11-fix-sync-plugin-root-anchoring-plan.md
  - knowledge-base/project/plans/archive/20260812-125433-2026-08-11-fix-sync-producer-freshness-probe-plan.md
related_specs:
  - knowledge-base/project/specs/feat-one-shot-7442-sync-plugin-root-anchoring/tasks.md
  - knowledge-base/project/specs/archive/20260812-145032-feat-one-shot-7474-sync-producer-freshness-probe/tasks.md
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

Mandatory companion, before the first producer, in every command file and in every
**secret-gate** skill file (scope extended by the 2026-08-12 amendment):

> **Scoped to SECRET-GATE skill files on 2026-08-12 (#7450 review-finding C7).** The
> amendment first widened this to "command **or skill** file", which the amending PR then
> violated with a site it shipped: `compound/SKILL.md` is a skill file with a producer
> (`token-efficiency-report.sh`) and no companion preflight. The wider wording was also
> wrong on the merits — that producer prints an advisory cost table and its exit code
> authorises nothing, so halting there is a pure operator regression with no security
> benefit, which is the same asymmetry §R5's correction records. The population is now the
> one `plugin-root-anchoring.test.ts` G5 actually pins: `incident`, `legal-generate`,
> `linear-fetch`. The ~105 remaining non-gate `skills/**` sites stay deferred to #7453.


```bash
[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
  && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" \
  || { echo "soleur — cannot verify the Soleur plugin installation; refusing to run producers (ADR-179)." >&2
       exit 2; }
```

> **This block was REPLACED on 2026-08-12 (#7450).** It previously shipped
> `test -d "${CLAUDE_PLUGIN_ROOT}/scripts" || { …; exit 1; }` — the exact directory-shape
> check that §(a) *Correction (review, measured)* above records as **bypassable**, where a
> `test -d` preflight passed and an attacker-chosen payload executed. The defeated form was
> therefore prescribed by this ADR's own Decision while being refuted 30 lines above it, and
> it appeared **nowhere** in `plugins/` — what actually shipped was the manifest+name check
> now written here. An agent following Decision 2 literally would have implemented the
> bypassable guard. Extending the scope without replacing the block would have propagated it.

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
- **A fourth precondition — producer PRESENCE — was added 2026-08-11 (#7474).** Identity is
  not freshness: a root that is authentically Soleur can still not carry a producer. See
  `## Amendment 2026-08-11 (#7474)` below.
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

- **R1. SETTLED 2026-08-12 by #7450 — scoped, not strengthened.** *(Previously: "the
  monorepo sentinel is CWD-relative and therefore shares #7450's threat model … not a
  defense on the review path. Tracked in #7450." That text conflated two claims; the
  scoping below is the resolution, and the tracking reference is discharged.)*

  The monorepo sentinel answers *"is this a Soleur monorepo checkout?"* — a
  **surface-selection** predicate, not a **trust** predicate. It correctly excludes the
  marketplace customer, who never satisfies it. It cannot exclude a `gh pr checkout` of a
  contributor PR, and **no CWD-resident fact can**, because every byte in the checked-out
  tree is contributor-writable — including any sentinel added to authenticate it. The
  correct disposition is therefore not a stronger sentinel but the removal of trust
  decisions from CWD-resident operands: where the target ships in the payload, decision 1's
  bare anchor applies; where the target is monorepo-only — `.claude/hooks/lib/incidents.sh`
  — the invocation is inverted to an inert marker captured hook-side (decision 9), so no
  operand exists to shadow; and the rejected forms are banned from operator configuration
  as well (decision 8). Under these, the sentinel is never load-bearing for trust on the
  review path, which is what R1 was recording.

  **Re-routed, not closed here:** a review session opened *inside* a contributor-checked-out
  worktree executes that tree's `.claude/hooks/*.sh` on every tool call. That is a
  **strictly larger** exposure than any path anchor, it is not an anchoring defect, and it
  must not hold #7450 open. **Tracked at #7502.**
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

- **R5. CLOSED 2026-08-12 by #7450** — see the amendment at the foot of this ADR. Retained
  in full because the enumeration is what the amendment closes against, and because one of
  its own claims was measured false.

  **A severity-distinct subset of #7453, called out so it is not processed in file
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

  > **Correction (2026-08-12, #7450): the sentence above is false for one of the four.**
  > `token-efficiency-report.sh` is **not** a secret-handling gate — it prints an advisory
  > top-3 cost table and appends `te-*` warnings to `.claude/.rule-incidents.jsonl`. Its exit
  > code authorises nothing. The four shipped sites are **three classes, not one**: two
  > secret gates that already had a `[[ -r ]]` guard (`incident`, `legal-generate`); one
  > secret gate that had **no guard at all** (`linear-fetch` — an unresolved root yielded
  > exit 127 and empty stdout, which is the shape an agent persists as "the redacted text");
  > and one advisory reporter (`compound`). The distinction is load-bearing rather than
  > pedantic: the fail-closed asymmetry that justifies halting rests on the gate authorising
  > secret emission, so a **non-blocking** skip guard is the right shape for `compound` and a
  > halt is not. Halting knowledge capture over a missing cost table would be a pure operator
  > regression with no security benefit. Flattening the four into one class is what would have
  > produced that regression.
  >
  > **Correction (2026-08-12, #7450 review-finding C6): that guard was NOT shipped.** An
  > earlier revision of this paragraph said `compound` "correctly received" it. It did not —
  > `7840b2a42` descoped the guard to stay inside a byte budget and landed the anchor swap
  > only, so `compound/SKILL.md` carries a bare, unguarded invocation today. The class
  > analysis above is unchanged and still correct; what was wrong was the tense. Recording a
  > design as a delivered control is precisely the defect class this PR exists to close, so
  > it is corrected here rather than quietly satisfied by shipping the guard late.
  > Tracked with the other non-gate `skills/**` work at #7453.

- **R6.** **Deferrals are tracked at #7452** (remaining follow-ups, incl. the unmodelled
  self-hosted-CLI C4 topology) **and #7453** (the `skills/**` convention migration). Named
  here and in the guard's docstring so a reader can find them from either.

## Amendment 2026-08-11 (#7474) — producer PRESENCE is a fourth precondition, guarded at each invocation site

### Decision 7

Every anchored invocation in `plugins/soleur/commands/**` is wrapped in a presence check in
its own fence, emitting a named marker instead of invoking a file that is not there:

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/<rel>" ]; then
  <runner> "${CLAUDE_PLUGIN_ROOT}/<rel>"
else
  echo "SOLEUR_SYNC_PRODUCER_MISSING producer=<rel> affects=<area> reason=absent-from-verified-root"
fi
```

**The marker family is per-surface, not universal.** The template above is the `sync.md`
instance. `go.md`'s two guards deliberately reuse *its* existing families —
`SOLEUR_GIT_REPO_DIAG source=probe-unreachable reason=…` and
`SOLEUR_SESSION_START_SKIPPED reason=…` — because they are not sync producers and because
`SOLEUR_GIT_REPO_DIAG` is already mirrored by
`apps/web-platform/server/git-lock-marker-telemetry.ts`. Emitting a `SOLEUR_SYNC_*` marker
from `/soleur:go` would be wrong. What is universal is the SHAPE: presence check and
invocation in one subprocess, and an `else` that NAMES the absence.

`sync.md`'s Phase 0 identity fence is **not** edited. (`go.md`'s Step 0.0 identity fence
*body* is — a presence check is nested inside it. The fence's own predicate is unchanged.)

Pinned by `plugin-root-anchoring.test.ts` P6 (presence-guard parity across the whole command
surface, guard-precedes-invocation), P7 (`sync.md` marker grammar + producer→area
correspondence) and P8 (`go.md`'s two markers), and by
`test-sync-producer-reachability.sh` T0j/T0k/T0l/T0m.

### Why the axes stay separate

The preflight answers *identity*; this answers *freshness*. Three reasons to keep them
apart, none of which is "adding a path predicate would be the rejected `test -d` shape" —
that argument does not survive contact with the file, since the shipped gate already
carries `[ -d "${CLAUDE_PLUGIN_ROOT}/scripts" ]` as a **conjunct**. §Considered Options
rejected that predicate as *sufficient alone*, never as a conjunct.

1. **Blast radius.** An identity failure means nothing about the root is trustworthy →
   refuse the whole run. A freshness failure means one file is absent → skip one area and
   run the rest. Folding freshness into Phase 0 collapses per-area degradation into
   all-or-nothing refusal. T0j asserts exactly this: a present sibling producer that fails
   to run is a test failure.
2. **Area-scoped dispatch.** `/soleur:sync conventions` invokes no producer at all, so a
   Phase 0 presence loop emits confident wrong markers on a completely healthy run.
3. **Cross-fence state.** Bash carries no state between markdown fences, so a Phase 0 result
   can only ever *instruct* a downstream fence — and a marker printed above a bare death is
   still a bare death.

A single-gate design does exist — a payload-shipped `producers.json` verified wholesale in
Phase 0 — and it loses on (1) and (2) while adding a manifest that can itself drift.

### What decision 5 does and does not give us

Decision 5's stated property is that **the invocation line, taken alone, is safe**: its
operand is `"${SOLEUR_MONOREPO:?…}"`, a variable bound only by the gate, so a reader or tool
that extracts invocations line-wise gets an unset variable rather than a live command.

The guard above does **not** have that property. Its invocation line is
`<runner> "${CLAUDE_PLUGIN_ROOT}/<rel>"` — byte-identical to the pre-amendment line. The
guard is **co-located**, not fail-closed in isolation. What decision 5 contributes here is
its *reasoning*, not its guarantee: a gate separated from its invocation is not a gate, which
is why the check sits at the call site rather than in Phase 0.

This is a deliberate trade, recorded rather than glossed. Binding the operand to a
gate-set variable would satisfy decision 5 literally, but a variable operand drops out of
`extractOperands`, silently vacating P2's `existsSync` residency assertion over every
anchored operand. Trading a proven residency check for a nominal isolation property is the
worse deal. **Residual:** under line-wise extraction the guard degrades to the pre-fix bare
error — not to customer-tree execution, which is what this ADR's threat model is about.

Do not read this amendment as establishing "wrapped in an `if`" as a satisfying predicate
for decision 5. Decision 6 rejects syntactic self-serve predicates for exactly that reason.

### Marker vocabulary

**Eight** markers cross the surface Decision 7 governs (`plugins/soleur/commands/**`), not the
three this section originally listed. Six in the `sync.md` + `kb-coverage.ts` family:
`SOLEUR_SYNC_ROOT_UNRESOLVED` (anchor identity), `SOLEUR_SYNC_TOOLCHAIN_MISSING` (runner
binary), `SOLEUR_SYNC_PRODUCER_MISSING` (producer file), `SOLEUR_SYNC_AREA_UNAVAILABLE` (area
not offered on this surface), plus `SOLEUR_KB_SYNC_PRODUCERS` and `SOLEUR_KB_SYNC_ERROR` from
`plugins/soleur/lib/kb-coverage.ts`. Two more in `go.md`: `SOLEUR_GIT_REPO_DIAG` and
`SOLEUR_SESSION_START_SKIPPED`.

The **axes** are disjoint and coherent. The **grammar** is not, and this amendment does not
close it. Target shape:

```text
SOLEUR_SYNC_<CONDITION> <subject>=<value> [affects=<csv>] reason=<observation>
```

Pre-existing divergence, recorded so it is not mistaken for new: `AREA_UNAVAILABLE` uses
`area=` where `TOOLCHAIN_MISSING` and `PRODUCER_MISSING` use `affects=` for the same concept.

`reason=` names an **observation**, never a cause — matching both pre-existing tokens.
`absent-from-verified-root` identifies *which* root the path is absent from (the one Phase 0
verified earlier in the same run); it is not a claim that the guard block re-verified
anything, and it re-checks nothing.

### Scope of the fix

This closes the axis for torn or incomplete payloads, for an instruction/payload split, and
for every producer added in future — P6 makes the guard mandatory for producers that do not
exist yet. Whether it resolves the originally-reported incident depends on which generator
was actually at work there; see the plan's H1/H2/H3 table. It does **not** close the layer-7
durability residual above: a run whose missing producer is `write-kb-coverage.ts` still has
no durable channel by construction.

### Additional residual (R1–R3 are in §Residuals above)

**R4.** The command TEXT and `${CLAUDE_PLUGIN_ROOT}` can resolve to **different trees** — the
harness may load a project-scoped `sync.md` while the anchor points at an installed payload
at a different SHA. That is the root architectural fact behind #7474 and it is not otherwise
recorded in this ADR. Nothing in this amendment detects it; the SHA-divergence probe that
would is deferred (#7452).

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

## Amendment — 2026-08-12 (#7450): the skills secret-gate subset

`status: accepted` is unchanged. This amendment **retires a deferral; it does not extend a
scope.** Decision 1 already says "every customer-facing executable path in **plugin
markdown**", which governs `SKILL.md`. What deferred the *work* was the Consequences ("the
`~100` … sites under `plugins/soleur/skills/**` are **not** migrated here … Deferred, blocked
on this ADR"), and §R5 named these five sites by path. So this subset was already governed
both normatively and by name.

**1. Deferral retired for the gate subset only.** The five §R5 sites now carry the canonical
bare anchor. The remaining ~105 non-gate `skills/**` sites stay deferred to #7453.

**2. Decision 2's code block was replaced, not merely rescoped.** See the note under §(a).
This is the substantive correction: the ADR prescribed the shape its own review had measured
as bypassable.

**3. This subset needed NO `safe-bash.ts` change, so that coupling never blocked it.**
Measured: `EXACT_LITERAL_SAFE_COMMANDS` is a closed set of exactly two literals, both
`worktree-manager.sh list|ls`; none of `redact-sentinel.sh`, `redact-linear-urls.sh` or
`token-efficiency-report.sh` appears anywhere in that file (0 hits each), and
`SAFE_BASH_PATTERNS` carries no `^bash <path>` regex at all. All three therefore fall to the
review gate both before and after the migration — behaviour-neutral on that surface under
**either** branch of §R3. `plugin-root-list-carveout-coupling.test.ts` is likewise unaffected
(it scopes to `worktree-manager.sh list|ls`). The Consequences cite both as blockers for the
wider migration; they block the `list`/`ls` sites, not this subset.

**4. The fail-closed asymmetry — why a secret gate is SAFER to migrate than `/soleur:sync`
was.** §R3a scopes the "becomes runnable" claim to the substitution branch because a refusing
`/soleur:sync` is a broken feature. For a gate whose exit code authorises secret emission, a
refusal **is** the correct unresolved-root behaviour: an unresolved gate that halts leaks
nothing, whereas the form it replaces silently resolved the reviewed party's scanner and
reported a pass. This subset is therefore sound under **both** branches of §R3 — strictly
stronger than this ADR's position on its original surface. That is the substantive new
reasoning, and it is why the migration did not wait on item 5.

**5. §R3 upgraded from "corroborated" to "proven for the measured construction" — by
measurement, not argument.** Measured 2026-08-12 in a live CLI session: `commands/go.md`
ships a bare `${CLAUDE_PLUGIN_ROOT}` inside a fenced `bash` block and the text **delivered to
the agent** carried the absolute installed root, while `echo "[${CLAUDE_PLUGIN_ROOT:-<UNSET>}]"`
in that same session printed `[<UNSET>]`. Substitution is therefore a **loader text-transform
performed before the text is ever executed**, not a shell expansion. In the same session the
`:-` form arrived **unsubstituted** in two `SKILL.md` files, which confirms empirically that
the transform is **exact-literal** — the reasoning behind rejecting options (b) and (d) is now
a measurement rather than an inference, and it also shows the transform pass runs over
`SKILL.md` text.

*Scope of the claim, stated honestly:* the direct bare-token-inside-a-`SKILL.md` arm could not
be executed. A throwaway skill carrying a bare token was written and invoked; the Skill tool
returned `Unknown skill`, because the skill registry is built at session start. That arm needs
a fresh session. **Do not restate this as "proven" flatly.**

---

### Amendment continued — 2026-08-12 (#7450 review panel + CTO ruling)

Items 1–5 above covered the gate subset. The review panel then scoped three further
surfaces, all of which failed for the same reason, and the binding decision was routed to
the `soleur:engineering:cto` agent because both instruments this ADR sanctions were blocked
on its own §R1. The ruling and its rejected alternatives are recorded at
`knowledge-base/project/specs/feat-one-shot-7450-git-root-anchor-untrusted/cto-ruling-adr179-fork.md`.

**6. §R5 enumerated by SYNTAX, not by STAKES — and that is why the highest-stakes site was
missed.** §R5's five sites were found by grepping one anchor form. `trigger-cron/SKILL.md`
sat on `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}` and invokes a script that reads
`INNGEST_MANUAL_TRIGGER_SECRET` from Doppler at `-c prd` and fires a real production event,
with **no env-var precondition at all** — strictly cheaper to exploit than the redaction
gates this issue was filed about. `redact-sentinel.test.sh` test 18c reported "zero …
remain anywhere under `plugins/soleur/`" while that site stood, because its needle keyed on
the git-rev-parse variant. Migrated under decision 1; no new instrument was required,
because the target is IN the payload.

**7. Twenty `source` sites were not enumerable at all by the `SKILL.md` grep.** Three
payload **scripts** — `gdpr-gate.sh` (itself a compliance gate), `net-issue-flow.sh` (a ship
gate) and `token-efficiency-report.sh` — derived a root from `git rev-parse --show-toplevel`
and sourced `.claude/hooks/lib/incidents.sh` from it. Amendment item 7's predecessor had
already migrated `token-efficiency-report.sh`'s *code* root to the plugin anchor and left
its lib resolution git-root-derived; the ADR had touched the file and not closed it.

### Decision 8

**The rejected anchor forms are banned in operator configuration, not only in plugin
markdown.** `.claude/settings.json` `permissions.allow[]` may contain neither
`$(git rev-parse` nor `${CLAUDE_PLUGIN_ROOT:-`. An auto-approval entry is read by agents as
documentation of the sanctioned form, and a `permissions.allow` match executes with **no
prompt at all** — the cheapest exploitation shape in the corpus. The entry removed under
this decision was measured DEAD before removal (all 22 `git-worktree` invocation sites emit
the `:-` form, so it matched nothing Soleur emits); it was removed anyway, for the
documentation-by-example reason. It is deliberately **not replaced** with an anchored
entry: per item 5 the loader substitutes the token before delivery, so the delivered command
carries an absolute installed path that no static literal can match, and an anchored allow
entry would be a dead entry replacing a dead entry. Prompt-suppression for
`worktree-manager.sh` belongs with the `git-worktree` migration in #7453, where
`EXACT_LITERAL_SAFE_COMMANDS` must move in the same commit.

### Decision 9

**When the target is monorepo-only and therefore unanchorable, invert the invocation rather
than choosing an anchor.** Payload markdown emits an inert `printf`/`echo` marker; a
monorepo-only PostToolUse hook parses the marker and performs the privileged action,
resolving its own library through `${CLAUDE_PROJECT_DIR}`. **Decision 1 governs *paths*; it
does not require that every capability be expressed as a path.** That misreading — treating
this ADR's options table as exhaustive over *designs* when it is exhaustive over *anchor
forms* — is what made §E read as a deadlock.

Preferred over **relocation into the payload**, which would manufacture on every customer
machine the exact input decision 4 reason 1 says must not exist there (and would not fix the
vector: a relocated lib still needs a data root, whose current default is the
location-derived fail-open this ADR names at decision 3). Preferred over **sentinel
gating**, which §R1 records as no defense on the review path — gating this vector behind a
gate the review path satisfies would repeat the error item 2 corrected.

It satisfies decision 5 **maximally**: under line-wise extraction every other governed site
degrades to a non-resolving operand; this one degrades to printing a string.

A hook consuming a marker **MUST** validate the rule id against a closed corpus and sanitise
the note to a fixed charset, because the markdown that prompts the marker is
contributor-writable on the review path. This bounds the worst case to a rejected telemetry
row. The hook is **PostToolUse, not PreToolUse**: PreToolUse counts *intent* while the
construction it replaces counted *execution*, so PreToolUse would over-count against every
row already in the corpus. Verified rather than argued — a marker driven through the hook
and a direct `emit_incident` call produce byte-identical rows, differing only in timestamp.

### Decision 10

**Scope of option (e).** Option (e) rejects a git-root shim as a **code root / trust
anchor**. It does **not** reject `plugins/soleur/scripts/resolve-git-root.sh` in its live use
as a **workspace/data** root by `hooks/stop-hook.sh`, `hooks/welcome-hook.sh`, and
`.openhands/hooks/stop-hook.sh`, which is correct under item 7's code-root/data-root
distinction. Stated because a one-line rejection read out of context invites deleting a
working helper.

### Classification rule for the remaining corpus (#7453 needs no re-deciding)

Every `git rev-parse --show-toplevel` in the payload is exactly one of three things:

| Class | Test | Disposition |
| --- | --- | --- |
| **Code root** | Does the resolved path get *executed* (`source`/`bash`/`python3`/`awk`)? | **Ban.** Bare `${CLAUDE_PLUGIN_ROOT}` if the target is in the payload; decision-9 inversion if it is monorepo-only. |
| **Data root** | Is it only read or written as content? | **Allowed and correct** — the workspace is what it is measuring. |
| **Repo-root `scripts/` class** | Executes, and the target is outside the payload | Code root. §R4's table. Route to #7453. |

*Implementation note, measured during #7450 and recorded because the obvious form is
wrong:* a decision-9 hook may rely on `${CLAUDE_PROJECT_DIR}`, which the harness sets for
hook processes. A payload **script** may not — it is measured UNSET in a plain Claude Code
Bash call and in git hooks, so a `CLAUDE_PROJECT_DIR`-only resolution silently retires the
telemetry it was meant to preserve. Payload scripts use `${CLAUDE_PROJECT_DIR}` first and
then their own `BASH_SOURCE` location (layout-invariant per ADR-178, and not CWD-derived),
never `git rev-parse`.

*This also dissolves a worry rather than mitigating it:* the identity preflight reads
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`, so it was thought to halt on an unset
variable regardless of substitution — a second, independent unknown. Because substitution
happens at delivery, there is no unset-variable state at the point the preflight runs.

**6. Evidence correction — two of this ADR's own citations are circular.** §R3's supporting
evidence must **not** cite `preflight/SKILL.md` or `review/SKILL.md`; both bare-token sites
landed in `98ad03aa8`, the commit that introduced this ADR. **The same defect applies to
`commands/go.md` and `commands/sync.md`,** which were treated as independent command-surface
precedent and are from that same commit (`git log -1 -S'${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json' -- plugins/soleur/commands/go.md`
→ `98ad03aa8`). The genuinely independent precedents are `plugins/soleur/hooks/hooks.json`
(three bare tokens since `6893c7941`, 2026-04-03 — four months earlier, and its hooks fired
successfully in the measuring session) and the 2026-02-22 bundling learning, which states the
loader expands the token "in all command/skill text" and names the skill surface explicitly.

**7. Code root vs data root, so the `compound` migration does not read as inconsistent.**
Its **code** root moved to `${CLAUDE_PLUGIN_ROOT}`; its script-internal `TE_REPORT_REPO_ROOT`
**data** root correctly stays git-root-defaulted, because the report measures the *workspace*.
This is decision 3 applied honestly: the two roots answer different questions, and only one
of them is a trust anchor.

**8. New residual — Pattern C, not previously recorded here.** `preflight/SKILL.md` carries
**two unconditional** `$(git rev-parse --show-toplevel)/plugins/soleur/…` anchors
(`parse-form-a.awk`, `probe-verb-gate.sh`) — a *third* form, with no `${CLAUDE_PLUGIN_ROOT}`
arm at all, so neither §R4 nor §R5 enumerated it. Same threat model, and arguably worse than
gate-bypass since `probe-verb-gate.sh` is itself a gate and the awk parser is executed.
Neither is a secret-emission gate, so both are **routed to #7453 flagged
severity-above-baseline** rather than folded in (#7450 DC-1). Their committed rationale
comment — which argued *for* git-root resolution — was corrected in this PR: its premise
(the variable is unset in a plain session) is true and is this ADR's headline finding, but its
conclusion holds only for the `:-plugins/soleur` form it was written against, not for the bare
form, whose unset expansion is root-anchored rather than CWD-relative.

**9. Guard coverage.** `plugin-root-anchoring.test.ts` now enforces this subset structurally
on both axes — every `skills/**/SKILL.md`, and a gate-script set discovered on disk
(`redact-*.sh`, excluding `*.test.sh`) plus a closed extras constant. Two shape facts made a
copy of the command-surface rule unusable: the anchor lives in an **assignment**
(`SENTINEL="…"` then `bash "$SENTINEL"`), so an operand rule certifies the invocation while
the assignment points anywhere; and most path-form references in the corpus are **markdown
links**, so a bare-path rule reports documentation as a vulnerability. `redact-sentinel.test.sh`
carries a planted-decoy positive control and a corpus-wide zero.
