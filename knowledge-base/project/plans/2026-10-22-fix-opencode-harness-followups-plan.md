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
3. **#10821** — ADR-245's supported-harness set still excludes OpenCode, while ADR-291 records the
   OpenCode adapter; both are live records.
4. **#10822** — `CONTRIBUTING.md` documents every harness but OpenCode, and four source comments
   still describe a four-harness world.

Out of scope by explicit ruling: the CLO-signed legal parenthetical re-pin (its own PR, #10815).

## Research Reconciliation — Spec vs. Codebase

The repo research returned gap callouts against the issue text. They are reconciled here rather
than inherited as phase fiction.

| Spec claim | Reality | Plan response |
|---|---|---|
| #10819: `guardEnvelope` at `:183-189`, `decidePermission` at `:272` | Both exist at those anchors; `decidePermission` calls `decideBash(action, { command }, cwd, …)` | Plan cites function and section anchors, not the issue's line numbers |
| #10819: bind `workdir` into `tool_input`/`cwd` at two call sites | `permission.evaluate` carries **no** workdir (measured); the value exists only on `tool.execute.before`, keyed by a call id that `permission.evaluate.source.id` also carries | Fix publishes the value from the deciding hook and correlates by id; it cannot be read at the permission site |
| #10819: "open a relative dangerous path" | The hole is **both** classes: the `ask` is lost *and* the cwd-dependent **deny** is lost | Both are named in `## User-Brand Impact`; the Guard Contract covers the decision |
| #10820: `INSTRUCTIONS.md:109-116` is the limitations section | Limitations are prose paragraphs under `## Hooks and completion`; there is no `## Limitations` heading | Add the paragraph to the generator source (`instructions()`), regenerate, never hand-edit output |
| #10820: the matrix is the only disclosure owed | Three public surfaces already say the gate "refuses rather than approves" on OpenCode (`README.md`, `plugins/soleur/README.md`, `docs/pages/getting-started.njk`), and `skills/operator-bootstrap/SKILL.md` states the receipt path with no harness qualification | The new paragraph is scoped to what is actually true (no receipt can be minted here); the SKILL.md gap is filed, not silently absorbed |
| #10821: ADR-291 reconciled §Context | The non-exhaustive parenthetical is in ADR-291 **§Status**, not §Context | Amendment cites ADR-291 by ordinal + title; the parenthetical is quoted from §Status |
| #10821: ADR-245's set is a current claim | ADR-245 is `date: 2026-09-23`, `status: active`; the set appears in **§Context** and **Decision item 1**. ADR-291 §Decision also records `tool.execute.before` as "withdrawn as measured-false" | Amendment is dated 2026-09-23-anchored, scoped to those two clauses, with an inline pointer at item 1; ADR-291 gains a one-paragraph note that a capture-only binding now exists (no decision moves) |
| #10822: `CONTRIBUTING.md` has Grok at `:39`/`:48-63` and Codex at `:23` | Correct, but there is **no** `### Grok Build` heading — Grok is a paragraph inside `### Codex`, and `### Grok command naming` is about command namespaces | Plan inserts `### OpenCode` after the Grok command-naming subsection, before `## Contributor License Agreement`, and adds one routing line above `### Codex` |
| #10822: stale comments at four anchors | All four exist; the `lib/harness.ts` header omits OpenCode **and** Antigravity while the `Harness` union has both; `components.test.ts` has **four** count phrases, not two | Rewrite count-free where it is a total; name the three harnesses where the count is accurate and scoped |
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
- `source.id` on the permission event equals the tool hook's `id`, and `source.messageID` equals the
  tool hook's `messageID`, so the two hooks correlate on either alone or on the pair.
- `external_directory` fires **first** with the same call id — consuming the correlation on any
  action other than the shell decision would lose it before that decision.
- Guard pair run with the production envelope construction (both guards, ordered):
  `cwd=sessionDir` → no output, exit 0 (**allow**); `cwd=workdir` → `ask`,
  rule `recursive-delete-workdir`. The hole is real: a relative destructive command is silently
  allowed whenever `workdir` differs from the session directory.
- The hole is worse than a missing `ask`: the guard's **deny** class is cwd-dependent too ("a bare
  `*` `**` or `./*` when the working directory is home or an ancestor", the rule table's
  `recursive-delete-home` arm). With `workdir=$HOME` and envelope `cwd=<checkout>`, `rm -rf *`
  matches no rule at all and is allowed with no prompt of any class.
- Running the guards with `cwd = workdir` is safe for the credential guard, checked rather than
  assumed: `browser-snapshot-credential-guard.sh` reads `.tool_input.command` and gates on
  `.tool_name` through `hook-tool-kind.sh`; it has **no cwd reference**, so repointing `cwd` cannot
  change its verdict. Both scripts are invoked by absolute path, so the child cwd cannot change
  which script runs.
- **`cwd = workdir` is not verdict-neutral for the destructive guard, and the plan says which way.**
  It prefers the envelope's `cwd` over `CLAUDE_PROJECT_DIR`/`PWD` and reads the default-branch set
  from *that directory's own repository* (`git_ro "$repo" symbolic-ref
  refs/remotes/<remote>/HEAD`, falling back to `main`/`master`). A workdir inside a repository with
  no `refs/remotes/origin/HEAD` therefore narrows that set. Recorded as a residual in
  `## User-Brand Impact`; not changed here.
- **Relative `workdir` resolves against the session directory** — measured, not assumed. The
  session was moved to a worktree while the OpenCode process kept its launch cwd in the bare
  checkout; `shell` with `workdir: "plugins/soleur"` ran in
  `<worktree>/plugins/soleur`, not `<bare>/plugins/soleur`. The two bases were distinct, so the
  base is `location.directory`.
- `effect = "ask"` + `message` is a **real prompt**, measured live (§12.2, quoted in the module
  docblock): the tool stays `running` awaiting a decision. So a decision the plugin cannot compute
  can be escalated to the operator instead of being guessed.

### Property list (Phase 0.6b)

| # | Property | Mechanism that satisfies it |
|---|---|---|
| P1 | A `shell` decision is judged against the directory the command **starts** in — the per-call `workdir` when one was usable, the session directory otherwise | correlate `input.workdir` from `tool.execute.before` into the permission envelope's `cwd` |
| P2 | A capture is never silently absent: every Bash tool call records an entry, with a sentinel when it carries no workdir | entry keyed by `(messageID, id)`; a lookup miss then means "the tool hook did not fire", not "no workdir" |
| P3 | The `external_directory` event never consumes the entry | the handler decides "is this a Bash action" first and returns before touching the map |
| P4 | Correlation never fails open **silently**: every degraded decision `console.error`s a sentence and writes its event-log line | `console.error` because the log file is unset by default, plus the TSV line when it is armed |
| P5 | The generated matrix names the one absent **approval** gate and its consequence, from the generator source | generator paragraph + regenerated output + drift `--check` |
| P6 | Two accepted ADRs cannot disagree about the supported set, and neither can disagree about the hook posture this PR changes | dated, clause-scoped amendments on ADR-245 and ADR-291 |
| P7 | Public/contributor docs name the fifth harness without a count that can stale | CONTRIBUTING subsection + count-free comments |

P5 is deliberately narrowed from "every absent gate": the ledger carries six
`absent-with-reason` rows and this PR discloses one. The other five are named in `## Out of Scope`
so the narrower claim is visible rather than implied away.

### Cut list (Phase 0.6b)

- **Wiring `tool.execute.before` as a blocking guard** — measured to fire before
  `permission.evaluate`; a throw there preempts a real `ask` and re-degrades it to a refusal. The
  binding is **capture-only**.
- **Re-deriving the workdir at the permission site** — impossible (not on the event). Not attempted.
- **A `consumed` flag and an eviction log line** — the only reader would be the eviction notice, and
  the decision-time lookup already announces a lost capture (`cause=no-capture`). Eviction is
  silent; the loud path is the one that fires where a wrong decision could actually be made.
