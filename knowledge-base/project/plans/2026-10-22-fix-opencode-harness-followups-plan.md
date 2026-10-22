---
title: "fix: close four OpenCode harness follow-ups (workdir visibility, approval-gate disclosure, ADR set, contributor docs)"
date: 2026-10-22
slug: fix-opencode-harness-followups
branch: feat-one-shot-10819-opencode-harness-followups
issue: 10819
issues: [10819, 10820, 10821, 10822]
lane: cross-domain
requires_cpo_signoff: true
---

## Overview

Four follow-ups filed against the OpenCode adapter rollout, each a single scoped defect:

1. **#10819** — the Bash guard envelope carries the session directory as `cwd`, so a `shell` call
   with a per-call `workdir` is judged against the wrong directory. Measurement below shows this is
   a real guard hole (relative `rm -rf` is allowed from the session dir, asked from the workdir).
2. **#10820** — the generated capability matrix never names the one approval gate OpenCode cannot
   carry, so the disclosure lives only in marketing copy.
3. **#10821** — ADR-245's supported-harness set still excludes OpenCode while ADR-291 records the
   OpenCode adapter; both are live records (ADR-245 `status: active`, ADR-291 `status: accepted`).
4. **#10822** — `CONTRIBUTING.md` documents every harness but OpenCode, and four source comments
   still describe a four-harness world.

Out of scope by explicit ruling: the CLO-signed legal parenthetical re-pin (its own PR, #10815).

## Research Reconciliation — Spec vs. Codebase

The repo research returned gap callouts against the issue text. They are reconciled here rather
than inherited as phase fiction.

| Spec claim | Reality | Plan response |
|---|---|---|
| #10819: `guardEnvelope` at `:183-189`, `decidePermission` at `:272` | Both exist at those anchors; `decidePermission` is `:264-273` and calls `decideBash(action, { command }, cwd, …)` | Plan cites the function anchor, not the issue's line numbers |
| #10819: bind `workdir` into `tool_input`/`cwd` at two call sites | `permission.evaluate` carries **no** workdir (measured); the value exists only on `tool.execute.before`, keyed by a call id that `permission.evaluate.source.id` also carries | Fix publishes the value from the deciding hook and correlates by id; it cannot be read at the permission site |
| #10820: `INSTRUCTIONS.md:109-116` is the limitations section | The limitations are prose paragraphs under `## Hooks and completion` (`:100-136` after regeneration); there is no `## Limitations` heading | Add the paragraph to the generator source (`instructions()`), regenerate, never hand-edit output |
| #10821: ADR-291 reconciled §Context | The non-exhaustive parenthetical is in ADR-291 **§Status** (`:43`), not §Context | Amendment cites ADR-291 by ordinal + title; the parenthetical is quoted from §Status |
| #10822: `CONTRIBUTING.md` has Grok at `:39`/`:48-63` and Codex at `:23` | Correct, but there is **no** `### Grok Build` heading — Grok is a paragraph inside `### Codex`, and `### Grok command naming` at `:48` is about command namespaces | Plan inserts `### OpenCode` after the Grok command-naming subsection, before `## Contributor License Agreement` |
| #10822: stale comments at four anchors | All four exist as described; the `lib/harness.ts` module header omits OpenCode **and** Antigravity while the `Harness` union has both | Rewrite the header count-free instead of correcting a number that will stale again |
| Overlap preflight (`pr-overlap-preflight.sh --mode start`) | Ran twice, both `rc=2` (`jq: Argument list too long`); no result | **Overlap was NOT checked** by that tool; the Phase 1.7.5 code-review overlap check ran instead (see `## Open Code-Review Overlap`). Do not claim the diff is overlap-clear |

## Research Insights

### Premise Validation (Phase 0.6)

All 11 paths cited by the four issues exist on the branch base (`dev` merge-base), and both ADRs
exist. Premise corrections are in the reconciliation table above. Nothing in the four issues is
premised on code that has since moved or been deleted.

### Measurement record — #10819 (live, OpenCode 2.1.2)

Probe: a project plugin logging every hook event, plus one `shell` call
`echo probe-from-workdir && pwd` with `workdir=/tmp/opencode/wdprobe/elsewhere`, run in
`/tmp/opencode/wdprobe/`. Three events, in this order:

```text
TOOL_BEFORE  keys=[tool,sessionID,agent,messageID,id,input]
             id=call_00_s3uv… input={"command":"echo … && pwd","workdir":"/tmp/opencode/wdprobe/elsewhere"}
PERMISSION   action="external_directory" resources=["/tmp/opencode/wdprobe/elsewhere/*"]
             source={"type":"tool","messageID":"msg_…","id":"call_00_s3uv…"}
PERMISSION   action="shell" resources=["echo probe-from-workdir","pwd"]
             source={"type":"tool","messageID":"msg_…","id":"call_00_s3uv…"}
```

Conclusions that bind the design:

- `workdir` is visible **only** on `tool.execute.before`; `permission.evaluate` has no cwd field.
- `source.id` on the permission event equals the tool hook's `id`, so the two hooks correlate.
- `external_directory` fires **first** with the same call id — consuming the correlation on any
  action other than `shell` would lose it before the shell decision.
- Guard pair run with the production envelope construction (both guards, ordered):
  `cwd=sessionDir` → no output, exit 0 (**allow**); `cwd=workdir` → `ask`,
  rule `recursive-delete-workdir`. The hole is real: a relative destructive command is silently
  allowed whenever `workdir` differs from the session directory.
- The hole is worse than a missing `ask`: the guard's **deny** class is cwd-dependent too ("a bare
  `*` `**` or `./*` when the working directory is home or an ancestor",
  `hooks/destructive-command-guard.sh:23`). With `workdir=~` and envelope `cwd=<checkout>`,
  `rm -rf *` lands in "not decided" and is allowed with no prompt of any class.
