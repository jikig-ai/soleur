---
title: "feat: route technical forks in closing prose to the CTO agent"
date: 2026-10-12
slug: closing-prose-technical-fork-gate
branch: feat-one-shot-closing-prose-technical-fork-gate
issue: 10057
lane: single-domain
type: feat
---

## Overview

A technical fork reached the operator again on 2026-10-12, this time as end-of-turn prose rather than a
tool call or a rendered artifact: a closing message listed numbered decisions and a "your calls" line of
questions on evidence sufficiency, a design choice and an ordering. The rule
`hr-technical-fork-is-not-an-operator-question` was in force, and none of its three enforcers can read a
closing message. This plan adds the missing enforcer at that carrier (a repo-local Stop hook), shares its
vocabulary with the existing pre-ask hook through one library so the two cannot drift, places short
pointer lines where skills close, and records the carrier lesson.

The founder's correction is the acceptance test: "you should ask the CTO, not me ... improve the workflow
and skills so we ask those to the CTO in the future".

## Research Insights

### Premise Validation (Phase 0.6)

Checked by reference, against `origin/main` and `gh`:

- **#9642** is an OPEN issue (the web-2 emptiness-evidence question), not a PR. The brief calls it the PR that
  introduced the delegation reference. `git log -S"Ruled by CTO agent"` shows the reference
  (`plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`) arrived in PR
  **#10049** (commit 83851c9e1c, merged 2026-10-11). The pointer lines link that one file; no second reference is written.
- **#7462** is CLOSED (inngest host restore). It is the historical incident named in the rule's `Why`, not a work target.
- **#10057** (OPEN, `deferred-scope-out`): "chat-prose Stop-hook arm for an unruled owner-ruling label". Its
  re-evaluation trigger was "the first hit" of the carrier. The 2026-10-12 session is that hit, so this PR closes it.
- **#10056** (OPEN): port the pre-ask gate to `plugins/soleur/hooks` for end users. Stays open (see D1 and Deferral Tracking).
- **The brief's Stop-hook location was wrong** and the brief says so: `unkept-promise-hook.sh` is a PLUGIN hook
  at `plugins/soleur/hooks/`, registered in `plugins/soleur/hooks/hooks.json`; `.claude/settings.json` registers no Stop hook.
- **ADR corpus (Phase 0.6 item 4).** ADR-084's 2026-10-11 addendum lists "a Stop-hook label matcher over closing
  chat text" as REJECTED (13-of-15 over-block record). That rejection was about an exact-LABEL arm with a producer
  the ship gate removed. This plan is cue-based on a label-less carrier, which is the re-evaluation trigger the
  addendum itself named. The ADR is amended in this PR (see Architecture Decision).
- **Measured, not supposed (Phase 0.6b item 2).** The brief asks for "the SAME cue vocabulary" as the pre-ask hook.
  Driving the three must-BLOCK questions and the two must-PASS questions through the real
  `.claude/hooks/pre-ask-technical-fork-gate.sh` returned ALLOW for all five. No existing cue matches any of the
  three, and question (b) contains the word `deploy` (as `deploy-channel`), which `RULING_OPVOCAB_RE` matches, so a
  weak cue would be silenced on exactly the sentence it must block. Sharing the lib is therefore necessary but not
  sufficient: the shared vocabulary has to GROW.

### Property List and Cut List (Phase 0.6b)

Properties:

- **P1** A closing message that asks the operator to choose on a technical fork (evidence sufficiency, design choice, ordering) is stopped once and redirected to the CTO.
- **P2** A request to authorize a production act, a money/scope/priority/schedule/legal/brand question, and a message with no question are never stopped.
- **P3** The pre-ask hook and the closing hook cannot drift: one definition site for the shared vocabulary, one verdict function.
- **P4** The gate's own faults never block a session end: fail open on any parse doubt, at most one block per turn.
- **P5** The skills that close a phase name the closing message as a carrier of the rule.
- **P6** The carrier lesson is recorded where the next planner finds it.

Cut List (mechanism, property, what already covers it or why cut):