- **A per-call `workdir-correlated` stderr line** — the success path is the common path (the
  generated matrix *tells* agents to set `workdir`); a line per call is noise. Log only.
- **Adding OpenCode to the C4 model** — real pre-existing gap, filed as #10866; not folded in.
- **Legal parenthetical re-pin** — excluded by the CLO ruling; not touched.

### Institutional learnings that bind the fix

- Publish the derived value from the hook that can see it; do not re-derive it at the consumer.
- A correlation test must pin the wire: deleting either side must redden it.
- A bounded map must not silently degrade to "no workdir → proceed"; a lookup miss must be visible
  at the decision, which is where the damage would happen.
- Test fixtures must carry a real `input.workdir`; a fixture without it tests the fallback.
- After any doc/generated edit, run the whole prose-gate set (`harness-claim-parity`,
  `harness-tool-map`, adapter drift), not just the file's own test.

### Related issues and PRs

- #10815 — parent OpenCode claim flip (closed); the four issues here are its follow-ups.
- #10863 — draft PR for this branch.
- #10866 — filed from this plan: C4 model has no OpenCode harness element.
- #10591 (uninstall flag), #10587 (compaction `context` probe).
- #8593 — open `code-review` issue naming `plugins/soleur/test/components.test.ts`; see overlap
  section.

### Repository conventions

- `plugins/soleur/opencode/plugin.ts` is a **source** file for the generator, not generated: edit it
  directly, never add it to a template string.
- `plugins/soleur/opencode/INSTRUCTIONS.md` is generated; edit `scripts/sync-opencode-adapter.ts`
  and regenerate.
- `.claude/hooks/opencode-dispositions.tsv` is the canonical hook ledger: one row per registration,
  every row with a disposition **and** a binding column. A code change that invalidates a row must
  update the row — and its legend, if the row needs a word the legend does not define — in the same
  PR.
- ADRs are immutable records; corrections are dated amendments citing decisions by ordinal + title,
  never by position. A clause that now reads false conventionally gets an inline pointer **at the
  clause** as well as the appended amendment (ADR-084, ADR-199), because readers stop at §Decision.
- Harness claims are gated by `test/harness-claim-parity.test.ts`: name OpenCode explicitly or use
  count-free phrasing.

## Implementation Phases

### Phase 1 — #10819: carry the per-call `workdir` into the guard envelope

**Design (decided; no open technical fork).** `tool.execute.before` is the only surface that sees
`input.workdir`; `permission.evaluate` is the only surface that can block. So the tool hook
**publishes** the value keyed by the call, and the permission hook **consumes** it. Ship Phase 1 as
its own commit so a review finding on it cannot hold the three disclosure edits.

1. `plugins/soleur/opencode/plugin.ts`
   - `SetupContext` gains an optional `tool?: { hook(name: "execute.before", handler: (event: ToolBeforeEvent) => Promise<void> | void): Promise<unknown> }`.
     Optional because the plugin must load on a runtime that does not offer it; absence **and a
     rejecting registration** are announced once at setup, not ignored.
   - New `ToolBeforeEvent` (`tool`, `id`, `messageID`, `input` — all `unknown`) and
     `PermissionEvaluateEvent` gains
     `readonly source?: { readonly type?: unknown; readonly id?: unknown; readonly messageID?: unknown }`.
   - New exported **`decidesBash(tool: string): boolean`** = `claudeToolName(tool) === "Bash"`, and
     `guardEnvelope` uses it instead of its own inline comparison. **One predicate decides "is this
     a call the Bash guards see", used by the envelope, the capture, and the consume.** Two
     independent copies of that question is the rot that would silently reopen this hole.
     Consumption is gated on `decidesBash(event.action)`, never on the literal `"shell"` — the
     `bash` alias is exactly why the capture gate already uses the map.
   - New exported `resolveWorkdir(input: unknown, baseDir: string): WorkdirCapture` where
     `WorkdirCapture = { kind: "absent" } | { kind: "usable"; path: string } | { kind: "unusable"; raw: string }`:
     a non-empty string `input.workdir`; relative values resolved against `baseDir` (measured —
     see the measurement record); then `existsSync` + `statSync().isDirectory()` + `realpathSync`,
     so the envelope names the physical directory the shell will `chdir` to rather than
     `path.resolve`'s lexical answer. Any failure is `kind: "unusable"`, not a silent session-dir
     fallback.
   - `createSetup` holds `calls = new Map<string, WorkdirCapture>()`, keyed
     `` `${messageID}\u0000${id}` `` — both fields are measured on both events, and the pair is what
     makes a colliding counter suffix harmless. **Both ids are required**: defaulting a missing one
     to `""` would collapse the key back to the bare counter and let call A's workdir answer call B.
     Bounded FIFO at 500 (`MAX_CALLS`), evicting oldest-first **silently**: a lost capture is
     announced at the decision (`cause=no-capture`), which is the surface where it could change a
     verdict.
   - Bind `ctx.tool?.hook("execute.before", …)` **after** `ctx.permission.hook("evaluate", …)`, and
     wrap registration in `try/catch`: a rejecting `hook()` must not abort `setup` and leave the
     guards unbound. A throw is treated exactly like an absent surface.
   - Handler: type-check `event.tool === "string"` and `decidesBash`; require a non-empty string
     `event.id` (otherwise `console.error` + `soleur-opencode\tworkdir-uncapturable\tid=absent` and
     return — never key the map on `undefined`); then
     `calls.set(key, resolveWorkdir(event.input, sessionCwd))`. **Never throw** — capture-only.
   - **Do not delete on consume** and do not re-insert on consume: the measurement establishes one
     tool event and *two* permission events per call, not that a call is evaluated exactly once, and
     a re-insert would reset recency and re-order eviction. Call keys are not reused within a
     message; the FIFO bounds memory.
   - Permission handler, in order: resolve `action`; **`if (!decidesBash(action)) return;`** before
     the map is touched; resolve one effective cwd:
     - `source.type !== "tool"` or a missing/non-string `source.id` → loud `id=absent` → session dir;
     - no entry → loud `cause=no-capture` (the tool hook did not fire) → session dir;
     - `kind: "absent"` → session dir, silent (the normal path);
     - `kind: "usable"` → `entry.path`, and write `workdir-correlated\tcwd=…`;
     - `kind: "unusable"` → **the guards still run, against the session directory**, and only if
       they decline does the decision become `effect = "ask"` with a message naming the path: their
       cwd-independent classes (a home wipe, an infra destroy, a credential-bearing snapshot, a
       forced push to the default branch) must not be skipped, and an arriving `deny` is never
       relaxed into that prompt.
   - Pass the resolved cwd as the existing `cwd` argument of `decidePermission(action, resources, cwd, …)`
     — **no new parameter**: that value becomes both the envelope `cwd` and the runner cwd inside
     `decideBash`. `guardEnvelope` and both guard scripts change only as stated above.
   - `ScriptRun` gains `error?: string`, filled from `spawnSync`'s `result.error?.code`. `runScript`
     currently discards it, so a cwd that cannot be entered (`EACCES`, `ENOTDIR`, a directory
     removed between the check and the spawn) is reported as a moved checkout and tells the operator
     to re-run an installer that will answer `ok`. `decideBash`'s failure reason branches:
     when `run.error !== undefined`, say the guard's working directory could not be entered and name
     it; the moved-checkout sentence is reserved for a spawn that did happen.
   - Every emitted value that can contain filesystem text (`workdir`, `cwd`, `id`) goes through the
     existing `field()` before it reaches a TSV line.
   - Rewrite the module docblock paragraph that says `execute.before` is "deliberately not bound":
     it is now bound **as a capture**, with the preemption reason retained, and a short invariant
     block stating capture gate = envelope gate, consume gate = `decidesBash(action)`, never delete
     on consume, one entry per Bash call.
