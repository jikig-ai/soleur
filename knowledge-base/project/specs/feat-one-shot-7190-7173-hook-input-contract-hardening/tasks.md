# Tasks — hook-input contract hardening + trust-boundary extension

Plan: `knowledge-base/project/plans/2026-08-03-feat-hook-input-exit-codes-and-trust-boundary-extension-plan.md`
Closes: #7190, #7173 · Lane: cross-domain · Threshold: single-user incident

**Mutation discipline (applies to every RED step):** apply the mutation to a scratch copy,
observe RED, revert. Never commit a mutation. Record each in the PR-body table.

---

## Phase 0 — Baseline

- [ ] 0.1 Run `bash .claude/hooks/hook-input-contract.test.sh`; record exact pass/total
      (expected 50/50). Pin in the PR body as the delta anchor.

## Phase 1 — Exit codes (#7190 item 1)

- [ ] 1.1 In `hook-input-contract.test.sh`, assert `rc == 0` **inside** `decision_for()`
      and `bad` loudly on violation. Do NOT return `"<decision>/<rc>"`.
- [ ] 1.2 Add `rc_for()` for cases needing the code alone.
- [ ] 1.3 Add assertion **A16**: `INSCOPE20` × {unparseable, happy, deny} → `rc == 0`.
      Comment must state that a non-zero rc voids the stdout JSON channel.
- [ ] 1.4 RED proof: `exit 2` in `guardrails.sh` after `hook_input_emit_ask`.
- [ ] 1.5 RED proof: `exit 1` in a non-responder after `hook_input_report`.
- [ ] 1.6 RED proof: `exit 2` in a non-responder.

## Phase 2 — Merged reachability loop (#7190 items 2 + 3)

- [ ] 2.1 Collapse `a3_rce_regression()`'s `EVAL10` loop and
      `a14_bare_payload_coverage()`'s 4-hook loop into ONE loop over `INSCOPE20`,
      one sandbox per hook.
- [ ] 2.2 Per hook assert: (i) no attacker marker; (ii) a `hook-input-*` row in that hook's
      OWN `INCIDENTS_REPO_ROOT` — read `rule_id`/`kind` only, never `command_snippet`;
      (iii) `rc == 0`; (iv) stdout silent unless responder.
- [ ] 2.3 Preserve A3's existing positive control (the pinned vulnerable stub).
- [ ] 2.4 Responder predicate reads the CURRENT `HOOK_INPUT_RESPONDER` scalar. Do NOT
      forward-reference the Phase 5 set. A8's `responders` array stays literal here.
- [ ] 2.5 Empirically re-confirm all 19 non-responders are silent / RECORDS=YES / rc=0
      before widening. If any diverges, LIST it — do not trim the loop.
- [ ] 2.6 RED proof: `exit 0` at line 3 of two different hooks → absence green, presence RED.
- [ ] 2.7 RED proof: disarm the parse gate in a hook outside the original four → RED.

## Phase 3 — Vacuity, skips, fidelity (#7190 items 4 + 5 + 6)

- [ ] 3.1 Assert non-emptiness before content for every extracted range in
      `a11_mechanism_ban()`: the `_HOOK_INPUT_JQ` range (:472), the `hook_input_report`
      range (:478), and the A4 apostrophe range (:226).
- [ ] 3.2 Replace `grep -cE '\| jq '` (:469) with a token count — `\bjq\b` appears exactly
      twice in `lib/hook-input.sh` stripped of comments.
- [ ] 3.3 Add a `SKIPPED` counter + `skip()` helper; print in the summary line. Route the
      python3-gated fixtures (:234-244) through it.
- [ ] 3.4 Make the ":328 worktree ledger unchanged" assertion unconditional: synthesize a
      git repo in the sandbox with a `.claude/` the test owns; point
      `INCIDENTS_REPO_ROOT` at a DIFFERENT sandbox; assert the synthesized ledger is
      untouched while the target grows.
- [ ] 3.5 Make the ":338" aggregator walk a hard failure (a committed repo file's absence
      is a broken checkout, not a skip).
- [ ] 3.6 **Keep the jq SKIP.** Record the rejection rationale in the PR body (four
      reasons in plan Phase 3.6) — this discharges item 5's "justify whichever way you go."
- [ ] 3.7 Add assertion **A17**: byte-exact round-trip of a value with leading spaces,
      trailing spaces, an embedded newline and a TRAILING newline. Compare lengths AND
      content. Assert for `HOOK_CMD` and one other slot.
- [ ] 3.8 RED proofs (6): rename `_HOOK_INPUT_JQ`; rename `hook_input_report`; add a second
      `jq` as `$(jq …)`; delete the aggregator; whitespace-trim `HOOK_CMD`; drop sentinel +
      trailing separator.
- [ ] 3.9 Suite green; record delta vs Phase 0.1.

## Phase 4 — ADR-158 + C4 (contract — precedes Phases 5–6)

- [ ] 4.1 Write `ADR-158-extending-the-hook-input-trust-boundary-past-the-bash-hot-path.md`.
      Re-verify the ordinal is still free against `origin/main` first.
- [ ] 4.2 D1: one program, widened slots, per-slot flag vector, fixed named group
      predicates. Preserve: one fork, status-before-values, `catch {}`→object, empty
      bad-path values, RS separator, sentinel+trailing-separator pair, additive field order.
