---
title: "feat: compaction-aware session hooks — evidence-based fresh-session gate"
date: 2026-09-18
slug: feat-compaction-aware-session-hooks
branch: feat-compaction-aware-session-hooks
issue: 8323
closes: 8323
type: feat
lane: cross-domain
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

> **Superseded in part, 2026-09-18 (#8323 Phase 0):** the paragraphs below describe the compaction
> signal as read from the transcript at `SessionStart:compact`, and the `SessionStart` binding as
> matcher `compact`. Both are false in what shipped — the boundary is not yet on disk at that
> moment (measured twice) and the matcher is `startup|resume|clear|compact`. The operative
> description is `## Addendum — 2026-09-18 (Phase 0 payload probe: measured results)` at the foot
> of this file, and ADR-227. Left standing rather than rewritten: this is the reasoning the probe
> was designed to test, and deleting it would delete the evidence for why the probe was blocking.

Soleur's "run `/clear` and resume" advice is unconditional prose in `plan` and `work`; it cannot see whether context compaction happened, how often, or in which phase. Claude Code records every compaction in the session transcript as a `compact_boundary` record carrying `compactMetadata.{trigger, preTokens, postTokens}`, and the `SessionStart` hook with matcher `compact` receives that transcript's path and injects model-visible context verbatim after the summary.

This plan ships **one plugin-owned bash hook, bound twice** (`SessionStart:compact` and `PreCompact`) in `plugins/soleur/hooks/hooks.json`: after a compaction it injects a short re-read directive and, on the second auto-compaction of the session, recommends continuing in a fresh session; before a compaction it tells the summarizer which resume identifiers to keep verbatim. The unconditional `/clear` prose is then retired in favour of that signal.

**This plan was cut roughly in half by a six-agent review panel.** The `PostCompact` checkpoint writer, its gitleaks guard, the token-ratio clause and the phase-derivation mechanism are all **deleted** — see `## Review Cuts` for the evidence, and `## Deferred` for what became its own issue.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
|---|---|---|
| `#8323` (work target) | `gh issue view 8323 --json state` | **OPEN** — valid target |
| PR `#8320` | `gh pr view 8320 --json state,isDraft` | **OPEN, draft** — this branch's draft PR |
| `#8172` (Devin `PostCompaction` probe) | `gh issue view 8172 --json state` | **CLOSED** without a positive `PostCompaction` measurement — the "unmeasured" caveat is stale-but-accurate, not resolved |
| Upstream `anthropics/claude-code#14258` | `gh issue view` | CLOSED 2026-08-17; `PostCompact` shipped v2.1.76 ("Added `PostCompact` hook that fires after compaction completes") |
| Local CLI supports it | `claude --version` | **2.1.273** |
| ADR corpus for the mechanism | `git grep -il "compaction\|compact_boundary\|PostCompact\|transcript_path" -- 'knowledge-base/engineering/architecture/decisions/*.md'` | 6 hits, **none** decide a compaction-state mechanism. No rejected-alternative collision. |
| `hooks.json` can carry a `compact` SessionStart matcher | read `plugins/soleur/hooks/hooks.json` | Already binds `startup\|resume\|clear\|compact` to the Codex shim. No `PreCompact`/`PostCompact` key exists in **either** registry. |
| Anything already branches on `source == "compact"` | `grep -rn '"source"' .claude/hooks/*.sh plugins/soleur/hooks/*.sh` | **No.** All three SessionStart scripts fire identically regardless of source. |

**Capability claims verified against live artifacts (not memory):**

- `compact_boundary` shape, read from a real transcript: `{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":1006181,"postTokens":105006,…}}`.
- **`SessionStart` fires after auto-compaction** — measured across 4 transcripts: the `[rules-loader] loaded` lines (emitted only by a SessionStart hook) appear 14 lines after each `"trigger":"auto"` boundary and nowhere else mid-session. Inferential — Phase 0 confirms the literal `source`.
- Compaction frequency here: 8 of 22 recent sessions compacted, 11 boundaries total.
- **Measured performance** (review panel, 31 MB transcript): `grep -c` ≈ **25 ms**. "Bounded reads" was a misnomer — `grep -c` and `grep | tail -1` both scan to EOF; `tac | grep -m1` measured *slower* (20 ms vs 11 ms on 11 MB) because `tac` buffers. The scan is simply cheap; the plan no longer claims boundedness.
- **Sibling worktrees do NOT share a project dir** (one `sessionId` per file). A cross-session-contamination concern was raised and **falsified** by measurement.
- **Boundaries accumulate within one file across `--resume`** (one local file holds 3). An all-time count would pin `recommend=true` forever on a long resumed session — the count must be scoped to this session's window (TR2).
- `session-rules-loader.sh` already fires on `compact` and already injects branch + the rules corpus, so the directive's *marginal* content is small by design.
- `.gitleaks.toml` exists at this repo root and **nowhere under `plugins/soleur/`** — a customer install has no config (and usually no binary).
- `.claude/phase-surface-map.json` `skill_to_phase` holds **16** keys to **5** phases. In the largest local transcript the last `Skill` record is `soleur:preflight`, which is *not* the current phase.

### Property List (Phase 0.6b)

1. After a compaction, the agent re-reads the plan before editing, instead of trusting a paraphrased summary.
2. The operator is asked to continue in a fresh session only when the evidence supports it.
3. The compaction summary retains the identifiers a resume depends on.
4. A non-Claude harness degrades honestly rather than silently claiming the behaviour.

*(The former property "the on-disk resume artifact is never older than the last compaction" was deleted with the checkpoint writer; see `## Review Cuts`.)*

### Cut List (Phase 0.6b, pre-review)

| Mechanism | Property | Why cut |
|---|---|---|
| `PostCompact`-written counter store in the repo | #2 | Needs a `.gitignore` entry the plugin cannot add to a user's repo; `.claude/.session-manifests/<sid>.json` — the obvious host — is repo-side and **overwritten** by `session-rules-loader.sh` on every SessionStart *including* `compact`. |
| Plugin-side copy of `.claude/phase-surface-map.json` | phase naming | Superseded — phase derivation is deleted entirely (see `## Review Cuts`). |
| `SOLEUR_COMPACTION` telemetry marker | measurement | Deferred to **#8324**. The premise that `SOLEUR_*` markers reach Better Stack was false — they terminate in the gitignored `.claude/.rule-incidents.jsonl`. |
| Blocking `PreCompact` (exit 2) | none | Trades a recoverable context loss for a dead session. |

### Value proposition (Phase 0.6c)

A correctness saving, **not quantified at plan time**. What would quantify it: compaction/resume-tagged learnings and `unkept-promise-hook.sh` firings in the 30 days after merge (#8324 measures exactly this). Standing on its own: an 8-of-22 measured compaction rate against prose that fires at fixed points regardless.

### Institutional learnings that constrain this work

| Learning | Constraint |
|---|---|
| `2026-03-04-sessionstart-hook-api-contract.md` | `additionalContext` (not `systemMessage`) is what the model sees; envelope is `hookSpecificOutput.{hookEventName, additionalContext}`. |
| `2026-06-30-posttooluse-skill-additionalcontext-is-the-autonomous-safe-phase-injection-vehicle.md` | Caps at **10,000 chars**; **any non-zero exit other than 2 silently drops the whole JSON output**. Build with `jq -n --arg`; never echo model-controlled strings raw. |
| `developer-experience/2026-04-02-plugin-hook-scope-guard-welcome-hook.md` | **Load-bearing here.** A plugin hook is global; `welcome-hook.sh` gates on a `plugins/soleur` directory check because "without this guard, every project gets a sentinel file." |
| `2026-05-10-claude-code-posttooluse-task-hook-input-shape.md` | Hook payload fields diverge from docs — capture real envelopes, date them in the header. |
| `2026-07-05-declarative-context-injection-pointer-vs-inline-and-frontmatter-hook-traps.md` | Pointers (paths) over inlined bodies; hook-delivered content carries elevated authority framing. |
| `workflow-patterns/2026-09-18-compaction-state-lives-in-the-transcript-not-a-counter-file.md` | This feature's own brainstorm learning. |

### Repo conventions this must follow

- Fail-open from `phase-surface-hint.sh`: `set -uo pipefail` (no `-e`), exit 0 on every path, `SOLEUR_DISABLE_*` kill-switch.
- `hooks.json` calls `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh`; scripts resolve siblings via a `SCRIPT_DIR` `dirname "${BASH_SOURCE[0]}"` idiom.
- **Every sibling plugin hook carries a harness/sentinel early-exit** — `codex-session-start.sh` (`CODEX_THREAD_ID`/`PLUGIN_ROOT`), `devin-session-start.sh` (`DEVIN*`), `welcome-hook.sh` (the `plugins/soleur` sentinel). This hook must too.
- Test precedent: `plugins/soleur/test/unkept-promise-hook.test.sh` — **verified** to exist, and `plugins/soleur/test/*.test.sh` is the first `SUITE_GLOBS` entry in `scripts/test-all.sh`.
- `components.test.ts` has **0** `hooks.json` hits (verified) — binding assertions go in the new suite.
- Fixtures synthesized only (`cq-test-fixtures-synthesized-only`).

## Review Cuts

A six-agent panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO-devex) reviewed this plan at `590a33ea5`. Where the simplification and correctness panels fired on the same scope, the rule is **prefer delete over fix**. Four mechanisms are deleted; the evidence is recorded here so the ADR and any future re-proposal inherit it rather than re-deriving it.

### CUT 1 — the `PostCompact` checkpoint writer + its gitleaks guard. Six-for-six.

- **spec-flow (P0):** nothing reads it. `work/SKILL.md` Phase 0 loads `constitution.md`, `tasks.md` and `spec.md` — **never** `session-state.md`. The block would be write-only: the exact anti-pattern the brainstorm skill's own "write-mostly artifact diagnosis" warns about.
- **architecture (P0):** `one-shot/SKILL.md` step 3 is a **whole-file template write** ("Write the parsed content to … (create if needed)" followed by a complete `# Session State` document containing no marker). Every plan-phase run destroys the hook's block. The hook can respect the skill; the skill cannot respect the hook. The claim that the file is "written only by `one-shot`" was also **false** — `ship`, `work`, `plan`, `review` and `compound` all reference it, and `compound/SKILL.md` *parses* `### Errors`, so it would ingest an elevated-authority machine block.
- **architecture (P1):** `.gitleaks.toml` exists at this repo root and nowhere under `plugins/soleur/`, so on a customer install the guard fail-opens (skips the write) on essentially **every** install — the property would never ship to the population it ships to.
- **Kieran (P0):** the prescribed command could not do the job. `gitleaks git --pre-commit --staged` reads the git index, not a string; the correct form is `gitleaks stdin -c "<config>"`, and omitting `-c` silently falls back to gitleaks' **default** config — which would have falsified the Guard Contract's own Anchor clause.
- **DHH / code-simplicity:** every allowlisted field is re-derived by the hook itself from `git` and `gh`. The mechanism cached state that cannot go stale.
- **CTO:** `PostCompact` is a one-month-old API whose stdin shape the plan itself had to probe because docs and an internal pass disagreed — that disagreement *is* the signal to wait.

Deleted with it: the whole Guard Contract section, the `hooks` write edge into the knowledge base, the gdpr-gate finding's AC, the `PostCompact` binding, and 4 test scenarios. **Re-proposal is tracked at #8328** and must start from the two P0s above.

### CUT 2 — the token-ratio clause. Three independent reviewers.

The rule was `trigger=auto AND (count_auto >= 2 OR postTokens/preTokens > 0.15)`. The ratio clause is deleted; the rule is now `trigger == auto AND count_auto >= 2`.

- **code-simplicity + Kieran, independently:** the threshold was picked from **n=1** and sits just *above* the plan's only real measurement (1006181 to 105006 = **0.104**), so it would never have fired on observed data. The only fixture that fires it (0.30) was synthesized to satisfy the clause it tests.
- **code-simplicity:** it is not independent of the count clause — a high retained ratio on compaction #1 means the session is about to compact again, so it fires one event earlier on the same sessions.
- **Kieran (P1):** the prescribed `awk 'print (a/b) > 0.15'` is **file redirection** in awk — it creates a file named `0.15` and always succeeds (reproduced).

Deleted with it: one env var, the `awk` dependency, the `preTokens == 0` guard, the high-ratio fixture, and 2 scenarios.

### CUT 3 — phase derivation. Four reviewers.

- **Kieran (P0):** the drift AC was unsatisfiable. The map holds **16** keys to 5 phases; the plan's `case` had 8 arms, two of which (`soleur:compound`, `soleur:one-shot`) are **absent** from the map, and it mapped `qa` to `qa` where the map says `qa` to `review`.
- **architecture (P1):** "last `Skill` record" is not the current phase — in the largest local transcript it is `soleur:preflight`.
- **spec-flow (P1):** inside `/soleur:one-shot` the last skill record is the *child* (`soleur:work`), so the hook could never detect that it is mid-pipeline — the one-shot exception rested on a signal the read path does not produce.
- **code-simplicity:** the Cut List rejected a plugin copy of the map to avoid drift, then the AC re-coupled to that repo-only file — a test that cannot run where the hook ships.

The directive names the branch and the plan path instead; the phase is legible in the artifacts it orders re-read.

### CUT 4 — the `one-shot` Step 8 edit (spec-flow P0)

`one-shot/SKILL.md` Step 8 is one sentence (emit the DONE promise); there is **no resume-prompt block** anywhere in that file. The FR edited a site that does not exist, and Step 8 fires *after* merge, so the recommendation would arrive when the arc is over. Dropped rather than inventing a block; the recommendation surfaces through the `work`/`plan` phase-boundary prose that already exists.

### KEPT, with a correction each

| Finding | Correction |
|---|---|
| **architecture P0 — the scope guard is the wrong one** (worst finding in the panel). `git rev-parse --is-inside-work-tree` is true in *every* customer repo, so a customer compacting work on their own app would have the summarizer told to preserve "PR #, plan path, unchecked ACs, operator holds" — degrading a summary of work that has none. | TR1: gate on the `welcome-hook.sh` sentinel (a `plugins/soleur` directory check) **plus** the presence of a Soleur spec/plan artifact, never on "is a git repo". |
| **CTO — the rot answer was false.** "The suite's fixtures pin the parsed shape" is untrue when the fixtures are *synthesized*: they pin the shape Soleur wrote, not the shape Claude Code emits. On an upstream rename every fixture stays green and the feature dies silently on users' machines. | FR7 drift canary (new) + `claude --version` stamped into every marker. |
| **architecture — boundaries accumulate across `--resume`.** | TR2: count boundaries **since this session's last SessionStart**, not all-time. |
| **Kieran / architecture — the JSON ACs contradicted each other.** `jq -e . <<<""` returns rc 4, so "every fixture parses as JSON" rejected the silent paths; and the Observability block put markers on stdout while Phase 1 said stdout carries only the envelope. | Emit a **valid envelope on every SessionStart path**, marker inside `additionalContext`; when `jq` is unavailable emit a static `printf`'d JSON literal. |
| **CTO — no user-facing doc surface; Grok missing.** | `plugins/soleur/README.md` gains the kill-switch + a Grok row (Grok has no `INSTRUCTIONS.md`; the README table is its surface). |
| **architecture — the C4 claim was wrong three ways.** | See `### C4 views`. |
| **Kieran — AC mechanics.** `grep -c` exits 1 on zero matches (aborts under `set -e`); an AC asserting a command *fails* kills the suite; the grep pattern is whitespace-sensitive. | Folded into the AC set and the scenarios. |

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Spec names a test path under `plugins/soleur/hooks/` | **Zero** `*.test.sh` exist there, and that path is not in `SUITE_GLOBS` — a suite there would never run. | Test lands at `plugins/soleur/test/compaction-state-hook.test.sh`. |
| Spec adds a `components.test.ts` hooks.json case | `components.test.ts` does not reference `hooks.json` at all. | Binding assertion goes in the new suite. |
| Spec derives the phase from `.claude/phase-surface-map.json` | Repo-only; and the mechanism is now deleted (CUT 3). | Directive names branch + plan path. |
| Spec assumes `PostCompact` stdin carries `compact_summary` | Docs and the CTO pass disagree. | Moot — the `PostCompact` binding is cut (CUT 1). |
| Spec writes into `session-state.md` | `one-shot` writes that file from a whole-file template; five skills reference it; `compound` parses it. | Cut (CUT 1); re-proposal at **#8328**. |
| Spec budget "<200 ms on a 30 MB transcript" | Measured: **~25 ms** on 31 MB. | Recorded; the suite ceiling has ~40x headroom. |

## Open Code-Review Overlap

One open `code-review` issue names a file this plan edits (65 scanned):

- **#4133** — *Schema parity test for `## Observability` block* — names `plugins/soleur/skills/plan/SKILL.md` §2.9. **Disposition: Acknowledge.** This plan edits that file's `/clear` prose, a different region; the §2.9 drift surface is untouched. The issue remains open.

## Files to Create

- `plugins/soleur/hooks/compaction-state.sh` — one script, dispatching on `hook_event_name` (two events).
- `plugins/soleur/test/compaction-state-hook.test.sh` — stdin-fixture suite.
- `plugins/soleur/test/fixtures/compaction/` — **3** synthesized fixtures: `no-boundary.jsonl`, `one-auto.jsonl`, `two-auto.jsonl` (manual is a one-field flip asserted against `two-auto`; malformed input is a heredoc, not a file).
- ~~`scripts/followthroughs/compaction-format-drift-8323.sh` — FR7 drift canary~~ — **built, then deleted at implementation review** (ADR-227 `## Amendment`).
- `knowledge-base/engineering/architecture/decisions/ADR-227-compaction-state-from-a-per-session-ephemeral-ledger.md` — ordinal **provisional**; re-verify across every `origin/*` ref immediately before merge.

## Files to Edit

- `plugins/soleur/hooks/hooks.json` — add `PreCompact` (matcher `manual|auto`) and a `SessionStart` entry (matcher `compact`). **No `PostCompact` binding.**
- `plugins/soleur/skills/plan/SKILL.md` — make the two `/clear` recommendations conditional. The **mandatory** resume-prompt block is untouched (TR5).
- `plugins/soleur/skills/work/SKILL.md` — same for the `Tip: After shipping…` display.
- `plugins/soleur/README.md` — kill-switch documentation + the Grok row (honest degradation, 3-of-3 harnesses).
- `plugins/soleur/devin/INSTRUCTIONS.md`, `plugins/soleur/codex/INSTRUCTIONS.md` — one line each under `## Hooks and completion`.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — see `### C4 views`.
- `knowledge-base/engineering/architecture/principles-register.md` — AP-020 amendment (see `### C4 views`).
- `knowledge-base/project/specs/feat-compaction-aware-session-hooks/{spec.md,tasks.md}` — fold in the reconciliation + the four cuts.

## Implementation Phases

### Phase 0 — Payload probe (TR4) — blocking, and now much smaller

CUT 1 removed the flush-state dependency's hardest half, but the probe still decides one thing FR1 rests on: **whether the current compaction's `compact_boundary` is on disk when `SessionStart:compact` runs.** If not, `count_auto` is off by one and the rule fires on the wrong event while every fixture test stays green.

1. Bind a throwaway marker hook (scratchpad path) to `PreCompact` and `SessionStart` via `.claude/settings.local.json` (gitignored). On each event append: timestamp, `hook_event_name`, `source`/`trigger`, sorted top-level stdin keys, `transcript_path`, `grep -c '"subtype":"compact_boundary"' "$transcript_path"`, and the last boundary's `trigger` — i.e. exactly what FR1 will read, read where FR1 will read it.
2. Force one `/compact`; then let one auto-compaction occur.
3. Record in the hook header, dated: the literal `source` value; **whether the observed count includes the compaction that just fired**; whether `transcript_path` is stable across it; and `--fork-session` inheritance (untested, flagged by the panel).
4. Delete the probe and its settings entry.

**Pre-authorized fallback:** if the boundary is not yet flushed, `PreCompact` (which fires *before* the boundary and already has its own binding) appends one line to a per-session file under `TMPDIR`, and `SessionStart:compact` counts lines there instead. **This is not the rejected counter store** — that one lived in the user's repo and needed an un-addable `.gitignore` entry; a per-session temp file has neither problem and is disposable. The panel noted this was arguably the simpler primary all along; it stays the fallback only because the transcript needs no second writer if the flush ordering is favourable.

### Phase 1 — `compaction-state.sh` (FR1, FR2)

RED first (`cq-write-failing-tests-before`).

- Dispatch on `hook_event_name`. `SOLEUR_DISABLE_COMPACTION_HOOKS=1` short-circuits first. `set -uo pipefail` + **`trap 'exit 0' ERR EXIT`** — the `EXIT` arm is load-bearing because a `set -u` unbound-variable expansion terminates the shell with status 1 **without** firing `ERR`, which is exactly the silent-drop the fail-open contract exists to prevent.
- **Scope guard (TR1):** the `welcome-hook.sh` sentinel — a `plugins/soleur` directory check under the project root — **plus** a Soleur artifact (`knowledge-base/project/plans/` or `specs/`). Not "is a git repo".
- Read `transcript_path` via `jq -r '.transcript_path // empty'`; empty or unreadable → emit the no-directive envelope, exit 0.
- Derive `count_auto` **scoped to this session's window** (TR2) and the last boundary's `trigger`.
- **Recommendation rule (FR2):** `trigger == "auto" AND count_auto >= ${SOLEUR_COMPACTION_COUNT_THRESHOLD:-2}`. One integer, one env override.
- Directive content: compaction number, trigger, branch, plan path, "re-read the plan before editing" (`hr-always-read-a-file-before-editing-it`), the `claude --version` string, and the `SOLEUR_COMPACTION_*` marker — all **inside `additionalContext`**. stdout carries the JSON envelope and nothing else; diagnostics to stderr. Truncate at 8,000 chars.

### Phase 2 — `PreCompact` summary shaping (FR3)

~5 lines of **static** plain-text stdout (not JSON) — the wire contract externally verified in the upstream thread. Names the identifiers to preserve; no derivation, no fixtures beyond one scenario. Exit 0 always; never exit 2. Gated by the same TR1 scope guard, because this is the path that would otherwise degrade a stranger's summary.

### Phase 3 — Prose retirement (FR5) + docs (FR6)

Each `/clear` *recommendation* becomes conditional. The resume prompt stays **mandatory and unconditional** (TR5). README gains the kill-switch and the Grok row; the two INSTRUCTIONS files gain one line each.

### Phase 4 — Drift canary (FR7)

A `scripts/followthroughs/`-shaped script that reads the operator's **real** `~/.claude/projects/**/*.jsonl` and asserts at least one `"subtype":"compact_boundary"` across N recent transcripts. Scheduled via `soleur:schedule`, **not** a suite case — a suite case would break CI on a clean box. This is the only mechanism that can detect an upstream format rename; synthesized fixtures structurally cannot.

### Phase 5 — ADR + C4 + register + spec/tasks reconciliation

### Phase 6 — Full battery, review

## Architecture Decision (ADR/C4)

### ADR

**ADR-227 — "The compaction signal is read from the transcript, not from a counter file"** (create; ordinal provisional). Decision: compaction count and trigger are derived from the transcript's own `compact_boundary` records at `SessionStart:compact`; no counter store is introduced; no `PostCompact` binding ships in this slice.

`## Alternatives Considered` must record, each with its evidence: (a) the `.claude/.session-manifests` piggyback (repo-only, overwritten on every SessionStart including `compact`); (b) a repo-side counter store (un-addable `.gitignore` entry); (c) **the per-session `TMPDIR` file — accepted-conditional**, as Phase 0's fallback, so the ADR does not contradict the plan; (d) skill-prose-only (the model cannot observe its own compaction count); (e) `PostCompact` + `UserPromptSubmit` rebinding; (f) statusline `context_window` (measured unreachable from hooks — record the probe); (g) **the checkpoint writer, deleted by review**, with the two P0s that killed it, so #8328 inherits them.

Per the CTO pass, the ADR must also record that this is the **first customer-shipped consumer** of the transcript format. `.claude/hooks/monitor-supersede-guard.sh` already parses transcript internals, but it is repo-side — the operator sees it break. The rot economics differ, and FR7 exists because of that difference.

### C4 views

The panel found the previous C4 claim wrong in three ways; corrected:

1. The falsified string is the `hooks` container's **`technology "PreToolUse Guards + Rewriter + PostToolUse hints"`** line, not its description — the previous AC targeted the wrong line.
2. The `hooks` description's surface split ("in the repo-local `.claude/` hook surface only — never the shipped plugin surface") is falsified in a second way: this makes the *shipped* surface a compaction-lifecycle consumer.
3. **`claude -> hooks "Tool-call envelope on stdin"` is falsified** — the hook now dereferences `transcript_path` and reads full conversation history. That is a new access relationship, and it widens **AP-020** (scoped to "the MODEL-CONTROLLED hook-stdin envelope") to content merely *pointed at* by that envelope. `knowledge-base/engineering/architecture/principles-register.md` AP-020 needs the amendment.

So: **three** changed relationships, not one. The `hooks` write edge into the knowledge base is **not** among them — it died with CUT 1.

**Completeness enumeration** (all three `.c4` files read): no external human actors added; no external systems added (the transcript is a local file written by the already-modelled Agent Runtime); containers touched are `platform.engine.hooks` only. **Cardinality gate:** no skill and no agent added, so no derived count moves; `plugins/soleur/test/c4-count-parity.test.sh` is green at HEAD and must be green after.

## User-Brand Impact

**If this lands broken, the user experiences:** a spurious recommendation to abandon a healthy session, or — with a malformed envelope — no directive at all, which is today's behaviour and therefore the fail-open floor. **With the pre-review scope guard**, a customer working on an unrelated repo would have had their compaction summary degraded by instructions about PRs and operator holds they do not have; TR1 is the fix and is the single highest-value change in this revision.

**If this leaks, the user's workflow is exposed via:** nothing in the shipped scope. The writer that carried this risk (transcript-derived text into a tracked, pushed file) was deleted by review; #8328 inherits the exposure analysis.

**Brand-survival threshold:** `single-user incident`.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm; re-checked against the post-cut scope).

