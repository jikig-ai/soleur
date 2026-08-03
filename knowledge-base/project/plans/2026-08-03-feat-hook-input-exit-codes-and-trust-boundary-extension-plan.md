---
title: "feat: hook-input contract — assert exit codes, close suite vacuity, extend the ADR-156 boundary past the Bash hot path"
date: 2026-08-03
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: [7190, 7173]
branch: feat-one-shot-7190-7173-hook-input-contract-hardening
adr: ADR-162 (provisional ordinal — re-verify at ship)
revision: v3 (post deepen-plan; 22 measured findings, 2 blocking — see § Deepen-Plan Findings. v2 was post plan-review — see § Plan Review Revisions)
---

# hook-input contract: exit codes, suite vacuity, and the boundary past the hot path

## Overview

Two follow-ups to the ADR-156/157 hook-input trust-boundary migration (#7168, merged
2026-08-02) and its immediate repair (#7191, `68996d3ed`). Both touch
`.claude/hooks/lib/hook-input.sh` and `.claude/hooks/hook-input-contract.test.sh`, so they
share a worktree and a PR.

**#7190** hardens the contract suite itself. A 22-mutation battery against the merged tree
left 10 survivors (8.0/10, B). The A9 dead-gate and A13 call-site findings were already
fixed by `68996d3ed` and are explicitly out of scope. Six items remain; items 1–3 are the
ones that would have caught a real regression.

**#7173** extends the type assertion to the two groups #7168 deliberately scoped out: the
10 advisory/PostToolUse hooks and the OpenHands mirror.

**Ordering is load-bearing.** #7190's assertions (exit codes, paired presence/absence,
widened cardinality) all iterate `INSCOPE20`, and #7173 grows that list. Landing #7190
first means every hook #7173 migrates is policed by the new assertions on arrival. This is
a strong workflow benefit rather than a hard technical constraint — but Phase 2's loop is
*derived* from the responder set, so the responder change (Phase 5) must not be
forward-referenced from Phase 2. See § Sharp Edges.

### What the empirical probe changed about item 1

The issue frames item 1 as "exit codes are never asserted." The measured Claude Code
semantics make it considerably sharper. Per the official hooks reference (fetched
2026-08-03, `code.claude.com/docs/en/hooks.md`):

| Exit code | Effect on a PreToolUse hook |
|---|---|
| `0` | stdout JSON is parsed; `permissionDecision` (allow/deny/ask/defer) is honored |
| `2` | **blocking error** — tool prevented, **stdout JSON ignored entirely**, stderr becomes the block reason |
| `1` / any other non-zero | non-blocking error — **stdout JSON ignored**, tool **proceeds**, stderr shows as a hook error notice |

> "You must choose one approach per hook, not both … Claude Code only processes JSON on
> exit 0. If you exit 2, any JSON is ignored."

`exit 0` is therefore **the precondition for the entire ADR-157 posture to exist at all**:

- `exit 2` in `guardrails.sh` after emitting the ask → the ask is discarded and the call is
  **denied**. Violates ADR-157's "it never denies."
- `exit 2` in any of the 19 non-responders → that hook becomes a denier.
- `exit 1` anywhere → the JSON channel is voided and **the tool proceeds**. For
  `guardrails.sh` that is defect 2 restored verbatim.

Measured on the current tree: every one of the 20 in-scope hooks exits `0` on the
unparseable, happy and deny paths. The invariant holds today and is asserted nowhere —
`decision_for()` (`hook-input-contract.test.sh:60-69`) captures stdout and discards `$?`.

## Premise Validation

| Premise | Verified how | Result |
|---|---|---|
| #7190 / #7173 open | `gh issue view` | ✅ both OPEN |
| A9/A13 already fixed, out of scope | `git log`, read `68996d3ed` | ✅ suite carries repaired A9 + non-vacuity control |
| `exit 2` is the CC deny channel | Official hooks reference, 2026-08-03 | ✅ **stronger** — exit 2 *and* exit 1 both discard stdout JSON |
| Suite discards exit codes | Read `decision_for()` :60-69 | ✅ no `$?` capture anywhere |
| README documents the exemptions | Read § "Parsing hook input" :95-160 | ✅ + documents two blockers the issue understates |
| Mirror uses `.working_dir` / `.tool_input.path`, `exit 2` + `{"decision":"deny"}` | Read `.openhands/hooks/guardrails.sh:18-33,51-63` | ✅ verbatim |
| `pre-merge-rebase-parity.test.sh` exists | `.claude/hooks/pre-merge-rebase-parity.test.sh` | ✅ header records both prior divergences |
| ADR-157 rejected a variadic/per-field extractor | Read ADR-157 § Alternatives | ✅ on fork-count grounds |
| ADR-162 ordinal free | `ls decisions/` | ✅ **provisional** — re-verify at ship |
| Baseline suite state | `bash …/hook-input-contract.test.sh` | ✅ **50/50 pass**, exit 0 |

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / ARGUMENTS / plan v1) | Codebase reality | Plan response |
|---|---|---|
| "48 assertions on a fresh CI checkout vs 49 locally" | Suite runs **50/50** post-`68996d3ed`, with the gated assertion **already skipping here** — `.claude/.rule-incidents.jsonl` does not exist and is gitignored (`.gitignore:37`). | Item 5 stands; the numbers moved. Fix makes the assertion unconditional rather than counting its skip. |
| #7173(a) blocked because "the fields are not defined" | README documents two blockers: unpublished fields (incl. booleans) **and** no designated responder for `CronCreate`/`Skill`/`mcp__*`. | Both addressed. See next two rows — both turn out smaller than stated. |
| Blocker 2 blocks all four gating hooks | **Blocks zero.** A9 resolves coverage at the **tool** level, not by matcher-string equality; guardrails' covered set is `Bash Edit MultiEdit NotebookEdit Write` (measured). `skill-security-scan-write` (`Write`) and `new-scheduled-cron-prefer-inngest` (`Write\|Edit`) are already covered. And `CronCreate` and `mcp__pencil__open_document` each carry **exactly one** hook (measured), so "election" is degenerate — the responder set is a data change, not a mechanism. | D2 demoted from "per-matcher election in the helper" to a space-delimited constant. |
| The boolean problem blocks `durable-reminder-prefer-inngest` | **False.** `durable-reminder-prefer-inngest.sh:83-84` **already** performs the `has()`-guarded, `//`-avoiding boolean read that `lib/hook-input.sh:97-102` warns about, with a comment distinguishing *absent* from *present-and-false*. Its booleans are type-safe today. Its only unprotected field is `.tool_input.prompt` — a string. | The boolean group is **deleted from the design**. Booleans stay where they are. |
| (v1) The advisory matchers are rare, so a second program costs nothing | **False.** `skill-security-scan-write` sits on `Write` and `new-scheduled-cron-prefer-inngest` on `Write\|Edit` — the second-hottest matcher, already carrying five migrated hooks. Both read **core and aux** fields, so a two-program design would fork twice each, taking a `Write` from 5 forks to 9. | v1's auxiliary-program design (D1) is **cut**. One widened program, one fork. |
| ADR-157 rejected the per-field extractor, so a second extractor is off the table | The rejection is cost-based: *"N forks per hook per call … across 20 hooks."* | Moot once the design is one program. Recorded in Alternatives anyway. |
| (v1) ADR-157's fail-closed rejection was scoped to the 18-hooks-per-Bash-call hot path | **False — misattribution.** ADR-157:115 reads: *"Bricks the session with no in-band recovery — the repair for a broken `PATH` or a missing `jq` is itself a Bash call, which would also be denied."* **No hook count appears.** The rationale is **self-referential repair**, which transfers to OpenHands unchanged. The 18-hooks figure belongs to a *different* rejection (prompt volume, ADR-157:123). | D3's argument rebuilt from scratch on the correct rationale. |
| (v1) "The mirror denies on an unparseable envelope today" | **False.** `.openhands/hooks/guardrails.sh:43-45` states the guard is *"Scoped deliberately NARROW — it fires only when the document PARSES and a contracted field is the wrong TYPE. A transport failure keeps the pre-existing behaviour."* The `\|\| GR_ENVELOPE_SHAPE="unparseable"` fallback (`:60`) makes `unparseable` **fall through and the guards run**; only `nonstring` denies. | D3 narrowed to match reality: deny on `nonstring`/`separator`, loud fail-open on `unparseable`/`jq_missing`/`internal`. |
| The OpenHands mirror is two files | **Three.** `.openhands/hooks/worktree-write-guard.sh` also reads the envelope (`:14`), carries its own bespoke in-place assertion (`:34-45`) and its own `jq -r` extraction (`:49`), registered on `file_editor` in `.openhands/hooks.json`. | Added to scope. Omitting it would reintroduce the silent-divergence class in the PR claiming to close it. |
| `ask` is honored by CC | `DEFER-DECISION-PAYLOAD-SHAPE.md:5` records the probe used a **`PreToolUse(Bash)` stub**; every row in its table is a Bash call. Whether CC honors `ask` on `mcp__*` or `CronCreate` is **unestablished** — and ADR-156:40-41 names exactly that as the unverifiable region. | Phase 5 gains a probe precondition. If `ask` is not honored there, the responder designation for those two hooks is descoped. |
| "`pencil-open-guard` is the likeliest first candidate" | README says the opposite: *"one of the harder migrations … needs the unpublished camelCase `filePath` and has no responder."* | Plan follows the README's ordering. Recorded so the divergence is deliberate. |
| Neither ADR pins the 5-slot contract | Correct. ADR-156: *"must never be superseded. It may be extended."* | ADR-162 **extends**. |
| jq-absent skip is a repo-wide convention | Confirmed: **22 suites**, none hard-fail. | Item 5's jq sub-item: **considered and rejected**, with reasons. |

