# Tasks — hook-input contract hardening + trust-boundary extension

Plan: `knowledge-base/project/plans/2026-08-03-feat-hook-input-exit-codes-and-trust-boundary-extension-plan.md`
Closes: #7190, #7173 · Lane: cross-domain · Threshold: single-user incident

**Mutation discipline (applies to every RED step):** apply the mutation to a scratch copy,
observe RED, revert. Never commit a mutation. Record each in the PR-body table.

---

## Status — what shipped, and what did not

`[x]` done · `[~]` **descoped to #7219**, with the design work carried forward there.

**#7190 — complete.** All six items. Suite 50/50 → 62/62, 0 skipped. Mutation battery of
16, run against both `origin/main` and this branch in a sandboxed hook tree: **11 were
survivors on main and are now caught, 0 survive.**

**#7173 — half shipped, half deferred.**

- **(b) OpenHands mirror — shipped, and larger than the issue thought.** The premise that
  the mirror only needed de-duplication was refuted by measurement: it had a live bypass
  (any jq-rejected document aborted at rc 5 before the type check, inducible by a lone
  surrogate in a *sibling* field while the command stayed a clean `rm -rf $HOME`) and an
  availability bug (an unsatisfiable `$t == null` conjunct denied every payload with an
  absent or null `tool_input`). Both fixed in all three mirror hooks, both with parity
  coverage. ADR-160 records the reason-class decision the issue actually asked for.
- **(a) advisory-hook migration — descoped to #7219.** The six genuinely-advisory hooks
  and `security_reminder_hook.py` now carry per-hook exemption reasons in the README, so
  they are documented rather than residue. The four **gating** hooks are not exempt on
  principle and did not ship: publishing their fields means widening the slot contract,
  and the per-slot widening opens two holes no design closes yet — an `allow`-vs-`ask`
  collision that becomes reachable for the first time and whose resolution order is
  unestablished, and a silent fail-open where a non-string `.tool_input.content` leaves
  the responder's core group clean while the scanner exits 0. Establishing the first
  needs a live hook registration and a real permission prompt; ADR-156 forbids assuming
  it. **Operator decision, 2026-08-03:** ship the rest now, follow up in #7219.

