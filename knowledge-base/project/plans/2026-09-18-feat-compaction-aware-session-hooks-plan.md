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

Soleur's "run `/clear` and resume" advice is unconditional prose in `plan` and `work`; it cannot see whether context compaction happened, how often, or in which phase. Claude Code records every compaction in the session transcript as a `compact_boundary` record carrying `compactMetadata.{trigger, preTokens, postTokens, cumulativeDroppedTokens}`, and the `SessionStart` hook with matcher `compact` receives that transcript's path and injects model-visible context verbatim after the summary.

This plan ships one plugin-owned hook script, bound three ways in `plugins/soleur/hooks/hooks.json` so every marketplace install gets it, that turns those records into: a post-compaction re-read directive naming the current workflow phase; a fresh-session recommendation gated on an evidence rule; a `PreCompact` instruction that keeps resume identifiers verbatim in the summary; and an allowlisted checkpoint block in `session-state.md`. The unconditional `/clear` prose is then retired in favour of the injected signal.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
|---|---|---|
| `#8323` (work target) | `gh issue view 8323 --json state` | **OPEN** — valid target |
| PR `#8320` | `gh pr view 8320 --json state,isDraft` | **OPEN, draft** — this branch's draft PR |
| `#8172` (Devin `PostCompaction` probe) | `gh issue view 8172 --json state` | **CLOSED** without a positive `PostCompaction` measurement — `devin/INSTRUCTIONS.md`'s "unmeasured" caveat is stale-but-accurate, not resolved |
| Upstream `anthropics/claude-code#14258` | `gh issue view` | CLOSED 2026-08-17; `PostCompact` shipped v2.1.76 (confirmed in the upstream CHANGELOG entry for 2.1.76: "Added `PostCompact` hook that fires after compaction completes") |
| Local CLI supports it | `claude --version` | **2.1.273** |
| ADR corpus for the mechanism | `git grep -il "compaction\|compact_boundary\|PostCompact\|transcript_path" -- 'knowledge-base/engineering/architecture/decisions/*.md'` | 6 hits, **none** decide a compaction-state mechanism (ADR-176 is plan-artifact checkpointing; ADR-221 is cloud-mode sentinel detection; the rest are incidental). No rejected-alternative collision. |
| `hooks.json` can carry a `compact` SessionStart matcher | read `plugins/soleur/hooks/hooks.json` | Already binds `startup\|resume\|clear\|compact` → `codex-session-start.sh`. No `PreCompact`/`PostCompact` key exists in **either** registry. |
| Anything already branches on `source == "compact"` | `grep -rn '"source"' .claude/hooks/*.sh plugins/soleur/hooks/*.sh` | **No.** All three SessionStart scripts fire identically regardless of source. |

**Capability claims verified against live artifacts (not memory):**

- `compact_boundary` record shape — read from a real transcript under `~/.claude/projects/-data-git-repositories-jikig-ai-soleur/`: `{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":1006181,"postTokens":105006,"cumulativeDroppedTokens":901175,"durationMs":125559,…}}`.
- **`SessionStart` fires after auto-compaction** — measured across 4 transcripts: the `[rules-loader] loaded` / `[session-context] branch` lines (emitted only by a SessionStart hook) appear 14 lines after each `"trigger":"auto"` boundary and nowhere else mid-session. This is strong evidence the `compact` matcher fires on auto-compaction, and it is what makes the stateless design viable. **TR4 must still confirm the literal `source` value**, because "a SessionStart hook fired" is not the same claim as "`source == "compact"`".
- Compaction frequency in this repo: 8 of 22 recent sessions compacted, 11 boundaries total.
- Skill invocations are visible in the transcript as `"name":"Skill","input":{"skill":"soleur:<name>"` — the portable phase source (`.claude/.skill-invocations.jsonl` is repo-only).
- Transcripts run 13–30 MB. Bounded reads only (`grep -c`, `grep | tail -1`); never `cat`.
- Advisor tier resolves to `fable` (`plugins/soleur/lib/harness-model-map.ts`).
- `plugins/soleur/test/c4-count-parity.test.sh` is **green at HEAD** (`ALL TESTS PASSED`) — the pre-edit baseline for the C4 gate.

### Property List (Phase 0.6b)