2. `plugins/soleur/test/opencode-plugin.test.ts`
   - Extend `fakeContext()` with a `tool` member that captures `tool:execute.before`; add
     `fakeContext({ tool: false })` and `fakeContext({ toolRejects: true })` forms.
   - New suite `workdir correlation`:
     (a) a workdir from the tool hook reaches both the envelope and the runner cwd, and writes
     `workdir-correlated`; (b) no workdir → session dir, no line; (c) workdir equal to the session
     dir → identical envelope, correlated line **present** (pinned, not left to either reading);
     (d) a **relative** workdir resolves against the session dir; (e) a symlinked workdir is
     reported as its realpath; (f) no `source.id` → session dir + stderr + `id=absent`; (g) an id
     with no capture → stderr + `cause=no-capture`; (h) a captured path that no longer exists →
     `effect = "ask"`, message names the path, `workdir-unusable` written, **no guard spawned**;
     (i) `action: "bash"` correlates and is decided (alias); (j) an `external_directory` event with
     the same id does not consume, and the following `shell` event still correlates; (k) two `shell`
     events for one id both correlate (never delete on consume); (l) same `id`, different
     `messageID` → the second call does not inherit the first's workdir; (m) an absent `ctx.tool`
     writes `no-tool-hook-surface` to **stderr** and the log once; (n) a rejecting `tool.hook` does
     the same and the permission handler is still bound and decides; (o) the capture handler
     tolerates a non-object input and a non-string `workdir` without throwing and without mutating
     the event; (p) an arriving `deny` is not relaxed into the unusable-workdir prompt, and the
     guards are still consulted; (q) a non-Bash tool call is not captured at all; (r) two live
     captures are consumed by key, so an out-of-order evaluation still correlates; (s) a guard
     `ETIMEDOUT` is not reported as an unenterable directory; (t) the real `runScript` surfaces
     `spawnSync`'s error code for a missing cwd.
   - Every correlation assertion reads the **bytes handed to the guard** (`runs[0].stdin`), not an
     internal variable.
   - Update the ledger suite: the `tool.execute.before` row today sits in the case named for
     "surfaces that were considered and **rejected**", because it was rejected. Flipping it to
     `bind` in place would leave a green test whose stated claim is false. **Move** the row's
     assertions out of that case and add a named case — "the capture-only binding is recorded as a
     binding, with what it does and does not deliver" — asserting **all three** fields:
     disposition `bind`, binding `ctx.tool.hook("execute.before")`, and a reason containing
     *capture-only*.
3. `.claude/hooks/opencode-dispositions.tsv` — the `tool.execute.before` row changes from
   `absent-with-reason` to `bind`; its **binding column** gains
   `ctx.tool.hook("execute.before")` (the legend says the column names the call site or `-`); its
   reason reads "capture-only: publishes `input.workdir` for the permission hook to consume by call
   key; delivers no decision (a throw here would preempt the real ask)". Because that is a word the
   legend does not define, extend the legend's `bind` line to say the reason states what is
   delivered — a decision, or a capture published for another surface — and add the same value to
   the test's allowed-disposition set in the same edit.

### Phase 2 — #10820: disclose the absent operator-stage approval gate

1. `plugins/soleur/scripts/sync-opencode-adapter.ts` — inside `instructions()`, after the guards
   paragraph, add a paragraph naming `hooks/operator-stage-approval.sh` as **absent**, with the
   consequence and its **scope**:
   - the hook is what mints the digest-bound approval receipt a staged `--apply` consumes, so
     `plugins/soleur/scripts/lib/operator-script.sh`'s `soleur_op_stage_gate` finds no receipt and
     exits **75** (`SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED`);
   - the typed-`yes` fallback is gated on `[[ -t 0 && -t 1 ]] && ! soleur_op_in_agent_harness`, and
     that detector recognises only `CLAUDECODE` / `CLAUDE_CODE_ENTRYPOINT` — **neither is set under
     OpenCode**, so the arm the harness check exists to close is open here whenever the spawned
     shell has a pty. Do not describe the fallback as "a human ran it"; describe it as what it is: a
     terminal confirmation that this harness cannot attribute to a person;
   - the honest summary: **no receipt can be minted on this harness**; a staged `--apply` refuses
     rather than approving, and nothing is approved silently.
2. Regenerate `plugins/soleur/opencode/INSTRUCTIONS.md` with
   `bun plugins/soleur/scripts/sync-opencode-adapter.ts`; never hand-edit.
3. Re-run `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` (expect `opencode-adapter ok`).
4. `.claude/hooks/opencode-dispositions.tsv` — the operator-stage row's evidence gains
   "disclosed in `opencode/INSTRUCTIONS.md` §Hooks and completion" so ledger and matrix agree.
5. **Operator-surface sweep (read-only).** The gate is named on surfaces an operator reaches before
   the matrix: `plugins/soleur/skills/operator-bootstrap/SKILL.md`,
   `plugins/soleur/hooks/hooks.json`, `plugins/soleur/scripts/lib/operator-script.sh`, ADR-264,
   ADR-277, `README.md`, `plugins/soleur/README.md`,
   `plugins/soleur/docs/pages/getting-started.njk`. Sweep with
   `git grep -n "operator-stage-approval\|SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED" -- <those paths>`
   (all paths exist; an unmatched pathspec exits 128 and must not be read as "no matches"). The
   question is falsifiable: **does any surface present the receipt path as harness-neutral, or claim
   OpenCode mints one?** Expected: the three public pages say the gate "refuses rather than
   approves" (consistent); `SKILL.md` states the receipt mechanism with no qualification (a
   contradiction). **No edit to those files in this PR** — the SKILL.md qualifier and the
   `soleur_op_in_agent_harness` recognition gap are filed as their own issue (Phase 2.6), because
   changing an operator gate's identity detection is a different change with its own review.
6. File the tracking issue required by `wg-when-deferring-a-capability-create-a-tracking-issue`:
   `soleur_op_in_agent_harness()` does not recognise `OPENCODE` (the marker `lib/harness.ts` and
   `scripts/emit-decision.sh` already use), so the "a terminal is not evidence of a person" guard
   does not apply on this harness, and
   `skills/operator-bootstrap/SKILL.md` presents the receipt path as unconditional. Cite ADR-264's
   honest-threshold paragraph. Record the issue number in the PR body and in `tasks.md`.

### Phase 3 — #10821: amend ADR-245 (and note the hook posture in ADR-291)