### Engineering

**Status:** reviewed
**Assessment:** `PostCompact` stdout is never model-visible; `SessionStart` is. `.session-manifests` is repo-side and overwritten per SessionStart. The six-agent panel deleted the checkpoint writer, the ratio clause, phase derivation and the one-shot edit; the surviving design is one script, two bindings, one integer threshold.

### Product

**Status:** reviewed
**Assessment:** Phase 4 milestone, internal-tooling row. Nudge at the phase boundary, never mid-pipeline; threshold as env override, not a setting. The precedence question this domain raised ("define precedence between the hook and the skills that already write `session-state.md`") was answered by deleting the hook's write.

### Legal

**Status:** reviewed
**Assessment (plan-time gdpr-gate, 2026-09-18):** the single `Important` finding — an absolute worktree path carrying the OS username into a tracked, pushed file — **is moot in the shipped scope**, because the writer that would have carried it is cut. It is recorded on **#8328** so the re-proposal starts with it. The surviving slices are read-only and local: no Art. 9 surface, no Chapter V transfer, no disclosure change. Privacy policy §4.1/§4.2 already describe this accurately.

### Product/UX Gate

**Tier:** none — no path in the file lists matches the UI-surface glob superset.
**Pencil available:** N/A (no UI surface).

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_COMPACTION_DIRECTIVE, emitted inside additionalContext on every SessionStart:compact fire, carrying count_auto, trigger, recommend=true|false, and the claude --version string"
  cadence: "once per compaction (measured: 11 boundaries across 22 recent local sessions)"
  alert_target: "none — layer 7 (customer-installed CLI); the aggregated metric is deferred to #8324"
  configured_in: "plugins/soleur/hooks/compaction-state.sh"