1. After a compaction, the agent re-reads the plan and `session-state.md` before editing, instead of trusting a paraphrased summary.
2. The operator is asked to continue in a fresh session only when the evidence supports it, and never mid-pipeline.
3. The compaction summary retains the identifiers a resume depends on (branch, worktree, PR #, issue #, plan path, phase, unchecked ACs, operator holds, file paths).
4. The on-disk resume artifact (`session-state.md`) is never older than the last compaction.
5. A non-Claude harness degrades honestly rather than silently claiming the behaviour.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property it would buy | Why cut |
|---|---|---|
| `PostCompact`-written counter store (`.claude/.compaction/<sid>.json`) | #2 (count compactions) | The transcript already carries every boundary and `SessionStart:compact` receives `transcript_path`. A store adds a write path, a `.gitignore` entry the plugin cannot add to a user's repo, and a dependency on the undocumented `PostCompact`↔`SessionStart` ordering. `.claude/.session-manifests/<sid>.json` — the obvious host — is repo-side and **overwritten** by `session-rules-loader.sh` on every SessionStart *including* `compact`. |
| Plugin-side copy of `.claude/phase-surface-map.json` | #1 (name the phase) | An in-script `case` over the ~6 pipeline skills buys the same property with no second artifact to drift. |
| `SOLEUR_COMPACTION` telemetry marker | measurement, not a listed property | Deferred to **#8324**. The brainstorm's premise that `SOLEUR_*` markers reach Better Stack was false — they terminate in the gitignored `.claude/.rule-incidents.jsonl` rolled up by `scripts/rule-metrics-aggregate.sh`; `scripts/betterstack-query.sh` reads prod Vector logs only. |
| Blocking `PreCompact` (exit 2) during ship | none | Trades a recoverable context loss for a "Prompt is too long" dead session. |

### Value proposition (Phase 0.6c)

Not a cost saving — a correctness saving, and it is **not** quantified at plan time. What would quantify it: the count of compaction/resume-tagged learnings and `unkept-promise-hook.sh` firings in the 30 days after merge (the #8324 metric measures exactly this). The justification standing on its own is the measured 8-of-22 compaction rate against prose that fires at fixed points regardless.

### Institutional learnings that constrain this work

| Learning | Constraint |
|---|---|
| `2026-03-04-sessionstart-hook-api-contract.md` | `additionalContext` (not `systemMessage`) is what the model sees; envelope is `hookSpecificOutput.{hookEventName, additionalContext}`. |
| `2026-06-30-posttooluse-skill-additionalcontext-is-the-autonomous-safe-phase-injection-vehicle.md` | `additionalContext` caps at **10,000 chars**; **any non-zero exit other than 2 silently drops the whole JSON output**. Build the envelope with `jq -n --arg`; never echo model-controlled strings raw. |
| `best-practices/2026-06-15-sessionstart-snapshot-ordering-and-committed-config-sanitization.md` | Compute snapshot values *before* the hook writes its own state; clamp control chars per key, not per stream. |
| `2026-05-10-claude-code-posttooluse-task-hook-input-shape.md`, `2026-03-09-stop-hook-path-resolution-and-api-simplification.md` | Hook payload field names diverge from docs — capture real envelopes, date them in the header, prefer a structured hook field over re-parsing the transcript. |
| `developer-experience/2026-04-02-plugin-hook-scope-guard-welcome-hook.md` | A plugin SessionStart hook must scope-guard on project presence or it pollutes every repo. |
| `2026-07-05-declarative-context-injection-pointer-vs-inline…` | Prefer pointers (paths) over inlined bodies; hook-delivered content carries elevated authority framing. |
| `2026-02-22-context-compaction-command-optimization.md` | `session-state.md` is the established compaction-boundary forwarding artifact — this extends it, reverses nothing. |
| `workflow-patterns/2026-09-18-compaction-state-lives-in-the-transcript-not-a-counter-file.md` | This feature's own brainstorm learning: read the harness's own event log before designing a store. |

### Repo conventions this must follow

- Fail-open shape from `phase-surface-hint.sh`: `set -uo pipefail` (no `-e`), `trap 'exit 0' ERR`, exit 0 on every path, `SOLEUR_DISABLE_*` kill-switch.
- `hooks.json` entries call `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh`; scripts resolve siblings via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` (`stop-hook.sh`) — ADR-178 pattern for reaching `scripts/lib/`.
- Test precedent for a **plugin-shipped** hook with stdin-JSON fixtures: `plugins/soleur/test/unkept-promise-hook.test.sh` (globbed by `scripts/test-all.sh` via `plugins/soleur/test/*.test.sh`; no incident-sandbox dependency) and the envelope helper in `.claude/hooks/browser-snapshot-credential-guard.test.sh` (`jq -nc` → `bash "$HOOK"` → read decision with `jq -r`).
- Machine-owned fenced region inside a hand-edited markdown file: `<!-- taste-profile:data:start -->…:end` rewritten idempotently by `plugins/soleur/scripts/taste-profile-update.sh`.
- gitleaks: `.claude/hooks/git-commit-secret-scan.sh` runs `gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1` against the repo-root `.gitleaks.toml` and **fails open** with a `WARN:` line when the binary is absent.
- Test fixtures must be synthesized only (`cq-test-fixtures-synthesized-only`).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| TR6 names `plugins/soleur/hooks/compaction-state.test.sh` "with stdin fixtures" | **Zero** `*.test.sh` exist under `plugins/soleur/hooks/`, and `scripts/test-all.sh`'s `SUITE_GLOBS` does not include that path — a suite there would never run. | Test lands at `plugins/soleur/test/compaction-state-hook.test.sh` (globbed, plugin-shipped). |
| TR6 adds "a `components.test.ts` case asserting hooks.json binds the three events" | `components.test.ts` does **not** reference `hooks.json` at all; `plugins/soleur/test/devin-plugin.test.ts` and `.claude/hooks/devin-matcher-parity.test.sh` are the files that parse it. | The binding assertion lands in the new hook suite (it already reads `hooks.json` to locate the script), not in `components.test.ts`. |
| FR1 derives the phase "via the same mapping as `.claude/phase-surface-map.json`" | That file is repo-only; a marketplace install has no copy. | The mapping is an in-script `case` over `soleur:{brainstorm,plan,work,review,qa,compound,ship,one-shot}`; a drift assertion in the new suite compares the case arms against the repo-side JSON so the two cannot silently diverge. |
| Spec assumes `PostCompact` stdin carries `compact_summary` | The published docs' `PostCompact` example input shows only `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `trigger`. The CTO pass reported `compact_summary` present; the two disagree. | **TR4 decides it empirically before FR4 is implemented.** FR4's fallback (already the design) reads allowlisted fields from git/`gh`/the transcript, never from summary prose — so FR4 does not depend on the answer. |
| Spec FR4 writes into `knowledge-base/project/specs/<branch>/session-state.md` | Today that file is written **only** by `one-shot/SKILL.md`, with headings `## Plan Phase` / `### Errors` / `### Decisions` / `### Components Invoked`. | The hook owns **only** a `<!-- compaction-checkpoint:start -->…:end` block appended after existing content; it never parses or rewrites the skill-owned headings. |
| Spec TR3 budget "<200 ms on a 30 MB transcript" | Unmeasured at spec time. | Measured in the new suite against a synthesized large fixture; the number lands in the hook header. |

## Open Code-Review Overlap

One open `code-review` issue names a file this plan edits (65 open issues scanned):

- **#4133** — *follow-through(#4116): Schema parity test for `## Observability` block* — names `plugins/soleur/skills/plan/SKILL.md` §2.9. **Disposition: Acknowledge.** This plan edits `plan/SKILL.md`'s `/clear` prose (exit gate / post-generation options), a different region; the §2.9 observability-schema drift surface is untouched and needs its own cycle. The issue remains open.

## Files to Create

- `plugins/soleur/hooks/compaction-state.sh` — the one hook script, dispatching on `hook_event_name`.
- `plugins/soleur/test/compaction-state-hook.test.sh` — stdin-fixture suite + guard mutation matrix.
- `plugins/soleur/test/fixtures/compaction/` — synthesized transcript fixtures (`no-boundary.jsonl`, `one-auto.jsonl`, `two-auto.jsonl`, `manual.jsonl`, `high-ratio.jsonl`, `large.jsonl`, `malformed.jsonl`).
- `knowledge-base/engineering/architecture/decisions/ADR-228-compaction-signal-read-from-the-transcript.md` — ordinal **provisional** (224/225/227 are claimed across the 92 pushed refs; re-verify against freshly fetched `origin/main` immediately before merge).

## Files to Edit

- `plugins/soleur/hooks/hooks.json` — add `PreCompact` (matcher `manual|auto`), `PostCompact` (matcher `manual|auto`), and a `SessionStart` entry with matcher `compact`.
- `plugins/soleur/skills/plan/SKILL.md` — make the two unconditional `/clear` sentences conditional (Exit Gate step 3 and the Post-Generation question).
- `plugins/soleur/skills/work/SKILL.md` — make the `Tip: After shipping, run /clear…` display conditional.
- `plugins/soleur/skills/one-shot/SKILL.md` — Step 8: carry any fresh-session recommendation into the final resume prompt; never pause for it.
- `plugins/soleur/devin/INSTRUCTIONS.md` — under `## Hooks and completion`: compaction hooks are Claude-only; `PostCompaction` remains unmeasured (#8172 closed without a positive measurement).
- `plugins/soleur/codex/INSTRUCTIONS.md` — same section, one line.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `hooks` container description + a `hooks -> kb` write edge (see `### C4 views`).
- `knowledge-base/project/specs/feat-compaction-aware-session-hooks/{spec.md,tasks.md}` — fold the six Research Reconciliation corrections into the spec; `tasks.md` is generated.

## Implementation Phases

Phases are ordered by **dependency**, not by file: the payload probe (Phase 0) decides the contract every later phase codes against, and FR4 is sequenced after the ordering probe.

### Phase 0 — Payload + ordering probe (TR4, TR5) — blocking

**The load-bearing unknown is transcript FLUSH STATE, not event metadata.** `source` matcher values and the `trigger` field are documented; what is not documented — and what FR1/FR2 entirely rest on — is whether the *current* compaction's `compact_boundary` record is already written to `transcript_path` at the moment `SessionStart:compact` runs. The "14 lines after" evidence above shows the hook's output landed *after* the boundary in the finished file; it does **not** show the boundary was on disk when the hook ran. If it is not, `count_auto` is off by one and `trigger`/ratio are read from the *previous* compaction — the rule fires on the wrong event, and every fixture-based test would still pass.

1. Write a throwaway marker hook (scratchpad path, `SOLEUR_COMPACT_PROBE`) bound in `.claude/settings.local.json` to `PreCompact`, `PostCompact` and `SessionStart`. On **every** event it appends: `date -u +%s.%N`, `hook_event_name`, `source`/`trigger`, the sorted top-level stdin keys, **the `transcript_path` value itself**, **`grep -c '"subtype":"compact_boundary"' "$transcript_path"`**, and **the last boundary's `trigger` + `preTokens`** — i.e. exactly what FR1 will read, read at the moment FR1 will read it.
2. Force one `/compact` in a scratch session; then let one auto-compaction occur (or replay the measured evidence if none occurs within the session).
3. Record in the hook's header comment, dated: the literal `source` value on the post-compaction SessionStart; **whether the boundary count observed at SessionStart:compact includes the compaction that just happened**; **whether `transcript_path` is unchanged across the compaction** (a rotation would zero the count); whether `compact_summary` is present on `PostCompact` stdin; and the `PostCompact` vs `SessionStart:compact` firing order.
4. Delete the probe and its `settings.local.json` entry (that file is gitignored; nothing ships).

**Pre-authorized fallback — decided now, not escalated.** If the boundary is *not* flushed at SessionStart time, or `source` is not `compact`, FR1/FR2 read their inputs from a scratch file instead: `PostCompact` (which carries `trigger` on its own stdin) writes `{count, trigger, preTokens, postTokens}` to `${TMPDIR:-/tmp}/soleur-compaction-<session_id>.json`, and `SessionStart:compact` prefers that file when it is newer than the last boundary it can see. **This is not the counter store the Cut List rejected:** that one was rejected for living *in the user's repo* (an un-addable `.gitignore` entry) and for piggybacking a manifest another hook overwrites. A per-session file under `TMPDIR` has neither problem, is never committed, and is disposable. Deciding it here means the probe's outcome changes at most ~15 lines of the hook, not the spec.

### Phase 1 — `compaction-state.sh`, read path (FR1, FR2)

RED first (`cq-write-failing-tests-before`): the suite's `SessionStart:compact` cases fail against an absent script.

- Dispatch on `hook_event_name`; `SOLEUR_DISABLE_COMPACTION_HOOKS=1` short-circuits at the top; `set -uo pipefail` + **`trap 'exit 0' ERR EXIT`** — the `EXIT` arm is load-bearing, because a `set -u` unbound-variable expansion terminates the shell directly with status 1 **without** firing an `ERR` trap, which is exactly the silent-drop the fail-open contract exists to prevent.
- **stdout carries the JSON envelope and nothing else.** On the `SessionStart` path a single stray non-JSON byte on stdout invalidates the whole output, so the `SOLEUR_COMPACTION_*` markers are emitted **inside `additionalContext`** (where they are model-visible, which is their purpose) and every diagnostic goes to stderr. The `PreCompact` path is the one exception — there stdout is plain text by contract.
- Scope-guard: `git rev-parse --is-inside-work-tree` must be `true`, else exit 0 silently.
- Read `transcript_path` from stdin via `jq -r '.transcript_path // empty'`; if empty or unreadable, exit 0.
- Derive, with bounded reads: `count_total` (`grep -c '"subtype":"compact_boundary"'`), `count_auto`, and the last boundary's `trigger` / `preTokens` / `postTokens` (`grep '"compact_boundary"' | tail -1 | jq`).
- Derive the phase: last `"name":"Skill","input":{"skill":"soleur:<name>"` in the transcript → in-script `case` → phase; unknown/absent → `unknown`, and the directive omits the phase clause rather than guessing.
- Build `additionalContext` with `jq -n --arg` only; clamp per-field to printable + newline; truncate the whole string at 8,000 chars (headroom under the 10,000 cap).
- **Recommendation rule (FR2):** `trigger == "auto"` AND (`count_auto >= ${SOLEUR_COMPACTION_COUNT_THRESHOLD:-2}` OR `postTokens/preTokens > ${SOLEUR_COMPACTION_RATIO_THRESHOLD:-0.15}`). Ratio computed with `awk`, guarded against `preTokens == 0`.

### Phase 2 — `PreCompact` summary shaping (FR3)

Plain-text stdout, **not** JSON — the wire contract externally verified in the upstream thread (PreCompact stdout is merged with any `/compact "…"` argument and delivered to the summarizer as custom instructions). Pointer-style: name the identifiers and the paths to preserve, never inline file bodies. Exit 0 always; never exit 2.

### Phase 3 — Ordering probe result applied, then checkpoint (FR4) + Guard 1

- Compose the block from **allowlisted fields only**: branch (`git branch --show-current`), worktree path **repo-relative** — the basename of `git rev-parse --show-toplevel`, never the absolute path, which routinely carries the OS username (`/home/<name>/…`) and is the one allowlisted field gitleaks cannot flag (gdpr-gate `GDPR-Art-6`, Art. 4(1)/5(1)(c)) —, PR # and issue # (`gh pr view --json number` / the plan frontmatter), plan path, phase, `count_total`/`count_auto`, last `trigger`/`preTokens`/`postTokens`, ISO timestamp, and the provenance comment. **Never** transcript prose, `compact_summary` prose, user prompts, or `tool_result` bodies.
- Run gitleaks over the rendered block before writing (Guard 1). On a finding: refuse the write, emit `SOLEUR_COMPACTION_CHECKPOINT_REFUSED reason=gitleaks-hit` to stdout, exit 0. On a missing binary: `WARN:` to stderr, skip the write, exit 0 (mirrors `git-commit-secret-scan.sh`'s fail-open).
- Idempotent block replace between `<!-- compaction-checkpoint:start -->` and `<!-- compaction-checkpoint:end -->`; create the file with just the block if absent; never touch other headings.
- **Skip guard:** if `knowledge-base/project/specs/<branch>/` does not exist, do nothing and exit 0. On `main`, a hotfix branch, a detached HEAD, or a branch whose name contains `/`, there is no spec directory and the hook must not create one.
- **Git contract (decided, not deferred):** the block **is** meant to be committed. `session-state.md` is already a tracked artifact that `one-shot` writes and `ship` stages along with the rest of `specs/<branch>/`, so the checkpoint inherits an existing commit path rather than inventing one — and a resume in a *fresh session on the same worktree* reads the working tree, so it is useful before it is ever committed. The accepted cost is that the working tree is dirty mid-session; that is already true of `session-state.md` today, and the block is small, deterministic and confined between its two markers, so it produces a stable one-hunk diff rather than churn. A `/tmp` location was considered and rejected for this slice: it would not survive the worktree move that a genuine fresh-session resume implies.

### Phase 4 — hooks.json bindings + harness docs (FR6)

Three entries added; the existing `startup|resume|clear|compact` → `codex-session-start.sh` entry is untouched. One line each in `devin/INSTRUCTIONS.md` and `codex/INSTRUCTIONS.md` under `## Hooks and completion`.

### Phase 5 — Prose retirement (FR5)

Each `/clear` sentence becomes conditional on the injected signal. The resume prompt itself stays **mandatory and unconditional** (`wg-end-of-work-emit-resume-prompt`, `cm-when-proposing-to-clear-context-or`) — only the *recommendation to start fresh* becomes conditional.

### Phase 6 — ADR + C4 + spec/tasks reconciliation

### Phase 7 — Full battery, `/soleur:gdpr-gate` on the FR4 writer, review

## Architecture Decision (ADR/C4)

### ADR

**ADR-228 — "The compaction signal is read from the transcript, not from a counter file"** (create; ordinal provisional). Decision: compaction count, trigger and token ratio are derived from the session transcript's own `compact_boundary` records at `SessionStart:compact`; no plugin- or repo-side counter store is introduced; `PostCompact` is used only where it is the sole source (the checkpoint write). Alternatives Considered must record: (a) the `.claude/.session-manifests` piggyback and why it fails (repo-only, overwritten on every SessionStart including `compact`), (b) a plugin-owned counter store and why it loses (extra write path, un-addable `.gitignore` entry in a user's repo, dependency on an undocumented hook ordering), (c) skill-prose-only and why it loses (the model cannot observe its own compaction count).

### C4 views

**Container + relationships** (`model.c4`; `views.c4` needs no new `include` — both elements already render):

1. `platform.engine.hooks` description currently reads `"PreToolUse Guards + Rewriter + PostToolUse hints"` — the change adds compaction-lifecycle events, so the technology/description line is falsified by this PR and must be amended.
2. **New edge:** `hooks -> kb` currently exists as *read-only* (`"Reads context_queries artifacts (skill-scoped injection)"`). The checkpoint writer makes the Hook Engine a **writer** into the knowledge base — a genuinely new access relationship, added as its own edge naming the allowlisted-fields + gitleaks-gated contract.

**Completeness enumeration** (mandate: all three `.c4` files read, not grepped): **external human actors** — none added (the operator already exists; no new correspondent or recipient). **External systems/vendors** — none added; the transcript is a local file written by the already-modelled `claude` Agent Runtime, and gitleaks is a local binary, not a service. **Containers/data stores touched** — `platform.engine.hooks` (amended) and `platform.plugin.kb` (new write edge). **Access relationships that change** — exactly the one above (kb read → read+write from the Hook Engine).

**Cardinality gate:** `model.c4` embeds derived counts ("98 workflow skills", "65 domain agents"). This PR adds no skill and no agent, so no count moves; `plugins/soleur/test/c4-count-parity.test.sh` is green at HEAD and must be re-run green after the edit (it is the authority, not the actor enumeration above).

## User-Brand Impact

**If this lands broken, the user experiences:** a `/soleur:work` or `/soleur:one-shot` session that is told to abandon a healthy pipeline mid-flight (a spurious fresh-session recommendation), or — with a malformed `additionalContext` envelope — a post-compaction turn with *no* re-read directive at all, which is today's behaviour and therefore the fail-open floor.

**If this leaks, the user's workflow and source data are exposed via:** the FR4 checkpoint writer copying transcript- or summary-derived text into `knowledge-base/project/specs/<branch>/session-state.md`, which later workflow steps **commit and push to the user's own git remote** — a silent exfil of secrets, prompts or third-party content through the user's own history.

**Brand-survival threshold:** `single-user incident`.

CPO sign-off is required at plan time and is satisfied by carry-forward from the brainstorm (`## Domain Assessments` → Product). `user-impact-reviewer` runs at PR review per `review/SKILL.md`.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm's `## Domain Assessments`; no scope pivot since).

### Engineering

**Status:** reviewed
**Assessment:** `PostCompact` stdout is never model-visible; `SessionStart` is. Statusline `context_window` data is unreachable from hooks. `.session-manifests` is repo-side and overwritten per SessionStart, so no piggyback. `hooks.json` already binds a `compact` SessionStart matcher for the Codex shim, so adding `PreCompact`/`PostCompact` is trivial. The checkpoint slice is the large one (redaction + commit semantics). Recommended decision rule adopted verbatim as FR2; ADR recommended and scheduled as Phase 6.

### Product

**Status:** reviewed
**Assessment:** Phase 4 milestone, internal-tooling row — protects alpha-tester validation on the CLI plugin rather than adding a customer-facing surface. Nudge at the next phase boundary, never mid-`one-shot`; threshold as env override, not a user-facing setting; define precedence between the hook and the skills that already write `session-state.md`. Success signal: compaction/resume-tagged learnings per month, `unkept-promise-hook.sh` firings after compaction, alpha-tester "the agent lost track" mentions.

### Legal

**Status:** reviewed
**Assessment (plan-time gdpr-gate run, 2026-09-18):** one `Important` finding — the absolute worktree path carries the OS username into a tracked, pushed file; folded in as a repo-relative path + AC22a. No Art. 9 surface, no Chapter V transfer, no disclosure update. FR1–FR3 are purely local and already covered by privacy policy §4.2 ("workflow state stored locally") — no disclosure change. FR4 must be allowlist-only structured fields with a gitleaks pass before write, never transcript prose or `tool_result` bodies. The `/soleur:gdpr-gate` path regex does not match `plugins/soleur/hooks/**`, so run it manually against the FR4 writer (Phase 7). A Jikigai-operated telemetry sink would require privacy-policy / DPD §2.3 / Art. 30 updates in the same PR — out of scope here and the reason #8324 is specified local-only.

**Brainstorm-recommended specialists:** none named beyond the triad.

### Product/UX Gate

**Tier:** none — no path in `## Files to Create`/`## Files to Edit` matches the UI-surface glob superset (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, email templates). Hooks, skill markdown, `.c4` and ADR only.
**Pencil available:** N/A (no UI surface).

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_COMPACTION_DIRECTIVE emitted to stdout by compaction-state.sh on every SessionStart:compact fire, carrying count_total, count_auto, trigger, ratio, phase, recommend=true|false"
  cadence: "once per compaction event (measured: 11 boundaries across 22 recent local sessions)"
  alert_target: "none — layer 7 (customer-installed CLI); the marker is the operator-inspectable signal, and the aggregated metric is deferred to #8324"
  configured_in: "plugins/soleur/hooks/compaction-state.sh"
error_reporting:
  destination: "stdout SOLEUR_COMPACTION_* markers (SessionStart stdout is model-visible and lands in the transcript); stderr WARN: lines for operator-visible degradations (gitleaks absent, transcript unreadable)"
  fail_loud: "no — fail-open by contract (a non-2 non-zero exit silently drops additionalContext), so every failure path emits a named marker instead of a non-zero exit"
failure_modes:
  - mode: "transcript_path missing, unreadable, or malformed JSON"
    detection: "SOLEUR_COMPACTION_SKIPPED reason=transcript-unreadable on stdout"
    alert_route: "operator/agent reads it in-session; asserted by the test suite"
  - mode: "jq or awk unavailable on the user's machine"
    detection: "SOLEUR_COMPACTION_SKIPPED reason=jq-unavailable"
    alert_route: "same"
  - mode: "gitleaks finds a secret in the rendered checkpoint block"
    detection: "SOLEUR_COMPACTION_CHECKPOINT_REFUSED reason=gitleaks-hit"
    alert_route: "same; the write is refused, never partial"
  - mode: "gitleaks binary absent"
    detection: "WARN: gitleaks not installed — checkpoint write skipped (stderr)"
    alert_route: "same"
  - mode: "hook runs outside a git worktree (global plugin install in an unrelated dir)"
    detection: "silent exit 0 — by design, per the plugin-hook scope-guard learning"
    alert_route: "n/a"
logs:
  where: "the session transcript itself (stdout of a SessionStart hook is recorded there); stderr to the Claude Code debug log"
  retention: "as long as the user's ~/.claude/projects transcripts are retained — local only, nothing shipped"
discoverability_test:
  command: "bash plugins/soleur/test/compaction-state-hook.test.sh"
  expected_output: "ALL TESTS PASSED"
```

No `credentials_required` — the probe is fully local and unauthenticated.

## Guard Contract

### Guard 1 — checkpoint redaction gate (gitleaks pre-write)

**Property.** No content that gitleaks classifies as a secret is ever written into the tracked `session-state.md` by this hook.

**Assembly.** The single chokepoint is `render_checkpoint_block()` → `scan_then_write()` in `compaction-state.sh`: every path that writes the block flows through `scan_then_write`, and the block is composed only by `render_checkpoint_block`. There is exactly one write site (FR4); the mutation matrix asserts a second write site cannot be added silently.

**Mutation matrix** (each edit MUST drive the suite RED):

| # | Mutation | Why it must red |
|---|---|---|
| 1 | Make `scan_then_write` return success without invoking gitleaks (the guard's own dispatch) | A guard that reports "0 scanned" and exits 0 is vacuous |
| 2 | Add a **second** write site that calls `write_block` directly, bypassing `scan_then_write`, after a compliant first | A check that stops at the chokepoint it knows about is the defect class |
| 3 | Add a field to the allowlist that interpolates raw transcript text | Allowlist drift is the leak vector the property is about |
| 4 | Move the gitleaks call to *after* the write (a reorder, not a delete) | The property is about *order/lifetime*: a delete-only battery would stay green on a scan that runs once the bytes are already on disk |
| 5 | Truncate the rendered block **before** scanning rather than after | A cap upstream of a redactor splits the token the regex was written against |

**Harness rows.** (a) Delete the seeded-secret fixture assertion from the suite — the suite must red, proving it is not self-satisfying. (b) A must-PASS input that is **not** the canonical: a checkpoint block with an unusual-but-permitted field order and a branch name containing a hyphenated token that merely *resembles* a key prefix — it must pass, proving the guard does not reject everything.

**Anchor.** The guard compares rendered content against `.gitleaks.toml` at the **repo root** — a file outside this hook's directory, reviewed independently, and the same config `lefthook`'s `gitleaks-staged` and CI's secret-scan use. One diff cannot both weaken the config and widen the allowlist without touching a file three other gates read.

## Infrastructure (IaC)

None. No server, service, cron, vendor account, DNS record, secret or firewall rule is introduced; the change is plugin markdown + one bash hook + tests. The Phase 2.8 detection scan over the plan draft and feature description found no SSH form, no systemd unit management, no secret-store write, no vendor-dashboard step, and no new cron.

## Encryption Posture

Not applicable — Phase 2.11 detection does not fire: no `*.tf`, no `supabase/migrations/*.sql`, no `cloud-init*.yml`, no `docker-compose*.yml` in the file lists, no new persistent store (the checkpoint targets an artifact that already exists and is already committed), and no new cross-component or network connection (every read and write is local filesystem).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — Phase 0 probe results are recorded, dated, in `compaction-state.sh`'s header: the literal `source` value on the post-compaction SessionStart, whether `compact_summary` is on `PostCompact` stdin, and the `PostCompact` vs `SessionStart:compact` order. Verify: `grep -c 'measured 2026-09-' plugins/soleur/hooks/compaction-state.sh` ≥ 1.
- [ ] **AC2** — On a fixture with **zero** boundaries the hook emits no directive and exits 0. Verify: the suite's `no-boundary` case.
- [ ] **AC3** — On `one-auto.jsonl` (1 auto boundary, ratio 0.10) the directive is emitted **without** a fresh-session recommendation. Verify: the emitted `additionalContext` contains `Compaction #1` and `recommend=false`, and does not contain `fresh session`.
- [ ] **AC4** — On `two-auto.jsonl` (2 auto boundaries) and on `high-ratio.jsonl` (1 auto boundary, `postTokens/preTokens` = 0.30) the recommendation **is** emitted. Both cases assert `recommend=true`.
- [ ] **AC5** — On `manual.jsonl` (2 manual boundaries, ratio 0.40) the recommendation is **not** emitted — manual compaction never triggers.
- [ ] **AC6** — Thresholds are overridable: the same `one-auto.jsonl` fixture with `SOLEUR_COMPACTION_COUNT_THRESHOLD=1` emits `recommend=true`.
- [ ] **AC7** — Exit code is 0 on every path: malformed stdin, absent `transcript_path`, unreadable transcript, non-git CWD, and `SOLEUR_DISABLE_COMPACTION_HOOKS=1`. Verify: 5 suite cases each asserting `rc=0`.
- [ ] **AC8** — `additionalContext` never exceeds 8,000 chars, asserted against the `large.jsonl` fixture.
- [ ] **AC9** — The envelope shape is `hookSpecificOutput.{hookEventName:"SessionStart", additionalContext}` — parsed with `jq -e`, not substring-matched.
- [ ] **AC10** — The phase `case` arms in the hook and the `skill_to_phase` keys in `.claude/phase-surface-map.json` agree; a suite case fails on divergence.
- [ ] **AC11** — Guard 1: a fixture seeding a synthesized fake secret into a checkpoint field is **refused** (`SOLEUR_COMPACTION_CHECKPOINT_REFUSED`, file unchanged), and all five mutation-matrix rows plus both harness rows are exercised by the suite.
- [ ] **AC12** — The checkpoint write is idempotent: running the hook twice against the same `session-state.md` leaves exactly one `<!-- compaction-checkpoint:start -->` block and does not modify any other heading. Verify: `grep -c 'compaction-checkpoint:start' = 1` plus a diff of the non-block region.
- [ ] **AC13** — `PreCompact` emits **plain text** on stdout (not JSON), exits 0, and never exits 2. Verify: the suite pipes the `PreCompact` envelope and asserts `jq -e . <<<"$out"` **fails** while the output is non-empty.
- [ ] **AC14** — `hooks.json` binds all three events to `${CLAUDE_PLUGIN_ROOT}/hooks/compaction-state.sh` with matchers `manual|auto`, `manual|auto`, `compact`; the file remains valid JSON and the referenced script is mode 100755. Verified in the new suite (not `components.test.ts`, which does not read `hooks.json`).
- [ ] **AC15** — Every `/clear` recommendation in `plan/SKILL.md` and `work/SKILL.md` is conditional; the **mandatory** resume-prompt instructions are unchanged. Verify: `grep -c 'Resume prompt (MANDATORY' plugins/soleur/skills/plan/SKILL.md` is unchanged from `origin/main`, and each remaining `/clear` recommendation sentence is preceded by a conditional clause.
- [ ] **AC16** — `devin/INSTRUCTIONS.md` and `codex/INSTRUCTIONS.md` each carry the Claude-only compaction-hook line under `## Hooks and completion`.
- [ ] **AC17** — ADR created, its ordinal re-verified free across every `origin/*` ref immediately before merge, and its `## Alternatives Considered` records all three rejected options.
- [ ] **AC18** — `model.c4` amends the `hooks` container description and adds the `hooks -> kb` write edge; `bash plugins/soleur/test/c4-count-parity.test.sh` and the `apps/web-platform/test/c4-*.test.ts` suites are green.
- [ ] **AC19** — `/soleur:gdpr-gate` has been run manually against the FR4 writer (path regex does not cover `plugins/soleur/hooks/**`) and its verdict is recorded in the PR body.
- [ ] **AC20** — Measured wall-clock of the `SessionStart` path against the `large.jsonl` fixture (≥ 30 MB) is recorded in the hook header; the suite fails if it exceeds 1 s.
- [ ] **AC21** — Full battery green: `TEST_GROUP=all bash scripts/test-all.sh` (read the rc file, never the notification).
- [ ] **AC1a** — The Phase 0 probe's flush-state finding is recorded in the hook header: whether the boundary count observed at `SessionStart:compact` includes the compaction that just fired, and whether `transcript_path` is stable across it. If it does not include it, the `TMPDIR` fallback path is the one implemented, and a suite case asserts the hook prefers the scratch file when it is newer.
- [ ] **AC7a** — A `set -u` unbound-variable fault inside the script still exits 0 and emits no partial stdout. Verify: a suite case invokes the hook with an internal variable deliberately unset and asserts `rc=0` and empty-or-valid-JSON stdout.
- [ ] **AC9a** — On the `SessionStart` path stdout parses as JSON **in full** (`jq -e . <<<"$out"` succeeds) for every fixture, including the failure fixtures — proving no marker or diagnostic leaked onto stdout.
- [ ] **AC12a** — The checkpoint write is skipped with rc 0 when `knowledge-base/project/specs/<branch>/` is absent (fixtures: detached HEAD, `main`, a branch name containing `/`), and no directory is created.
- [ ] **AC22a** — The rendered checkpoint block contains no absolute home-directory prefix: `grep -cE '(/home/|/Users/|C:\\\\Users\\\\)' <rendered block>` is 0, asserted with a fixture whose worktree sits under a synthesized `/home/<name>/` path. Closes the gdpr-gate `GDPR-Art-6` finding.
- [ ] **AC22** — Every fixture under `plugins/soleur/test/fixtures/compaction/` is synthesized (`cq-test-fixtures-synthesized-only`): no real session ids, no real paths outside this repo, no live tokens.
- [ ] **AC23** — The diff is a subset of the files named in `## Files to Create` / `## Files to Edit` **plus** the pipeline-written artifacts: `knowledge-base/INDEX.md`, `knowledge-base/project/specs/feat-compaction-aware-session-hooks/session-state.md`, and this plan file.

### Post-merge (operator)

None. Every step above is automatable in-session; there is no vendor credential to mint, no infrastructure apply, and no dashboard action.

## Test Scenarios

All in `plugins/soleur/test/compaction-state-hook.test.sh`, envelopes built with `jq -nc` and piped to `bash "$HOOK"` (the `browser-snapshot-credential-guard.test.sh` shape):

1. Zero boundaries → no directive, rc 0.
2. One auto boundary, low ratio → directive, `recommend=false`.
3. Two auto boundaries → `recommend=true`.
4. One auto boundary, ratio 0.30 → `recommend=true`.
5. Manual boundaries only, ratio 0.40 → `recommend=false`.
6. Threshold override via env → `recommend=true` on fixture 2.
7. `preTokens: 0` → no division error, rc 0, `recommend` decided by count alone.
8. Phase derivation: last skill `soleur:work` → phase `work`; no skill record → phase clause omitted.
9. Phase-map drift assertion against `.claude/phase-surface-map.json`.
10. Malformed stdin / absent `transcript_path` / unreadable transcript / non-git CWD / kill-switch → rc 0, named marker (5 cases).
11. 8k-char cap against `large.jsonl`.
12. Envelope parsed with `jq -e`; `hookEventName == "SessionStart"`.
13. `PreCompact` → non-empty, non-JSON stdout, rc 0.
14. `PostCompact` checkpoint: creates the block; re-run is idempotent; sibling headings untouched.
15. Guard 1: seeded synthesized secret → refused, file unchanged.
16. Guard 1 mutation matrix rows 1–5, each asserted to red the suite.
17. Guard 1 harness rows: assertion-deleted suite must red; non-canonical permitted input must pass.
18. `hooks.json` binding + exec-bit assertion.
19. Timing assertion on the ≥30 MB fixture.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `SessionStart:compact` does not actually fire on auto-compaction (the measurement is inferential — a hook fired, but the `source` value was not read) | Phase 0 is blocking and reads the literal `source`; the documented fallback re-binds FR1/FR2 to `PostCompact` + `UserPromptSubmit` and is a spec change, escalated |
| The current compaction's boundary is not yet flushed when `SessionStart:compact` runs — every derived value off by one, with fixture tests still green | Phase 0 measures exactly this at the moment FR1 would read it (AC1a); the `TMPDIR` scratch-file fallback is pre-authorized so the outcome costs ~15 lines, not a spec change |
| Directive is elevated-authority text the model over-trusts | Pointer-style only (paths + counts), never inlined file bodies; the recommendation is advisory and explicitly deferred to the next phase boundary |
| Spurious recommendation interrupts a healthy `/soleur:one-shot` | FR2's directive names the one-shot exception explicitly; `one-shot/SKILL.md` Step 8 carries it into the final resume prompt instead of pausing |
| An allowlisted field silently carries personal data (the absolute worktree path carries the OS username) | Path stored repo-relative; AC22a asserts no `/home/`, `/Users/` or `C:\Users\` prefix survives into the block; gitleaks cannot catch this class because a username is not a secret |
| Checkpoint write races a skill writing `session-state.md` | The hook owns only its fenced block and never parses the skill-owned headings; the block is appended, and the replace is anchored on both markers |
| `grep` over a 30 MB transcript on every compaction | Bounded reads only; AC20 measures and the suite fails above 1 s |
| Transcript format changes in a future CLI version | The suite's fixtures pin the parsed shape; a format change reds the suite rather than silently emitting nothing. The fail-open contract means the worst case is today's behaviour |
| ADR ordinal collision during the pipeline | Ordinal is provisional; AC17 re-verifies across every `origin/*` ref immediately before merge, and any renumber sweeps plan + tasks + ACs in the same edit |

## Deferred

- **#8324** — local `SOLEUR_COMPACTION` metric via the `incidents.sh` → `rule-metrics-aggregate.sh` ledger. Re-evaluate after ~30 days of dogfooding this feature.
- Devin `PostCompaction` measurement — #8172 closed without a positive measurement; the residual arm needs a cloud session where a compaction actually occurs on a branch with the marker hook bound.