1. **ADR-245** — append `## Amendment — 2026-10-22 (#10821)`, scoped to **Decision item 1** ("The
   supported harness set is Claude Code, Grok Build, Codex and Devin") and to the **§Context**
   sentence beginning "Soleur ships one plugin tree to four supported harnesses". The amendment:
   - records that both are **the set at this record's date (2026-09-23)**, not a current claim;
   - names the superseding record by ordinal and title: **ADR-291, "Add an OpenCode plugin
     adapter"** (accepted), and records that OpenCode **satisfies this record's own re-entry
     criterion**: a `Harness` union member (`opencode` exists) and a generator
     (`sync-opencode-adapter.ts`). It does not claim ADR-291 restates the supported set — it does
     not, and that is why the criterion is the bridge;
   - scopes itself **without restating the four harness names**, so it adds no new statement of the
     set and the record's occurrence count of the set phrase cannot increase;
   - does not rewrite the original text and does not assert a C4 or gate consequence.
2. **ADR-245, inline pointer.** Under Decision item 1's sentence, add
   `*(Amended 2026-10-22 (#10821): the set recorded here is the set at this record's date; ADR-291
   added OpenCode under this record's re-entry criterion. See §Amendment.)*` The original sentence
   is untouched — an annotation, not a rewrite, following the convention the corpus already uses.
   Without it, the reader who stops at §Decision still reads the stale claim, which is the defect
   #10821 reports.
3. **ADR-291** — append `## Amendment — 2026-10-22 (#10819)`, scoped to the §Decision paragraph that
   records the earlier `tool.execute.before` binding as "withdrawn as measured-false". It records:
   the surface is now bound **capture-only** (it publishes `input.workdir` for the permission hook
   to consume by call key); the withdrawal stands for **decisions**, because the only channel there
   is still a throw; and the decision surface's correctness now depends on that capture having
   fired, with the degradation announced (`workdir-uncorrelated`) rather than assumed. Original text
   unchanged.
4. Verified: `git grep -n "Grok Build, Codex" knowledge-base/engineering/architecture/decisions/`
   returns only ADR-245 (**§Context**, **Decision item 1**) and ADR-291 (**§Context**, **§Status**
   parenthetical, the "before this adapter" paragraph). ADR-291's occurrences are correct as
   written — it states the pre-adapter set and calls its own parenthetical non-exhaustive.

### Phase 4 — #10822: contributor path and count-free comments

1. `CONTRIBUTING.md` — one routing line above `### Codex` ("Harness setup: Codex and Grok below,
   OpenCode at the end; Claude Code above"), then a new `### OpenCode` subsection after
   `### Grok command naming`, before `## Contributor License Agreement`. Content:
   - **install for branch work:** `bun plugins/soleur/scripts/install-opencode-adapter.ts --target DIR`
     — lead with `--target`, because the default writes the operator's live `~/.config/opencode` and
     the installer removes attributed stale stubs without prompting, so a worktree run silently
     repoints real sessions at feature-branch code;
   - **verify the install:** `… install-opencode-adapter.ts --check --target DIR`, and what exit 1 +
     `MISSING`/`STALE`/`EXTRA` mean;
   - **what is generated and what is not:** edit `plugins/soleur/opencode/plugin.ts` directly (it is
     never generated); never hand-edit `INSTRUCTIONS.md`, `agents/`, `commands/`, `opencode.json`
     — run `bun plugins/soleur/scripts/sync-opencode-adapter.ts` then `… --check`;
   - **re-install after any edit**, including a regeneration: `--check` validates the committed
     tree, it does not refresh an installed copy, so edited behaviour that "did nothing" is a stale
     install;
   - **no CI job checks this tree** — `--check` before pushing is the only gate, not belt-and-braces;
   - **commands and ids are bare**: `/go`, `/help`, `/sync`, `/version`; skill ids `plan` not
     `soleur:plan`; agents spawn by path id (`engineering/cto`);
   - **the checkout must stay put**: the installed config points at this tree for skills, routing
     rules and guard scripts; moving it makes every guard fail closed (`guard-did-not-run`);
   - **the durable log**: `SOLEUR_OPENCODE_EVENT_LOG=<path>` arms the TSV event log; unset means the
     log is not written and only stderr reports a degraded decision;
   - **verify behaviour**: `cd plugins/soleur && bun test test/opencode-plugin.test.ts`;
   - **the ledger**: a hook disposition change is part of the same PR
     (`.claude/hooks/opencode-dispositions.tsv`);
   - **the absent approval gate**: one line saying a staged `--apply` exits 75 on this harness;
   - link `plugins/soleur/opencode/INSTRUCTIONS.md`.
   The subsection names OpenCode literally (the parity gate's `FOUR_MEMBER_WITHOUT_FIFTH` scan
   covers `CONTRIBUTING.md`).
2. `plugins/soleur/lib/harness.ts` module header docblock — replace the enumerated
   "Claude Code, Grok Build, Codex, Devin CLI, or the Cursor CLI" with "maps Soleur workflow
   invocations to each member of the `Harness` union" (count-free; the union is the authority and
   includes OpenCode and Antigravity).
3. `plugins/soleur/lib/workflow-fidelity.ts` — in the `pipelineInvocationSuffix` docblock, "silently
   on three of four harnesses" → "silently for any caller that forgot it". The paragraph already
   names the caller as the subject, so the sentence ends there instead of replacing one harness
   count with a universal claim about harness behaviour that the file does not establish.
4. `plugins/soleur/test/components.test.ts` — four count phrases, two shapes:
   - "blocked on the OTHER THREE HARNESSES" → "blocked on the harnesses that load them";
   - "a real change on three harnesses" → "a real change on those three harnesses";
   - "the other three harnesses DO resolve these paths" and "the other three do not" → name them:
     "devin, codex and grok DO resolve these paths" / "devin, codex and grok do not".
   **Not** "every other harness": OpenCode, Cursor and Antigravity do not declare those shim roots,
   so a universal claim would introduce a new false statement in a fix for false statements. Naming
   the three is the durable form: the count cannot stale, and the grep that finds "other three" no
   longer finds a near-miss a future reader would "fix". Comments only; no assertion changes.

### Phase 5 — verification and disclosure

1. Focused suite: `cd plugins/soleur && bun test test/opencode-plugin.test.ts
   test/opencode-adapter-drift.test.ts test/harness-claim-parity.test.ts test/harness-tool-map.test.ts`
   (baseline before the change: 84 pass / 0 fail; measured after: **111 pass / 0 fail**, 27 new
   rows — an exact count, because `≥` is also satisfied by deleting cases elsewhere).
2. `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` → `opencode-adapter ok`.
3. `TARGET=$(mktemp -d)`; `bun plugins/soleur/scripts/install-opencode-adapter.ts --target "$TARGET"`,
   then `… install-opencode-adapter.ts --check --target "$TARGET"` → `opencode-install ok`. The
   `--check` arm writes nothing and reports `MISSING` against an empty target, so the install must
   come first; running `--check` on a bare `mktemp -d` reports a false red.
4. Run the C4 suite (`c4-from-components.test.ts`, `c4-count-parity.test.sh`,
   `c4-model-freshness.test.sh`) and expect green, because no component is added — asserted rather
   than waived.
5. Mutation pass, in a **scratch copy** (`cp -a plugins/soleur` under `/tmp`, `sed -i` there, run,
   discard; the real tree is never mutated): the six capture/consume mutations in `## Guard
   Contract`, each shown red with its quoted fail count. If any mutation stays green, the suite is
   vacuous and the phase is not done.
6. PR body discloses: overlap preflight `rc=2` (not checked), C4 gap (#10866), the new tracking
   issue from Phase 2.6, the ADR-291 capture note, the relative-workdir measurement, the
   `cwd = workdir` default-branch narrowing residual, that stderr visibility in the TUI is
   **unmeasured** (the log line is the durable record), and that `plugins/soleur/scripts/` is
   CI-checked only by the fixture-based drift test — no workflow runs
   `sync-opencode-adapter.ts --check` against the committed tree.

## Files to Edit

- `plugins/soleur/opencode/plugin.ts`
- `plugins/soleur/test/opencode-plugin.test.ts`
- `plugins/soleur/scripts/sync-opencode-adapter.ts`
- `plugins/soleur/opencode/INSTRUCTIONS.md` (regenerated)
- `.claude/hooks/opencode-dispositions.tsv`
- `knowledge-base/engineering/architecture/decisions/ADR-245-retire-openhands-gemini-ports-and-prove-codex-devin-discovery-in-ci.md`
- `knowledge-base/engineering/architecture/decisions/ADR-291-add-an-opencode-plugin-adapter.md`
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
  `plugins/soleur/test/components.test.ts`. **Acknowledge:** this plan's edit there is four comment
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
| 5 | `[issue #10820]` "Then the marketing clause can be reduced to a link, as the CLO asked" | — | descoped — justification: the clause lives in the CLO-signed canonicals; its re-pin is #10815 by ruling. This PR creates the link target and says so in the PR body |
| 6 | `[issue #10821]` "Either add OpenCode to ADR-245's set … or mark it explicitly as the recorded state at decision time" | Phase 3.1–3.2 | mapped |
| 7 | `[issue #10821]` "Check whether any other ADR names the harness set the same way" | Phase 3.4 (grep, recorded) | mapped |
| 8 | `[issue #10822]` "Add an OpenCode subsection to CONTRIBUTING: install from the repo root, `--check` for drift, bare command and bare skill ids, and that the checkout must stay put" | Phase 4.1 | mapped |
| 9 | `[issue #10822]` "Correct the four comments, or replace the counts with 'every harness'" | Phase 4.2–4.4 | mapped |
| 10 | `[user directive]` "The CLO-signed legal parenthetical re-pin … remains its own PR, as ruled" | — | descoped — justification: touching the seven canonicals forces `TC_VERSION`/`TC_DOCUMENT_SHA`/`LEGAL_DOC_SHAS` re-pins and its own signature path |
| 11 | `[user directive]` deliver all four in one merged PR | Single PR, Phases 1–5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 correlation (`calls` map, effective cwd) | asks 1–2: "bind `workdir` into `tool_input`/`cwd`" | asked |
| Phase 1 `decidesBash` single predicate | — | inferred — justification: the capture gate and the envelope gate answer the same question; two copies is how a wire-name change reopens the hole at one site only |
| Phase 1 dispositions row | — | inferred — justification: the ledger's row says `tool.execute.before` is "deliberately NOT bound"; shipping the capture leaves a false record the honesty contract forbids |
| Phase 1 `ctx.tool` optional + guarded registration + degradation lines | — | inferred — justification: an absent or rejecting hook surface, or a bounded map that degrades to "no workdir → proceed", silently reintroduces the exact hole |
| Phase 1 unusable-workdir `ask` | — | inferred from the stated property (P1): judging in a directory the operator did not ask about is the defect, so the honest answer is a prompt, and `ask` is a measured channel |
| Phase 1 `runScript.error` | — | inferred — justification: making cwd variable makes an unenterable cwd reachable; without the field the operator is told to re-run an installer that will answer `ok` |
| Phase 2 generator paragraph + regen | asks 3–4 | asked |
| Phase 2.4 ledger evidence cross-reference | — | inferred — justification: #10820 exists because matrix and ledger diverged in what they disclose |
| Phase 2.5 operator-surface sweep | — | inferred — justification: the disclosure is only honest if no faster-reached surface contradicts it |
| Phase 2.6 tracking issue | — | inferred — justification: `wg-when-deferring-a-capability-create-a-tracking-issue`; a PR-body note is not a deferral |
| Phase 3 ADR-245 amendment | asks 6–7: "mark it explicitly as the recorded state at decision time" | asked |
| Phase 3.2 inline pointer | — | inferred — justification: appending alone leaves the clause reading current, which is the defect being fixed |
| Phase 3.3 ADR-291 note | — | inferred — justification: this PR makes ADR-291's "withdrawn" paragraph partially stale; leaving it is a new false record |
| Phase 4.1 CONTRIBUTING subsection | ask 8 | asked |
| Phase 4.2–4.4 comments | ask 9: "replace the counts with 'every harness'" | asked |
| Phase 5 verification | asks 2, 4 | asked |
| Plan/tasks artifacts | — | inferred — justification: `plan` Phase 6 requires the plan on disk and `tasks.md` derived from it |
| #10866 C4 follow-up | — | inferred — justification: a deferral without a tracking issue is invisible |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `knowledge-base`, `.claude`, repo root (`CONTRIBUTING.md`)
- Planned files: 13 (11 edit + 2 create) | Estimated changed lines: ~300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **single PR** — over the subsystem-root threshold by one, under both others. The
  operator's stated objective is one merged PR closing #10819–#10822; three of the four issues are
  disclosure edits in different roots (one file each), and splitting would run four CI cycles and
  four ADR/ledger syncs for one harness concern.
- **Isolation, adopted rather than hypothetical:** Phase 1 lands as its own commit, and Phases 2–4
  depend on nothing in Phase 1. If review finds a defect in the guard change, the disclosure and
  record fixes re-land ahead of it on that seam without waiting for a second review round.
  `tasks.md` carries the seam as executable ordering, not prose.

## Domain Review

### Engineering

CTO consult (Phase 2.5) — **status: concern, no unresolved blocking finding**. The only genuine
technical fork ("read the workdir at the permission site" vs "publish it from the tool hook") is
closed by measurement, so the second is the only implementable shape. Folded: (1) the fail-visible
claim no longer rests on an event log that is off by default — every degraded path
`console.error`s; (2) a sentinel entry per Bash call removes the "no workdir vs lost capture"
ambiguity; (3) the `workdir-correlated` token now has an emitter (log-only, by ruling); (4) the
`components.test.ts` count comment is corrected specifically instead of universalised; (5) Phase 5.3
installs before checking. Advisory findings folded: gate capture and consume through one
`decidesBash`; never delete on consume; pre-check that the workdir exists; update the ledger
assertion; and state what repointing `cwd` does to the destructive guard's default-branch read.

Plan-review panel (7 agents, this revision) folded: the absent-surface degradation becomes stderr;
registration is guarded and ordered after the permission binding; the unusable-workdir path escalates
to `ask` instead of judging in the session directory; relative resolution is measured; the `consumed`
flag and its eviction line are cut; the workdir key carries `messageID`; `source.type` is checked;
`runScript` keeps `spawnSync.error`; the ADR-245 amendment date is the record's date, not a guess;
ADR-291 gains a clause-scoped note; the ledger legend and binding column are updated with the row;
`bind`, not `absent-with-reason`, and the assertion moves out of the rejected-surfaces case; the
operator-surface sweep has real paths and a falsifiable question; the CONTRIBUTING flow gains
re-install, test, ledger and `--target`; `components.test.ts` names the three instead of keeping a
near-miss; and the acceptance criteria stop pinning source shape.

Kept against panel advice, with reasons: the `calls` map rather than a single last-workdir slot
(interleaved calls), the sentinel entry (P2), and the two-channel announce (stderr **and** log).

### Code review round (post-implementation, 4 agents)

`security-sentinel`, `observability-coverage-reviewer`, `test-design-reviewer` and
`code-simplicity-reviewer` reviewed the diff. One P0 and three P1s were real and are fixed:

1. **The new `ask` branch relaxed an arriving `deny`** and skipped the guards entirely — a
   model-controlled `workdir` could have suppressed a credential deny or a home-wipe deny. Fixed:
   the guards run against the session directory on that path, an arriving `deny` is preserved, and
   only their *declining* becomes the prompt. Two tests pin it.
2. **The ask message told the operator to approve** a command the plugin had just said it could not
   check, and understated the scope ("not checked against the session directory" — it was not
   checked at all). Reworded to state the facts and the repair.
3. **A missing `messageID` on both sides collapsed the key** to the bare counter and could hand one
   call's workdir to another. Fixed: both ids are required; absence is loud and uncorrelated.
4. **Model-controlled paths reached stderr and the prompt unescaped**, and a 1 MB `workdir` was
   echoed whole. Fixed: one `clip()` (control characters flattened, length bounded) on every
   operator-facing interpolation, and `announce()` fields its own detail.
5. **`run.error` hijacked the timeout path**, so a 12 s guard timeout was reported as an unenterable
   directory. Fixed: only `EACCES`/`ENOTDIR`/missing-cwd get the directory sentence.
6. **An unwritable `SOLEUR_OPENCODE_EVENT_LOG` rejected `setup`** — taking every hook with it.
   Fixed: the default writer announces once and continues.
7. Missing test arms added: arriving-deny preservation, non-`tool` source, non-Bash capture,
   not-a-directory workdir, `..`, out-of-order captures, `ETIMEDOUT`, real `runScript` error
   extraction, unkeyable capture.

Simplification applied: `existsSync`/`isAbsolute` dropped from `resolveWorkdir` (both redundant), the
unused test option removed, and the three hand-rolled announce pairs routed through `announce`.

### Product

CPO sign-off — **granted** (Phase 2.5), threshold confirmed as `single-user incident`, with four
corrections applied: the false credential-guard vector is removed; the impact statement names the
cwd-dependent **deny** class loss; the placeholder `[data / workflow / money]` is resolved to `data`
with a concrete artifact; and the residual is stated rather than implied away.

Plan-review panel — the second CPO read kept the threshold, corrected the over-claim ("deleted"
→ the working tree and uncommitted work), asked for the human-facing one-liner in CONTRIBUTING
(added, Phase 4.1), and required the SKILL.md / `soleur_op_in_agent_harness` gap to carry an issue
number rather than a PR-body note (Phase 2.6). It did **not** challenge the one-PR scope.

### Legal

Not consulted: no regulated-data surface, no legal claim, and the one legal-adjacent item (the
canonical parenthetical) is explicitly excluded by the CLO ruling.

## User-Brand Impact

**If this lands broken, the user experiences:** a `shell` call that supplies `workdir` is judged
against the session directory because the capture was lost or unusable. That is not merely a missed
`ask`: the destructive guard's **deny** class is cwd-dependent, so `rm -rf *` with `workdir=$HOME`
and envelope `cwd=<checkout>` matches no rule and is allowed with no prompt of any class, and the
recursive-delete `ask` is lost too. The operator's **working tree and everything uncommitted** are
deleted — `rm -rf *` does not match dotfiles, so `.git` and `~/.ssh` survive and the repository is
recoverable from the remote.

**If this leaks, the user's data is exposed via:** no new data path is introduced — the exposure
vector is destruction, not disclosure. A mis-correlated `cwd` changes which paths the destructive
guard recognises as protected (home, its ancestors, the working directory). The credential guard
reads `.tool_input.command`/`.tool_name` and has no cwd-dependent rule, so it cannot be pointed at a
directory. On an absent capture the plan falls back to the session directory and **allows**, exactly
as before the fix: that residual is deliberate (asking every call when the tool surface never existed
would make the harness unusable), it is announced on every occurrence, and it is the pre-fix
behaviour rather than a new one. A *captured but unusable* workdir does not take that residual — it
prompts.

**Residuals this PR introduces or leaves, named rather than implied:**

- **In-command `cd`.** The guard's contract covers the envelope `cwd` and a literal `cd`/`pushd` it
  can see in the command; it does not follow a path built at runtime. `cd $HOME && rm -rf *` is
  judged where the command starts, before and after this change.
- **The destructive guard's default-branch read follows the new `cwd`.** Repointing it at a workdir
  inside a repository without `refs/remotes/<remote>/HEAD` narrows its default-branch set to
  `main`/`master`, so a force-push to another default that was asked about from the session checkout
  is no longer asked. Disclosed here; not changed, because widening it is a guard-script change.
- **stderr visibility is unmeasured.** The plugin's `console.error` is the operator-facing channel by
  construction, but whether the TUI surfaces it was not measured in the probe. Every degraded path
  therefore also writes the TSV line, and the CONTRIBUTING subsection documents
  `SOLEUR_OPENCODE_EVENT_LOG` as the durable record.

**Brand-survival threshold:** single-user incident

## Observability

```yaml
liveness_signal:
  what: "`soleur-opencode\tworkdir-correlated` per shell call that applies a captured workdir, and one of `workdir-uncorrelated id=<id|absent> cause=<source-not-tool|id-absent|message-id-absent|no-capture>`, `workdir-unusable`, `workdir-uncapturable`, `workdir-capture-error` on each degraded decision"
  cadence: "per shell call; plus one `no-tool-hook-surface` at setup when the tool surface is absent or rejects registration"
  alert_target: "none — a local CLI writes to the operator's own stderr and log; the line is the record, not an alert"
  configured_in: "SOLEUR_OPENCODE_EVENT_LOG (unset = no log file; every degraded path still console.errors a sentence)"
  layer: "observability layer 7 `cli-stdout-artifact` — stderr in-session, plus the operator-local TSV file as the durable artifact; no vendor-side sink"
error_reporting:
  destination: "console.error for every degraded correlation (the log file is off by default), plus the event-log line when armed; the success line is log-only"
  fail_loud: true
failure_modes:
  - mode: "a shell decision arrives with ids the capture cannot be keyed by"
    detection: "`[soleur] …` sentence on stderr + `workdir-uncorrelated\tid=…\tcause=source-not-tool|id-absent|message-id-absent`"
    remedy: "the decision falls back to the session directory; if this repeats, the runtime changed the event shape — check the OpenCode version"
  - mode: "call id present but no capture (the tool hook never fired)"
    detection: "`[soleur] …` sentence on stderr + `workdir-uncorrelated\tid=…\tcause=no-capture`"
    remedy: "session directory used — the pre-fix behaviour, deliberately loud; check the OpenCode version and re-run `install-opencode-adapter.ts --check`"
  - mode: "captured workdir cannot be resolved to an existing, real directory (or is a present non-string value)"
    detection: "`[soleur] …` sentence + `workdir-unusable\tcwd=…`; the guards are run against the session directory first, and only their declining becomes `effect = ask`"
    remedy: "re-issue without `workdir`, or create the directory; an arriving `deny` is never relaxed into that prompt"
  - mode: "the capture cannot be keyed (no call id, or no message id, on the tool event)"
    detection: "`[soleur] …` sentence + `workdir-uncapturable\tid=…\treason=id-absent|message-id-absent` at capture time"
    remedy: "the following decision reports `cause=no-capture`; both lines point at the runtime's event shape"
  - mode: "runtime exposes no tool hook surface, or rejects the registration"
    detection: "one `[soleur] …` sentence on stderr + `no-tool-hook-surface\tworkdir-unavailable\treason=…` at setup"
    remedy: "every decision uses the session directory, as before the fix; the permission guards remain bound"
  - mode: "the capture threw (containment path; unreachable with the current total helpers)"
    detection: "`[soleur] …` sentence + `workdir-capture-error\treason=…`"
    remedy: "the shell call is judged in the session directory and the guards still run; report the text"
  - mode: "a guard script cannot run (moved checkout, unenterable cwd, timeout, spawn error)"
    detection: "existing GUARD_RUN_FAILURE deny path; `ENOENT`/`ENOTDIR`/`EACCES` (or a cwd that does not exist) name the unenterable directory, `ETIMEDOUT`/`ENOBUFS` keep the checkout sentence"
    remedy: "create the directory or re-issue without `workdir` for a directory fault; re-run the installer for a moved checkout; retry for a timeout"
logs:
  where: "the file named by SOLEUR_OPENCODE_EVENT_LOG (operator-chosen; its parent directory must exist; unset means no log file)"
  retention: "operator's filesystem policy; not a hosted log sink"
discoverability_test:
  command: 'grep -c "decidesBash" plugins/soleur/opencode/plugin.ts'
  expected_output: "5"
```

## Architecture Decision (ADR/C4)

No new architectural decision. The plan **amends two existing ADRs** (Phase 3) because both records
now describe a harness set or a hook posture that this repo no longer has — not because a decision
changes. ADR-291 already made the adapter decision; this PR records its consequence.
`wg-architecture-decision-is-a-plan-deliverable` is satisfied by delivering both amendments here.

### C4 views

No C4 impact from this change, checked against all three model files **and** run through the C4
suite rather than waived:

- **External human actors** — founder/operator, product end user, support persona: none added,
  removed, or re-scoped.
- **External systems/harnesses** — `codex`, `devin`, `grokBuild`, `cursorCli` are modeled as
  external harnesses with delivery edges to `platform.plugin`. **`opencode` is not modeled** (a
  pre-existing gap from ADR-291, not created here). This plan adds no element and no edge; it
  changes the plugin carrier's internals only. Tracked as #10866 rather than asserted complete.
- **Containers/data stores** — no container, no store, no network connection is added or changed.
- **Access relationships** — no relationship changes: the harness still loads the same plugin tree.

No `.c4` edit is required. `c4-from-components.test.ts`, `c4-count-parity.test.sh` and
`c4-model-freshness.test.sh` are run in Phase 5.4 and expected green, because no component is added.

## Guard Contract

### Guard 1 — workdir correlation in the Bash guard envelope

**Property.** A `shell` permission decision is judged against the directory the command **starts**
in — the per-call `workdir` when one was usable, the session directory otherwise — and never against
the session directory when a different, usable `workdir` was supplied.

**Assembly.** Two hook surfaces, one chokepoint each. `tool.execute.before` is the **only** surface
carrying `input.workdir`; it records `calls.set(key, resolveWorkdir(input, sessionCwd))` for every
call for which `decidesBash` holds — including the sentinel when there is no workdir. Every
`permission.evaluate` for a Bash action flows through the single handler in `createSetup`, which
resolves one effective cwd from `event.source` and passes it as `cwd` to `decidePermission` — the
same value becomes the envelope `cwd` and the runner cwd inside `decideBash`, for **both**
`BASH_GUARDS`. There is no second envelope constructor and no other cwd writer. `external_directory`
events reuse the same call id and cannot consume the entry, because they fail `decidesBash` and the
handler returns before touching the map.

| # | Mutation (must drive the guard RED) | Why it is derivable from the design | Observed red |
|---|--------------------------------------|--------------------------------------|--------------|
| 1 | Delete the capture write in `execute.before` (`recordCall`) | The only source of the value; P1 cannot hold | (a) and 8 others |
| 2 | Ignore the map in the consume (always `sessionCwd`) | The property is about the decision, not the capture | (a) and 8 others |
| 3 | Gate the consume on the literal `"shell"` instead of `decidesBash` | The `bash` alias then captures and never consumes — a silent fallback | (i), alone |
| 4 | Delete the entry **before** the action gate, so a non-Bash event consumes it | `external_directory` fires first with the same call id, so the capture is gone before the decision | (j) and (k) |
| 5 | Delete the entry on consume (after the read) | A second evaluation for the same call falls back to the session directory | (j) and (k), alone |
| 6 | Record an entry only when a workdir is usable (drop the sentinel) | A lookup miss becomes indistinguishable from "no workdir" — the normal path turns into a false alarm | (b) and (h) |

**Harness rows.**

| # | Edit to the suite (must drive it RED) or must-PASS input | Why |
|---|----------------------------------------------------------|-----|
| H1 | Remove `input.workdir` from the fixture | Proves the fixture carries the real wire field, not a stand-in |
| H2 | Assert a local variable instead of `runs[0].stdin` | Proves the test reads the bytes the canonical guard parses |
| H3 | **Must PASS:** workdir equal to the session directory | A guard that rejects everything cannot pass this |
| H4 | **Must PASS:** no workdir at all | Unchanged pre-fix behavior is a permitted input |
| H5 | **Must PASS:** `action: "bash"` with a captured workdir | The alias must decide *and* correlate |

**Anchor.** The guard scripts are canonical and **unmodified** by this change; the assertions read
the envelope bytes handed to them. A weakening therefore has to change the bytes the canonical
script parses (or the script itself, which no diff in this PR touches), not an internal belief the
suite could be edited to match. The `decidesBash` predicate, the tool-name map and the dispositions
ledger are independent surfaces that also name the bound hook.

## Acceptance Criteria

1. `plugins/soleur/opencode/plugin.ts` correlates `input.workdir` from `tool.execute.before` into
   the envelope `cwd` used by both Bash guards, keyed by `(messageID, id)`, with a sentinel entry
   for calls that carry no workdir, and with one `decidesBash` predicate answering "is this a Bash
   call" for the envelope, the capture and the consume. Proven by the behaviour in AC2 and the
   mutation pass in AC3; **no source-shape grep is an acceptance criterion** — an implementation
   detail that survives a rename is not a property.
2. A unit test asserts the **envelope bytes** (`runs[0].stdin`) carry `cwd === workdir` and that
   `workdir-correlated` was written; a second asserts `cwd === sessionDir` on the sentinel path with
   no degradation line; a third asserts a **relative** workdir resolves against the session
   directory and a symlinked one is reported as its realpath.
3. Each of the six Guard Contract mutations reddens the suite in a scratch copy, with the quoted
   fail count recorded in the PR body; the real tree is never mutated for this check.
4. **Degraded-correlation paths, one assertion each:** a non-`tool` source, a missing call id, and a
   missing message id each `console.error` a sentence **and** write `workdir-uncorrelated` with
   their own `cause=` **and** fall back to the session directory; a captured-but-unusable workdir
   (missing, not-a-directory, or a present non-string value) runs the guards against the session
   directory and, only if they decline, sets `effect = "ask"` naming the path and writes
   `workdir-unusable`; an arriving `deny` is **not** relaxed into that prompt; an absent **or
   rejecting** `ctx.tool` writes `no-tool-hook-surface` with its `reason=` to stderr **and** the log
   once, and leaves the permission handler bound; an unkeyable capture writes `workdir-uncapturable`
   with `reason=id-absent|message-id-absent`.
5. The ledger suite asserts **all three** fields of the `tool.execute.before` row — disposition
   `bind`, binding `ctx.tool.hook("execute.before")`, reason containing *capture-only* — in a case
   named for the binding, not inside the case named for rejected surfaces; the legend defines what
   `bind` means when the row delivers a capture rather than a decision.
6. `plugins/soleur/opencode/INSTRUCTIONS.md` names `hooks/operator-stage-approval.sh` as absent with
   the `exit 75` consequence, the scoped `tty-ack` statement (the harness detector does not
   recognise OpenCode), and "no receipt can be minted here"; it is regenerated from
   `plugins/soleur/scripts/sync-opencode-adapter.ts`. Checkable:
   `grep -c "operator-stage-approval"` and `grep -c "SOLEUR_BOOTSTRAP_APPROVAL_REQUIRED"` are each
   ≥1 in **both** the generated file and the generator (a match only in the generated file means it
   was hand-edited and the next regen reverts it).
7. The operator-surface sweep ran over the eight named paths with `rc=0`, its question ("does any
   surface present the receipt path as harness-neutral?") answered in writing, and the SKILL.md /
   `soleur_op_in_agent_harness` gap carries an issue number in the PR body and `tasks.md`.
8. `bun plugins/soleur/scripts/sync-opencode-adapter.ts --check` exits 0 with `opencode-adapter ok`.
9. ADR-245 carries (a) `## Amendment — 2026-10-22 (#10821)` scoped to Decision item 1 and the
   §Context sentence, naming ADR-291 by ordinal and title, citing ADR-245's own re-entry criterion,
   **without restating the four harness names**, and (b) an inline `*(Amended 2026-10-22 (#10821)…)*`
   pointer beneath item 1's sentence, with the original text unchanged. ADR-291 carries
   `## Amendment — 2026-10-22 (#10819)` recording the capture-only binding and stating that the
   withdrawal stands for decisions. Checkable: `grep -c "^## Amendment — 2026-10-22"`
   → `1` in ADR-245 and `1` in ADR-291; `git grep -c "Grok Build, Codex"` in **both** files is
   unchanged from the branch base (an amendment adds no new statement of the set as current).
10. No other ADR names the set as current: `git grep -n "Grok Build, Codex"
    knowledge-base/engineering/architecture/decisions/` returns only ADR-245 and ADR-291, and each
    occurrence is either ADR-245's retained-at-decision-time text or a correct ADR-291 statement.
11. `CONTRIBUTING.md` has an `### OpenCode` subsection covering install **and re-install**,
    `--check`, bare commands/ids/skill ids, the stay-put requirement, the test command, the ledger
    obligation, `SOLEUR_OPENCODE_EVENT_LOG`, the absent approval gate, and a link to
    `opencode/INSTRUCTIONS.md`. Checkable with a heading-bounded scan
    (`awk '/^### OpenCode/,/^## Contributor License Agreement/'`), each pattern ≥1: install script,
    `--check`, `bare`, `stay put`, `re-install`, `bun test`, `opencode-dispositions.tsv`,
    `SOLEUR_OPENCODE_EVENT_LOG`, `exit 75`, `opencode/INSTRUCTIONS.md`.
12. `plugins/soleur/lib/harness.ts` no longer enumerates harnesses in its header;
    `grep -rniE "three of four|other three harness" plugins/soleur/lib plugins/soleur/test` returns
    **one** hit — the detector's own pattern in `test/harness-claim-parity.test.ts` — and no comment
    or string states a four-harness total (the `components.test.ts` comments name devin, codex and
    grok instead of counting).
13. Focused suite green with an **exact** count: 84 baseline + 27 new rows = **111 pass / 0 fail**
    across `test/opencode-plugin.test.ts`, `test/opencode-adapter-drift.test.ts`,
    `test/harness-claim-parity.test.ts`, `test/harness-tool-map.test.ts`.
14. The PR body closes #10819, #10820, #10821, #10822, carries a `## Changelog`, and discloses the
    overlap-preflight `rc=2`, the #10866 C4 gap, the new tracking issue, the ADR-291 note, the
    relative-workdir measurement, the default-branch narrowing residual, and that stderr visibility
    is unmeasured. The same disclosures live under a `## Disclosures` heading in `tasks.md` so they
    survive a lost PR body.

## Sharp Edges

- **Do not bind `execute.before` as a blocker.** Measured: it fires before `permission.evaluate`;
  a throw preempts a real `ask`. Capture only.
- **Do not gate capture and consume differently.** One predicate (`decidesBash`); a literal
  `"shell"` on one side is how the `bash` alias silently keeps the hole.
- **Do not consume on `external_directory`.** It fires first for the same call id.
- **Do not treat an empty-map lookup as "no workdir".** Record a sentinel entry per Bash call; the
  miss means the tool hook did not fire and must be loud.
- **Do not delete on consume, and do not re-insert on consume.** The first loses a retry's capture;
  the second silently re-orders the FIFO.
- **Do not fall back to the session directory when a workdir *was* captured but is unusable.** That
  is the one case where the operator asked for a different directory and can be told; `ask` is a
  measured channel.
- **A captured workdir that cannot be used must not skip the guards.** Run them against the session
  directory, and let only their declining become the prompt. Skipping them would suppress the
  cwd-independent denies — a home wipe, an infra destroy, a credential-bearing snapshot — exactly
  where the plugin has admitted it cannot vouch for the directory.
- **Never relax an arriving `deny` into that prompt.** The file's own invariant ("an arriving deny is
  never relaxed to an ask") has to hold on every branch, including the new one.
- **Key on both ids, never on the counter alone.** Defaulting a missing `messageID` to `""` lets two
  concurrent messages share a key and hands one call's workdir to the other — silent, and in the
  allow direction.
- **A timeout is not a directory fault.** `ETIMEDOUT`/`ENOBUFS` keep the checkout sentence; only
  `EACCES`/`ENOTDIR` and an `ENOENT` with a missing cwd may say the directory is unenterable.
- **`console.error` every degraded decision**, and write the log line too — the log is unset by
  default, so a log-only claim is false in the default configuration; stderr visibility in the TUI
  is unmeasured, so neither channel alone is enough. An unwritable log path must not reject `setup`.
- **Keep the success line quiet.** `workdir-correlated` is log-only. The generated matrix tells
  agents to set `workdir`, so the success path is the common one, and a stderr line per call is
  noise that trains the operator to ignore the loud ones.
- **The fixture must carry `input.workdir`.** A fake permission event cannot test this fix; the
  value is not on that event.
- **Do not assert an internal variable.** Read `runs[0].stdin` — the bytes the guard parses.
- **Name the three harnesses; never count them.** "devin, codex and grok load these trees" survives
  the sixth harness and cannot be "fixed" into a false universal by the next reader.
- **Never hand-edit `plugins/soleur/opencode/INSTRUCTIONS.md`.** Regenerate, then `--check`.
- **Run the prose gates after doc edits** (`harness-claim-parity`, `harness-tool-map`, drift), not
  just the file's own test; `CONTRIBUTING.md` is inside the parity scan.
- **Cite ADRs by ordinal + title.** ADR-291's parenthetical lives in §Status, not §Context; ADR-245's
  amendment must not be phrased as if it rewrote the decision, and its date is the record's
  (`2026-09-23`), not the amendment's.
- **Do not restate the harness set inside an amendment.** Quoting it increases the occurrence count
  the acceptance criterion holds steady, and re-typing it is how the stale claim outlives the fix.
- **Never `sed -i` the real tree for the mutation check.** Copy `plugins/soleur`, mutate the copy,
  run there, discard.
- **`CLAUDE_PROJECT_DIR` now equals the workdir for the guard spawn.** Neither current guard reads
  it as a project root (both checked), but a future guard that does must not assume it points at the
  checkout — the envelope `cwd` is the operator's requested directory, and that is the point.
- **The overlap preflight did not run.** Do not claim the diff is overlap-clear in the PR body.
- **Do not sweep `AGENTS.md`/`AGENTS.rules.md`** while editing comments: `git add -A` in a user repo
  is forbidden by `hr-never-git-add-a-in-user-repo-agents`.

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| Read `workdir` from `permission.evaluate.metadata` | Measured: no workdir key on that event; `source` carries only `type`/`messageID`/`id` |
| Bind `tool.execute.before` as the guard itself | Its only refusal is a throw, which preempts the permission `ask` — a denial is not a prompt |
| A single "last workdir" slot instead of a map | Interleaved calls would inherit each other's directory; the map is the same two lines |
| Keep a `consumed` flag and log unconsumed evictions | Its only reader would be the eviction notice, and the decision-time `no-capture` line already reports a lost capture where it could change a verdict |
| Judge in the session directory when the captured workdir is unusable | It is the defect this PR fixes, applied to the case where the operator explicitly asked for another directory; `ask` is available and measured |
| Extract `lib/guard-envelope.ts` for the next harness | One consumer today; the contract that needs to survive is the predicate and the invariant block, not the envelope constructor. Revisit on the second carrier |
| Patch `INSTRUCTIONS.md` directly for #10820 | It is generated and drift-gated; the next regeneration reverts it |
| Add OpenCode to ADR-245's Decision text in place | Rewrites an accepted record's history; the plan amends with a dated note plus an inline pointer |
| Correct the "four harness" counts to "six" | The next harness addition stales them again; naming the three that load the trees is durable |
| Fold the C4 gap into this PR | A new external element + view includes is its own architectural change and review; filed as #10866 |

## Out of Scope

- The CLO-signed legal parenthetical re-pin (`TC_VERSION` / `TC_DOCUMENT_SHA` / `LEGAL_DOC_SHAS`) —
  ruled to be its own PR (#10815).
- A CI gate that runs `sync-opencode-adapter.ts --check` against the committed tree — the drift test
  is fixture-based and no workflow runs it on the real tree. Disclosed in the PR body. Filing it as
  its own issue is optional; the disclosure is required.
- `soleur_op_in_agent_harness()` not recognising `OPENCODE`, and the harness-neutral receipt
  wording in `skills/operator-bootstrap/SKILL.md` — filed as its own issue in Phase 2.6.
- **The other five `absent-with-reason` ledger rows** (canonical loader additions, the user-visible
  `systemMessage` hooks, and `bare-root-cwd-guard.sh`) remain undisclosed in the matrix. This PR's
  P5 claims one gate, not six.
- The destructive guard's default-branch set narrowing under a repointed `cwd` (named as a residual
  in `## User-Brand Impact`).
- The C4 OpenCode element (#10866).
- OpenCode V1 support.

## Changelog

- fix(opencode): judge shell calls against the per-call `workdir` instead of the session directory
- docs(opencode): name the absent operator-stage approval gate and its fail-closed consequence
- docs(adr): amend ADR-245's supported-harness set and ADR-291's hook posture with dated, clause-scoped notes
- docs: add the OpenCode contributor path and replace stale harness counts with named or count-free phrasing