## Open Code-Review Overlap

**None.** Queried all 62 open `code-review` issues against every path in *Files to Edit* /
*Files to Create* — zero body matches.

## User-Brand Impact

**If this lands broken, the user experiences:** a disarmed PreToolUse guard. A regression in
`lib/hook-input.sh` or the responder wiring means `guardrails.sh` stops blocking `rm -rf`
onto a repo root, stops blocking commits to `main`, and stops scanning staged diffs for
secrets — while the suite reports green. That is exactly what #7168 closed, and the
operator's own working tree is the blast radius.

**If this leaks, the user's workflow is exposed via:** incident telemetry. The new
presence-assertions read `hook-input-*` rows out of per-hook `INCIDENTS_REPO_ROOT`
sandboxes. A row carrying a *field value* rather than a reason classifier would put
model-controlled payload content into `.claude/.rule-incidents.jsonl` and thence the weekly
aggregate. A7 already asserts no payload content in `command_snippet`; this plan must not
weaken it, and the new assertions read only `rule_id`/`kind`.

**A second, subtler exposure — and the reason the slot design changed in v2.** Widening one
shared status token across fields drawn from unrelated tool schemas would let the model
force an `ask` on demand: adding `"content": 123` to a *Bash* payload flips a union token,
`guardrails.sh` cannot parse, and a call that would have been **denied** becomes a
**prompt**. `ask` is not `allow`, but a mechanism the model can trigger at will to convert
hard blocks into prompts is a prompt-fatigue generator, and prompt fatigue is how an `ask`
posture degrades into an `allow` posture in practice. The per-slot status vector (ADR-162
D1) exists to close this.

**Brand-survival threshold:** `single-user incident`.

One operator, one machine, one disarmed guard is the whole incident. Consequences:
`requires_cpo_signoff: true`; `user-impact-reviewer` at review time; 5-agent `plan-review`
(done — see § Plan Review Revisions); `/deepen-plan` mandatory before `/work`.

## Architecture Decision (ADR/C4)

Detection fires: this plan changes a **trust boundary** (which fields are type-asserted and
how a caller checks them) and a **dispatch rule** (which hook is the designated responder).
Both are in-scope deliverables, not follow-ups.

### ADR

**ADR-162 — "Extending the hook-input trust boundary past the Bash hot path"**
(provisional ordinal; `/ship`'s ADR-Ordinal Collision Gate re-verifies against
`origin/main`. On renumber, sweep
`grep -rn 'ADR-162' knowledge-base/project/{plans,specs}/feat-one-shot-7190-7173-*/` in the
same edit — a renumber reaching only the ADR body leaves this plan's ACs citing a
nonexistent file.)

ADR-162 **extends** ADR-156/157; it supersedes neither. Three clauses.

