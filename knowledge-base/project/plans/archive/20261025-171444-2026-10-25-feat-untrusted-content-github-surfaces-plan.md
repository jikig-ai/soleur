---
title: "feat(security): untrusted-content framing for GitHub-sourced agent input (slices A and B of #10194)"
date: 2026-10-25
slug: untrusted-content-github-surfaces
branch: feat-untrusted-content-remaining-surfaces
issue: 10194
lane: cross-domain
type: feat
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-10-25-untrusted-content-remaining-surfaces-brainstorm.md
spec: knowledge-base/project/specs/feat-untrusted-content-remaining-surfaces/spec.md
---

# feat(security): untrusted-content framing for GitHub-sourced agent input

## Overview

ADR-287 (merged 2026-10-14) frames and scores WebFetch results only. Issue and PR text written by third parties still reaches hosted and scheduled agents unframed, and those agents hold real credentials. This plan frames three channels using the shared `apps/web-platform/server/untrusted-content.ts` module and a new source, `github`:

- **A1.** The six read-only GitHub MCP tools in `server/github-tools.ts` return their result behind the `github` preamble.
- **A2.** The four leader prompts that interpolate third-party text (`engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`) wrap it in `envelope("github", ...)` after the existing sanitize and scrub.
- **B.** `spawnClaudeEval` passes the `github` preamble to every cron spawn through `--append-system-prompt`, leaving the prompt itself untouched.
- **Subagent signal.** The classify log line gains a boolean `subagent`; a unit test sets `agent_id`; the live dev check goes on #10195's canary.

Framing is **static** (preamble/envelope, no scoring), per the CTO ruling. It follows the email/inbox/crm precedent, so it is unconditional and not behind `untrusted-content-classify` / `untrusted-content-wrap`. Rollback is revert plus redeploy, which is slower than a flag flip; this is disclosed in the PR body and the ADR.

**Not covered, stated plainly (no claim of "GitHub-sourced input is framed" anywhere):**

