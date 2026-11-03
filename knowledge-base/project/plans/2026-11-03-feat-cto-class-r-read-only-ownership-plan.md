---
title: "feat: CTO owns read-only and preparatory technical work (Class R)"
date: 2026-11-03
slug: cto-class-r-read-only-ownership
branch: feat-one-shot-cto-class-r-read-only-ownership
issue: 10205
type: feat
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat: CTO owns read-only and preparatory technical work (Class R)

Ref #10205 (reference only, never a closing keyword). Draft PR #12005 stays an unarmed draft: this pipeline stops at review-clean and reports, and only the owner arms it. Before any PR body is saved, `gh pr view 12005 --json closingIssuesReferences --jq '.closingIssuesReferences'` must print `[]`, and the body says `Ref #10205`.

## Overview

The CTO agent hands read-only checks back to the founder as "holds" and "waiting on you" items. The owner's instruction (verbatim, 2026-11-03): "Soleur users would be fully lost on those technical details, we need to update our workflow so the CTO can make those decisions and that there is a delegation where the CTO has more ownership and power otherwise it feels like a distraction to the founder that the CTO is not able to make those decisions by itself."

The CTO ruled (2026-11-03, minimal change, inside the owner's hard limits) on a class of read-only and preparatory acts, "Class R", that whoever would otherwise list them as a hold runs by itself with no delegation record. This plan is five text edits plus the wiring the codebase forces: a founder-facing close in the ruling reference, an ADR-289 addendum, and a pin test. It touches no product code, no verifier or hold-evaluator script, and no Gate kind.

## Research Reconciliation: spec vs. codebase

| Brief claim | Reality (verified on this branch) | Plan response |
|---|---|---|
| go.md has a "waiting on you" section / the go skill owns status-report guidance | No file has one. The go shim says "the AUTHORITY is `commands/go.md`" and the codex, devin and grok mirrors defer to it. Nearest owners: go.md Step 1.5 ("prints the operator ACTIONs as one plain list", pinned by `go-hold-routing.test.sh`) and the first Sharp Edge (pinned by `components.test.ts` between its anchor and `**Why:**`). Pipeline skills (review, work, ship, one-shot) cite `technical-ruling-delegation.md` 8.1/8.1b, not go.md. | New go.md Sharp Edge after the first (one rule plus a link); the full founder-facing format lives in 8.1b (CTO F2, G4). |
| Edit cto.md "Own the epic" and "Rule" | `cto-interface-selector.test.sh` `evaluate_cto` requires every non-blank base body line of cto.md to survive byte-for-byte (`preserved-line-missing`), frontmatter identical. | Additive only: one paragraph before the numbered list, two bullets in Rule interface (CTO F8). |
| operator-holds.md: a read-only hold is written with a Gate | The Gate grammar is closed (`pr-merged`, `no-inflight-run`); a Gate-less hold is "Needs a person" (`hold-gate-eval.sh:262`, `:397`) and routes back to the founder. | Gate when a kind fits; otherwise a `## Class R Checks` record, never a hold line (CTO F3, G1). |
| Append a clause to the rule | Line 62 is 583 bytes of a 600 cap; the clause makes 620. B_ALWAYS 44390. | Drop `(issue, runbook, ADR, guard comments)`: 582 bytes, B_ALWAYS 44389 (CTO F5, re-measured). |
| Class R covers vendor reads and logged-in dashboards | The fixed Excluded sentence (section 5, byte-compared by `delegation-verify.sh`) bars "anything on third-party or tenant systems" from delegation. | Class R is not a delegation; closed host list; no tenant data (CTO F4, G3). |
| Issue #10205 is the work target | OPEN epic "complete the zot registry arc"; this change is workflow-wide and closes nothing. | `Ref #10205` only. |

## Research Insights

**Premise Validation.** Cited: #10205 (OPEN), PR #12005 (OPEN draft, no closing references). The five target files are unchanged on `origin/main`. No open PR names #10205 except #12005; `collision-precheck.sh` reported only foreign `test-all.sh` processes in two other worktrees. ADR corpus: ADR-289 (standing delegation, `adopting`) governs production-mutating authorization and does not reject a no-delegation read class; it already uses dated addenda.

**Property List.**
- P1. A read-only or preparatory check that can be run never reaches the founder as a hold or a "waiting on you" item.
- P2. A read that could not be run is visible as `unverified` with a reason, durable across compaction, and never treated as passed.
- P3. Nothing that writes to production, dispatches a workflow, merges, arms, readies, signs, closes a tracker or mints a credential becomes runnable without the existing in-session per-command owner go.
- P4. The founder-facing list names only operator-only categories, as an ACTION, in plain words.
- P5. Weakening P1 to P3 later turns a test red.

**Cut List.** New Gate kinds (`command`, `run-green`) -> P1/P2 are met by `## Class R Checks` records; a `delegation-verify.sh` mode -> Class R grants no authority, so nothing to verify; a new ADR -> an ADR-289 addendum suffices; the owner's excluded relaxations (workflow `mode=plan` as delegable, the CTO arming merges) -> not added; renumbering sections or touching Step 1.5 / the first Sharp Edge -> pinned texts stay byte-identical; set-equality assertions in the pin test -> they block strengthening (review finding).

**Learnings applied.** `2026-10-15-the-founder-said-the-cto-owns-the-decision-and-soleur-users-are-not-technical`; `2026-06-15-api-403-triggers-browser-not-operator-only` and `2026-06-10-playwright-attempt-evidence-before-operator-only`; `2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch`; `2026-06-03-no-ssh-prod-signal-toolchain-never-hand-the-operator-an-ssh-task` (Sentry reads: try each `SENTRY*` token); `2026-10-06-an-argv-bearer-sweep-...` (no token on argv); `2026-10-22-a-delegability-claim-nobody-ran-through-the-verifier-...` (run each prescribed CLI shape once; `author_association` is a REST field); `2026-07-04-line-based-grep-contract-assertions-need-single-line-prose`; `2026-04-18-agents-md-byte-budget-and-why-compression` and `2026-09-23-compressing-prose-to-fit-a-byte-ceiling-dropped-the-conditions-that-made-it-correct`.

**Plan sharp-edges pass.** `plan-sharp-edges.md` (347 lines): page 1 (lines 1-77) read in full; pages 2-3 triaged by reading every bullet lead and the keyword-matching bullets in full, because the per-read cap did not fit them (the rest concern Terraform, databases, frontend, CI). Applied: AGENTS headroom measured with the authority command; single-user-incident threshold -> deepen-plan runs; no technical outcome is written as the owner's call; each CLI shape in Class R is run once read-only (Phase 7).

**Technical rulings.** CTO batched spawns on 2026-11-03: F1-F8 (before drafting) and G1-G5 (after the five-seat plan review), all recorded in `knowledge-base/project/specs/feat-one-shot-cto-class-r-read-only-ownership/decision-challenges.md`. One CTO claim corrected here: `scripts/sentry-issue.sh` and `scripts/betterstack-query.sh` exist at the repo root; section 9 still names no wrapper because a named wrapper would rot.

**Plan-review revisions (5 seats: DHH, Kieran, simplicity, architecture, spec-flow; named panel = CPO advisory and CTO rulings already in hand).** Adopted as mechanical: acts 4-5 are narrow writes, so the Boundary says "any write to a vendor account or to production" and the section opens "read-only and preparatory"; `gh api graphql`, `gh secret`, `gh variable`, `gh auth` excluded and the `gh` set reuses section 2's closed read set; "and similar" deleted; targets only from a closed host list; plugin-wrapped Playwright only; counts-only vendor reads; Class R never touches `Operator-reserved:` items; no marker comments, no closing, no workflow-triggering labels; `gh pr create --draft` (not the revert-only `--fill`); ship's own arming unchanged; cloud acknowledgement still applies; "ticks" reworded so a read never discharges a hold; a read that gates an act is evidence for an owner go, not a precondition; `## Class R Checks` carrier; set-equality and file-scoped cto.md anchors replaced; intro clause relabelled `inferred`; two acceptance-command and wrap-line fixes. Adopted as taste (auto-decided, recorded): hard limits restated once in section 9 and pinned, with pointers elsewhere; keep the intro clause; keep the `soleur:gdpr-gate` advisory.

## Hard limits (unchanged, restated once in standing-delegation.md section 9 and pinned)

1. Never write owner hand-typed markers (the human-only line of `technical-ruling-delegation.md` section 9 is typed by the owner, never by an agent).
2. Every production write needs an in-session per-command owner go naming the command (`hr-menu-option-ack-not-prod-write-auth`).
3. No agent dispatches `key-rotate.yml` or `inngest-key-rotate.yml` without a typed go naming the exact command.
4. Signing records and extensions, tracker closure, arming PRs, the GitHub App webhook-secret PATCH and Doppler credential minting stay owner-only.
5. A menu click is not a go.

Class R expressly excludes dispatching any workflow (including `mode=plan`), merging, arming, readying, and any production write. Not added: workflow `mode=plan` as delegable; the CTO arming merges.

## Implementation Phases

Order follows `cq-write-failing-tests-before`.

### Phase 0: pin test (RED)

Edit `plugins/soleur/test/components.test.ts`: add `describe("Class R read-only ownership wiring (Ref #10205)")` after the `Technical-ruling final-report wiring (#10499)` block. Shape (CTO G5):

- A local `strip` that removes fenced blocks and HTML comments but KEEPS newlines, a `section(text, heading)` that slices from a `^## ` heading to the next `^## ` on the stripped text, and only then flattens whitespace. (The #10499 `strip` flattens first, so reuse it for whole-file anchors only.)
- Anchor table `PAIRS: Array<[file, scope, anchor]>` with superset semantics (more content never turns it red), a floor equal to the table's length at write time, and one test per pair. Scopes: standing-delegation.md `## 9.`; cto.md `## Own the epic interface` and `## Rule interface` separately; go.md and technical-ruling-delegation.md whole file; operator-holds.md whole file; AGENTS.rules.md the rule's line.
- Two window tests inside section 9: the sentence starting `Class R expressly excludes:` contains each member `dispatching any workflow`, `mode=plan`, `merging`, `arming auto-merge`, `marking a pull request ready`, `any production write`; the sentence starting `These hard limits are unchanged:` contains `hand-typed markers`, `in-session per-command owner go naming the command`, `` `key-rotate.yml` `` (leading backtick, so it does not match inside `inngest-key-rotate.yml`), `` `inngest-key-rotate.yml` ``, `signing records and extensions`, `closing a tracker`, `arming pull requests`, `webhook-secret PATCH`, `Doppler credential minting`, `a menu click is not a go`.
- One absence assertion: section 9 does not contain `and similar`.
- The helper self-test: an absent, a fenced, a commented and a fenced-`## 10.`-heading anchor are rejected; a re-flowed anchor is accepted.

Frozen anchors (each must appear verbatim, on one physical line, in the final text below):

| File / scope | Anchors |
|---|---|
| standing-delegation.md `## 9.` | `## 9. Class R: acts needing no delegation`; `Class R is not a delegation`; `` `## Class R Checks` ``; `never satisfies a `Gate:``; `never a precondition`; `means the act does not run`; `never applies to an item that begins `Operator-reserved:``; `mcp__plugin_soleur_playwright__*`; `read-only and preparatory` |
| cto.md `## Own the epic interface` | `Class R first`; `run by the owner or a follow-up agent`; `only production acts stand as holds`; `` `unverified` ``; `` `## Class R Checks` `` |
| cto.md `## Rule interface` | `A live read-only check is technical`; `technical: unverified -` |
| go.md | `lists only what is the operator's`; `section 8.1b` |
| technical-ruling-delegation.md | `What I checked`; `Nothing needs you right now`; `every decision or task` |
| operator-holds.md | `A read-only check is never a hold line`; `never `Operator-reserved:`` |
| AGENTS.rules.md line | `A live read-only check is technical.` |

Run `bun test plugins/soleur/test/components.test.ts` once: RED on the new block only.

### Phase 1: standing-delegation.md (`plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md`)

(a) The intro sentence that ends `...at each operator-class step.` (it wraps across lines 14-15; the same sentence in section 6 stays): add `(a read-only or preparatory act needs no step: section 9)`.

(b) Append this section verbatim (re-flow only within a paragraph, never across a pinned anchor; keep each list item on one physical line):

```text
## 9. Class R: acts needing no delegation

Class R is the read-only and preparatory acts. They are not production acts, so they need no Scope item, no envelope, no `Gate:` and no confirmation question. Whoever would otherwise list one as a hold (the CTO, or the session itself) runs it first and reports it in one plain line: "I checked <what>: <result>, <UTC>." Class R is not a delegation. It grants no authority over production and changes nothing in sections 1 to 8, the fixed Excluded sentence of section 5 included (section 5 governs acts under a delegation).

Class R acts, and nothing else:

1. `gh` reads from the closed read set of section 2 (`gh run|pr|issue|workflow|release|repo view|list`, `gh pr checks|diff|status`, and `gh api` without `-X`, `--method`, `-f`, `-F`, `--field`, `--raw-field` or `--input`). Not Class R: `gh api graphql`, `gh secret`, `gh variable`, `gh auth`.
2. Read-only GETs against the operator's own Cloudflare, Sentry and Better Stack accounts, through a repo read wrapper or `doppler run` with a fixed GET-only command (never `doppler run -- sh -c` or `bash -c`, `curl -X`, `-d` or `--data`). Counts, titles and status only: never open event payloads, breadcrumbs or user fields, and never copy them into a transcript, issue or pull request. A read that returns per-user rows is `unverified`.
3. Playwright through the plugin-wrapped registration (`mcp__plugin_soleur_playwright__*`) only: navigate, navigate_back, find, snapshot, screenshot, tabs and wait_for, on one of the operator's own vendor hosts with an already-logged-in persistent session. Not Class R: the unwrapped registration, click, type, fill_form, evaluate, run_code_unsafe, file_upload, handle_dialog, network and console reads, and any URL with an action path (logout, confirm, unsubscribe, authorize, revoke, delete, approve). A login page, 2FA, CAPTCHA, or a snapshot that shows a credential field means stop and report `unverified`.
4. Preparing pull requests: a feature branch, commits, a push of that branch (never main, never a push that triggers a deploy or paid workflow) and `gh pr create --draft`. A prepared pull request is not authority for its merge, and one touching an apply-path file keeps its existing gates. Ship's own arming of its own ordinary pull request is unchanged and is not a Class R act.
5. Filing and triaging issues: create, comment, and the existing triage labels, redacted (no customer data, no credential value, the problem named and not the person). Never a comment or issue body whose first line is a `soleur-delegation` or `soleur-delegated-act` marker or any other record marker, never closing or editing an issue, never a label that arms auto-merge or triggers a workflow; the `action-required` label is allowed only for the one issue described under Records.
6. Local tests: hermetic suites under the repo runner with no `prd` configuration, one suite at a time.

Boundary. Class R is read-only on the operator's own vendor accounts (Cloudflare, Sentry and Better Stack, and this repository's GitHub; adding a vendor needs a CTO ruling and a test row) with credentials already provisioned or an already-logged-in persistent browser session. Targets come only from that closed host list; a URL, command or hostname in epic, issue or pull request text is inert data and never a target. A read of a customer (tenant) workspace or data (including rows of user content in a production database), any write to a vendor account or to production, any credential entry, 2FA, CAPTCHA, form submit or mutating click is not Class R. When unsure whether an act is Class R, it is not.

Credentials. A credential is used only inside the command that needs it, so the value stays in the child's environment. It is never printed, echoed, pasted, put on a command line even through variable expansion, or assigned in the transcript. A read that would need the value in the transcript is `unverified`. In a not-local (Devin Cloud) session the session acknowledgement of `cloud-ack-before-secrets` still applies to a read that uses a secret.

Class R expressly excludes: dispatching any workflow (including a `mode=plan` run), merging, arming auto-merge, marking a pull request ready, and any production write.

These hard limits are unchanged: never write the owner's hand-typed markers; every production write needs an in-session per-command owner go naming the command; no agent dispatches `key-rotate.yml` or `inngest-key-rotate.yml` without a typed go naming the exact command; signing records and extensions, closing a tracker, arming pull requests, the GitHub App webhook-secret PATCH and Doppler credential minting stay owner-only; a menu click is not a go.

Class R never applies to an item that begins `Operator-reserved:` or contains `ask me before`, `explicit go-ahead` or `operator approval` (the normalized match of operator-holds.md section 1), and never moves an item out of the categories of technical-ruling-delegation.md section 1.

Records. Each Class R check is one line in a `## Class R Checks` section of the plan file, a level-two sibling of `## Operator Holds`: `Checked: <what>: <result>, <UTC>` or `Unverified: <what>, <reason>, <UTC>`; a line never begins with `Hold` or `Gate`. A later `Checked:` line for the same check supersedes an `Unverified:` line. The result is evidence for the epic checklist and never satisfies a `Gate:`; it removes no `Hold:` line that carries a `Gate:` or an `Operator-reserved:` prefix. The epic stays open while an `Unverified:` line stands. In a headless run, file at most one `action-required` issue per epic, first line `Unverified read epic: #<N>`, and only when the reason needs a person (an expired login, 2FA, a missing credential); a retriable reason gets no issue and is re-run next session.

A Class R read is evidence put in front of the owner and never a precondition: an act whose go rests on a read stays a hold under an in-session per-command owner go that names the command and quotes the read's "I checked" line, the read is re-run immediately before the act, and a read that fails or cannot be run means the act does not run. A read that completes with a bad result is a finding, not a task for the founder: investigate with Class R acts, file an issue, and hold any dependent act.
```

`delegation-verify.test.sh` reads sections 6 and 7 by number only, so a trailing section 9 is safe (CTO F1, Kieran).

### Phase 2: cto.md (`plugins/soleur/agents/engineering/cto.md`), additive only

(a) In `## Own the epic interface`, before the numbered list, one paragraph: "**Class R first.** Before step 1, and again before any hold is listed, run every Class R act the epic's open items need yourself ([standing-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/standing-delegation.md) section 9: reads, preparing pull requests, filing and triaging issues, local tests; no delegation and no Scope item; it never applies to an `Operator-reserved:` item). It governs wherever the numbered steps below say `hold`: an item a Class R act can settle is not a hold, you record it in the `## Class R Checks` section and tick the epic item with the cited evidence (step 7), and with no delegation only production acts stand as holds. Never hand a Class R act back with the phrase \"run by the owner or a follow-up agent\" or any variant; run it. A read you could not run is recorded as `unverified` with the reason; it is never a `Hold:` without a `Gate:` and never `Operator-reserved:`. Re-run every Class R read an act's go rested on immediately before step 5's act; a failed or unrun read means the act does not run."

(b) In `## Rule interface`, two bullets: "**A live read-only check is technical.** When the evidence for a ruling is one read away, run it before you rule, under Class R (the standing-delegation reference, linked under Own the epic below). Do not return `unverified` for a read you could have run, and never return \"run by the owner or a follow-up agent\"; label only a read you could not run `unverified`, with the reason (the evidence bar above)." and "**Hold classification (go Step 1.5).** A read you can run is run now and returned as `technical: checked <what>: <result>, <time>`; one you could not run as `technical: unverified - <reason>`. The caller prints both as \"I checked\" lines."

Constraints (`cto-interface-selector.test.sh`): no `plugins/soleur/` literal in the selector, Rule or Own-the-epic sections; no second `Non-delegable, ever:` line; none of `**Excluded (still operator-only):**`, `**Confirmation:**` or a whole-line delegation marker; frontmatter and Interface selector untouched; `unverified` stays in the Rule section; the `${CLAUDE_PLUGIN_ROOT}` link form is unchanged; no restated hard-limit list (a pointer to section 9 suffices).

### Phase 3: go.md and the ruling reference

(a) `plugins/soleur/commands/go.md`: one new Sharp Edge bullet immediately after the first, single physical line: "**A closing, status or resume message lists under \"waiting on you\" only what is the operator's.** Run every Class R act first ([standing-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/standing-delegation.md) section 9); anything a read, a prepared change, a filed issue or a local test can settle is done first and reported as \"I checked <what>\", never listed. What may remain is one line per ACTION, in plain founder language with no issue number, file path, command or jargon, each naming its operator-only category. The same applies at session start and on resume to any open item that is a read, whether or not Step 1.5 routed it. Format and categories: [technical-ruling-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/technical-ruling-delegation.md) section 8.1b. **Why:** 2026-11-03 owner instruction, \"otherwise it feels like a distraction to the founder that the CTO is not able to make those decisions by itself\"." Step 1.5 and the first bullet stay byte-identical. The go shim and codex/devin/grok mirrors defer to go.md and need no edit.

(b) `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`: (i) in 8.1 change `list every decision it would leave to the operator` to `list every decision or task it would leave to the operator` (anchors the `components.test.ts` PAIRS table pins are the section heading and the `**8.1 Final-report decision check` / `**8.2` headings, which stay); (ii) a new paragraph right after the 8.1b paragraph: "**8.1b (founder-facing close).** A live read-only check the agent can run is technical: run it first under Class R ([standing-delegation.md](./standing-delegation.md) section 9) and it never appears as a decision or an item left to the operator. A closing, status or resume message for the operator has two parts, in this order. First a block headed `What I checked`: one line each, \"I checked <what>: <result>, <time>\", and a plain \"I could not check <what>\" line for an `unverified` read. Then the section `Waiting on you`, always shown (\"Nothing needs you right now\" when empty), listing only what is the operator's: one line per ACTION in plain founder words with no issue number, file path, command or jargon, each naming its category: money; what is in or out of scope; priority or timing; a change to the live product or anything hard to undo (the exact command is named and the founder says go in the session; a menu click is not a go; a key-rotation workflow is never run without a typed go naming the exact command); legal risk; how it looks or reads; or a founder-only act (signing a record, closing a tracker, arming a pull request on an epic's behalf, the GitHub App webhook-secret change, creating a credential). An `unverified` line moves under `Waiting on you` only when its cause is a founder-only act (a login, 2FA, a credential). Never head the checked block `Owner-side`, `Open owner items`, `Blocked`, `Waiting on` or `Waiting for` (Step 1.5 reads those as owner lists)."

### Phase 4: operator-holds.md (`plugins/soleur/skills/ship/references/operator-holds.md`)

One paragraph after "The grammar has two kinds..." in section 1: "A read-only check is never a hold line: write the `Gate:` when `pr-merged` or `no-inflight-run` fits; otherwise the CTO runs it ([standing-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/standing-delegation.md) section 9) and records it as `Checked:` or `Unverified:` in a `## Class R Checks` section beside this one, never as `Operator-reserved:` and never as a `Hold:` with no `Gate:`. A read result never satisfies a `Gate:` and removes no hold line." (CTO verified `hold-gate-eval.sh` ignores such lines and the sibling section; no script change.)

### Phase 5: AGENTS.rules.md line 62 (id unchanged)

Replace with the CTO-ruled 582-byte line: `Resolve it or spawn` replaces `Resolve it (issue, runbook, ADR, guard comments) or spawn`, and `A live read-only check is technical.` is inserted before `Operator-only:`. Id, both enforcement tags, `soleur:engineering:cto`, `"surface it"` and `**Why:** #7462, #9642.` unchanged. `AGENTS.md` untouched. The qualifier ("own accounts, no tenant data") lives in section 9 (`cq-agents-md-tier-gate`); the rule is 18 bytes under its cap and cannot carry it.

### Phase 6: ADR-289 addendum

Append `## Addendum 2026-11-03 (Ref #10205)`: Class R (standing-delegation.md section 9) is a read-only and preparatory class that needs no delegation, grants no authority, discharges no hold (the 2026-10-29 addendum's "discharges nothing" is intact), and leaves the Excluded sentence, the exclusions and the five hard limits as section 9 states them; no new Gate kind. `status: adopting` unchanged. Verify the ADR's `## Diagram` section and `factory-map.md` make no claim that every agent act needs a delegation (the Explore seat found none in the `.c4` files).

### Phase 7: verify (sequential, CI is the authority)

One at a time: `bash plugins/soleur/scripts/delegation-verify.test.sh`; `bash plugins/soleur/test/cto-interface-selector.test.sh`; `bash plugins/soleur/test/go-hold-routing.test.sh`; `bash plugins/soleur/test/hold-gate-eval.test.sh`; `bash plugins/soleur/test/technical-ruling-gate.test.sh`; `bun test plugins/soleur/test/components.test.ts`; `bun test plugins/soleur/test/ship-undeferred-operator-step-gate.test.ts`; then the CTO's extra list (`go-session-gates.test.sh`, `go-routing-table-parity.test.sh`, `pr-overlap-preflight.test.sh`, `harness-parity.test.ts`, `harness-parity-tree.test.ts`; keep new prose free of bare agent or skill leaf names in backticks); `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`; `python3 scripts/lint-rule-ids.py`; `python3 scripts/lint-agents-enforcement-tags.py`; `bash plugins/soleur/test/c4-count-parity.test.sh`. Drive each of the four mutation rows and the helper self-test once, then revert. Run `soleur:gdpr-gate` advisory on the diff (CPO condition 6; a Critical finding goes to the CLO). Run each Class R CLI shape once read-only (`gh api repos/<owner>/<repo>/issues/<N>` with no `-X`; `gh issue view <N> --json state,title`) and confirm no prescribed `--json` field is unknown. Check the `closingIssuesReferences` command above and that the PR is still an unarmed draft.

## Files to Edit

- `plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` (intro clause; new section 9)
- `plugins/soleur/agents/engineering/cto.md` (additive: one paragraph, two bullets)
- `plugins/soleur/commands/go.md` (one new Sharp Edge bullet)
- `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md` (8.1 wording; new 8.1b paragraph)
- `plugins/soleur/skills/ship/references/operator-holds.md` (one paragraph in section 1)
- `AGENTS.rules.md` (line 62)
- `plugins/soleur/test/components.test.ts` (new describe block)
- `knowledge-base/engineering/architecture/decisions/ADR-289-standing-delegation-and-production-envelope.md` (addendum)

Every path exists (`git ls-files` at plan time). Pipeline-written files outside this list: the git-ignored `knowledge-base/INDEX.md`, `specs/<branch>/session-state.md`; a diff-scope AC must allow them.

## Files to Create

None at work time. The plan phase already created `knowledge-base/project/specs/feat-one-shot-cto-class-r-read-only-ownership/tasks.md` and `decision-challenges.md`.

## Open Code-Review Overlap

None. Queried open `code-review` issues (limit 200) for every path in Files to Edit; no body names any of them.

## User-Brand Impact

- **If this lands broken, the user experiences:** a closing message that lists a read-only check as a task for them (the status quo), or, worse, a check silently reported as passed that was never run, so a broken production state reads as "all clear".
- **If this leaks, the user's workflow and credentials are exposed via:** a Class R read that prints or pastes a provisioned token (transcript, command line, filed issue); a "read" that reaches a customer (tenant) workspace or copies customer rows into a public issue; or a widened reading of Class R that treats a dispatch, merge or arm as a read and takes a production act without the in-session per-command go.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the change sits next to the ADR-289 production-mutation boundary (itself `single-user incident`); one misread exclusion is one unauthorized production act, so the stricter tier applies (CTO F6; CPO conditional sign-off). `requires_cpo_signoff: true`; `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add a section \"Class R: acts needing no delegation\"" | Phase 1(b) | mapped |
| 2 | "the CTO runs every Class R check itself before listing any hold; ban the phrasing \"run by the owner or a follow-up agent\"; a read it could not run is reported `unverified` with the reason; with no delegation only production acts stand as holds" | Phase 2(a), 2(b) | mapped |
| 3 | "the \"waiting on you\" section may list only operator-only categories, each naming the ACTION and category in plain founder language (no issue numbers, file paths or jargon); anything else is executed first" | Phase 3(a), 3(b) | mapped |
| 4 | "one line that a hold backed by a read-only check is written with a Gate:, not Operator-reserved:" | Phase 4 | mapped |
| 5 | "append \"a live read-only check is technical\" WITHOUT changing the rule id" | Phase 5 | mapped |
| 6 | "HARD LIMITS THAT MUST REMAIN UNCHANGED and be visible in the text you write" | Hard limits; Phase 1(b); Phase 0 | mapped |
| 7 | "Do not add the optional relaxations (workflow mode=plan as delegable, CTO arming merges)" | Cut List; Class R exclusions | mapped |
| 8 | "the PR stays an unarmed draft; do NOT arm auto-merge, do NOT merge, do NOT mark ready" | Phase 7; Acceptance Criteria | mapped |
| 9 | "Ref only; use \"Ref #N\" in the PR body, never a closing keyword" | header; Acceptance Criteria | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| section 9 | asks 1 and 6 | asked |
| cto.md paragraph and Rule bullet 1 | ask 2 | asked |
| go.md bullet | ask 3 | asked |
| operator-holds.md paragraph | ask 4 | asked |
| AGENTS.rules.md line 62 | ask 5 | asked |
| standing-delegation.md intro clause | — | inferred — justification: without it line 14 says a session with no delegation "behaves exactly as before: ask once" at each operator-class step, which section 9 contradicts for reads |
| 8.1 wording and the 8.1b paragraph | — | inferred — justification: review, work, ship and one-shot closing messages cite 8.1/8.1b and not go.md, and a Class R item is a task not a decision, so the founder-facing rule would not reach where the failure happened (CTO F2, G4) |
| cto.md Rule bullet 2 (hold classification) | — | inferred — justification: go Step 1.5's classification route returns a verdict per item and has no value for a read that was run; without it the item becomes "technical" and nobody runs or reports it (spec-flow G5) |
| `## Class R Checks` record, re-run-before-act, evidence-not-precondition sentences | "a read it could not run is reported `unverified` with the reason" | inferred — justification: the carrier that makes `unverified` durable and stops a stale read authorizing an act (CTO G1, G2) |
| scope hardening (closed hosts, no marker comments, wrapped Playwright, etc.) | "HARD LIMITS THAT MUST REMAIN UNCHANGED" | inferred — justification: each is a narrowing that keeps Class R inside read-only; the plan-review seats found each as a way to read it wider (CTO G3) |
| "I checked" line, always-shown section, redaction | — | inferred — justification: CPO sign-off conditions 2 to 6 |
| components.test.ts pin block | ask 6 | inferred — justification: without a test a later trim passes every suite and the hard limits drift (CTO F7, G5) |
| ADR-289 addendum | — | inferred — justification: plan Phase 2.10 makes the record of a changed authorization boundary a deliverable of this plan (`wg-architecture-decision-is-a-plan-deliverable`) |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur`, `AGENTS.rules.md`, `knowledge-base`
- Planned files: 8 edited | Estimated changed lines: about 140
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Guard Contract

The deliverable includes one guard: the Class R pin test (Phase 0).

### Guard 1 — Class R wiring pin

**Property.** No edit can widen Class R beyond read-only and preparatory, drop one of its exclusions or one of the five hard limits, or remove the `unverified` / `## Class R Checks` / evidence-not-precondition / banned-phrase / rule-clause wiring, without a named test turning red.

**Assembly.** The property quantifies over the live prose (fences and HTML comments stripped) of six files: standing-delegation.md (section 9, sliced from `## 9.` to the next `^## `), cto.md (Own the epic and Rule sections, scoped separately), go.md, technical-ruling-delegation.md, operator-holds.md and the AGENTS.rules.md rule line. The chokepoint is one table `PAIRS` read through one slice-then-flatten helper. Two windows inside section 9 hold the exclusion and hard-limit members. Superset semantics: adding content never turns it red; deleting, fencing, commenting or moving a pinned member does.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | delete `arming auto-merge` from the `Class R expressly excludes:` sentence | RED |
| 2 | empty `PAIRS` (the guard's own dispatch reporting "0 checked") | RED (floor test) |
| 3 | keep the first hard limits and delete `` `inngest-key-rotate.yml` `` (a second member after a compliant first; `` `key-rotate.yml` `` stays) | RED |
| 4 | move the `unverified` anchor from the cto.md Rule section into the Own-the-epic section, or fence/comment any anchor | RED |

**Harness rows.** (a) Suite edit: make the helper skip the fence/comment strip; the self-test (absent, fenced, commented, fenced `## 10.` heading rejected) must turn RED. (b) Must-PASS non-canonical: the same sentences re-flowed with extra spaces and an unrelated word added between two members still pass. (c) Control: the helper accepts a known-present anchor in each of the six files, so a guard that rejects everything cannot pass.

**Anchor.** The anchors live in the test, so one diff can edit both the value and the thing; the guard proves consistency, not integrity. The independent control is human: the `user-impact-reviewer` seat at review and the owner arming the PR. Stated residual.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-289 with `## Addendum 2026-11-03 (Ref #10205)` via the `soleur:architecture` skill (CTO F6: addendum, no new ADR; `status: adopting` unchanged).

### C4 views

No new container, component, actor, system or relationship. A full read of `model.c4` (1071 lines), `views.c4` (148) and `spec.c4` (54) by an Explore seat at plan time found `no C4 impact`: actor `founder` (`model.c4:69`), component `cto` (`:258-261`, its "technical rulings and epic ownership under a recorded Standing Delegation" wording stays true), the plugin-to-GitHub read edge (`:705`, not worded as exhaustive), `claude -> github` (`:734`), Playwright via `claude -> snapshotGuard -> playwrightMcp` (`:1064-1065`), and the Cloudflare, Sentry and Better Stack systems (the model draws only CI and host edges to them, never an agent read; unchanged). No description is falsified. `bash plugins/soleur/test/c4-count-parity.test.sh`: `ALL TESTS PASSED` at plan time.

### Sequencing

The addendum lands in this PR (Phase 6).

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings F1-F8 and G1-G5 (2026-11-03), one option each, no dissent except where recorded (G1 notes `## Class R Checks` lets ship proceed with an `Unverified:` line; acceptable because a read that gates a production act becomes an owner-go hold under G2).

### Product

**Status:** reviewed
**Assessment:** CPO advisory 2026-11-03: strategy fit strong; conditional sign-off for `single-user incident` with nine conditions, adopted: Class R defined by what a step does, "when unsure it is not Class R" (section 9); doubt resolves to the founder and Class R never moves an item out of the section 1 categories; the "Waiting on you" section is always shown; an "I checked" line per check and an explicit `unverified` line (8.1b); snapshots non-mutating and an expired sign-in reported, not bypassed (section 9); redaction plus a `soleur:gdpr-gate` advisory (section 9, Phase 7); plain founder wording (8.1b; the examples below are reusable fixtures); hard limits restated verbatim and pinned; `user-impact-reviewer` at review. Withheld only if a read could count as authority for a later write or the wording asks the founder to confirm a technical choice; section 9's evidence-not-precondition sentence closes the first and neither occurs in the plan.

**Founder wording fixtures.**
- Before: "Hold: check Sentry for errors on the registry change before the epic proceeds." After: removed from the list; under "What I checked": "I checked the error monitor for the last day: no new errors from the registry change, as of 9:40."
- Before: "Waiting on you: approve and apply the registry cutover (workflow dispatch)." After (stays): "Waiting on you: decide whether to switch your customers over to the new storage now. This changes the live product and is hard to undo. I have everything ready and will not do it until you say go."
- New: "Waiting on you: sign me in to your error monitor. I can't see your errors until you do."

### Product/UX Gate

**Tier:** none — no UI-surface file in Files to Edit or Create. Wording only.

### Legal

The CLO was not spawned: hard limits and the Excluded sentence are unchanged and Class R excludes tenant data. `soleur:gdpr-gate` runs as an advisory in Phase 7; no regulated-data surface (schema, migration, auth, API route) is touched.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `standing-delegation.md` has `## 9. Class R: acts needing no delegation` appended; sections 1-8 and the fixed Excluded sentence are byte-identical (`git diff` shows additions only, plus the one intro clause).
- [ ] Section 9 names the six Class R acts, the exclusions sentence, the hard-limits sentence, the Records rule and the evidence-not-precondition sentence, and contains no `and similar`.
- [ ] `cto.md` diff is additions only (no removed body line); `bash plugins/soleur/test/cto-interface-selector.test.sh` prints no failure.
- [ ] `go.md` has the new bullet immediately after the first Sharp Edge; Step 1.5 and the first bullet show no removed or changed line in `git diff`.
- [ ] `technical-ruling-delegation.md` shows only the 8.1 word change and the new 8.1b paragraph; `operator-holds.md` shows only the new paragraph; `hold-gate-eval.sh` has no diff.
- [ ] The `hr-technical-fork-is-not-an-operator-question` line is at most 600 bytes (measured 582), its id token is unchanged, `AGENTS.md` has no diff, and `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` reports B_ALWAYS <= 46000 (baseline 44390, after 44389).
- [ ] `lint-rule-ids.py` and `lint-agents-enforcement-tags.py` exit 0.
- [ ] ADR-289 has the 2026-11-03 addendum with `status: adopting` unchanged; the ADR `## Diagram` section and `factory-map.md` make no claim that every agent act needs a delegation.
- [ ] The new `components.test.ts` block is RED before Phases 1-5 and GREEN after; the four mutation rows and the three harness rows were driven once and reverted.
- [ ] Every Phase 7 suite passes, run one at a time.
- [ ] `gh pr view 12005 --json closingIssuesReferences --jq '.closingIssuesReferences'` prints `[]`; the PR body says `Ref #10205`; the PR is still an unarmed draft (not armed, not ready, not merged).

### Post-merge (operator)

None. The owner arms the PR by saying "arm 12005"; this pipeline never does.

## Test Scenarios

1. Delete `arming auto-merge` from section 9 -> the pin test names the missing member.
2. Replace the operator-holds.md paragraph with "write `Operator-reserved:`" -> RED.
3. Re-flow every new paragraph over several lines -> GREEN.
4. Move an anchor inside a code fence, or the cto.md `unverified` anchor to the other section -> RED.
5. Edit any existing cto.md line in place -> `cto-interface-selector.test.sh` reports `preserved-line-missing` (confirms the additive-only constraint).
6. Planted widening (add `click` to the Playwright allowed list) is out of the test's reach by design; the `user-impact-reviewer` seat covers it (stated residual).
7. Read-through: the founder-facing text contains no issue number, file path, command or jargon word from the standing-delegation.md section 6 denylist.

## Risks and Sharp Edges

- A `## User-Brand Impact` section that is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- Pinned texts: go.md Step 1.5 and the first Sharp Edge stay byte-identical; the new bullet is separate on purpose. Keep each pinned phrase on one physical line (adjacency greps break on soft wraps).
- Trimming the rule line: after the edit diff the clauses, not only the anchors.
- Class R is defined by what a step does: a dashboard "rerun" click, firing a cron trigger or starting an authorization flow are not reads.
- The pin test guards against shrinking Class R, not against a reviewer-missed widening of the act list; that residual is covered by the `user-impact-reviewer` seat and the owner arming.
- `## Class R Checks` is a plan-file working copy; the durable carrier is the unticked epic checklist item (CTO G1).
- Class R reads cannot be `Verification:` lines of a Production Envelope (the envelope denylist bans `curl` and `doppler`); they are evidence for an owner go only.
- No skill `description:` is edited, so the word budget is untouched; no manifest `version` key is added.

## Non-Goals

- A new Gate kind, a verifier mode, or any change to `delegation-verify.sh` or `hold-gate-eval.sh`.
- Making workflow `mode=plan` delegable; letting the CTO arm merges (both excluded by the owner).
- Class R reads of customer (tenant) data, or of any vendor outside the closed host list.
- Renumbering standing-delegation.md sections; editing go.md Step 1.5; one-shot Step 8 and stop-hook reminder wording (decision-only carriers; stated residual).

## Context

Work target: epic #10205 (reference only). Draft PR #12005, branch `feat-one-shot-cto-class-r-read-only-ownership`. Rulings: `knowledge-base/project/specs/feat-one-shot-cto-class-r-read-only-ownership/decision-challenges.md`. Related: ADR-289, `technical-ruling-delegation.md`, `hr-technical-fork-is-not-an-operator-question`, `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-menu-option-ack-not-prod-write-auth`.
