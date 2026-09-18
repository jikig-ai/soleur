# ADR-227: Compaction state is read from a per-session ephemeral ledger, because the transcript answers too late

- **Date:** 2026-09-18
- **Issue:** #8323
- **Supersedes in part:** the plan's provisional title, "the compaction signal
  is read from the transcript, not from a counter file", which the Phase 0
  measurement falsified before implementation began. It is recorded under
  Alternatives as (a) rather than deleted, because the reasoning that made it
  attractive is still correct and the thing that killed it is a timing fact
  nobody could have read off the docs.

## Status

Accepted.

## Context

Soleur told the operator to "run `/clear` and resume" at two fixed points, the
end of `plan` and the end of `work`, regardless of whether context compaction
had ever occurred. On a session with no compaction the nudge is noise; on a
session that auto-compacted twice mid-`/work` it arrives long after the model
lost the branch, PR and plan state it needed. Locally, 8 of 22 recent sessions
compacted, 11 boundaries in total, so both halves of that mismatch are real
rather than hypothetical.

Claude Code 2.1.76+ exposes the compaction lifecycle to hooks (`PreCompact`,
`PostCompact`, and `SessionStart` with matcher `compact`), and it records every
compaction in the session transcript as a `compact_boundary` record carrying
`compactMetadata.{trigger, preTokens, postTokens}`. The obvious design —
and the one this plan carried into implementation — is to read the transcript at
`SessionStart:compact`, count the boundaries, and decide from that.

**That design does not work, and the reason is a flush ordering no document
states.** Measured on 2026-09-18 against CLI 2.1.273, with a marker hook bound
in a throwaway project and driven by headless `claude -p --continue "/compact"`:

| Reading | Result |
|---|---|
| Boundary count at `SessionStart:compact`, compaction #1 | **0** — the file held 1 afterwards |
| Boundary count at `SessionStart:compact`, compaction #2 | **1** — the file held 2 afterwards |
| Same count at `PostCompact`, ~100 ms later | unchanged, still lagging |
| The boundary record's own `timestamp` | `16:10:14.926Z`, *preceding* the hook fire at `16:10:14.957Z` |

So the record exists in memory when the hook runs and is flushed to disk after
it returns. The transcript cannot answer "how many compactions has this session
had" at the only moment the question matters, and the `SessionStart` envelope
carries no `trigger` field either (`PreCompact` has `trigger`; `SessionStart`
has `source`), so the current compaction's trigger is equally unavailable from
that side. Reading the last on-disk boundary yields the *previous* compaction's
trigger.

A second measurement shaped the mechanism that replaced it. **`PreCompact`
firing does not imply a compaction occurred**: three fires produced two
boundaries, because a `/compact` with nothing left to compact fires `PreCompact`
and then no `SessionStart:compact` at all. Any design that counts `PreCompact`
events over-counts, and over-counting here means recommending that the operator
abandon a healthy session one compaction early — with every fixture green,
because a fixture that replays only complete cycles cannot see it.

## Decision

`plugins/soleur/hooks/compaction-state.sh` derives compaction count and trigger
from a **per-session ephemeral ledger under `TMPDIR`**, written by the same hook
across two bound events, using **pending-then-commit**:

- `PreCompact` **overwrites** a single `pending` slot with its own stdin
  `trigger`. It never appends, precisely because it fires on no-op compactions.
- `SessionStart:compact` **commits** that slot as one ledger line, clears it,
  then counts. It fires exactly once per real compaction, so the ledger holds
  one line per compaction and each line carries that compaction's own trigger.
- `SessionStart` with `source` in `startup|resume|clear` **truncates** the
  ledger and clears pending.

That third arm is why the `SessionStart` matcher is `startup|resume|clear|compact`
rather than `compact` alone. It is also what makes the session-window scoping
exact rather than approximated: boundaries accumulate within one transcript
across `--resume`, so an all-time count would pin the recommendation on forever
for a long-lived resumed session.