- Running the guards with `cwd = workdir` is safe, checked rather than assumed:
  `destructive-command-guard.sh` prefers the envelope's `cwd` over `CLAUDE_PROJECT_DIR`/`PWD` and
  strips `GIT_*` by prefix; `browser-snapshot-credential-guard.sh` reads only
  `tool_input.command` (no cwd reference) and sources its library via `BASH_SOURCE`. Both scripts
  are invoked by absolute path, so the child cwd cannot change which script runs.

### Property list (Phase 0.6b)

| # | Property | Mechanism that satisfies it |
|---|---|---|
| P1 | A `shell` decision uses the directory the command will run in | correlate `input.workdir` from `tool.execute.before` into the permission envelope's `cwd` |
| P2 | A capture is never silently absent: every Bash tool call records an entry, with a sentinel when it has no `workdir` | entry = `{workdir?: string, consumed: boolean}`, keyed by call id; a lookup miss then means "the tool hook did not fire", not "no workdir" |
| P3 | `external_directory` never consumes the entry | consume (mark consumed) only when `action === "shell"` |
| P4 | Correlation never fails open without a loud complaint | unmatched id / unusable workdir / unconsumed eviction each `console.error` **and** write an event-log line — `console.error` because the log file is unset by default, the same reason `GUARD_RUN_FAILURE` announces itself |
| P5 | The generated matrix names every absent gate with its consequence | generator source paragraph + regenerated output + drift `--check` |
| P6 | Two accepted ADRs cannot disagree about the supported set | dated, clause-scoped amendment on ADR-245 naming ADR-291 |
| P7 | Public/contributor docs name the fifth harness without a count that can stale | CONTRIBUTING subsection + count-free comments |

### Cut list (Phase 0.6b)

- **Wiring `tool.execute.before` as a blocking guard** — measured to fire before
  `permission.evaluate`; a throw there preempts a real `ask` and re-degrades it to a refusal. The
  binding is **capture-only**.
- **Re-deriving the workdir at the permission site** — impossible (not on the event). Not attempted.
- **Adding OpenCode to the C4 model** — real pre-existing gap, filed as #10866; not folded in.
- **Legal parenthetical re-pin** — excluded by the CLO ruling; not touched.

### Institutional learnings that bind the fix

- Publish the derived value from the hook that can see it; do not re-derive it at the consumer.
- A correlation test must pin the wire: deleting either side must redden it.
- A bounded map must not silently degrade to "no workdir → proceed"; eviction and fallback must be
  visible.
- Test fixtures must carry a real `input.workdir`; a fixture without it tests the fallback.
- After any doc/generated edit, run the whole prose-gate set (`harness-claim-parity`,
  `harness-tool-map`, adapter drift), not just the file's own test.

### Related issues and PRs

- #10815 — parent OpenCode claim flip (closed); the four issues here are its follow-ups.
- #10863 — draft PR for this branch.
- #10866 — filed from this plan: C4 model has no OpenCode harness element.
- #10591 (uninstall flag), #10587 (compaction `context` probe), #10819–#10822.
- #8593 — open `code-review` issue naming `plugins/soleur/test/components.test.ts`; see overlap
  section.

### Repository conventions

- `plugins/soleur/opencode/plugin.ts` is a **source** file for the generator, not generated: edit it
  directly, never add it to a template string.- `plugins/soleur/opencode/INSTRUCTIONS.md` is generated; edit `scripts/sync-opencode-adapter.ts`
  and regenerate.
- `.claude/hooks/opencode-dispositions.tsv` is the canonical hook ledger: one row per registration,
  every row with a disposition. A code change that invalidates a row must update the row in the
  same PR.
- ADRs are immutable records; corrections are dated amendments (see `adr-template.md:27`), citing
  decisions by ordinal + title, never by position.
- Harness claims are gated by `test/harness-claim-parity.test.ts`: name OpenCode explicitly or use
  count-free phrasing.

## Implementation Phases

### Phase 1 — #10819: carry the per-call `workdir` into the guard envelope

**Design (decided; no open technical fork).** `tool.execute.before` is the only surface that sees
`input.workdir`; `permission.evaluate` is the only surface that can block. So the tool hook
**publishes** the value keyed by the call id, and the permission hook **consumes** it.