- **D1 — One program, more slots, a per-slot status vector.** `_HOOK_INPUT_JQ` grows from 5
  slots to cover the fields the migration needs — `.tool_input.content`,
  `.tool_input.new_string`, `.tool_input.filePath`, `.tool_input.prompt` — plus the
  OpenHands envelope terms (`.working_dir`, `.tool_input.path`) so one program serves both
  harnesses. Record 0 changes from a single `"ok"|"bad"` token to a **fixed-width per-slot
  flag vector**, each slot's expected type fixed in the constant program. Callers check
  only the slots they read, through a small set of **fixed named group predicates** in the
  helper (`hook_input_ok_core`, `hook_input_ok_write`, …) — constants, no caller-supplied
  names, no `printf -v`, no program interpolation, so this is not the variadic API ADR-157
  rejected. Everything structural is preserved verbatim: **one fork**, status computed
  before any value is emitted, `catch {}` yielding an object, bad-path values emitted
  empty, RS separator, trailing-separator + sentinel pair, field order additive (core
  slots keep positions 1–5).
  - *Rejected alternative — flat widening with the existing union token.* Simpler, but it
    couples four unrelated tool contracts behind one flag and hands the model the forced-ask
    vector described in § User-Brand Impact.
  - *Rejected alternative — a second auxiliary program (plan v1's D1).* Two of the four
    migration targets sit on `Write`/`Write|Edit` and read core **and** aux fields, so they
    would fork twice each, taking a `Write` call from 5 forks to 9 — the exact cost ADR-157
    rejected the per-field shape over.
  - **No boolean group.** `durable-reminder-prefer-inngest` already reads its booleans
    safely (`:83-84`) and keeps doing so. Its migration takes only the `prompt` slot.
  - **[v3 — D1 is INCOMPLETE without this; see F2.]** Decoupling the token buys the
    forced-ask fix and pays in **silent fail-open on every non-core slot**: a non-string
    `.tool_input.content` leaves guardrails' core group clean, so it does not ask, while
    `skill-security-scan-write` fails its own group, reports, and exits 0 — Write allowed,
    scanner never ran. So the responder model must extend to **one core-group responder per
    matcher, plus each hook is responder for its own non-core group.** ADR-157's all-emit
    objection does not transfer (it concerned 18 hooks × a *persistent* fault;
    `jq_missing`/`internal`/`unparseable` stay core-group failures owned by the single
    responder). D1 must also pin an exact **vector-width check** and **positively-phrased**
    group predicates (F5), and A13 must bind each hook's slot reads to the predicate it
    calls (F6) — without that last one, D1 reintroduces defect 2 per-slot.
- **D2 — The designated responder is a SET, not a scalar.** `HOOK_INPUT_RESPONDER`
  (`hook-input.sh:60`) becomes `HOOK_INPUT_RESPONDERS`, a space-delimited list of hook
  basenames (bash 3.2 — no `declare -A`, per the helper's own portability pin at `:34-35`).
  `hook_input_should_ask` becomes a membership test on `HOOK_INPUT_HOOK`, which the call
  site already supplies. **The election is static and settings-derived, never runtime:** a
  hook cannot know its own matcher — the matcher lives in `.claude/settings.json` and is
  never passed in, and `.tool_name` is empty by construction on the failure path (the
  helper resets every global at `:123` and returns at `:209-214` before any slot
  assignment), which is the only path where responder identity matters. A9 does the
  matcher-level work where the matcher actually exists — a pure jq assertion over the
  settings document: *for every matcher carrying ≥1 in-scope hook, exactly one registered
  hook is in the responder set.* The `== 1` form gives the no-double-responder clause for
  free.
  - *Failure directions are asymmetric and the ADR must say so.* **Zero responders on a
    matcher is the P0 direction** — every hook reports and exits 0, nothing asks, the tool
    proceeds unguarded: defect 2 restored for that tool class, silent, catchable only by A9.
    **Two responders is P2** — two prompts on one call; noise, not exposure.
  - *Rejected alternative — register `guardrails.sh` on the two extra matchers.* A two-line
    settings edit needing no helper change and no ADR clause; A9 would pass unmodified. It
    is rejected because it conflates the universal responder with a Bash-specific guard file
    whose every guard no-ops on those payloads, and it scales badly as matchers accrue. But
    it is a genuine alternative and it is the fallback if D2's probe precondition fails.
- **D3 — What `ask` means on a protocol with no `ask` state.** OpenHands has two states:
  block (`exit 2` + `{"decision":"deny"}`) and continue. **Decision: the mirror denies on
  `nonstring` and `separator`, and fails open loudly (incident row + stderr) on
  `unparseable`, `jq_missing` and `internal`.** This is what the mirror does today
  (`.openhands/hooks/guardrails.sh:43-45,60-63`) and the ADR's job is to say *why* it is
  correct rather than incidental:
  - ADR-157's rejection of fail-closed reasons from **self-referential repair** — *"the
    repair for a broken `PATH` or a missing `jq` is itself a Bash call, which would also be
    denied"* (ADR-157:115). That argument transfers to OpenHands **unchanged**, and bites
    harder: the mirror has no `ask`, no operator-in-the-loop escalation, and no kill-switch
    equivalent to `SOLEUR_DISABLE_HOOK_INPUT_ASK`. So `jq_missing` and `internal` must
    **not** deny.
  - For `nonstring`/`separator` the deny is right and the in-band recovery is real: the
    `reason` string returns **to the agent**, which can re-send the command as a string.
    No legitimate caller sends a non-string; a deny is recoverable where a silent bypass
    is not.
  - Uniformly denying on helper rc 1 — plan v1's proposal — would have been a **behavior
    change on three of five reason classes** with a hard brick on `jq_missing`. Recorded in
    Alternatives as measured-and-rejected.
  - **[v3 — D3 must be rebuilt a THIRD time on measured behavior; see F1/F3/F13.]** The
    `.claude` half is sound and was signed off by security review. The **mirror** half is
    not yet writable: today a malformed document does not fall through — it **aborts at
    rc 5** before the shape check (F1); the `unparseable` branch is **dead code** (F3); and
    the `$t == null` conjunct denies every payload with an absent or null `tool_input`
    (F13). ADR-162 must state, per reason class, what the mirror **measurably** does
    after Phase 6.1b/6.1c, and must not assert anything about non-0/2 exit codes until
    Phase 6.1a's runtime probe returns.

### C4 views

Checked all three model files against the completeness mandate:

- **(a) External human actors** — `founder`, `emailSender`, `betaContact`, `contributor`
  modeled; this plan adds none. ✅
- **(b) External systems / vendors** — 13 modeled. `grep -ci openhands` returns **0** across
  all three files. The OpenHands harness is unmodeled.
- **(c) Containers / data stores** — `engine.hooks` ("Hook Engine") exists at `model.c4:68`,
  description already carrying ADR-156/#7164 detail. No new store.
- **(d) Access relationships** — `claude -> hooks` (`model.c4:390`) carries the ADR-156/157
  semantics. No edge represents a second harness.

**Decision: amend, do not add an element.** `.openhands/hooks/` is three shell scripts in
this repo — not a vendor, not a deployment unit, not a data store. Encoding "these scripts
use `exit 2` instead of `ask`" as a *container* would put code-level protocol detail in the
wrong C4 layer, and plan v1's inability to decide between "container under `engine`" and
"external sibling" was the tell. The reader is served, at a fraction of the cost, by:

1. Amending `engine.hooks`'s description (`model.c4:68`) so it no longer implies a single
   harness — one clause naming the mirror, its `.working_dir`/`.tool_input.path` envelope,
   its `exit 2` + `{"decision":"deny"}` protocol, the absence of `ask`, and ADR-162.
2. Amending the `claude -> hooks` edge text (`model.c4:390`) if D2 changes what "the
   responder" means.
3. Running `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

No new element, so no `views.c4` include is required and no render surface changes.

### Sequencing

ADR-162 is authored in Phase 4, **before** the Phase 5/6 implementations that depend on
D1/D2/D3. The C4 amendment lands with it. Neither is deferred to a follow-up issue.

## Implementation Phases

Six phases. v1's ten were over-decomposed: Phases 1–6 there each edited one function in one
file and were verified by one command.

### Phase 0 — Baseline (one step)

0.1 `bash .claude/hooks/hook-input-contract.test.sh` → record exact pass/total (measured:
    **50/50**). Pin it in the PR body; later phases report deltas against it.
    Mutation convention is already in-file (`A15:567-572`, `A13:493-500`, `A9:386-399`):
    every new assertion carries a comment naming the mutation that turns it RED. Mutations
    are applied to a scratch copy, observed RED, reverted — **never committed**.

### Phase 1 — #7190 item 1: exit codes (highest value)

1.1 **[v3 — reversed by F7]** Do **not** call `bad` inside `decision_for()`. It is invoked
    exclusively inside `$( )` (~25 sites), so the increment runs in a subshell and is
    discarded — measured `FAIL_after=0`. Written to stderr it returns a clean decision, the
    outer `want` passes, and the suite exits 0 having detected a non-zero rc and thrown it
    away: the A9 vacuity class reproduced. **Leave `decision_for` unchanged.** Add a sibling
    `rc_for()` and let **A16** own the rc assertion in the caller's shell via `want` — zero
    churn across the `want` strings, and it is where 1.2 already puts it. Borrow the
    conjoined idiom proven at `.claude/hooks/pre-merge-rebase.test.sh:84-101` — never assert
    rc in isolation where a decision is also available.
1.2 New assertion **A16 — every in-scope hook exits 0 on every path.** `INSCOPE20` × three
    payload classes (unparseable, happy, and — for the responder — deny). Comment states
    *why*: a non-zero rc voids the stdout JSON channel, so `ask` and `deny` both evaporate.
1.3 **Mutations (3):** `exit 2` in `guardrails.sh` after `hook_input_emit_ask`; `exit 1` in
    a non-responder after `hook_input_report`; `exit 2` in a non-responder. Each RED.

### Phase 2 — #7190 items 2 + 3: one loop, four properties

v1 split these into two phases that built two overlapping loops with duplicated sandbox
setup, both asserting "a `hook-input-*` row is present" from the same payload class.

2.1 Collapse `a3_rce_regression()`'s `EVAL10` loop and `a14_bare_payload_coverage()`'s
    hardcoded 4-hook loop into **one loop over `INSCOPE20`**, one sandbox per hook, four
    assertions each: (i) no attacker marker (absence — keeps A3's existing positive
    control); (ii) a `hook-input-*` row in that hook's **own** `INCIDENTS_REPO_ROOT`
    (presence — reading `rule_id`/`kind` only, never `command_snippet`); (iii) `rc == 0`;
    (iv) silent on stdout unless the hook is a responder.
2.2 The responder predicate here reads the **current** `HOOK_INPUT_RESPONDER` scalar. It is
    rewritten to the D2 set in Phase 5 — do **not** forward-reference D2 from this phase.
2.3 Verify empirically before widening: the reviewer probed all 19 non-responders and
    reports silent / `RECORDS=YES` / rc=0. Re-confirm. If any hook diverges, **list it** —
    do not trim the loop back to a passing subset (the discipline A14's existing comment
    already applies).
2.4 A8's `responders` array (`:361`) stays literal until Phase 5.
2.5 **Mutations (3):** `exit 0` at line 3 of two different hooks → absence green, presence
    RED (the pairing is the point); disarm the parse gate in a hook outside the original
    four → RED (proves the widening bought something).

### Phase 3 — #7190 items 4 + 5 + 6: vacuity, skips, fidelity

3.1 **Item 4 — non-vacuity.** Every extracted range in `a11_mechanism_ban()` asserts
    **non-empty** before asserting content — the A9 treatment from `68996d3ed`. Applies to
    the `sed -n "/^_HOOK_INPUT_JQ='/,/^'$/p"` range (:472), the
    `sed -n '/^hook_input_report()/,$p'` range (:478), and the A4 apostrophe range (:226),
    which shares the anchor.
3.2 Replace the spelling-pinned `grep -cE '\| jq '` (:469) with a **token count**: stripped
    of comments, `\bjq\b` appears exactly twice in `lib/hook-input.sh` (`command -v jq` and
    the invocation). One number, no pattern to evade — do not start a regex arms race over
    `$(jq`, `< <(jq`, backticks.
3.3 **Item 5 — skips.** Add a `SKIPPED` counter and a `skip()` helper beside `ok()`/`bad()`,
    printed in the summary (`=== hook-input-contract: $PASS/$TOTAL pass, $SKIPPED skipped
    ===`). Real user today: the python3-gated fixtures at `:234-244`.
3.4 **[v3 — corrected by F8]** Make the ":328 worktree ledger unchanged" assertion
    **unconditional**, but **without synthesizing a git repo**. `_incidents_repo_root()`
    (`lib/incidents.sh:36-42`) falls back to `dirname(BASH_SOURCE)/../../..` —
    helper-relative, not cwd- or git-relative — so a synthesized sandbox repo is a location
    the fallback can never resolve to, and asserting its ledger is untouched cannot fail
    under any mutation. The `git init` would also re-couple to the branch-dependent gate
    `:56-58` deliberately avoids (#5192). Instead: point `INCIDENTS_REPO_ROOT` at sandbox
    `T`; assert (a) `T`'s ledger **grew** and (b) `$REPO_ROOT/.claude/.rule-incidents.jsonl`
    is **byte-identical**, treating absent as size 0 on both sides. Deleting the
    `INCIDENTS_REPO_ROOT` branch from `_incidents_repo_root` then makes both RED.
3.5 The ":338" aggregator walk is gated on `[[ -x $agg || -f $agg ]]`. The aggregator is a
    committed repo file; its absence is a broken checkout, not a legitimate skip. Hard-fail
    with a message saying so.
3.6 **jq absent → keep the SKIP.** #7190 item 5 asks to *"consider a hard failure … and
    justify whichever way you go."* Considered and rejected: (a) verifying CI has jq makes
    the hard-fail unreachable in CI — dead code guarding a hypothetical image change; (b)
    if CI lacks jq, the change is struck anyway; (c) it turns a green `test-all.sh` on a
    jq-less dev machine red for an environment reason; (d) it buys false comfort, since
    **21 sibling suites still skip silently** in exactly that scenario. If aggregate
    skip-invisibility is the real concern, the fix is skip-accounting in `test-all.sh` —
    one place, all 22 suites — and that is not this PR. Record the reasoning in the PR body
    so the "considered" half of the AC is discharged visibly.
3.7 **Item 6 — fidelity.** New assertion **A17**: round-trip a value carrying, in one
    payload, leading spaces, trailing spaces, an embedded newline and a **trailing**
    newline. Assert byte-exact equality — compare lengths *and* content, since a
    trailing-newline loss is invisible to a naive `[[ "$a" == "$b" ]]` inside `$( )`.
    **[v3 — pinned by F9]** The trailing-newline case MUST be asserted on
    **`HOOK_FILE_PATH` (slot 5)**: only the last emitted record sits at the end of `raw`, so
    only slot 5 is protected by the sentinel/trailing-separator pair. Measured against a
    scratch mutation dropping both, slots 1–4 keep `trailing_nl=YES` and only
    `HOOK_FILE_PATH` flips to `NO` — so asserting "`HOOK_CMD` and one other slot" leaves
    two of three choices under which prescribed mutation 6 is **GREEN**. `HOOK_CMD` carries
    the non-trailing whitespace and embedded-newline properties.
3.8 **Mutations (6):** rename `_HOOK_INPUT_JQ` → RED on the new non-emptiness precondition
    (today: silently vacuous-pass); rename `hook_input_report` → RED; add a second `jq` as
    `$(jq …)` → RED; delete the aggregator → RED; whitespace-trim `HOOK_CMD` → A17 RED;
    drop sentinel **and** trailing separator → A17 RED on the trailing-newline case.

### Phase 4 — ADR-162 + C4 (contract; precedes Phases 5–6)

4.1 Author `ADR-162-*.md` with D1/D2/D3 as specified, including every rejected alternative
    named above (flat widening / auxiliary program / guardrails-on-extra-matchers /
    uniform-deny-on-rc-1) and a `## Consequences` section. Status `accepted`.
4.2 C4 amendments 1–3 from the § above; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
4.3 Forward pointers from ADR-156 and ADR-157 so the corpus is navigable both ways.

### Phase 5 — #7173(a): CC-side migration

5.1 **Reachability probe (precondition, before any migration).** The `Bash` threat model
    does not automatically transfer. For each candidate, establish what a non-string field
    actually buys an attacker: `pencil-open-guard` with a non-string `filePath` →
    `git -C` fails → `REPO_ROOT` empty → `exit 0`, guard bypassed — **but** the MCP tool
    then receives a non-string `filePath` and may reject it, leaving the attacker with a
    failed tool call and nothing else. Same shape for `skill-security-scan-write` with an
    array `content`. **If the harness rejects non-string `tool_input` fields for these
    tools, some of these migrations defend nothing** and the set shrinks. Run the probe;
    record the result; let it size the migration set rather than assuming.
5.2 **`ask`-honored probe (precondition for D2's new responders).**
    `DEFER-DECISION-PAYLOAD-SHAPE.md:5` probed `ask` with a **`PreToolUse(Bash)` stub`**
    only. Probe `mcp__pencil__open_document` and `CronCreate` on the model of the existing
    one. **If `ask` is not honored there, fall back to ADR-162 D2's recorded alternative**
    (register `guardrails.sh` on those matchers) or descope those two hooks — do not build
    a safety posture on an unverified harness invariant (ADR-156's own clause).
5.3 **Helper (D1):** widen `_HOOK_INPUT_JQ` with the new slots, replace record 0 with the
    per-slot flag vector, add the fixed named group predicates, update the slot-count
    detector (`n != 6` → the new count). Core slots keep positions 1–5, additively.
5.4 **Helper (D2):** `HOOK_INPUT_RESPONDER` → `HOOK_INPUT_RESPONDERS` space-list;
    `hook_input_should_ask` becomes a membership test. Generalize A9's jq to take
    `--argjson responders` and assert **exactly one** responder per matcher carrying an
    in-scope hook. Re-verify A9's non-vacuity control still fires (`needed >= 1`). Update
    A8's `responders` array and Phase 2's responder predicate to read the set.
5.5 **A11 fork count.** It asserts the helper forks `jq` exactly once. One program means the
    count is **unchanged** — verify, and state in the commit message that D1 deliberately
    preserves it (this is the assertion v1's two-program design would have loosened).
5.6 **Migrate**, gated on 5.1/5.2: `skill-security-scan-write` (`content`),
    `new-scheduled-cron-prefer-inngest` (`content`, `new_string`), `pencil-open-guard`
    (`filePath`), `durable-reminder-prefer-inngest` (`prompt` + `tool_name` only — its
    booleans stay on their existing safe read). Grow `INSCOPE20`; A13's three call-site
    verbs must pass for each.
5.7 **Exempt, decided now — no implementation-time branch.** `pencil-collapse-guard`
    (PostToolUse, emits no `permissionDecision`) plus `agent-token-tee`,
    `docs-cli-verification`, `phase-surface-hint`, `skill-context-queries`,
    `skill-invocation-logger`. Issue AC2 makes this a passing outcome. Each keeps a
    **hook-specific** reason in the README — not a shared "advisory" blanket.
    `pencil-collapse-guard`'s reason must note that it *restores a file from git* on a
    `filePath` it does not type-assert, so the exemption is eyes-open.
    `agent-token-tee`'s must note it reads an entire `.tool_response.*` family the program
    does not model.
5.8 README § "Parsing hook input": move migrated hooks into the mandate list, rewrite the
    two-blocker prose (blocker 2 now applies to zero hooks; the boolean blocker was never
    real), and keep per-hook exemption reasons. **Delete the hardcoded counts** rather than
    maintaining them — they drift, and the lists themselves are the source of truth.

### Phase 6 — #7173(b): OpenHands + integration

6.1 **[v3 — premise REFUTED by F1; this phase is rewritten.]** v2 claimed "the gap is code
    duplication, not a trust-boundary hole." Measurement refutes it: a malformed document
    kills `.openhands/hooks/guardrails.sh` at `:19` under `set -euo pipefail` — **before**
    the ADR-156 shape check at `:51-60` — with rc 5, no `deny`, no decision JSON and no
    incident row. A lone surrogate in a sibling field induces it while
    `.tool_input.command` stays a clean `rm -rf $HOME`. Two mandatory items, and a
    precondition:
    - **6.1a (precondition).** Probe how the OpenHands runtime treats a hook exit code that
      is neither 0 nor 2. Its response decides whether F1 is a live bypass or a loud abort.
      ADR-162 must not assert anything about it before this returns.
    - **6.1b.** Give all three mirror hooks' raw extractions an explicit failure branch
      instead of letting `set -e` abort them —
      `… jq -r '…' 2>/dev/null) || deny "BLOCKED: the tool-call envelope did not parse
      (ADR-156/158 D3)."` Two lines per extraction, no cross-tree source and none of its
      fail-hard hazard. Note this makes `unparseable` **deny**, which D3 must then reflect.
    - **6.1c.** Fix `.openhands/hooks/guardrails.sh:56`'s unsatisfiable `$t == null`
      conjunct to `$t == "null"` (F13). Measured, the mirror currently denies
      `{"tool_input":null,…}` **and** any payload with no `tool_input` at all — an
      availability incident in a harness with no `ask`, where `.claude` parses both cleanly.
    The convergence-vs-in-place decision itself still stands as v2 wrote it (the shared
    extractor's cross-tree fail-hard `source` remains the riskiest line in the change set),
    and the README still records the reason — but it records a **fixed** mirror, not a
    mirror whose divergence was mischaracterised.
6.2 **ADR-162 is still authored** (Phase 4) — the decision is *why the mirror's
    divergence is correct*, which is the thing #7173 asked to be made deliberately. It now
    also covers all **three** mirror hooks, not two.
6.3 **Extend `pre-merge-rebase-parity.test.sh`** with three cases, not two:
    - **non-string** — `.claude` **asks**, `.openhands` **denies**. Unchanged from v2.
    - **unparseable** — **[v3, corrected by F3]** assert what the mirror *measurably does*
      after 6.1b, **not** "falls through." v2's drafted assertion would have passed while
      asserting the opposite of the truth: `GR_ENVELOPE_SHAPE="unparseable"` (`:60`) is
      **dead code** in the mirror (reachable only if the shape program fails while the
      simpler `:19-22` extractions succeed on the same document — on jq 1.8 that set is
      effectively empty), and today a malformed document aborts at rc 5 rather than falling
      through. Written as "no `decision:deny` on stdout" it is the repaired-A9
      false-confidence class.
    - **absent/null `tool_input`** — **[v3, new, F13]** the third divergence class neither
      v2 case would catch: `.claude` parses cleanly, the mirror denies. Asserts 6.1c's fix.
    This is the highest-value item in Phase 6: it makes the divergence executable, which is
    what the parity suite is for. Header comment records the new divergence classes.
6.4 Verify the suite's existing T-S fixed-string cases (`:175-193`) and behavioural cases
    (`:54-65`) still pass — Phase 6 does not touch the `grep -E` literal, but verify rather
    than assume (issue AC3; the header records two prior silent divergences).
6.5 Full `bash scripts/test-all.sh`. Mutation table into the PR body (suite convention,
    `A11:458`). Final assertion + skip count against Phase 0.1's baseline.
    `Closes #7190` and `Closes #7173`.

## Files to Edit

| File | Change |
|---|---|
| `.claude/hooks/hook-input-contract.test.sh` | Ph1 rc assertion in `decision_for` + A16; Ph2 merged `INSCOPE20` loop (4 properties); Ph3 A11 non-vacuity + jq token count, `SKIPPED` counter, unconditional ledger assertion, aggregator hard-fail, A17; Ph5 `INSCOPE20` growth, A9 responder-set generalization, A8 |
| `.claude/hooks/lib/hook-input.sh` | Ph5.3 widened program + per-slot flag vector + group predicates; Ph5.4 `HOOK_INPUT_RESPONDERS` + `hook_input_should_ask` |
| `.claude/hooks/README.md` | Ph5.8 mandate/exempt lists, per-hook reasons, blocker prose, counts deleted; Ph6.1 mirror rationale |
| `.claude/hooks/skill-security-scan-write.sh` | Ph5.6 migrate (`content`) |
| `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` | Ph5.6 migrate (`content`, `new_string`) |
| `.claude/hooks/pencil-open-guard.sh` | Ph5.6 migrate (`filePath`) |
| `.claude/hooks/durable-reminder-prefer-inngest.sh` | Ph5.6 migrate (`prompt`, `tool_name`); booleans untouched |
| `.claude/settings.json` | Ph5.4 only if D2's probe outcome requires a registration change |
| `.claude/hooks/pre-merge-rebase-parity.test.sh` | Ph6.3 non-string + unparseable parity cases, header note |
| `knowledge-base/engineering/architecture/decisions/ADR-156-*.md`, `ADR-157-*.md` | Ph4.3 forward pointers |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Ph4.2 `engine.hooks` description + `claude -> hooks` edge text |

**Not edited** (decided, not deferred): `.openhands/hooks/*` — see Phase 6.1.
`.claude/hooks/pencil-collapse-guard.sh` and the five advisory hooks — see Phase 5.7.
`views.c4` — no new element.

## Files to Create

| File | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-162-what-ask-means-on-a-harness-with-no-ask-state.md` | D1/D2/D3 |
| `knowledge-base/project/specs/feat-one-shot-7190-7173-hook-input-contract-hardening/tasks.md` | Task breakdown |
| `knowledge-base/project/specs/feat-one-shot-7190-7173-hook-input-contract-hardening/decision-challenges.md` | The PR-split challenge (see § Plan Review Revisions) |

## Acceptance Criteria

### Pre-merge (PR)

**#7190**

- [ ] **AC1** `bash .claude/hooks/hook-input-contract.test.sh` exits 0 and its summary line
      reports `0 skipped` in this worktree.
- [ ] **AC2** A16 asserts `rc == 0` for every hook in `INSCOPE20` across the unparseable,
      happy and deny payload classes, and `decision_for()` fails loudly on a non-zero rc.
- [ ] **AC3** The merged Phase-2 loop asserts, per hook in `INSCOPE20`: marker absence,
      `hook-input-*` row presence in that hook's own `INCIDENTS_REPO_ROOT`, `rc == 0`, and
      stdout silence unless the hook is a responder. A3's positive control survives.
- [ ] **AC4** Every extracted range in A11 (and the A4 apostrophe range at `:226`) asserts
      non-empty before asserting content. The `jq` ban is a token count, not a pipe-spelling
      grep.
- [ ] **AC5** The ledger assertion and the aggregator walk both run unconditionally; the
      suite prints a skip count.
- [ ] **AC6** A17 asserts byte-exact round-trip of a value with leading spaces, trailing
      spaces, an embedded newline and a trailing newline, for `HOOK_CMD` and one other slot.
- [ ] **AC7** The PR body contains a mutation table covering #7190 items 1–6, each row
      naming the mutation and the assertion that goes RED — 12 mutations across Phases
      1–3. It also records the item-5 jq decision (SKIP retained) with its justification.

**#7173**

- [ ] **AC8** Every migrated hook parses via `lib/hook-input.sh` and checks the slots it
      reads via a named group predicate; `INSCOPE20` has grown to match; A13's three
      call-site verbs pass for each new member.
- [ ] **AC9** A9 passes with the responder **set**, asserting exactly one responder per
      matcher carrying an in-scope hook, and its non-vacuity control still fires.
      Deliberately designating two responders on one matcher makes A9 RED.
- [ ] **AC10** Every hook that stays exempt — including all three OpenHands mirror hooks —
      has a **hook-specific** reason in `.claude/hooks/README.md`. No hardcoded counts
      remain in that section.
- [ ] **AC11** `bash .claude/hooks/pre-merge-rebase-parity.test.sh` exits 0, including the
      new non-string case (`.claude` asks, `.openhands` denies) and the new `unparseable`
      case (`.openhands` falls through).
- [ ] **AC12** The reachability probe (5.1) and the `ask`-honored probe (5.2) are recorded
      in the PR body with their outcomes, and the migration set matches what they justify.

**Architecture / integration**

- [ ] **AC13** `ADR-162-*.md` exists with D1, D2, D3, an `## Alternatives Considered` table
      carrying all four rejected alternatives named in this plan, the asymmetric
      zero-vs-two responder failure analysis, and `## Consequences`. ADR-156 and ADR-157
      carry forward pointers.
- [ ] **AC14** `model.c4`'s `engine.hooks` description names the mirror, its envelope, its
      protocol and the absence of `ask`; `c4-code-syntax.test.ts` and `c4-render.test.ts`
      pass.
- [ ] **AC15** `bash scripts/test-all.sh` green. **Behavioural pin:** the 20 original hooks
      produce identical decisions on the existing fixture corpus before and after the D1
      widening — asserted by the suite passing unchanged expectations, not by a source diff
      (the primary program *does* change under D1, so a byte-diff AC would be unsatisfiable).
- [ ] **AC16** `A11 helper forks jq exactly once` passes **unchanged** — D1 preserves the
      single-fork property.
- [ ] **AC17** PR body closes both: `Closes #7190`, `Closes #7173`.

### Post-merge (operator)

None. Every step runs in-session: the suite, the mutation battery, `test-all.sh`, the C4
tests, the two probes, and `gh pr merge --squash --auto`. No infrastructure, no vendor
dashboard, no migration apply.

## Observability

The Phase 2.9 gate does not strictly fire (no Files-to-Edit under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`; no new infrastructure). Recorded
because the change concerns a telemetry path.

```yaml
liveness_signal:
  what: "summary.hook_input_fault_count in the rule-metrics aggregate"
  cadence: "on every aggregator run"
  alert_target: "weekly rule-metrics report"
  configured_in: "scripts/rule-metrics-aggregate.sh; asserted end-to-end by A6"
error_reporting:
  destination: ".claude/.rule-incidents.jsonl via emit_incident, rule_id hook-input-<reason>"
  fail_loud: "yes — CC asks; the mirror denies on nonstring/separator and fails open LOUDLY (incident + stderr) on unparseable/jq_missing/internal per ADR-162"
failure_modes:
  - mode: "a migrated hook stops reaching the parse gate"
    detection: "Phase-2 loop presence assertion — no hook-input-* row in that hook's own INCIDENTS_REPO_ROOT"
    alert_route: "CI, scripts shard"
  - mode: "a hook returns non-zero, voiding the stdout JSON channel"
    detection: "A16 rc assertion across all three payload classes"
    alert_route: "CI, scripts shard"
  - mode: "zero responders on a matcher (the P0 direction) — nothing asks, tool proceeds unguarded"
    detection: "A9 exactly-one-responder-per-matcher assertion over .claude/settings.json"
    alert_route: "CI, scripts shard"
  - mode: "an assertion becomes vacuous (empty extracted range, silent skip)"
    detection: "A11 non-emptiness preconditions + the SKIPPED counter in the summary line"
    alert_route: "CI, scripts shard"
  - mode: "the two harnesses diverge again"
    detection: "pre-merge-rebase-parity.test.sh, incl. the new non-string and unparseable cases"
    alert_route: "CI, scripts shard"
logs:
  where: "stderr via headless_or_stderr; .claude/.rule-incidents.jsonl"
  retention: "per existing incidents.sh rotation"
discoverability_test:
  command: "bash .claude/hooks/hook-input-contract.test.sh && bash .claude/hooks/pre-merge-rebase-parity.test.sh"
  expected_output: "both exit 0; contract suite prints '=== hook-input-contract: N/N pass, 0 skipped ==='"
```

No soak-gated closure criterion → no follow-through enrollment (Phase 2.9.1 not triggered).

## Encryption Posture

Not applicable — no persistent data store, no new cross-component connection. The only
writes are per-run tempfiles under `HIC_TMPROOT` (trap-cleaned, ADR-129 rule (c)) and the
existing local incident ledger.

## GDPR / Compliance Gate

Not triggered. No regulated-data surface; no schema, migration, auth flow, API route or
`.sql` file. None of the four expansion triggers fire. The `single-user incident` threshold
*is* trigger (b) — noted and discharged: the telemetry path carries a reason classifier and
a hook name, never a field value, and A7 asserts that. Phase 2 must not weaken A7.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering

**Status:** reviewed
**Assessment:** Security-boundary change to the hook trust surface. Risks named and
addressed in-plan: (1) the widened program must not change the 20 original hooks'
decisions — AC15 pins this behaviourally rather than by source diff, which is the stronger
assertion; (2) a shared union status token would hand the model a forced-ask vector — D1's
per-slot flag vector closes it; (3) the responder change touches the invariant that makes
"one prompt per tool call" true, and its zero-responder direction is a silent fail-open —
A9's exactly-one assertion catches both directions; (4) two probes (reachability,
`ask`-honored) are preconditions rather than assumptions, because ADR-156's own clause
forbids building on unverifiable harness invariants. No product, legal, finance, marketing,
sales, support or operations implications: no user-facing surface, no vendor, no spend.

### Product/UX Gate

Not applicable. No file in *Files to Create* or *Files to Edit* matches any UI-surface term
or glob — the change set is shell hooks, a shell test suite, an ADR, one `.c4` model file
and a README. Product was not flagged by the sweep and the mechanical UI-surface override
did not fire.

## Plan Review Revisions

Plan v1 went to a 5-agent panel at the `single-user incident` threshold.
`architecture-strategist` and `code-simplicity-reviewer` converged independently on the
same verdict: the #7190 half was right-sized; **all three ADR-162 clauses were defective.**
Every finding below was re-verified against source before being applied.

| # | Finding | Verification | Applied |
|---|---|---|---|
| R1 | v1's D3 claimed "the mirror denies on an unparseable envelope today." **False.** | `.openhands/hooks/guardrails.sh:43-45` — *"Scoped deliberately NARROW … A transport failure keeps the pre-existing behaviour"*; `:60` `\|\| GR_ENVELOPE_SHAPE="unparseable"`, deny fires only on `nonstring`. | D3 rewritten: deny on `nonstring`/`separator`, loud fail-open on the rest. v1 would have been a behavior change on 3 of 5 reason classes. |
| R2 | v1's D3 attributed ADR-157's fail-closed rejection to the "18 hooks per Bash call" hot path. **Misattribution.** | ADR-157:115 contains **no hook count**; the rationale is *self-referential repair* (the fix for a broken `PATH`/missing `jq` is itself a Bash call). The 18-hooks figure belongs to a different rejection at `:123`. | Argument rebuilt on the correct rationale — which *strengthens* the case for not denying on `jq_missing`. |
| R3 | v1's D2 specified "per-matcher responder election in the helper." **Not implementable.** | A hook never receives its matcher; `.tool_name` is empty on the failure path by construction (`hook-input.sh:123`, `:209-214`). Runtime election would be dead code always resolving to "not the responder" — the A9-dead-gate class from `68996d3ed`, one layer down. | D2 demoted to a static space-delimited responder **set** + a settings-level A9 assertion. |
| R4 | D2 is degenerate anyway. | `CronCreate` and `mcp__pencil__open_document` each carry **exactly one** hook (measured). | Recorded; D2 is a data change, and the simpler alternative (guardrails on both matchers) is now an explicit Alternatives row and the probe-failure fallback. |
| R5 | v1's D1 boolean group was unnecessary. | `durable-reminder-prefer-inngest.sh:83-84` **already** does the `has()`-guarded, `//`-avoiding boolean read, with a comment distinguishing absent from present-and-false. | Boolean group deleted. That hook's migration takes only `prompt`. |
| R6 | v1's D1 justified a second program by "rare matchers." **False.** | `skill-security-scan-write` → `Write`; `new-scheduled-cron-prefer-inngest` → `Write\|Edit`. Both read core **and** aux fields → two forks each, taking a `Write` from 5 forks to 9. | Auxiliary program cut. One program. |
| R7 | Flat widening (the simplicity recommendation) couples unrelated tool contracts behind one token, letting the model force an `ask`. | Reasoned from the existing union-token design at `hook-input.sh:78-81`. | Per-slot flag vector + named group predicates — one fork, no coupling. Both alternatives recorded as rejected, with reasons. |
| R8 | The mirror is **three** hooks, not two. | `.openhands/hooks/worktree-write-guard.sh:14,34-45,49` parses the envelope and carries its own assertion; registered on `file_editor`. | Scope corrected; all three covered by the README reason and D3. |
| R9 | `ask` was only ever probed on a `PreToolUse(Bash)` stub. | `DEFER-DECISION-PAYLOAD-SHAPE.md:5`; ADR-156:40-41 names MCP shapes as the unverifiable region. | Phase 5.2 probe precondition + a named fallback. |
| R10 | Phase 5.4's jq hard-fail produces no value in either branch, and 21 sibling suites still skip silently. | 22 suites carry the skip; none hard-fail. | Cut. Item 5's "consider … and justify" discharged by recording the rejection. |
| R11 | v1 Phases 2 and 3 built two overlapping loops asserting the same property. | Read `a3_rce_regression()` and `a14_bare_payload_coverage()`. | Merged into one `INSCOPE20` loop with four properties. |
| R12 | v1's C4 added a new element while unable to decide container-vs-external-system. | Reviewed both `.c4` files + the mandate. | Reduced to amending the existing `engine.hooks` description + edge text. No new element, no `views.c4` change. |
| R13 | v1 had 10 phases, several of which were `/ship`'s job or restated existing conventions. | — | Six phases. Phase 0.2/0.3/0.4 and Phase 10 folded or cut. |
| R14 | v1 ACs included ceremony (`grep -c 'rc'`, an assertion-count ratchet on an unstable baseline, five separate "recorded in the PR body" ACs, method instructions). | — | 17 ACs → each a checkable post-condition; mutation ACs collapsed to one; ratchet cut; AC15 restated as a behavioural pin. |
| R15 | v1 Phase 8.6 shipped an undecided branch ("migrate if … if not, exempt"). | — | Decided: `pencil-collapse-guard` is exempt, with the file-restore caveat written down. |
| R16 | v1 Phase 3.3/3.1 forward-referenced D2 from a #7190 phase, undercutting its own ordering claim. | — | Phase 2.2/2.4 pin the current scalar; the set rewrite happens in Phase 5.4. |
| R17 | Hidden assumption: the `Bash` threat model may not transfer to these tools. | Both reviewers, independently. | Phase 5.1 reachability probe as a precondition that may shrink the migration set. |

**Deferred to the operator as a User-Challenge (not applied):** both reviewers recommended
**splitting this into 2–3 PRs at the Phase 3/4 boundary** (suite hardening alone touches one
file and carries zero trust-boundary risk). The operator's stated direction is one worktree
and one PR closing both issues. Per ADR-084 that is a User-Challenge, not guidance to apply
silently — persisted to
`knowledge-base/project/specs/feat-one-shot-7190-7173-hook-input-contract-hardening/decision-challenges.md`
for `/ship` to surface.

## Deepen-Plan Findings (v3)

`test-design-reviewer` (Farley 8-property, scored **7.5/10 B**) and `security-sentinel` ran
against plan v2. Both **measured** rather than reasoned. Every finding below was
independently re-verified in this worktree before being accepted. Two are blocking.

### Blocking

**F1 — The OpenHands mirror aborts on malformed JSON with no deny, no decision, no
incident row. Phase 6.1's premise is FALSE.** *(security CRITICAL-2)*

```console
$ printf '{"tool_input":' | bash .openhands/hooks/guardrails.sh
jq: parse error: Unfinished JSON term at EOF at line 2, column 0
  rc=5
```

`.openhands/hooks/guardrails.sh:19` runs `COMMAND=$(… | jq -r …)` under `set -euo pipefail`
with **no `|| true`**, so any document jq rejects kills the script *before* the ADR-156
shape check at `:51-60`. A lone surrogate in a sibling field is enough — OpenHands is
Python, `json.dumps` re-emits `\ud800`, and the document is valid to its parser and invalid
to jq. `.tool_input.command` can stay a clean `rm -rf $HOME`. If the OpenHands runtime
treats hook rc 5 as anything but "block," **every guard in the mirror is bypassed silently.**
The same payload on the `.claude` side yields `n == 0` → `unparseable` → rc 1 → ask.

So v2 Phase 6.1's *"the gap is code duplication, not a trust-boundary hole"* is refuted by
measurement — the same error class v2 was written to correct in v1's D3. **Amends Phase
6.1:** the mirror needs a fix regardless of the convergence decision. Minimum, two lines
per extraction, no cross-tree source and none of its fail-hard hazard:

```bash
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) \
  || deny "BLOCKED: the tool-call envelope did not parse (ADR-156/158 D3)."
```

Note this makes `unparseable` **deny**, which contradicts D3 as drafted — see F3. The
current behavior (abort, rc 5) is neither of D3's two options, and **the OpenHands runtime's
response to a non-0/2 hook exit code must be probed before ADR-162 asserts anything about
it.** New Phase 6 precondition.

**F2 — D1's per-slot vector converts an aux-slot failure into a silent ALLOW.**
*(security CRITICAL-1)*

The chain, all four steps verified: under D1, `guardrails.sh` checks only the **core** group,
so a non-string `.tool_input.content` on a `Write` does not flip its flags — that is D1's
stated purpose. `guardrails.sh` parses cleanly and does not ask.
`skill-security-scan-write.sh` reads `content`, its group predicate fails, and per v2 Phase
5.6 it takes the standard non-responder path (`report` → `should_ask` false → `exit 0`):
no stdout, no ask. Claude Code sees no `permissionDecision` → **the Write is allowed and
the security scanner never ran.**

That is ADR-157's explicitly rejected *"fail open with a loud incident."* Worse, it is a
**regression against the hook's own current posture** — `skill-security-scan-write.sh`
already asks rather than allows on both of its "cannot evaluate" branches, with in-source
rationale citing the same threshold:

> `# Scanner missing → ask, not allow. At single-user incident threshold a silently-removed
> scanner must surface for operator approval rather than silently disable enforcement.`

The trade is structural and v2 saw only one horn: **coupled token ⇒ forced-ask vector;
decoupled vector ⇒ silent fail-open on every non-core slot.**

**Amends ADR-162 D1 + Phase 5.6.** The responder model extends from "one hook per matcher"
to "**one core-group responder per matcher, plus each hook is responder for its own
non-core group.**" ADR-157's all-emit objection does not transfer: it concerned 18 hooks ×
a *persistent* fault (`jq_missing`), and `jq_missing`/`internal`/`unparseable` remain
core-group failures owned by the single responder. A per-slot `nonstring` on `content` is
transient, model-induced, and reaches at most two hooks on `Write`. New AC: *no migrated
hook whose failure disarms a deny/ask gate may exit silently on a failed group predicate*,
with a mutation (array `content` on a SKILL.md Write → assert an `ask` on stdout).

### High

**F3 — D3 must be rebuilt a third time, on measured five-class behavior.** `unparseable`
is attacker-inducible (lone surrogate, measured on both harnesses) but is **dead code in the
mirror**: `GR_ENVELOPE_SHAPE="unparseable"` (`:60`) is reachable only if the shape program
fails while the simpler `:19-22` extractions succeeded on the same document, and on jq 1.8
that set is effectively empty. So v2 Phase 6.3's *"assert `.openhands` falls through on
unparseable"* would, written as "no `decision:deny` on stdout," **pass while asserting the
opposite of the truth** — the false-confidence class of the repaired A9 dead gate. Written
faithfully it fails. Fail-open on `jq_missing`/`internal`/`unparseable` remains **sound on
the `.claude` side** and the security reviewer signed it off there.

**F4 — D2's named probe-failure fallback is a no-op under D1.** Registering `guardrails.sh`
on `CronCreate` does nothing: with a non-string `.tool_input.prompt`, guardrails' **core**
group is clean (`.tool_input.command` absent → `""` → string, measured), so it parses, its
guards no-op on a CronCreate payload, and it exits 0 silently. D1 and D2 were revised
independently in v2 and the interaction was never re-checked. Either drop the fallback and
make descoping the only branch, or have guardrails check the **union** of groups on matchers
where it is sole responder (acceptable there — each carries one hook).

**F5 — The flag vector needs a width assertion and positively-phrased predicates.** Today's
`[[ ${_hi_s[0]} != "ok" ]]` is fail-closed against every possible value. A vector consumed
by indexing is not: if it is shorter than expected, `${vec:5:1}` is `""` and a predicate
written `!= "b"` returns true → **treated as ok → guards run against an unvalidated slot.**
Pin in D1 and assert: `hook_parse_input` returns 1 unless `${#_hi_s[0]}` equals the exact
expected width; every group predicate is **positive** (`== "s"`, never `!= "b"`); mutation —
truncate the vector by one char, every predicate must go RED.

**F6 — Nothing binds a hook's slot reads to the group predicate it calls.** A13's three
verbs do not catch a hook that reads `HOOK_FILE_PATH` while calling `hook_input_ok_write`.
Combined with "bad-path values emitted empty," the hook sees `""`, every guard no-ops, exit
0 — **defect 2 restored per-slot**, re-entering through the widening. Add a fourth A13
check: grep each in-scope hook's referenced `HOOK_*` globals, map to group, assert the hook
calls that group's predicate. A static grep over ~24 files, and the only thing standing
between D1 and a silent disarm.

**F7 — Phase 1.1's `bad()`-inside-`decision_for` is the A9 vacuity class reproduced.**
`decision_for` is called exclusively inside `$( )` (~25 sites), so `FAIL=$((FAIL+1))` runs
in a **subshell and is discarded**. Measured: `captured=[ask] FAIL_after=0`. Written to
stderr — the natural reading of "fail loudly" — the decision returns clean, the outer `want`
passes, and the suite exits 0 having detected a non-zero rc and thrown it away. **v2's
explicit rejection of the `"<decision>|<rc>"` return was backwards.** *Amends Phase 1.1:*
leave `decision_for` unchanged and let **A16** own rc via `rc_for()` in the caller's shell —
which is where v2 already puts it, at zero `want`-string churn.

### Medium

**F8 — Phase 3.4's synthesized git repo is itself vacuous.** `_incidents_repo_root()`
(`lib/incidents.sh:36-42`) falls back to `dirname(BASH_SOURCE)/../../..` — **helper-relative,
not cwd- or git-relative** (verified: with cwd inside a fresh git repo and the env unset, it
resolves to this worktree). The synthesized sandbox is a location the fallback can never
return, so "the synthesized repo's ledger is untouched" cannot fail under any mutation — a
vacuous assertion added by the phase whose purpose is removing vacuity. The `git init` also
re-couples to the branch-dependent gate `:56-58` deliberately avoids (#5192) and leaks
`init.defaultBranch` / global config. *Amends Phase 3.4:* no git. Point
`INCIDENTS_REPO_ROOT` at sandbox `T`; assert (a) `T`'s ledger grew **and** (b)
`$REPO_ROOT/.claude/.rule-incidents.jsonl` is byte-identical, treating absent as size 0 on
both sides. Deleting the `INCIDENTS_REPO_ROOT` branch from `_incidents_repo_root` then makes
both RED — the mutation the assertion exists for — and it runs on every checkout.

**F9 — A17 must name `HOOK_FILE_PATH` or prescribed mutation 6 survives.** Only the **last**
emitted record sits at the end of `raw`, so only slot 5 is protected by the
sentinel/trailing-separator pair. Measured against a scratch mutation dropping both: slots
1–4 keep `trailing_nl=YES`; only `HOOK_FILE_PATH` flips to `NO`. v2 Phase 3.7 says "`HOOK_CMD`
and one other slot" — two of the three available choices make mutation 6 **GREEN**, and the
PR body would record a mutation row that was never RED. *Amends Phase 3.7:* the
trailing-newline case is asserted on `HOOK_FILE_PATH` (slot 5); the second slot covers the
non-trailing whitespace properties.

**F10 — A16 needs a fourth payload class: `jq_missing`.** v2 covers unparseable/happy/deny.
`jq_missing` is the class where `hook_input_emit_ask`'s printf envelope is the *only*
surviving channel (`lib/hook-input.sh:277-281`) — `emit_incident` needs jq too — so a
non-zero exit there voids the ask **with zero telemetry**. A mutation
`[[ "$HOOK_INPUT_REASON" == jq_missing ]] && exit 1` survives A16 as drafted. Reuse A5's
shim PATH (`:253-278`). Also: A16's name overclaims — `pre-merge-auto-close-scan.sh:252`
carries a deliberate commented `exit 2` on a branch no A16 payload reaches; scope the
comment to the probed classes so a future maintainer does not delete it as a violation.

**F11 — Three of the four migration targets emit an unconditional explicit `allow`.**
Measured on a happy `Write`: `skill-security-scan-write` and
`new-scheduled-cron-prefer-inngest` both return
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}`;
`durable-reminder-prefer-inngest` likewise. When Phase 5.6 grows `INSCOPE20`, **Phase 2
property (iv) ("silent unless responder") goes RED for three of four new members** — a
guaranteed mid-implementation stall that v2 budgets as a small data change. Either Phase 5.6
also rewrites their emit behaviour, or property (iv) carries an explicit exempt list.
Related and newly reachable: an explicit `allow` from these hooks races an `ask` from
`guardrails.sh` on the same `Write`. Under the union token both fail together and both go
silent, so the combination is unreachable today; **D1's decoupling makes allow-vs-ask
reachable for the first time**, and Claude Code's resolution order for it is unestablished.
Per ADR-156's own clause that is a **third probe**, alongside 5.1 and 5.2.

**F12 — `command -v jq || allow` short-circuits *before* the parse gate in two designated
responders.** `durable-reminder-prefer-inngest.sh:66` and
`new-scheduled-cron-prefer-inngest.sh:51` both exit with an explicit `allow` when jq is
missing. Under D2 `durable-reminder-prefer-inngest` becomes the **sole responder on
`CronCreate`**, so with jq absent that matcher has **zero responders** — the plan's own
stated P0 direction. *Amends Phase 5.6:* every migrated hook's pre-existing jq/parse
short-circuit is **deleted**, not layered above the helper. Mutation: `PATH=/nonexistent` +
a `CronCreate` payload → assert an `ask`.

**F13 — The mirror's `$t == null` conjunct is unsatisfiable, and it denies every payload
without a `tool_input` object.** `type` returns the **string** `"null"`; measured,
`$t == null` → `false`, `$t == "null"` → `true`. Consequences, both measured: the mirror
denies `{"tool_input":null,…}` **and** `{"working_dir":"/tmp"}` (no `tool_input` at all),
rc 2 — an availability incident in a harness with no `ask` and no recovery path, where
`.claude` parses both cleanly. It also falsifies the mirror's own comment that the guard
*"fires only when the document PARSES and a contracted field is the wrong TYPE"* — the
sentence D3 is built on — and it is a **third divergence class** neither of Phase 6.3's
planned parity cases would catch. Fix the conjunct to `$t == "null" or $t == "object"` and
add the parity case.

**F14 — `security_reminder_hook.py` is a PreToolUse hook on `Edit`, in neither list.**
Verified registered on the `Edit` matcher. It reads the same model-controlled envelope and
is explicitly fail-open. It is absent from `INSCOPE20`, from Phase 5.6's migration set and
from Phase 5.7's exemption list — so **AC10 passes vacuously** while a Python PreToolUse
hook sits outside the ADR-156 boundary undocumented. "It is Python and cannot source a bash
helper" is a fine reason; write it down. Note also its `emit_incident(…, cmd=…)` path
(`:52`, `:217`) is a second telemetry writer with its own truncation, not covered by A7.

**F15 — Phase 2 must keep A12 (stray artifacts) as a fifth property.** A12 (`:161-176`)
appears in neither v2 Phase 2.1's four properties nor AC3, and it currently depends on the
**shared** `$run` that per-hook sandboxes dissolve. High risk of silent loss during the
merge. Add as property (v), per-hook, keeping `.claude` allow-listed (each sandbox is now
also an `INCIDENTS_REPO_ROOT`). A3's positive control also needs its own directory once the
shared `$run` is gone.

**F16 — The telemetry claim in § User-Brand Impact and § GDPR is broader than A7 asserts,
and false as written.** A7 reads the first row of one sandbox from one hook on one payload
class. Repo-wide, full model-controlled command text and file paths already reach the ledger
on every guard deny — `guardrails.sh:125,145,161,281,300,325,373,392` pass `"$COMMAND"`;
`worktree-write-guard.sh:69` and `pencil-open-guard.sh:43` pass `"$FILE_PATH"`. That may be
intended for forensics, but the GDPR section discharges trigger (b) on a claim A7 does not
check. Narrow both sections to: *the `hook-input` **fault** rows carry only a classifier and
a hook name, asserted by A7.*

### Low

**F17** — `grep -c` counts *lines*, not occurrences; Phase 3.2's jq count must be
`grep -oE '\bjq\b' | wc -l`. The claim "exactly twice, comment-stripped" is **verified**
(`:125` `command -v jq`, `:147` the invocation; raw count 28, so the strip is load-bearing),
but the count is not a fork count — relocating `:147` into a loop keeps it at 2. Retitle the
assertion. **AC16 contradicts Phase 3.2** (it requires the assertion pass "unchanged" while
3.2 rewrites it) — reconcile.
**F18** — D2's membership test must be space-padded/loop-based, not a bare `==` glob match:
an empty `HOOK_INPUT_HOOK` would otherwise make **every** hook a responder (the
20-prompts-per-call loop ADR-157 designed against), and `guard` would substring-match
`guardrails`. Use an explicit `for r in $HOOK_INPUT_RESPONDERS` loop with `local IFS=' '`.
No injection risk otherwise — all 20 call sites pass hardcoded literal basenames (verified).
**F19** — A9 reads only `.claude/settings.json`; Claude Code merges `settings.local.json`,
`~/.claude/settings.json` and enterprise policy. A hook registered through any of those gets
zero responders and A9 cannot see it. Record the limitation in D2 at minimum.
**F20** — Phase 3.3's `SKIPPED` counter: the `:29` jq precondition exits *before* the summary
prints, so a jq-less machine emits no summary line at all for `test-all.sh` to read. Make
that path print the summary form. AC1's "0 skipped" is also python3-dependent (`:234-244`).
**F21** — Phase 3.1's A4 apostrophe non-emptiness is **not** needed: measured, an empty range
yields `awk '{print $1-2}'` → `-2`, and `want "0" "-2"` is already RED. Harmless for
uniformity, but v2's justification for it is wrong. A11's program check *is* vacuous
(`printf '%s\n' "" | grep -cF '$'` → `0`) — that one is real.
**F22** — Runtime budget: baseline 9.1s; A16 adds ~60 hook invocations and Phase 2 goes
14→20 with per-hook ledger reads. Roughly 2–3×, unbudgeted. A16 can reuse Phase 2's
invocations. Also consider dropping Phase 2's rc property (it duplicates A16's unparseable
class) or having Phase 2 use the *happy* class so the two cover disjoint ground.

### Surviving-mutation classes after v3

Named so they are not mistaken for coverage: `exit 1`/`exit 2` gated on `internal`;
an `exit` added inside `hook_input_report`..EOF with non-leading whitespace
(`[[ x ]] && exit 1` evades A11's `^\s*exit `); a second jq fork created by relocating the
invocation into a loop or by swapping `command -v jq` for `type jq`.

### Effect on the split recommendation

**F1, F2, F3, F4 and F13 all live in Phases 4–6. None touches Phases 1–3.** The
security-sentinel reached the split conclusion independently of the two plan reviewers, and
added a reason none of them had: the trust-boundary half now needs a further design pass and
**three more probes** (OpenHands rc-5 runtime semantics, allow-vs-ask resolution order, plus
the two already planned). DC-1 is updated accordingly. Phases 1–3 remain sound and
independently shippable.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The widened program changes a decision for one of the 20 original hooks.** | Core slots keep positions 1–5 additively; absent fields still render `""`. AC15 pins behaviour on the existing fixture corpus rather than a source diff. The full mutation battery re-runs in Phase 6.5. |
| **The per-slot flag vector is a more complex record-0 than the union token.** | Real cost, accepted deliberately: the union token hands the model a forced-ask vector (§ User-Brand Impact). Both alternatives are in ADR-162's Alternatives table so the trade is reviewable, and the group predicates are fixed constants — no interpolation, no `printf -v`. |
| **Zero responders on a matcher — a silent fail-open.** | A9's exactly-one assertion over `.claude/settings.json`, plus its existing non-vacuity control. ADR-162 D2 states explicitly that zero is the P0 direction and two is P2. |
| **`ask` may not be honored on `mcp__*` / `CronCreate`.** | Phase 5.2 probe is a precondition, with a named fallback (guardrails on those matchers) and descoping as the last resort. Building on it unprobed would violate ADR-156's own clause. |
| **The migrations may defend nothing** if the harness already rejects non-string `tool_input` for these tools. | Phase 5.1 reachability probe sizes the set. A migration that defends nothing is cut, not shipped for symmetry. |
| **Scope.** Two issues, one PR, a security-critical helper. | Six phases; Phases 1–3 touch one file and are independently shippable. The split recommendation is persisted as a User-Challenge rather than silently applied or silently dropped. |
| **ADR-162 ordinal collision** with a sibling PR. | `/ship`'s collision gate re-verifies against `origin/main`. On renumber, sweep `plans/` + `specs/` in the same edit or AC13 cites a nonexistent file. |
| **Mutations accidentally committed.** | Applied to a scratch copy, observed RED, reverted. Phase 6.5 re-runs from a clean tree; `git status` must show only the intended diff. |
| **Widening a loop to 19 surfaces a genuine divergence**, tempting a trim back to a passing subset. | Phase 2.3 mandates listing divergent hooks — the discipline A14's existing comment already applies. |

## Test Scenarios

1. **Baseline** — 50/50 before any edit; `pre-merge-rebase-parity.test.sh` green.
2. **Exit codes** — `exit 2` post-ask in the responder; `exit 1` in a non-responder; `exit 2`
   in a non-responder. Each RED.
3. **Reachability pairing** — `exit 0` at line 3 of two hooks: absence green, presence RED.
4. **Cardinality** — disarm the parse gate in a hook outside the original four: RED.
5. **Vacuity** — rename `_HOOK_INPUT_JQ`; rename `hook_input_report`; add a second `jq` as
   `$(jq …)`; delete the aggregator. Each RED.
6. **Fidelity** — trim whitespace from `HOOK_CMD`: RED. Drop sentinel + trailing separator:
   RED on the trailing-newline case.
7. **Probes** — non-string `filePath` / array `content` against the real tools; `ask` on
   `mcp__pencil__open_document` and `CronCreate`. Outcomes recorded, migration set sized.
8. **Migration** — each migrated hook: non-string in a slot **it reads** → correct posture +
   incident row + rc 0; non-string in a slot it does **not** read → **unaffected** (the
   per-slot vector's whole point); string envelope → guard behaves as before.
9. **Responder** — exactly one per matcher; a deliberate double-designation is RED; a
   deliberate zero-designation is RED.
10. **Parity** — non-string: `.claude` asks, `.openhands` denies. Unparseable:
    `.openhands` falls through. Existing T-S and behavioural cases unchanged.
11. **Integration** — full `test-all.sh`; C4 syntax + render tests.

## Sharp Edges

- **`/deepen-plan` is mandatory before `/work`.** At `single-user incident` threshold,
  `plan-review` catches style, scope and YAGNI; the deepen triad
  (`data-integrity-guardian`, `security-sentinel`, `architecture-strategist`) is where a
  flaw in the flag-vector encoding or the responder-set membership test gets caught. v1's
  three defective ADR clauses are the existence proof.
- **`exit 2` and `exit 1` both discard stdout JSON.** Any future hook edit introducing a
  non-zero exit voids the ask/deny envelope entirely. The single most important fact in
  this plan, and the reason item 1 outranks the other five.
- **A9 resolves coverage at the tool level, not by matcher-string equality.** `Write` and
  `Write|Edit|MultiEdit|NotebookEdit` are different strings that both cover a `Write` call.
  Reasoning about the responder invariant from matcher strings is what made blocker 2 look
  four times larger than it is (it blocks zero hooks).
- **A hook cannot know its own matcher, and `.tool_name` is empty on the failure path.**
  Any responder logic keyed on tool identity at runtime is dead code that always resolves to
  "not the responder." The election must be static and settings-derived.
- **ADR-157's fail-closed rejection reasons from self-referential repair, not hook count.**
  Do not re-derive it as a volume argument — that misreading is what produced v1's D3, and
  it inverts the conclusion for `jq_missing`.
- **The OpenHands mirror's `nonstring`-only scope is deliberate and load-bearing.** Routing
  it through a helper whose rc 1 covers five reason classes and denying on rc 1 widens the
  deny to `jq_missing`, where the deny blocks its own repair.
- **The mirror's `freeze-lock.sh` source at `.openhands/hooks/guardrails.sh:29` is
  deliberately fail-soft.** If Phase 6.1 is ever revisited, do not copy that line's shape
  for the input helper — fail-hard, per `lib/hook-input.sh:29-32`.
- **`grep -c '| jq '` is not a `jq` census.** It misses `$(jq …)`, `< <(jq …)` and
  `jq … < file`. Count the token, not the pipe — and do not escalate into a regex arms race.
- **An extracted range that yields empty passes every content assertion vacuously.** Assert
  non-emptiness first — the A9 lesson from `68996d3ed`, applied to A11 and to the A4
  apostrophe check that shares A11's anchor.
- **Do not trust the issue's "48/49 assertions" figure.** Measured baseline is 50/50 with
  the ledger absent. Anchor deltas on Phase 0.1's own measurement, and do not write a
  count ratchet into an AC — the number is worktree-dependent.
