# Prose drafts — feat-one-shot-8288-reproduce-bug-red-loop

Produced by the deepen-plan prompt-engineer pass (2026-09-19) for the work phase to paste. Corrections already applied on top of the agent's draft: the cleanup grep carries `--untracked`, no `-I`, and the `knowledge-base/**/*.md` exclusion (plan R47/R48); the label command follows the `scheduled-terraform-drift.yml` precedent with no `--force` (R65). Still to add when pasting, per the plan: the Phase 2 Redact paragraph's two extensions (fixture-from-trace synthesized/redacted; Phase 8 body + `--cmd` through `redact-engine.py`, R56/R57), the "environment access is non-shell only" clause (R72), the HAR redaction clause, the Phase 6 payload rule (R58), and the Phase 9 "no production payload" checkbox. Every agent/skill reference must stay canonical (ADR-226). Attribution comments go between the frontmatter close and the `<!-- soleur-cloud-mode:start -->` line.

---

Draft text follows, in paste order. Imported peer sentences are verbatim; every sentence that differs from the peer is Soleur's composition and is listed in the conflicts section at the end.

## (1) `reproduce-bug` — Phase 2

```markdown
## Phase 2: Build a feedback loop

**This is the skill.** Everything else is mechanical. If you have a **tight** pass/fail signal for the bug (one that goes red on _this_ bug), you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume it. If you don't have one, no amount of staring at code will save you.

**Redact.** This phase has you show commands, outputs and captured artifacts. **Redact every secret first**: write `<REDACTED>` in its place. Build loops against env vars, so the credential stays in the environment rather than in what you show. Captured artifacts carry auth headers: quote only the lines that carry the signal.

**Completion criterion: a tight loop that goes red.** Phase 2 is done when you can name **one command** (a script path, a test invocation, a curl) that you have **already run at least once** (show the invocation and its output, redacted), and that is:

- [ ] **Red-capable**: it drives the actual bug code path and asserts the **user's exact symptom**, so it can go red on this bug and green once fixed. Not "runs without erroring"; it must be able to _catch this specific bug_.
- [ ] **Deterministic**: same verdict every run (flaky bugs: a pinned, high reproduction rate, per below).
- [ ] **Fast**: seconds, not minutes.
- [ ] **Agent-runnable**: you start everything the loop needs yourself — a dev server (backgrounded, then wait on the port with an until-loop), fixtures, containers — and never ask the founder to start a server or paste output (`hr-exhaust-all-automated-options-before`).

If you catch yourself reading code to build a theory before this command exists, **stop: jumping straight to a hypothesis is the exact failure this skill prevents.** **No red-capable command, no Phase 5.**

**When you genuinely cannot build a loop.** Stop and say so explicitly. List what you tried, rung by rung. Then take the first option that applies; each is a decision with a default, and the default is option 1:

1. **Add instrumentation (default).** Where a loop will follow once the signal exists, add a temporary `[DEBUG-<hex4>]` probe (Phase 6 spelling) and build the loop on its output. Where the failure lives on a blind production surface, apply Phase 1's blind-surface bullet: add a permanent `SOLEUR_*` marker so the next occurrence self-reports, write `no loop buildable yet; instrumentation added: SOLEUR_<…>; re-run soleur:reproduce-bug on the next occurrence` into the Phase 8 comment, and end the run.
2. **Environment access.** Name the one environment that reproduces it (staging tenant, seeded database, device) and what you need from it — only when option 1 cannot carry the signal.
3. **A redacted captured artifact** (HAR file, log dump, core dump, screen recording with timestamps). The one data-retrieval ask permitted, and only after the ladder and option 1 are exhausted: a founder's local device state is the one thing no instrumentation can capture.

Headless (one-shot, cloud, no TTY): take option 1 and end with the Phase 8 comment. Never downgrade silently to rung 10. **For a UI bug, Phase 3 is how rung 4 is built — go there and come back before declaring that no loop exists.**

### Ways to construct one, in roughly this order

1. **Failing test** at whatever seam reaches the bug: unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) that drives the UI and asserts on DOM/console/network. Phase 3 builds this rung.
5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay it through the code path in isolation. The Sentry event payload or Better Stack rows you pulled in Phase 1 are a captured trace.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it.
9. **Differential loop.** Run the same input through old-version vs new-version (or two configs) and diff outputs.
10. **Scripted interactive session** via `soleur:agent-browser`. Last resort: when only a full session reaches the bug, the agent drives it — ref-based clicks, captured output fed back into the loop. Never a human clicking.

Build the right feedback loop, and the bug is 90% fixed.

### Tighten the loop

Treat the loop as a product. Once you have _a_ loop, **tighten** it:

- Can I make it faster? (Cache setup, skip unrelated init, narrow the test scope.)
- Can I make the signal sharper? (Assert on the specific symptom, not "didn't crash".)
- Can I make it more deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than no loop; a 2-second deterministic one is tight, a debugging superpower.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not, so keep raising the rate until it's debuggable.

Nothing is posted to the issue in this phase — every line destined for the founder (the command, its redacted output, what you tried, the instrumentation note) is carried to the single Phase 8 comment.
```