error_reporting:
  destination: "markers inside additionalContext (model-visible, recorded in the transcript); stderr for diagnostics. stdout carries the JSON envelope ONLY — a stray byte there invalidates the whole output."
  fail_loud: "no — fail-open by contract; every failure path emits a valid envelope plus a named marker instead of a non-zero exit"
failure_modes:
  - mode: "the ledger directory is missing, foreign-owned, or a symlink"
    detection: "SOLEUR_COMPACTION_SKIPPED reason=ledger-dir-unusable, inside additionalContext"
    alert_route: "read in-session; asserted by the suite"
  - mode: "jq unavailable"
    detection: "a static printf'd JSON envelope carrying reason=jq-unavailable — the envelope cannot be built with jq in this state, so it is emitted literally"
    alert_route: "same"
  - mode: "hook runs in a non-Soleur repo (global plugin install)"
    detection: "silent exit 0 by design (TR1 scope guard)"
    alert_route: "n/a — this is the correct behaviour, not a degradation"
  - mode: "upstream renames a stdin envelope field (hook_event_name, source, trigger, session_id)"
    detection: "NONE, deliberately — no offline probe can observe a contract that exists only at hook-fire time. The hook fails open to silence and every marker carries the claude --version string for attribution. The FR7 canary that once sat here watched the TRANSCRIPT, which since the ledger change cannot break the feature; it was deleted at review (ADR-227 Amendment). The aggregated signal that would show the hooks having stopped firing is tracked at #8324."
    alert_route: "n/a — named residual risk, not a mitigated one"
