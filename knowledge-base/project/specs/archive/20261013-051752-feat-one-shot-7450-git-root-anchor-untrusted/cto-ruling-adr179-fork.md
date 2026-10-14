# CTO ruling — the §E architectural fork (B2 / B3 / B4)

Binding. Routed to `soleur:engineering:cto` per the architectural-fork routing rule, because
both instruments ADR-179 sanctions were blocked on §R1, which is itself "Tracked in #7450".
Prompted "do NOT use AskUserQuestion". Implement as returned; record as an ADR-179 amendment.

## Framing corrections the ruling made to the panel's findings

- **C1 — B3 is not 20 sites.** It is 20 markdown sites PLUS three payload **scripts** carrying
  the identical vector, which the panel's `SKILL.md`-only grep missed:
  `skills/gdpr-gate/scripts/gdpr-gate.sh` (itself a compliance gate),
  `skills/ship/scripts/net-issue-flow.sh` (a ship gate), and
  `skills/compound/scripts/token-efficiency-report.sh`. **VERIFIED independently** — all three
  derive `REPO_ROOT` from `git rev-parse --show-toplevel` and then source
  `$REPO_ROOT/.claude/hooks/lib/incidents.sh`. All three already carry the no-op-if-absent
  shape, so each is a one-line fix. They must land in the same PR or the corpus-wide assertion
  reports a **false zero** — the same defect class as 18c's syntax-keyed needle.
- **C2 — "`source` is strictly worse" overstates it.** Each Bash call is a fresh shell, so
  `source` gains no persistence. The real delta is scope WITHIN the call: it can redefine
  `git`/`gh`, mutate `PATH`, install traps. Both forms are already arbitrary code execution.
- **C3 — "ADR-179 leaves exactly two instruments" is FALSE.** Decision 1 governs **paths**.
  Nothing requires a telemetry emission to be expressed as a path. That misreading is what
  produced the deadlock.
- **C4** — B2's needle is `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}`, no leading `./`.
- **C5** — ADR-179 option (e) is over-broad as written: `scripts/resolve-git-root.sh` is live
  and correct as a **workspace/data** root (three hook consumers). Option (e) rejects it only
  as a **code root / trust anchor**. Scope it, or someone deletes a working helper.

## Ruling

1. **B3 → invert the invocation (new decision 9).** Neither ADR-179 instrument. Delete every
   `source … && emit_incident` from payload markdown; replace with an inert `printf` marker.
   No source, no path, no file resolution — **no operand to shadow**. A monorepo-only
   PostToolUse/`Bash` hook parses the marker and calls `emit_incident`, resolving its lib via
   `${CLAUDE_PROJECT_DIR}` exactly as `.claude/hooks/git-commit-secret-scan.sh` already does.
   PostToolUse **not** PreToolUse: PreToolUse counts intent and would over-count against
   today's execution-counting semantics, breaking rule-metrics comparability.
   The hook MUST validate the rule id against a closed corpus and sanitize the note, because
   the markdown that prompts the marker is contributor-writable on the review path. This bounds
   the worst case from arbitrary code execution to **a rejected JSONL row**.
   - *Rejected — relocate into the payload:* inverts decision 4 reason 1 (stated "independently
     dispositive"), which says the rule-corpus telemetry "does not and should not exist on a
     customer machine". Relocation MANUFACTURES that input on every customer machine.
   - *Rejected — monorepo sentinel:* §R1 records it is satisfied by `gh pr checkout` and is
     "not a defense on the review path". Gating the review-path vector behind a gate the review
     path satisfies would repeat the ADR's own corrected error.
   - *Also rejected:* drop telemetry entirely (blacks out the CONCUR-threshold measurement);
     a payload-side shim (must still locate the monorepo lib — same problem one level down);
     deriving from `skill-invocation-logger.sh` (cannot distinguish rule-id-at-phase).
2. **B2 → decision 1, unmodified.** Different instrument because the target is IN the payload.
   Bare quoted anchor + decision-2 preflight + decision-7 presence guard. Ships now, waits on
   nothing: sound under both branches of §R3. Widen 18c to any `${CLAUDE_PLUGIN_ROOT:-` under
   the payload with a monotonically-shrinking allowlist for the ~105 sites deferred to #7453 —
   **not** a flat zero, which would force the whole #7453 migration into this P0 PR. Add a
   second, **stakes-keyed** assertion with no allowlist: zero `:-` on any site whose invoked
   script reads a secret, discovered on disk rather than hard-coded.
3. **B4 → DELETE, do not replace.** Measured dead (all 22 sites emit the `:-` form). Delete
   anyway: it is the only grant of no-prompt execution to the rejected form, and agents read
   `settings.json` as documentation of the sanctioned shape. Not replaced, because the loader
   substitutes the token before delivery so no static literal can match — that belongs with the
   git-worktree migration in #7453, alongside `EXACT_LITERAL_SAFE_COMMANDS`.
   **New decision 8:** the ban extends to operator config, asserted structurally.
4. **§R1 → SETTLED, scoped, one half re-routed. #7450 may close.** §R1 conflates two claims.
   "The sentinel does not authenticate the tree on the review path" is true and **unfixable by
   any in-tree instrument** — every byte in a checked-out tree is contributor-writable,
   including any sentinel added to authenticate it. The disposition is therefore not a stronger
   sentinel but the removal of trust decisions from CWD-resident operands (decisions 1, 8, 9).
   **Re-routed, not closed here:** a review session opened INSIDE a contributor-checked-out
   worktree executes that tree's `.claude/hooks/*.sh` on every tool call. That is a strictly
   LARGER exposure than any path anchor, is not an anchoring defect, and must not hold #7450
   open. File as a separate P0.

## Classification rule for the remaining corpus (so #7453 needs no re-deciding)

| Class | Test | Disposition |
| --- | --- | --- |
| **Code root** | Does the resolved path get executed (`source`/`bash`/`python3`/`awk`)? | Ban. Bare anchor if in payload; decision-9 inversion if monorepo-only. |
| **Data root** | Only read or written as content? | **Allowed and correct** — the workspace is what it measures. |
| **Repo-root `scripts/` class** | Executes, target outside the payload | Code root. Route to #7453. |

Data roots — leave: `one-shot/SKILL.md`, `plan/SKILL.md`, `preflight/SKILL.md` (681, 1104),
`community/SKILL.md`, `kb-search-cache.sh`, `audit-models.sh`, `harvest-debt.sh`.
Code roots — route to #7453 above baseline: `preflight/SKILL.md` (788, 974 — Pattern C) and
`compound/SKILL.md`'s repo-root `scripts/` invocation.

## Sizing

Medium, 1–2 days including tests. No prerequisites outside this PR; nothing waits on #7452,
#7453, or the §R3 substitution branch. **Ordering matters:** the three payload scripts land
before or with the 20 markdown sites, or the corpus-wide assertion is a false zero.
