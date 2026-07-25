# ADR-094: Freshness `last_reviewed` — source-fix-first integrity + a commit-time audit tripwire

- **Status:** Accepted
- **Date:** 2026-07-05
- **Issue:** #5999 (epic #6003)
- **Ordinal note:** Ordinal chain: 085 (provisional) → 086 (re-verified at ship time — ordinal 085 was taken by the attention-inbox ADR, PR #6007) → **094** (this collision cleanup, #6054: three PRs concurrently claimed ordinal 086 on 2026-07-05; this one moved to the next-free ordinal).

## Context

Soleur already had the freshness *convention* — `last_reviewed` + `review_cadence`
frontmatter on ~40 knowledge-base files — and the *surfacing*: `review-reminder.yml`
(and the Inngest strategy-review crons) file an overdue-review issue when a doc
passes its cadence. The gap was integrity of the signal itself: **automated flows
silently bump `last_reviewed`**, so a staleness computation derived from it is false
confidence. A deepen-plan review (5 agents) corrected the original premise on two
points:

1. **There are TWO automated writers, not one.** Beyond `plugins/soleur/skills/brainstorm/SKILL.md`
   (the roadmap reconcile), `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts`
   instructs an agent to bump `last_reviewed` on `content-strategy.md`, auto-committed
   by the platform with no gate.
2. **A commit-time gate cannot be an integrity *guarantee*.** A `Context-Reviewed:`
   trailer is self-attestable by the committing agent, and `git commit -am`/pathspec,
   plus any commit outside the Claude Code Bash tool (Warp / IDE / CI / Inngest),
   bypass it entirely.

The always-loaded constitutional layer (`AGENTS.core.md`) was also outside the review
clock, and the byte budget (`B_ALWAYS` ≤ 23000, only ~5 bytes of headroom) left no
room to add frontmatter naively.

## Decision

1. **`last_updated` vs `last_reviewed` boundary.** `last_updated` records *any* write
   (including automated reconciles). `last_reviewed` records a *human review* and is the
   clock the cadence surfacing measures. An automated write must bump `last_updated`
   only, never `last_reviewed`.

2. **Source-fix-first — the integrity is the writer fixes, not the gate.** Both known
   automated writers now bump `last_updated` only: `brainstorm/SKILL.md` (the reconcile)
   and `cron-campaign-calendar.ts` STEP 3 (server-side — the gate cannot see its commit,
   so the source-fix is the *only* control there). Re-grepped for a third writer; none.

3. **A commit-time audit tripwire (detective, not preventive).** A `PreToolUse(Bash)`
   hook (`.claude/hooks/context-reviewed-gate.sh`) denies any commit through the Bash
   tool that *removes or changes* a `last_reviewed` line in a `*.md` file unless the
   message carries a `Context-Reviewed:` trailer, and logs undeclared attempts to the
   local incident ledger (`context-reviewed-*` rule_ids, orphan-gate-exempted). It unions
   the working-tree delta for `-a`/`-am`/pathspec commits (closes the `-am` bypass),
   exempts pure net-new adoptions (only `+`, no `-` — no trailer-fatigue, no self-trip),
   and splits fail-open into benign (silent) vs error (`hook_self_fault` warn).

4. **Guarantee-boundary statement (verbatim).**

   > This gate is a speed-bump + audit chokepoint, not an integrity guarantee. The `Context-Reviewed:` trailer is self-attestable by the committing agent; the gate relocates the honor-system boundary to a single greppable, incident-logged point. It does not prove human review; it is bypassed by `git commit -a`/pathspec (mitigated here via working-tree detection), by commits outside the Claude Code Bash tool (Warp/IDE/CI/Inngest), and by non-canonical key spellings. `last_reviewed` remains a cooperative signal, now with tamper-evidence. The trust anchor is the convention + the source-level fixes to known automated writers; the gate is its tripwire.

5. **Bring `AGENTS.core.md` under the clock, funded by a frontmatter-strip — no rule
   trim.** `AGENTS.core.md` gains `last_reviewed`/`review_cadence`/`owner` frontmatter.
   The session loader strips leading frontmatter before injection (at all three raw
   read-sites), and the budget lint measures *loaded* (post-strip) bytes — so `B_ALWAYS`
   is unchanged (22995) and no hard rule is trimmed for bytes the loader strips anyway.
   The strip contract is single-sourced (`scripts/lib/frontmatter-strip/`: byte-identical
   perl + python impls, a spec, shared fixtures, and a cross-check test), replacing
   hand-maintained regex parity. Both consumers guard against *over-strip*: the loader
   injects the RAW sidecar + a loud stamp note rather than a rule-shorn one (a governance
   blackout is a single-user incident); the lint fail-hard ERRORs rather than reporting a
   falsely-low `B_ALWAYS`.

6. **Reuse the existing KB-corpus consumer; add no new scanner.** `review-reminder.yml`
   is extended to also scan the repo-root `AGENTS.core.md` (which lives outside
   `knowledge-base/`) plus a required-constitutional-path *liveness assert* that fails the
   run loudly if that path is silently dropped from the scan (frontmatter/cadence removed,
   or feed drop). This acknowledges that the frontmatter is **already parsed by three
   independent consumers** (`review-reminder.yml`, `scripts/strategy-review-check.sh`,
   `cron-strategy-review.ts`); this change creates no new parser but does **not** claim to
   collapse those three (`cq-union-widening-grep`).

### Amendment — 2026-07-22 (#6794): third impl + promoters made unit-exact

This extends Decision §5's frontmatter-strip contract; it is **not** a new decision (no new ordinal).

1. **A third byte-identical implementation, `strip.ts`**, joins `strip.sh` and `strip.py` at
   `scripts/lib/frontmatter-strip/strip.ts`. All three are pinned byte-identical by
   `scripts/lib/frontmatter-strip.test.sh`, now extended to a three-way parity assertion.
2. **The two always-loaded-budget measurement consumers now measure on the stripped basis.**
   `cron-compound-promote.ts` (the runtime promoter contract) imports `strip.ts` via an
   extracted, unit-tested `measureAlwaysLoadedBytes` helper; `compound-promote.sh` (operator
   hand-testing) sources `strip.sh`. This closes the documented raw-vs-stripped skew (~73 B on
   `AGENTS.core.md`) that #6461 accepted knowingly as fail-safe — the promoter total now equals
   the commit gate's `B_ALWAYS` **exactly** (verified 22900 == 22900 at implementation time).
   The runtime consumer keeps the *dangerous*-direction over-strip guard (a malformed strip that
   drops a `[id:]` rule line falls back to RAW bytes + `op="frontmatter-overstrip-fallback"`).
3. **The parity test is now CI-enforced.** It was already reached by the scripts shard's
   `scripts/lib/*.test.sh` glob (so sh↔py parity ran), but that shard has no `bun`; registering
   it in `scripts/test-all.sh`'s `want_bun` block is what actually exercises the `strip.ts` arm
   in CI.

## Consequences

- The freshness signal gains real integrity from the source-fixes and tamper-evidence
  from the tripwire, honestly scoped: the gate is a detective chokepoint, never described
  as preventing automated bumps.
- The always-loaded constitution is now on a monthly review clock without spending any of
  the 5-byte `B_ALWAYS` headroom.
- A new single-sourced strip contract must stay byte-identical across bash + python;
  enforced mechanically by the cross-check test, not by hand.
- The loader is fail-closed-critical: the over-strip guard is load-bearing (a mangled
  sidecar = governance blackout). Kept aligned with the ≤200-byte stamp-header contract.
- Fully reversible: delete the gate + its registration, revert the loader/lint strip and
  the `AGENTS.core.md` frontmatter, revert the two writer fixes and the review-reminder
  extension, and delete this ADR.

## C4 impact

**None.** Checked `model.c4` / `views.c4` / `spec.c4`. `platform.plugin.kb` and
`platform.plugin.skills` are already modeled (`model.c4:67-89`). A dev-workflow metadata
convention (frontmatter + a local PreToolUse hook + a CI scan extension) adds no external
actor, no external system, no container/datastore, and no access-relationship — so there
is no context/container/component view to update. "None" is cited against the full
element enumeration per the completeness mandate, not asserted by omission.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Frame the gate as a preventive "integrity guarantee" | The trailer is self-attestable and `-am`/CI/Warp bypass it. The honest frame is source-fix + audit tripwire. |
| An A–F freshness GPA surfaced every session | Duplicates the overdue-issue channel; ambient noise on the wrong surface. |
| A `bump-frontmatter-updated.py` helper (original FR2) | Neither writer would call it (one is agent-prose, one is TypeScript); the gate + source-fixes are the enforcement. Cut. |
| A separate threshold/registry file | A second source of truth; reuse in-file `review_cadence` + the one existing scanner instead. |
| Fund the frontmatter via a hard-rule body trim | Trims *loaded* rule content for bytes the loader strips anyway; the lint measuring loaded (post-strip) bytes is the correct accounting. |
| Frontmatter on the `AGENTS.md` index | `AGENTS.md` loads raw via the harness `@`-import every session (unstrippable) — the YAML would leak into context. Frontmatter lives on `AGENTS.core.md` only. |
| Add a second overdue-review scanner for the rule layer | `review-reminder.yml` already walks the corpus; extend its feed + add a liveness assert instead of a parallel scanner. |