The recommendation rule is one integer and one string: `trigger == "auto" AND
count_auto >= ${SOLEUR_COMPACTION_COUNT_THRESHOLD:-2}`.

**No counter file is introduced in the user's repository, and nothing is
written to the knowledge base.** The ledger lives under `TMPDIR`, is keyed on
the session id, is age-reaped after seven days, and is disposable by
construction: losing it costs one directive, never correctness.

**The transcript is not read at all.** An earlier revision of this decision kept one grep for a
`prior_boundaries` corroboration marker; the review panel deleted it — see `## Amendment` below.

**No `PostCompact` binding ships in this slice.** See alternative (g).

## Alternatives Considered

**(a) Read the count from the transcript at `SessionStart:compact`** — the
plan's primary design. Rejected on the measurement in §Context: the boundary is
not yet flushed, so the count is short by exactly one and the trigger belongs to
the previous compaction. Nothing about the record's *shape* is wrong; the
timing is. Recorded first because it is the design a future reader will reach
for again.

**(b) Piggyback `.claude/.session-manifests/<sid>.json`** — the obvious existing
host. Rejected twice over: it is repo-side, and `session-rules-loader.sh`
overwrites it on every SessionStart **including `compact`**, so the hook's own
state would be destroyed by the event that needs it.

**(c) A counter store committed in the user's repository.** Rejected: it needs a
`.gitignore` entry the plugin cannot add to a user's repo, so it would either
dirty every customer's working tree or be committed by accident.

**(d) The per-session `TMPDIR` ledger.** **Accepted** (see §Decision). It is not
alternative (c): (c) lived in the user's repository and needed an un-addable
ignore rule; this is machine-local, disposable, and reaped. The plan authorized
it as a conditional fallback and the measurement made it the primary. Its one
correction relative to the plan's wording is pending-then-commit instead of
append-per-`PreCompact`, forced by the 3-fires-2-boundaries measurement.

**(e) Skill prose only — tell the model to notice its own compactions.**
Rejected: a model cannot observe its own compaction count. This is the status
quo the feature replaces, and its defect is that it fires identically on a
session with zero compactions and one that has lost state twice.

**(f) `PostCompact` plus a `UserPromptSubmit` rebinding.** Rejected: `PostCompact`
stdout is never model-visible, so the directive would have to be smuggled into a
later event. It also inherits the same lagging count — measured, `PostCompact`
read the stale value 100 ms after `SessionStart:compact`.

**(g) A `PostCompact` checkpoint writer into `session-state.md`**, with a
gitleaks guard. **Deleted by a six-agent plan review**, unanimously, and tracked
for re-proposal at **#8328**. It is recorded here with its two P0s so the
re-proposal inherits them rather than re-deriving them:

1. **Nothing reads it.** `work/SKILL.md` Phase 0 loads `constitution.md`,
   `tasks.md` and `spec.md` — never `session-state.md`. The block would be
   write-only.
2. **`one-shot/SKILL.md` step 3 writes that file from a whole-file template**
   containing no marker, so every plan-phase run destroys any hook-owned block.
   The hook can respect the skill; the skill cannot respect the hook.

Two supporting findings: `.gitleaks.toml` exists at this repo root and nowhere
under `plugins/soleur/`, so on a customer install the guard fail-opens on
essentially every install; and `gitleaks git --pre-commit --staged` reads the
git index, not a string, so the prescribed command could not have done the job.
The gdpr-gate finding about an absolute worktree path carrying the OS username
into a tracked, pushed file is inherited by #8328 with the writer.

**(h) Statusline `context_window`.** Rejected: measured unreachable from hooks.

**(i) A token-ratio clause** (`postTokens/preTokens > 0.15` as a second trigger).
Rejected at review on three independent grounds: the threshold was picked from
n=1 and sits *above* the only real measurement (1006181 → 105006 = 0.104), so it
would never have fired on observed data; it is not independent of the count
clause; and the prescribed `awk 'print (a/b) > 0.15'` is file redirection in
awk, which creates a file named `0.15` and always succeeds.