- [ ] 4.3 D2: responder is a SET; election is static and settings-derived; A9 asserts
      exactly one per matcher. State that ZERO responders is the P0 direction and TWO is P2.
- [ ] 4.4 D3: mirror denies on `nonstring`/`separator`, fails open LOUDLY on
      `unparseable`/`jq_missing`/`internal`. Ground it in ADR-157:115's self-referential-
      repair rationale (NOT hook count). Covers all THREE mirror hooks.
- [ ] 4.5 `## Alternatives Considered` must carry all four rejections: flat widening
      (forced-ask vector); auxiliary program (fork cost on `Write`); guardrails-on-extra-
      matchers (conflates universal responder with a Bash-specific guard — also the
      probe-failure fallback); uniform-deny-on-rc-1 (behavior change on 3 of 5 classes).
- [ ] 4.6 C4: amend `model.c4:68` `engine.hooks` description to name the mirror, its
      `.working_dir`/`.tool_input.path` envelope, `exit 2` + `{"decision":"deny"}`, the
      absence of `ask`, and ADR-158 D3. Amend the `claude -> hooks` edge (:390) if D2
      changes what "the responder" means. NO new element; NO `views.c4` change.
- [ ] 4.7 Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [ ] 4.8 Forward pointers from ADR-156 and ADR-157 to ADR-158.

## Phase 5 — CC-side migration (#7173a)

- [ ] 5.1 **Reachability probe (precondition).** For each candidate, establish what a
      non-string field actually buys an attacker — does the harness reject non-string
      `tool_input` for these tools? Record the outcome; let it SIZE the migration set.
- [ ] 5.2 **`ask`-honored probe (precondition).** `DEFER-DECISION-PAYLOAD-SHAPE.md:5`
      probed only a `PreToolUse(Bash)` stub. Probe `mcp__pencil__open_document` and
      `CronCreate`. If not honored → fall back to ADR-158 D2's recorded alternative or
      descope those two hooks. Do NOT build on an unverified harness invariant.
- [ ] 5.3 Helper D1: widen `_HOOK_INPUT_JQ`; replace record 0 with the per-slot flag
      vector; add group predicates; update the slot-count detector (`n != 6` → new count).
      Core slots keep positions 1–5.
- [ ] 5.4 Helper D2: `HOOK_INPUT_RESPONDER` → `HOOK_INPUT_RESPONDERS` space-list (bash 3.2
      — no `declare -A`); `hook_input_should_ask` → membership test. Generalize A9's jq to
      `--argjson responders` + exactly-one-per-matcher. Re-verify A9's non-vacuity control.
      Update A8's array and Phase 2's responder predicate.
- [ ] 5.5 Verify `A11 helper forks jq exactly once` passes UNCHANGED (D1 preserves it).
- [ ] 5.6 Migrate `skill-security-scan-write` (`content`).
- [ ] 5.7 Migrate `new-scheduled-cron-prefer-inngest` (`content`, `new_string`).
- [ ] 5.8 Migrate `pencil-open-guard` (`filePath`) — gated on 5.2.
- [ ] 5.9 Migrate `durable-reminder-prefer-inngest` (`prompt`, `tool_name` only — its
      booleans stay on the existing `has()`-guarded read at :83-84) — gated on 5.2.
- [ ] 5.10 Grow `INSCOPE20`; confirm A13's three call-site verbs pass for each new member.
- [ ] 5.11 README: move migrated hooks into the mandate list; rewrite the two-blocker prose
      (blocker 2 applies to zero hooks; the boolean blocker was never real); DELETE the
      hardcoded counts.
- [ ] 5.12 README: hook-specific exemption reason for each of `pencil-collapse-guard`
      (note it restores a file from git on an unasserted `filePath`), `agent-token-tee`
      (reads a `.tool_response.*` family the program does not model),
      `docs-cli-verification`, `phase-surface-hint`, `skill-context-queries`,
      `skill-invocation-logger`. No shared blanket.

## Phase 6 — OpenHands + integration (#7173b)

- [ ] 6.1 README: replace "Convergence is a tracked follow-up" with the Phase 6.1 rationale
      — all THREE mirror hooks already type-assert; the gap is duplication, not an absent
      assertion; convergence would cost a cross-tree fail-hard `source`.
- [ ] 6.2 Extend `pre-merge-rebase-parity.test.sh`: non-string envelope → `.claude` asks,
      `.openhands` denies.
- [ ] 6.3 Extend it: `unparseable` envelope → `.openhands` FALLS THROUGH (pins D3's narrow
      scope).
- [ ] 6.4 Header comment records the new divergence class prevented.
- [ ] 6.5 Verify existing T-S fixed-string cases (:175-193) and behavioural cases (:54-65)
      still pass — verify, do not assume.
- [ ] 6.6 Full `bash scripts/test-all.sh` green.
- [ ] 6.7 Re-run the full mutation battery from a clean tree; `git status` shows only the
      intended diff.
- [ ] 6.8 PR body: mutation table (12 mutations, Phases 1–3), both probe outcomes, the jq
      decision, final assertion + skip counts vs baseline, `Closes #7190`, `Closes #7173`.
- [ ] 6.9 Confirm `decision-challenges.md` is surfaced by `/ship` (DC-1 PR split, DC-2
      #7173b discharge).
