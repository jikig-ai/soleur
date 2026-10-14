---
title: "feat: Operator weekly comprehension digest"
issue: 5085
branch: feat-operator-weekly-digest
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-11-operator-weekly-digest-brainstorm.md
spec: knowledge-base/project/specs/feat-operator-weekly-digest/spec.md
plan_review: applied 2026-06-11 (code-simplicity + architecture-strategist + spec-flow-analyzer + security-sentinel)
---

# feat: Operator Weekly Comprehension Digest ✨

## Overview

A weekly, plain-language **private** digest that tells the non-technical operator *"what your
company actually did this week"* — fighting **business comprehension debt** (autonomous loops ship
features, move money, and resolve incidents faster than a solo owner can track).

**Substrate (settled):** a **scheduled GitHub Actions workflow that runs `claude-code-action` to
invoke a new Soleur skill** (`operator-digest`). The workflow lives in a **NEW private repo**
(`jikig-ai/operator-digest`) so its Actions logs *and* the digest issues stay private; it reads the
**public** `jikig-ai/soleur` repo for data. The skill (SKILL.md, public, instructions-only) reads
four sources, synthesizes plain prose, and writes `digest.md`; a deterministic workflow **post-step**
scrubs that file (fail-closed) and only then posts a private GitHub issue. **LLM-as-script** pattern
— synthesis is SKILL.md prose, not a TS/bash synthesizer; bash is reserved for the scrub gate + the
post. Distinct from the shipped **community** release digest (`cron-weekly-release-digest.ts`, #5080):
that is a public TS Inngest cron with a *closed* input set; this is operator-private with the *open*
internal-business input set it inverts against.

**V1 sections:** (1) What your company built; (2) Money & vendors; (3) What broke & whether it's
fixed; (4) Action needed from you. **Type:** feature (new skill). **Semver:** `minor`.

**ADR:** this PR introduces a new repo, a new cross-repo read pattern, and a privilege-separated
two-token topology — an ADR is warranted (`/soleur:architecture create "Operator-private weekly
digest — two-repo privilege-separated pipeline"`), capturing the scrub-as-post-step + two-token-context
decisions outside this (archivable) plan.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Deliver to a "private GitHub issue in the operator's repo" (soleur) | **`jikig-ai/soleur` is PUBLIC.** A soleur issue is world-readable; generating the digest in soleur's Actions runs in **public logs**. | **Operator re-decided (2026-06-11): provision a NEW private repo** `jikig-ai/operator-digest`. Workflow + issues both private; reads public soleur for data. Resolves both the issue-leak and the public-logs-leak. |
| "Action needed" is a thin signal (~stale-CLA only) | **FALSE — verified 7 producers** of the `action-required` label: `cron-linkedin-token-check.ts` (OAuth expiry), `cron-supabase-disk-io.ts` (DB disk/IO), `cron-gh-pages-cert-state.ts` (TLS cert), `event-cf-token-expiry-check.ts` (CF token), `cron-campaign-calendar.ts` (overdue content), `scripts/content-publisher.sh` (failed posts), `cla-evidence-timestamp.yml` (stale CLA). | **Section 4 is HIGH-value, not thin** — expiring tokens / saturating disks are exactly "your company needs you to act." KEEP it. Independent recap of open `action-required` issues, links only; does NOT mirror the inbox (#5103). Brainstorm Open Q#4 RESOLVED: different signals, both kept. |
| "Action needed" mirrors the operator inbox (#5103) | **#5103 does NOT use the label** and its spec **forbids GitHub issues as a surface** ("third-party PII", `specs/archive/…operator-inbox-delegation/spec.md:106`). | Reframed as independent (above). The inbox owns email-triage decisions; section 4 owns infra/ops/CLA decisions. No overlap. |
| Reuse `redact-sentinel.sh` as the digest scrub gate | **MISMATCH (verified):** the sentinel `exit 1`-aborts on `email` (and `ops@jikigai.com` is literally in `expenses.md`), `UUID` (trace ids in PIRs), and `IPv4` (node addrs) — so it would **silently kill the digest on benign first-party content** — AND it **passes named PII** ("Jane Doe at Contoso"). | **Build a TUNED `digest-scrub.sh`** (secrets hard-abort; email aborts UNLESS first-party allowlist; UUID/IPv4 warn-only; grep-error → abort). The named-PII control is **upstream** (summaries-only synthesis). See Architecture. |
| claude-code-action uses one "clean" `GITHUB_TOKEN`, cross-repo read needs no PAT | **Two token contexts** (`2026-05-07-claude-code-action-boundaries…` Insight 3): the action's App-installation token vs the bash-bridge `GH_TOKEN`. A cross-repo `gh` read from inside the action can 403/return-empty under the App token; `\|\| true` would then render "Nothing shipped" on an **auth failure** (false-negative comprehension leak, #3403). | Pass `github_token: ${{ secrets.GITHUB_TOKEN }}` into the action `with:` AND `env: GH_TOKEN: ${{ github.token }}` on the step. Phase-0 probe reproduces the **in-action** topology (not local `gh`). Add an auth-failure failure-mode (empty read ≠ quiet week). |
| `soleur:schedule` generates the workflow | Recurring template **assumes same-repo** (`plugin_marketplaces`→running repo; agent posts to running repo), **can't pass skill args** (date window; :727), **no scrub post-step**, and ships a vestigial `gh label create` step. | Use the template as the **base**; hand-edit: pin `plugin_marketplaces` to `jikig-ai/soleur`, cross-repo checkout, date-window prompt, the scrub post-step (model on the `--once` post-step :546-578), drop the label step. |
| (Substrate) reuse `cron-weekly-release-digest.ts` mechanism | TS Inngest cron — TS catches (`extractModelJson`, quadratic-regex, clock-in-step, pagination) **do NOT transfer** (no JSON-parse seam — the skill IS the model). | Don't import TS-cron catches. Quantified regex only in the bash scrub gate (slice-before-regex applies there). |

## User-Brand Impact

**If this lands broken, the operator experiences:** a silently-missing or malformed weekly digest —
they believe they're caught up on their company when they're not. The digest is brand-critical
precisely because it concentrates **financial + incident + decision** data into one artifact.

**If this leaks, the operator's financial + incident data is exposed via:** (a) a public surface
(resolved by the private-repo substrate); (b) a **secret** in source data flowing into the issue
(resolved by the L3 tuned scrub gate); (c) **named PII** from a PIR body (a customer name) that no
regex catches — resolved **upstream** by summaries-only synthesis (L2); (d) **prompt-injection** from
a read source (a malicious PR title / `action-required` issue body / ledger line / PIR) instructing
Claude to post directly — resolved by removing `gh issue create` from the agent allowlist (only the
post-step posts); (e) the **API key next to model-driven bash** exfiltrated over open egress —
resolved by the narrow allowlist (the containment boundary) + `persist-credentials: false`.

**Brand-survival threshold:** `single-user incident`. → `requires_cpo_signoff: true` (CPO assessed at
brainstorm Phase 0.5). `user-impact-reviewer` fires at PR-review time.

**Load-bearing guardrails (4-layer, fail-closed):**
- **L1 — path scope:** the skill reads ONLY the four named sources; any other file path is out of scope.
- **L2 — summaries-only synthesis (the named-PII + customer-email control):** the incident section is
  built from PIR **frontmatter / title / status ONLY, never the PIR body**; the money section emits
  **amounts + vendor names only**, never the ledger Notes column's contact emails/IPs. This is the
  only real defense against named PII (a regex cannot catch "Jane Doe"). Enforced by SKILL.md + an AC.
- **L3 — tuned fail-closed scrub post-step (`digest-scrub.sh`, GHA `- run:`, NOT in-prompt):** HARD-ABORT
  on secret classes (JWT, stripe/`sk_`-`pk_`-`whsec`-`acct`, github `ghp_`/`gho_`/…, `sk-ant-`, openai
  `sk-`, supabase `sbp_`/`sb_secret`, `env_var=value`, PEM); ABORT on `email` UNLESS the domain is in a
  **first-party allowlist** (`@jikigai.com`); **WARN-only** on UUID / IPv4 (legitimate in prose);
  **grep-error (exit 2) → ABORT** (real fail-closed, not the sentinel's per-pattern `|| true` fail-open).
- **L4 — no durable plaintext copy:** post-step `rm digest.md` after posting; never `actions/upload-artifact`
  the file; `show_full_output` OFF; no `cat`/`echo` of `digest.md` or `$ANTHROPIC_API_KEY` anywhere.

**On L3 abort → positive operator signal (not silent):** the post-step posts a **content-free** notice
issue ("This week's digest was withheld by the safety scrub; a value matched a secret pattern. No data
shown. See run #N.") — zero source-derived content — so a withhold is visible, not a silent absence.

**GDPR / data-minimization (discharges Phase 2.7 — security-sentinel P1-A):** the digest is a NEW
durable copy of personal data in a NEW system (private-repo issues + 90-day Actions logs). Lawful basis
= the same legitimate-interest basis as the source PIRs; the digest inherits the source retention. The
minimization control is L2 (summaries-only); the retention control is L4 (`rm digest.md`, no artifact).
No Art. 33 trigger (the statutory clock lives in the incident skill). No third-party processor beyond
Anthropic (same sub-processor posture as every other claude-code-action run; disclosed by precedent).

## Background — what this protects (do not weaken)

The community digest (#5080) protects *outbound* exposure (no private content in a public post); this
**inverts** the threat model — it deliberately aggregates private content, so the load-bearing question
is *"can this aggregated private data reach a non-private surface?"* Every guardrail above answers "no."

## Architecture

```
[Private repo: jikig-ai/operator-digest]  weekly Fri cron + workflow_dispatch
  workflow (PRIVATE logs):
   1. actions/checkout repository: jikig-ai/soleur  (PUBLIC, fetch-depth: 0, persist-credentials: false)
        → KB + git history + plugins/soleur/skills/.../digest-scrub.sh, in $GITHUB_WORKSPACE
   2. claude-code-action@<sha>  (plugin_marketplaces pinned to jikig-ai/soleur; plugins: soleur@soleur)
        permissions: contents: read, issues: write, id-token: write
        with: anthropic_api_key=${{secrets.ANTHROPIC_API_KEY}}, github_token=${{secrets.GITHUB_TOKEN}}
        env: GH_TOKEN=${{github.token}}   ;  show_full_output: OFF
        --allowedTools  Write,Read,Glob,Grep,Bash(gh pr list:*),Bash(gh issue list:*),Bash(git log:*)
            ^ NO Bash(gh issue create) — the agent CANNOT post (closes the prompt-injection bypass)
        prompt: Run /soleur:operator-digest → reads 4 sources, writes $GITHUB_WORKSPACE/digest.md, STOPS
   3. POST-STEP (GHA run, secrets.GITHUB_TOKEN):  bash $GITHUB_WORKSPACE/.../digest-scrub.sh "$GITHUB_WORKSPACE/digest.md"
        → secret hit / non-allowlisted email / grep-error → exit≠0 → post CONTENT-FREE withheld-notice → done
   4. POST-STEP:  gh issue create -R jikig-ai/operator-digest --title "Digest: <ISO-week>" --body-file digest.md
        (body names the prior week's issue: "Last week: #N" — in-band liveness loop)
   5. POST-STEP:  rm -f "$GITHUB_WORKSPACE/digest.md"   (no durable plaintext copy)
   6. on any failed step → GitHub Actions failure email to the repo owner (operator)
```

**Token model:** the private repo's `secrets.GITHUB_TOKEN` reads public soleur (public → no grant) and
writes issues to its own repo (`issues: write`). The only secret is `ANTHROPIC_API_KEY`. Both token
contexts are aligned (`github_token` in `with:` + `env: GH_TOKEN`) so the in-action cross-repo read does
not silently 403 (#3403). No cross-repo PAT.

**Source-of-truth for review:** the workflow YAML + `digest-scrub.sh` + the provisioning script are
committed **in soleur** (reviewed in THIS PR) and installed into the private repo by the bootstrap
script — the brand-critical workflow gets multi-agent review here even though it executes elsewhere.

**Section data sources:** (1) `gh pr list -R jikig-ai/soleur --search "merged:>=<date>"` → Claude
rewrites to business consequence (no PR#/paths). (2) `git log --since="7 days ago" -p --
knowledge-base/operations/expenses.md` → amounts + vendor-name deltas only. (3) `post-mortems/*.md`
**frontmatter/title/status** with `status: resolved|closed` + filename date in window → one line + link,
NEVER body. (4) `gh issue list -R jikig-ai/soleur --label action-required --state open` → recap + links,
no mutation.

## Files to Create (in public soleur — THIS PR)

- **`plugins/soleur/skills/operator-digest/SKILL.md`** — the skill. Markdown-heading style (match
  `changelog`/`community`/`schedule`). Headless. Instructs Claude to read the 4 sources, synthesize each
  section in a calm chief-of-staff register (every line states a business consequence or an action, or
  is cut), apply L1+L2 (incident = frontmatter/title/status only; money = amounts+vendor-names only;
  never echo emails/IPs/raw records), apply the per-section deterministic fallback (empty → "Nothing
  shipped this week." labeled line, NEVER blank; **even an all-empty week still posts**), reference the
  prior week's issue, write `$GITHUB_WORKSPACE/digest.md`, and **STOP without posting**. Description ≤30
  words, third-person, routing-only.
- **`plugins/soleur/skills/operator-digest/scripts/digest-scrub.sh`** — the TUNED fail-closed gate
  (L3 spec above). Distinct from `redact-sentinel.sh` (which over-aborts on prose + misses named PII).
- **`plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml`** — the workflow TEMPLATE
  (inert in soleur; installed into the private repo). Encodes steps 1-6; `id-token: write`,
  `show_full_output` OFF, the narrowed allowlist (no `gh issue create`), SHA-pinned actions,
  `persist-credentials: false`, `workflow_dispatch:`.
- **`plugins/soleur/skills/operator-digest/scripts/provision-operator-digest-repo.sh`** — idempotent
  bootstrap (multi-step ⇒ a script, not a checklist): `gh repo create jikig-ai/operator-digest --private`
  (no-op if exists) → set `ANTHROPIC_API_KEY` via **`doppler secrets get ANTHROPIC_API_KEY -p soleur -c
  prd --plain | gh secret set ANTHROPIC_API_KEY -R jikig-ai/operator-digest`** (stdin, never argv; fail
  loud if the Doppler value is empty) → install the workflow into the private repo's `.github/workflows/`
  → `gh workflow enable`.

## Files to Edit (in public soleur — THIS PR)

- **`README.md`** + **`plugins/soleur/README.md`** — `bash scripts/sync-readme-counts.sh` (skill 83→84).
- **`plugins/soleur/test/components.test.ts:15`** — bump `SKILL_DESCRIPTION_WORD_BUDGET` by exactly the
  new description's word count against the **zero-headroom 2009/2009 baseline**, conventional comment
  (5 precedents). Not sibling-trim.
- **`knowledge-base/product/roadmap.md`** — milestone row if applicable.
- **ADR** — `knowledge-base/engineering/architecture/decisions/ADR-NNN-operator-digest-two-repo.md`
  (next free number via `/soleur:architecture create`).

## Files NOT to Edit (scope guards)

- `cron-weekly-release-digest.ts` — community digest; no shared helper/input set/webhook.
- `plugins/soleur/skills/schedule/SKILL.md` — reuse the template; don't modify the generic generator.
- `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` — leave as-is (it's correctly tuned for
  PIRs); the digest gets its own `digest-scrub.sh`.
- `feat-operator-inbox-delegation` (#5103) surfaces — independent; read the label only.
- `plugin.json` / `marketplace.json` version fields (frozen sentinels).

## Implementation Phases

### Phase 0 — Preconditions (probes, no code)
- [ ] `jikig-ai/soleur` still PUBLIC; operator `gh` token can `gh repo create` in `jikig-ai` (org owner).
- [ ] **In-action token probe (NOT local `gh`):** run a throwaway `claude-code-action` job in a private
      scratch repo that does `gh issue list -R jikig-ai/soleur --label action-required` via the Bash
      bridge, with `github_token`+`env GH_TOKEN` set, and assert a non-empty/authorized result — proving
      the cross-repo read works under the in-action token topology (a local `gh` proves nothing — #3403).
- [ ] Enumerate current open `action-required` issues (`gh issue list -R jikig-ai/soleur --label
      action-required --state open`) so /work sees real signal density.
- [ ] Confirm claude-code-action latest pin (in-repo `v1.0.101`; re-check per `model-launch-review`); use the SHA.
- [ ] Measure exact new-description word count; set the `components.test.ts` bump value.

### Phase 1 — Build the skill + tuned scrub gate (soleur)
- [ ] Author `SKILL.md` (4 sections; L1+L2; deterministic fallback; prior-week reference; writes
      `$GITHUB_WORKSPACE/digest.md`; STOPS, does NOT post). Description ≤30 words.
- [ ] RED→GREEN: `digest-scrub.sh` + its test — proves the gate **FIRES** (positive sentinel) on a planted
      secret-shaped token AND on a non-first-party email; **passes** a first-party `@jikigai.com` email +
      a UUID + an IPv4 (warn, not abort); **aborts** on a grep-error input (fail-closed-for-real).
- [ ] RED→GREEN: skill static-contract test — frontmatter, third-person ≤1024-char description, body names
      4 sources + "incident = frontmatter/title/status only, never body" + "write digest.md, do NOT post".
- [ ] Bump `components.test.ts:15`; `bun test plugins/soleur/test/components.test.ts` green.

### Phase 2 — Workflow template + provisioning (soleur; installed post-merge)
- [ ] Author `assets/operator-digest.workflow.yml` from the recurring template, hand-edited per Architecture
      (pin `plugin_marketplaces` to soleur, cross-repo checkout `persist-credentials: false`, `id-token:
      write`, `show_full_output` OFF, narrowed allowlist WITHOUT `gh issue create`, SHA-pinned actions,
      the `digest-scrub.sh` post-step + withheld-notice + `rm digest.md`, `workflow_dispatch:`, drop the
      vestigial label step).
- [ ] RED→GREEN: workflow-lint test — asserts `id-token: write` present, `show_full_output` ≠ `true`,
      `--allowedTools` contains `Write` AND does NOT contain `gh issue create`, the ONLY `gh issue create`
      is a GHA `run:` post-step (not the action), a `digest-scrub.sh` post-step exists OUTSIDE the action,
      `rm` of `digest.md` present, actions SHA-pinned, no `cat`/`echo` of `digest.md` or `ANTHROPIC_API_KEY`.
- [ ] Author `provision-operator-digest-repo.sh` (idempotent; secret via Doppler→stdin; fail-loud-if-empty).
- [ ] RED→GREEN: provision-script test — `gh secret set` reads from stdin (no `--body "$VALUE"` argv leak).

### Phase 3 — Docs & budget
- [ ] `sync-readme-counts.sh`; both READMEs `--check` green. `## Changelog`; `semver:minor`. Author the ADR.

### Phase 4 — Pre-merge verification (local only — `workflow_dispatch` is 404 from a feature branch)
- [ ] Locally produce a sample `digest.md` from the checked-out repo; assert prose quality (not byte-identical
      to a bare `gh pr list` dump; ≥1 sentence-with-verb per non-empty section) + no blank section.
- [ ] Run `digest-scrub.sh` against a sample built from the REAL current `expenses.md` → assert exit 0 (no
      benign first-party false-positive on today's data). Then plant a secret-shaped token → assert abort.

### Phase 5 — Post-merge (operator-authenticated, automated)
- [ ] Run `provision-operator-digest-repo.sh` (creates private repo + Doppler-sourced secret + installs
      + enables the workflow on the default branch — required for `schedule:` to fire).
- [ ] `gh workflow run operator-digest.yml -R jikig-ai/operator-digest` → confirm a private digest issue
      with 4 sections + the scrub post-step ran; conclusion `success`.

## Acceptance Criteria

### Pre-merge (PR)
- AC1 — `operator-digest/SKILL.md` exists; third-person description ≤1024 chars; names all 4 sources;
  instructs "incident from frontmatter/title/status only, never body", "write digest.md, do NOT post",
  "even an all-empty week posts", "reference the prior week's issue".
- AC2 — `components.test.ts` budget bumped by exactly the new description's word count; `bun test
  plugins/soleur/test/components.test.ts` passes.
- AC3 — workflow-lint test passes: `id-token: write` present; `show_full_output` ≠ `true`; `--allowedTools`
  contains `Write` and does NOT contain `gh issue create`; the only `gh issue create` is a GHA `run:`
  post-step; a `digest-scrub.sh` post-step runs OUTSIDE claude-code-action; `rm digest.md` present;
  actions SHA-pinned; `plugin_marketplaces` pinned to `jikig-ai/soleur`; no `cat`/`echo` of `digest.md`
  or `ANTHROPIC_API_KEY` in the YAML.
- AC4 — `digest-scrub.sh` test proves: ABORT (exit 1) on a planted **secret-shaped** token (positive
  sentinel, not secret-absent); ABORT on a non-first-party email; **PASS** a `@jikigai.com` email + a
  UUID + an IPv4; ABORT on a grep-error input.
- AC5 — content-quality: sample `digest.md` is NOT byte-identical to a bare `gh pr list` dump AND each
  non-empty section contains ≥1 sentence with a verb (deterministic heuristic, not human-eyeball).
- AC6 — `grep -nE 'sk_(test\|live)_[A-Za-z0-9]{16,}\|ghp_[A-Za-z0-9]{20,}\|sk-ant-[A-Za-z0-9-]{16,}'`
  across every touched markdown returns 0 (structural placeholders only — push-protection).
- AC7 — both READMEs in sync (`sync-readme-counts.sh --check` exit 0); `semver:minor` + `## Changelog`; ADR present.
- AC8 — `provision-operator-digest-repo.sh`: `gh secret set` reads from stdin (no argv secret); fails loud if
  the Doppler value is empty.

### Post-merge (operator)
- AC9 — `provision-operator-digest-repo.sh` creates `jikig-ai/operator-digest` (private), sets
  `ANTHROPIC_API_KEY` from Doppler, installs + enables the workflow. **Automation: feasible** (gh CLI on the
  operator's authenticated machine; `gh repo create` needs org-owner scope, which the operator has).
- AC10 — `gh workflow run operator-digest.yml -R jikig-ai/operator-digest` produces a private digest issue
  (4 sections, prior-week back-reference); conclusion `success`; the scrub post-step is present in the log.

## Domain Review

**Domains relevant:** Product, Engineering, Legal, Marketing (carry-forward from brainstorm `## Domain
Assessments`; Phase 2.5 carry-forward — no fresh spawn).

### Product (CPO) — sign-off carry-forward
**Status:** reviewed (brainstorm Phase 0.5). **Assessment:** distinct from the community digest; thin
synthesizer reusing existing sources; V1 = built/money/incidents/action-needed; gate *section expansion*
on a read/engagement signal. CPO sign-off satisfied at brainstorm; `requires_cpo_signoff: true`;
`user-impact-reviewer` fires at PR review.

### Engineering (CTO)
**Status:** reviewed. **Assessment:** LLM-as-script; scrub = load-bearing GHA post-step (in-prompt exit
swallowed); agent allowlist has NO `gh issue create` (prompt-injection-bypass closed); two token contexts
aligned; tuned `digest-scrub.sh` (raw redact-sentinel over-aborts + misses named PII); private repo
resolves public-logs leak.

### Legal (CLO)
**Status:** reviewed. **Assessment:** permitted with guardrails — first-party private repo; post-redaction
PIR frontmatter/title only (never body); summaries + links; tuned fail-closed scrub; `rm digest.md` for
minimization; no statutory trigger. (Phase 2.7 GDPR discharged by security-sentinel P1-A — see
User-Brand Impact §GDPR.)

### Marketing (CMO)
**Status:** reviewed. **Assessment:** calm chief-of-staff register (NOT promotional); candid; editorial
rule: every line states a business consequence or an action, or is cut (anti-vanity-report).

### Product/UX Gate
**Tier:** none. **Decision:** N/A — output is a markdown GitHub issue, not an app UI surface (no
page/component/modal/banner/email-template). No `.pen` required (same precedent as #5080). **Pencil
available:** N/A (no UI surface).

## Infrastructure (IaC)

New private repo + Actions secret + workflow — Phase 2.8 fires.

### Resources
- `jikig-ai/operator-digest` — private GitHub repo.
- `ANTHROPIC_API_KEY` — Actions secret (sourced from Doppler `soleur/prd`).
- `.github/workflows/operator-digest.yml` — scheduled workflow (source-of-truth = soleur-committed asset).

### Apply path
**Automated idempotent bootstrap script** (`provision-operator-digest-repo.sh`), run once post-merge on the
operator's authenticated machine (`hr-all-infrastructure-provisioning-servers` + `hr-multi-step-post-merge-bootstrap-script`
satisfied — gh-CLI automation, not a manual dashboard; a script, not a checklist). Heavier alternative:
Terraform `github_repository` + `github_actions_secret` (the `provision-github` tenant pattern) —
**rejected for V1** as disproportionate to one internal repo + one secret.

### Distinctness / drift safeguards
The only sensitive value (`ANTHROPIC_API_KEY`) lives in the private repo's Actions secrets, sourced from
Doppler. The workflow YAML's source-of-truth is the soleur-committed asset; **re-running the bootstrap
script re-installs it** — but nothing *enforces* re-running it (honest limitation). Drift detection: the
weekly discoverability_test (below) additionally diffs the deployed workflow against the committed asset
(`gh api repos/jikig-ai/operator-digest/contents/.github/workflows/operator-digest.yml`) and warns on
divergence. (Not Terraform-grade, but adequate for one workflow at V1.)

### Vendor-tier reality check
GitHub private repos + Actions within the existing org plan; no new paid tier. Anthropic spend: one short
weekly claude-code-action run — negligible.

## Observability

```yaml
liveness_signal:
  what: the weekly digest workflow run in jikig-ai/operator-digest (success = a private issue posted);
        each digest names the prior week's issue ("Last week: #N") as an in-band continuity check
  cadence: weekly (Fri); plus on-demand via workflow_dispatch
  alert_target: GitHub Actions failure email to the repo owner; a missing "Last week" back-reference is the
        operator-visible skipped-week signal
  configured_in: jikig-ai/operator-digest/.github/workflows/operator-digest.yml
error_reporting:
  destination: workflow run conclusion (scrub/post steps are GHA post-steps; their non-zero exit IS the conclusion)
  fail_loud: true
failure_modes:
  - mode: cross-repo read returns empty under in-action App-token denial (#3403)
    detection: a section reads "Nothing shipped" while PRs/issues demonstrably merged that week
    alert_route: github_token+env GH_TOKEN aligned to prevent it; Phase-0 in-action probe; treated as a bug, not a quiet week
  - mode: scrub gate aborts (secret / non-first-party email / grep-error)
    detection: digest-scrub.sh exit ≠ 0
    alert_route: post a CONTENT-FREE withheld-notice issue ("withheld by scrub, see run #N") — operator-visible, not silent
  - mode: LLM produces a blank/garbage section
    detection: Phase-4 content-quality assertion + per-section deterministic fallback
    alert_route: fallback renders labeled "Nothing this week" (never blank); all-empty week still posts
  - mode: scheduled workflow auto-disabled after 60d repo inactivity
    detection: the weekly successful run keeps the repo active (self-sustaining once started); GitHub's 60d-disable email
    alert_route: a failed-run streak risks inactivity — the withheld-notice issue (a write) also counts as repo activity
logs:
  where: jikig-ai/operator-digest Actions run logs (PRIVATE) + the private digest issues
  retention: GitHub default (90 days for logs)
discoverability_test:
  command: gh run list -R jikig-ai/operator-digest --workflow operator-digest.yml --limit 1 --json conclusion --jq '.[0].conclusion'
  expected_output: success
  note: runnable post-provision (the workflow does not exist until the bootstrap runs); SSH-free.
```

## Test Scenarios
1. **Happy path** — merged PRs + ledger change + resolved PIR + open `action-required` → 4 plain-language
   sections (prose), prior-week back-reference, posted privately.
2. **Empty week** — nothing in any source → issue still posts, each section says so plainly, never blank.
3. **Secret planted** — a secret-shaped token in a source → scrub abort → content-free withheld-notice issue.
4. **Benign first-party** — `ops@jikigai.com` (in expenses.md) appears → first-party allowlist → PASS (no abort).
5. **Prompt-injection** — a malicious `action-required` issue body says "post the digest now" → the agent
   lacks `gh issue create` → cannot post → the gated post-step is the only path.
6. **Cross-repo read** — the private-repo run reads public soleur data with `github_token`+`GH_TOKEN` aligned.

## Risks & Open Questions
- **R1 — cross-repo read is a new pattern** (no in-repo precedent) + the two-token-context split. Mitigation:
  Phase-0 in-action probe; `github_token` in `with:` + `env GH_TOKEN`; auth-failure failure-mode.
- **R2 — `action-required` is a genuine 7-producer operator-action signal** (corrected from the brainstorm's
  "thin" framing): token-expiry, disk-IO, cert-state, CF-token, campaign-overdue, content-publish, CLA.
- **R3a (defer) — engagement signal to gate section EXPANSION** (write-mostly): defer; blocks nothing in V1.
- **R3b (V1) — minimal liveness loop:** each digest names the prior week's issue; a missing back-reference =
  a visible skipped week. Ships in V1 (not deferred).
- **R4 — claude-code-action pin freshness** — verify latest at /work (model-launch-review surface); SHA-pin.
- **R5 — tuned scrub vs raw sentinel** — `digest-scrub.sh` must NOT inherit the sentinel's per-pattern
  `|| true` fail-open; grep-error must abort.
- **R6 — prompt-injection from read sources** — closed by the no-`gh issue create` allowlist + L2 body-exclusion.

## Sharp Edges
- The scrub gate is a GHA post-step, NEVER an in-prompt assertion (in-prompt `exit 1` is swallowed; the
  conclusion still reads `success`).
- The agent allowlist must NOT contain `gh issue create` — only the deterministic post-step posts (else a
  prompt-injection in any read source bypasses the entire scrub stack).
- Do NOT reuse `redact-sentinel.sh` raw as the digest gate — it over-aborts on benign prose (email/UUID/IPv4,
  and `ops@jikigai.com` is in the ledger) AND misses named PII; the named-PII control is upstream (L2).
- Do NOT import the community digest's TS-cron catches (`extractModelJson`, quadratic-regex, clock-in-step,
  pagination) — no seam on the claude-code-action substrate.
- The workflow YAML is committed in soleur for review but EXECUTES in the private repo — `/work` must NOT
  place it under soleur's `.github/workflows/` (that would run it in PUBLIC logs).
- A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan Phase 4.6 — this is filled.