**(j) Deriving the current phase from the transcript's last `Skill` record.**
Rejected at review: the last record is not the current phase (measured:
`soleur:preflight`), and inside `/soleur:one-shot` it is the child skill, so the
one-shot exception rested on a signal the read path cannot produce. The
directive names the branch and the plan path instead; the phase is legible in
the artifacts it orders re-read.

**(l) Read the transcript count and ADD ONE.** §Context proves the lag is exactly one, twice, so
this is the design a reader reaches for next and the ADR owes it an answer. It fails for a reason
stated elsewhere in this record and not previously connected to it: boundaries accumulate within a
single transcript across `--resume`, so `on_disk + 1` is an **all-time** count, not a
**session-window** count — precisely the failure the reset arm exists to prevent (TR2). It is also
undefined for a `--fork-session` child, whose transcript inherits a prefix of the parent's
boundaries.

**(m) Drop the `trigger` discriminator and bind `SessionStart:compact` alone.** `SessionStart:compact`
fires exactly once per real compaction, so counting *that* event needs no `PreCompact` binding, no
pending slot, no overwrite semantics and no cross-event state — the whole mechanism above exists to
carry one string across an event boundary that cannot carry it. Rejected because the `SessionStart`
envelope has no `trigger` (measured), so the rule would have to fire on manual `/compact` too. FR2
is explicit that a manual compaction never satisfies it: an operator who types `/compact` has made a
deliberate choice and does not need to be told to abandon the session. Recorded because it is the
cheapest design in the set and a reader should see it was weighed.

**(n) A transcript-format drift canary (FR7).** Shipped in an earlier revision of this branch and
**deleted by the review panel** — see `## Amendment` below.

## Consequences

- The feature is **Claude Code only**. Codex, Devin and Grok Build degrade to
  silence and say so in their `INSTRUCTIONS.md`; the skill-prose fallback keeps
  the end-of-work resume prompt firing everywhere, with no `/clear` nudge.
- A **plugin hook is global**, so the scope guard is load-bearing rather than
  hygienic. It is `welcome-hook.sh`'s sentinel — a `plugins/soleur` directory —
  **plus** a Soleur plan/spec artifact, never `git rev-parse --is-inside-work-tree`,
  which is true in every customer repo. Without it, a customer compacting work
  on their own application would have their summary shaped around PR numbers and
  operator holds they do not have. This was the worst finding in the plan review
  and both conjuncts are mutation-proven.
- **The guard's real population is Soleur DOGFOODING repos, not marketplace customers.** A
  marketplace install puts the plugin under `~/.claude/plugins/`, never in the user's repository, so
  the `plugins/soleur/` sentinel selects this monorepo and forks of it. The feature therefore ships
  to every customer and fires for approximately none of them. That is the intended first posture —
  dogfood the directive before widening it — but it is a consequence of the guard rather than an
  accident, and an earlier draft of this ADR framed the guard purely as blast-radius control and let
  a reader conclude customers get the directive. If the population should be Soleur *users*, the
  sentinel to switch to is the `sync`-written knowledge-base artifact (`connectedRepoKb` in the C4),
  not the plugin directory.
- **`--fork-session` is a known, silent gap.** Measured: a fork gets a new `session_id`, a new
  transcript, and fires **no `SessionStart` hook at all** — so its ledger is absent and its count
  starts at zero, while it inherits the parent's entire compacted context. The fork is the session
  most in need of the recommendation and is guaranteed not to receive it. It fails safe
  (under-counts, never over-recommends) and is recorded here because nothing in the system reports it.
- **The scope walk is anchored at the enclosing repository.** It stops at the first directory
  carrying `.git`, matching `welcome-hook.sh`, which resolves one `GIT_ROOT` and tests exactly one
  directory. An unanchored walk is strictly wider than that precedent: a Soleur checkout at `~/dev`
  would make the guard pass for every unrelated repo nested beneath it, and nesting is this repo's
  own `.worktrees/` layout rather than a hypothetical.