| Mechanism | Verdict |
|---|---|
| Exact-label Stop arm in the plugin hook (#10057's design) | Cut: brittle (CTO R3); replaced by cue-based design; #10057 closed as superseded |
| Plugin placement (`plugins/soleur/hooks`, `hooks.json`) | Cut for now (CTO ruling T1): needs a web opt-out plus the web-parity test and carries third-party false-positive risk; tracked as #10056 with a graduation criterion |
| Separate unit suite for the lib | Cut: lib drift is asserted inside the closing-hook suite and the pre-ask suite; a second floor-bearing suite would need its own promotion |
| Committed false-positive sampling script | Cut: the sample runs from the scratchpad and only counts are recorded (CTO T5, nothing from transcripts is committed) |
| Transcript parsing for the closing text | Cut: `last_assistant_message` is in the Stop payload (the plugin hook already relies on it) |
| Judging "Decision for you: 1. 2. 3." lists that carry no `?` | Cut (CTO T3): high over-block risk; accepted residual |
| Pointer lines in `plan` and `work` | CTO ruled cut (T6); the brief names them, so the default taken is to keep them (see Decision Classes, S1) |

### Repo research (consolidated)

- Pre-ask hook: `.claude/hooks/pre-ask-technical-fork-gate.sh` (448 lines). Ruling arm cues at lines 320-334; per-question loop
  at 341-401; `AUTHZ_VERB_RE` at 251. Suite: `.claude/hooks/pre-ask-technical-fork-gate.test.sh` (977 lines, 140 cases, V1-V5
  non-vacuity, floor `MIN_CASES=140` reported by `printf` + `exit 1`). The suite reads regexes OUT of the hook source with `sed`
  at lines 343 (`EXTERNAL_EXPERT_RE`), 395-396 (`AUTHZ_VERB_RE`, `AUTHORITY_RE`) and 842 (`RULING_PERM_RE`); moving cues to a lib
  means those reads must follow the cues.
- Stop hook model: `plugins/soleur/hooks/unkept-promise-hook.sh` (payload fields `stop_hook_active`, `last_assistant_message`;
  8000-byte tail, fence strip, sentence split via `tr`/`sed`, `{"decision":"block","reason":...}`). Suite
  `plugins/soleur/test/unkept-promise-hook.test.sh` (SUT-written execution marker `SOLEUR_HOOK_TRACE`, both-direction fixtures, floors).
- Registries (ADR-223): `.claude/settings.json` (Claude-canonical; Devin also loads it), `.devin/config.json`, `plugins/soleur/hooks/hooks.json`,
  `.codex/config.toml`; ledger `.claude/hooks/devin-dispositions.tsv` (row per registration); drift guard
  `.claude/hooks/devin-matcher-parity.test.sh`. A repo-local Stop entry needs a `claude-settings ... Stop (none)` ledger row; the
  existing precedent is `soleur-plugin ... unkept-promise-hook.sh Stop (none) already-fires` (EC section 3: Stop fires under Devin with an empty matcher).
- `settingSources:[]` in the web Concierge blocks `.claude/settings.json` hooks, so a repo-local Stop hook never runs in web.
  Plugin Stop hooks DO run in web unless disabled (`SOLEUR_DISABLE_*` in `AGENT_ENV_OVERRIDES`, parity test
  `apps/web-platform/test/plugin-stop-hooks-web-parity.test.ts`).
- Test registration: `scripts/test-all.sh` auto-globs `.claude/hooks/*.test.sh`; `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`
  are regenerated (`python3 scripts/regenerate-shard-manifest.py --incremental --write`); `scripts/guard-vacuity-floor.test.sh`
  treats `.claude/hooks/` as a DEFERRED directory, so a new floor-bearing suite there must be PROMOTED per file (`PROMOTED_FILES`,
  repeated assignments, the last one is effective) and `MIN_FIRING_SUITES` ratchets up by one, never `MAX_DEFERRED`.
- Skill byte ceilings (`plugins/soleur/test/skill-body-budget.json`, enforced against the merge-base): `one-shot` 52000 vs 50360 bytes
  (1640 headroom), `plan` 120000 vs 118913 (1087), `work` 359189 vs 359189 (**0**). `go` is a shim whose authority is
  `plugins/soleur/commands/go.md` (69922 bytes, no ceiling row). `lint-skill-body-budget.py --base $(git merge-base HEAD origin/main)` is green at plan time.
- Existing prose and links to the same reference (all failed to prevent 2026-10-12): `go.md` Sharp Edges (line 629), `work` line 286, `plan` line 951,
  `one-shot` lines 144 and 259, `ship` line 1621.
- Open code-review overlap: #4133 touches `plan/SKILL.md` (schema parity test; unrelated, acknowledged) and #9705 mentions `model.c4` (unrelated, acknowledged).

### Institutional learnings applied

- `2026-10-11-the-rule-existed-and-the-carrier-was-an-artifact-pipeline-the-hook-never-saw.md`: find the carrier first; a gate needs a could-not-measure arm distinct from pass.
- `2026-10-11-a-plain-word-escape-hatch-needs-an-empty-label-exclusion.md`: anchor the label, exclude empty labels, put the discriminating text in the FINAL sentence of must-block rows, and assert the block reason carries no angle-bracket text.
- `2026-09-30-plugin-stop-hooks-run-in-web-sessions-and-a-strip-wider-than-its-producer-is-a-defect.md`: why the plugin placement is not free; matchers must be linear and mirror the producer's exact vocabulary.
- `2026-09-15-devin-dual-hook-registries-dead-matchers-fires-then-noops.md`: Devin loads settings.json AND plugin hooks.json with no dedup; keep the ledger row and the parity test in the same PR.
- `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md` and `2026-10-04-...-the-loop-i-added-to-close-it-did-nothing.md`: the floor reports via `printf` + `exit 1`, never through the helper it backstops; a removal loop needs a canary.
- `2026-10-01-a-grep-q-in-a-pipefail-chain-made-the-trigger-miss-its-own-bug-class.md`: no `producer | grep -q` under `pipefail`; filter to a file or use a herestring.
- `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct.md`: fund skill bytes by RELOCATING prose, diff clause by clause.

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| The model Stop hook lives under `.claude/hooks` | It is `plugins/soleur/hooks/unkept-promise-hook.sh`, registered in `hooks.json` (the brief corrects itself) | Model on it; place the new hook per the CTO ruling (repo-local) |
| PR #9642 introduced the delegation reference | #9642 is an open issue; PR #10049 introduced the file | Link the file; cite #10049 |
| Escape form is `<stop>OPERATOR-GATE: ...</stop>` | The plugin hook retired that markup (users read it as raw text); a repo-local hook never reaches web | Honour it silently as one of three escapes; the block reason prints no angle-bracket text (CTO T4) |
| Use the SAME cue vocabulary | The existing cues match none of the three must-block questions (measured) and the existing veto silences question (b) | Shared lib with a SHARED group (byte-identical move) plus a CLOSING group, and a BUSINESS/ACTION veto split (CTO T2) |
| Fixtures "drawn from real closing messages" | `cq-test-fixtures-synthesized-only` requires synthesized fixtures | The three brief sentences are used verbatim (supplied by the brief, no secrets or personal data); every other fixture is synthesized |
| Pointer lines in one-shot, go, work and plan | `work` has 0 bytes of headroom; the CTO ruled plan and work cut | Keep all four (stated scope); fund `work` by relocation; see Decision Classes S1 |
| `[hook-enforced:]` tag "should" name the new hook | The rule body is ADR-092 human-gated | One follow-up issue; net-issue-flow satisfied by `Closes #10057` (NET 0) |
| The Stop hook "blocks at most once per turn" | `stop_hook_active` carries it on Claude Code; its presence in a Devin envelope is unmeasured | Absent `stop_hook_active` key is parse doubt: fail OPEN |

## Problem Statement

`hr-technical-fork-is-not-an-operator-question` has three enforcers and each reads a different carrier:

1. `.claude/hooks/pre-ask-technical-fork-gate.sh` reads only `AskUserQuestion` tool calls.
2. `ship/scripts/technical-ruling-gate.sh` reads only a `## Decision Classes` table in `decision-challenges.md` or a PR body.
3. one-shot runs that gate once, after the plan phase.

On 2026-10-12 the carrier was none of these: plain interrogative sentences in the closing message of a turn. A
rule-enforcer pair that cannot see a carrier is not an enforcer of that carrier (the 2026-10-11 learning's
lesson). The unkept-promise Stop hook sees closing text but is about promises and parked work, and its
over-block history (13-of-15 mandated operator gates) is the standing warning about a wide net.

## Proposed Solution

1. **Shared lib** `.claude/hooks/lib/technical-fork-cues.sh` holding the cue regexes and one verdict function
   `tfc_is_fork <unit> <groups>`, a predicate always called inside an `if`: exit 0 = technical fork (block), exit 1 = pass, exit 2 = bad
   arguments (an unknown group name, so a typo can never silently mean "shared only"; callers treat 2 as pass plus a stderr line). It prints
   nothing and sets the global `TFC_HIT` to the matching cue name. Groups: `shared` (the existing ruling cues, `RULING_PERM_RE`,
   `RULING_MONEY_RE` and the veto, moved byte-identical) and `shared+closing` (adds the three new cues and the closing-only veto). The pre-ask hook calls
   `tfc_is_fork "$__rq" shared`; its behaviour is unchanged. The lib is pure (no `emit_incident`, no `.claude/` paths, no `set`), is located through ONE variable in each consumer
   (`TFC_LIB`) so graduation edits one line per consumer, and offers `tfc_self_check` (every cue variable non-empty, `tfc_is_fork` defined) that both hooks call instead of keeping their own variable lists.
2. **Closing hook** `.claude/hooks/pre-closing-technical-fork-gate.sh`, a `Stop` entry in `.claude/settings.json`.
   It reads `last_assistant_message`, judges each `?`-terminated sentence of the closing window alone with
   `tfc_is_fork "$s" shared+closing`, and blocks at most once per turn.
3. **Tests**: a new suite `.claude/hooks/pre-closing-technical-fork-gate.test.sh` (both-direction fixtures, mutation rows,
   non-vacuity, floor) and additions to the pre-ask suite (lib-sourcing assertions, non-regression rows; `sed` reads repointed).
4. **Registries**: `Stop` registration, ledger row, exec bit, floor-ratchet promotion, shard manifest.
5. **Skill carriers**: one pointer line each in one-shot (before Step 8), go (`commands/go.md`), work (step 3.5) and plan (Post-Generation Options).
6. **Record**: ADR-084 addendum, C4 Hook Engine description, compound learning, one follow-up issue, comments on #10056/#10057.

## Ruled by CTO agent, 2026-10-12 (plan-time ruling, brief on the design above)

Spawned `soleur:engineering:cto` with the measured facts (the existing cues match none of the three questions; the veto
silences question (b); the web-parity cost of a plugin placement; the plugin hook's retired markup; the skill headroom) and the draft
design D1-D9, "do NOT use AskUserQuestion". Abridged substance (T1-T8 are this plan's numbering of the CTO's eight answers):

- **T1 Location: repo-local.** `.claude/hooks/pre-closing-technical-fork-gate.sh`, a new `Stop` entry in `.claude/settings.json`,
  ledger row `already-fires`. Graduation to the plugin only together with the pre-ask gate, under #10056, in one PR that adds the
  `SOLEUR_DISABLE_*` env opt-out and satisfies the web-parity test, and only when ALL hold: 30 days in service, at least 10 recorded
  firings (`emit_incident`), zero founder-reported wrongful blocks, the false-positive sample re-run clean.
- **T2 Cue structure.** Two named groups in one lib. SHARED moved byte-identical (the 140 pre-ask cases and V1-V5 pass unchanged, else revert
  the refactor); CLOSING is new. The group is a function argument, never a flag inside a regex. `RULING_OPVOCAB_RE` is redefined as
  BUSINESS|ACTION; CLOSING cues are vetoed by BUSINESS only (the design of a deploy channel is technical; a landing-page headline is not).
  Three STRONG cues (each already sits on a `?` sentence, so no co-signal is needed): CL1 sufficiency, CL2 design, CL3 ordering (regexes in
  Technical Approach). The verdict function owns the weak-cue interrogative extraction, the vetoes and the permission exemption, so the
  exemption always reads the same unit as the cues and applies to every cue; a unit over 600 bytes is not judged (passes, stderr note).
- **T3 Closing window.** Strip fenced blocks, take the last 1500 bytes of prose, drop a leading mid-sentence fragment, split on `?`/newline/`. `/`! `,
  judge only sentences ending in `?`, each alone; any hit blocks. "Decision for you: 1. 2. 3." with no `?` is not judged (accepted residual).
- **T4 Escapes.** Any one of: `<stop>OPERATOR-GATE: ...</stop>` or `<stop>BLOCKED: ...</stop>` (anywhere in the window, honoured silently);
  a sentence-initial `Operator-only (money|scope|priority|schedule|irreversible|production-mutating|legal-risk|brand): ...`; a final-sentence plain
  `Paused:`/`Blocked:` label. Each needs non-empty content (`Blocked: none.` does not count). The block reason names `soleur:engineering:cto`
  (`soleur:legal:clo` for legal), says to record "Ruled by CTO agent", lists the closed operator-only categories, states the split remedy,
  cites `hr-technical-fork-is-not-an-operator-question`, teaches only the plain forms, and contains no `<` or `>` (a test asserts it).
- **T5 False-positive budget.** Newest 300 final assistant closings from the local session transcripts that carry a `?` in the stripped window;
  offline classifier with `stop_hook_active=false`; counts only in the PR body; every hit classed technical, operator-class or ambiguous.
  Bar: ZERO operator-class or ambiguous hits; more than 15% of the sample blocked means the cue set is too broad (cut before shipping).
  On any false positive: narrow with a veto or tighter shape, add a synthesized fixture, re-run the whole sample; two failed rounds on the
  same cue drop that cue. Never ship with a known false positive.
- **T6 Skills.** The CTO's cut: pointers in `one-shot` and `go` only, each naming the closing message and "Decision for you:" lists as the carrier
  (new information, not a repeat of the rule), none in `plan` or `work`, no trimming of `work/SKILL.md` line 286. Reason: the rule prose and
  link already exist in all four and the failure happened anyway; the hook carries the property.
- **T7 Reconciliation.** R3 stands for the exact-label arm. This hook is cue-based on a label-less carrier: close #10057 as superseded (`Closes #10057`),
  file ONE follow-up for the rule's `[hook-enforced:]` tag (no `AGENTS.rules.md` edit, ADR-092), leave #10056 open with a comment stating the
  graduation criterion. Triggers: a founder-reported wrongful block triggers immediate narrowing or removal; a missed fork triggers a new cue plus
  fixture only after the sample re-runs clean; a 30-day incident review applies the graduation test.
- **T8 Most likely failure: recall decay.** The cues are phrase-shaped; the next phrasing ("is the personal CLI token acceptable?") passes. Do not
  broaden preemptively; the incident log plus the miss, cue, fixture loop is the remedy. Cheapest scope cut: the CLOSING group is its own cue set,
  so the pre-ask hook is not widened.
- **Dissent:** none on the core design. Evidence that flips it: an un-narrowable false positive in the sample drops that cue; recurring misses at a
  rate that makes cues pointless flips to label-plus-list judging; firings that originate in `plan` or `work` sessions flip T6 to add those pointers.
  Thin evidence flagged by the CTO: the regexes were specified, not run (this plan runs them, see Technical Approach); the 15% ceiling and the
  30-day / 10-firing numbers are judgement calls.

**Plan-review amendments to T2-T4 (2026-10-12; mechanical, none changes a ruling's substance).** (a) The 600-byte unit cap moves OUT of the shared function
into the closing hook's call site: the pre-ask suite pins DENY on 30-60 KB questions (rows T1-T4, `pre-ask-technical-fork-gate.test.sh` lines ~775-815) and the pre-ask hook hands the
function a whole question, so a cap inside the lib would silently weaken an existing gate; the CTO's intent (a bound on what the closing hook feeds the regexes) is kept.
(b) `headline` is dropped from the BUSINESS veto: the string-equality claim for `RULING_OPVOCAB_RE` forbids a new member and fixture A2 already passes with no cue. (c) The predicate is
named `tfc_is_fork` with a validated group argument and an exit-2 arm. (d) The closing hook's `systemMessage` (user-visible, separate from `reason`) carries the kill switch
`SOLEUR_ACK_TECHNICAL_FORK=1` (read from the hook's environment, so it must be set before a session starts) and the plain escape wording, and the reason ends by telling the model to say in
one line why it re-sent; neither carries angle-bracket text. (e) Inline code spans and quoted (`>`) lines are stripped from the window before splitting, up front, because sessions in this repo
quote these very phrases while editing the hook; stripping can only make the hook block less. (f) CL2b stays (ruled, and it is the founder-observed phrase "do you want a migration design?"); the Phase 4
sample is what drops it. (g) Plan review measured near-misses that over-block, so two ruled cues are NARROWED (never widened; the CTO's own false-positive protocol allows a tighter shape): CL2a needs an object (`for|to|of|when`), CL2b needs a technical noun, and a CLOSING-only extra veto (`CLOSING_EXTRA`) covers `prioriti[sz]e`, `publish`, `announce`, `auditor`, `accountant`, `lawyer`, `investor`, `customer`, `feature`, `roadmap`, `milestone`; the fixtures B1-B3 are unaffected. (h) `AUTHZ_VERB_RE` stays in the pre-ask hook with `AUTHORITY_RE` (the closing hook never evaluates it). (i) Unit boundaries: a `?` ends a unit only before whitespace, end of text or closing punctuation, so URLs are safe. (j) Deepen-plan (spec-flow P0-1) found that a whole-window escape lets one appended `Operator-only (money): ...` sentence pass three unrelated technical questions, the silent self-label path. The escape scope is therefore: `<stop>` forms and a final-sentence `Paused:`/`Blocked:` stay whole-window (the brief's fixture A4 and the plugin hook's own escape require it), while `Operator-only (category):` governs only its own sentence and the next `?` unit in the same paragraph. This makes the hook block MORE than the CTO's wording for that one form; it is recorded as the taste row S2 (the CTO may overrule). (k) Deepen-plan (spec-flow P0-2) found the block has no teeth unless the reason's FIRST imperative is the action: an Agent-tool call to `soleur:engineering:cto` (legal: `soleur:legal:clo`), with the escapes listed after it and only for a genuinely operator-only fork, and a tail that asks for the ruling (or the category) in one line plus only the delta and the authorization, because Stop fires after the founder has already read the message. (l) Deepen-plan (security F1) bounded the hook's cost by unit COUNT (last 12 units, one normalisation, `"timeout": 10`) and (F7) replaced the ledger's unit text by cue name, length and sha256.

**Adopted:** T1, T2, T3, T4, T5, T7, T8 as ruled. **T6 partly adopted:** the `one-shot` and `go` pointers as ruled (their text names the closing
carrier). **Not adopted as ruled:** the cut of the `plan` and `work` pointers. The brief names all four skills, a stated scope item, and dropping an
operator-stated scope item is a NEVER-Mechanical class (decision-principles.md). Default taken: keep the four, as single pointer lines, with `work`
funded by relocation (Phase 6); the CTO's two-skill form is the fallback if `work` cannot be funded byte-neutrally. Recorded as the S1 row below (class `taste`: the model followed the operator's stated direction against the CTO's two-skill form, so there is no operator override to ask about and no issue is filed; it renders under Model Dissents in the PR body) and
persisted to `knowledge-base/project/specs/feat-one-shot-closing-prose-technical-fork-gate/decision-challenges.md`.

## Technical Approach

### The cue regexes, run against the fixtures (planner check; the CTO flagged these as unrun)

All lowercased, linear (bounded `{0,60}` gaps), applied to ONE `?`-terminated sentence:

```text
CL1 sufficiency  \b(is|are) [^?]{0,60}\b(evidence|census|inventory|coverage|audit|baseline|gate|proof)\b[^?]{0,60}\b(enough|sufficient|adequate)\b
                 vetoed by RULING_MONEY_RE, BUSINESS and CLOSING_EXTRA
CL2 design       \b(what|which)( is|'s| are| would be)? (the )?(right|best|correct|proper|cleanest) (design|architecture|mechanism|approach) (for|to|of|when)\b
                 \bdo you want (a|an|the) ([a-z -]{0,20} )?(migration|rotation|storage|credential|schema|pipeline|rollout|cutover)[a-z -]{0,20}(design|architecture)\b
                 vetoed by BUSINESS and CLOSING_EXTRA ("way" is deliberately not a cue; the first pattern needs an object so a bare
                 "what is the best approach?" passes; the second needs a technical noun so "do you want a dark design?" passes)
CL3 ordering     \b(in what|what|which) (order|sequence)\b  AND  \b(credentials?|tokens?|secrets?|keys?|configs?|configuration|storage|migrations?|cutover|pipelines?|schema|hosts?|rotat[a-z]*)\b
                 vetoed by BUSINESS and CLOSING_EXTRA
BUSINESS veto    prices?|pricing|plans?|tiers?|launch(es)?|dates?|deadlines?|licen[sc]es?|vendors?|logos?|copy|landing|budgets?|costs?|spend|revenue|invoices?|refunds?|schedules?|priorit(y|ies)|brand|hero
ACTION veto      merge|deploy|ship|releases?|delete|prod|production      (existing cues keep BUSINESS|ACTION; CLOSING cues use BUSINESS only, plus CLOSING_EXTRA)
CLOSING_EXTRA    prioriti[sz]\w*|publish\w*|announce\w*|auditors?|accountants?|lawyers?|investors?|customers?|features?|roadmap|milestones?   (applies to EVERY cue, SHARED ones included, but only in the `shared+closing` group, so the pre-ask hook is untouched; a seed list the Phase 4 sample tunes; the one place a closing-only false positive is narrowed)
exemption        RULING_PERM_RE (unchanged): may i | is it fine to | ok(ay)? to | go-ahead | approve[ds]? | authori[sz]e | ack-destroy
```

Run on 2026-10-12 with `grep -E` over lowercased sentences (scratchpad probe, not committed):

| Sentence | Verdict |
|---|---|
| is the existing census enough to close the G2 issue, given a personal CLI token not listed and a branch-nameable write token on another config? | CL1 block |
| what is the right design for moving the three deploy-channel credentials out of branch-nameable storage? | CL2 block (the ACTION word `deploy` does not veto it) |
| should the two credentials be rotated now, and in what order? | CL3 block |
| do you want a migration design? (from the founder-observed "your calls" line) | CL2 block |
| Do you authorize rotating HCLOUD_TOKEN now? | pass (no cue) |
| which option do you want for the landing page headline? | pass (no cue; the BUSINESS veto's `landing` would also apply) |
| Is the evidence enough to start charging? | pass (money veto) |
| what is the best design for the pricing page? / Do you want a logo design for the landing page? | pass (BUSINESS veto) |
| May I rotate the keys in what order you prefer? | pass (permission shape; the exemption applies to every cue) |
| Should I merge PR 123 now? / Which should I do first, the P1 or the feature? | pass (no cue) |
| Do you want a design doc for the new importer? | pass after the CL2b narrowing (no technical noun); "do you want a migration design?" still blocks. CL2b stays the cue most likely to be dropped by the sample |
| do you want a dark design? / what is the best approach? / is the audit log sufficient for the SOC2 auditor? / is the baseline enough to publish the case study? / in what order should we prioritize the migrations? / in what order should we ship the features, config first? | pass (near-misses found in plan review: CL2b needs a technical noun, CL2a needs an object, CLOSING_EXTRA vetoes auditor, publish, prioritize and features) |

### Closing-hook contract (`pre-closing-technical-fork-gate.sh`)

Order of arms (each early exit is a bypass path, so the order is load-bearing, and every one fails OPEN):

1. SUT execution marker to stderr when `SOLEUR_HOOK_TRACE` is set (test-only; the suite counts executions from it).
2. `SOLEUR_ACK_TECHNICAL_FORK=1` disarms, announced on stdout as a `systemMessage` (same name as the pre-ask hook, so one variable disarms both). `GITHUB_ACTIONS=true` also exits 0 (headless CI has no operator to ask, and a block there only burns a turn; `claude-code-review.yml`, `scheduled-machinery-drain.yml` and `fix-constraints-stage-a.yml` load `.claude/settings.json`). `export LC_ALL=C` and a pinned `PATH` come first. The message is read with `jq -r '.last_assistant_message'` and nothing else: no jq `test`, `gsub` or `splits` on model text (the pre-ask file records a 13 s jq gsub).
3. `jq` missing, stdin empty, input not JSON, `stop_hook_active` key ABSENT (loop guard cannot be verified), `last_assistant_message` absent or not a string, or the lib failed to load (`tfc_self_check` fails after `source "$TFC_LIB"`: a missing file, an undefined `tfc_is_fork`, or an empty cue variable, because an empty regex matches everything): exit 0 with one stderr line naming the arm. Every check is silent on stdout (`declare -f ... >/dev/null 2>&1`: bare `declare -f` prints the function body and would corrupt the JSON), and an unterminated fenced block (the fence toggle ends set) is also parse doubt: exit 0 with a stderr line.
4. `stop_hook_active == true`: exit 0 (blocks at most once per turn; a second identical close passes).
5. Take the last 200000 bytes, strip fenced blocks FIRST (a cut that lands inside a fence flips the awk toggle and would drop the real closing, the residual `unkept-promise-hook.sh` documents), then strip inline code spans PER LINE (a stray lone backtick must not pair across lines and eat the question) and `>`-quoted lines, map NBSP, U+2009 and the zero-width characters (U+200B-U+200D) to a space or delete them before any matching, then cut to the last 1500 bytes under `LC_ALL=C` (a byte cut can split a UTF-8 character and make `grep` treat the text as binary), drop a leading fragment.
6. Escape scan (the three T4 forms, non-empty content only). Scope, decided in plan review (amendment (j)): `<stop>OPERATOR-GATE|BLOCKED: ...</stop>` anywhere in the window passes the whole closing (the brief's own fixture requires it); a final-sentence `Paused:`/`Blocked:` label passes the whole closing (it mirrors the plugin hook's escape); a sentence-initial `Operator-only (category): ...` governs ONLY its own sentence and the next `?` unit in the same paragraph, every other unit is judged normally. Match on the whole-window forms: exit 0.
7. Split into `?`-terminated units, where a `?` terminates only when followed by whitespace, end of text or closing punctuation (`)`, `]`, a quote, `*`, `_`, a backtick), so a URL query string is not a unit boundary, and the `?` stays IN the unit (the shared weak-cue extraction needs it); the window is lowercased and whitespace-normalised ONCE (not per unit); only the LAST 12 units are judged (a stderr note on truncation; 500 tiny `?` units through eight greps each measured 16.9 s, so the unit COUNT, not the byte length, is the scaling variable), each judged alone by `tfc_is_fork "$unit" shared+closing`; THIS CALLER skips a unit over 600 bytes with a stderr note (the cap is not in the lib, see Plan-review amendment (a)).
8. First hit: print ONE `jq -n --arg r ... --arg m ...` object `{"decision":"block","reason":...,"systemMessage":...}` and nothing else on stdout (a suite row asserts stdout parses as exactly one JSON object). `reason` and `systemMessage` are byte-constant: they never interpolate the unit, the cue name or any message text (echoing model text would re-inject it into the model's context and, via `systemMessage`, into the operator terminal). AFTER the JSON is printed, record the hit through ONE function `_tfc_record` (the only repo-local dependency, so graduation rewrites exactly it): `declare -f emit_incident >/dev/null 2>&1 && emit_incident pre-closing-technical-fork-gate deny "<cue name>" "<unit length and sha256 of the unit>" Stop >/dev/null 2>&1 || true` (signature `rule_id event prefix cmd hook_event kind`; the hook sources `lib/incidents.sh` itself because it does not source `hook-input.sh`; `umask 077`; `emit_incident` takes an indefinite `flock -x`, so it runs last and is registered with a `"timeout": 10`). The ledger row stores the cue name, the length and a hash, NOT the text: CL3's vocabulary (credentials, tokens, keys) makes the units secret-adjacent, and the row only has to let a later reader find the unit in a local transcript by hash. No hit: exit 0.

It does NOT source `lib/hook-input.sh` (that helper is PreToolUse-shaped and `hook-input-contract.test.sh` A18 would then require it to be listed in `INSCOPE21`); a Stop hook cannot ask, so ADR-157's ask-on-parse-failure does not apply and the fail-open arms above are the contract.
No `eval` (the contract suite bans it under `.claude/hooks`). Linear throughout (`awk`/`tr`/`sed`, no nested quantifiers). bash 3.2-compatible syntax; GNU `grep -E` with `\b` is the supported target, exactly as in the pre-ask hook (a Linux dev-host surface, not a macOS one). A `mktemp` is not needed in the hook.

### What the lib moves (byte-identical) and what stays

Moves to `lib/technical-fork-cues.sh` (SHARED): `RULING_STRICT_RE`, `RULING_EVID_NOUN_RE`, `RULING_BAR_RE`, `RULING_SUFF_RE`, `RULING_STATUS_RE`, `RULING_ADR_RE`,
`RULING_AB_RE`, `RULING_TECH_RE`, `RULING_PERM_RE`, `RULING_MONEY_RE`, `RULING_OPVOCAB_RE` (now the concatenation BUSINESS|ACTION, byte-equal to today's literal, which the suite pins as a literal), and the weak-cue
interrogative extraction. Stays in the pre-ask hook: `AUTHZ_VERB_RE` and `AUTHORITY_RE` together (only the expert arm uses the first, and the V3 pair compares them in one file; plan review moved `AUTHZ_VERB_RE` back out of the CTO's SHARED list), `EXTERNAL_EXPERT_RE` and the expert arm, `INVESTIGATIVE_RE`, the corpus assembly, the deny envelopes. The pre-ask loop body becomes a
call to the predicate; `TFC_HIT` is read only for the incident row (the suite's `RULING_HIT_NAMES` is its own bookkeeping built from the deny reason, not from a hook variable). Both hooks source the lib FAIL-OPEN: a missing or empty lib exits 0 with a stderr line (in the pre-ask hook it would otherwise leave every cue regex empty, which matches everything and denies every question); the suites carry a missing-lib row for each hook.
The lib is side-effect-free at source time, guarded against double-source with a `${_TFC_LOADED:-}` guard that is safe under `set -u`, uses `local` for every function variable, ships no `set` changes, and never sources `incidents.sh`, calls `emit_incident` or names `.claude/` or `CLAUDE_PROJECT_DIR` (a suite row greps its non-comment lines for those, which also keeps it out of the incident-sandbox census's hop-1 population). `tfc_is_fork` must run in the current shell, never inside `$(...)`, or `TFC_HIT` is lost. The cue regexes carry no repo-specific nouns (a row greps for `soleur`, `hcloud`, `G2`), so graduation to a third-party surface is a move, not a rewrite. Suites read regex VALUES by sourcing the lib in a subshell, never by `sed` over its source text.

## Implementation Phases

Phase order follows `cq-write-failing-tests-before`: tests and the Guard Contract matrices come first.

### Phase 0 — Baselines and funding (no product code)

1. Run, record and keep the numbers: `bash .claude/hooks/pre-ask-technical-fork-gate.test.sh` (140 pass), `bash .claude/hooks/devin-matcher-parity.test.sh`,
   `bash .claude/hooks/settings-hook-exec-bit.test.sh`, `bash .claude/hooks/hook-input-contract.test.sh`, `bash scripts/guard-vacuity-floor.test.sh` (note `n_fires`), `bash plugins/soleur/test/unkept-promise-hook.test.sh`.
2. Re-measure skill headroom against the merge-base: `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"`; record `wc -c` for `one-shot`, `plan`, `work` `SKILL.md`.
3. **Fund the `work` pointer (headroom 0):** the pointer needs about 250 bytes. Relocate, verbatim, the explanatory "no-marker branch" tail of `work/SKILL.md` step 3.5
   (the `SOLEUR_COMPACTION_DIRECTIVE` rationale) into a reference file under `plugins/soleur/skills/work/references/` with a markdown link left behind. Only that tail may move: `plugins/soleur/test/compaction-state-hook.test.sh` scenarios 25c and 25d require `work/SKILL.md` to keep the `SOLEUR_COMPACTION_DIRECTIVE` marker literal, `recommend=true` and the "no marker means no `/clear` recommendation" clause, so those stay and the two scenarios are part of this phase's gate. First
   `grep -rn "SOLEUR_COMPACTION_DIRECTIVE\|no-marker" plugins/soleur/test` to see every other test that reads that text; diff the moved text clause by clause (the
   2026-09-23 learning: compression dropped conditions). Net bytes of `work/SKILL.md` must be <= 0 after the pointer is added. Time-box the search to one bounded pass (the first candidate that relocates
   clause-for-clause with no asserted token); if none qualifies, take the fallback: drop the `work` pointer only (the CTO's form; `plan` has headroom and keeps its line) and say so in the PR body. A cheaper-looking
   variant (a clause appended to the existing line-286 sentence) still needs the same funding, so it is not a shortcut.
4. Draft the sample extractor in the scratchpad (not the repo): the newest 300 assistant closings with a `?` in the stripped window from `~/.claude/projects/-data-git-repositories-jikig-ai-soleur/*.jsonl`
   (read-only, counts only). Specification: each record with `type == "assistant"` carries `.message.content[]`; the closing text of a turn is the LAST `type == "text"` block of the
   assistant records between two user records; turns whose last block is `tool_use` are excluded; the extractor feeds `{stop_hook_active:false, last_assistant_message:<text>}` to the real hook. Confirm the shape with one file
   before relying on it. The exact recipe (path, jq filter, selection rule) is carried in the compound learning, because the extractor itself is not committed and the cue loop must be reproducible by the next session.
5. **Unmeasured claims to probe, or to record as unmeasured:** how the runtime surfaces TWO simultaneous Stop blocks (the plugin's `unkept-promise-hook.sh` plus this hook, and the ralph loop's `stop-hook.sh` which blocks every Stop and never reads `stop_hook_active`), and a Stop payload whose `last_assistant_message` is non-text. A scratch ralph state file plus a fake payload drives the first without a live session.
6. **Dry run for reacting suites.** Create an empty `.claude/hooks/lib/technical-fork-cues.sh` and an empty executable `.claude/hooks/pre-closing-technical-fork-gate.sh` in a scratch copy and run `grep-q-pipe-guard.test.sh`, `settings-hook-exec-bit.test.sh`,
   `hook-input-contract.test.sh`, `scripts/lint-orphan-test-suites.sh` and the shellcheck sweep, to enumerate which census reacts to a new hook or lib before any real code exists.

### Phase 1 — Failing tests first

1. Write `.claude/hooks/pre-closing-technical-fork-gate.test.sh` (shape of the pre-ask suite, plus the plugin suite's SUT execution marker): fixtures, mutation rows, non-vacuity, floor (see Test Scenarios and the Guard Contract). It sources `lib/test-incident-sandbox.sh` FIRST (the closing hook is a new `emit_incident` caller, so the suite is hop 2 of `incident-sandbox-coverage`); EVERY spawn, the mutant-tree runs and the `jq`-absent row included, inherits `INCIDENTS_REPO_ROOT` (an `env -i` spawn would point the hook at the real ledger); a mutant tree copies `lib/incidents.sh` and `lib/log-rotation.sh` beside the hook and lib; a missing `jq` follows `hook-suite-dep-unresolved` (`UNRESOLVED: jq missing`, exit 3), never an in-suite skip. It fails (hook absent).
2. Extend the pre-ask suite: lib-sourcing assertions, non-regression rows, the `RULING_PERM_RE` read (V4, line 842 today) repointed to read the VALUE by sourcing the lib in a subshell, never by `sed` over source text and never by line number (a `sed` over source breaks for `RULING_OPVOCAB_RE`, now a BUSINESS|ACTION concatenation); the `AUTHZ_VERB_RE`, `AUTHORITY_RE` and `EXTERNAL_EXPERT_RE` reads (lines 343 and 395-396) stay as they are because those variables stay in the hook; plus a byte-equality row for `RULING_OPVOCAB_RE`, a missing-lib row, V1 inventory literal and `MIN_CASES` raised together.

### Phase 2 — The lib and the pre-ask refactor

1. Create `.claude/hooks/lib/technical-fork-cues.sh` (SHARED moved byte-identical; CLOSING added; `tfc_is_fork`).
2. Refactor the pre-ask hook to source it and call the verdict function. Gate: all 140 existing cases and V1-V5 pass UNCHANGED apart from the repointed reads, including the 30-60 KB deny rows T1-T4 (the proof that no cap leaked into the lib); a flipped case reverts the refactor (CTO T2). Time the worst SHARED regex on a 1500-byte unit; the closing hook's bound rests on it.
3. `shellcheck` both files; no `eval`.

### Phase 3 — The closing hook and its registration

1. Create `.claude/hooks/pre-closing-technical-fork-gate.sh` per the contract above; `git update-index --chmod=+x` (settings.json invokes the bare path).
2. Register under `Stop` in `.claude/settings.json` (new event key; no matcher, like the plugin's Stop entries) with `"timeout": 10`: `"$CLAUDE_PROJECT_DIR"/.claude/hooks/pre-closing-technical-fork-gate.sh`. No `.devin/config.json` Stop entry (Devin loads settings.json, so a second one would double-fire).
3. Add the ledger row to `.claude/hooks/devin-dispositions.tsv`: `claude-settings	.claude/hooks/pre-closing-technical-fork-gate.sh	Stop	(none)	already-fires	dispatch measured (EC§3); blocking under Devin UNMEASURED - Stop payload fields not captured, hook fails open when absent	EC§3` under a new `# --- .claude/settings.json - Stop ---` section header (the disposition set is closed, ADR-223 Decision 5, so `already-fires` stays; seven TAB-separated fields). Codex gets no Stop binding and needs no row: its registry is not enumerated by the parity suite, so the omission is deliberate. Run the parity suite.
4. Turn the Phase 1 suite green.
5. Run the declared `discoverability_test` command once now that the registration exists and record its literal output in the PR body (expected `1`).

### Phase 4 — False-positive sample (CTO T5)

Run the Phase 0 extractor over the sample through the real hook. Record in the PR body ONLY: sample size, hit count, per-hit class (technical, operator-class, ambiguous) and the cue name, plus the over-broad percentage. Zero operator-class or
ambiguous hits is the bar; above 15% blocked, cut cues. Each false positive: narrow, add a synthesized fixture, re-run the entire sample; two failed rounds on a cue drop it (CL2b is the first candidate; a dropped cue's must-block rows become pinned KNOWN-MISS must-PASS rows labelled with the cue and date, so the case count never decreases and no floor is lowered: lowering a floor is the weakening the ratchet exists to stop). No transcript text is
copied anywhere in the repo or the PR. Classification: the implementing agent reads each hit and classes it; when unsure it records `ambiguous`, which fails the bar. Also record (counts only) the sentences the BUSINESS veto
silenced that a reader would have blocked (the veto's measured cost, a recorded residual) and a recall estimate: of the sample's technical-fork-bearing closings, how many the hook blocks.

### Phase 5 — Registries and ratchets

1. `scripts/guard-vacuity-floor.test.sh`: append the new suite to the effective (last) `PROMOTED_FILES` assignment with a comment block in the sibling style, and raise `MIN_FIRING_SUITES` by 1 with a dated note (record the measured `n_fires` before and after). Do NOT touch `MAX_DEFERRED`. `MIN_FIRING_SUITES` is a one-line hand ratchet that most commits to that file touch, so a concurrent promotion conflicts textually here: on a rebase, re-measure `n_fires` and re-derive the number, never resolve by taking the larger one.
2. `python3 scripts/regenerate-shard-manifest.py --incremental --write` for `scripts/suite-shard-legs.tsv` / `scripts/suite-durations.tsv`; check `scripts/lib/test-affected-paths.sh` derives the new suite's edge to the hook, the lib and `.claude/settings.json` (add a declared edge only if derivation misses it).
3. Verify the floor shape the sweep recognises: `(( TOTAL < MIN_CASES ))` with the literal adjacent, reported by `printf` + `exit 1` (copy the pre-ask suite's tail).

### Phase 6 — Skill carriers (pointer lines only)

Each line links `technical-ruling-delegation.md` and names the closing message / "Decision for you:" list as the carrier:

| File | Point | Bytes |
|---|---|---|
| `plugins/soleur/skills/one-shot/SKILL.md` | a blockquote line at step 8 saying the final summary is a closing message too (signage: inside the ralph loop the hook judges only the first Stop, so this is NOT hook-backed) | 1640 headroom |
| `plugins/soleur/commands/go.md` | extend the EXISTING Sharp Edge sentence at line 629 ("never a technical question in a closing message") with a clause naming "Decision for you:" / "Your calls" lists, instead of adding a line: line 625 is an intent-routing `AskUserQuestion`, not a technical-fork surface, and a new line would repeat line 629 | no ceiling row |
| `plugins/soleur/skills/work/SKILL.md` | end of step 3.5 (end-of-work closing; says it applies to direct `work` runs, since under one-shot work returns a `## Work Phase Complete` marker) | 0 headroom: funded by Phase 0.3, sequenced LAST so a blocked relocation cannot hold up the PR |
| `plugins/soleur/skills/plan/SKILL.md` | on the summary and handoff text of `## Post-Generation Options`, not on the option list (all six options are routing, so the carrier is the prose around them) | 1087 headroom |

Then `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"` must stay OK, and the `components.test.ts` wiring (every skill that names the CTO agent links the reference) must stay green.

### Phase 7 — Record

1. ADR-084 addendum dated 2026-10-12 (see Architecture Decision). 2. C4 Hook Engine description (and technology string) in `model.c4`, then regenerate `model.likec4.json` (lefthook or `scripts/regenerate-c4-model.sh`); run `plugins/soleur/test/c4-count-parity.test.sh`.
3. Compound learning under `knowledge-base/project/learnings/` (topic: the closing-prose carrier; the author picks the dated filename at write time; carrier lesson; a gate whose vocabulary is shared must grow, not just be shared; the founder's correction; measured fixture result).
4. `knowledge-base/project/specs/feat-one-shot-closing-prose-technical-fork-gate/decision-challenges.md` with the Decision Classes table (S1 plus the T rows). 5. File ONE follow-up issue ("add the closing hook to the rule's `[hook-enforced:]` tag", `domain/engineering`, `deferred-scope-out`,
`Mandated-By: wg-when-deferring-a-capability-create-a`; its body also carries the Devin Stop-payload capture and the ralph-loop dedupe design, so no second issue is filed and net-issue-flow stays at NET 0), and one self-contained comment on #10056: the T1 graduation criterion (30 days in service, 10 recorded firings counted by hook name from `.claude/.rule-incidents.jsonl` on the founder's machine by the session that runs the review, zero reported wrongful blocks, the sample re-run clean), the graduation checklist from the ADR addendum, and the channel for false-positive reports (a comment on #10056, which the 30-day review reads; no new label). An `ON A WRONGFUL BLOCK` checklist heads both the hook and the lib: find the closing in the local transcript by the ledger's unit hash; a CLOSING cue is narrowed in the lib (a tighter shape or `CLOSING_EXTRA`) with a must-PASS fixture in the closing suite and `MIN_CASES` plus the V1 literal raised together, touching no other file; a BUSINESS word is NEVER the fix (it changes the pinned `RULING_OPVOCAB_RE` literal and silences the pre-ask hook too); `guard-vacuity-floor` and the shard manifest need no change.

### Phase 8 — Pre-push ratchets and ship

Run every repo-global ratchet that references the changed files, from the worktree, targeted. The aggregate local net is `bash scripts/pre-push-ratchet-lane.sh` (`--print-members` lists it without running: trap-tempfile `--check-highwater`,
`lint-diagnosis-claims`, `fixture-relative-assert`, `fixture-dir-operand-assert`, `fixture-cd-containment`, `skill-body-budget`, `rule-bodies`, the kb-consumers member and others); it merges main into a scratch worktree, so it also catches a sibling's new test. Members the lane does NOT
carry are run by name: `bash scripts/guard-vacuity-floor.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `python3 scripts/lint-shell-capture-exit.py <each new or changed .sh>` and `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base "$(git merge-base HEAD origin/main)"` (both baseline-gated: a new file must add no finding), `bash .claude/hooks/incident-sandbox-coverage.test.sh`, `bash plugins/soleur/test/c4-model-freshness.test.sh`, `python3 scripts/lint-agents-enforcement-tags.py`,
`python3 scripts/lint-rule-ids.py` (no rule body is edited, so these are no-ops), `shellcheck` on every changed `.sh`, and the targeted suites for every file touched (the pre-ask suite, the closing suite, `devin-matcher-parity`, `settings-hook-exec-bit`, `hook-input-contract`, `hookeventname-coverage`, `unkept-promise-hook.test.sh` as a neighbour). The new suite adds a `mktemp -d`, so the lane's `lint-trap-tempfile-ownership --check-highwater` member is mandatory, not optional.

If a repo-global ratchet moves, measure `origin/main` first in a detached worktree before attributing it (the 2026-09-23 learning: a base-side
count is a two-minute check). Also run `bash scripts/lint-orphan-test-suites.sh` once the new suite is tracked (the census proves it is registered, not just
that a glob should reach it), `bash scripts/markdown-lint.sh` on the new learning, the ADR addendum and every touched `.md` (plans and specs are excluded by `.markdownlintignore`; the script reports that rather than failing), and the Rollback simulation below. Run `soleur:ship` step 5.5 (`archive-kb.sh`) BEFORE arming auto-merge. Standing constraints apply: no workflow dispatch, no `--admin`, no push to an armed queued PR.

## Files to Create

- `.claude/hooks/lib/technical-fork-cues.sh` — shared cue lib and verdict function.
- `.claude/hooks/pre-closing-technical-fork-gate.sh` — the Stop hook (mode 100755).
- `.claude/hooks/pre-closing-technical-fork-gate.test.sh` — the suite.
- `plugins/soleur/skills/work/references/<name>.md` — only if Phase 0.3 relocates the step-3.5 tail (name chosen then).
- one compound learning under `knowledge-base/project/learnings/` (filename chosen at write time).
- `knowledge-base/project/specs/feat-one-shot-closing-prose-technical-fork-gate/{tasks.md,decision-challenges.md}`.

## Files to Edit

- `.claude/hooks/pre-ask-technical-fork-gate.sh` — source the lib, call the verdict function.
- `.claude/hooks/pre-ask-technical-fork-gate.test.sh` — repoint reads, add lib/non-regression rows, raise the V1 literal and `MIN_CASES`.
- `.claude/settings.json` — new `Stop` registration.
- `.claude/hooks/devin-dispositions.tsv` — one ledger row.
- `scripts/guard-vacuity-floor.test.sh` — `PROMOTED_FILES` and `MIN_FIRING_SUITES`.
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` — regenerated (and `scripts/lib/test-affected-paths.sh` only if derivation misses).
- `plugins/soleur/skills/one-shot/SKILL.md`, `plugins/soleur/commands/go.md`, `plugins/soleur/skills/work/SKILL.md`, `plugins/soleur/skills/plan/SKILL.md` — one pointer line each.
- `knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md` — addendum.
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `model.likec4.json` (generated).
- Not edited: `AGENTS.rules.md` (ADR-092), `.github/workflows/**`, `apps/web-platform/infra/*.tf`, `plugins/soleur/hooks/**`, `apps/web-platform/**`.

## Rollback

Revert the PR. The revert must stay green on its own gates, so the recipe is written from running it, not from the diff: in a scratch detached worktree, `git revert --no-commit` the change's commits, then run `scripts/guard-vacuity-floor.test.sh`
(the `PROMOTED_FILES` entry and the `MIN_FIRING_SUITES` bump revert together), `.claude/hooks/devin-matcher-parity.test.sh` (the ledger row reverts with the registration), `scripts/lint-skill-body-budget.py --base <merge-base>` and the shard-manifest consistency check. Phase 8 records the outcome in the PR body.
The runtime kill switch needs no revert: `SOLEUR_ACK_TECHNICAL_FORK=1` disarms both the pre-ask and the closing hook for a session, announced, never silent.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Plugin placement now (`plugins/soleur/hooks` + `hooks.json`) | Runs in web unless opted out (needs `AGENT_ENV_OVERRIDES` + the web-parity test, an `apps/web-platform` change); third-party vocabularies raise the false-positive risk before any in-repo record exists; graduation criterion recorded under #10056 (CTO T1) |
| Exact-label arm in the plugin hook (#10057 as written) | Brittle, no producer once the ship gate removed the label (CTO R3); superseded |
| One cue list with no groups, so pre-ask also gains the new cues | Widens the AskUserQuestion deny surface and the refactor's regression risk; groups keep pre-ask behaviour byte-identical (CTO T2) |
| Flat veto including ACTION words for the new cues | Silences question (b) (`deploy-channel`); measured |
| Judge "Decision for you:" lists with no `?` | Over-block risk, repeats the unkept-promise record; revisit only on measured misses (T3, T8) |
| Co-signal (weak) design cues | The sentence is already interrogative; extra co-signals only reduce recall (CTO) |
| Whole-closing exemption by any permission ask | Lets an appended "Approve?" hide a ruling in the same message; per-sentence judging avoids it |
| Honour only the `<stop>` escape | Gives the model no plain way to classify a fork as operator-only (T4) |

## Deferral Tracking

- **Plugin port of both gates** is tracked as **#10056** (existing, open); this PR adds a comment with the T1 graduation criterion. No new deferral issue.
- **Recall decay** (a missed phrasing) is handled by the miss, cue, fixture loop in the compound learning, not an issue.
- One new issue is FILED by this PR: the rule's `[hook-enforced:]` tag (ADR-092 human-gated body). Net-issue-flow: this PR `Closes #10057` (1) and files 1, so NET = 0 and the gate passes without an override; verify with `bash plugins/soleur/skills/ship/scripts/net-issue-flow.sh <PR>` before `gh pr ready`. `SOLEUR_ACK_AUTOCLOSE` is not used; the close of #10057 is intended and stated in the PR body (`Closes #10057`).
- The 30-day graduation review is recorded as a comment on #10056, not as a time-gated close criterion of this PR (nothing here closes on a duration), so no follow-through enrollment applies.

## Open Code-Review Overlap

- #4133 (`plan/SKILL.md`, schema parity test for the Observability block): **Acknowledge** — different concern (a parity test), this PR adds one pointer line.
- #9705 (`model.c4`, dead-probe heartbeat for an inngest alert): **Acknowledge** — unrelated element; this PR edits only the Hook Engine description.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled at plan time, see "Ruled by CTO agent, 2026-10-12" above. No product/UX surface (no page or component file, so the mechanical UI-surface override does not fire),
no marketing copy, no money or vendor change, no data movement. Legal posture: the hook reads the operator's own local assistant text and moves nothing off the machine; CLO not needed.
GDPR gate: no regulated-data surface (the false-positive sample reads local transcripts on the operator's own machine, counts only, nothing committed or sent to an API).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-084** (Accepted) with an addendum dated 2026-10-12, not a new ADR: it records the reversal of the one rejected alternative that mattered here. New text: the carrier of a technical fork can be the closing
chat message; a cue-based (not label-based) Stop hook, REPO-LOCAL, reads it; the cue vocabulary lives in one lib shared with the pre-ask hook; the hook blocks at most once per turn and fails open; graduation to the plugin follows #10056's criterion; the hook is one forced reconsideration per turn, not a guarantee (a repeat after the block passes); a cue-growth tripwire is recorded (more than 6 CLOSING cue patterns, or 3 founder-reported misses in 30 days, means revisit judging lists with no `?` or stop adding cues); the earlier rejection
(13-of-15 over-block) remains true of a LABEL arm and is superseded for a cue arm because every cue sits on a `?` sentence behind a business veto and a permission exemption and the sample bar is zero operator-class hits.
Alternatives Considered gains the T-row rejections above. This is a deliverable of this plan (`wg-architecture-decision-is-a-plan-deliverable`), authored in Phase 7 describing the target state.
The per-harness ledger row (ADR-223) is the registry record; no ADR-223 amendment is needed (its disposition set is closed, so the Devin caveat lives in the row's reason text). The addendum also carries: a bracketed forward pointer on the 2026-10-11 addendum's "not built" ruling and its Alternatives (2) (ADR-156's dated `[Correction ...]` bracket is the precedent), so the old text no longer reads as binding; a Decision 6 note that the "one-shot inherits, not edited" supersession now also covers a signage-only pointer line; the telemetry note that the hook's bare `rule_id` is hook telemetry under ADR-205, so the 30-day review counts ledger rows by hook name; citations of ADR-157 "What this supersedes" (absorbing a failure is correct for Stop hooks) for the fail-open prologue, ADR-156 for the type-asserted model-controlled input and the absence of `eval`, ADR-178 for the repo-reaches-into-plugin direction and ADR-245 for "move, never hand-copy"; the ralph-loop residual (the hook is mostly inert inside a loop); the shared `Paused:`/`Blocked:` label coupling with `unkept-promise-hook.sh`; and a GRADUATION CHECKLIST: (1) move the lib to `plugins/soleur/hooks/lib/` and have BOTH hooks reach into it (a move, never a copy: `hook-tool-kind.sh` and `log-rotation.sh` already exist as twin copies held together by parity tests), changing one `TFC_LIB` line per consumer; (2) rewrite only `_tfc_record` for the plugin form (no repo-local ledger); (3) delete the repo-local `settings.json` Stop entry and move the ledger row from `claude-settings` to `soleur-plugin` in the same PR (parity T8 keys on event plus path, so a leftover entry and a new plugin entry would both dispatch unflagged); (4) add `SOLEUR_DISABLE_*` to `AGENT_ENV_OVERRIDES` in `apps/web-platform/server/agent-env.ts` and satisfy `plugin-stop-hooks-web-parity.test.ts`; (5) decide `stop_hook_active` absent as fail-open (this hook) versus `// false` (the plugin hook) for Devin and Codex users; (6) decide whether the plain `Operator-only` and `Paused:` vocabulary survives; (7) confirm the cue regexes carry no repo-specific nouns.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Checked: (a) external human actors: the founder (already modelled); no new one. (b) external systems/vendors: none (no network call). (c) containers/data stores: the **Hook Engine** container
(`platform.engine.hooks`) is the one touched. Its `technology` line ("PreToolUse Guards + Rewriter + PostToolUse hints + SessionStart/PreCompact ...") and its description (which states the input is a tool-call envelope and that unparseable input ASKS, ADR-157) are made incomplete
by a Stop arm that reads model-generated closing text and FAILS OPEN; the `claude -> hooks` edge states "input that cannot be fully parsed asks, never continues silently", which does not hold for a Stop event. In-scope plan task, exactly three strings in `model.c4`: (1) append ` + repo-local Stop closing-prose gate (fail-open, once per turn)` to the Hook Engine `technology`; (2) insert one sentence after the ADR-156 clause of the Hook Engine `description` (the word "asks" lives only on the edge, not in the description): the repo-local Stop arm consumes `last_assistant_message`, equally model-controlled and type-asserted, fails open on any parse doubt (ADR-157 supersession note), blocks at most once per turn, shares `lib/technical-fork-cues.sh` with the pre-ask gate and never runs in web (`settingSources:[]`); (3) append to the `claude -> hooks` edge, after "(ADR-157)", `; a Stop event carries the closing message instead and fails open, bounded to one block per turn`. Optionally one bullet in the hand-authored `c4-model.md` Containers list. Regenerate `model.likec4.json` (lefthook's `c4-model-regenerate`) and run `plugins/soleur/test/c4-model-freshness.test.sh` as the `--no-verify` backstop. (d) actor-to-surface access relationships: unchanged.
Derived cardinalities: no skill, agent or workflow is added, so `plugins/soleur/test/c4-count-parity.test.sh` must stay green (run in Phase 7). No `views.c4` change (no new element).

### Sequencing

Nothing here is gated on a later slice; the ADR addendum describes the shipped state, no `adopting` marker.

## User-Brand Impact

**If this lands broken, the user experiences:** the founder is still asked a technical question in a closing message (a miss), or a closing message that carries a legitimate operator question is stopped once and must be re-sent (a wrongful block, costing one extra model turn; never a lost authorization, because an authorization-shaped sentence passes and a second close always passes).
**If this leaks, the user's data / workflow / money is exposed via:** no data path. The hook reads text already in the session and writes an incident row to the local ledger; the false-positive sample reads local transcripts and publishes counts only.
**Brand-survival threshold:** aggregate pattern.
**Threshold decision (challengeable):** aggregate pattern, not single-user incident: no outcome of this change exposes one user's data or money; a wrongful block is a one-turn friction and a miss is the status quo. Not `none`, because repeated wrongful blocks would erode trust in every hook in this repo.

## Observability

Scope: one repo-local executable (`pre-closing-technical-fork-gate.sh`) on the operator's machine (layer 7, no server surface). The signal is the process's own stdout decision plus an incident ledger row via `lib/incidents.sh` (`emit_incident`).

```yaml
liveness_signal:
  what: "an incident ledger row (hook=pre-closing-technical-fork-gate, kind=deny) per block, and the {decision:block} line on the hook's stdout"
  cadence: "per Stop event that carries a technical fork; zero rows over a window is also information for the T1 graduation review"
  alert_target: "the incident ledger read at the 30-day review recorded on #10056, and the founder in-session via the block reason"
  configured_in: ".claude/settings.json (Stop registration) and .claude/hooks/pre-closing-technical-fork-gate.sh"
error_reporting:
  destination: "stderr of the hook (execution marker, oversize-unit note, announced disarm) and the incident ledger"
  fail_loud: "every fail-open arm prints one stderr line naming the arm (jq missing, bad JSON, absent loop guard, non-string message); a silent pass is never the only evidence"
failure_modes:
  - mode: "a technical fork phrased outside the cue vocabulary passes (recall decay)"
    detection: "the founder reports it; the miss, cue, fixture loop adds a cue only after the sample re-runs clean"
    alert_route: "founder report -> compound learning plus a fixture"
  - mode: "a legitimate operator question is blocked (false positive)"
    detection: "the Phase 4 sample (zero operator-class hits is the bar) and the founder report; the escape forms release it, a second close always passes"
    alert_route: "founder report triggers immediate narrowing or removal of the cue (T7)"
  - mode: "a closing with hundreds of `?` units stalls the turn end"
    detection: "suite rows U3 (700 units under 3 s) and the judged-unit cap; the registration carries a 10 s timeout"
    alert_route: "CI red on the suite"
  - mode: "the hook is deleted from settings.json or loses its exec bit"
    detection: "the new suite's registration row, settings-hook-exec-bit.test.sh and devin-matcher-parity.test.sh redden in CI"
    alert_route: "CI red on the PR that removes it"
logs:
  where: "the incident ledger under the repo's incidents path (lib/incidents.sh) and the session transcript"
  retention: "the ledger's rotation policy (lib/log-rotation.sh)"
discoverability_test:
  command: "grep -c pre-closing-technical-fork-gate .claude/settings.json"
  expected_output: "1"
```

The probe is deliberately the static registration count: preflight Check 10 rejects any command containing a pipe, `;`, `&`, `<`, `>`, `$` or a backtick, so a piped
behavioural probe (payload into the hook, decision out) cannot be the declared command, and the behavioural proof is the new suite (too slow for the 15 s cap). The
suite's own P1 row asserts the same registration plus the ledger row, and its dispatch row asserts the hook ran. Run the command once after Phase 3 and record the literal output (the Phase 3 step does).

## Guard Contract

Two guards ship. Matrices are derived from the design and written BEFORE the guards (Phase 1 builds the suite first).

### Guard 1 — The closing-prose Stop hook (`pre-closing-technical-fork-gate.sh`)

**Property.** No closing message whose closing window contains a `?`-terminated sentence that asks the operator to choose on a technical fork (CL1-CL3 or a SHARED ruling cue, outside the business veto and the permission exemption) ends a turn unescaped, while a request to authorize a production act, an operator-class question, a message with no question and any input the hook cannot fully parse always pass, and the hook never blocks twice in one stop-chain.

**Assembly.** The population is every `?`-terminated unit in the closing window, and "closing window" is assembled by ONE function chain: 200 KB tail -> fence strip -> span/quote strip and Unicode-space normalisation -> 1500 B window -> fragment drop -> unit split (last 12) -> verdict. Chokepoints the property must flow through: (a) the verdict function `tfc_is_fork` (the only place a cue, a veto or the exemption is evaluated); (b) the unit loop (judges EVERY unit, not the first); (c) the fail-open prologue (all parse-doubt exits); (d) the registration (`Stop` in `.claude/settings.json`, ledger row, exec bit); (e) the reason string (one emitter). Members that drift: the cue list, the veto sets, the escape forms — all in the lib or the hook's constants, enumerated by the suite from the file, never from a remembered list.

**Mutation matrix** (each row MUST turn a named suite row RED; "landing" is asserted with `cmp` against the pristine copy, a mutant that exits abnormally is rejected and never counted as killed; mutants live beside a copy of the hook and lib in a suite-owned tmp tree because the hook sources `lib/` relative to itself):

| # | Mutation | Must redden |
|---|---|---|
| G1-1 | Empty the CLOSING group, or replace `tfc_is_fork` by `return 1` (the guard's OWN dispatch) | B1-B3 flip block to pass, AND the dispatch row reddens (each named must-block row must have been blocked with THIS hook's reason, and the `SOLEUR_HOOK_RAN` execution count must equal the run count) |
| G1-2 | Delete the permission exemption | Z1 ("may i rotate the keys, and in what order?": cue AND permission shape) flips pass to block; the canonical authorization row cannot witness this (it carries no cue) |
| G1-3 | Delete the `stop_hook_active` check | L1 (second identical close) flips pass to block |
| G1-4 | Judge only the first `?` unit (stops at the first member) | U1 (compliant authorization first, technical question second) flips block to pass |
| G1-5 | Veto CLOSING cues with BUSINESS\|ACTION instead of BUSINESS | B2 (`deploy-channel`) flips block to pass |
| G1-6 | Remove the BUSINESS veto from CLOSING cues | A7 ("what is the best design for the pricing page?") flips pass to block |
| G1-7 | Make a fail-open arm block (bad JSON, non-string message, absent loop guard, missing `jq`) | the matching F-row flips pass to block |
| G1-8 | Delete one escape form, or drop the empty-label exclusion | E1 / E2 / E3 (`Blocked: none.` must NOT escape) flip |
| G1-10 | Make `Operator-only (category):` escape the whole window instead of its own sentence and the next unit | E4 (B1 plus an unrelated `Operator-only (money): ...` sentence elsewhere must still block) flips block to pass |
| G1-11 | Remove the judged-unit cap (judge every unit) | U3 (700 tiny `a? ` units) exceeds its time bound |
| G1-9 | Remove the code-span / quoted-line strip | X2 (a fixture question inside backticks, and inside a `>` quote) flips pass to block |

Rows that need no mutant because a direct row already pins them: the window (W1), the unit cap (O1, in the caller), the reason text (R1-R4) and the registration (P1, plus `devin-matcher-parity`).

**Harness rows.** H1: neuter the suite's own `verdict` helper to always print BLOCK; the must-PASS rows (authorization variants that are NOT the canonical: "May I merge PR 123?", "Approve the rotation order?", "Do you authorize ... in what order?") redden, which a RED-only matrix cannot show. H3: a positive control drives the helper through one real pass and one real fail before any row (the pre-ask suite's V2 shape). The neutered-counter / floor mutant is NOT hand-rolled: `scripts/guard-vacuity-floor.test.sh` builds it for any suite whose floor has the recognised shape (`(( TOTAL < MIN_CASES ))`, literal adjacent, `printf` + `exit 1`), so the suite carries that shape and the accounting identity (`PASS + FAIL == TOTAL`).

**Anchor.** The stored values are `MIN_CASES`, the V1 inventory literal and the named must-block row set. What must also move for a weakening to pass: `scripts/guard-vacuity-floor.test.sh` (a separate file in `PROMOTED_FILES` with its own hand-ratcheted `MIN_FIRING_SUITES`, which re-derives that the floor exists, fires and is covered), and the named-row identity check (rows B1-B3 and the dispatch row must each have produced the block with this hook's reason), because a `>=` count survives any substitution that keeps the count.

### Guard 2 — The shared-vocabulary drift guard (inside the closing and pre-ask suites)

**Property.** There is exactly one definition site for each shared cue and for the verdict function, and both hooks route every cue judgement through that function.

**Assembly.** The population is every file under `.claude/hooks/` (and `lib/`) derived by `find`, not listed: the lib, the pre-ask hook, the closing hook, and any future hook that judges technical forks. Chokepoint: the `tfc_is_fork` symbol. The suite derives (a) the set of files that define a `RULING_*_RE` or `AUTHZ_VERB_RE` assignment (must be exactly the lib), (b) the set of files that call `tfc_is_fork` (must be exactly the two hooks), (c) that each hook's `source` line resolves.

**Mutation matrix** (same landing and abnormal-exit rules as Guard 1):

| # | Mutation | Must redden |
|---|---|---|
| G2-1 | Re-add a local `RULING_PERM_RE=` copy to the closing hook | the definition-site census (a) reports a second site |
| G2-2 | Lib ignores the `groups` argument (always `shared+closing`) | a pre-ask row that must NOT deny a CLOSING-only phrasing ("what is the right design for X?") reddens (pins T2: pre-ask is not widened) |
| G2-3 | Change `RULING_OPVOCAB_RE` in the lib (drop or add a member) | the byte-equality row (the lib's BUSINESS\|ACTION concatenation equals the pinned literal of today's `RULING_OPVOCAB_RE`) reddens, and V6 reddens for a dropped member |

The census is the other half of this guard and needs no mutant per instance: it DERIVES, with `git ls-files` over BOTH `.claude/hooks` and `plugins/soleur/hooks` (so the graduation PR does not have to rewrite the guard that protects it), the files that define a `^RULING_[A-Z_]*_RE=` cue and the files that call `tfc_is_fork`, and asserts exactly one definition site and at least two callers; a stale-exemption row asserts the derived population is non-empty (floor 2 callers), so a census over nothing cannot pass.

**Harness rows.** A must-PASS input that is not the canonical: a SHARED-only phrasing through the closing hook ("how strict should the evidence bar be?") still blocks, and the same phrasing through pre-ask still denies, so the census cannot be satisfied by a stub lib that defines nothing.

**Anchor.** The lib is one file reviewed in the same diff as its two consumers, so a single commit can weaken lib and rows together; the independent anchors are the 140 PRE-EXISTING pre-ask cases (unchanged rows, not edited by this PR except the repointed reads) and V1-V5, which were authored before this change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A Stop hook that blocks a CLOSING assistant message which asks the operator to choose on a TECHNICAL fork" [brief] | Phase 3, `pre-closing-technical-fork-gate.sh` | mapped |
| 2 | "factor the cues into ONE sourced lib so the two hooks cannot drift, never copy them" [brief] | Phase 2, `lib/technical-fork-cues.sh`, Guard 2 | mapped |
| 3 | "DECIDE in the plan (and have the CTO agent rule on it) whether the new gate belongs in .claude/hooks ... or plugins/soleur/hooks" [brief] | Ruled by CTO agent T1; Alternative Approaches | mapped |
| 4 | "Escape form: `<stop>OPERATOR-GATE: ...</stop>` / `<stop>BLOCKED: ...</stop>`" [brief] | Closing-hook contract arm 6, T4 | mapped |
| 5 | "Feedback text must say: spawn soleur:engineering:cto (legal: soleur:legal:clo), record 'Ruled by CTO agent', or classify the fork as operator-only" [brief] | T4 reason wording; test R1-R3 | mapped |
| 6 | "a request to AUTHORIZE a production write/rotation/merge/arm/flip ALWAYS passes; it fails OPEN on any parse doubt, blocks at most once per turn" [brief] | Closing-hook contract arms 3-4, exemption, Guard 1 | mapped |
| 7 | "Consult the CTO agent ... to set that budget and the cue list; the plan must record 'Ruled by CTO agent' for it, and must carry a `## Decision Classes` table" [brief] | Ruled by CTO agent section; Decision Classes | mapped |
| 8 | "Tests with both-direction fixtures drawn from real closing messages" [brief] | Phase 1, Test Scenarios | mapped |
| 9 | "Add mutation rows and an assertion floor, and register the suite the way the repo's other hook suites are registered" [brief] | Guard Contract, Phase 5 | mapped |
| 10 | "a short POINTER LINE, not prose, in one-shot (before the Step 8 closing), go, work and plan" [brief] | Phase 6 | mapped |
| 11 | "A compound learning for the carrier" [brief] | Phase 7.3 | mapped |
| 12 | "DO NOT edit the AGENTS.rules.md rule body ... file ONE follow-up issue" [brief] | Files to Edit (not edited); Deferral Tracking | mapped |
| 13 | "a PR must close at least as many issues as it files, so plan how to satisfy or override it" [brief] | Deferral Tracking (`Closes #10057`, NET 0) | mapped |
| 14 | "run every repo-global ratchet that references the files you change" [brief] | Phase 8 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Stop hook, lib, suite, registration, ledger row | asks 1, 2, 9 | asked |
| `tfc_is_fork` single verdict function | "factor the cues into ONE sourced lib so the two hooks cannot drift" | asked |
| CLOSING cue group and BUSINESS/ACTION veto split | "the three questions ... MUST block" (ask 8) | inferred — justification: measured (all five fixtures ALLOW under the existing cues; `deploy` vetoes question (b)), so the MUST-block requirement cannot be met by sharing alone |
| Three escape forms (the plain forms beyond `<stop>`) | "classify the fork as operator-only" (ask 5) | inferred — justification: the CTO ruled the model needs a plain way to classify, and the plugin learning retired raw markup; the `<stop>` form the brief names is also honoured |
| `stop_hook_active`-absent fail-open | "fails OPEN on any parse doubt" | asked |
| 600 B unit cap (in the closing hook's call site) | "fails OPEN on any parse doubt" | inferred — justification: linear-time safety on a model-controlled string (the pre-ask file records a 13 s regex on a 32 KB question); CTO T2, relocated out of the lib by plan review |
| Code-span and `>`-quote strip in the window | "the false-positive budget is deliberately tiny" | inferred — justification: sessions in this repo quote these phrases while editing the hook (the founder's sessions here routinely quote hook phrases); stripping only makes the hook block less |
| `CLOSING_EXTRA` veto, narrowed CL2a/CL2b, URL-safe unit boundary, missing-lib fail-open arm, fence-before-cut ordering | "a wrongly blocked closing message is the worse failure" | inferred — justification: each was measured by plan review against a concrete near-miss or failure (a dark-design question, a bare "best approach", a URL query string, an empty cue regex matching everything, a cut inside a fence dropping the closing); every one makes the hook block less |
| Escape scoping of `Operator-only`, the judged-unit cap, `GITHUB_ACTIONS` exit, byte-constant reason/systemMessage, hash-only ledger row, unterminated-fence arm, Unicode-space normalisation | "it fails OPEN on any parse doubt" and "a wrongly blocked closing message is the worse failure" | inferred — justification: deepen-plan security, spec-flow and architecture passes each measured a concrete hole (a whole-window self-label, 16.9 s of fork fan-out, echoing model text, secret-adjacent ledger text, an odd fence dropping the closing); each is a stricter-to-evade or cheaper-to-run rule, none widens the hook |
| Kill switch and re-send line in the `systemMessage` | "a wrongly blocked closing message is the worse failure" | inferred — justification: the pre-ask hook's kill switch is read from the process environment, so a developer who is wrongly blocked must be told it before the session, and the reason text deliberately teaches only the plain forms (CTO devex review) |
| False-positive sample (Phase 4) | "the false-positive budget is deliberately tiny" | asked |
| Promotion in `guard-vacuity-floor.test.sh`, shard manifest | "register the suite the way the repo's other hook suites are registered" | asked |
| Pointer lines (four skills) | "in one-shot (before the Step 8 closing), go, work and plan" | asked |
| `work` byte relocation | "keep each skill edit to a pointer line" | inferred — justification: `work` has 0 bytes of headroom and the ceiling is read from the merge-base, so a pointer cannot land without moving an equal number of bytes |
| ADR-084 addendum and C4 Hook Engine edit | "(ADR-084 ... find the carrier before strengthening the enforcer)" | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the addendum rejected a Stop arm and this PR reverses part of it |
| Close #10057, comment on #10056 | "plan how to satisfy or override it" | asked |

### Split Assessment

- Subsystems touched: 4 — `.claude/hooks`, `scripts` (ratchets), `plugins/soleur` (skill pointers), `knowledge-base`
- Planned files: about 22 | Estimated changed lines: about 900 (suite and hook dominate; the pre-ask diff is mostly a move)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The threshold is met on subsystem roots and lines, but the pieces cannot ship apart: the hook without the lib duplicates the cues, the lib without the hook is dead code, and the ratchet and ledger edits are what the registration needs to stay green.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** `.claude/hooks/pre-closing-technical-fork-gate.sh` exists, is committed `100755`, and `.claude/settings.json` registers it under `Stop`. Verify: `git ls-files -s .claude/hooks/pre-closing-technical-fork-gate.sh | cut -c1-6` prints `100755`; `jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(test("pre-closing-technical-fork-gate"))' .claude/settings.json` (no position assumption).
- [x] **AC2** The three must-block questions (CL1, CL2, CL3 sentences from the brief, verbatim) block, each with the hook's reason; "Do you authorize rotating HCLOUD_TOKEN now?", "which option do you want for the landing page headline?", a status report with no question and a closing carrying `<stop>OPERATOR-GATE: ...</stop>` pass. Verify: `bash .claude/hooks/pre-closing-technical-fork-gate.test.sh` exits 0.
- [x] **AC3** A request to authorize passes in every shape the suite lists (permission shapes with and without a cue), and the exemption row Z1 pins the cue-plus-permission case.
- [x] **AC4** Fail-open rows pass: empty stdin, invalid JSON, `jq` absent (PATH stripped), `stop_hook_active` key absent, `last_assistant_message` absent / non-string, oversize unit, `stop_hook_active: true`.
- [x] **AC5** The block reason names `soleur:engineering:cto` and `soleur:legal:clo`, "Ruled by CTO agent", the six operator-only category groups (eight tokens: money, scope, priority, schedule, irreversible, production-mutating, legal-risk, brand), the split remedy and `hr-technical-fork-is-not-an-operator-question`; its FIRST imperative is an Agent-tool call to `soleur:engineering:cto` (legal: `soleur:legal:clo`) with the evidence and "do NOT use AskUserQuestion", the escapes come after it and only "if the fork is genuinely operator-only", teaching `Operator-only (category): ...` before `Paused:`; it tells the model to state the CTO ruling (or the operator-only category) in one line and restate only the delta plus the authorization (the founder has already seen the first message); it contains no `<`, `>`, `promise`, `OPERATOR-GATE` or `DONE`; and it is byte-identical for two different closings.
- [x] **AC6** One definition site for the shared cues: `grep -lE '^RULING_[A-Z_]*_RE=' .claude/hooks/*.sh` prints nothing (`AUTHZ_VERB_RE` and `AUTHORITY_RE` legitimately stay in the pre-ask hook); the lib defines them; both hooks call `tfc_is_fork`. The pre-ask suite's pre-existing 140 cases and V1-V5 pass unchanged except the repointed reads and the V1 count and `MIN_CASES` literal.
- [x] **AC7** The suite carries the Guard 1 and Guard 2 mutation rows, H1-H3, a floor reported by `printf` + `exit 1`, and the accounting identity; `bash scripts/guard-vacuity-floor.test.sh` is green with the suite in `PROMOTED_FILES` and `MIN_FIRING_SUITES` raised by one; `MAX_DEFERRED` is unchanged.
- [x] **AC8** `bash .claude/hooks/devin-matcher-parity.test.sh`, `settings-hook-exec-bit.test.sh`, `hook-input-contract.test.sh` and `hookeventname-coverage.test.sh` are green with the ledger row present.
- [ ] **AC9** Phase 4 sample recorded in the PR body (size, hits, class per hit, percentage): zero operator-class or ambiguous hits, at most 15% blocked, no transcript text anywhere.
- [x] **AC10** One pointer line each in `one-shot` (before step 8), `go.md`, `work` (step 3.5) and `plan` (Post-Generation Options), each linking `technical-ruling-delegation.md` and naming the closing message as the carrier; `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base HEAD origin/main)"` is OK; `work/SKILL.md` is not larger than at the merge-base (or, on the Phase 0.3 fallback, carries no `work` pointer and the PR body says so).
- [x] **AC11** ADR-084 addendum, C4 Hook Engine edit (with `model.likec4.json` regenerated) and `c4-count-parity.test.sh` green; compound learning written (it carries the sample-extractor recipe and the cue-growth tripwire); the ADR addendum and the learning both state that the hook is ONE forced reconsideration per turn, not a guarantee (a repeat after the block passes); `decision-challenges.md` carries the Decision Classes table.
- [x] **AC12** `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh knowledge-base/project/plans/2026-10-12-feat-closing-prose-technical-fork-gate-plan.md` exits 0 (the plan's `## Decision Classes` table parses; every technical row carries `Ruled by CTO agent`).
- [ ] **AC13** PR body carries `Closes #10057`, names the ONE filed follow-up (the rule's `[hook-enforced:]` tag, rule body untouched per ADR-092) and the net-issue-flow arithmetic (NET 0); `git diff --quiet origin/main...HEAD -- AGENTS.rules.md` exits 0 (merge-base form, so a sibling merge cannot redden it).
- [ ] **AC14** All Phase 8 ratchets green locally before the first push; `shellcheck` clean; `soleur:ship` step 5.5 (`archive-kb.sh`) run BEFORE auto-merge is armed.

### Post-merge

- [ ] **AC15** Comment on #10056 recording the T1 graduation criterion; #10057 closed by the merge (verify `gh issue view 10057 --json state`).

## Test Scenarios

Fixtures live in the suite as synthesized strings; the three brief sentences are verbatim. Every must-block row puts the discriminating text in the FINAL sentence or the unit judged (2026-10-11 learning), and a courtesy closer is appended to a subset.

| Row | Closing message | Expect |
|---|---|---|
| B1 | "... is the existing census enough to close the G2 issue, given a personal CLI token not listed and a branch-nameable write token on another config?" (CL1) | block |
| B2 | "what is the right design for moving the three deploy-channel credentials out of branch-nameable storage?" (CL2) | block |
| B3 | "should the two credentials be rotated now, and in what order?" (CL3) | block |
| B4 | all three in one message with a "Your calls:" lead-in and a status paragraph above | block |
| B5 | B1-B3 each followed by "Let me know what you think." | block |
| B6 | "do you want a migration design?" | block |
| B7 | SHARED cue through the closing hook: "how strict should the evidence bar be?" | block |
| A1 | "Do you authorize rotating HCLOUD_TOKEN now?" | pass |
| A2 | "which option do you want for the landing page headline?" | pass |
| A3 | status report, no `?` | pass |
| A4 | B1 plus `<stop>OPERATOR-GATE: this is the accounting call (money).</stop>` | pass |
| A5 | "May I merge PR 123?" / "Approve the rotation order?" / "Do you want me to open the follow-up issue?" | pass |
| A6 | "Is the evidence enough to start charging?" (money veto) | pass |
| A7 | "what is the best design for the pricing page?" / "Do you want a logo design for the landing page?" | pass |
| A8 | "Which should I do first, the P1 or the feature?" | pass |
| Z1 | "may i rotate the keys, and in what order?" (cue and permission shape) | pass |
| U1 | "Do you authorize the rotation? Also, which design is best for the migration?" (second unit is technical) | block |
| L1 | B3 with `stop_hook_active: true` | pass |
| W1 | B1 above 2000 bytes of status prose | pass |
| O1 | an oversize (over 600 B) unit carrying a cue, through the closing hook | pass, stderr note |
| O2 | the same oversize question through the PRE-ASK hook (pre-ask rows T2-T4) | still deny (no cap in the lib) |
| E1-E3 | `<stop>BLOCKED: ...</stop>` / `Operator-only (money): ...` / final-sentence `Paused: waiting on CI`; and `Blocked: none.` must NOT escape | pass, pass, pass; block |
| F1-F6 | empty stdin / invalid JSON / absent loop guard / non-string message / `jq` absent / absent message | pass (fail open) |
| R1-R3 | reason names cto and clo, "Ruled by CTO agent", six categories, split remedy, rule id; no `<` or `>` | assert |
| U3 | 700 tiny `a? ` units in the window | pass in under 3 s (the judged-unit cap; the scaling variable is unit COUNT) |
| E4 | B1 plus an unrelated `Operator-only (money): ...` sentence elsewhere | block (that escape governs only its own sentence and the next unit) |
| E5 | an unterminated fence above the closing; a lone stray backtick; NBSP or a zero-width space inside "is the evidence enough" | fence: pass with a stderr line (parse doubt); backtick: the question still blocks (spans are stripped per line); NBSP or zero-width: still blocks (normalised first) |
| J1 | stdout of every block is exactly one JSON object; two different closings give a byte-identical `reason` and `systemMessage` | assert |
| G3 | `GITHUB_ACTIONS=true` with B1 | pass (no operator to ask) |
| R4 | `systemMessage` names `SOLEUR_ACK_TECHNICAL_FORK=1` and the plain escape form; no `<` or `>`; the reason tells the model to say in one line why it re-sent | assert |
| P1 | `Stop` registration present in `settings.json` and ledger row present | assert |
| X1 | fenced code block holding B1 above a clean closing | pass (fence stripped) |
| U2 | "is the census enough, see https://example.com/issues?id=3" followed by a clean closing; and a bold `**is the census enough?**` question | first: pass (a URL `?` is not a unit boundary, and there is no real question); second: block (the `?` is followed by closing punctuation) |
| M1 | the lib file is missing or empty, for the closing hook AND for the pre-ask hook | pass / allow, with a stderr line (fail open), never a blanket deny |
| N1 | the near-miss sentences of the narrowing table (dark design, bare best approach, SOC2 auditor, publish, prioritize, features/config) as must-PASS rows | pass |
| X2 | B1 inside inline backticks, and inside a `>` quoted line, above a clean closing | pass (meta sessions quote these phrases) |
| T1 | worst-case 1500 B unit through the closing hook, and the 60 KB closing | pass under a generous bound (10 s), and linearity asserted by comparing a 30 KB and a 60 KB closing, not a tight wall-clock |
| V8 | `RULING_OPVOCAB_RE` in the lib is byte-equal to the pinned literal of today's value; V6 per-member rows still green | assert |

Pre-ask non-regression rows added to its suite: the five CTO-measured questions still ALLOW through `AskUserQuestion` (pins T2: pre-ask is not widened); a lib-sourcing row; the repointed reads; the existing 30-60 KB deny rows T1-T4 unchanged.

## Risks and Sharp Edges

- **A wrongful block is the worse failure.** Mitigations are structural: once per turn, fail-open prologue, per-sentence judging, authorization exemption on every cue, BUSINESS veto, the zero-operator-class sample bar, and a repo-local blast radius. The founder-report trigger narrows or removes a cue immediately.
- **Meta sessions.** This repository writes about these hooks, so inline code spans and `>`-quoted lines are stripped from the window up front (a quoted fixture question is not a question put to the operator). The residual is the mirror image: a real technical fork wrapped in backticks passes. Accepted: the hook blocks less, the stricter direction.
- **The BUSINESS veto silences some technical forks.** `plan`, `copy`, `schedule`, `launch`, `cost` and `brand` are ordinary words here ("what is the best design for the plan phase gate?" passes). That is recall decay accepted under T8; Phase 4 counts the vetoed sentences a reader would have blocked so the cost is measured, not guessed.
- **Inside a ralph loop the hook is mostly inert.** `plugins/soleur/hooks/stop-hook.sh` blocks every Stop while a loop (one-shot) is active and never reads `stop_hook_active`, so after the first block every later Stop in the chain carries `stop_hook_active: true` and arm 4 exits. Mid-pipeline closing messages in a `soleur:one-shot` run are therefore not judged; the one-shot pointer line is signage, not hook-backed. Stated residual (hook header, ADR addendum, learning). If incidents show misses inside loops, the escalation is a `session_id` plus message-hash dedupe in place of `stop_hook_active` (the plugin hook deleted its counter for real defects, so that is a design to re-open, not a parameter).
- **Rhetorical self-answered questions** ("Did the evidence bar pass? Yes.") can trip a SHARED strong cue in a status line. Accepted as rare; the sample counts them.
- **The incident row stores text.** The ledger is local and gitignored (`.claude/.rule-incidents*`), the pre-ask hook already stores up to 1 KB of the question there, and the closing hook stores only the matched unit (at most 600 bytes) plus the cue name.
- **One forced reconsideration, not a guarantee.** A repeat of the same question after a block runs with `stop_hook_active == true` and passes; the ADR addendum and the learning say so, so nobody reads the gate as stronger than it is.
- **Cue-growth tripwire (judgement numbers, CTO devex review).** More than 6 CLOSING cue patterns (3 today), or 3 founder-reported misses in 30 days, (or incidents showing misses inside ralph loops) means the phrase-shaped design has outgrown its budget: revisit judging "Decision for you:" lists with no `?` (T3's rejected alternative) or stop adding cues. Recorded in the ADR addendum and the learning.
- **Headless CI sessions** that load `.claude/settings.json` (`claude-code-review.yml`, `scheduled-machinery-drain.yml`, `fix-constraints-stage-a.yml`) would run this hook; `GITHUB_ACTIONS=true` exits 0 so the cost there is zero, and a block anywhere costs at most one turn (bounded by `stop_hook_active`). Blocks in ephemeral runners never reach a local ledger, so the 30-day firing count and the false-positive record are blind there; stated, not fixed.
- **Latency is unit-count-bound.** 500 tiny `?` units through eight greps each measured 16.9 s on this host, so the plan normalises once, judges at most the last 12 units, and registers the hook with `"timeout": 10`.
- **Escape scope is the weak point of any label vocabulary.** `<stop>` and a final-sentence `Paused:`/`Blocked:` pass the whole closing (the brief demands the first; the second mirrors the plugin hook), so both are unverified self-classification; `Operator-only (category):` is scoped to its own sentence and the next unit. The `Paused:`/`Blocked:` label is shared with `unkept-promise-hook.sh`'s `STOP_MARK_RE`, so one appended label disarms both gates: the reason therefore teaches `Operator-only (category): ...` first.
- **A leading permission phrase launders a technical clause** ("may i rotate the keys, and in what order?" passes, row Z1). This is the price of the brief's hard requirement that an authorization ALWAYS passes; recorded, with the cue-growth tripwire as the escalation.
- **The kill switch is a developer tool.** `SOLEUR_ACK_TECHNICAL_FORK=1` is read from the hook's own environment, so it must be set before a session starts, and `settings.json`'s `env` block or `settings.local.json` can set it persistently (a model with write access could too; a residual shared with the pre-ask hook). The founder's path is to ask the agent to relaunch with it.
- **No new web or CI trust boundary.** `settingSources: []` is pinned at `apps/web-platform/server/agent-runner-query-options.ts` (and `apps/web-platform/test/agent-runner-query-options.test.ts`), so a `.claude/hooks` Stop entry is not reachable from web.
- **The Stop payload under Devin is unmeasured** for `stop_hook_active` and `last_assistant_message`; the hook fails open when either is absent, so the ledger's `already-fires` row is honest about firing, not about blocking there.
- **Recall decay is accepted** (T8). A phrasing outside CL1-CL3 and the SHARED cues passes. The remedy is the miss, cue, fixture loop, not preemptive widening.
- **Self-classification at the writer** (the 2026-10-11 residual, unchanged): the `Operator-only (category)` escape lets the model label a technical fork operator-only. The category list is closed and the label is visible in the transcript; the ship gate's PR-body rendering remains the review surface.
- **Two Stop hooks can block the same turn** (this one and the plugin's unkept-promise hook); each blocks at most once per chain and the runtime caps consecutive Stop blocks, so the worst case is two bounded reasons.
- **Linear-time regexes only.** Every new pattern uses bounded `{0,60}` gaps over a unit the closing hook caps at 600 bytes; the suite carries a generous timing row plus a 30 KB versus 60 KB linearity comparison (a tight wall-clock bound is a known CI flake source).
- **`lint-skill-body-budget.py` reads the ceiling from the merge-base**: a same-PR raise is impossible, so Phase 0.3 must land the relocation in the same edit as the `work` pointer.
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one states `aggregate pattern`.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 where the closing-prose gate lives: repo-local `.claude/hooks` Stop entry versus the shipped plugin | technical | Ruled by CTO agent, 2026-10-12: repo-local (new `Stop` entry in `.claude/settings.json`, ledger row `already-fires`); graduate to the plugin only together with the pre-ask gate under #10056 after 30 days in service, 10 recorded firings, zero founder-reported wrongful blocks and a clean sample re-run - the plugin route needs a web opt-out and the web-parity test, and third-party vocabularies raise the false-positive risk before any in-repo record exists |
| T2 shared cue lib structure, new cues and veto split | technical | Ruled by CTO agent, 2026-10-12: one lib with SHARED (byte-identical move) and CLOSING groups, group as a function argument; BUSINESS/ACTION veto split with CLOSING cues vetoed by BUSINESS only; three strong cues CL1 sufficiency, CL2 design, CL3 ordering; one verdict function owns extraction, vetoes and the permission exemption; 600 byte unit cap - pre-ask stays behaviourally untouched and question (b) is not silenced by `deploy` |
| T3 closing window and sentence scoping | technical | Ruled by CTO agent, 2026-10-12: last 1500 bytes of fence-stripped prose, judge only `?`-terminated sentences each alone, any hit blocks, lists with no `?` are not judged - the stricter (blocks less) option, with the miss as a stated residual |
| T4 escape vocabulary and block-reason wording | technical | Ruled by CTO agent, 2026-10-12: honour `<stop>OPERATOR-GATE\|BLOCKED`, a plain `Operator-only (category):` sentence and a final-sentence `Paused:`/`Blocked:` label (non-empty); reason names the CTO and CLO, "Ruled by CTO agent", the closed categories and the split remedy, with no angle-bracket text - the model echoes markup it is taught |
| T5 false-positive budget and measurement method | technical | Ruled by CTO agent, 2026-10-12: newest 300 closings with a `?`, offline run, counts only in the PR body, zero operator-class or ambiguous hits, over 15% blocked means too broad, narrow then re-run, two failed rounds drop the cue - a wrongly blocked closing is the worse failure |
| T6 skill pointer lines | technical | Ruled by CTO agent, 2026-10-12: pointers in `one-shot` and `go` only, naming the closing message as the carrier; none in `plan` or `work`; no trimming of `work/SKILL.md` line 286 - the rule prose and link already exist in all four and the failure happened anyway. Dissent: none |
| S1 pointer lines in `plan` and `work` (the brief names all four skills) | taste | |
| S2 escape scope of `Operator-only (category):` (own sentence plus the next unit) versus the CTO's whole-window wording | taste | |
| T7 reconciliation with R3, #10057 and #10056 | technical | Ruled by CTO agent, 2026-10-12: R3 stands for the exact-label arm; this cue-based hook is the re-evaluation case #10057 named, so close #10057 as superseded, file ONE follow-up for the rule's `[hook-enforced:]` tag, leave #10056 open with the graduation criterion - no `AGENTS.rules.md` edit under ADR-092 |
| T8 most likely failure and the cheapest cut | technical | Ruled by CTO agent, 2026-10-12: recall decay (phrase-shaped cues); do not broaden preemptively, use the miss, cue, fixture loop; keep the CLOSING group separate so the pre-ask hook is not widened |

## Plan Review and Deepening

### Plan review (2026-10-12, headless)

Panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer` (per mechanism, against the Property and Cut Lists), and the named panel's `soleur:engineering:cto` (devex lens; the other named agents did not activate: no UI surface, no market or money change).

- **Applied (mechanical):** the 600-byte cap moved to the closing hook's call site (DHH P1-1, Kieran P0-1, both measured against pre-ask rows T1-T4); `headline` dropped from the veto (DHH P1-2, Kieran P1-1); predicate renamed `tfc_is_fork` with an exit-2 arm and `TFC_HIT` only for the incident row (DHH P2-2, Kieran P2-2); missing-lib fail-open arm in both hooks (Kieran P1-2); URL-safe unit boundary (Kieran P1-4); narrowed CL2a/CL2b and the closing-only veto from measured near-misses (Kieran P1-5); `AUTHZ_VERB_RE` stays in the pre-ask hook (Kieran P2-1); fence strip before the byte cut and `LC_ALL=C` (Kieran P2-4); `work` funding pinned to scenarios 25c/25d (Kieran P2-5); AC wording fixes (Kieran P2-6, DHH P2-5); matrix cut to 11 rows plus a derived census and H1/H3 (simplicity, DHH P2-1); sed reads by variable name, then by sourcing (CTO devex, architecture); timing row by unit count, kill switch in `systemMessage`, `MIN_FIRING_SUITES` conflict note, dry run of reacting suites, sample-extractor recipe in the learning, cue-growth tripwire (CTO devex).
- **Kept against a reviewer:** CL2b stays (simplicity wanted it cut up front; it is the founder-observed phrase and the CTO ruled it; the sample drops it if needed); the third escape form and the 600-byte cap stay (binding rulings T4, T2); the C4 edit stays (DHH P2-6 asked to defer it; the C4 completeness mandate requires correcting an edge sentence this change falsifies); the single-PR shape stays (the CTO devex review noted the lib refactor could land first; the brief says one PR and the pieces share the registry edits).
- **Taste / user-challenge (persisted to `decision-challenges.md`):** S1 (the four pointer lines, against the CTO's two-skill form; class `taste`, no issue) and S2 (the `Operator-only` escape scope, stricter than the CTO's wording).

### Deepen-plan enhancement summary (2026-10-12)

Gates run: Phase 4.6 (User-Brand Impact present, threshold `aggregate pattern`), 4.7 (Observability: all five fields present, no stub values, no pipe or shell-active character in the command, first token `grep` is allowlisted, `expected_output` a literal), 4.8 (no PAT-shaped variable), 4.9 and 4.10 (no UI surface, no store or `.tf`: skipped), 4.11 (`lint-guard-contract.py` green; assembly names the chokepoints, not members), 4.12 (one live `## Scope Check`), plus the quality checks: every cited issue and PR number resolved live (#10057, #10056, #9642 is an OPEN issue, #7462 CLOSED, #10049 merged and the commit that introduced the reference), every rule id resolved (`wg-architecture-decision-is-a-plan-deliverable` is migrated-active), every KB path exists or is a to-be-created file, labels exist. 4.5 (network outage) did not fire: no SSH or network symptom.

Agents used: `soleur:engineering:review:security-sentinel`, `soleur:product:spec-flow-analyzer`, `soleur:engineering:review:architecture-strategist` (plus the plan-review panel above and the CTO ruling).

Key improvements: (1) the escape scoping hole and the toothless reason ordering (spec-flow P0-1/P0-2); (2) the 16.9 s unit fan-out (security F1, measured); (3) the ralph-loop blind spot stated as a residual with a probe and a tracked escalation (spec-flow P0-3, verified against `stop-hook.sh`); (4) the shared `Paused:`/`Blocked:` label coupling with the plugin hook (security F4); (5) ledger privacy (F7), stdout-corruption arms (F5), byte-constant reason (F6); (6) the exact three C4 strings, the graduation checklist and the seam variables that make the later plugin move mechanical (architecture); (7) the false-positive loop given an owner, a channel, an origin-to-file map and a no-floor-lowering rule (spec-flow P1-2).

New considerations: the closing hook is a new `emit_incident` caller, so its suite is hop 2 of `incident-sandbox-coverage`; a `.devin` Stop entry would double-fire; Codex needs no row; the `go` pointer extends an existing sentence instead of adding a line; brainstorm (not named in the brief) is where "which approach?" prose is likeliest and is recorded as an omission, not added.