**Phase 6.0 (probe the OpenHands runtime's non-0/2 exit semantics) was not run and is no
longer needed.** The fix removes the dependency rather than resolving it: no mirror hook
now exits outside {0, 2}, so the runtime's treatment of other codes is not load-bearing.

---

## Phase 0 — Baseline

- [x] 0.1 Run `bash .claude/hooks/hook-input-contract.test.sh`; record exact pass/total
      (expected 50/50). Pin in the PR body as the delta anchor.

## Phase 1 — Exit codes (#7190 item 1)

- [x] 1.1 **[v3/F7]** Leave `decision_for()` UNCHANGED. Do NOT call `bad` inside it — it
      runs inside `$( )` at ~25 sites, so the FAIL increment is lost to the subshell
      (measured `FAIL_after=0`) and the suite exits 0 having detected a non-zero rc and
      discarded it. v2's rejection of the value-carrying return was backwards.
- [x] 1.2 Add `rc_for()`; A16 owns the rc assertion in the caller's shell via `want`.
- [x] 1.3 Add assertion **A16**: `INSCOPE20` × {unparseable, happy, deny, **jq_missing**}
      → `rc == 0`. **[v3/F10]** The 4th class is mandatory: `jq_missing` is where the
      printf ask envelope is the ONLY surviving channel, so a non-zero exit there voids
      the ask with zero telemetry. Reuse A5's shim PATH (:253-278). A mutation
      `[[ "$HOOK_INPUT_REASON" == jq_missing ]] && exit 1` survives A16 without it.
- [x] 1.4 **[v3/F10]** Scope A16's NAME/comment to the probed classes, not "every path" —
      `pre-merge-auto-close-scan.sh:252` carries a deliberate commented `exit 2` on an
      unreached branch; do not invite a maintainer to delete it as a contract violation.
- [x] 1.5 RED proof: `exit 2` in `guardrails.sh` after `hook_input_emit_ask`.
- [x] 1.6 RED proof: `exit 1` in a non-responder after `hook_input_report`.
- [x] 1.7 RED proof: `exit 2` in a non-responder.
- [x] 1.8 **[v3/F22]** Budget runtime: A16 adds ~60 hook invocations to a 9.1s baseline.
      Reuse Phase 2's invocations where possible.

## Phase 2 — Merged reachability loop (#7190 items 2 + 3)

- [x] 2.1 Collapse `a3_rce_regression()`'s `EVAL10` loop and
      `a14_bare_payload_coverage()`'s 4-hook loop into ONE loop over `INSCOPE20`,
      one sandbox per hook.
- [x] 2.2 Per hook assert: (i) no attacker marker; (ii) a `hook-input-*` row in that hook's
      OWN `INCIDENTS_REPO_ROOT` — read `rule_id`/`kind` only, never `command_snippet`;
      (iii) `rc == 0`; (iv) stdout silent unless responder; **(v) [v3/F15] no stray
      artifacts** — A12 (:161-176) appears in neither v2's four properties nor AC3 and
      currently depends on the SHARED `$run` that per-hook sandboxes dissolve. Keep
      `.claude` allow-listed (each sandbox is now also an `INCIDENTS_REPO_ROOT`).
- [x] 2.3 Preserve A3's existing positive control (the pinned vulnerable stub) — **[v3/F15]
      it needs its OWN directory** once the shared `$run` is gone.
- [x] 2.3b **[v3/F11]** Property (iv) WILL go RED for 3 of 4 Phase-5.6 migration targets:
      `skill-security-scan-write`, `new-scheduled-cron-prefer-inngest` and
      `durable-reminder-prefer-inngest` all emit an unconditional explicit
      `permissionDecision:"allow"` (measured). Either Phase 5.6 rewrites their emit
      behaviour or property (iv) carries an explicit exempt list. Decide before Phase 5.
- [x] 2.3c **[v3/F22]** Consider dropping property (iii) here (it duplicates A16's
      unparseable class) or driving Phase 2 with the HAPPY class so the two cover
      disjoint ground.
- [x] 2.4 Responder predicate reads the CURRENT `HOOK_INPUT_RESPONDER` scalar. Do NOT
      forward-reference the Phase 5 set. A8's `responders` array stays literal here.
- [x] 2.5 Empirically re-confirm all 19 non-responders are silent / RECORDS=YES / rc=0
      before widening. If any diverges, LIST it — do not trim the loop.
- [x] 2.6 RED proof: `exit 0` at line 3 of two different hooks → absence green, presence RED.
- [x] 2.7 RED proof: disarm the parse gate in a hook outside the original four → RED.

## Phase 3 — Vacuity, skips, fidelity (#7190 items 4 + 5 + 6)

- [x] 3.1 Assert non-emptiness before content for every extracted range in
      `a11_mechanism_ban()`: the `_HOOK_INPUT_JQ` range (:472), the `hook_input_report`
      range (:478), and the A4 apostrophe range (:226).
- [x] 3.1b **[v3/F21]** The A4 apostrophe range (:226) does NOT need the non-emptiness
      guard — measured, an empty range yields `-2` and `want "0" "-2"` is already RED.
      A11's program check IS vacuous today (`printf '%s\n' "" | grep -cF '$'` → 0). Add
      the guard for uniformity if you like, but do not claim it fixes a survivor.
- [x] 3.2 Replace `grep -cE '\| jq '` (:469) with a token count — `\bjq\b` appears exactly
      twice in `lib/hook-input.sh` stripped of comments (VERIFIED; raw count is 28, so the
      comment strip is load-bearing). **[v3/F17]** Use `grep -oE '\bjq\b' | wc -l`, NOT
      `grep -c` (which counts LINES — a second `jq` on an existing line would pass).
      Retitle the assertion: this is a token count, not a fork count (relocating the
      invocation into a loop keeps it at 2). **Reconcile AC16**, which requires this
      assertion pass "unchanged" while 3.2 rewrites it.
- [x] 3.3 Add a `SKIPPED` counter + `skip()` helper; print in the summary line. Route the
      python3-gated fixtures (:234-244) through it. **[v3/F20]** The `:29` jq precondition
      exits BEFORE the summary prints — make that path print the summary form too, or a
      jq-less machine emits no line for `test-all.sh` to read.
- [x] 3.4 **[v3/F8 — NO git synthesis].** `_incidents_repo_root()` (`lib/incidents.sh:36-42`)
      falls back to `dirname(BASH_SOURCE)/../../..` — helper-relative, NOT cwd/git-relative
      (verified). A synthesized sandbox repo is a location the fallback can never return, so
      asserting its ledger is untouched CANNOT FAIL — vacuous, in the phase whose purpose is
      removing vacuity. And `git init` re-couples to the branch-dependent gate :56-58 avoids
      (#5192). Instead: point `INCIDENTS_REPO_ROOT` at sandbox `T`; assert (a) `T`'s ledger
      GREW and (b) `$REPO_ROOT/.claude/.rule-incidents.jsonl` is BYTE-IDENTICAL (absent = 0
      both sides). Mutation: delete the `INCIDENTS_REPO_ROOT` branch → both RED.
- [x] 3.5 Make the ":338" aggregator walk a hard failure (a committed repo file's absence
      is a broken checkout, not a skip).
- [x] 3.6 **Keep the jq SKIP.** Record the rejection rationale in the PR body (four
      reasons in plan Phase 3.6) — this discharges item 5's "justify whichever way you go."
- [x] 3.7 Add assertion **A17**: byte-exact round-trip of a value with leading spaces,
      trailing spaces, an embedded newline and a TRAILING newline. Compare lengths AND
      content. **[v3/F9]** The TRAILING-NEWLINE case MUST be on `HOOK_FILE_PATH` (slot 5) —
      only the last record sits at the end of `raw`, so only slot 5 is sentinel-protected.
      Measured: under mutation 6, slots 1-4 keep `trailing_nl=YES`; only slot 5 flips to NO.
      "One other slot" left 2 of 3 choices under which mutation 6 is GREEN. `HOOK_CMD`
      carries the non-trailing whitespace + embedded-newline properties.
- [x] 3.8 RED proofs (6): rename `_HOOK_INPUT_JQ`; rename `hook_input_report`; add a second
      `jq` as `$(jq …)`; delete the aggregator; whitespace-trim `HOOK_CMD`; drop sentinel +
      trailing separator.
- [x] 3.9 Suite green; record delta vs Phase 0.1.

## Phase 4 — ADR-158 + C4 (contract — precedes Phases 5–6)

- [x] 4.1 Write `ADR-158-extending-the-hook-input-trust-boundary-past-the-bash-hot-path.md`.
      Re-verify the ordinal is still free against `origin/main` first.
- [~] 4.2 D1: one program, widened slots, per-slot flag vector, fixed named group
      predicates. Preserve: one fork, status-before-values, `catch {}`→object, empty
      bad-path values, RS separator, sentinel+trailing-separator pair, additive field order.
      Update the slot-count detector `n != 6` → the new count.
- [~] 4.2b **[v3/F2 — BLOCKING; D1 is incomplete without this].** Decoupling the token pays
      in SILENT FAIL-OPEN on non-core slots: a non-string `.tool_input.content` leaves
      guardrails' core group clean (no ask) while `skill-security-scan-write` fails its own
      group and exits 0 → Write ALLOWED, scanner never ran. That is ADR-157's rejected
      "fail open with a loud incident", and a regression against that hook's own current
      posture (it already asks on both "cannot evaluate" branches). Extend the responder
      model to: ONE CORE-GROUP RESPONDER PER MATCHER + EACH HOOK IS RESPONDER FOR ITS OWN
      NON-CORE GROUP. ADR-157's all-emit objection does not transfer (18 hooks × a
      PERSISTENT fault; `jq_missing`/`internal`/`unparseable` stay core-group).
- [~] 4.2c **[v3/F5]** Pin in D1 + assert: `hook_parse_input` returns 1 unless
      `${#_hi_s[0]}` equals the exact expected width; every group predicate is POSITIVE
      (`== "s"`, never `!= "b"` — a short vector makes `${vec:5:1}` empty and `!=` returns
      true → guards run on an unvalidated slot). Mutation: truncate the vector by one char
      → every predicate RED.
- [~] 4.2d **[v3/F4]** D2's named fallback ("register guardrails on the extra matchers") is
      a NO-OP under D1 — guardrails' core group stays clean on a non-string `.prompt`, so
      it parses, no-ops and exits 0 silently. Either drop the fallback (descoping becomes
      the only branch) or have guardrails check the UNION of groups where it is sole
      responder. Do not ship D2 citing a fallback that cannot fire.
- [~] 4.3 D2: responder is a SET; election is static and settings-derived; A9 asserts
      exactly one per matcher. State that ZERO responders is the P0 direction and TWO is P2.
- [x] 4.4 D3: **[v3/F1+F3+F13 — rebuild a THIRD time, on MEASURED behavior.]** The `.claude`
      half is sound (security review signed it off): fail open on
      `unparseable`/`jq_missing`/`internal`, grounded in ADR-157:115's self-referential-
      repair rationale (NOT hook count). The MIRROR half is NOT YET WRITABLE — today a
      malformed doc ABORTS at rc 5 before the shape check (F1); the `unparseable` branch is
      DEAD CODE (F3); `$t == null` denies every absent/null `tool_input` (F13). State per
      reason class what the mirror MEASURABLY does after 6.1b/6.1c. Assert NOTHING about
      non-0/2 exit codes until 6.1a's runtime probe returns. Covers all THREE mirror hooks.
- [x] 4.5 `## Alternatives Considered` must carry all four rejections: flat widening
      (forced-ask vector); auxiliary program (fork cost on `Write`); guardrails-on-extra-
      matchers (conflates universal responder with a Bash-specific guard — also the
      probe-failure fallback); uniform-deny-on-rc-1 (behavior change on 3 of 5 classes).
- [x] 4.6 C4: amend `model.c4:68` `engine.hooks` description to name the mirror, its
      `.working_dir`/`.tool_input.path` envelope, `exit 2` + `{"decision":"deny"}`, the
      absence of `ask`, and ADR-158 D3. Amend the `claude -> hooks` edge (:390) if D2
      changes what "the responder" means. NO new element; NO `views.c4` change.
- [x] 4.7 Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.
- [x] 4.8 Forward pointers from ADR-156 and ADR-157 to ADR-158.

## Phase 5 — CC-side migration (#7173a)

- [~] 5.1 **Reachability probe (precondition).** For each candidate, establish what a
      non-string field actually buys an attacker — does the harness reject non-string
      `tool_input` for these tools? Record the outcome; let it SIZE the migration set.
- [~] 5.2 **`ask`-honored probe (precondition).** `DEFER-DECISION-PAYLOAD-SHAPE.md:5`
      probed only a `PreToolUse(Bash)` stub. Probe `mcp__pencil__open_document` and
      `CronCreate`. If not honored → fall back to ADR-158 D2's recorded alternative or
      descope those two hooks. Do NOT build on an unverified harness invariant.
- [~] 5.3 Helper D1: widen `_HOOK_INPUT_JQ`; replace record 0 with the per-slot flag
      vector; add group predicates; update the slot-count detector (`n != 6` → new count).
      Core slots keep positions 1–5.
- [~] 5.4 Helper D2: `HOOK_INPUT_RESPONDER` → `HOOK_INPUT_RESPONDERS` space-list (bash 3.2
      — no `declare -A`); `hook_input_should_ask` → membership test. Generalize A9's jq to
      `--argjson responders` + exactly-one-per-matcher. Re-verify A9's non-vacuity control.
      Update A8's array and Phase 2's responder predicate.
- [~] 5.5 Verify `A11 helper forks jq exactly once` passes UNCHANGED (D1 preserves it).
- [~] 5.6 Migrate `skill-security-scan-write` (`content`).
- [~] 5.7 Migrate `new-scheduled-cron-prefer-inngest` (`content`, `new_string`).
- [~] 5.8 Migrate `pencil-open-guard` (`filePath`) — gated on 5.2.
- [~] 5.9 Migrate `durable-reminder-prefer-inngest` (`prompt`, `tool_name` only — its
      booleans stay on the existing `has()`-guarded read at :83-84) — gated on 5.2.
- [~] 5.5b **[v3/F12]** DELETE each migrated hook's pre-existing jq/parse short-circuit —
      do not layer the helper above it. `durable-reminder-prefer-inngest.sh:66` and
      `new-scheduled-cron-prefer-inngest.sh:51` both `command -v jq || allow` (explicit
      allow + exit) BEFORE any parse gate. Under D2 the first becomes sole responder on
      `CronCreate`, so with jq missing that matcher has ZERO responders — the plan's own
      stated P0 direction. Mutation: `PATH=/nonexistent` + a `CronCreate` payload → ask.
- [~] 5.5c **[v3/F11 — third probe]** Probe Claude Code's resolution order when one hook
      emits explicit `allow` and another emits `ask` on the SAME tool call. Unreachable
      today (union token fails both together); D1's decoupling makes it reachable for the
      first time. If `allow` wins it neutralises the responder's ask. ADR-156's own clause
      forbids assuming it.
- [~] 5.10 Grow `INSCOPE20`; confirm A13's three call-site verbs pass for each new member.
- [~] 5.10b **[v3/F6]** Add a FOURTH A13 check: grep each in-scope hook's referenced
      `HOOK_*` globals, map each to its group, assert the hook calls THAT group's
      predicate. Without it a hook can read `HOOK_FILE_PATH` while checking
      `hook_input_ok_write`, see `""`, no-op every guard and exit 0 — defect 2 restored
      per-slot, re-entering through the widening. Static grep over ~24 files.
- [~] 5.10c **[v3/F14]** `security_reminder_hook.py` is a PreToolUse hook on the `Edit`
      matcher (verified) and is in NEITHER list — so AC10 passes vacuously. Add a
      hook-specific README exemption ("Python; cannot source a bash helper") and note its
      `emit_incident(…, cmd=…)` path (:52, :217) is a second telemetry writer not covered
      by A7.
- [~] 5.11 README: move migrated hooks into the mandate list; rewrite the two-blocker prose
      (blocker 2 applies to zero hooks; the boolean blocker was never real); DELETE the
      hardcoded counts.
- [~] 5.12 README: hook-specific exemption reason for each of `pencil-collapse-guard`
      (note it restores a file from git on an unasserted `filePath`), `agent-token-tee`
      (reads a `.tool_response.*` family the program does not model),
      `docs-cli-verification`, `phase-surface-hint`, `skill-context-queries`,
      `skill-invocation-logger`. No shared blanket.

## Phase 6 — OpenHands + integration (#7173b)

- [x] 6.0 **[v3/F1 — PRECONDITION].** Probe how the OpenHands runtime treats a hook exit
      code that is neither 0 nor 2. Its answer decides whether F1 is a live guard bypass or
      a loud abort. ADR-158 D3 must assert nothing about it until this returns.
- [x] 6.1a **[v3/F1 — BLOCKING].** `.openhands/hooks/guardrails.sh:19` runs
      `COMMAND=$(… | jq -r …)` under `set -euo pipefail` with NO `|| true`, so any document
      jq rejects kills the script BEFORE the ADR-156 shape check at :51-60 — measured
      rc=5, no deny, no decision JSON, no incident row. A lone surrogate in a SIBLING field
      induces it while `.tool_input.command` stays a clean `rm -rf $HOME`. Give all three
      mirror hooks' raw extractions an explicit failure branch:
      `… 2>/dev/null) || deny "BLOCKED: the tool-call envelope did not parse (ADR-156/158 D3)."`
      Two lines per extraction; no cross-tree source, none of its fail-hard hazard. NOTE
      this makes `unparseable` DENY — D3 must reflect that.
- [x] 6.1b **[v3/F13].** Fix `.openhands/hooks/guardrails.sh:56`'s unsatisfiable
      `$t == null` → `$t == "null"`. `type` returns the STRING "null" (verified:
      `$t == null` → false, `$t == "null"` → true). Measured today the mirror DENIES
      `{"tool_input":null,…}` AND `{"working_dir":"/tmp"}` (no `tool_input` at all), rc 2 —
      an availability incident in a harness with no `ask`, where `.claude` parses both
      cleanly. Also falsifies the mirror's own "fires only when the document PARSES"
      comment, which is the sentence D3 was built on.
- [x] 6.1c README: record the mirror's in-place decision — now describing a FIXED mirror,
      not one whose divergence was mischaracterised. Replace "Convergence is a tracked
      follow-up."
- [x] 6.2 Extend `pre-merge-rebase-parity.test.sh`: non-string envelope → `.claude` asks,
      `.openhands` denies.
- [x] 6.3 **[v3/F3 — corrected].** Extend it with an `unparseable` case asserting what the
      mirror MEASURABLY does after 6.1a — NOT "falls through." `GR_ENVELOPE_SHAPE=
      "unparseable"` (:60) is DEAD CODE (reachable only if the shape program fails while
      the simpler :19-22 extractions succeed — on jq 1.8 that set is effectively empty), and
      today a malformed doc aborts at rc 5. Written as "no `decision:deny` on stdout" the
      test PASSES WHILE ASSERTING THE OPPOSITE OF THE TRUTH — the repaired-A9 class.
- [x] 6.3b **[v3/F13 — new third case].** absent/null `tool_input` → `.claude` parses
      cleanly, mirror denies. Asserts 6.1b's fix; neither planned case would catch it.
- [x] 6.4 Header comment records the new divergence class prevented.
- [x] 6.5 Verify existing T-S fixed-string cases (:175-193) and behavioural cases (:54-65)
      still pass — verify, do not assume.
- [ ] 6.6 Full `bash scripts/test-all.sh` green.
- [x] 6.7 Re-run the full mutation battery from a clean tree; `git status` shows only the
      intended diff.
- [ ] 6.8 PR body: mutation table (12 mutations, Phases 1–3), both probe outcomes, the jq
      decision, final assertion + skip counts vs baseline, `Closes #7190`, `Closes #7173`.
- [ ] 6.9 Confirm `decision-challenges.md` is surfaced by `/ship` (DC-1 PR split, DC-2
      #7173b discharge).
