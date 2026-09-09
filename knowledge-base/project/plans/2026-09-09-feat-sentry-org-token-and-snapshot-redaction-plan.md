---
title: "Retire the personal Sentry auth token and redact password values out of browser accessibility snapshots"
date: 2026-09-09
slug: feat-sentry-org-token-and-snapshot-redaction
branch: feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction
issue: 7947
closes: [7947]
type: security
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Two credential-exposure guards, both fallout from the #7797 post-mortem.

The first (#7946) moves the `scripts/followthroughs/*.sh` Sentry consumers off a
personal, human-account-bound auth token onto the org-level Internal Integration
shape ADR-031-sentry-as-iac already establishes, and narrows the token's scopes to
the minimum the followthroughs are measured to need rather than the sixteen the
current replacement inherited.

The second (#7947) stops a browser-automation accessibility snapshot from
rendering an auto-filled password input's value as readable text into the agent
transcript, and repairs the canonical teaching example in the agent-browser skill
that currently demonstrates exactly that unsafe sequence.

## Enhancement Summary

**Deepened on:** 2026-09-09. Nine review lenses ran across plan-review and deepen-plan: CTO, CLO,
Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, security-sentinel, a scoped
strong-model consult, plus two mechanical realism sweeps and a framework-docs research pass. Every
claim they returned was independently re-verified in this worktree before being folded in — one
reviewer's "ADR-202 does not exist" was a false negative, and inheriting it unchecked would have
propagated into the ADR.

### The three findings that changed the plan's shape

1. **A defect that would have re-opened the incident this PR closes.** Thirteen of the sixteen
   followthrough files carry the ADR-202 xtrace refusal with the *old* credential in its predicate.
   Renaming consumption alone would leave the escape hatch open on the *new* credential. Phase 3.3
   now rewrites both guards per file and Rule E reds on the mismatch.
2. **The plan as first drafted could not have merged green.** Touching those files draws down 21
   entries in the Rule D baseline, because `--changed` bypasses it by design. Budgeted, not
   discovered in CI.
3. **The #7947 premise was never measured, and the fix pointed at the wrong provenance.** A value
   the agent *types* is already in the transcript as the tool-call argument — no snapshot redaction
   reaches it. Phase 0.1 now sets its sentinel only by non-agent paths, and reading the installed
   Playwright source moved the premise from unmeasured to strongly evidenced.

### What was cut

Two standalone lint scripts, two test suites, a fixtures directory, every new `run_suite` line, one
soak probe, a compatibility shim, and one file from the edit list — roughly a quarter of the
original net add. Both walkers became rule families inside lints that already own their populations;
the shim was inert by construction; the disuse probe had no measurement mechanism in this repo.

### What was added

An honest statement of where property P7 is *not* achieved (the Playwright-MCP runtime path); the
shipped-plugin hook manifest as the surface that decides whether the operator receives any
enforcement at all; a correction to two shipped files that teach the inverse of the
`browser_evaluate` leak rule; a directive gate closing the mid-cutover window; and a Phase 0 that
can conclude "no hazard here" and close the issue on the measurement.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
|---|---|---|
| #7946 | `gh issue view 7946` | OPEN, `priority/p1-high` + `domain/engineering` + `type/security`, zero closing PRs. Live target. |
| #7947 | `gh issue view 7947` | OPEN, same three labels, zero closing PRs. Live target. |
| #7797 | `gh issue view 7797` | OPEN, `priority/p0-critical` + `security/leak-suspected`. Context only — never a work target here. |
| #7945 | `gh issue view 7945` | OPEN, `domain/legal`. Explicit Non-Goal (see Non-Goals). |
| #7948 | `gh pr view 7948` | MERGED — `compound: I measured the right thing on the wrong instance`. The compound learning that FILED #7946/#7947, not an implementation. Collision gate clear. |
| `ADR-031` | `ls .../decisions/ | grep ^ADR-031` | Duplicated ordinal, two files. The one #7946 means is `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`; the other is `ADR-031-cc-dispatcher-extraction-cc-workflow-end-messages.md`. Flagged, not renumbered. |
| `ADR-202` | `ls .../decisions/ | grep ^ADR-202` | EXISTS: `ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md`. A research subagent reported it absent — a false negative from searching `learnings/` rather than `decisions/`. Verified directly. |
| post-mortem "Still open" | `grep -n "Still open" -A 4` | Verified verbatim at `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`, section `### Still open`: "The ADR-031 migration is undone — the org-token surface is empty, so this credential class is still a personal token and the next rotation is still gated at an interactive login. That remains the durable fix." |
| `### Login Flow` | content-anchor grep | Present in `plugins/soleur/skills/agent-browser/SKILL.md` under `## Examples`; snapshots a login page, fills a password, snapshots again to "Verify logged in". |

One premise in #7946 is materially stale and the plan is re-scoped around it — see Research Reconciliation.

### Property List (Phase 0.6b)

| # | Property (one observable outcome) |
|---|---|
| P1 | No `scripts/followthroughs/*.sh` execution — in CI or on a workstation — can bind a personal, human-account-scoped Sentry credential. |
| P2 | The credential the followthroughs do bind carries only the scopes their measured API surface requires. |
| P3 | A Sentry credential rotation for this consumer completes end-to-end driven by an agent, with no interactive step beyond the sanctioned auth handoff when the browser profile's session has expired. |
| P4 | The post-mortem "Still open" item and the ADR-031 reference name the shape that actually exists after this ships. |
| P5 | On the surfaces Phase 0.1 measures as leaking, a snapshot node whose serialized type is `password`, or whose role is a text-input role and whose accessible name matches the stated credential-name list, does not render its value into the agent transcript. Nodes outside that predicate are explicitly **not** covered: a localised accessible name, a `type=text` credential box, a show-password toggle that flips `password` to `text`, a value split across segmented single-character inputs, a value echoed into a status or validation region, and every node on the Playwright-MCP path. |
| P6 | No skill or agent in the shipped plugin instructs an unconditional accessibility snapshot inside an authentication flow. |
| P7 | P5 and P6 hold without the acting agent having to remember them. |

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Why it is cut |
|---|---|---|
| A new content-shaped secret detector for snapshot output | P5 | `plugins/soleur/skills/incident/scripts/redact-engine.py` (ADR-095) already detects secret-shaped strings and does not buy P5: its own header states it "never rewrites in place", and an operator password carries no vendor prefix or format anchor — ADR-095 names prefix-agnostic entropy detection an explicit non-goal. P5 needs a structural predicate (the node is a password textbox), not a content one. Cut the detector; keep ADR-095's fail-closed contract as the shape the new filter honours. |
| Narrowing the `iac-terraform-prd` integration itself | P2 | It would break the Terraform plane, which measurably needs `project:admin` and `alerts:write` (ADR-031 section "Why a dedicated Internal Integration"). Cut: narrow by ADDING a dedicated read-only integration for this consumer, never by shrinking a shared one. |
| A PostToolUse hook that redacts `browser_snapshot` output | P5, P7 | Verified capability claim: PostToolUse cannot rewrite tool output. `.claude/hooks/README.md` section `### PostToolUse hooks (no deny semantics)` — "PostToolUse runs after the tool's write, so these cannot block"; the sole MCP precedent `pencil-collapse-guard.sh` can only append `additionalContext`. Structurally unable to buy the property. |
| Renumbering the duplicated ADR-031 ordinal | none in this list | A real hazard for anyone citing "ADR-031", but it buys no property here. Flagged only. |

### Repo facts this plan builds on

All verified in this worktree, never read from the bare repo.

**Sentry and the followthroughs**

- `.github/workflows/scheduled-followthrough-sweeper.yml` sets `SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}` — the sweeper already binds the org-level `iac-terraform-prd` integration, under a personal-looking env-var name.
- `scripts/sweep-followthroughs.sh` builds a deny-by-default env (`env -i PATH=... HOME=...`) and forwards only the names listed in a tracker's `secrets=` clause; a name absent from the workflow `env:` block fails the issue and leaves it open. `secrets=` is a pass-through name, not a rename.
- **Sixteen** followthrough files name `SENTRY_AUTH_TOKEN` (`grep -rl … | wc -l` = 16): fourteen `.sh`, one of them comment-only, plus two `.test.sh` stubs. A seventeenth, `scripts/followthroughs/git-data-rung2-evidence-capture.sh`, reads `SENTRY_ISSUE_RO_TOKEN` instead, which the sweeper does not forward — it degrades to "second channel: SKIPPED".
- Measured API surface across all `scripts/followthroughs/*.sh`: four endpoints, every one a GET, zero writes. `GET /api/0/organizations/{org}/events/` (nine direct callers), `GET /api/0/organizations/{org}/monitors/{slug}/checkins/` (three), `GET /api/0/organizations/{org}/` (one), `GET /api/0/projects/{org}/{project}/issues/` (one). No caller exercises `alerts:write`, `project:admin`, `project:releases` or `org:ci`.
- Scope ledger (ADR-031 section "Why a dedicated Internal Integration", plus the live probe recorded in `knowledge-base/project/learnings/2026-06-17-sentry-internal-integration-mint-needs-org-admin-and-skill-backtick-scripts-rule.md`): `iac-terraform-prd` = `[alerts:read, alerts:write, event:read, org:read, project:admin, project:read, project:write]`; `inline-read-prd` (`SENTRY_ISSUE_RO_TOKEN`, Doppler `soleur/prd`) = `[event:read, org:read]`; the personal token probed at that date = `[org:ci, org:read, project:read, project:releases, project:write]`.
- The only live `doppler secrets get SENTRY_AUTH_TOKEN --plain -p soleur -c prd_terraform` in the repo is in `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`.
- **Thirteen of the sixteen followthrough files carry the ADR-202 xtrace refusal with the credential named in the predicate** — `grep -l 'SENTRY_AUTH_TOKEN:+x' scripts/followthroughs/*.sh | wc -l` returns 13, e.g. `scripts/followthroughs/sentry-checkins-3859.sh` under the anchor `REFUSE TO RUN UNDER XTRACE (#7797)`: `if [ -n "${SENTRY_AUTH_TOKEN:+x}" ]; then`.
- **`scripts/lint-shell-trace-credential-refusal-d.baseline.txt` carries 21 `scripts/followthroughs/` entries**, and its own header states the contract: *"DRAWDOWN: `--changed` bypasses this file, so touching a listed script must remediate it."* `.github/workflows/ci.yml` runs that lint with `--changed --base origin/main`.
- **`apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` asserts on the exact line Phase 3.5 changes** — its AC13 row greps `fresh-host-boot-trail.sh` for `doppler secrets get SENTRY_AUTH_TOKEN .*-c prd_terraform`. It runs in CI from `.github/workflows/infra-validation.yml`.
- **`scripts/sweep-followthroughs.sh` forwards only the names a tracker's `secrets=` clause lists**, under `env -i`. A workflow-env entry no directive names is invisible to the probe — which is what makes a compatibility shim inert (see Phase 3.4).
- **`scripts/followthroughs/sentry-checkins-3859.sh` sets `ORG="jikigai"`**, the legacy org slug, against `API="https://sentry.io/api/0"`. Every other followthrough uses `jikigai-eu`. It is also one of the three callers of the checkins endpoint.
- **`knowledge-base/engineering/operations/runbooks/followthrough-convention.md` names the retired credential three times**, not twice — the stub example, the Soak row of the trigger-shape table, and the `sentry-checkins-3859.sh` prose citation. The table row is the one a new follow-through author copies from.
- **`scripts/lint-infra-no-human-steps.py` scans five roots only** (`SCAN_DIRS`: `knowledge-base/project/{plans,specs}`, `.../operations/runbooks`, `.../legal/runbooks`, `.../architecture/decisions`). It cannot see hooks, scripts, workflows or `model.c4`.
- **The shipped plugin declares no PreToolUse hook.** `jq -r '.hooks | keys[]' plugins/soleur/hooks/hooks.json` returns `SessionStart` and `Stop` only. Anything registered in `.claude/settings.json` is repo-local to this checkout and never reaches a customer's machine — the fact that decides whether P7 is delivered to the operator at all.
- **The #7947 leak is evidenced in the installed Playwright source, not only hypothesised.** `apps/web-platform/node_modules/playwright-core` (v1.58.2) carries the aria-snapshot generator's value-rendering branch as `(n instanceof HTMLInputElement||n instanceof HTMLTextAreaElement)&&n.type!=="checkbox"&&n.type!=="radio"&&n.type!=="file"&&(h.children=[n.value])` — it excludes checkbox, radio and file, and **does not exclude `password`**. It reads `element.value` from the DOM rather than the platform accessibility tree, so the platform-level masking that Windows and macOS accessibility APIs apply to password fields never applies. This is evidence, not proof for the surfaces in play: `.mcp.json` pins `@playwright/mcp@0.0.78`, which bundles its own Playwright, and `agent-browser` may not wrap `ariaSnapshot` at all. Phase 0.1 still measures both surfaces — but the premise has moved from unmeasured to strongly evidenced for the MCP path, and "neither leaks" is now the least likely verdict.
- **`@playwright/mcp` ships a `--secrets` mechanism** that replaces configured plaintext values in tool responses, and its own README calls it *"a convenience and not a security feature"*. It masks only values named in advance, so it cannot reach an autofilled password the agent never supplied — but it is a real partial control on the MCP path and the plan names it rather than presenting the deferred proxy as the only option.
- **`@playwright/mcp`'s fill tools echo the typed value into the action log** unless that value is a configured secret. That is the separate agent-supplied hazard Phase 0.1 measures in its own row, and it is documented rather than speculative.
- **`ADR-202`'s own Alternatives table classifies output redaction**: a targeted redaction on a specific known channel is *"defense-in-depth on one enumerated sink, not a substitute for the carried refusal"*. That sentence governs how strongly this plan may describe the redactor.
- **Two shipped files teach the inverse of the `browser_evaluate` leak rule.** `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md` says to call it *"**without** a `filename` (a `filename` JSON-dumps the result to the transcript)"*, and `plugins/soleur/skills/cf-token-scope/SKILL.md` says *"never call `browser_evaluate` with a `filename`"*. The learning both cite records the opposite: *"Token leakage when extracting via Playwright's `browser_evaluate` **without** the `filename` parameter — the return value writes to the conversation transcript by default"*, and that `filename` merely JSON-**encodes** the on-disk value (a 24-char token becomes 26 bytes). Both files are steering agents into the leak class this PR exists to close.
- Mint path, measured: `POST /api/0/organizations/{org}/sentry-apps/` requires `org:admin` (or `org:integrations`), which no Soleur credential carries, and an internal-integration identity is blocked by Sentry from creating sentry-apps at all. The Playwright dashboard mint at `/settings/developer-settings/new-internal/` is already proven automatable with no CAPTCHA, MFA or passkey (#5495 / #5496). Scope self-probe: `GET https://<org>.sentry.io/api/0/` returns `.auth.scopes`.
- Rotation-automation rungs already in the repo: fully autonomous API mint (`apps/web-platform/server/inngest/functions/cron-ghcr-token-minter.ts`, ADR-088); Terraform-declared vendor token (`plugins/soleur/skills/provision-cloudflare/`); Playwright scope edit paired with a deterministic retained-scope probe (`plugins/soleur/skills/cf-token-scope/`, ADR-130); Playwright mint chained to a Doppler plus `gh secret set` write with a `shred -u` trap (`scripts/rotate-x-api-secret-bootstrap.sh`).

**Browser snapshots**

- `plugins/soleur/skills/agent-browser/` contains exactly one file, `SKILL.md`. `agent-browser` is a bare global binary and there is no repo-local wrapper, so nothing currently sits between the CLI and the transcript.
- `.mcp.json` launches the Playwright MCP through `bash -c "... exec ... npx @playwright/mcp@... "` — the one place a stdio proxy could splice in. Its own comment records that `.mcp.json` changes load only on a full Claude Code restart, not on an `/mcp` reconnect.
- PreToolUse can match MCP tools: `.claude/settings.json` already registers a PreToolUse entry on `mcp__pencil__open_document`, and `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` already branches per Playwright tool and returns `{ permissionDecision: "deny", permissionDecisionReason }`.
- Browser-driving surfaces found by sweep — the assembly P6 quantifies over: `plugins/soleur/skills/agent-browser/SKILL.md` (`### Login Flow`, the smoking gun), `plugins/soleur/skills/test-browser/SKILL.md`, `plugins/soleur/skills/reproduce-bug/SKILL.md` (which also carries a stale `mcp__plugin_soleur_pw__*` tool prefix), `plugins/soleur/skills/qa/SKILL.md`, `plugins/soleur/skills/feature-video/SKILL.md`, `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md` (which actively steers toward the leaky surface — "Prefer `browser_snapshot` (accessibility tree) for navigation over screenshots"), `plugins/soleur/skills/review/references/review-e2e-testing.md`, `plugins/soleur/skills/ux-audit/SKILL.md`, `plugins/soleur/agents/operations/ops-provisioner.md`, `plugins/soleur/agents/operations/ops-research.md`.
- In-repo precedent for the exact mechanism: `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md` records a `browser_snapshot` taken after a token-mint click returning the generated Sentry token verbatim inside a `textbox` node. The class has already fired here once, on a vendor token rather than a password.
- ADR-202 `## Decision`: enforce a runtime-STATE hazard with a self-refusal the artifact carries, gated at commit time by a walker over every member of the population; the boundary interceptor is the complement, scoped to what is never committed. Snapshot output is never committed, so this plan ships both halves and labels which is which.

**Conventions this plan must follow**

- Lint triple: `scripts/lint-<name>.py`, co-located `scripts/lint-<name>.test.sh`, and `scripts/fixtures/<slug>/` with `compliant-*` / `violation-*` / `outofscope-*` names.
- `scripts/*.test.sh` is not auto-globbed — every suite needs an explicit `run_suite` line in `scripts/test-all.sh`, and `scripts/lint-orphan-test-suites.sh` reds on an unregistered tracked `*.test.sh`.
- The model to copy is the sibling guard from the same incident: `scripts/lint-shell-trace-credential-refusal.py` plus `.test.sh` plus `scripts/fixtures/shell-trace-refusal/`. Exit `0` clean, `1` violations, `2` cannot-evaluate (fail-closed, ADR-157), with a vacuity guard that refuses to report clean for a scan that inspected nothing. Its registration comment is load-bearing here: the advisory `lint-bot-statuses` CI step is not the gate — `scripts/test-all.sh` is, because "a credential guard a PR can merge past red is theatre".
- Measured baselines on this branch, so the new guards' floors are set against readings rather than guesses: `bash scripts/lint-followthrough-varq-ban.sh` reports `clean (67 probe(s) scanned)`; `bash scripts/lint-orphan-test-suites.sh` walks 417 tracked `*.test.sh` against **six** registration surfaces with 0 orphaned; `cd plugins/soleur && bun test test/components.test.ts` is `1297 pass / 0 fail`. A new `*.test.sh` must land in one of those six surfaces or the orphan lint reds.
- `plugins/soleur/skills/*/test/*.test.sh` is auto-globbed by `scripts/test-all.sh`; `plugins/soleur/skills/*/scripts/*.test.sh` deliberately is not. Skill-scoped tests go in `test/`, never beside the script.
- `.claude/hooks/*.test.sh` and `.claude/hooks/lib/*.test.sh` are auto-globbed.
- A skill body may not contain a backtick reference that opens with `scripts/`, `references/` or `assets/` — `plugins/soleur/test/components.test.ts` asserts it. Use a markdown link or a full command invocation.
- Plugin tests run with `cd plugins/soleur && bun test test/components.test.ts`.

### Institutional learnings that bind this plan

| Learning | Constraint |
|---|---|
| `knowledge-base/project/learnings/2026-06-17-sentry-internal-integration-mint-needs-org-admin-and-skill-backtick-scripts-rule.md` | The Sentry mint is Playwright-automatable with no human gate. An API 403 on `sentry-apps/` is not operator-only evidence — it is the trigger for the dashboard attempt. Also: no bare backtick `scripts/` reference in a skill body. |
| `knowledge-base/engineering/architecture/decisions/ADR-095-fail-closed-redaction-engine-contract.md` | Any redaction path fails closed: cannot-evaluate exits 2 and emits nothing, never a partially filtered stream. Cap the input; normalise before matching. |
| `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md` | New suites report their anti-vacuity floor directly (`printf >&2` then `exit 1`) and increment the case counter at the call site, never inside a command substitution. |
| `knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md` | State the walker/interceptor split explicitly for #7947 rather than shipping one half and calling it the guard. |
| `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` | Exit 0 auto-closes the tracker, so ambiguity maps to TRANSIENT (2 or more), never PASS. Exit 78 is the xtrace refusal and lands in TRANSIENT. A soak probe's positive control must be impossible for the pre-change artifact. |
| `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md` | The `event:read` token trap: the personal token 403s on the id-shaped `/issues/<id>/` path. Probe each endpoint; never reason from one endpoint's success to another's. |
| `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` | Every new guard needs a floor that distinguishes clean from never-ran. |

### Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (64 open) against every planned path token: `scripts/followthroughs`, `agent-browser`, `SENTRY_AUTH_TOKEN`, `lint-shell-trace`, `scheduled-followthrough-sweeper`.

- **#3740** — "review: author sentry-post-merge-smoke.yml automated workflow (deferred from PR-B #3710)". Matched on the `SENTRY_AUTH_TOKEN` token only. **Disposition: acknowledge.** It concerns a post-merge smoke workflow, not the followthrough credential path; this plan neither fixes nor worsens it, and it stays open. It would, however, become a consumer of the naming change, so the ADR-031 amendment records the new secret name where a future author will read it.
- No other overlap. Recorded so the next planner can see the check ran.

### Skill Description Budget

`SKILL_DESCRIPTION_WORD_BUDGET = 2400` in `plugins/soleur/test/components.test.ts`; the suite is green on this branch. This plan edits no skill `description:` field, so no headroom is consumed. Re-check if a front-matter edit later enters `## Files to Edit`.

No `spec.md` exists for this branch, so `lane:` could not be carried forward — defaulted to `cross-domain` (TR2 fail-closed).

## Research Reconciliation — Spec vs. Codebase

| Claim (from #7946 / #7947 / the brief) | Reality, measured in this worktree | Plan response |
|---|---|---|
| "`scripts/followthroughs/*.sh` consumers read a PERSONAL auth token." | **Materially stale for the CI path.** `.github/workflows/scheduled-followthrough-sweeper.yml` already sets `SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}` — the org-level `iac-terraform-prd` integration. The residual hazard is the env-var NAME: because it is called `SENTRY_AUTH_TOKEN`, any local or manual run under `doppler run -c prd_terraform` (which exports ~160 names) silently binds the PERSONAL token instead. | Re-scoped from "migrate the token" to "**retire the ambiguous name and narrow the scopes**". A name a personal credential can satisfy is the defect. |
| "The org-token surface holds ZERO tokens, so the ADR-031 shape is entirely un-adopted." | **False as written.** ADR-031 records three live Internal Integrations. `/settings/auth-tokens/` holding zero tokens is a statement about **Org Auth Tokens**, a different surface from `/settings/developer-settings/` where Internal Integrations live. | The ADR-031 amendment states the surface distinction so the next reader does not repeat the inference. |
| "Sixteen scopes on the live replacement." | Not verifiable from the repo. The last committed live probe (2026-06-17) recorded the personal token at five scopes and `iac-terraform-prd` at seven. | Phase 0.2 re-probes live and records the reading. The plan asserts no scope count it has not read. |
| "Ten browser-driving skills instruct a snapshot." | **Six carry a snapshot *invocation token*; two more name one in prose only.** `git grep -lE 'browser_snapshot\|agent-browser snapshot' -- 'plugins/soleur/skills/**' 'plugins/soleur/agents/**'` returns six. `ops-provisioner.md` and `review-e2e-testing.md` are prose-only. `ux-audit/SKILL.md` and `ops-research.md` return `grep -c snapshot` = 0. | `## Files to Edit` is split into walker-reachable and prose-only tiers, and Guard 1's Assembly states that its `agents/**` arm has **zero live members today**. |
| "Thirteen followthrough scripts read the token." | **Sixteen files** — fourteen `.sh` (one comment-only) plus two `.test.sh`. | All sixteen are in `## Files to Edit`. |
| "`browser_snapshot` renders a password input's value as readable text." | **UNMEASURED on the two surfaces this repo uses.** Every supporting fact is about documentation or hook capability. The one in-repo empirical record is a *generated-token* `textbox`, a different DOM node class from a `type=password` input. | **Phase 0.1 measures it first**, per surface and per provenance path, and the verdict gates Phase 1. |
| "The credential half is independently revertable because its commits are contiguous." | **False.** The #7946 cutover includes GitHub issue-body rewrites that `git revert` does not touch, a live `gh secret set`, a live Sentry integration, and — measured — a Rule D baseline drawdown across the files it renames. | The claim is retracted. The split is surfaced as DC-1, and the phase order (#7947 before #7946) makes taking it cheap. |
| "The compatibility shim keeps the sweeper green across the cutover." | **False.** `scripts/sweep-followthroughs.sh` runs each probe under `env -i` and forwards **only** the names in that tracker's `secrets=` clause. A shim exports a value no migrated script reads, converting a self-describing `fail` into a silent TRANSIENT retry loop. | The shim is cut. Phase 3.4 sequences the directive rewrites instead. |
| "Renaming the credential is a rename." | **False, and this is the plan's most dangerous correction.** Thirteen of the sixteen carry the ADR-202 xtrace refusal with `[ -n "${SENTRY_AUTH_TOKEN:+x}" ]` in the predicate. Renaming consumption without renaming the refusal leaves the escape hatch open **on the new credential** — a live re-leak of the #7797 class inside the PR that claims to close it. | Phase 3.3 rewrites **both** guards, and Guard 2 gains a mutation row that reds on the mismatch. |
| "`ops-provisioner.md` is one of the members the `agents/**` arm exists for." | **False.** `ops-provisioner.md` names a snapshot in prose only and carries no invocation token, so the walker's predicate cannot reach it. | Guard 1's Assembly says the `agents/**` arm is currently vacuous and that M3 proves it against a synthesized fixture, not live coverage. |
| "The guards hold for a Soleur operator." | **False for two of the three.** `jq -r '.hooks | keys[]' plugins/soleur/hooks/hooks.json` returns `SessionStart` and `Stop` only. Anything in `.claude/settings.json` is repo-local. As drafted, the operator received prose plus a filter, and neither enforcement mechanism. | The hook is moved into the shipped plugin manifest. If that proves infeasible, the plan states plainly that P7 is not delivered to the operator rather than implying it is. |

## User-Brand Impact

**If this lands broken, the user experiences:** a scheduled follow-through sweep that silently stops verifying anything — the new read-only token 403s on an endpoint nobody probed, every Sentry-backed probe returns TRANSIENT, and trackers that should have closed sit open while trackers that should have failed stay quiet. Concretely: `scripts/followthroughs/sentry-checkins-3859.sh` stops confirming that eight scheduled workflows are still firing, and nothing says so out loud.

**If this leaks, the user's credentials are exposed via:** an agent transcript. A non-technical operator runs a browser-automation skill, the skill takes an accessibility snapshot of a page their password manager has **already auto-filled**, and their password is rendered into the session log and into any snapshot file the MCP server writes to disk — in a call that looks like "check whether the login worked". No warning fires and no monitor surfaces it. This is the #7797 class exactly: a legitimate value in a legitimate stream.

**Brand-survival threshold:** single-user incident.

A Soleur operator is non-technical by construction. They cannot audit an accessibility tree, they will not know that a screenshot is safe where a snapshot is not, and they will not think to grep their own transcript. Every control here is judged on one question — does it hold when the agent does not remember? That is property P7, and the plan is explicit about where P7 is and is not achieved: on the `agent-browser` Bash path, yes, via the shipped interceptor; on the Playwright-MCP runtime path, **no**, because the interceptor there is deferred and a walker gates only what the corpus *instructs*, never what an agent *does*. Saying that plainly is the point — an unstated gap is the failure mode, not the gap itself.

For the #7946 half the operator-facing consequence is different in kind: the personal token is bound to one human account, so its blast radius is that person's whole Sentry presence, and every rotation has historically cost an operator trip through a password-and-2FA login. Retiring the ambiguous name and proving the rotation is agent-drivable removes a standing bill the operator pays in attention.

## Non-Goals

- **#7945 — the Sentry-support vendor escalation.** Explicitly out of scope, routed separately. No part of this plan drafts, files, or references vendor correspondence.
- **#7797 itself.** Cited as context. This plan does not close it or alter its determination.
- **Publishing incident specifics for #7947.** The issue deliberately records only the mechanism. No credential value, length, fragment, account, or timing detail enters any artifact here, and none is requested from the operator. The synthesized sentinel in Phase 0.1 is the only credential-shaped string anywhere in this work.
- **Renumbering the duplicated `ADR-031` ordinal.** Flagged in the amendment header; tracking issue only.
- **Revoking the personal `SENTRY_AUTH_TOKEN` secret in Doppler `soleur/prd_terraform`.** A set of artifacts outside `scripts/followthroughs/` bind that name — some from the ambient Doppler config, others from `secrets.SENTRY_IAC_AUTH_TOKEN` under the same name and therefore unaffected by a Doppler revocation. **Re-derive the consuming set with a stated command in the revocation PR rather than inheriting a count from here**; the earlier draft asserted "six", and `git grep -l SENTRY_AUTH_TOKEN -- ':!scripts/followthroughs'` returns far more, most of them irrelevant. After Phase 3.5 migrates `fresh-host-boot-trail.sh`, that file leaves the set. The revocation PR's question is static reachability — *does any remaining consumer depend on the ambient binding?* — answerable by grep plus one dry run each.
- **The Playwright-MCP runtime path.** It ships with **no runtime control of our own** — `@playwright/mcp`'s `--secrets` option can mask values named in advance in `.claude/playwright-mcp.config.json`, but its own README calls that "a convenience and not a security feature", and it cannot reach a password the agent never supplied, which is exactly #7947's mechanism. So: the walker gates instructions only, and the `.mcp.json` stdio proxy is deferred. **P7 is not achieved there**, and given `brand_survival_threshold: single-user incident` the proxy issue is filed `priority/p1-high`, not as an unprioritised tracking issue. This residual is acceptable only under the Phase 0.1 verdict "only `agent-browser` leaks"; if the MCP surface leaks, the verdict table requires a re-scope before Phase 1 and that branch must not be quietly skipped.
- **Splitting the two issues into two PRs.** Recommended by three of the five review lenses. Recorded as DC-1 in `knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/decision-challenges.md` and surfaced rather than applied, because it changes the operator's stated direction (ADR-084). The phase order below puts #7947 entirely ahead of #7946 so that taking the challenge is a clean cut rather than a re-plan.

## Implementation Phases

### Phase 0 — Measure, then decide, before writing anything

**Nothing past 0.4 is written until 0.1's verdict table is filled in.** The verdict gates **Phase 1**, not Phase 2 — Phase 1 authors the filter suite and the hook suite, which two of the verdicts delete.

**0.1 — Does an accessibility snapshot emit a value the agent never supplied?**

The threat model, stated precisely, because getting it wrong invalidates the probe. A value the agent *types* is already in the transcript as the tool-call **argument**; no snapshot redaction reaches it, and measuring that path would "confirm" a leak this deliverable does not close. The hazard #7947 names is the opposite provenance: a value put there by a password manager's autofill, a static `value=` attribute, or a JS assignment.

Serve a synthesized page over `python3 -m http.server --bind 127.0.0.1 <port> --directory <a dedicated mktemp -d dir holding only the probe page>`, torn down before Phase 3 begins. Never `file://`, whose support on both surfaces is unverified; never inside the repo; and never bare `python3 -m http.server`, which binds `0.0.0.0` and serves the whole directory with listing enabled — over the same scratchpad family Phase 3.2's token capture will use.

The page carries: an `input type="password"` with a **static `value=`** holding the sentinel; a second `input type="password"` whose value is **set by inline JS**; a `type="text"` input named "Enter your password" left empty, exercising the name predicate separately from the structural one; a **read-only `input type="text"` whose accessible name is "Token"**, holding the sentinel, styled as a generated-credential panel; and an ordinary email field with a benign value as the must-PASS control.

The "Token" node is not optional. It is the class that has **already fired in this repo** — `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md` records a snapshot rendering a freshly-minted Sentry token verbatim from exactly such a node — and it is the class **Phase 3.1's own mint page renders**. Omitting it would let a "neither leaks" verdict close #7947 on a measurement that never tested the only instance we have. The sentinel is `ZZQP-SENTINEL-7947` — invented, never a real credential (`cq-test-fixtures-synthesized-only`).

Capture and `grep` per surface: `agent-browser snapshot -i` and `--json`; `mcp__playwright__browser_snapshot`; `mcp__playwright__browser_take_screenshot` (to confirm a screenshot is safe); every snapshot flag the six token-bearing surfaces actually use (`-i`, `-c`, `-d N`, `--json`); headed and headless, since Chromium's accessibility tree can mask password values differently between them.

**Record how the node is MARKED, not merely whether the sentinel appears.** A stateless redactor needs a distinguishable marker. If a surface prints `- textbox "Password" [ref=e2]: ZZQP-SENTINEL-7947` with only the label distinguishing it and no serialized `type`, the predicate is name-heuristic rather than structural and the filter's design changes. Capture the exact serialized line per surface per provenance path.

Separately, as its **own row with its own disposition**, check whether `browser_type` / `agent-browser fill` echo the typed value back in the tool result. That is a different hazard with a different fix and it is orthogonal to the four snapshot verdicts — both can be true. If it reproduces, file its own issue; do not widen this plan around it.

| Verdict | Deliverables kept | Dropped | ACs voided |
|---|---|---|---|
| Both surfaces leak a non-agent-supplied value | All. Record the marker shape per surface in the ADR. Amend nothing except to note that P7 is achieved on the Bash path only. | — | — |
| Only `agent-browser` leaks | Filter, pipe, interceptor, walker, ADR. | The deferred `.mcp.json` proxy issue is closed as unnecessary, citing the measurement. | The walker's `mcp__playwright__browser_snapshot` predicate token becomes advisory rather than load-bearing. |
| Only the MCP surface leaks | Walker, ADR, skill rewrites. **Re-plan before Phase 1.** | The filter, its suite, its fixtures, the pipe, the interceptor and its suite. The proxy stops being deferrable and must be designed. | The criterion asserting the shipped-hook manifest declaration, and the redactor-routing clause of the `### Login Flow` criterion. |
| Neither leaks a non-agent-supplied value | The `### Login Flow` correction, the `browser_evaluate` correction in the two `cf-token-scope` files, and a recorded negative result appended to the #7797 post-mortem. #7947 closes on the measurement. | Filter, suite, fixtures, interceptor, interceptor suite, walker, ADR-213, the PA-31 register bracket. | The "and in the new ADR" clause of the Phase 0.1 recording criterion; the snapshot-rule clause of the `credential-path-literals` criterion; the Tier-A grep criterion; the shipped-hook manifest criterion; and the PA-31 half of the Article 30 register criterion. |
| Only the JS-set or only the static-`value=` path leaks | All, with the filter's claim scoped to exactly that provenance. | — | — |

**0.2 — What scopes does the followthrough API surface actually require?**

Probe each measured endpoint with the existing `SENTRY_ISSUE_RO_TOKEN` (`inline-read-prd`, `[event:read, org:read]`) from Doppler `soleur/prd`, and record the HTTP status **per endpoint and per distinct org slug the callers use** — `jikigai-eu`, and `jikigai` for as long as `sentry-checkins-3859.sh` points there. A 200 against one slug is not evidence for the other, exactly as the `sentry-issue-read` runbook documents for endpoints.

| Endpoint | Verb | Callers | Org slug(s) | Status to record |
|---|---|---|---|---|
| `/api/0/organizations/{org}/events/` | GET | 9 | `jikigai-eu` | |
| `/api/0/organizations/{org}/monitors/{slug}/checkins/` | GET | 3 | `jikigai-eu`, `jikigai` | |
| `/api/0/organizations/{org}/` | GET | 1 | `jikigai` | |
| `/api/0/projects/{org}/{project}/issues/` | GET | 1 | `jikigai` | |

A 403 names a **ceiling**, not the minimum — it says the current pair is insufficient, not what would suffice, and no probe discriminates `project:read` from `alerts:read` without a token that carries one. So the branch is explicit rather than circular:

| Reading | Next step |
|---|---|
| All 200 | The minimum is `[event:read, org:read]`. Proceed to Phase 3.1's convergence rule. |
| Checkins 403 | Mint a throwaway at `[event:read, org:read, project:read]`, re-probe, and widen to `alerts:read` only on a second 403. **The same phase that mints the throwaway deletes it**, in the same trap scope. |
| Any 404 on the `jikigai` slug | The org-slug branch: `sentry-checkins-3859.sh` must move to `jikigai-eu` in this PR (Phase 3.3), not in a deferred issue. |

Also re-probe every relevant token's own scopes (`GET https://<org>.sentry.io/api/0/` → `.auth.scopes`) so the scope table is a reading, not a recollection.

**0.3 — Confirm the populations.** `grep -rl SENTRY_AUTH_TOKEN scripts/followthroughs/ | wc -l` must return 16; `git grep -lE 'browser_snapshot|agent-browser snapshot' -- 'plugins/soleur/skills/**' 'plugins/soleur/agents/**'` must return the six token-bearing files; `grep -c snapshot` must return 0 for `ux-audit/SKILL.md` and `ops-research.md`. If any has moved, the walker's population and `## Files to Edit` move with it.

**0.4 — Decide each guard's HOST and the interceptor's SHIPPING SURFACE before writing it.** The plan verified that its *properties* are unmet on `origin/main`; this verifies that its *mechanisms* are unbuilt there, which is a different question and the one a plan reliably skips.

- **Walker 2's host.** `scripts/lint-shell-trace-credential-refusal.py` already carries four rule families, and Rule D is not about xtrace at all — `excluded_for_rule_d` exists precisely so a rule can hold its own exclusion set inside a shared population walk, and Rule D carries its own baseline for the same reason. `scripts/followthroughs/*.sh` is already inside that lint's population. Land Walker 2 as **Rule E in that file**. Confirm the per-rule exclusion override can un-exclude `*.test.sh` for Rule E alone; if it cannot, fall back to a second pattern in `scripts/lint-followthrough-varq-ban.sh`, which already walks that directory with a `MIN_PROBES` floor and a `TARGET_DIR` argument.
- **Walker 1's host.** `scripts/lint-credential-path-literals.py` scans "tracked `*.md` under `plugins/**` and `knowledge-base/**`, minus `**/archive/**`" — a superset of Walker 1's population — with the same 0/1/2 contract and the same mode set. It describes itself as regression teeth for the credential auto-attach class; Walker 1 is regression teeth for the credential snapshot-render class, and both are "a credential value reaching model context through a doc-driven path". Land Walker 1 as a **second rule family there**, and state the consequence rather than discovering it: that lint backs the `credential-path-guard` job, which **is** a named entry in `scripts/required-checks.txt`, so the new rule is blocking from its first run. For a credential guard that is the intended posture — it is the #6882 precedent, where the resolvable-credential-path guard was deliberately promoted advisory to blocking as Article 32(1)(d) evidence.
- **The interceptor's shipping surface.** This decides whether P7 reaches a Soleur operator at all. `jq -r '.hooks | keys[]' plugins/soleur/hooks/hooks.json` returns `SessionStart` and `Stop`; a hook registered only in `.claude/settings.json` is repo-local and never reaches a customer. **Register the interceptor in `plugins/soleur/hooks/hooks.json` as a `PreToolUse` entry on the `Bash` matcher**, which makes it a user-facing surface and pulls in `hr-new-skills-agents-or-user-facing`. **The shape is already verified, so this is a runtime check rather than a feasibility question:** that manifest is a standard hooks object keyed by event name, its entries use `{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"}` — which resolves from the installed plugin root, exactly what a customer-side hook needs — and the plugin **already ships a browser-related hook** (`browser-cleanup-hook.sh`, under `Stop`). What remains to confirm is only that a `PreToolUse` arm dispatches from the plugin manifest at runtime, not whether the file can express one. If it cannot ship, say so in `## User-Brand Impact` and file the shipped-hook work as a named deferral — do not leave the plan implying an enforcement the operator does not receive.
- **The hook's disposition.** `ADR-162-pretooluse-hooks-may-rewrite-tool-input.md` gives a PreToolUse hook a third disposition: rewrite the tool input and let the call proceed. A rewrite splices the redactor in automatically and buys P7 outright, where a deny buys it only if the agent remembers to re-issue. **But the cost is measured:** `.claude/hooks/hookeventname-coverage.test.sh` hard-fails a second rewriter — *"ADR-162 permits exactly one. Two hooks emitting `updatedInput` for the same call have undefined precedence and one rewrite is silently discarded"* — and the one permitted rewriter is `grep-rewrite.sh`. Taking it means either living inside that file under the wrong name, or amending ADR-162 with a defined precedence. **Default: ship the deny.** Take the rewrite only if this reading concludes the amendment is independently worth making, and record the outcome in the Cut List either way.

### Phase 1 — RED tests first

Written only after Phase 0.1's verdict. Every guard's failing test precedes the guard (`cq-write-failing-tests-before`), and the mutation matrices come from the design in this document, not from finished code.

**1.1 `plugins/soleur/skills/agent-browser/test/redact-a11y-snapshot.test.sh`** — drives the not-yet-existing filter over synthesized fixtures:

- a fixture with `- textbox "Enter your password" [ref=e2]: ZZQP-SENTINEL-7947` emits `<redacted>` and the sentinel appears nowhere in stdout;
- a `type=password` node whose accessible name is *not* password-shaped is redacted too — structural first, name-based second;
- a non-password textbox passes through **unchanged** (the must-PASS row: a filter that redacts everything is as broken as one that redacts nothing);
- the `--json` shape is handled, not only the indented-text shape;
- malformed or over-cap input exits 2 with **stdout empty and stderr non-empty and sentinel-free**.

**1.2 The Walker 1 rule cases**, added to `scripts/lint-credential-path-literals.test.sh` with fixtures in that lint's existing corpus.

**1.3 The Rule E cases**, added to `scripts/lint-shell-trace-credential-refusal.test.sh`.

**1.4 `.claude/hooks/browser-snapshot-credential-guard.test.sh`** — feeds synthesized PreToolUse JSON envelopes on stdin, asserts the decision and the exact `permissionDecisionReason`, and carries a **registration case** that parses both `.claude/settings.json` and `plugins/soleur/hooks/hooks.json` with `jq`.

**Registration, stated correctly.** Two of these are auto-globbed and must **not** carry a `run_suite` line, or they run twice: `plugins/soleur/skills/agent-browser/test/redact-a11y-snapshot.test.sh` (matched by `plugins/soleur/skills/*/test/*.test.sh`) and `.claude/hooks/browser-snapshot-credential-guard.test.sh` (matched by `.claude/hooks/*.test.sh`). `scripts/lint-orphan-test-suites.sh` reads those patterns from `scripts/test-all.sh --print-suite-globs`, so it treats both as covered. The two rule families land inside host lints that are already registered, so **this plan adds no `run_suite` line at all**.

### Phase 2 — #7947 GREEN

**2.1 The filter.** `plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py`, stdin to stdout. A node is redacted when its serialized `type` is `password`, or when its role is a text-input role and its accessible name matches a named credential-name list held as data in one place: `password`, `passphrase`, `secret`, `token`, `api key`, `client secret`, `recovery code`, `one-time code`, `otp`, `2fa`, `pin`. **The list is English-only and the plan says so** rather than implying coverage it does not have — a French or German login page defeats the name limb entirely, and a show-password toggle defeats the structural limb at exactly the moment a value becomes visible. Everything else passes through byte-for-byte. **It is not a streaming filter:** it reads stdin to EOF and classifies the whole input before writing a single byte to stdout. A line-oriented filter would have emitted N-1 clean lines before discovering malformation at line N, then exited 2 with a partially filtered stream already on the wire — the exact ADR-095 violation this cites, and one a head-malformed fixture cannot catch. The cap is a **refusal, never a truncation**, so no value can straddle a truncation boundary because no boundary exists.

**Normalisation is per-node and decision-only.** "Byte-for-byte passthrough" and "normalise before matching" do not compose through a whole-string transform — `redact-engine.py`'s own header records that its pipeline leaves "no offset-map back to the original". So each node's serialized name and type are normalised into a scratch copy purely to decide redact-or-not; on a no-redact decision the node's **original bytes** are emitted unchanged, and on a yes-redact decision the value is replaced wholesale. No offset map is needed, and a zero-width character spliced into an accessible name still cannot defeat the name limb. Fail-closed per ADR-095 — but **fail-closed with a voice**: on exit 2 it writes a single-line, operator-legible diagnostic to **stderr** naming the reason and the safe alternative (take a screenshot), never echoing the input, while stdout stays empty. A silent exit 2 pushes the agent toward the one obvious recovery — re-run without the pipe — and fail-closed becomes fail-open in one turn.

**Do not retype the cap and normalisation front-half.** `plugins/soleur/skills/incident/scripts/redact-engine.py` already carries `REDACT_MAX_INPUT_BYTES` and roughly sixty lines of hard-won Unicode work. Import it, or vendor it with a pointer comment naming the source — **but reuse the constant and the normalisation table, not its return contract.** Measured: that engine's over-cap path is `print(f"SYNTHETIC HIGH: …")` then `return 1` — stdout, and exit 1. This filter's over-cap path is exit **2**, stdout empty, diagnostic on stderr. Inheriting `scan()` wholesale would import a fail path that violates this plan's own contract on both the stream and the code.

**2.2 One consistent rule, replacing three inconsistent ones.** The earlier draft said "screenshot after filling credentials", "never snapshot the login page", and "pipe any snapshot that must happen" — three rules that disagree. The first guards the *post-fill* snapshot while the named threat is the *pre-fill autofilled* one; the second is not executable at all, because `agent-browser`'s whole model is ref discovery from a snapshot, so `fill @e2` is impossible without having snapshotted. The single rule:

> **The redactor reduces one enumerated node class; it does not make a credential page safe to snapshot.** Prefer a screenshot wherever a screenshot answers the question. Where `agent-browser`'s ref discovery makes a snapshot unavoidable, it goes through the redactor — including before any fill, because autofill may already have populated the field. Verification after login is a screenshot, never a snapshot. If the redactor exits 2, take a screenshot; do not re-run the snapshot unpiped.

Stating the ceiling first is load-bearing. Without it the rule reads to an agent as "piping makes a snapshot safe", which is exactly the overclaim P5 was narrowed to avoid — and it is also what makes Phase 3.1's mint executable: "no accessibility snapshot of any credential-bearing page" and "`fill @e2` is impossible without having snapshotted" cannot both hold, so the mint's login step snapshots **through the redactor** rather than not at all.

Rewrite `### Login Flow` to that rule and drop the `password123` literal, which currently teaches an agent to type a plausible password into a form. Apply the rule to the five other token-bearing surfaces.

**`cf-token-scope` gets a carve-out and a correction, not the blanket rule.** Its `## Full-power-session leak constraints (load-bearing)` section says to scope screenshots to the edit control and prefer the accessibility tree, because a full-page screenshot of a live dashboard session leaks. Applying "screenshot instead" literally would trade a snapshot leak for a screenshot leak. Its rule is *route the snapshot through the redactor*; the existing scoping constraint stays verbatim. **And both `cf-token-scope` files carry an inverted `browser_evaluate` rule that must be corrected in this PR** — `widen-playbook.md` says to call it "without a `filename` (a `filename` JSON-dumps the result to the transcript)" and `SKILL.md` says "never call `browser_evaluate` with a `filename`", while the learning both cite records the opposite: *without* `filename` the return value writes to the transcript by default, and `filename` merely JSON-**encodes** the on-disk value. Two shipped files are steering agents into the leak class this PR exists to close, in a file this PR already opens.

The two prose-only surfaces — `review/references/review-e2e-testing.md` and `agents/operations/ops-provisioner.md` — get the rule for consistency, but the plan does not claim the walker enforces it there.

**2.3 Walker 1** — a second rule family in `scripts/lint-credential-path-literals.py`. Predicate: a file naming an accessibility-snapshot invocation (`agent-browser snapshot`, `browser_snapshot`, `mcp__playwright__browser_snapshot`) inside an authentication context — a password fill, a credential literal, a login-shaped URL, or a sign-in heading within the same fenced block or section — that neither routes it through the redactor nor replaces it with a screenshot. It also reds a file documenting an **un-piped retry** as the exit-2 recovery. It accepts an optional `--population-root <dir>` (default: repo root) so the suite can point it at a mktemp sandbox — without that seam the M4 mutation row cannot be executed. It inherits the host's registration and fixture corpus.

**2.4 The interceptor, `agent-browser` Bash arm only.** `.claude/hooks/browser-snapshot-credential-guard.sh`, PreToolUse on `Bash`, registered in **`plugins/soleur/hooks/hooks.json`** so it reaches a customer's machine (Phase 0.4), and in `.claude/settings.json` for this checkout. **It is an allowlist, not a denylist.** It allows only command strings whose every `agent-browser … snapshot` segment matches a small enumerated set of approved shapes — a bare invocation with `2>&1 |` into the redactor as the final stage, and nothing writing the raw stream to a file or a variable. Every other shape carrying `snapshot` after an `agent-browser` invocation is denied, with a `permissionDecisionReason` naming the approved form and the screenshot alternative. Deny-by-default converts an unbounded evasion enumeration into a bounded false-deny budget, which is the same argument this plan uses in `## Alternatives Considered` for preferring a knowable cost to an unknowable one.

The shapes that make a denylist untenable are not exotic — each is something an agent reaches for with no intent to evade: an absolute path (`/usr/local/bin/agent-browser snapshot`, which this repo's own `hr-mcp-tools-playwright-etc-resolve-paths` pushes agents toward), a `timeout 60` or `env` prefix, a redirection to a file that is then `cat`-ed, a `tee` that writes the unredacted tree to disk while still piping to the redactor, and command substitution into a variable that gets echoed.

Stated residual, rather than left silent: `eval "$cmd"`, a variable-expanded binary name, a wrapper script on `PATH` that calls `agent-browser` internally, and any invocation not going through the Bash tool. **Not** a residual, and the plan closes it for free: a shell alias, because aliases are not expanded in non-interactive bash and `hr-the-bash-tool-runs-in-a-non-interactive` fixes that this is what the Bash tool runs. It carries a kill-switch env var and writes its reason to `.claude/.rule-incidents.jsonl`, matching every other row in the `.claude/hooks/README.md` PreToolUse table.

**No MCP arm.** `browser_snapshot` takes no arguments, so the hook receives an empty `tool_input` and the credential-context predicate would be reconstructed from side-channel state — failing open on at least six paths (navigation by `browser_click`, an SPA route change with no tool call, `browser_fill_form` rather than `browser_type`, `browser_run_code_unsafe`, a second tab, and a re-auth modal on a non-login URL) while failing *closed* on the log-in-then-snapshot loop four skills rely on. A guard that denies the QA loop is worked around within a week, and a worked-around guard is worse than none because it reads as coverage.

**2.5** Add the hook's row to the `.claude/hooks/README.md` PreToolUse table.

### Phase 3 — #7946 GREEN

**3.1 Mint — conditional, and with the fork pre-committed.** If Phase 0.2 shows all four endpoints return 200 under `inline-read-prd`'s `[event:read, org:read]`, two readings are defensible and the plan takes one deliberately. The architecture lens argues: mint nothing, store the existing token as the new GitHub secret, because a fourth integration with an identical scope set widens the rotation surface this PR exists to narrow. The engineering-strategy lens argues the opposite and the plan follows it: **mint the dedicated `followthroughs-read-prd` anyway**, because the deciding factor is the store and the independence of the rotation domain, not the permission list. ADR-031 places `SENTRY_ISSUE_RO_TOKEN` in Doppler `soleur/prd` with a stated reason — it is consumed by an inline CLI under `doppler run` — and copying it into GitHub secrets would contradict a reasoned amendment, double blast radius, and couple two rotation domains so that a CI compromise darkens no-SSH agent issue debugging and vice versa. **What would flip this:** if the ADR-031 amendment concludes the two consumers should share one rotation domain, reuse and store the existing token. The dissent is recorded here rather than left as a live fork discovered at implementation time.

Playwright-drive `https://jikigai-eu.sentry.io/settings/developer-settings/new-internal/`. The API mint path is closed by measurement — `POST /organizations/{org}/sentry-apps/` requires `org:admin`, which no Soleur credential carries, and an internal-integration identity is blocked from creating sentry-apps at all — and the dashboard form is proven to load fully authenticated with no CAPTCHA, MFA or passkey (#5495 / #5496).

**Be honest about the auth rung.** The precedent this cites, `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md`, states in its click-path that the operator clears login and MFA as the sanctioned interactive-auth gate. The #5495 evidence is about a browser profile that was *already* authenticated in that session. Months later that cookie is expired. So the runbook records: Playwright drives to the dashboard; if the session is not authenticated, that single handoff is the sanctioned auth gate, identical in kind to `cf-token-scope` step 2 — and everything after it is automated. P3 is "no interactive step beyond the sanctioned auth handoff", not "no human ever".

**Perform the mint under the #7947 discipline.** Driving that dashboard is a browser login, precisely the hazard the other half of this PR addresses: no accessibility snapshot of any credential-bearing page, screenshots scoped to the control, and the token captured via `browser_evaluate(filename:)` — **with** the filename, per the learning, not without it.

**No credential value is ever passed as an MCP tool-call argument.** MCP arguments are not shell-expanded: `browser_type(text: "$SENTRY_PASSWORD")` types seven literal characters, so entering a password on the MCP path means putting it in the tool-call argument — the agent-supplied provenance Phase 0.1 explicitly places outside the redactor's reach. The interactive-auth handoff is therefore performed by the operator in the browser, or on the `agent-browser` Bash path where `$VAR` genuinely expands. If neither is available the mint stops and is filed as a tooling gap; it is never typed as a literal. This ordering is why the mint sits after Phase 2.

**3.2 Store, inside one trap scope.**

**Dry-run the whole chain against the Phase 0.1 sentinel before pointing it at Sentry.** Phase 0.1 already stands up a page and `ZZQP-SENTINEL-7947`; run capture, decode, write, read-back and cleanup against it, and confirm the sentinel appears in no transcript-visible tool result, that the decode returns it byte-exact, and that the trap removes the file. Only then run it live — the alternative is first exercising an untested five-step credential chain on a real token.

The write is `gh secret set <NAME> --body-file -` fed from the decode's stdout, **never** `--body "$TOKEN"`: an argument is visible in `ps` and printed verbatim under `set -x`, which is the #7797 class exactly.

The capture, the decode, the write and its read-back verification all live inside one trap scope, because a cleanup firing between capture and write leaves an unrecoverable token attached to a live integration nobody holds. If the write fails, delete the just-minted integration in-page before the trap fires.

Three details decide whether that trap is real. It is `trap cleanup EXIT INT TERM HUP`, not `EXIT` alone — the flow expects a human auth handoff mid-run, and a Ctrl-C during that wait would otherwise leave the plaintext file behind. The `filename` is an **absolute path inside a `mktemp -d` created mode 0700**, outside the repo and outside any MCP output directory, and the runbook asserts the file exists at that exact path before proceeding: an unpinned relative filename can resolve into the MCP server's own output directory, where the trap shreds a path that was never written while the real file persists, one `git add -A` from being committed. And `shred -u` is **best-effort** — it does not erase on journaled ext4, on copy-on-write filesystems, or on tmpfs, any of which the scratchpad may be. The primary control is the 0700 directory and the short lifetime; the overwrite is defence in depth.

The decode is not optional: `filename` JSON-**encodes** the result, so a 24-character token lands as 26 bytes with surrounding quotes. Storing that sends `Bearer "tok"` on every call and TRANSIENTs every probe. `python3 -c "import sys,json; sys.stdout.write(json.loads(sys.stdin.read()))"` sits between the file read and `gh secret set`, and the runbook carries it.

Then **re-run all four endpoint probes against the newly minted token, before migrating a single file**, and assert `.auth.scopes` **contains every scope in the derived minimum and none outside the smallest dashboard-expressible superset of it** — Sentry's permission model is hierarchical and the form hands back implied scopes, so exact equality can be unsatisfiable by construction. Any implied extra is recorded in the ADR with the level that granted it.

**3.3 Migrate — two guards per file, not one.** All sixteen files move from `SENTRY_AUTH_TOKEN` to `SENTRY_FOLLOWTHROUGH_RO_TOKEN`, including the two `.test.sh` stubs and the comment in `git-data-birth-emitter-6982.sh`. Two distinct guards change:

- **(a) The TRANSIENT presence guard** keeps its form verbatim — `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: ..." >&2; exit 2; fi` — never the banned `${VAR:?}` word-expansion.
- **(b) The ADR-202 xtrace refusal.** Thirteen of the sixteen carry a `case "$-" in *x*)` prologue whose predicate is `[ -n "${SENTRY_AUTH_TOKEN:+x}" ]`, under the anchor `REFUSE TO RUN UNDER XTRACE (#7797)`. **Renaming consumption without renaming the refusal leaves the hatch open on the new credential** — the exact "guarded one credential and consumed another" defect ADR-202's Rule C was written for, and a live re-leak of the #7797 class inside the PR that claims to close it. Rewrite the predicate and the message's parenthetical in the same edit, preserving `${VAR:+x}` (never `${VAR:-}`, which expands the value under xtrace).

**The Rule D drawdown is real, measured, and budgeted here rather than discovered in CI.** `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` carries 21 `scripts/followthroughs/` entries and states its own contract: *"DRAWDOWN: `--changed` bypasses this file, so touching a listed script must remediate it."* CI runs that lint with `--changed --base origin/main`. Touching these files therefore obliges remediating each to Rule D form (`curl --disable --noproxy '*'`, pinned destination) and deleting its baseline line in the same commit. **This is the single largest cost in the #7946 half, it is what the rename drags in, and it is the strongest argument for DC-1's split** — if the remediation cannot be carried here, the rename must not happen in this PR.

**`git-data-birth-emitter-6982.sh` is one of the 59 and this PR opens it.** It carries no xtrace refusal while binding `BETTERSTACK_QUERY_PASSWORD` through `${!v:-}` — an indirect expansion that prints the **value** under `set -x`, not the name. Since the PR touches the file anyway, it gains an unconditional refusal covering every credential it binds. Handling it here rather than in the filed backlog issue is the difference between a rename that walks past a live instance of the class and one that closes it.

**`sentry-checkins-3859.sh`'s org slug moves in this commit, not in a deferred issue.** It sets `ORG="jikigai"` against `API="https://sentry.io/api/0"` while every other probe uses `jikigai-eu`, and it is one of three callers of the checkins endpoint. A Sentry Internal Integration is org-scoped, so handing it a token minted in `jikigai-eu` ships exactly the silent blackout this plan's risk table names — on the one script `## User-Brand Impact` says stops confirming that eight scheduled workflows still fire.

**3.4 Sweeper — no compatibility shim.** `scripts/sweep-followthroughs.sh` runs each probe under `env -i` and forwards only the names in that tracker's `secrets=` clause. A shim exports a value no migrated script reads: an un-rewritten tracker forwards the old name, the migrated script finds the new name unset, and exits 2 TRANSIENT — a silent daily retry with no named cause. Dropping the old name in the same commit makes a missed tracker fail *loudly* on the `required secret '<name>' not set in workflow env` path, which names both the defect and the fix.

Sequence: **(1)** rewrite the affected tracker directives first — they are issue-body edits, instantly revertible and independent of the merge; **(2)** add `SENTRY_FOLLOWTHROUGH_RO_TOKEN` to the sweeper env and drop `SENTRY_AUTH_TOKEN` in the same commit as the script migration. Enumerate the affected trackers with `gh issue list --label follow-through --state open --limit 200 --json number,body` — **the limit is load-bearing; the default is 30** — and commit the reading as a timestamped census fixture so the acceptance criterion is diff-derived rather than query-derived. Trackers filed after the census timestamp are handled by 3.9.

Also add `SENTRY_ISSUE_RO_TOKEN` to the sweeper env, closing the documented `second channel: SKIPPED` degradation in `git-data-rung2-evidence-capture.sh`. That is a decided default, not a fork.

The env block therefore ends the phase carrying one net additional Sentry credential in the sweeper job's own process. Per-probe isolation still holds via `env -i`, and `scripts/sweep-followthroughs.sh` carries its **own unconditional** xtrace refusal — verified: `case "$-" in *x*) … exit 78`, with a comment stating it refuses unconditionally rather than behind a `${VAR:+x}` hatch. So the widening needs no predicate edit there. The plan says this explicitly because it is the one place a reader would otherwise assume the widening is unguarded.

**3.5 The remaining personal-token consumer.** Migrate `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`, and retarget the assertion in `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` that greps it for `doppler secrets get SENTRY_AUTH_TOKEN .*-c prd_terraform` — retarget the row, never delete it. That suite runs in CI from `.github/workflows/infra-validation.yml` and goes red otherwise.

**3.6 Rule E** in `scripts/lint-shell-trace-credential-refusal.py`: reds when any file under `scripts/followthroughs/` names `SENTRY_AUTH_TOKEN`, including in a comment and including `*.test.sh` — which needs a per-rule exclusion override in the shape of `excluded_for_rule_d`, since the shared `EXCLUDE_PATTERNS` drops `\.test\.sh$` for every other rule. Min-cardinality floor **14** (fourteen of the sixteen are `.sh`), with a test-only override env var in the shape of `VARQ_BAN_MIN_PROBES`. Where a comment records a fact about a **non-migrated** consumer — as `git-data-birth-emitter-6982.sh` does about the sweeper's historical mapping — it is rewritten to name the consumer rather than the variable, so Rule E's comment ban cannot force a factually false comment. Rule E inherits the host's two existing registrations.

**3.7 The rotation runbook**, `knowledge-base/engineering/operations/runbooks/sentry-org-token-rotation.md`. No SSH limb. It carries the closed API path with its measured reason, the Playwright rung with its selector-level recipe and its honest auth-handoff rung, the `filename`-plus-decode capture, the single trap scope, the `gh secret set` write, the `.auth.scopes` assertion, and the verification sweep. **It also carries a `## Failure modes` table with a next action — not a diagnosis — for every row:** session unauthenticated; scope-checkbox labels drifted so the intended set is unselectable; the form saved but the one-time token panel was missed by the capture selector; `.auth.scopes` returned a superset; the org slug moved; `gh secret set` failed; the new token 403s at verification. The table's presence is an acceptance criterion.

**3.8 Update the followthrough convention.** `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` names the retired credential at **three** places — the stub example, the Soak row of the trigger-shape table, and the `sentry-checkins-3859.sh` prose citation. The table row is the one a new author copies from, so a fix that reaches only the two `secrets=` literals leaves the highest-traffic occurrence teaching the retired name. Also update the header comment in `scripts/sweep-followthroughs.sh`, which spells the old name in its worked `env -i` example, and `plugins/soleur/skills/schedule/SKILL.md`, which ships a statement about this sweeper's secret mapping to customers' machines.

**3.9 Close the mid-window hole.** Nothing today stops a concurrent session from filing a tracker with `secrets=SENTRY_AUTH_TOKEN`: `.claude/hooks/follow-through-directive-gate.sh` validates `script=` and `earliest=` but not `secrets=`, and Rule E is scoped to `scripts/followthroughs/` so it never sees an issue body. Extend that gate to reject a `secrets=` name absent from the sweeper's `env:` block, with a mutation row asserting the retired name is denied. Prose in the convention doc fails this plan's own P7 test. The gate is a **write-time consistency check between a directive and the sweeper `env:` block, not an authorisation boundary** — it grants nothing and restricts nothing about what a credential can do; it catches a name that will fail at sweep time, at the moment the directive is written rather than a day later.

### Phase 4 — Documentation, ADR and C4

**4.1** Amend `ADR-031-sentry-as-iac.md`: the fourth credential class, its measured scope set, the **store discriminator** (a CI consumer takes a GitHub repo secret; a `doppler run` inline-CLI consumer takes a Doppler secret) **and its cost** — a repo secret is reachable from any workflow in the repository and by anyone with repo admin, a different and arguably wider audience than Doppler `soleur/prd`, so the dedicated integration must be scoped to the narrowest project set Sentry allows and not only the narrowest permission set, the Org-Auth-Tokens-vs-Internal-Integrations surface distinction the issue's "zero tokens" observation conflated, the rule that narrowing happens by adding a dedicated integration and never by shrinking a shared one, and a header note that the `ADR-031` ordinal is duplicated in this corpus.

**4.2** New ADR (provisionally **ADR-213**), conditional on Phase 0.1 — under "neither leaks" there is no decision to record, only a negative result, and the ordinal must not be claimed against a hypothesis. Highest ordinal claimed across all `origin/*` refs at plan time is ADR-212; re-derive before merge.

It must state, at true strength and per path, what ships and what does not. **ADR-202 does not cleanly apply here and the record says so rather than force-fitting it.** For `bash -x` the carried refusal was `case "$-" in *x*)` — a state predicate complete by construction, carried by the artifact that would leak. #7947 has no analogue: the artifact that leaks is a live browser page, which is not a member of any committed population, and markdown prose is advisory. **The redactor pipe is not the carried artifact** — ADR-202's own Alternatives table already classifies this exact shape as *"defense-in-depth on one enumerated sink, not a substitute for the carried refusal"*, and the pipe's predicate is a DOM and accessible-name enumeration, the drifting dimension ADR-202 confines to Rule B. So: **(a)** the filter is defense-in-depth on one enumerated sink; **(b)** the PreToolUse interceptor is ADR-202's complement, covering the never-committed ad-hoc invocation — which is where #7797 actually happened and is the higher-value half; **(c)** the walker gates what the corpus *instructs*, never what an agent *does*. **P7 is achieved on the `agent-browser` Bash path only and is NOT achieved on the Playwright-MCP path**, and that is the ADR's principal recorded consequence.

The ADR also records the CLO's two bounding conditions on the Article 33 analysis, because they are the conditions under which this decision stops holding: it holds only while the credential's investigation has not returned BREACH, and **it flips the moment the redacted field holds a third party's password** rather than the operator's own — an operator-assisted run against a tester's account makes the value personal data of a data subject and Article 33 must be re-run from scratch.

**4.3 C4.** All three model files were checked rather than grepped for the feature's own noun. `sentry` is already a `system` in `model.c4` and already appears in the include list of both views in `views.c4`, so no `views.c4` or `spec.c4` edit is needed. No external actor, external system or container is added.

One edge label changes, and the earlier draft got its reason wrong. The `github -> sentry` edge reads `HTTPS (cron check-in API + Terraform provider, SENTRY_AUTH_TOKEN)`. **That name is not retired by this PR** — it is the Terraform provider's required env-var name, bound in `.github/workflows/apply-sentry-infra.yml` from `secrets.SENTRY_IAC_AUTH_TOKEN`, as that workflow's own header states. What changes is that the edge gains a *third* credential. Widen the label to name all three; do not remove the existing name. Then regenerate `knowledge-base/engineering/architecture/diagrams/model.likec4.json` rather than hand-editing it, and run the C4 syntax, render and `c4-count-parity` suites.

**4.4** Update the post-mortem's `### Still open` section to name the shape that now exists. **Touch nothing else in that file** — not its `art_33_*` / `art_34_*` frontmatter, not its `### GDPR Art. 4(12) determination` section, not the asymmetry table's read-limb column. Those belong to the #7797 / #7945 determination and the canonical audit record; amending a machine-readable legal claim from a hardening PR is how the record drifts from the artifact that owns it.

**4.5** Amend the Article 30 register per the CLO advisory: additive dated brackets on **PA-8 §(g)** and **PA-31 §(g)**, no new PA number (PA-36 stays free), every implementation slot filled from the actual mint and the actual diff rather than from this plan's prose. Add one row under `## Completed Compliance Work` in `knowledge-base/legal/compliance-posture.md`. No edit to the published legal corpus.

**4.6** File the deferrals: the `.mcp.json` stdio proxy (`priority/p1-high`), the personal-token revocation, the `ADR-031` ordinal collision, the `browser_type` echo if Phase 0.1 reproduces it, and the shipped-hook work if Phase 0.4 finds the plugin manifest cannot carry a `PreToolUse` arm.

### Phase 5 — Follow-through enrolment

One probe. `scripts/followthroughs/sentry-followthrough-token-cutover-7946.sh` asserts that a sweep after the cutover ran with the new credential and that no Sentry-backed probe returned TRANSIENT for a missing token. Its positive control is impossible for the pre-change artifact: it asserts on the **new** secret name, which the old sweeper could not have set. It must not spell the retired name — Rule E's population includes it, so it reads any reference through an env indirection supplied by the sweeper. It gets a `<!-- soleur:followthrough script=... earliest=<deploy+Nd> secrets=... -->` directive, the `follow-through` label, and its `secrets=` names wired into the sweeper env. Exit 0 auto-closes the tracker, so ambiguity maps to TRANSIENT (2), never PASS.

**A disuse probe was specified and cut for cause.** "Zero reads of the retired name" has no measurement mechanism — `git grep -ln 'activity_log\|activity-log\|/v3/logs'` over `scripts/` and `apps/` returns nothing, so this repo has never exercised the Doppler activity log and the plan would have been asserting an unprobed capability. It also measures the wrong thing: consumers outside `scripts/followthroughs/` still read that name by design. The revocation PR needs a static reachability answer, and it inherits that question as a grep-plus-dry-run checklist on its tracking issue.

### Phase 6 — Verification

- Walk every pre-merge acceptance criterion and record the command output, using each criterion's
  command verbatim rather than a reconstruction of its input set.
- Re-derive the ADR ordinal across every `origin/*` ref and sweep the whole feature artifact set on
  any renumber — the plan, the spec, `tasks.md`, and the Phase 5 probe.
- Confirm the published legal corpus is untouched.

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py` *(0.1)* | The filter. Ships in the plugin; runs on the customer's machine. |
| `plugins/soleur/skills/agent-browser/test/redact-a11y-snapshot.test.sh` *(0.1)* | Filter suite. Auto-globbed; no `run_suite` line. |
| `plugins/soleur/skills/agent-browser/test/fixtures/` *(0.1)* | Synthesized snapshot fixtures. No real credential, ever. |
| `.claude/hooks/browser-snapshot-credential-guard.sh` *(0.1)* | PreToolUse interceptor, `agent-browser` Bash arm only. |
| `.claude/hooks/browser-snapshot-credential-guard.test.sh` *(0.1)* | Envelope-driven suite with a registration case. Auto-globbed. |
| `knowledge-base/engineering/operations/runbooks/sentry-org-token-rotation.md` | Agent-executable rotation with a `## Failure modes` table. |
| `knowledge-base/engineering/architecture/decisions/ADR-213-browser-snapshot-credential-guard-split.md` *(0.1)* | Ordinal provisional; re-derive before merge. |
| `scripts/followthroughs/sentry-followthrough-token-cutover-7946.sh` | Cutover soak probe. |
| `knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/followthrough-directive-census.txt` | Timestamped tracker census, so the directive-rewrite criterion is diff-derived rather than query-derived. |

Rows marked *(0.1)* exist only if Phase 0.1 measures a leak. **No new lint scripts and no new `run_suite` lines** — both walkers land as rule families inside existing hosts, and both new suites are auto-globbed.

## Files to Edit

**#7946 — sixteen followthrough files** (`grep -rl SENTRY_AUTH_TOKEN scripts/followthroughs/`, count verified 16): `ac10-workspace-reconcile-sentry-4246.sh`, `ac8-founder-ambiguous-soak-5673.sh`, `accounted-beacon-live-6462.sh`, `anthropic-admin-key-6297.sh`, `anthropic-admin-key-6297.test.sh`, `community-monitor-checkin-soak-5728.sh`, `deploy-ghcr-pull-recovery-6400.sh`, `ghcr-minter-live-6031.sh`, `git-data-birth-emitter-6982.sh`, `phase3-ga-soak-5274.sh`, `reconcile-ff-only-sentry-4977.sh`, `sentry-checkins-3859.sh` (credential **and** org slug), `sync-health-residual-5689.sh`, `workspaces-luks-soak-6604.sh`, `zot-soak-6122.sh`, `zot-soak-6122.test.sh` — each for its consumption, its xtrace-refusal predicate where present (13 files), and its Rule D remediation where baselined.

**#7946 — everything else:** `.github/workflows/scheduled-followthrough-sweeper.yml`; `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`; `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` (retarget its AC13 assertion); `scripts/lint-shell-trace-credential-refusal.py` (Rule E) and its `.test.sh` and both baseline files; `scripts/sweep-followthroughs.sh` (header comment); `.claude/hooks/follow-through-directive-gate.sh` (Phase 3.9) and its suite; `plugins/soleur/skills/schedule/SKILL.md`; `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`; `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`; `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`; `knowledge-base/engineering/architecture/diagrams/model.c4` and the regenerated `model.likec4.json`.

**#7947 — two tiers, both derived from a stated grep.**

*Tier A — walker-reachable, carrying a snapshot invocation token* (`git grep -lE 'browser_snapshot|agent-browser snapshot' -- 'plugins/soleur/skills/**' 'plugins/soleur/agents/**'`): `plugins/soleur/skills/agent-browser/SKILL.md`, `plugins/soleur/skills/test-browser/SKILL.md`, `plugins/soleur/skills/reproduce-bug/SKILL.md`, `plugins/soleur/skills/qa/SKILL.md`, `plugins/soleur/skills/feature-video/SKILL.md`, `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md`. Plus `plugins/soleur/skills/cf-token-scope/SKILL.md`, which the token grep does not catch but which carries the same inverted `browser_evaluate` rule and a "snapshot-only navigation" instruction inside a credential-mint flow.

*Tier B — prose-only, outside the walker's predicate, edited for consistency and not for the gate:* `plugins/soleur/skills/review/references/review-e2e-testing.md`, `plugins/soleur/agents/operations/ops-provisioner.md`.

**Not edited:** `plugins/soleur/skills/ux-audit/SKILL.md` and `plugins/soleur/agents/operations/ops-research.md` — both `grep -c snapshot` = 0.

**#7947 — hosts and registration:** `scripts/lint-credential-path-literals.py` (Walker 1) and its `.test.sh` and fixture corpus; `plugins/soleur/hooks/hooks.json`; `.claude/settings.json`; `.claude/hooks/README.md`.

**Legal register (per the CLO advisory):** `knowledge-base/legal/article-30-register.md` — additive dated brackets on PA-8 §(g) and PA-31 §(g), no new PA number; `knowledge-base/legal/compliance-posture.md` — one `## Completed Compliance Work` row. No edit to `plugins/soleur/docs/pages/legal/` or `docs/legal/`.

No skill `description:` front-matter field is edited, so `SKILL_DESCRIPTION_WORD_BUDGET` (2400, suite green at 1297 assertions) is untouched.

## Guard Contract

### Guard 1 — the snapshot rule family in `scripts/lint-credential-path-literals.py`

**Property.** No committed skill or agent instruction in the shipped plugin directs an accessibility snapshot inside an authentication flow without first preferring a screenshot, and — where ref discovery makes a snapshot unavoidable — routing it through the redactor. The redactor is the fallback the guard permits, not a control that makes snapshotting a credential page safe.

**Assembly.** Not a file list — a chokepoint: the host lint's existing walk over tracked `*.md` under `plugins/**` and `knowledge-base/**` minus `**/archive/**`, derived at run time from `git ls-files`. Members drift, so the walk is the assembly. Both `skills/**` and `agents/**` are in the population **by construction, but the `agents/**` arm has zero live members today and that is stated rather than implied**: the token grep returns six files, all under `skills/`, and `ops-provisioner.md` names a snapshot in prose only. M3 therefore proves the `agents/**` arm against a synthesized fixture, not live coverage — which is exactly what makes it worth keeping, since a walker scoped to `skills/` alone would pass today and rot on the first agent that gains a browser flow. The predicate quantifies over every snapshot-invocation token (`agent-browser snapshot`, `browser_snapshot`, `mcp__playwright__browser_snapshot`), because the MCP interceptor is deferred and the walker is that path's only committed control.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| M1 | Re-introduce the original `### Login Flow` body (snapshot, fill password, snapshot) into `agent-browser/SKILL.md` | RED, citing that file |
| M2 | Add the same unsafe pattern to a **second** file after the first is compliant | RED, citing **both** — a check that stops at the first member is itself an instance of the class |
| M3 | Add the pattern to a synthesized fixture under `plugins/soleur/agents/**` | RED — proves the `agents/` arm is wired despite having no live member |
| M4 | Point `--population-root` at a directory containing no markdown | Exit 2 via the host's vacuity guard — a lint reporting "0 checked" and exiting 0 is vacuous |
| M5 | Reduce the predicate's token list to the `agent-browser` form alone | RED on an `mcp__playwright__browser_snapshot` fixture |
| M6 | Replace the redactor pipe with a look-alike command name that does not redact | RED — the assertion is on the anchor, not a bare token |
| M7 | Add a fixture documenting an **un-piped retry** as the exit-2 recovery | RED — the recovery path is part of the property, and it is the one an agent reaches for first |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Delete one mutation case | Suite RED via its anti-vacuity floor (ADR-193: report directly with `printf >&2` then `exit 1`, count at the call site) |
| H2 | Make `mutate()` run inside `$( )` so its failure is swallowed | Suite RED — every mutation asserts it LANDED before the lint runs |
| H3 | Must-PASS, not the canonical: a skill that snapshots a page with no authentication context | Exit 0 |
| H4 | Must-PASS: a skill naming a password field that takes a **screenshot** | Exit 0 |
| H5 | Must-PASS: `cf-token-scope/references/widen-playbook.md` in its corrected form — snapshot **through the redactor**, screenshots still scoped to the edit control | Exit 0 — the carve-out must actually be permitted, or the guard forces a screenshot leak in its place |

### Guard 2 — Rule E in `scripts/lint-shell-trace-credential-refusal.py`

**Property.** No file under `scripts/followthroughs/` names a credential whose value a personal, human-account-scoped Sentry token can satisfy, **and no file that carries an xtrace refusal consumes the new Sentry credential without naming it in that refusal.**

The second clause is deliberately narrower than "no file consumes one credential while its refusal guards another", which would be the property worth having but is not the property this rule implements. Measured: **59 of the 78 scripts under `scripts/followthroughs/` carry no `case "$-" in *x*)` prologue at all**, several of them binding live Better Stack, Supabase and Cloudflare credentials. Implementing the broad clause would red that entire pre-existing population, which this PR does not budget. The gap is filed as its own issue with the measured count rather than smuggled in behind a rename.

**Assembly.** Every tracked file under `scripts/followthroughs/`, including `.test.sh` files and comment lines. `.test.sh` is deliberately in scope for this rule, which needs a per-rule exclusion override in the shape of `excluded_for_rule_d`, since the shared `EXCLUDE_PATTERNS` drops it for every other rule. Min-cardinality floor **14**. Any probe that must *reference* the retired credential does so through an env indirection, never a literal — stated here because Phase 5's probe lives inside this walker's own population.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| M1 | Restore `SENTRY_AUTH_TOKEN` in one migrated `.sh` | RED, citing the file at its true line |
| M2 | Restore it in a **second** file after the first is compliant | RED citing both |
| M3 | Restore it in a `.test.sh` only | RED — proves test files are in the population |
| M4 | Restore it inside a full-line **comment** | RED — the name in a comment is what the next author copies |
| M5 | Force a floor breach on the **production** path via the test-only override, with no `TARGET_DIR` | Exit 2. The floor keys on the resolved target dir matching the default, so an empty mktemp sandbox deliberately skips it — pointing `TARGET_DIR` at one is not a floor test |
| M6 | **Rename a file's consumption to the new credential but leave its xtrace refusal predicate on the old one** | RED — the defect that would re-open the #7797 class, invisible to a name-only predicate |
| M7 | Rename a file's consumption and **delete** the Sentry limb from a multi-credential refusal predicate | RED. Measured, this is reachable: `anthropic-admin-key-6297.sh` guards `"${BETTERSTACK_QUERY_PASSWORD:+x}${GH_TOKEN:+x}${SENTRY_AUTH_TOKEN:+x}"` as one concatenated predicate, so an edit that drops the third term instead of renaming it satisfies both the absence-grep and M6 while shipping a file that consumes the new credential with nothing guarding it |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Remove one RED case | Suite RED via its anti-vacuity floor |
| H2 | Must-PASS, not the canonical: a probe naming `SENTRY_FOLLOWTHROUGH_RO_TOKEN` and `BETTERSTACK_API_TOKEN` together, with a matching refusal predicate | Exit 0 |
| H3 | Must-PASS: `TARGET_DIR` pointed at an empty mktemp sandbox | Exit **0** — pins the sandbox exemption, so a later "fix" that fires the floor in sandboxes breaks this row instead of every other case |

### Guard 3 — `.claude/hooks/browser-snapshot-credential-guard.sh`

**Property.** A Bash-invoked `agent-browser snapshot` not routed through the redactor is denied before it runs — **on a customer's machine, not only in this checkout.**

**Assembly.** The `tool_input.command` string of every PreToolUse `Bash` envelope, plus the two registration manifests that determine whether the hook dispatches at all: `plugins/soleur/hooks/hooks.json` (the shipped surface) and `.claude/settings.json` (this checkout). The chokepoint is the hook's own dispatch, which is why M4 targets the manifests.

**Mutation matrix.**

| # | Edit | Must |
|---|---|---|
| M1 | Envelope carrying a bare `agent-browser snapshot -i` | `permissionDecision: "deny"`, reason naming the redactor and the screenshot alternative |
| M2 | The same command reached through a wrapper (`bash -c '... agent-browser snapshot ...'`, or after a `--` separator) | Deny — an anchor on `^` or a chain operator alone silently passes the wrapped form |
| M3 | Two snapshot invocations chained with `&&` where only the first is piped | Deny |
| M4 | Delete or mis-spell the hook's entry in **either** manifest | Suite RED via its registration case, which parses both with `jq` and asserts a `PreToolUse` entry whose matcher selects `Bash`, whose command resolves to an existing executable, and which has a matching row in the `.claude/hooks/README.md` table |
| M5 | Change the emitted decision from `permissionDecision: "deny"` to any non-deny value, or make it exit 0 with empty stdout | Suite RED on the envelope cases — the emitted decision is the only thing a stdin/stdout hook can be held to |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Delete one envelope case | Suite RED via its anti-vacuity floor |
| H2 | Must-PASS: `agent-browser snapshot -i 2>&1 \| python3 <redactor>` | Allowed. **The `2>&1` is part of the approved form, not decoration:** a pipe redirects stdout only, while the Bash tool captures stdout and stderr merged, so any node content `agent-browser` writes to stderr would reach the transcript un-redacted while the interceptor reported the invocation compliant. Phase 0.1 measures whether it writes any. |
| H3 | Must-PASS: `agent-browser screenshot` and `agent-browser open` | Allowed — the hook must not become a general `agent-browser` ban |

## Observability

```yaml
liveness_signal:
  what: the daily follow-through sweep completes with every Sentry-backed probe
        returning a definite verdict rather than TRANSIENT-missing-token
  cadence: daily (scheduled-followthrough-sweeper.yml)
  alert_target: the tracker issue itself — sweep failures post a comment and leave
        the issue open; scripts/followthroughs/sentry-followthrough-token-cutover-7946.sh
        is the enrolled probe that asserts it
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml

error_reporting:
  destination:
    - "#7946 paths: observability layer 6 — the synchronous workflow-run log plus the
       sweeper's own issue comment. scripts/sweep-followthroughs.sh posts the last 4 KB
       of stdout/stderr onto the tracker, and its comment path deliberately strips xtrace
       lines because issue-comment bodies do NOT pass through the Actions secret masker."
    - "#7947 paths: observability layer 7 — the self-hosted CLI synchronous consumer.
       The filter and the interceptor run on a customer's own machine, where the
       operator- and agent-visible signal is the tool-result stdout and stderr read
       in-session (cli-stdout-artifact), plus the hook's .claude/.rule-incidents.jsonl
       row. There is no hosted sink for layer 7 by design, and this plan does not add one.
       The operator-facing signal is therefore the agent's rendering of the tool result,
       which is why the filter's exit-2 diagnostic and the deny reason are both written
       in plain language rather than as agent-only tokens."
    - "Both rule families: observability layer 6 — the CI step output in
       .github/workflows/ci.yml (including the required credential-path-guard job) and
       the scripts/test-all.sh scripts shard."
  fail_loud: yes — every new path exits 2 on cannot-evaluate rather than 0, and the
        filter's exit 2 carries a stderr diagnostic, so an instrument that cannot tell
        clean from never-ran reports the ambiguity instead of a green.

failure_modes:
  - mode: the new read-only token 403s on an endpoint or an org slug Phase 0.2 did not probe
    detection: the affected probe exits 2 TRANSIENT and the sweeper posts the HTTP status
        onto the tracker issue
    alert_route: layer 6 — tracker comment plus workflow-run log
  - mode: gh secret set failed, so the sweeper env key resolves to an empty string
    detection: NOT the sweeper's set-ness check, which passes on an empty value — the
        real detector is each script's own [[ -z "${VAR:-}" ]] guard, which exits 2
        TRANSIENT. The pre-merge check is `gh secret list` showing the name before the
        sweeper env change merges.
    alert_route: layer 6
  - mode: a tracker filed after the census still names the retired credential
    detection: the extended follow-through-directive-gate rejects the directive at write
        time; if it slips past, the sweeper fails the issue with "required secret
        '<name>' not set in workflow env — leaving issue open"
    alert_route: layer 6 — hook refusal in-session, then tracker comment
  - mode: a file consumes the new credential while its xtrace refusal guards the old one
    detection: Rule E M6 — red in the scripts shard and in the required credential guard
    alert_route: layer 6 — CI step output
  - mode: the redactor exits 2 mid-pipe, so a snapshot produces no output
    detection: empty stdout plus a plain-language stderr line naming the screenshot
        alternative, read in-session by the agent and rendered to the operator
    alert_route: layer 7 — cli-stdout-artifact, synchronous in the tool result
  - mode: the interceptor denies a legitimate snapshot (false deny)
    detection: the deny reason returns synchronously to the agent; the hook writes its
        reason string to .claude/.rule-incidents.jsonl
    alert_route: layer 7 in-session, plus the incidents ledger
  - mode: a rule family's population walk breaks and it scans nothing
    detection: the host lint's vacuity guard or the min-cardinality floor exits 2, never 0
    alert_route: layer 6 — CI step output

logs:
  where: workflow-run logs and tracker issue comments (layer 6); in-session tool results
        and .claude/.rule-incidents.jsonl (layer 7)
  retention: GitHub Actions default for run logs; tracker comments are permanent; the
        incidents ledger is local to the checkout

discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py
  expected_output: "exit 0, repo-wide, with Rule E active and a scanned-file count at or above its floor"
```

No limb requires SSH (`hr-no-ssh-fallback-in-runbooks`). The rotation runbook has no SSH fallback either.

## Infrastructure (IaC)

### Terraform changes

**None, and the reason is measured rather than assumed.** A Sentry Internal Integration is created by `POST /api/0/organizations/{org}/sentry-apps/`, which requires `org:admin` or `org:integrations`. No Soleur credential holds either, and Sentry additionally blocks an internal-integration identity from creating sentry-apps at all — so the Terraform provider, which authenticates with exactly such a token, cannot represent the resource however the configuration is written. A vendor-imposed limit verified live (#5495 / #5496), not a preference.

### Apply path

Playwright dashboard automation driven by an agent, followed by a scripted `gh secret set`. This is the rung `plugins/soleur/skills/cf-token-scope/` (ADR-130) and `scripts/rotate-x-api-secret-bootstrap.sh` already establish. The token is captured with `browser_evaluate(filename:)` — **with** the filename, per the learning — JSON-decoded, written, verified and shredded inside one trap scope.

`hr-exhaust-all-automated-options-before` is satisfied by measurement: the API rung is closed with a named reason, the dashboard rung is proven open, and the plan takes the open rung. **The one human limb is named honestly rather than elided:** if the browser profile's session has expired, clearing login and MFA is the sanctioned interactive-auth gate, identical in kind to `cf-token-scope`'s click-path step 2, and everything after it is automated. An API 403 is not evidence of an operator gate; a *newly appeared* human gate mid-form is `attempted-blocked-on-tool` and is filed as a tooling retry with a resume recipe, never relabelled operator-only.

### Distinctness / drift safeguards

The new credential is a GitHub repo secret, distinct from Doppler `soleur/prd` (`SENTRY_ISSUE_RO_TOKEN`) and Doppler `soleur/prd_terraform` (the personal token). That distinctness is the point of the change. No Terraform state holds the value.

### Vendor-tier reality check

Sentry Internal Integrations carry no per-integration billing on the current plan. `jikigai-eu` already carries two at zero recorded expense, so `wg-record-recurring-vendor-expense-before-ready` records nothing new.

## Encryption Posture

Not applicable, and the skip is recorded rather than silent. Phase 2.11's detection set is `.tf`, `supabase/migrations/*.sql`, `cloud-init*.yaml`, `docker-compose*.yaml`; this plan touches none, introduces no persistent store and no new cross-component connection. The credential in flight moves over the existing GitHub-Actions-secret and Sentry HTTPS channels already covered by the current posture.

## GDPR / Compliance Gate determination

Both limbs are recorded because they disagree, and the disagreement is the interesting part.

**Hard-rule limb — NOT APPLICABLE.** The single source of truth is the canonical regex under `## Path globs (canonical)` in `plugins/soleur/skills/gdpr-gate/SKILL.md`, which reaches `apps/web-platform/supabase/migrations/`, `apps/web-platform/lib/auth/`, `apps/web-platform/server/*auth*`, `apps/web-platform/app/api/*`, and any `.sql`. No path this plan touches matches it — `scripts/followthroughs/*.sh`, the sweeper, the tracker directives, `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` (under `infra/`, not `lib/auth/`), the rule families, the browser-driving markdown, the hook, ADR-031, the post-mortem and the register are all outside. The `gdpr-gate-advisory` lefthook breadcrumb will not print and ship Phase 5.5 requires no critical-finding acknowledgement.

The tension is recorded rather than elided: #7947's subject is literally password inputs, which reads as an "auth flow" in the rule's prose gloss. It is not one here — the password field belongs to a **third party's** login form rendered in a browser the agent drives, not to a Soleur authentication surface.

**Skill Phase 2.7 expansion limb — FIRES, on two triggers.** The plan declares `brand_survival_threshold: single-user incident` (trigger b) and changes an artifact-distribution surface: a new script, revised skills and now a shipped `PreToolUse` hook reach customers' machines (trigger d). Under those triggers the gate is invoked, and it is discharged by the CLO advisory in `## Domain Review`, which carries the Article 30, 32, 33 and 34 analysis.

**Findings: no Critical.** No Article 9 special-category data, no new lawful basis, no Article 30 trigger — a credential's scope and a tool's output filter are Article 30(1)(g) technical-measure facts, not 30(1)(b)-(f) facts: same purpose, same data subjects, same categories, same recipient, same retention, same transfer posture. Nothing routes to `compliance-posture.md` Active Items and no `compliance/critical` issue is filed. The register work is two additive dated brackets and one Completed row.

The direction of travel is protective: this reduces what is recorded rather than adding a processing activity, and the credential at issue is the operator's own — the fact that bears on the Article 33/34 analysis.

## Architecture Decision (ADR/C4)

See Phase 4.1 through 4.3, which carry the ADR-031 amendment, the new ADR's per-path statement of what ships and what does not, and the `model.c4` edge-label correction with its full external-actor / external-system / relationship enumeration.

The ordinal is a claim, not a reservation. Re-derive across every `origin/*` ref immediately before merge with a recorded command, and when it moves, sweep the whole feature's artifact set — the plan, the spec, the tasks, and the Phase 5 probe — not just `knowledge-base/`.

## Acceptance Criteria

### Pre-merge (PR)

1. Phase 0.1's per-surface, per-provenance leak verdict is recorded in the plan, with the sentinel, the grep result, and the exact serialized node line per surface. **Every recorded line passes `python3 plugins/soleur/skills/incident/scripts/redact-engine.py` with exit 0 before it is committed, and must contain `ZZQP-SENTINEL-7947` and no other credential-shaped string** — pasting a raw snapshot line into a tracked file is itself a commit-time credential path, and the headed arm runs in a profile whose password manager may fire on `localhost`. No downstream deliverable is built before this lands. Under any verdict other than "neither leaks", it is recorded in the new ADR as well.
2. Phase 0.2's probe table is recorded with an HTTP status for all four endpoints **and every distinct org slug**, and the minimum scope set is derived from those statuses.
3. The ADR records the exact checkbox set selected in the mint form and the exact `.auth.scopes` that `GET https://jikigai-eu.sentry.io/api/0/` returns for the new token. The criterion is equality against that recorded pair — "no scope outside the smallest dashboard-expressible superset" has no derivable referent and is not assertable; the recorded form does, and any scope Sentry implied from a selected level is visible in the diff between the two.
4. `grep -rl SENTRY_AUTH_TOKEN scripts/followthroughs/ | wc -l` returns `0`.
5. `grep -c 'SENTRY_AUTH_TOKEN:+x' scripts/followthroughs/*.sh 2>/dev/null | grep -v ':0$' || true` returns empty — no file's xtrace refusal still guards the retired credential.
6. Every file consuming the new credential names it in its own xtrace refusal: `grep -l SENTRY_FOLLOWTHROUGH_RO_TOKEN scripts/followthroughs/*.sh | wc -l` equals `grep -l 'SENTRY_FOLLOWTHROUGH_RO_TOKEN:+x' scripts/followthroughs/*.sh | wc -l`. The negative criterion above cannot see a predicate that dropped the Sentry limb entirely.
7. `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0, with every touched baseline line remediated and deleted rather than re-suppressed.
8. `python3 scripts/lint-credential-path-literals.py` (full scan, the form the required `credential-path-guard` job runs) exits 0 with the snapshot rule family active and a non-zero scanned-file count.
9. `bash scripts/test-all.sh scripts` is green. **This plan adds no `run_suite` line**: both rule families inherit registered hosts, and both new suites are auto-globbed.
10. `bash scripts/lint-orphan-test-suites.sh` exits 0, still reporting 0 orphaned across its six registration surfaces.
11. `cd plugins/soleur && bun test test/components.test.ts` is green.
12. The C4 syntax, render and `c4-count-parity` suites are green after the edge-label edit and the `model.likec4.json` regeneration.
13. `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` is green with its AC13 assertion retargeted, not deleted.
14. Every mutation-matrix row has a corresponding suite case, asserted by a suite-level check that the case count equals the matrix row count and reported per ADR-193 — not by a human cross-read.
15. `plugins/soleur/skills/agent-browser/SKILL.md` `### Login Flow` routes every credential-page snapshot through the redactor, verifies login by screenshot, and no longer contains the `password123` literal.
16. `git grep -lE 'browser_snapshot|agent-browser snapshot' -- 'plugins/soleur/skills/**' 'plugins/soleur/agents/**'` returns exactly the Tier-A paths, and Walker 1 exits 0 over all of them. Neither `ux-audit/SKILL.md` nor `ops-research.md` appears in the diff.
17. Neither `cf-token-scope` file instructs `browser_evaluate` without a `filename`, and `widen-playbook.md` still carries its screenshot-scoping constraint verbatim.
18. `grep -c 'SENTRY_AUTH_TOKEN' knowledge-base/engineering/operations/runbooks/followthrough-convention.md || true` returns `0` — all **three** occurrences rewritten, not only the two `secrets=` literals.
19. The post-mortem's `### Still open` names the new shape, and `git diff origin/main -- <post-mortem>` shows hunks only inside that section — its `art_33_*` / `art_34_*` frontmatter, its Art. 4(12) determination section and the asymmetry table's read-limb column are unchanged.
20. `knowledge-base/legal/article-30-register.md` carries additive dated brackets on PA-8 §(g) and PA-31 §(g) with every slot filled from the actual mint and diff, and `grep -c 'PA-36' knowledge-base/legal/article-30-register.md || true` returns `0`.
21. `git diff --name-only origin/main -- plugins/soleur/docs/pages/legal/ docs/legal/` is empty — the published corpus is untouched, so the five `docs/legal/**` gates stay disarmed.
22. `python3 scripts/lint-infra-no-human-steps.py --changed --base "origin/$BASE_REF"` exits 0, invoked exactly as CI invokes it. Its scope is the five `SCAN_DIRS` roots only, so it covers this plan, the rotation runbook and both ADRs, and covers none of the hook, the rule families, the workflow or `model.c4` — none of which carry human-step prose.
23. The committed census fixture exists with a recorded UTC timestamp, its own count asserted non-zero, and every issue in it whose body matches `secrets=[^ ]*SENTRY_AUTH_TOKEN` appears in the PR's rewrite log. Trackers filed after the timestamp are covered by the Phase 3.9 gate, not by this criterion.
24. `plugins/soleur/hooks/hooks.json` declares the interceptor on a `PreToolUse` `Bash` matcher — or, if Phase 0.4 found the manifest cannot carry one, `## User-Brand Impact` states plainly that P7 is not delivered to the operator and a `priority/p1-high` deferral issue exists.
25. A pre-merge step records the reading of `for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree --name-only "$r" -- knowledge-base/engineering/architecture/decisions/; done | sed 's|.*/||' | grep -oE '^ADR-[0-9]{3}' | sort -u | tail -1` in the PR body. If it exceeds ADR-212 the file is renamed and the sweep is clean, measured as:

    git grep -l 'ADR-213' -- 'knowledge-base/project/plans' 'knowledge-base/project/specs' \
      'scripts/followthroughs' \
      ':!knowledge-base/project/plans/2026-09-09-feat-sentry-org-token-and-snapshot-redaction-plan.md' \
      | wc -l

    returns 0. The pathspec exclusion and the `| wc -l` are both load-bearing: this plan file lives
    permanently under `knowledge-base/project/plans/` and will always contain the literal `ADR-213`
    in its own provisional-ordinal prose, so an unexcluded absence-grep can never observe zero; and
    plain `grep` exits 1 on no match, which would abort a `set -e` caller on precisely the clean
    state the criterion is asserting.
26. Deferral tracking issues exist for: the `.mcp.json` stdio proxy (`priority/p1-high`), the personal-token revocation, the `ADR-031` ordinal collision, the `browser_type` echo if reproduced, and the shipped-hook work if applicable.
27. The PR body uses `Closes #7946` and `Closes #7947`.

### Post-merge (automated, no operator step)

28. The first scheduled sweep after merge runs with the new credential and posts no missing-token TRANSIENT on any Sentry-backed probe, verified by the enrolled cutover probe with an `earliest` of deploy plus one sweep cycle.

## Domain Review

**Domains relevant:** engineering, legal. Operations is folded into `## Infrastructure (IaC)` — once the mint rung is settled there is no separate provisioning decision. Product is NONE: the mechanical UI-surface override was run against `## Files to Create` and `## Files to Edit` and no path matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` or any UI-surface term, so `wg-ui-feature-requires-pen-wireframe` does not fire and no wireframe is required. Marketing, sales, finance and support are not implicated. `cmo` and `ux-design-lead` were not activated on an independent content read; `cpo` was not activated because the plan carries no product-scope or positioning language beyond engineering.

### Engineering

**Status:** reviewed. Five lenses ran: CTO (devex and strategy), Kieran (correctness and convention), code-simplicity (per-mechanism justification), architecture-strategist (blast radius), spec-flow-analyzer (journey completeness), plus a Step 4.5 scoped strong-model consult.

The panel corrected the plan far more than it endorsed it. Every correction below was independently re-verified in this worktree before being folded in — a reviewer's negative is a claim, not a fact, and one of them (an "ADR-202 does not exist" report) was a false negative.

**What the panel changed, in order of consequence:**

1. **A defect that would have re-opened the incident this PR closes.** Thirteen of the sixteen followthrough files carry the ADR-202 xtrace refusal with the credential named in the predicate. Renaming consumption without renaming the refusal leaves the escape hatch open **on the new credential** — the "guarded one credential and consumed another" defect ADR-202's Rule C exists for. Phase 3.3 now rewrites both guards and Rule E gains M6.
2. **The plan as drafted could not merge green.** `lint-shell-trace-credential-refusal-d.baseline.txt` carries 21 followthrough entries and states that `--changed` bypasses it, so touching a listed script obliges remediation. Budgeted in Phase 3.3, and asserted by the criterion that runs the lint under CI's own `--changed --base origin/main` invocation.
3. **The #7947 premise was never measured.** Every supporting fact concerned documentation or hook capability; nothing established that either tool emits the password value. Phase 0.1 is that measurement, and the strong-model consult sharpened it further: a value the agent *types* is already in the transcript as the tool-call argument, so a probe that fills the field by driving the tool measures the wrong exposure entirely.
4. **P7 was not delivered to the actor the plan exists to protect.** The shipped plugin declares only `SessionStart` and `Stop` hooks; a hook in `.claude/settings.json` never reaches a customer. Phase 0.4 now decides the shipping surface, and if it cannot ship, the plan says so instead of implying enforcement the operator does not receive.
5. **The ADR-202 framing was a rationalisation.** The redactor pipe is not a carried artifact — ADR-202's own Alternatives table classifies a targeted redaction on a known channel as "defense-in-depth on one enumerated sink, not a substitute for the carried refusal". Phase 4.2 now states per path what ships, and that P7 is unachieved on the MCP path.
6. **Two shipped files teach the inverse of the leak rule they cite.** Both `cf-token-scope` files instruct `browser_evaluate` *without* a `filename`, while the learning they cite records that the filename is what keeps the value out of the transcript. Corrected in Phase 2.2 — in files this PR already opens.
7. **The compatibility shim was inert and made failures quieter.** Cut; the directive rewrites are sequenced instead.
8. **A guard suite outside `## Files to Edit` asserts on a line Phase 3.5 changes.** Added, with the instruction to retarget rather than delete.
9. **Mechanism duplication.** Both walkers now land as rule families inside existing lints, removing two scripts, two suites, a fixtures directory and every new `run_suite` line. The draft had argued a second predicate would make an existing guard ambiguous — an argument the repo already refutes in production.
10. **Population and count corrections throughout:** sixteen followthrough files not thirteen; six token-bearing browser surfaces not eight, with the `agents/**` arm currently vacuous; three occurrences in the convention doc not two; four `run_suite` lines not six, and then zero after the merges.

**Standing disagreement, recorded rather than resolved by fiat.** The CTO lens rules for a dedicated fourth integration on store and rotation-domain-independence grounds; the architecture lens rules against it, on the grounds that a fourth credential with an identical scope set widens the surface this PR narrows. Phase 3.1 follows the CTO lens and names what would flip it.

**Split recommendation.** Three of the five lenses independently recommended splitting the PR. It is surfaced as DC-1 rather than applied, because it changes the operator's stated direction — but the phase order now puts #7947 entirely ahead of #7946 so that taking it is a cut, not a re-plan.

### Legal (CLO)

**Status:** reviewed. Scope fence held — #7945 was not assessed and no vendor correspondence drafted.

- **Article 30: no new Processing Activity.** Both changes are Article 32 technical-measure changes to registered activities. Next free number is **PA-36, verified and deliberately left free**; the only PA-36 references in the corpus *reserve* it. Two additive dated brackets instead: **PA-8 §(g)** for the credential (beside the sibling `inline-read-prd` control) and **PA-31 §(g)** for the redaction (beside the deny-by-default PreToolUse allowlist, the same control family). Every slot filled from the actual mint and diff, never from plan prose.
- **Article 32: no published-disclosure change.** No edit to `plugins/soleur/docs/pages/legal/` or `docs/legal/`, on three grounds: nothing in the published corpus states the fact being changed, so no sentence becomes false; Article 32 requires appropriate measures, not published ones, and the Article 13/14 facts are unmoved; and AUP §5.1's nearest candidate sentence stays true and must not be widened, since rewriting it would convert a shipped hardening into a contractual promise about third-party tool output Jikigai does not control. Consequence: the five `docs/legal/**` gates stay disarmed.
- **Article 33/34: no notification duty in this shape.** An operator's own infrastructure credential is not itself personal data, so the duty arises only derivatively. Limb 1 is satisfied; limb 2 is not — the channel is bounded to the operator's own session and a recipient already covered by the existing DPA, with no commit, no issue post and no CI emission. Reachability triggers the investigation, not the notification. **Two conditions bound it, and both are recorded in the ADR:** it holds only while the credential's investigation has not returned BREACH, and **it flips if the redacted field ever holds a third party's password** rather than the operator's own.
- **Posture:** no Active Item opened or closed; one `## Completed Compliance Work` row on merge, modelled on the #6882 precedent.
- **One hard constraint on the post-mortem edit:** update `### Still open`, and touch none of that file's `art_33_*` / `art_34_*` frontmatter, its Art. 4(12) determination section, or the asymmetry table's read-limb column. Amending a machine-readable legal claim from a hardening PR is how the record drifts from the artifact that owns it.
- **Vendor expense:** none. `jikigai-eu` already carries two Internal Integrations at zero recorded expense; a third is the same object.

Internal draft material, not external legal advice.

### Sign-off

`brand_survival_threshold: single-user incident` sets `requires_cpo_signoff: true`. `user-impact-reviewer` is invoked at review time per the review skill's conditional-agent block, and plan-review has already run at the escalated five-agent level.

## Test Scenarios

| # | Scenario | Expectation |
|---|---|---|
| T1 | A synthesized fixture with a password textbox holding the sentinel, piped through the redactor | Sentinel absent from stdout; `<redacted>` present; exit 0 |
| T2 | A fixture with only non-credential fields | Byte-identical passthrough; exit 0 |
| T3 | A `type=password` node whose accessible name is `Passphrase` | Redacted — structural predicate first |
| T4 | A `--json` snapshot shape carrying a password node | Redacted in the JSON value; JSON still parses |
| T5 | Malformed or over-cap input | Exit 2, stdout empty, stderr a plain-language line naming the screenshot alternative and free of the sentinel |
| T6 | The original `### Login Flow` body restored | Walker 1 RED, citing that file |
| T7 | The pattern added to a second file, and to a synthesized `agents/**` fixture | Walker 1 RED in both cases |
| T8 | A fixture documenting an un-piped retry as the exit-2 recovery | Walker 1 RED |
| T9 | Walker 1 pointed at an empty `--population-root` | Exit 2 via the vacuity guard |
| T10 | `SENTRY_AUTH_TOKEN` restored in a `.sh`, a `.test.sh`, and a comment | Rule E RED in all three, at true line numbers |
| T11 | A file whose consumption is renamed but whose xtrace refusal is not | Rule E RED — the #7797 re-leak case |
| T12 | Rule E floor forced above the live count on the production path | Exit 2; and `TARGET_DIR` at an empty sandbox exits 0 |
| T13 | PreToolUse envelopes: bare `agent-browser snapshot -i`, the same wrapped after `--`, and two chained with `&&` | Deny in all three, reason naming the redactor and the screenshot |
| T14 | PreToolUse envelopes: the piped form, `agent-browser screenshot`, `agent-browser open` | Allow in all three |
| T15 | The hook's entry deleted from either registration manifest | Hook suite RED via its registration case |
| T16 | Each of the four Sentry endpoints probed with the new token, per org slug | Documented status per pair; any 403 blocks the cutover |
| T17 | A dry-run sweep against a tracker whose directive still names the retired credential | Fails and stays open with the "required secret not set" message — the documented safe direction |
| T18 | A tracker directive naming the retired credential submitted to the Phase 3.9 gate | Refused at write time |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The #7947 hazard may not reproduce on the surfaces this repo uses.** Every supporting fact is about documentation or hook capability; Playwright's ARIA snapshot may render `textbox "Password"` with no value at all. | Phase 0.1 measures it first, per surface, per provenance path, per flag, headed and headless. Five verdicts, each with a kept/dropped/voided list, including "neither leaks" — which closes #7947 on the measurement rather than on apparatus for a hazard that does not exist. |
| **A probe that fills the field by driving the tool would measure the wrong exposure.** An agent-typed value is already in the transcript as the tool-call argument. | Phase 0.1 sets the sentinel by non-agent paths only. The agent-typed echo is a separate row with its own issue. |
| **Renaming the credential would re-open the #7797 leak class inside the PR that closes it** — thirteen files guard `SENTRY_AUTH_TOKEN` in their xtrace refusal while consuming the new name. | Phase 3.3 rewrites both guards per file; Rule E's M6 and M7 rows red on the mismatch so the coupling cannot silently break again; two criteria assert it directly — that no refusal predicate still names the retired credential, and that every file consuming the new one names it in its own refusal. |
| **The rename drags in a Rule D baseline drawdown across 21 baselined followthrough entries**, because `--changed` bypasses the baseline. | Measured and budgeted in Phase 3.3, with the criterion that asserts the lint green under CI's own invocation. If the remediation cannot be carried, the rename must not happen in this PR — which is DC-1's strongest argument. |
| **A compatibility shim would make failures quieter rather than safer**, since the sweeper forwards only names a directive lists. | No shim. The directive rewrites are sequenced first, and a missed tracker fails loudly with a message naming both defect and fix. |
| **`sentry-checkins-3859.sh` points at a different Sentry org than the one being minted in**, and it is a caller of the at-risk endpoint. | The slug moves in Phase 3.3, in scope. Phase 0.2 probes both slugs so the need is measured rather than assumed. |
| **The mint could leave an unrecoverable token attached to a live integration.** | Capture, decode, write, verify and shred all live in one trap scope; a failed write deletes the just-minted integration in-page before the trap fires. |
| **The Playwright mint is itself a browser login** — the #7947 hazard inside the PR that fixes it. | Performed under the #7947 discipline, after Phase 2 has landed the guard. |
| **A false deny gets the interceptor disabled**, and a worked-around guard reads as coverage. | No MCP arm. The Bash arm decides from the command string alone with no session state, carries a kill switch and a ledger row, and its must-PASS rows pin the legitimate forms. |
| **P7 is not achieved on the Playwright-MCP path.** | Stated plainly in `## User-Brand Impact`, `## Non-Goals` and the ADR, rather than implied away. The proxy issue is filed `priority/p1-high`. |
| **A guard that cannot tell clean from never-ran.** | Every rule family inherits its host's vacuity guard or carries a cardinality floor; every suite carries an anti-vacuity floor reporting directly per ADR-193; each matrix has a row targeting its own dispatch. |
| **The ADR ordinal is a claim, not a reservation.** | Re-derived across all `origin/*` refs before merge, with the sweep extended past `knowledge-base/`. |

## Alternatives Considered

| Alternative | Why not (now) |
|---|---|
| **Splice a redaction proxy into `.mcp.json`'s launch of the Playwright MCP.** The only structural control for the MCP runtime path. | Deferred, `priority/p1-high`. It protects **this checkout only** — the shipped plugin is what reaches Soleur users — and it cannot be verified in-session, since `.mcp.json` changes load only on a full Claude Code restart and a proxy that silently fails to splice is indistinguishable from one that works. Merging a guard that cannot be observed working is worse than a tracked issue. The deferral is honest only because the plan states that P7 is unachieved on that path rather than implying the walker covers it. |
| **A PreToolUse arm denying `browser_snapshot` in a credential context.** | Not shipped. The tool takes no arguments, so the predicate is reconstructed from side-channel state: fails open on six paths, fails closed on the log-in-then-snapshot loop four skills rely on. |
| **An unconditional deny of `browser_snapshot` with an acknowledgement escape hatch.** | The fallback if MCP-path coverage is wanted before the proxy lands. Its false-deny cost is *knowable* where a heuristic's is not. Not the default, because Phase 0.1 may show that surface does not leak. |
| **A stateless input-side deny on `browser_type` / `browser_fill_form` into password fields.** | Closes a *different* hazard: an agent-typed credential is in the transcript as the tool-call argument before any snapshot. Recorded as DC-2 and filed as its own issue if Phase 0.1 reproduces the echo. |
| **A PreToolUse *rewrite* (ADR-162) rather than a deny.** | Genuinely stronger — it buys P7 without the agent remembering. But `hookeventname-coverage.test.sh` hard-fails a second rewriter and the one permitted rewriter is `grep-rewrite.sh`, so taking it means an ADR-162 amendment with defined precedence: a third architectural decision in a PR carrying two. Evaluated at Phase 0.4; default not taken. |
| **Two new standalone lint scripts with their own suites, fixtures and registrations.** The first draft. | Rejected — the plan's largest reduction. The draft argued a second predicate would make an existing guard's floor and matrix ambiguous, which the repo already refutes in production: `lint-shell-trace-credential-refusal.py` ships four rule families, and Rule D is not about xtrace at all, carrying its own exclusion function and its own baseline. The draft named that file its structural model and then declined to copy the one structural decision it makes. |
| **Reuse `inline-read-prd` / `SENTRY_ISSUE_RO_TOKEN` instead of minting a fourth integration.** | Rejected on the **store**, with the dissent recorded. ADR-031 places that token in Doppler for a stated reason; the sweeper needs a GitHub repo secret. Reuse contradicts a reasoned amendment, doubles blast radius, and couples two rotation domains. The architecture lens argues the opposite — that a fourth integration with an identical scope set widens the very surface this PR narrows — and Phase 3.1 names what would flip the decision. |
| **Narrow `iac-terraform-prd` in place.** | Would break the Terraform plane, which measurably needs `project:admin` and `alerts:write`. Narrowing happens by adding a dedicated read-only integration, never by shrinking a shared one. |
| **A disuse soak probe asserting zero reads of the retired name.** | Cut for cause: no measurement mechanism exists in this repo, and it measures the wrong thing since consumers outside the followthroughs still read that name by design. The revocation PR needs a static reachability answer. |
| **Renumbering the duplicated `ADR-031`.** | A real hazard that buys none of this plan's properties. Flagged in the amendment header; tracking issue filed. |