- Hosted Concierge `gh` CLI output. `soleur-go-runner.ts` gives the hosted agent a `gh` CLI with an installation token and tells it to run `gh issue view`. That Bash output is unframed and has no hook. Added to #11076.
- Cron Bash output as a hook-level control, attachments/KB/PDF reads (#11076), plugin-side CLI (#11077), scoring of GitHub text, flag enablement and soak (#10195), taint downgrade and LLM tier (#10196).

## Research Reconciliation — Spec vs. Codebase

| # | Spec / brainstorm claim | Reality (verified in the worktree) | Plan response |
|---|---|---|---|
| 1 | "Ships dark behind the existing flag family" | `email`/`inbox`/`crm` use `untrustedRowsResponse` unconditionally. The two flags gate only the WebFetch hook. | GitHub framing is static and unconditional, matching precedent. ADR amendment states the carve-out in its Decision section. |
| 2 | FR2 names two leader prompts | Four of five classes interpolate `scrubbedContent` via `assemblePromptText`. `knowledge.kb_drift` is decided at implementation (KB text is the user's own, so it is expected to stay unwrapped). | One helper in `prompt-assembly.ts`. |
| 3 | Brainstorm: four tools | `github-tools.ts` has six read tools; the two CI tools return strings third parties control. | All six. |
| 4 | CTO cites `github-tools.ts`; repo research cites `github-read-tools.ts` | Both right: registration and `wrapToolHandler` in `github-tools.ts`, narrowing readers in `github-read-tools.ts`. | Edit `github-tools.ts` only. |
| 5 | FR4: "hook test with `agent_id` set" | The module never reads `agent_id`. | Add `subagent` boolean; never log the id. |
| 6 | FR3: prelude for crons whose allowlist includes `gh issue view` | The derivation (allowlist tables plus `--allowedTools` flags in the `Bash(gh issue view:*)` form, plus bug-fixer's bare `Bash`) is brittle and under-covers `gh pr diff`, `gh run view`, `gh search`, `gh api`. | Apply to **every** cron spawn at the chokepoint. No regex, no census module. |
| 7 | Plan v1: prepend the preamble to the prompt | `cron-bug-fixer`, `cron-nag-4216-readiness` and `cron-skill-freshness` pass prompts that start with `/soleur:`; the prompt is the final positional argv. Prepending breaks command recognition. | Use `--append-system-prompt <preamble>` (verified in `claude --help`; single-value; unused elsewhere in the repo). The prompt string is unchanged, so single-flight comparison is unchanged. |
| 8 | Plan v1: envelope the issue body in `cron-bug-fixer` | `fixIssuePrompt(issueNumber)` embeds only the number; the skill fetches the body. | Dropped. The system-prompt preamble covers it. |
| 9 | Plan v1: hash the conversation id | `workspaceIdHash` is already hashed; the raw field is `sessionId`. | Moved to the #10195 gate with the PA-8 amendment, as separate scope. |
| 10 | CTO: attachments partly covered; repo research: PDF text inlined unwrapped | Conflict, unresolved. | Out of scope; in #11076. |

## Review revisions (2026-10-25, 13-seat panel at `8c5eb4890a`)

Findings that changed the plan after implementation:

- **The leader-prompt envelope (Phase 2) is latent.** `agent-on-spawn-requested.ts` calls `userPromptTemplate` without `scrubbedContent` and nothing else supplies it (verified by grep; five seats concurred), so the four classes always render their empty-body fallback. The envelope and its tests stay as a guard for a future feeder; the ADR, PR body and #11076 say so, and `sourceRef`, which the model does see, is now reduced to one control-free line.
- **A GitHub-text MCP read tool was missed:** `workstream_issues_list` returns issue titles and descriptions to the agent. It now carries the same preamble.
- **The preamble wording** was reworded to read correctly as a system-prompt append (the plan's Phase 3.2 required this and the first implementation did not), to name advisories, and to keep the user's own task authoritative so a legitimate request to work an issue is not read as data. The hosted agent's GitHub-read prompt got a matching note.
- **Uncovered paths** found by the panel are listed in the ADR amendment and on #11076: GitHub Actions `claude-code-action` workflows, two crons that pass a comment body as the whole prompt, `cron-compound-promote.ts`, tool error text and write-tool results.
- Test additions: a tool-list census (read set plus write set equals the registered set), real-shaped cron flags, a check that only the substrate passes `--append-system-prompt`, a single-`resolveClaudeBin()`-call check, a scorer-error `subagent` arm, and content-retention and `sourceRef` cases.

## Research Insights

- **Module surface** (`server/untrusted-content.ts`): `UntrustedSource` union, `UNTRUSTED_PREAMBLES` and `FLAG_THRESHOLDS` are `Record<UntrustedSource, …>`, so adding `github` fails the build until complete. `FLAG_THRESHOLDS.github` is required by the type but unused (nothing calls `classify(…, "github")`); a comment says so. `untrustedRowsResponse` puts the preamble in `content[0]` and compact JSON in `content[1]`. `envelope()` strips control characters before the 256 KiB cap.
- **GitHub tools:** `wrapToolHandler` returns one pretty-printed JSON block and builds the error branch with `isError`. The tool file declares its own `ToolTextResponse` with optional `isError`, so a wrapper returning the module's shape is assignable. No test asserts tool-level response text. Reader payloads are already bounded (issue body 10 KB, comments 4 KB, logs 100 lines).
- **Leader prompts:** every class sets `promptVersion: "v1.0.0"`; `agent-on-spawn-requested.ts:708` writes it to `prompt_version`, which is the audit record that tells a later reader which prompt text produced a run. Every module uses `content || "(no … provided)"`, so an unconditionally enveloped empty string would defeat the fallback.
- **Cron chokepoint:** `spawnClaudeEval` destructures `{ cronName, runId, prompt }`, then branches to a guarded or unguarded path; the single `spawn(claudeBin, ["--strict-mcp-config", ...budget, ...outputFormatFlags, ...flags, prompt])` is the only claude-binary spawn in `server/inngest`. Single-flight compares `prompt`.
- **Learnings applied:** sanitize before wrapping (`2026-05-06-new-prompt-injection-site-needs-sanitization-parity.md`); no new scoring without its own corpus (`2026-10-13-a-heuristic-scorer-…`); workflow spawns skip PostToolUse while direct Agent spawns do not (`2026-06-10-workflow-spawns-skip-posttooluse-…`), so no single answer for subagents.
- **Open code-review overlap:** none.
- **Premise validation:** #10194, #4671, #9601, #11076, #11077, #10195, #10196 open; #10192 merged 2026-10-14; cited files and symbols exist on the base.
- **Plan-review revisions (2026-10-25):** five reviewers; applied: prelude moved to `--append-system-prompt` and made unconditional (rows 6-8 above); bug-fixer envelope and conversation-id hash cut; empty-content guard in the helper; one `wrapToolHandler` with an optional source instead of a second wrapper; stringify inside the try; Guard Contracts trimmed; hosted-Concierge `gh` output disclosed as uncovered; ADR carve-out wording; silent under-action risk added to failure modes.
- **Property List:** (P1) on the channels this PR frames (the seven GitHub-text MCP read tools and every Inngest cron spawn; the leader-prompt envelope is latent, see Review revisions), a third party cannot present instruction-shaped text to an agent without a data-only caution; (P2) every cron spawn carries the caution, so a new GitHub-reading cron cannot miss it; (P3) no new personal data enters logs.
- **Cut List:** per-tool sources (identical preamble); scoring or a hook for GitHub text (needs its own corpus; deferred to the #10195 soak); a CLI PostToolUse hook for cron output (#11076); a new flag (precedent is unconditional framing); a derived cron census and prelude module (replaced by unconditional injection); cron-bug-fixer envelope (false premise); conversation-id hash (separate scope).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "`github_read_issue*` / `github_read_pr*` MCP tools … call the shared `untrustedRowsResponse` (add a `github_issue` source)" [issue #10194] | Phase 1 | mapped (source named `github`) |
| 2 | "Cron GitHub issue / PR bodies reaching agents via `gh issue view` allowlists" [issue #10194] | Phases 2, 3 | mapped |
| 3 | "WebFetch calls made inside Task subagents (hook coverage unverified)" [issue #10194] | Phase 4 | mapped (unit test now, live check via #10195) |
| 4 | "Plugin-side CLI sessions; KB file reads and attachments; Playwright MCP" [issue #10194] | — | descoped — justification: operator chose slices A and B on 2026-10-25; tracked in #11076 and #11077 |
| 5 | "Each surface either routes through `server/untrusted-content.ts` … with a test, or is recorded as out of scope with a reason" [issue #10194] | Phases 1-4 tests + #11076/#11077 | mapped |
| 6 | "Slices 1 and 2" [operator, 2026-10-25] | Whole plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| `github` source and six tools | "`github_read_issue*` / `github_read_pr*` MCP tools" | asked (the two CI tools are inferred — justification: same wrapper, same attacker-writable class, no added code) |
| Leader-prompt envelope | "only a PII scrub today, `leader-prompts/prompt-assembly.ts`" | asked |
| Cron preamble via `--append-system-prompt` for every cron | "`gh issue view` allowlists" | asked (broadened to all crons — justification: the allowlist-derived set under-covers `gh pr diff`, `gh search`, `gh api`, and costs a census module) |
| `subagent` log boolean | "hook coverage unverified, see ADR-287" | inferred — justification: the only way a live session shows subagent coverage without logging an id |
| ADR-287 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` |
| C4 description edit | — | inferred — justification: the API container description names the annotator; kept only if the sentence is falsified (Phase 5 checks) |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform/server`, `knowledge-base`
- Planned files: ~13 | Estimated changed lines: ~300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

**If this lands broken, the user experiences:** a hosted agent or scheduled cron that still follows instructions planted in an issue or PR comment, with no sign to the founder; or, if the framing is wrong, a triage, PR-review or cron run that quietly does less than before because the model treats a legitimate instruction as data.

**If this leaks, the user's workflow and credentials are exposed via:** an attacker-written issue or PR comment steering an unattended agent that holds `GH_TOKEN` and push/PR tools. Static framing lowers this; it does not remove it (annotate-only; no capability downgrade until #4672/#10196), and hosted Concierge `gh` output stays unframed.

- **Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true`. The CPO assessed this scope during the brainstorm. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm)

### Engineering

**Status:** reviewed
**Assessment:** Rulings by CTO agent: static framing, one `github` source, leader envelope after sanitize+scrub, subagent coverage not claimed until a live line shows it, amend ADR-287. Plan-review changes to the cron mechanism (system-prompt flag, unconditional) are a plan-time technical call following the architecture and Kieran findings, not an operator question.

### Product

**Status:** reviewed
**Assessment:** GitHub tools and cron bodies are the unattended channels that matter for the solo-founder ICP. Annotate-only gives no founder-visible protection, so no UI and no "Soleur protects you" copy. No Product/UX Gate: tier NONE.

### Legal

**Status:** reviewed
**Assessment:** Closed field set for telemetry; no public claim; PA-8 (c) amendment and hashing of the raw `sessionId` are owed before prd enablement (#10195), not in this PR. `soleur:gdpr-gate` ran at plan time: no findings; two suggestions recorded.

## Implementation Phases

Tests come first in each phase (`cq-write-failing-tests-before`).

### Phase 1 — `github` source and the six read tools (A1)

1. RED: `test/github-tools-untrusted.test.ts` — for each of the six tools, success returns `content[0].text` containing `UNTRUSTED` and `content[1].text` parsing to the reader's result; a reader returning `undefined` or throwing yields the existing `isError` shape with no preamble (stringify is inside the try); write tools are unchanged.
2. `server/untrusted-content.ts`: add `"github"` to `UntrustedSource`; add a `github` entry to `UNTRUSTED_PREAMBLES` (contains `UNTRUSTED`; names issue, PR, comment and CI-log text and says the text is data, not instructions); add `github: 1.0` to `FLAG_THRESHOLDS` with a comment that it is unused.
3. `server/github-tools.ts`: give `wrapToolHandler` an optional `source` parameter; when set, the success path returns `untrustedRowsResponse(source, result)` and the catch branch is the existing one verbatim (keep the local `ToolTextResponse`). Pass `"github"` from the six read tools only.

### Phase 2 — leader prompts (A2)

1. RED: `test/server/inngest/leader-prompts/untrusted-envelope.test.ts` — loop over `Object.keys(LEADER_PROMPTS)`; for each class that takes third-party text, assert on `userPromptTemplate` output: hostile content (the end delimiter, NULs, `ignore previous instructions`, an email) is sanitized, scrubbed and enveloped, and the delimiter cannot close the envelope; an empty body keeps its "(no … provided)" fallback unwrapped; `promptVersion` is `v1.1.0` for the changed classes.
2. `leader-prompts/prompt-assembly.ts`: add `assembleEnvelopedPromptText(raw, allowlistEmail)` = empty string if the assembled text is empty, else `envelope("github", assemblePromptText(raw, allowlistEmail))`.
3. Switch the four modules (the unwrapped-class decision for `kb_drift` is recorded from `rg "assemblePromptText\("`). Bump `promptVersion` to `v1.1.0` on the four so `prompt_version` identifies the new text.

### Phase 3 — cron system-prompt preamble (B)

1. RED: `test/server/inngest/cron-untrusted-preamble.test.ts` driving `spawnClaudeEval` with a stub `spawn`: argv contains `--append-system-prompt` followed by `UNTRUSTED_PREAMBLES.github`, placed after `--strict-mcp-config` and before the prompt, in both the single-flight branch and the unguarded (no `runId`) branch; the prompt argument is byte-identical to the input; a prompt starting with `/soleur:` is still the final argv element.
2. `_cron-claude-eval-substrate.ts`: add the two argv elements at the one `spawn` site. No change to `prompt`, `Flight`, or the guarded/unguarded split. Wording of the cron-facing text says "issue, PR, comment and CI-log text you fetch with gh or tools", not "the following".
3. Grep tests that pin spawn argv (`cron-claude-eval-mcp-flags.test.ts`) and update only what the new elements legitimately change.

### Phase 4 — subagent signal

1. RED: extend `test/untrusted-content-wiring.test.ts` — hook input with `agent_id` set annotates identically and logs `subagent: true`; without it `subagent: false`; the logged object has no `agent_id` key. This proves the derivation only, not that the SDK fires the hook for Task subagents.
2. `untrusted-content.ts`: add `subagent` to the classify log.
3. Comment on #10195 adding a dev canary procedure: with the classify flag on in dev (after the typed-yes flag creation), run a session that spawns a Task subagent doing a WebFetch and look for one `untrusted-classify` line with `subagent=true`. #10194 stays open until that line exists.

### Phase 5 — records

1. Amend ADR-287 (section dated 2026-10-25). The Decision section states: the `github` source, static framing is unconditional and the flags gate only the scorer and hook, the four leader classes, the cron system-prompt preamble, the `subagent` field. Known limitations list hosted Concierge `gh` output, cron Bash output, attachments/KB, plugin CLI, subagent coverage unverified, with #11076/#11077/#10195 pointers.
2. `diagrams/model.c4`: edit the API container description only if the existing ADR-287 sentence is falsified by the change; if edited, run the C4 tests and `plugins/soleur/test/c4-count-parity.test.sh`.
3. Comment on #11076: add "hosted Concierge `gh` CLI output" to its scope.
4. PR body: unconditional framing and revert-based rollback; `Ref #10194` and `Ref #4671`, not `Closes`; no public claim; PA-8 amendment and `sessionId` hashing owed before #10195 enablement; the list of uncovered paths above.

## Guard Contract

### Guard 1 — every cron spawn carries the preamble

**Property.** Every claude-binary spawn made through the cron substrate passes the `github` preamble as a system-prompt append, without altering the prompt argument.

**Assembly.** The single `spawn(claudeBin, …)` in `_cron-claude-eval-substrate.ts`, reached by `spawnClaudeEval`'s guarded and unguarded branches. The test drives both branches and also asserts, by reading the substrate source, that the file has exactly one `spawn(claudeBin` site, so a second spawn site cannot appear without reddening it.

**Mutation matrix.**

| # | Edit (must turn the suite RED) | Why it matters |
|---|---|---|
| 1 | Delete the two argv elements | the property itself |
| 2 | Add them only on the guarded branch | a second member after a compliant first |
| 3 | Place them after `prompt` (last argv element) | position: the prompt must stay the final positional |

**Harness rows.** Must-PASS inputs that are not the canonical: a `/soleur:…` prompt (stays last and byte-identical) and a cron with a different `flags` shape. Suite edit that must go RED: stub `spawn` never invoked, expected to fail on a floor of one captured spawn per branch.

**Anchor.** The preamble text is read from `UNTRUSTED_PREAMBLES.github`, the same table the MCP tools use, so one edit cannot weaken the cron copy alone.

### Guard 2 — leader-prompt envelope

**Property.** No leader-prompt module puts third-party text into its user prompt except through `assembleEnvelopedPromptText`.

**Assembly.** The `LEADER_PROMPTS` registry (`Object.keys`) and each module's `userPromptTemplate` output. The test loops the registry, so a new class is covered by construction.

**Mutation matrix.**

| # | Edit (must turn the suite RED) | Why it matters |
|---|---|---|
| 1 | Revert one module to `assemblePromptText` | the property for one member |
| 2 | Wrap before sanitize (swap the helper's order) | NUL padding must not push text past the cap |
| 3 | Add a sixth class interpolating raw content | a new member |

**Harness rows.** `knowledge.kb_drift` (or any class with no third-party content) must pass without an envelope; a body containing the end delimiter must not close the envelope.

**Anchor.** `promptVersion` is asserted equal to `v1.1.0` for the changed classes in the same test, so an edited prompt without a bump fails.

## Files to Edit

- `apps/web-platform/server/untrusted-content.ts`
- `apps/web-platform/server/github-tools.ts`
- `apps/web-platform/server/inngest/leader-prompts/prompt-assembly.ts`
- `apps/web-platform/server/inngest/leader-prompts/engineering.pr_review_pending.ts`
- `apps/web-platform/server/inngest/leader-prompts/engineering.ci_failed.ts`
- `apps/web-platform/server/inngest/leader-prompts/triage.p0p1_issue.ts`
- `apps/web-platform/server/inngest/leader-prompts/security.cve_alert.ts`
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
- `apps/web-platform/test/untrusted-content-wiring.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-287-untrusted-content-annotate-not-block-heuristic-first.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (conditional, Phase 5.2)

## Files to Create

- `apps/web-platform/test/github-tools-untrusted.test.ts`
- `apps/web-platform/test/server/inngest/leader-prompts/untrusted-envelope.test.ts`
- `apps/web-platform/test/server/inngest/cron-untrusted-preamble.test.ts`

## Open Code-Review Overlap

None. Checked the open `code-review` issues against the touched server paths, ADR-287 and `model.c4`.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-287 (Phase 5.1). This extends its source table and adds an unconditional static-framing arm; it is a deliverable of this plan, not a follow-up.

### C4 views

Read `model.c4`: the API container (line ~133) describes the flag-gated WebFetch annotator. Checked against the completeness enumeration: external human actors — none new; external systems — GitHub already modeled; data stores — none touched; actor↔surface access — unchanged. Phase 5.2 edits the description only if the sentence becomes false; `views.c4` and `spec.c4` need no change.

### Sequencing

True on merge.

## Observability

```yaml
liveness_signal:
  what: untrusted-classify log lines carry subagent=true|false; static framing has no emit of its own
  cadence: per WebFetch result while the classify flag is on (off in prd until #10195)
  alert_target: Better Stack (WARN, app-container)
  configured_in: apps/web-platform/server/untrusted-content.ts
error_reporting:
  destination: existing mirrorWithDebounce to Sentry for classifier faults; tool errors keep isError responses
  fail_loud: wrapper failures return isError and show in the agent transcript and tool-attempt telemetry
failure_modes:
  - mode: GitHub tool wrapper returns a malformed block
    detection: github-tools-untrusted.test.ts per-tool shape assertions; isError rate on github_read_* in tool-attempt telemetry
    alert_route: CI red before merge; Better Stack query after
  - mode: a cron spawn loses the preamble
    detection: cron-untrusted-preamble.test.ts (both branches, single-spawn-site assertion)
    alert_route: CI red
  - mode: enveloped leader or cron task silently under-acts (model treats a legitimate instruction as data)
    detection: leader spawn outcomes grouped by prompt_version (v1.0.0 vs v1.1.0) in the agent-spawn table; compare label/comment action rate after deploy
    alert_route: query after deploy; revert if the v1.1.0 action rate drops
  - mode: subagent WebFetch is not classified
    detection: dev canary on #10195 looks for subagent=true
    alert_route: #10194 stays open until observed
logs:
  where: Better Stack via Vector (WARN level)
  retention: 90 days (PA-8)
discoverability_test:
  command: git grep -c "subagent" -- apps/web-platform/server/untrusted-content.ts
  expected_output: "untrusted-content.ts:"
```

The discoverability command checks only that the field exists in source; static framing has no runtime emit, so this is the honest minimum.

## Test Scenarios

1. Each of the six GitHub tools returns the preamble block first and round-tripping JSON; errors and stringify failures stay bare `isError`.
2. A hostile issue body is sanitized, scrubbed and enveloped for all four leader classes; the delimiter cannot close the envelope.
3. An empty leader body keeps its existing fallback line, unwrapped.
4. Every cron spawn, in both branches, carries `--append-system-prompt` with the `github` preamble; the prompt argument is untouched and a `/soleur:` prompt remains the final argv element.
5. Hook input with `agent_id` logs `subagent: true` and never the id.
6. Table completeness: `github` present in both `Record`s; the preamble contains `UNTRUSTED`.

## Acceptance Criteria

- [ ] `UntrustedSource` includes `github`; both `Record` tables complete; typecheck green.
- [ ] Six GitHub read tools return preamble + JSON through `wrapToolHandler`'s optional source; write tools unchanged.
- [ ] Four leader classes envelope their third-party text after sanitize+scrub, guard empty content, and carry `promptVersion` `v1.1.0`; the `kb_drift` decision is recorded.
- [ ] `spawnClaudeEval` passes `--append-system-prompt` with the `github` preamble in both branches; the prompt argument is byte-identical.
- [ ] Classify log has `subagent`; no `agent_id`, path, title or matched text in any new field.
- [ ] Both guard contracts' mutation rows exist as test cases or are exercised once during work and noted in the PR; harness rows and floors exist.
- [ ] ADR-287 amended with the carve-out in its Decision section and a Known-limitations list; `model.c4` edited only if falsified, with C4 tests green if so.
- [ ] Comments added on #10195 (live `subagent=true` canary procedure; PA-8 amendment and `sessionId` hashing before enablement) and #11076 (hosted Concierge `gh` output).
- [ ] PR body states: unconditional static framing, revert-based rollback, `Ref` not `Closes`, no public claim, and the uncovered paths.
- [ ] `soleur:engineering:review:user-impact-reviewer` ran at review.

## Non-Goals

Flag creation or flipping, scoring of GitHub text, new PostToolUse hooks, hosted Concierge Bash output, attachment/KB/PDF paths, plugin CLI, Playwright, taint downgrade, `sessionId` hashing, any public copy.

## Sharp Edges

- Never prepend text to a cron prompt: several crons are `/soleur:` commands and the CLI must see the slash first.
- Do not log titles, authors, repo names or matched text on any new field (CLO).
- `envelope()` caps at 256 KiB after control-character stripping; leader content is far below it, and the GitHub readers are already size-bounded.
- The classifier is a mistake-guard and must not be cited as a mitigation for #7122 (closed 2026-10-06 by the schema-constrained publication work) or as a public claim.
- A `## User-Brand Impact` section that is empty or filler text fails `deepen-plan`; this one is filled.