- Fail-open is the contract: every path exits 0, and `trap 'exit 0' ERR EXIT`
  carries it. The `EXIT` arm is load-bearing and measured, not assumed — on bash
  5.3.15 a `set -u` unbound-variable fault with an ERR-only trap exits **127**;
  with the EXIT arm it returns 0. Any non-zero exit other than 2 makes Claude
  Code silently drop the whole JSON output.

## Verification

- `plugins/soleur/test/compaction-state-hook.test.sh` — 103 cases over 104
  subject invocations, with an instrument self-test that drives both assertion
  arms and refuses to continue unless both counters and the failure ledger move,
  plus case and subject-invocation floors reported with `printf` + `exit` rather
  than through the helpers they backstop.
- A 22-row mutation battery kills 22, with a green control and a byte-identical
  restore check. Three rows survived the first pass: a whole-scenario deletion
  survived a floor with 19 cases of slack (both floors are now pinned to the
  measured count); dropping the `trigger == auto` operand survived because the
  manual-only fixture has `count_auto = 0` and cannot discriminate (scenario 19
  adds two autos followed by a manual, which can); and the third was an
  instrument defect rather than a result — the md5 landed-check proved *a* byte
  changed while the `replace` had hit the header comment quoting the trap line,
  so the row was scored against an unmutated subject.
- `scripts/followthroughs/compaction-format-drift-8323.sh` — all four arms
  driven, including a renamed `subtype` going RED and a positive control still
  going GREEN.

## Amendment — 2026-09-18 (review panel): the transcript read and its canary are deleted

A two-lens design-validity pass (`code-simplicity-reviewer`, `architecture-strategist`) converged,
by different routes, on the corroboration read and everything built to protect it. Recorded here
rather than only in the PR, so a future reader does not re-propose it.

**What was deleted:** the `prior_boundaries` field and the transcript grep that produced it;
`scripts/followthroughs/compaction-format-drift-8323.sh`; `.claude/hooks/compaction-drift-canary.sh`
and its `.claude/settings.json` binding; four `SOLEUR_COMPACTION_DRIFT*` env vars; the
`spaced-boundary.jsonl` fixture; the AP-020 widening; and the `claude -> hooks` C4 edge amendment
(both now byte-identical to `main` again).

**Why, on four measured grounds:**

1. **Nothing consumed the field.** `plan/SKILL.md` and `work/SKILL.md` read `SOLEUR_COMPACTION_DIRECTIVE`
   and `recommend=true`; a repo-wide grep found the only other references were the canary files that
   existed to guard it.
2. **The number was not even a legible off-by-one.** The ledger resets per session window while the
   transcript accumulates across `--resume`, so after any reset the two figures diverge arbitrarily.
   The directive was handing a model two disagreeing counts with no reconciliation rule.
3. **The canary could not report.** It exited 0 unconditionally and emitted its only finding on plain
   stderr, which `.claude/hooks/README.md` records as discarded for an exit-0 hook — and it wrote its
   cadence stamp *before* the run, so a RED verdict suppressed itself for seven days.
4. **It guarded the wrong thing.** Since this decision moved the count to the ledger, the format the
   feature depends on is the **stdin envelope** (`hook_event_name`, `source`, `trigger`, `session_id`),
   not the transcript. A rename of `compact_boundary` cannot break the feature; a rename in the
   envelope can, and the canary was blind to it.

**What replaces it:** nothing, deliberately, and the residual risk is named rather than mitigated. No
offline probe can observe the envelope contract — it exists only at hook-fire time. The hook fails
open to silence, every marker carries the `claude --version` string for drift attribution, and the
measurements this decision rests on are recorded in `compaction-state.sh`'s header so a CLI bump has
something to be re-measured against. The aggregated signal that would actually detect "the hooks
stopped firing" is the local ledger metric already tracked at **#8324**; no new issue was filed,
because that one already covers it.