logs:
  where: "the session transcript (additionalContext is recorded there); stderr to the Claude Code debug log"
  retention: "as long as the user's ~/.claude/projects transcripts are retained — local only, nothing shipped"
discoverability_test:
  command: "bash plugins/soleur/test/compaction-state-hook.test.sh"
  expected_output: "ALL TESTS PASSED"
```

No `credentials_required` — fully local and unauthenticated.

## Infrastructure (IaC)

None. No server, service, cron, vendor account, DNS record, secret or firewall rule is introduced; the change is plugin markdown + one bash hook + tests. The Phase 2.8 detection scan found no SSH form, no systemd unit management, no secret-store write, no vendor-dashboard step. FR7's canary is scheduled through the existing `soleur:schedule` mechanism, which introduces no new infrastructure.

## Encryption Posture

Not applicable — Phase 2.11 detection does not fire: no `*.tf`, no migrations, no cloud-init, no compose file, no new persistent store (the writer that touched one is cut), and no new cross-component or network connection.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — Phase 0's findings are in the hook header, dated: the literal `source` value, whether the observed boundary count includes the compaction that just fired, `transcript_path` stability, and `--fork-session` behaviour. If the count excludes it, the `TMPDIR` fallback is what shipped and a suite case asserts it.
- [x] **AC2** — Zero boundaries → the envelope is emitted and valid, and its `additionalContext` contains **no** directive. (Stated as a property of `additionalContext`, not of stdout emptiness — `jq -e . <<<""` returns rc 4.)
- [x] **AC3** — One auto boundary → directive present, `recommend=false`, no "fresh session" string.
- [x] **AC4** — Two auto boundaries → `recommend=true`.
- [x] **AC5** — Manual boundaries only → `recommend=false` at any count.
- [x] **AC6** — `SOLEUR_COMPACTION_COUNT_THRESHOLD=1` on the one-auto fixture → `recommend=true`.
- [x] **AC7** — rc is 0 on every path: malformed stdin, absent `transcript_path`, unreadable transcript, non-Soleur repo, kill-switch, and a deliberately-unset internal variable (the `set -u` case the `EXIT` trap exists for).
- [x] **AC8** — On **every** SessionStart fixture, stdout parses as JSON in full (`jq -e .` succeeds) — proving no marker or diagnostic leaked onto stdout — and `additionalContext` never exceeds 8,000 chars.
- [x] **AC9** — With `jq` removed from `PATH`, stdout is still valid JSON (the static `printf` path).
- [x] **AC10 (TR1 scope guard)** — In a git repo with **no** `plugins/soleur` directory, both events emit nothing and exit 0. Asserted for `PreCompact` specifically, since that is the path that would otherwise reach a stranger's summarizer.
- [x] **AC11 (TR2)** — A fixture holding 3 boundaries across a simulated `--resume` yields `count_auto` scoped to the current session window, not 3.
- [x] **AC12** — `PreCompact` emits non-empty, **non-JSON** stdout and rc 0. Written so the assertion cannot abort the suite: `if jq -e . <<<"$out" >/dev/null 2>&1; then fail "PreCompact emitted JSON"; fi`.
- [x] **AC13** — `hooks.json` binds exactly two events (`PreCompact` matcher `manual|auto`, `SessionStart` matcher `compact`) to the hook, contains **no** `PostCompact` key, remains valid JSON, and the script is mode 100755.
- [~] **AC14 (WITHDRAWN at implementation review)** — the hook no longer greps the transcript, so the spacing pin has no subject; scenario 15 was deleted with it. Original text: The `compact_boundary` grep pattern is pinned by a fixture whose spacing differs (`"subtype": "compact_boundary"`), so a CLI formatting change reds the suite rather than silently returning 0.
- [x] **AC15 (TR5)** — Every `/clear` **recommendation** in `plan/SKILL.md` and `work/SKILL.md` is conditional, AND the mandatory resume-prompt blocks are byte-identical to `origin/main`. Verify with `git diff origin/main -- <file>` scoped to the resume-prompt regions, not a heading count. `work/SKILL.md` must still emit an end-of-work resume prompt when the hook never fires (no compaction, non-Claude harness, kill-switch) — the spec-flow dead-end.
- [x] **AC16** — `README.md` documents `SOLEUR_COMPACTION_COUNT_THRESHOLD` and `SOLEUR_DISABLE_COMPACTION_HOOKS`, and carries a Grok row; `devin/` and `codex/INSTRUCTIONS.md` each carry the Claude-only line.
- [~] **AC17 (WITHDRAWN at implementation review)** — no canary ships, in any registration (ADR-227 `## Amendment`). Original text: The drift canary exists, runs against real `~/.claude/projects/**/*.jsonl`, exits non-zero when zero boundaries are found across N recent transcripts, and is registered — **not** as a suite case, and **not** as a GitHub Actions schedule either: measured, a runner has no `~/.claude/projects`, so that would be a probe that can only report TRANSIENT. Bound to the repo-side `SessionStart` surface via `.claude/hooks/compaction-drift-canary.sh`, stamp-gated to 7 days.
- [x] **AC18 (amended)** — `model.c4` amends the `hooks` **`technology`** line and its surface-split description, and adds the OUTBOUND `hooks -> claude` edge for the compaction summarizer. The AP-020 clause is **withdrawn**: the widening existed only because the hook dereferenced `transcript_path`, so `principles-register.md` is byte-identical to `main`. `c4-count-parity.test.sh`, `c4-model-freshness.test.sh` and the `c4-*.test.ts` suites are green.
- [x] **AC19** — Fixtures are synthesized (`cq-test-fixtures-synthesized-only`): no real session ids, no paths outside this repo, no live tokens.
- [ ] **AC20** — Full battery green: `TEST_GROUP=all bash scripts/test-all.sh`, verdict read from the rc file. **OPEN at work-phase exit, deliberately.** The run returned **rc=4 — REFUSED, nothing ran**: a sibling worktree held a full-gate run (measured, #7553). That is neither a pass nor a fail, and overriding it with `SOLEUR_ALLOW_FULL_GATE=1` would put two full gates on one box, which is the condition the refusal exists to prevent. Substitutes run in the meantime, derived from the diff's new `SOLEUR_COMPACTION_*` vocabulary and from consumers of the changed artifacts rather than from memory: `compaction-state-hook` 103/103, `hookeventname-coverage`, `settings-hook-exec-bit`, `hook-input-contract` 111/111, `devin-matcher-parity` 9/9, `c4-model-freshness`, `c4-count-parity`, `gitleaks-rules` 44/44, `lane-frontmatter`, `kb-search-lockstep`, `generate-kb-index`, `fixture-relative-assert` 62/62, `fixture-dir-operand-assert` 71/71, `components` 1331 pass, `devin-cloud-mode`, `devin-plugin`, `codex-plugin`, `fullsuite-merge-gate`, `observability-schema-parity`, `workflow-fidelity`, and 4 vitest c4 suites (36 tests) run CI-equivalent without Doppler. The battery runs at the `/ship` Phase 4 checkpoint (ADR-183), which is its sanctioned position.
- [x] **AC21** — The diff is a subset of `## Files to Create` / `## Files to Edit` plus the pipeline-written artifacts (`knowledge-base/INDEX.md`, `specs/<branch>/session-state.md`, this plan).

**Every AC above is a post-condition on file state, command output or merged behaviour.** The four process attestations the panel flagged as ceremony (probe-results-recorded-as-such, ordinal re-verification, gdpr-gate-verdict-in-PR-body, and the timing budget) are gone: AC1 now asserts the header's *content* decides the implementation, ordinal re-verification is a `/ship` gate not an AC, and the timing claim is recorded as a measurement (~25 ms on 31 MB) rather than asserted as a budget.

### Post-merge (operator)

None.

## Test Scenarios

In `plugins/soleur/test/compaction-state-hook.test.sh`, envelopes built with `jq -nc` and piped to the hook (the `browser-snapshot-credential-guard.test.sh` shape). `grep -c` is always wrapped (`n=$(grep -c … || true)`) because it exits 1 on zero matches and would abort the suite under `set -e`.

1. Zero boundaries → valid envelope, no directive.
2. One auto → `recommend=false`.
3. Two auto → `recommend=true`.
4. Manual only → `recommend=false`.
5. Threshold override → `recommend=true` on the one-auto fixture.
6. Resume-window scoping (3 boundaries, one session window).
7. Five rc-0 paths + the `set -u` case.
8. stdout parses as JSON on every SessionStart fixture; 8k cap.
9. `jq` absent → static envelope still valid.
10. Scope guard: no `plugins/soleur` → silence on both events.
11. `PreCompact` → non-empty, non-JSON, rc 0.
12. `hooks.json` bindings + no `PostCompact` key + exec bit.
13. Whitespace-variant `compact_boundary` pattern pin.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The current compaction's boundary is not flushed when `SessionStart:compact` runs — values off by one with fixture tests green | Phase 0 measures exactly this at the point FR1 reads it (AC1); the `TMPDIR` fallback via the already-bound `PreCompact` is pre-authorized |
| **Upstream renames the transcript format; synthesized fixtures stay green and the feature dies silently on users' machines** | FR7 canary against real transcripts (AC17) + `claude --version` in every marker. The previous "fixtures pin the shape" answer was false and is retracted |
| A plugin hook degrades a non-Soleur user's compaction summary | TR1 sentinel scope guard (AC10), mirroring `welcome-hook.sh` |
| Long `--resume` session pins `recommend=true` forever | TR2 session-window scoping (AC11) |
| Directive is elevated-authority text the model over-trusts | Pointer-style only (branch + plan path + counts); advisory, deferred to the next phase boundary |
| Prose retirement leaves a dead end when the hook never speaks | AC15 asserts the end-of-work resume prompt survives all three silent states |
| ADR ordinal collision | Provisional; re-verified across every `origin/*` ref at `/ship`, and any renumber sweeps plan + tasks + ACs together |

## Deferred

- **#8328** — the `PostCompact` checkpoint writer (CUT 1). Must start from: `one-shot` writes `session-state.md` as a whole-file template that would destroy any hook-owned block, and nothing in `work` Phase 0 reads that file. Re-evaluate once a reader exists and the upstream `PostCompact` stdin shape is settled. Inherits the gdpr-gate worktree-path finding.
- **#8324** — local `SOLEUR_COMPACTION` metric via the `incidents.sh` to `rule-metrics-aggregate.sh` ledger. Re-evaluate after ~30 days of dogfooding.
- Devin `PostCompaction` measurement — #8172 closed without a positive measurement; needs a cloud session where a compaction actually occurs with the marker hook bound.

## Addendum — 2026-09-18 (Phase 0 payload probe: measured results)

Run automatically, without an operator step: a scratch project at `/var/tmp/soleur-compaction-probe/proj`
with a marker hook bound to `PreCompact`, `SessionStart` and `PostCompact` via that project's own
`.claude/settings.json`, driven by headless `claude -p --continue "/compact" --model haiku`. No
`.claude/settings.local.json` entry was ever added to this repo, so Phase 0 step 4's delete step is
vacuous here. Claude Code **2.1.273**, Linux, 2026-09-18. The raw marker log (12 events) is retained at
`/var/tmp/soleur-compaction-probe-findings.log`; its content is transcribed below because that path is
swept.

| Question (plan Phase 0 / AC1) | Measured answer |
|---|---|
| Literal `source` value after a compaction | `compact` |
| `SessionStart:compact` stdin keys | `cwd, hook_event_name, model, prompt_id, session_id, source, transcript_path` — **no `trigger`** |
| `PreCompact` stdin keys | `custom_instructions, cwd, hook_event_name, prompt_id, session_id, transcript_path, trigger` — **no `source`** |
| `PostCompact` stdin keys | `compact_summary, cwd, hook_event_name, prompt_id, session_id, transcript_path, trigger` |
| `SessionStart:startup` stdin keys | `cwd, hook_event_name, session_id, source, transcript_path`; `transcript_path` names a file that **does not yet exist** |
| **Does the boundary count at `SessionStart:compact` include the compaction that just fired?** | **NO — off by exactly one.** Compaction #1: hook read `count=0`, file held 1 afterwards. Compaction #2: hook read `count=1`, file held 2 afterwards. `PostCompact`, 100 ms later, read the same lagging count. The boundary's own `timestamp` (`16:10:14.926Z`) *precedes* the hook fire (`16:10:14.957Z`), so the record exists in memory and is flushed after the hook returns. |
| `transcript_path` stability across a compaction | **Stable** — byte-identical at `PreCompact`, `SessionStart:compact` and `PostCompact`. |
| `--fork-session` inheritance | New `session_id` and a **new transcript file** carrying the post-compaction history (1 of the parent's 2 boundaries). **No `SessionStart` hook fired at all** for the forked run. |
| **Does `PreCompact` firing imply a compaction occurred?** (not asked by the plan) | **NO.** 3 `PreCompact` fires produced 2 boundaries: a `/compact` with nothing left to compact fires `PreCompact` and then no `SessionStart:compact`. |

### Consequence: the pre-authorized fallback ships, with one correction

The first bold row settles Phase 0's load-bearing unknown against the plan's primary design. The
transcript **cannot** answer "how many compactions has this session had" at the moment
`SessionStart:compact` runs, and it cannot supply the current compaction's `trigger` either (the last
on-disk boundary is the *previous* one, and the `SessionStart` envelope carries no `trigger`). Plan
Phase 0 step 4 and task 0.4 pre-authorize the `TMPDIR` ledger for exactly this outcome; it ships.

The last row corrects that fallback as written. "`PreCompact` appends one line; `SessionStart:compact`
counts lines" **over-counts**, because `PreCompact` fires on no-op compactions — measured 3 fires for 2
boundaries, which would have moved `recommend=true` one compaction early while every fixture stayed
green. The shipped mechanism is therefore **pending-then-commit**:

- `PreCompact` **overwrites** a single `pending` slot with the stdin `trigger` (never appends).
- `SessionStart:compact` **commits** the pending trigger as one ledger line, clears pending, then counts.
  It fires exactly once per real compaction, so the ledger holds exactly one line per compaction and
  each line carries that compaction's own trigger.
- `SessionStart` with `source` in `startup|resume|clear` truncates the ledger and clears pending — this
  is what makes TR2's session-window scoping exact, rather than approximated.

That last bullet requires the `SessionStart` matcher to be `startup|resume|clear|compact`, not `compact`
alone as `## Files to Edit` says. The non-`compact` arm emits no directive; it only resets the window.

### What the transcript is still read for

`count_auto` and `trigger` no longer come from the transcript. The hook still greps
`"subtype":"compact_boundary"` once, to report `prior_boundaries=N` inside the marker. This keeps AC14's
pattern pin and FR7's canary attached to a string the shipped hook actually greps, and — stated
honestly — a format rename now degrades that marker rather than the recommendation. FR7's value is
correspondingly narrower than `## Risks & Mitigations` claims: it signals that this addendum's
measurements have gone stale, not that the feature has stopped working.

### AC deltas this forces

- **AC2–AC6, AC11** are now properties of the **ledger**, driven by `PreCompact`/`SessionStart` event
  sequences rather than by transcript fixtures alone. The 3 transcript fixtures survive for AC14 and for
  `prior_boundaries`.
- **AC11 (TR2)** is asserted by the reset arm: a ledger holding 3 lines, then a `SessionStart:resume`,
  then one compaction, must yield `count_auto=1`.
- **AC13** now expects the `SessionStart` matcher `startup|resume|clear|compact`. Still **no**
  `PostCompact` binding.
- One new AC — **AC22**: a `PreCompact` that is never followed by `SessionStart:compact` (the measured
  no-op) contributes **zero** to `count_auto`.

## Addendum — 2026-09-18 (implementation review): FR7 and the transcript read are deleted

The Phase 0 addendum above narrowed FR7's value ("a format rename now degrades that marker rather
than the recommendation... FR7's value is correspondingly narrower than `## Risks & Mitigations`
claims"). A two-lens design-validity pass took the next step and deleted the mechanism, converging
from two directions: nothing consumed `prior_boundaries`, and the canary could not report (exit-0
hook stderr is discarded; the cadence stamp was written before the run, so a RED verdict
self-suppressed for seven days). Full evidence: ADR-227 `## Amendment — 2026-09-18`.

Deleted: the transcript grep and the `prior_boundaries` field;
`scripts/followthroughs/compaction-format-drift-8323.sh`;
`.claude/hooks/compaction-drift-canary.sh` and its `.claude/settings.json` binding; four
`SOLEUR_COMPACTION_DRIFT*` env vars; the `spaced-boundary.jsonl` fixture; the AP-020 widening and
the `claude -> hooks` C4 edge amendment (both byte-identical to `main` again); FR7/TR9/SC6.

### AC deltas this forces, on top of the Phase 0 set

- **AC14** (whitespace-variant `compact_boundary` pin) — **withdrawn.** The hook no longer greps the
  transcript, so the property does not exist. Scenario 15 deleted with it.
- **AC17** (FR7 canary) — **withdrawn.** No canary ships.
- **AC18** — the AP-020 clause is withdrawn; `principles-register.md` is unchanged from `main`.
  `model.c4` keeps two amendments (the `technology` line and the surface-split description, now also
  recording that the shipped surface is stateful across events) and gains one the earlier revision
  missed: the OUTBOUND `hooks -> claude` edge, because the `PreCompact` arm instructs the compaction
  summarizer, a second model consumer that "rewrites tool input before execution" does not describe.
- **Three new ACs from the review's P1s**, each mutation-proven (revert the fix → suite reds):
  **AC23** `trigger` is validated against `{manual, auto}` before reaching the ledger or
  `additionalContext` (unvalidated, a multi-line value inflates `count_total`, which is a line
  count, and can force `recommend=true` from one compaction);
  **AC24** the scope walk stops at the enclosing repository, so a git repo nested under a Soleur
  checkout is out of scope;
  **AC25** an unusable or foreign-owned ledger directory causes the hook to write nothing and exit 0
  (with `TMPDIR` unset the path is world-reachable `/tmp/soleur-compaction`, and a pre-seeded
  `.pending` would otherwise flow into model-read text).

Net issues filed by this review: **0**. The residual drift-detection capability is subsumed by the
already-open #8324, whose ledger metric is what would actually show the hooks having stopped firing.

## Addendum — 2026-09-18 (ten-seat panel): two CTO rulings and the harness vacuity

Full evidence in ADR-227's two `## Amendment — 2026-09-18 (CTO ruling …)` sections.
Recorded here because the AC list above is what a resumed session greps.

**AC23–AC25 (added last round) stand.** **AC26–AC28 are new:**

- **AC26** — the recommendation gate is `count_auto >= THRESHOLD` alone. A manual
  compaction after the threshold is met does **not** revoke the recommendation
  (scenario 19, restored inverted). `0`, non-numeric and `010` thresholds all
  resolve safely.
- **AC27** — the scope guard requires a Soleur plan/spec artifact and nothing
  else, so a marketplace install is in scope (scenario 11b). The
  `plugins/soleur` conjunct is gone.
- **AC28** — the suite is green in every environment it ships into: `CI=1`,
  `SOLEUR_SUBAGENT=1`, both, and on a **detached HEAD**. That last one was red
  before the panel: assertion 14g pinned the literal branch name, and CI checks
  out a detached HEAD on `pull_request`.

**Process errors this round, recorded rather than smoothed over.** I applied
fixes to the worktree while ten report-only agents were reading it, which the
skill's own sharp edge forbids — two seats reported the tree shifting under
them, and one had to re-run its battery. I recalibrated an assertion floor after
a drop without checking *which* case had gone, and a scenario-17 rewrite had
silently taken scenario 19 with it. And I twice measured an exit code with a
`bash -c` one-liner rather than the subject, getting 127 where the hook gives 1.