## (2) `reproduce-bug` — Phase 5

```markdown
## Phase 5: Hypothesise

Generate **3–5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea. Each hypothesis must be **falsifiable**: state the prediction it makes.

> Format: "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."

If you cannot state the prediction, the hypothesis is a vibe: discard or sharpen it.

Record the set as a table; every row fills every column, and `Verdict` starts `UNKNOWN` (Phase 6 upgrades it; `CONFIRMED` only with the discriminating observation quoted):

| # | Hypothesis (If X is the cause, then …) | Discriminator (what observation decides it, and where it is read) | Verdict |
|---|---|---|---|

**Founder checkpoint, in this turn, without a question tool.** Render the table in symptom language (what the founder would see; never a code path), with `Discriminator` rendered as *"what else you'd see if this is it"*, then continue in the same turn with: *"Here are the 3–5 likeliest causes, ranked; each says what else you would see if it were true. I will test them in this order unless you tell me one is wrong or you saw something that changes the order — proceed / re-rank / add a fact."* Do not call AskUserQuestion and do not wait: the default is your ranking and the founder's reply is an interrupt. **Headless (one-shot, cloud, no TTY):** the Phase 8 comment carries `founder checkpoint not presented (headless); proceeded with the agent's ranking` so the decision is auditable.
```

## (3) `reproduce-bug` — Phase 6 marker block

Peer Phase 4 paragraphs (probe ↔ prediction, one variable, tool preference 1–3) import verbatim above this block; the peer's "Tag every debug log" sentence is replaced by it; the peer's **Perf branch** paragraph follows it verbatim.

```markdown
**Removable probes.** Mint one tag per investigation with `printf '[DEBUG-%04x]\n' $((RANDOM % 65536))` and prefix every debug log with it. Spelling: `[DEBUG-<hex4>]`, exactly four hex characters, never a `SOLEUR_` prefix. Decision rule: the signal dies with the fix → `[DEBUG-<hex4>]`; the signal must outlive the fix (a blind surface, a recurring class) → a permanent `SOLEUR_*` marker via Phase 1's blind-surface bullet. Cleanup is one grep, run in Phase 9 and expected to print nothing: `git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- . ':!knowledge-base/**/*.md'`. In prose write the placeholder `<hex4>`, never a minted tag. Two-class table and rationale: ADR-230.
```

## (4) `reproduce-bug` — Phase 7 bullet

```markdown
- [ ] **Regression seam verdict.** Name the seam where the fix's regression test will exercise the real bug pattern as it occurs at the call site (file + entry point). If the only seam available is too shallow — a single-caller test when the bug needs the chain, a unit that cannot replicate the trigger — write **`no correct seam`** as the finding. If no correct seam exists, that itself is the finding: the architecture is preventing the bug from being locked down. Spawn `soleur:engineering:review:legacy-code-expert` (Task) with this prompt shape:

  ```text
  Change point: <file:entry point>, reached via <call-site chain, outermost → innermost>.
  Minimised repro (Phase 4): `<command>`; files: <list>.
  Seams already rejected as too shallow: <seam — why it cannot replicate the trigger>.
  Return your standard Change Analysis and Recommended Approach: the seam to break, the characterization tests to write first, the safe transformation path.
  ```

  Carry its seam analysis and characterization-test plan into the Phase 8 comment, then label the issue (`<N>` is the number from `$ARGUMENTS`): `gh label create "action-required" --description "Needs a human action" --color "B60205" 2>/dev/null || true; gh issue edit <N> --add-label action-required`. `soleur:operator-digest` reads that label when it runs against this repo (today: Soleur's own), and the digest is where a non-technical founder reads it as **"we cannot yet add an automatic test that keeps this bug from coming back"**; elsewhere it is a labelled issue the agent surfaces at the next session.
```

## (5) `test-fix-loop`

Phase 0, replacing the two `$ARGUMENTS` lines:

```markdown
`--cmd '<command>'` sets the test command and `--max N` the iteration cap; when either is present it wins over the number/command heuristics below (a red-capable command from `soleur:reproduce-bug` usually contains digits). When the caller is `soleur:reproduce-bug`, `--cmd` is its Phase 8 red-capable command, already committed in its Phase 9 — the loop iterates on the user's symptom, not on a proxy. Otherwise: if `$ARGUMENTS` contains a custom test command, use it instead of auto-detection; if it contains a number, use it as max iterations (default: 5).
```

§4, immediately before the checkpoint commit line:

```markdown
Before the checkpoint commit run `git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- . ':!knowledge-base/**/*.md'`; it must print nothing. On output, remove the probes and re-run the suite before committing — a probe removal is not a fix and never checkpoints as one (ADR-230).
```

§4, the "All pass" evaluation line becomes:

```markdown
- All pass (`rc` 0): run the same probe grep; on output, remove the probes, re-run the suite, and stage only when the grep is silent and `rc` is still 0. Then `git add -A`, report success, STOP
```

Diagnostic Report › Recommendation, appended:

```markdown
CIRCULAR or NON_CONVERGENCE on one cluster is an architecture signal, not a fix signal: recommend `soleur:engineering:review:legacy-code-expert` for that cluster's seams and characterization tests before another loop. Likewise when a fix landed but no existing test asserts the behaviour it changed — this loop never writes tests, so name the agent that should.
```

Key Principles, one bullet: `- Probes are not fixes -- a \`[DEBUG-<hex4>]\` line never checkpoints or stages (ADR-230)`

## (6) `ship` Phase 5 checklist, one line in the text block

```text
- [ ] No removable probe in the tree: `git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- . ':!knowledge-base/**/*.md'` prints nothing (ADR-230)
```

## Conflicts between peer text and Soleur rules (each resolved in the draft as composition, not import)

1. **Peer Redact, last sentence** — *"If the redacted output is not enough to diagnose the bug, say so and ask the user."* Dropped. It routes to the founder for data retrieval, against `hr-no-dashboard-eyeball-pull-data-yourself` and Phase 1's "the operator's role is DECISIONS, not data retrieval". The "cannot build a loop" ladder is the replacement.
2. **Peer "cannot build a loop"** — asks the user for (a) access, (b) artifact, (c) *permission* to add production instrumentation. The draft inverts the order and removes "permission": Phase 1's blind-surface bullet already instructs adding a `SOLEUR_*` marker unasked (it ships via PR, so `hr-menu-option-ack-not-prod-write-auth` is not engaged). Options 1–3 are Soleur's sentences.
3. **Rung 10 and checkbox 4** cite `scripts/hitl-loop.template.sh` (a human clicking, driven by a script). Not imported per the plan; both rewritten against `hr-exhaust-all-automated-options-before`. Rung 10 in the draft is therefore *not* peer prose — the NOTICE paragraph should not claim it as adopted verbatim.
4. **`[DEBUG-a4f2]`** — the peer's example tag is replaced by the mint command and `<hex4>` placeholder (D3). The draft contains no concrete tag anywhere.
5. **Peer motivational line** — *"Spend disproportionate effort here. Be aggressive. Be creative. Refuse to give up."* Omitted: three vague qualifiers with no executable constraint; "List what you tried, rung by rung" plus the four checkboxes is the measurable form. Restoring it is a faithful import (~90 B) if the work phase prefers completeness over the qualifier rule.
6. **Peer opener** — *"read `CONTEXT.md` (if it exists)"* has no Soleur counterpart (knowledge-base is the context store); not carried.
7. **Peer Phase 3 "proceed if the user is AFK"** — compatible; composed as the no-question-tool rule rather than imported, because "AFK" is not detectable headlessly and the plan wants the headless case written into the Phase 8 comment.

## Budget flag

The Phase 2 draft is about 4.4 KB, not 1.5–2 KB. The faithful ladder alone is 1.3 KB and the four checkboxes 0.7 KB, so 2 KB is unreachable without paraphrasing imported sentences. `reproduce-bug` is not in the ADR-229 ratchet (plan Premise table, row at line 51 of the plan), so nothing measures it; if the work phase still wants it shorter, the only faithful cuts are the "Build the right feedback loop, and the bug is 90% fixed" sentence and the Tighten closing sentence (~250 B together).

## Verification cases for the work phase

- Happy: server-side issue, Sentry names the error → rung 1 test goes red, Phase 5 table has four filled columns, `gh issue comment` appears exactly once, in Phase 8.
- Edge: UI bug with no unit seam → the agent enters Phase 3 before writing "no loop"; grep the transcript for "Phase 3" preceding any "cannot build".
- Failure (headless): no loop buildable → option 1 taken, Phase 8 comment carries both the `no loop buildable yet; instrumentation added: SOLEUR_…` line and `founder checkpoint not presented (headless)`, no AskUserQuestion call, no `soleur:agent-browser` fallback.
- Gate: a tracked file containing `[DEBUG-ABCD]` → `test-fix-loop` refuses the checkpoint and the `ship` checklist line stays unticked; a file containing `SOLEUR_DEBUG_X` → Guard 4 fails, per D3.

Files read: `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8288-reproduce-bug-red-loop/knowledge-base/project/plans/2026-09-19-feat-reproduce-bug-red-loop-tagged-instrumentation-bite-proof-plan.md`, `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8288-reproduce-bug-red-loop/plugins/soleur/skills/reproduce-bug/SKILL.md`, `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8288-reproduce-bug-red-loop/plugins/soleur/skills/test-fix-loop/SKILL.md`, `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8288-reproduce-bug-red-loop/plugins/soleur/skills/ship/SKILL.md` (Phase 5 only), and the peer file. Nothing written.