1. `plugins/soleur/opencode/plugin.ts`
   - `SetupContext` gains an optional `tool?: { hook(name: "execute.before", handler: …) }` member.
     Optional because the plugin must load on a runtime that does not offer it; absence is
     **announced once at setup**, not ignored.
   - `PermissionEvaluateEvent` gains `readonly source?: { readonly id?: unknown }`.
   - New exported `workdirForCall(input: unknown): string | undefined` — returns `input.workdir`
     only when it is a non-empty string; a relative value is resolved against the session directory
     (`isAbsolute`/`resolve` from `node:path`).
   - `createSetup` holds `calls = new Map<string, { workdir?: string; consumed: boolean }>()`, LRU
     bounded at 500 (same two-line shape as `sessions`). **Every Bash tool call records an entry**,
     with `workdir: undefined` as the sentinel for "this call carries no workdir". Without the
     sentinel a lookup miss cannot be distinguished from "no workdir", which is exactly the
     pre-fix behavior.
   - Bind `ctx.tool?.hook("execute.before", …)`: gate on `claudeToolName(event.tool) === "Bash"`
     (the same map the guards use — not the literal `shell`, so the `bash` alias keeps working);
     `calls.set(event.id, { workdir, consumed: false })`. **Never throw** here — capture-only.
   - **Do not delete on consume.** Mark `consumed = true` instead: the measurement establishes one
     tool event and two permission events per call, not that a call is evaluated exactly once. A
     retry or re-prompt with a second `shell` evaluation would otherwise fall back to the session
     directory — a correct decision turned into the hole. Call ids are not reused; the LRU bounds
     memory.
   - On eviction, if the evicted entry was never consumed, `console.error` **and** write
     `soleur-opencode\tworkdir-evicted\tid=…\tworkdir=…`; a consumed entry is evicted silently
     (normal LRU churn, not a fault).
   - In the shell path of the permission handler, resolve the effective cwd **once**:
     a missing/non-string `event.source.id` → `console.error` + `workdir-uncorrelated\tid=absent`;
     an id with no entry → `console.error` + `workdir-uncorrelated\tid=…\tno-capture` (the tool hook
     did not fire); an entry whose `workdir` is not an existing directory
     (`existsSync` + `statSync().isDirectory()`) → `console.error` +
     `workdir-unusable` and fall back to the session directory, because `spawnSync` with a
     nonexistent cwd returns `status: null` and would be misreported as `guard-did-not-run` blaming
     a moved checkout; an applied workdir → `workdir-correlated\tcwd=…`. No workdir (sentinel) is
     the normal path and writes nothing.
   - Non-`shell` permission events return **before** touching the map — the `external_directory`
     event that fires first for the same call id must not consume the entry.
   - Pass the resolved cwd as `cwd` into the existing `decidePermission(action, resources, cwd, …)`
     — **no new parameter**: that cwd becomes both the envelope `cwd` and the runner cwd inside
     `decideBash`. `decideBash`, `guardEnvelope`, and both guard scripts are unchanged.
   - Update the module docblock paragraph that says `execute.before` is "deliberately not bound":
     it is now bound **as a capture**, with the preemption reason retained.
2. `plugins/soleur/test/opencode-plugin.test.ts`
   - Extend `fakeContext()` with a `tool` member that captures `tool:execute.before`; add a
     `fakeContext({ tool: false })` form for the absent-surface case.
   - New suite `workdir correlation` with at least: (a) workdir from the tool hook reaches the
     envelope and the runner cwd, and writes `workdir-correlated`; (b) no workdir → session dir,
     unchanged, no line; (c) workdir equal to the session dir → identical allow; (d) no
     `source.id` → session dir **and** a `workdir-uncorrelated` line; (e) id with no capture → same
     line with `no-capture`; (f) nonexistent workdir → `workdir-unusable` and session dir;
     (g) eviction of an unconsumed entry writes `workdir-evicted`; (h) a consumed entry evicts
     silently; (i) an `external_directory` event does not consume, and the following `shell` event
     still correlates; (j) an absent `ctx.tool` writes `no-tool-hook-surface` once.
   - Every correlation assertion reads the **bytes handed to the guard** (`runs[0].stdin`), not an
     internal variable.
   - Update the ledger suite (the case in this file that asserts the `tool.execute.before` row): its
     comment says `tool.execute.before` is "deliberately unbound" and the assertion only checks a row
     mentions it. After this change the row must be `bind`, so assert the disposition and that the
     reason says *capture-only* — otherwise the test still passes while no longer testing its stated
     claim.
3. `.claude/hooks/opencode-dispositions.tsv` — the `tool.execute.before` row changes from
   `absent-with-reason` to `bind` with reason "capture-only: publishes `input.workdir` for the
   permission hook to consume by call id; never refuses (a throw here preempts the real ask)".
   Evidence cites `plugin.ts workdirForCall()` + the correlation test.

### Phase 2 — #10820: disclose the absent operator-stage approval gate

1. `plugins/soleur/scripts/sync-opencode-adapter.ts` — inside `instructions()`, after the guards
   paragraph, add a paragraph naming `hooks/operator-stage-approval.sh` as **absent**, with the
   consequence: the hook is what mints the digest-bound approval receipt a staged `--apply`
   consumes, so `scripts/lib/operator-script.sh`'s `soleur_op_stage_gate` finds no receipt and exits
   **75** (`SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED`); where the script is driven from a real TTY the
   fallback is a bare `tty-ack` confirmation. State that nothing is approved silently.
2. Regenerate `plugins/soleur/opencode/INSTRUCTIONS.md` with
   `bun plugins/soleur/scripts/sync-opencode-adapter.ts`; never hand-edit.
3. Re-run `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` (expect `opencode-adapter ok`).
4. `.claude/hooks/opencode-dispositions.tsv` — the operator-stage row's evidence gains
   "disclosed in `opencode/INSTRUCTIONS.md` §Hooks and completion" so ledger and matrix agree.
5. **Operator-surface sweep (read-only).** The gate is named on several surfaces an operator may read
   before the matrix: `plugins/soleur/skills/operator-bootstrap/SKILL.md`,
   `plugins/soleur/hooks/hooks.json`, `scripts/lib/operator-script.sh`, ADR-264 and ADR-277. Sweep
   them with
   `git grep -n "operator-stage-approval\|SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED" -- <those paths>` and
   confirm none of them claims OpenCode carries the gate. **No edit to those files in this PR** — a
   contradiction would be disclosed in the PR body as a follow-up, because widening this diff to the
   operator-bootstrap skill or an accepted ADR is a different change with its own review.

### Phase 3 — #10821: amend ADR-245

Append `## Amendment — 2026-10-22 (#10821)` to
`knowledge-base/engineering/architecture/decisions/ADR-245-*.md`. The amendment:

- scopes itself to **Decision item 1** ("The supported harness set is Claude Code, Grok Build, Codex
  and Devin") and to the **§Context** sentence "one plugin tree to four supported harnesses";
- records that both are **the set at decision time (2026-10-14)**, not a current claim;
- names the superseding record by ordinal and title: **ADR-291, "Add an OpenCode plugin adapter"**
  (accepted) — and records that OpenCode **satisfies this ADR's own re-entry criterion**: a
  `Harness` union member (`opencode` exists) and a generator (`sync-opencode-adapter.ts`). The
  amendment does not claim ADR-291 restates the supported set; it does not, and that is why the
  criterion is the bridge between the two records;
- does **not** rewrite the original text, and does **not** assert a C4 or gate consequence.

The issue also asks whether any other ADR names the set the same way. Verified:
`git grep -n "Grok Build, Codex" knowledge-base/engineering/architecture/decisions/` returns only
ADR-245 (**§Context**, **§Decision item 1**) and ADR-291 (its **§Context**, **§Status** parenthetical
and the "before this adapter" paragraph — all correct as written, because ADR-291 states the
pre-adapter set and calls its own parenthetical non-exhaustive). No further edit.

### Phase 4 — #10822: contributor path and count-free comments

1. `CONTRIBUTING.md` — new `### OpenCode` subsection after `### Grok command naming`, before
   `## Contributor License Agreement`. Content:
   - install from the repo root: `bun plugins/soleur/scripts/install-opencode-adapter.ts`
     (default `~/.config/opencode`, or `--target DIR`);
   - verify the install: `… install-opencode-adapter.ts --check [--target DIR]`;
   - after editing a generated input: `bun plugins/soleur/scripts/sync-opencode-adapter.ts` then
     `… --check`;
   - commands are bare (`/go`, `/help`, `/sync`, `/version`); skill ids are bare (`plan`, not
     `soleur:plan`); agents spawn by path id (`engineering/cto`);
   - **the checkout must stay put**: the installed config points at this tree for skills, routing
     rules and guard scripts. Moving it makes every guard fail closed (`guard-did-not-run`).
   - link `plugins/soleur/opencode/INSTRUCTIONS.md`.
   The subsection names OpenCode literally (the parity gate's `FOUR_MEMBER_WITHOUT_FIFTH` scan
   covers `CONTRIBUTING.md`).
2. `plugins/soleur/lib/harness.ts` module header docblock — replace the enumerated
   "Claude Code, Grok Build, Codex, Devin CLI, or the Cursor CLI" with
   "maps Soleur workflow invocations to each member of the `Harness` union" (count-free; the union
   is the authority and includes OpenCode and Antigravity).
3. `plugins/soleur/lib/workflow-fidelity.ts` — in the `pipelineInvocationSuffix` docblock, "silently
   on three of four harnesses" → "silently for any caller that forgot it". The paragraph already
   names the caller as the subject ("for any caller that forgot it"), so the sentence ends there
   instead of replacing one harness count with a universal claim about harness behaviour that the
   file does not establish.
4. `plugins/soleur/test/components.test.ts` — the comment reading "blocked on the OTHER THREE
   HARNESSES" → "blocked on the other harnesses that load them"; the comment reading "a real change
   on three harnesses" → "a real change on those three harnesses". **Not** "every other harness":
   OpenCode, Cursor and Antigravity do not declare those shim roots, so a universal claim would
   introduce a new false statement in a fix for false statements. The adjacent "the other three
   harnesses DO resolve these paths" is left as-is: it sits in the block that names which three, so
   it is scoped by context and not a total. Comments only; no assertion changes.

### Phase 5 — verification and disclosure

1. Focused suite: `cd plugins/soleur && bun test test/opencode-plugin.test.ts
   test/opencode-adapter-drift.test.ts test/harness-claim-parity.test.ts test/harness-tool-map.test.ts`
   (baseline before the change: 84 pass / 0 fail; expect **≥ 94** after the ≥10 new correlation rows,
   0 fail). Quote the pass/fail counts in the PR body rather than asserting "green".
2. `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` → `opencode-adapter ok`.
3. `TARGET=$(mktemp -d)`; `bun plugins/soleur/scripts/install-opencode-adapter.ts --target "$TARGET"`,
   then `… install-opencode-adapter.ts --check --target "$TARGET"` → `opencode-install ok`. The
   `--check` arm writes nothing and reports `MISSING` against an empty target, so the install must
   come first; running `--check` on a bare `mktemp -d` reports a false red.
4. Mutation pass (see `## Guard Contract`): delete each side of the correlation in a scratch copy,
   confirm the new suite reddens, restore.
5. PR body discloses: overlap preflight `rc=2` (not checked), C4 gap (#10866), and that
   `plugins/soleur/scripts/` is CI-checked only by the fixture-based drift test — no workflow runs
   `sync-opencode-adapter.ts --check` against the committed tree.

## Files to Edit

- `plugins/soleur/opencode/plugin.ts`
- `plugins/soleur/test/opencode-plugin.test.ts`
- `plugins/soleur/scripts/sync-opencode-adapter.ts`
- `plugins/soleur/opencode/INSTRUCTIONS.md` (regenerated)
- `.claude/hooks/opencode-dispositions.tsv`
- `knowledge-base/engineering/architecture/decisions/ADR-245-retire-openhands-gemini-ports-and-prove-codex-devin-discovery-in-ci.md`
- `CONTRIBUTING.md`
- `plugins/soleur/lib/harness.ts`
- `plugins/soleur/lib/workflow-fidelity.ts`
- `plugins/soleur/test/components.test.ts`

## Files to Create

- `knowledge-base/project/plans/2026-10-22-fix-opencode-harness-followups-plan.md`
- `knowledge-base/project/specs/feat-one-shot-10819-opencode-harness-followups/tasks.md`

## Open Code-Review Overlap

Check ran against 95 open `code-review` issues (two-stage `gh --json` + standalone script; the
`gh --jq --arg` form is not used).

- #8593 ("#6793 probe gate window is narrower than the silent-truncation property it names") names
  `plugins/soleur/test/components.test.ts`. **Acknowledge:** this plan's edit there is two comment
  sentences about harness counts; it does not touch the probe gate or its window. #8593 remains
  open.

All other planned paths: no match.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | `[issue #10819]` "Capture the `permission.evaluate` input shape for a `shell` call carrying `workdir`" | Measurement record (done) | mapped |
| 2 | `[issue #10819]` "If a relative dangerous path is allowed: bind `workdir` into `tool_input`/`cwd` … add a `plugin.ts` unit test" | Phase 1 | mapped |
| 3 | `[issue #10820]` "Add the absent-gate row to whatever source the generator renders the limitations section from, naming the consequence" | Phase 2.1 | mapped |
| 4 | `[issue #10820]` "Regenerate + re-run the adapter drift gate" | Phase 2.2–2.3, Phase 5.2 | mapped |
| 5 | `[issue #10821]` "Either add OpenCode to ADR-245's set … or mark it explicitly as the recorded state at decision time" | Phase 3 | mapped |
| 6 | `[issue #10821]` "Check whether any other ADR names the harness set the same way" | Phase 3 (grep, recorded) | mapped |
| 7 | `[issue #10822]` "Add an OpenCode subsection to CONTRIBUTING: install from the repo root, `--check` for drift, bare command and bare skill ids, and that the checkout must stay put" | Phase 4.1 | mapped |
| 8 | `[issue #10822]` "Correct the four comments, or replace the counts with 'every harness'" | Phase 4.2–4.4 | mapped |
| 9 | `[user directive]` "The CLO-signed legal parenthetical re-pin … remains its own PR, as ruled" | — | descoped — justification: CLO ruling recorded in #10815; touching the seven canonicals forces `TC_VERSION`/`TC_DOCUMENT_SHA`/`LEGAL_DOC_SHAS` re-pins and its own signature path |
| 10 | `[user directive]` deliver all four in one merged PR | Single PR, Phase 1–5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 correlation (`calls` map, effective cwd) | asks 1–2: "bind `workdir` into `tool_input`/`cwd` at `plugin.ts:183-189` and `:272`" | asked |
| Phase 1 dispositions row | — | inferred — justification: the ledger's row says `tool.execute.before` is "deliberately NOT bound"; shipping the capture leaves a false record that the honesty contract forbids |
| Phase 1 `ctx.tool` optional + degradation logs | — | inferred — justification: a bounded map or an absent hook surface that degrades to "no workdir → proceed" silently reintroduces the exact hole #10819 reports |
| Phase 2 generator paragraph + regen | ask 3–4 | asked |
| Phase 2 ledger evidence cross-reference | — | inferred — justification: #10820 exists because the matrix and the ledger diverged in what they disclose; leaving them uncross-referenced re-opens it |
| Phase 3 ADR-245 amendment | ask 5–6: "mark it explicitly as the recorded state at decision time" | asked |
| Phase 4.1 CONTRIBUTING subsection | ask 7 | asked |
| Phase 4.2–4.4 comments | ask 8: "replace the counts with 'every harness'" | asked |
| Phase 5 verification | asks 2, 4 | asked |
| Plan/tasks artifacts | — | inferred — justification: `plan` Phase 6 requires the plan on disk and `tasks.md` derived from it |
| #10866 C4 follow-up | — | inferred — justification: C4 completeness mandate found a pre-existing gap that this diff does not create; a deferral without a tracking issue is invisible |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `knowledge-base`, `.claude`, repo root (`CONTRIBUTING.md`)
- Planned files: 12 (10 edit + 2 create) | Estimated changed lines: ~260
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR** — over the subsystem-root threshold by one, under both others.
  Advisory split offered but overridden: the operator's stated objective is one merged PR closing
  #10819–#10822; three of the four issues are disclosure edits in different roots (one file each),
  and splitting would run four CI cycles and four ADR/ledger syncs for ~260 lines of one harness
  concern. Seam if ever split: #10819 (code + test + ledger) vs #10820–#10822 (prose/records).

## Domain Review

### Engineering

CTO consult — **status: concern, no unresolved blocking finding**. The only genuine technical fork
("read the workdir at the permission site" vs "publish it from the tool hook") is closed by
measurement, so the second is the only implementable shape. The CTO's blocking findings are folded
in: (1) the fail-visible claim no longer rests on an event log that is off by default — every
degraded path `console.error`s; (2) a sentinel entry per Bash call removes the "no workdir vs lost
capture" ambiguity; (3) the `workdir-correlated` token now has an emitter; (4) the
`components.test.ts` "a real change on three harnesses" comment is corrected specifically instead of
universalised; (5) Phase 5.3 installs before checking. Advisory
findings also folded: gate capture on `claudeToolName` rather than the literal `shell`; never delete
on consume; log eviction as informational for consumed entries; pre-check that the workdir exists;
update the ledger assertion (the case asserting the `tool.execute.before` row); and state that
`cwd = workdir` is safe for both guards (recorded in the measurement section). CTO also confirmed the
label must stay `semver:patch` and that review must explicitly cover the guard change.

### Product

CPO sign-off — **granted**, with the threshold confirmed as `single-user incident` and four
corrections applied: the false credential-guard vector is removed (that script reads only
`tool_input.command`); the impact statement now names the cwd-dependent **deny** class loss
(`rm -rf *` with `workdir=$HOME`), not just a missed ask; the placeholder `[data / workflow /
money]` is resolved to `data` with a concrete artifact; and the deliberate residual (fallback to
the session directory **allows**, loudly) is stated in the section rather than implied away.

### Legal

Not consulted: no regulated-data surface, no legal claim, and the one legal-adjacent item (the
canonical parenthetical) is explicitly excluded by the CLO ruling.

## User-Brand Impact

**If this lands broken, the user experiences:** a `shell` call that supplies `workdir` is judged
against the session directory because the capture was lost, evicted, or unusable. That is not
merely a missed `ask`: the destructive guard's **deny** class is cwd-dependent, so `rm -rf *` with
`workdir=$HOME` and envelope `cwd=<checkout>` is allowed with no prompt of any class, and the
recursive-delete `ask` is lost too. The operator's checkout or home directory is deleted.

**If this leaks, the user's data is exposed via:** no new data path is introduced — the exposure
vector is destruction, not disclosure. A mis-correlated `cwd` changes which paths the destructive
guard recognises as protected (home, its ancestors, the working directory). The credential guard
reads only `tool_input.command` and has no cwd-dependent rule, so it cannot be pointed at a
directory. On an unmatched, evicted, or unusable capture the plan falls back to the session
directory and **allows**, exactly as before the fix: that residual is deliberate (asking every call
when no tool surface exists would make the harness unusable) and it is why every fallback is
`console.error`-loud rather than silent.

**Brand-survival threshold:** single-user incident

## Observability

```yaml
liveness_signal:
  what: "`soleur-opencode\tworkdir-correlated` per shell call that applies a captured workdir, and `workdir-uncorrelated` / `workdir-unusable` / `workdir-evicted` on each degraded decision"
  cadence: "per shell call; plus one `no-tool-hook-surface` line at setup when ctx.tool is absent"
  alert_target: "none — a local CLI writes to the operator's own log; the line is the record, not an alert"
  configured_in: "SOLEUR_OPENCODE_EVENT_LOG (unset = no log file; the degraded paths still console.error)"
error_reporting:
  destination: "console.error for every degraded correlation (the log file is off by default), plus the event-log line when armed; console.error for the existing guard-run failure"
  fail_loud: true
failure_modes:
  - mode: "workdir captured but the permission event carries no usable call id"
    detection: "console.error + `soleur-opencode\tworkdir-uncorrelated\tid=absent` on the shell decision"
    alert_route: "stderr and event log; the decision falls back to the session directory"
  - mode: "call id present but no capture entry (the tool hook never fired)"
    detection: "console.error + `soleur-opencode\tworkdir-uncorrelated\tid=…\tno-capture`"
    alert_route: "stderr and event log; fallback to the session directory — the pre-fix behavior, deliberately loud"
  - mode: "captured workdir is not an existing directory"
    detection: "console.error + `soleur-opencode\tworkdir-unusable\tcwd=…`"
    alert_route: "stderr and event log; session directory used, so a nonexistent cwd is not misreported as `guard-did-not-run`"
  - mode: "bounded map evicts an entry that was never consumed"
    detection: "console.error + `soleur-opencode\tworkdir-evicted\tid=…\tworkdir=…`; a consumed entry evicts silently"
    alert_route: "stderr and event log"
  - mode: "runtime exposes no tool hook surface"
    detection: "`soleur-opencode\tno-tool-hook-surface\tworkdir-unavailable` written once at setup"
    alert_route: "event log; every decision uses the session directory, as before the fix"
  - mode: "a guard script cannot run (checkout moved, spawn error, timeout)"
    detection: "existing GUARD_RUN_FAILURE deny path"
    alert_route: "console.error + effect=deny naming the dead path"
logs:
  where: "the file named by SOLEUR_OPENCODE_EVENT_LOG (operator-chosen; unset means no log file)"
  retention: "operator's filesystem policy; not a hosted log sink"
discoverability_test:
  command: 'grep -c "calls.set(" plugins/soleur/opencode/plugin.ts'
  expected_output: "1"
```

## Architecture Decision (ADR/C4)

No new architectural decision. The plan **amends an existing ADR** (Phase 3) because ADR-245's
recorded set is read as current by readers, not because a decision changes: ADR-291 already made
it. `wg-architecture-decision-is-a-plan-deliverable` is therefore satisfied by delivering the
amendment in this PR, not by filing a follow-up.

### C4 views

No C4 impact from this change, checked against all three model files:

- **External human actors** — founder/operator, product end user, support persona: none added,
  removed, or re-scoped.
- **External systems/harnesses** — `codex`, `devin`, `grokBuild`, `cursorCli` are modeled as
  external harnesses with delivery edges to `platform.plugin`. **`opencode` is not modeled** (a
  pre-existing gap from ADR-291, not created here). This plan adds no element and no edge; it
  changes the plugin carrier's internals only. Tracked as #10866 rather than asserted complete.
- **Containers/data stores** — no container, no store, no network connection is added or changed.
- **Access relationships** — no relationship changes: the harness still loads the same plugin tree.

No `.c4` edit and no C4 test run are required because no model file changes; the absence of an
OpenCode element is disclosed above and tracked in #10866.

## Guard Contract

### Guard 1 — workdir correlation in the Bash guard envelope

**Property.** A `shell` permission decision is judged against the directory the command will actually
run in — the per-call `workdir` when one was supplied, the session directory otherwise — and never
against the session directory when a different `workdir` was supplied.

**Assembly.** Two hook surfaces, one chokepoint each. `tool.execute.before` is the **only** surface
carrying `input.workdir`; it records `calls.set(event.id, { workdir, consumed: false })` for every
call whose `claudeToolName` is `Bash` — including the sentinel entry when there is no workdir.
Every `permission.evaluate` for `action === "shell"` flows through the single handler in
`createSetup`, which resolves one effective cwd from `event.source.id` (missing id, missing entry,
and unusable directory each have their own loud path) and passes it as `cwd` to `decidePermission` —
the same value becomes the envelope `cwd` and the runner cwd inside `decideBash`, for **both**
`BASH_GUARDS`. There is no second envelope constructor and no other cwd writer. `external_directory`
events reuse the same call id and must not mark the entry consumed.

| # | Mutation (must drive the guard RED) | Why it is derivable from the design |
|---|--------------------------------------|--------------------------------------|
| 1 | Delete the capture write in `execute.before` (`calls.set`) | The only source of the value; P1 cannot hold |
| 2 | Delete the consume (ignore the map → always `sessionCwd`) | The property is about the decision, not the capture |
| 3 | Consume on any action, not only `shell` | `external_directory` fires first with the same id, so a correct capture still loses the value |
| 4 | Drop the eviction `console.error` + log for an unconsumed entry | P4: a silent fallback to the session dir is the hole, not a detail |
| 5 | Drop the `no-tool-hook-surface` line | Guard's own dispatch: with no tool surface every decision silently reverts to the pre-fix behavior while every other row passes |
| 6 | Record an entry only when a workdir exists (drop the sentinel) | A lookup miss becomes indistinguishable from "no workdir" — the ambiguity the sentinel exists to remove |
| 7 | Move the lookup to setup time instead of per event | A snapshot at setup certifies a property about a per-call value |

**Harness rows.**

| # | Edit to the suite (must drive it RED) or must-PASS input | Why |
|---|----------------------------------------------------------|-----|
| H1 | Remove `input.workdir` from the fixture | Proves the fixture carries the real wire field, not a stand-in |
| H2 | Assert a local variable instead of `runs[0].stdin` | Proves the test reads the bytes the canonical guard parses |
| H3 | **Must PASS:** workdir equal to the session directory | A guard that rejects everything cannot pass this |
| H4 | **Must PASS:** no workdir at all | Unchanged pre-fix behavior is a permitted input |

**Anchor.** The guard scripts are canonical and **unmodified** by this change; the assertions read
the envelope bytes handed to them. A weakening therefore has to change the bytes the canonical
script parses (or the script itself, which no diff in this PR touches), not an internal belief the
suite could be edited to match. The tool-name map and the dispositions ledger are independent
surfaces that also name the bound hook.

## Acceptance Criteria

1. `plugins/soleur/opencode/plugin.ts` correlates `input.workdir` from `tool.execute.before` into
   the envelope `cwd` used by both Bash guards, keyed by call id, marked consumed once per `shell`
   decision and never deleted on consume, with a sentinel entry for calls that carry no workdir —
   based on measurement §"Measurement record" above. Checkable:
   `grep -c "calls.set(" plugins/soleur/opencode/plugin.ts` → `1`,
   `grep -c "calls.delete(" …` → `0` (consumed entries are bounded by the LRU, not deleted), and
   `grep -c "workdirForCall(" …` → `≥2` (declaration + call site).
2. A unit test asserts the **envelope bytes** (`runs[0].stdin`) carry `cwd === workdir` and that
   `workdir-correlated` was written; a second asserts `cwd === sessionDir` on the sentinel path with
   no degradation line.
3. Deleting either the capture or the consume reddens the new suite, verified in a scratch copy:
   each side is removed with `sed -i`, the suite is run and its **quoted fail count** recorded
   (`not ok` lines), then the copy is discarded — the real tree is never mutated for this check.
4. **Degraded-correlation paths, one assertion each:** a missing `source.id` (`id=absent`), a
   missing capture (`no-capture`), and a nonexistent workdir (`workdir-unusable`) each
   `console.error` **and** write their distinct line **and** fall back to the session directory; an
   absent `ctx.tool` writes `no-tool-hook-surface` once at setup.
5. **Eviction, asserted separately from fallback:** evicting an entry that was **never consumed**
   writes `console.error` + `workdir-evicted`; evicting a **consumed** entry writes nothing. Neither
   assertion may be folded into the fallback cases — the two mechanisms (bounded map vs. per-call
   lookup miss) fail independently.
6. The ledger suite in `plugins/soleur/test/opencode-plugin.test.ts` (the case asserting the
   `tool.execute.before` row) asserts the row is `bind` and its reason says *capture-only* (the old
   assertion passes on any mention and no longer tests its stated claim).
7. `plugins/soleur/opencode/INSTRUCTIONS.md` names `hooks/operator-stage-approval.sh` as absent with
   the `exit 75` / bare-`tty-ack` consequence, regenerated from
   `plugins/soleur/scripts/sync-opencode-adapter.ts`. Checkable:
   `grep -c "operator-stage-approval" plugins/soleur/opencode/INSTRUCTIONS.md` → `≥1` **and**
   `grep -c "operator-stage-approval" plugins/soleur/scripts/sync-opencode-adapter.ts` → `≥1`
   (a match only in the generated file means it was hand-edited and the next regen reverts it).
8. `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` exits 0 with `opencode-adapter ok`.
9. `ADR-245` carries a dated `## Amendment — 2026-10-22 (#10821)` scoped to **Decision item 1** and
   the **§Context** "four supported harnesses" sentence, naming ADR-291 by ordinal and title and
   citing ADR-245's own re-entry criterion, with the original text unchanged. Checkable:
   `grep -c "^## Amendment — 2026-10-22 (#10821)" …` → `1`,
   `grep -c "ADR-291" …ADR-245-*.md` → `≥1`,
   `grep -c "Decision item 1" …` → `1`, and the pre-existing count of the set phrase does **not
   increase** (`git grep -c "Grok Build, Codex" …ADR-245-*.md` unchanged from the branch base) —
   an amendment adds no new statement of the set as current.
10. No other ADR names the set as current: `git grep -n "Grok Build, Codex"
    knowledge-base/engineering/architecture/decisions/` returns only ADR-245 and ADR-291, and each
    occurrence is either ADR-245's retained-at-decision-time text or a correct ADR-291 statement.
11. `CONTRIBUTING.md` has an `### OpenCode` subsection naming install, `--check`, bare ids, the
    stay-put requirement, and a link to `opencode/INSTRUCTIONS.md`. Checkable with one multi-pattern
    scan whose every hit is required:
    `grep -niE "install-opencode-adapter|--check|bare|stay put|INSTRUCTIONS.md" …` under the
    `### OpenCode` heading.
12. `plugins/soleur/lib/harness.ts` no longer enumerates harnesses in its header, and the **stale**
    counts are gone:
    `grep -rn "three of four" plugins/soleur/lib plugins/soleur/test` → nothing;
    `grep -rniE "other three harnesses?|[Aa] real change on three harnesses" plugins/soleur/test/components.test.ts`
    → **exactly one** hit remains, in the block that enumerates which three (`devin skills list`,
    `.codex-plugin`, `.grok/config.toml`) and is therefore accurate; the `:1516` "OTHER THREE
    HARNESSES" is reworded to "the other harnesses that load them" and the `:1628` "a real change on
    three harnesses" becomes "a real change on those three harnesses", so neither reads as a total.
    The surviving hit is verified by reading the block, not by pattern alone — universalising it
    would be a new false claim (OpenCode, Cursor and Antigravity do not load those shim trees).
13. Focused suite green: `test/opencode-plugin.test.ts`, `test/opencode-adapter-drift.test.ts`,
    `test/harness-claim-parity.test.ts`, `test/harness-tool-map.test.ts` — **≥ 94 pass / 0 fail**
    (84-case baseline plus the ≥10 new correlation rows).
14. The PR body closes #10819, #10820, #10821, #10822, discloses the overlap-preflight `rc=2` and the
    #10866 C4 gap, and carries a `## Changelog` section; the same disclosures live under a
    `## Disclosures` heading in `tasks.md` so they survive a lost PR body.

## Sharp Edges

- **Do not bind `execute.before` as a blocker.** Measured: it fires before `permission.evaluate`;
  a throw preempts a real `ask`. Capture only.
- **Do not consume on `external_directory`.** It fires first for the same call id.
- **Do not treat an empty-map lookup as "no workdir".** Record a sentinel entry per Bash call; the
  miss means the tool hook did not fire and must be loud.
- **Do not delete on consume.** A retry or re-prompt would fall back to the session directory;
  mark consumed and let the LRU bound the map.
- **`console.error` every degraded path.** The event log is unset by default, so a log-only
  "fail-visible" claim is false in the default configuration.
- **The fixture must carry `input.workdir`.** A fake permission event cannot test this fix; the
  value is not on that event.
- **Do not assert an internal variable.** Read `runs[0].stdin` — the bytes the guard parses.
- **Do not universalise the `components.test.ts` harness-count comment.** Only devin, codex and grok
  load those shim trees; "every other harness" would be a new false claim, and the adjacent "the
  other three harnesses DO resolve these paths" is already scoped by the block that names them.
- **Never `sed -i` the real tree for the mutation check.** Copy `plugins/soleur` to a scratch
  directory, mutate there, run the suite there, discard it; a mutation left behind is a silent
  regression in the diff.
- **An amendment that restates the set increases the count.** Name ADR-291 and the re-entry
  criterion in place; do not re-type "Claude Code, Grok Build, Codex and Devin" as current.
- **Never hand-edit `plugins/soleur/opencode/INSTRUCTIONS.md`.** Regenerate, then `--check`.
- **Run the prose gates after doc edits** (`harness-claim-parity`, `harness-tool-map`, drift), not
  just the file's own test; `CONTRIBUTING.md` is inside the parity scan.
- **Cite ADRs by ordinal + title.** ADR-291's parenthetical lives in §Status, not §Context; ADR-245's
  amendment must not be phrased as if it rewrote the decision.
- **No count that will stale.** "Every other harness" survives the sixth harness; "four" does not.
- **The overlap preflight did not run.** Do not claim the diff is overlap-clear in the PR body.
- **Do not sweep `AGENTS.md`/`AGENTS.rules.md`** while editing comments: `git add -A` in a user repo
  is forbidden by `hr-never-git-add-a-in-user-repo-agents`.

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| Read `workdir` from `permission.evaluate.metadata` | Measured: no workdir key on that event; `source` carries only `type`/`messageID`/`id` |
| Bind `tool.execute.before` as the guard itself | Its only refusal is a throw, which preempts the permission `ask` — a denial is not a prompt |
| Patch `INSTRUCTIONS.md` directly for #10820 | It is generated and drift-gated; the next regeneration reverts it |
| Add OpenCode to ADR-245's Decision text in place | Rewrites an accepted record's history; the plan amends with a dated note instead |
| Correct the "four harness" counts to "six" | The next harness addition stales them again; count-free phrasing is the durable fix |
| Fold the C4 gap into this PR | A new external element + view includes is its own architectural change and review; filed as #10866 |

## Out of Scope

- The CLO-signed legal parenthetical re-pin (`TC_VERSION` / `TC_DOCUMENT_SHA` / `LEGAL_DOC_SHAS`) —
  ruled to be its own PR (#10815).
- A CI gate that runs `sync-opencode-adapter.ts --check` against the committed tree — the drift test
  is fixture-based and no workflow runs it on the real tree. Disclosed in the PR body; not fixed here.
- The C4 OpenCode element (#10866).
- OpenCode V1 support.

## Changelog

- fix(opencode): judge shell calls against the per-call `workdir` instead of the session directory
- docs(opencode): name the absent operator-stage approval gate and its fail-closed consequence
- docs(adr): amend ADR-245's supported-harness set with a dated note naming ADR-291
- docs: add the OpenCode contributor path and replace stale four-harness counts with count-free phrasing
