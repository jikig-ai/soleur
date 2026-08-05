---
title: "chore(infra): move the zot pin off v2.1.2 and give it a freshness owner"
date: 2026-08-04
type: chore
issue: 7282
branch: feat-one-shot-7282-zot-pin-bump-cadence
pr: 7283
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(infra): move the zot pin off v2.1.2 and give it a freshness owner

Spec lacks valid `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`apps/web-platform/infra/zot-registry.tf` pins zot to **v2.1.2 (2025-01-17)** on both arches. Upstream is at **v2.1.20 (2026-08-04)** — 18 releases. Since ADR-096's 2026-07-30 amendment zot is the **sole pull path** with no fallback (`model.c4:484` calls the `hetzner -> ghcr` edge a "DEAD EDGE"), so this is an 18-month-old binary on a single point of failure.

Digest-pinning is correct and stays. The defect is that **nothing moves the pin** — the file's only freshness mechanism is a prose comment telling a human to run `crane digest`.

**This PR delivers three of the issue's four scope items in full, and stages the fourth.** The pin bump itself cannot reach production in this PR: three independent, live-verified blockers sit on the host-replace path (§Blockers). Because `zot-registry.tf` resources are `OPERATOR_APPLIED_EXCLUSIONS`, merging the bump is **inert in production by construction** — it is staged, not shipped, and it applies the moment the prerequisites clear. That is stated explicitly, not silently narrowed.

The cadence is the part that makes this not recur: **a cron step detects, a CI gate enforces.** A bi-monthly step on the existing `rule-audit.yml` polls upstream and files one idempotent issue when the pin falls behind; a deterministic offline staleness/coherence test refuses to go green unless a human has re-read the changelog and stamped the provenance sidecar. Neither half works alone — detection with no gate lets the sidecar rot, and a gate with no detector never notices upstream moving.

> **Revised 2026-08-05.** The first draft of this plan built the detection half on Renovate. **Renovate is not installed on this repository** — measured, see §Premise Validation. That inverted the mechanism choice and is corrected throughout; `renovate.json5` is an inert config file and this PR removes it (§Deliverable 6).

## Premise Validation

Every reference the issue cites was probed against live state before this plan was written. Two premises drifted.

| Cited premise | Probe | Verdict |
|---|---|---|
| #7282 open, unstarted | `gh issue view 7282` | **HOLDS.** OPEN, 0 linked PRs, 0 `git log origin/main --grep` hits. |
| Host replace blocked by `out_of_scope=2` | `gh run view 30926215332 --log-failed` | **HOLDS — measured, not inferred.** See §Blockers B1. |
| #7277 / #7278 are prerequisites | `gh issue view 7277 7278` | **HOLDS.** Both OPEN. |
| PR #7279 is OPEN (dispatch brief) | `gh pr view 7279` | **STALE.** `state: MERGED`. Its ADR-096 + recut-runbook edits are already on `main`. |
| "mirror the existing `model-launch-review` shape" (issue scope item 3) | `ls .github/workflows/*model-launch*` | **STALE PREMISE.** No such workflow exists, and the real shape **files an issue, never a PR** — see §Cadence. |
| "fold into the existing renovate/dependabot surface" (issue scope item 3) | `ls .github/dependabot.yml renovate.json5` | **STALE — BOTH HALVES.** See the two rows below. Neither surface can carry this pin. |
| **Renovate is installed and opens digest PRs here** (the first draft's load-bearing premise) | `gh pr list --state all -L 300` grouped by author; `gh issue list --search "Dependency Dashboard"` | **FALSE — MEASURED 2026-08-05.** **Zero** Renovate-authored PRs, all time. **No** Dependency Dashboard issue (`config:recommended` creates one at onboarding). `renovate.json5` exists but the **App was never installed**, so it has never executed. Its `docker:pinDigests` + `helpers:pinGitHubActionDigests` presets would have opened PRs continuously across a repo this size; they opened none. **This inverts the cadence decision** — see §Cadence. |
| Dependabot is the live bot surface | same PR grouping; `find . -name 'dependabot.y*ml'` | **PARTLY.** 17 PRs, author `app/dependabot`, all npm — but there is **no repo `dependabot.yml`** (they are GitHub-native security updates). Dependabot's `docker` ecosystem reads Dockerfiles/compose, **not a Terraform `locals` string**, so it cannot manage this pin either. |
| PRs #4204 / #4213 are "July 2026" fixes in the gap | `gh api repos/project-zot/zot/releases/tags/v2.1.19` | **HOLDS, and resolves the floor:** both ship in **v2.1.19**, not v2.1.18. |

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| Pin cited at `zot-registry.tf:55` (also in `ci-deploy.sh:1095`) | Digests are at `:59`/`:60`; `:55` is mid-comment | Fix the two stale citations to **content anchors** (`local.zot_image_amd64`), per `cq-cite-content-anchor-not-line-number`. Never re-introduce a line number. |
| "`distSpecVersion`, retention-policy shape, and `accessControl` semantics each deserve a check" | All three checked against upstream **source** at tags v2.1.2 vs v2.1.19. All three are safe; `accessControl` is already on the *new* nested shape | Record the analysis in the provenance sidecar (§Deliverable 2), not in prose that will be archived. |
| "Establish a cadence… scheduled workflow… or renovate/dependabot" | A new `.github/workflows/scheduled-*.yml` carrying `schedule:` is **denied by a PreToolUse hook** (`.claude/hooks/new-scheduled-cron-prefer-inngest.sh`) | Add a step to the **existing** `rule-audit.yml` (already on `origin/main`, already cron'd, already `issues: write`), plus a CI age gate. The hook denies *new* `scheduled-*.yml` files; it does not fire on editing an existing workflow. Do **not** write a new scheduled workflow. |
| "Record whether the upgrade resolves #7247" | The deciding datum (the Go panic header) is still unobserved — #7274's `head -c` fix merged 2026-08-04 but no post-fix sample has been read | Define the falsifiable check as a **follow-through**, never an acceptance criterion. Do not claim the bump fixes #7247. |

## Blockers — three independent, live-verified

Verified by me against live state, not taken on the issue's word (`hr-verify-repo-capability-claim-before-assert`).

### B1 — the destroy-guard scores `out_of_scope=2` and has no bypass

Run [30926215332](https://github.com/jikig-ai/soleur/actions/runs/30926215332) (2026-08-04T15:50:55Z, `conclusion=failure`), job `registry_host_replace`:

```
out_of_scope=2 store_destroyed=0 secret_destroyed=0 volume_bad_update=0 server_replaced=1 nic_recreated=1 attachment_recreated=1 firewall_ok=1
registry_host_replace_gate: ABORT — plan is NOT the exact scoped registry-host recreate
```

`Plan: 5 to add, 2 to change, 3 to destroy`. The two out-of-scope changes are named in the same log:

- `# doppler_secret.registry_luks_key will be created`
- `# random_password.registry_luks will be created`

Both are **creates of resources declared in `zot-registry.tf` but absent from prod state** (#6929), pulled into the plan by the server's `depends_on`. Neither is in the gate's 6-member allow-set (`tests/scripts/lib/registry-host-replace-gate.sh`, `def allow: [...]`). The gate's own header forbids the obvious "fix":

> Do NOT "fix" it by widening the allow-set… The abort is the correct outcome, not a false positive.

and

> **NO [ack-destroy] BYPASS**: a destructive prod host recreate is authorized by the menu-ack workflow_dispatch, never a commit trailer.

### B2 — forcing it past B1 makes things *worse*, not neutral

From #7277 verbatim: *"If forced, cloud-init refuses the plaintext volume and the registry goes **permanently dark**."* The boot guard is `findmnt -no SOURCE /var/lib/zot | grep -qx /dev/mapper/registry || FATAL` (`cloud-init-registry.yml`). Creating the LUKS resources makes the *new* host expect `/dev/mapper/registry`; the *live* volume is still plaintext ext4 (#6929 shipped unfired). So B1 is not merely an arithmetic gate — it is guarding a real dark-host outcome.

### B3 — the recreate fails on Hetzner stock regardless

`var.registry_server_type` default is **`cx23`** (`variables.tf`, reverted from cx33 by #6497/#6463 on 2026-07-16). PR #7280's live probe, 2026-08-04, read from `.server_types.available` (never `.supported`):

```
hel1-dc2   cx23 ✗  cpx22 ✓     ← the registry lives here
```

`stock_preflight_gate` catches this. Its own conclusion: *"until #6460's DR remediation lands, 'the plan shows the registry being replaced' is a STOP, not a proceed."*

### What is therefore left out of this PR, and why

**Left out: the production apply.** Not descoped by choice — blocked by B1 (#6929/#7277/#7278), B2 (#6929), and B3 (#6460). The pin bump merges to `main` and sits there. This is delivered as a tracked, automated-when-unblocked follow-up (§Phase 9), **not** as an operator checklist item.

## How merging a staged pin behaves (verified)

`apply-web-platform-infra.yml:1418-1421`, verbatim:

> zot-registry.tf resources are **OPERATOR_APPLIED_EXCLUSIONS** (CTO ruling 2026-07-06) — deliberately NOT in the per-PR `-target=` allow-list, and the per-PR path bridges over SSH to the EXISTING web host so it cannot reprovision the registry host at all.

Consequences, all of which the plan relies on:

1. **Merging cannot apply the bump.** The `on: push` apply job runs a `-target`-scoped apply; every registry address is excluded. Renovate's future PRs inherit this — a merged Renovate bump is equally inert.
2. **No feature flag or commented-out pin is needed.** "Staging" is a property of the existing exclusion, not something to build. Any mechanism invented here would be redundant machinery.
3. **The 12h drift detector will report the pending registry replace.** Run [30936594810](https://github.com/jikig-ai/soleur/actions/runs/30936594810) already emits `##[warning]Drift detected in web-platform`.
   - **UNVERIFIED at plan time:** I could not confirm from that run's log that `hcloud_server.registry` is *already* among the drifted resources (the plan detail is not in the retrievable log body; `grep -c hcloud_server.registry` = 0). PR #7280 asserts *"The replace was ALREADY pending before this change (state ≠ over-cap render)"*, which is sound inference — the live host was provisioned against an older, smaller render — but it is inference, not a measurement I made.
   - **/work MUST measure it** (Phase 0, P4). If the replace is already pending, this PR changes the *content* of a pending replace and adds no new drift-report condition. If it is not, this PR arms one, and the plan must say so in the PR body. Do not assert either until measured.

## Target version — decided, with the deciding evidence

Digests resolved with `crane digest` (crane is installed at `/home/jean/.local/bin/crane`), 2026-08-04:

| tag | published | amd64 | arm64 |
|---|---|---|---|
| v2.1.18 | 2026-06-24 | `sha256:34f18f783037f967dba10df02f9d4086c4d626f5643ef9f5e51e4a4547280a0b` | `sha256:96913b282b93ee7bc415555c14887e81ece9078631f3189c2e8c1fbb5f888af6` |
| v2.1.19 | 2026-08-04T06:46:22Z | `sha256:20c7e718a4bb10e2ab096e804bc0b7450cc1762d6262d40e3016690d6863f8f9` | `sha256:0b0b5627c6a17c10263fd3a09eba76f05a8e6388b724a249e509601e2a098a1e` |
| **v2.1.20** | 2026-08-04T17:51:30Z | **`sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5`** | **`sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6`** |

**Floor is v2.1.19, not v2.1.18.** Both cited panic fixes ship there, per v2.1.19's release body: `fix(meta): avoid panic on malformed cosign signature tag` (#4204) and `fix(meta): guard GetReferrersInfo against a missing referrer entry` (#4213). v2.1.18 contains neither, so it is disqualified by the issue's own safety motivation.

**Decision: v2.1.20.** The entire v2.1.19→v2.1.20 delta is two lines — `chore: bump zui version (#4296)` and `fix(ci): pin zot release ver to v2.1.18 (#4297)`. The zui bump is **inert in this deployment**: the rendered `config.json` has exactly four top-level keys (`distSpecVersion`, `storage`, `http`, `log`) and **no `extensions` block at all**, so zot never serves the UI. The CI pin is upstream-CI-only. So v2.1.20 carries **zero additional runtime surface** over v2.1.19 while being the current release — taking N-1 would buy no soak (they are 11 hours apart, both same-day) and would leave the cadence's first Renovate run opening a bump PR on day one.

**Fallback, recorded:** if v2.1.20 is later withdrawn or found broken, v2.1.19 is the floor and its digests are above. Do not fall back below v2.1.19.

**/work must re-resolve.** Tags are mutable in principle; digest-pinning exists precisely because they are. Phase 0 re-runs `crane digest` for both arches and **fails the phase on any mismatch** with the table above. If a newer release exists by /work time, the target may move **only** with a re-run of the §Config-compatibility analysis against that release — a version bump is not a formality here.

## Config-compatibility analysis — v2.1.2 → v2.1.19/v2.1.20

Done against **upstream source at the tags**, not release notes. Sources fetched from `raw.githubusercontent.com/project-zot/zot/{v2.1.2,v2.1.19}/…`.

The deployed config is written by `cloud-init-registry.yml` at `- path: /etc/zot/config.json`. Anchor on its content, not line numbers.

| Config surface | Deployed shape | v2.1.19 source | Verdict |
|---|---|---|---|
| `distSpecVersion` | `"1.1.0"` | `pkg/cli/server/root.go` › `func updateDistSpecVersion` logs a WARN on mismatch then **overrides** `config.DistSpecVersion = distspec.Version`. It never errors. | **SAFE, cannot fail.** A WARN does not trip the `zot_last_err` error/fatal tiers. |
| `storage.retention` | `{dryRun, delay, policies[{repositories, deleteReferrers, deleteUntagged, keepTags[]}]}` | `type RetentionPolicy` is byte-identical **plus** a new `KeepUntagged *KeepUntaggedPolicy`. `KeepTagsPolicy` unchanged. | **SAFE — purely additive.** #4191's untagged retention is inert here: `isUntaggedRetentionEnabledForPolicy` requires `retentionPolicy.KeepUntagged != nil`, and the deployed config has no `keepUntagged`. `deleteUntagged: true` keeps its old meaning. |
| `http.accessControl` | nested `accessControl.repositories["**"] = {policies[], defaultPolicy: []}` | `type AccessControlConfig { Repositories Repositories \`mapstructure:"repositories"\` … }` | **SAFE — already on the new shape**, not the deprecated flat form. v2.1.19 adds `Groups`, `Metrics`, and CEL `compiledConditions`: all additive/optional. |
| `http.compat` | `["docker2s2"]` | `pkg/compat/compat.go` › `DockerManifestV2SchemaV2 = "docker2s2"` — unchanged | **SAFE.** Load-bearing: zot rejects Docker schema2 pushes without it. |
| `http.auth.htpasswd` | `{path: /etc/zot/htpasswd}`, baked with `htpasswd -Bbn` (bcrypt) | unchanged; v2.1.11 (#3497) only *added* sha256/sha512 alongside bcrypt | **SAFE.** |
| log format | scraper greps `'"level":"(error\|fatal)"\|level:(error\|fatal)\|level=(error\|fatal)'` | v2.1.9 (#3405) migrated zerolog → `log/slog` | **ALREADY ABSORBED** — all three shapes are matched. Phase 0 **asserts** this rather than assuming it. |
| `storage.FastRestart` | absent | new opt-in in v2.1.19, defaults `false`, top-level storage only | **NOT ADOPTED** — explicit non-adoption decision, recorded in the sidecar. Out of scope; a separate change with its own soak. |

**Two version-scoped capability claims in the repo go stale on bump** (`hr-verify-repo-capability-claim-before-assert`). Both must be re-verified or re-scoped in this PR, not carried forward:

1. `cloud-init-registry.yml`, in the config.json rationale block: *"**NO on-boot gc trigger is issued: zot v2.1.2 exposes no sanctioned on-demand gc HTTP endpoint**"* — a claim scoped to v2.1.2 by name.
2. `ci-deploy.sh`, above `_docker_login_failure_class`: *"zot v2.1.2 (the digest at zot-registry.tf:55), with this repo's exact accessControl, **MEASURED**: GET /v2/ answers 200 or 401 — NEVER 403."* This measurement is what makes the `authz_denied` arm a tripwire rather than a live arm, and `ci-deploy.test.sh` says *"The 401 fixture is byte-accurate — reproduced against the pinned zot (v2.1.2)."* v2.1.19's #4165 (`fix(api): align blob, manifest, and referrers handling with OCI conformance`) is exactly the change class that can move a 401 body.

**Neither may be re-asserted from reading upstream source.** Both are *measurements*, and the honest re-verification is to run the pinned image locally with this repo's exact config (Phase 6). `docker` is available. If the measurement cannot be reproduced, the claim is downgraded to `UNMEASURED against v2.1.20` and a tracking issue is filed — never quietly carried.

**Test surface that will react:** `apps/web-platform/infra/registry-boot-guard.test.sh` asserts the config JSON with byte-literal `grep -qF` on fragments (`'"gcInterval": "1h"'`, `'"delay": "2h"'`, `'"gcDelay": "1h"'`, `'"deleteReferrers": false'`, `'"patterns": ["sha256-.*"], "mostRecentlyPushedCount": 50'`). **This plan changes no config JSON**, so those stay green — but any future schema migration reflowing that JSON breaks them even when semantics are preserved. Recorded in the sidecar as a known coupling.

## Byte budget — quantified

The parent asked for the remaining `user_data` headroom against Hetzner's hard 32,768 B cap.

| State | rendered `user_data` (terraform `base64gzip`) | headroom |
|---|---|---|
| `main` today | **34,628 B** | **−1,860 B (OVER CAP)** |
| after PR #7280 (`local.registry_rationale_strip`) | **9,072 B** | **23,696 B** |

**This PR's own byte delta is ~+10 B, and it is the only delta.**

- The digest strings are fixed-length (`sha256:` + 64 hex) — an amd64→amd64 swap is byte-identical.
- Adding the version tag to the reference (`…zot-linux-amd64:v2.1.20@sha256:…`, §Deliverable 1) adds **~10 raw bytes**, and only for the *selected* arch — `local.zot_image` renders one of the two.
- The `zot_image_digest` telemetry field (§Deliverable 5) adds roughly **+200 raw / ~+60 gzipped**.
- Any comment added to `cloud-init-registry.yml` is stripped by #7280's rationale strip *before* measurement, so rationale is free post-#7280 and must not be traded away for bytes.

**Against 23,696 B this is noise. Against today's main it inherits a pre-existing 1,860 B breach** — so **PR #7280 is a de-facto prerequisite for the bump to ever apply**, on top of #7277/#7278/#6929/#6460. That is a fourth blocker in practice, and it is the one most likely to clear first (#7280 is an open draft, not a design problem).

**Acceptance is stated as a delta, not an absolute** (§AC7), so it is measurable on either base and does not silently pass on a pre-#7280 checkout where the absolute number is already failing.

## Sequencing against PR #7280

PR #7280 (`feat-one-shot-7278-registry-restart-lever`, DRAFT/OPEN) edits `zot-registry.tf`. Read, not edited.

**Textual conflict risk is LOW.** #7280 touches (a) a *new* `locals` block after `doppler_secret.zot_push_token`, and (b) the `user_data = base64gzip(templatefile(` line. This PR touches the *first* `locals` block (`zot_image_amd64` / `zot_image_arm64`, ~40 lines above `hcloud_server.registry`) and, for the telemetry field, `cloud-init-registry.yml`. Different hunks in the same file — git merges these.

**Ordering: neither blocks the other.** Merge in whatever order they become ready. Rules:

- Whichever merges second **rebases** and re-runs `zot-image-staleness.test.sh` plus the byte-delta measurement.
- If #7280 merges first, /work re-measures AC7 on the post-#7280 base and records the absolute figure alongside the delta.
- **Do not edit `.worktrees/feat-one-shot-7278-registry-restart-lever`.**

## Cadence — the decision, and why the issue's two options are both partly wrong

### Option A — "mirror the `model-launch-review` shape": a step on `rule-audit.yml` filing one idempotent issue. **CHOSEN.**

There is no `model-launch-review` *workflow*. The shape is a step bolted onto the existing `.github/workflows/rule-audit.yml` (`cron: '0 9 1,15 * *'`), running `audit-models.sh --detect` on an **exit-code contract (rc=10 = drift)**, which files or updates **one idempotent issue**. It opens no PR, and `model-launch-review/SKILL.md` states why verbatim:

> A bot-token PR does not trigger CI or CLA checks, defeating the 'CI-gated' guarantee… **Headless/cron contexts must file an issue (the detection step), not a PR.**

The first draft rejected this because it **files an issue rather than opening a PR**, and the issue's scope item 3 asks for a PR. That rejection was correct only while Renovate was believed available to do the PR half. **Renovate is not installed** (§Premise Validation), so the comparison is no longer "issue-filer vs. first-class App"; it is "issue-filer vs. nothing".

And on the merits, the repo's own documented position now *favours* this shape. `model-launch-review/SKILL.md` argues a bot-token PR is the **weaker** artifact because it triggers neither CI nor CLA. An issue that names the exact remedy, filed idempotently, is the honest headless output — and the human who acts on it opens a real PR that *is* CI-gated and CLA-checked. The issue's "opens a PR" phrasing describes a mechanism, not the outcome it wants; the outcome is *the pin stops silently rotting*, and this delivers that with zero operator setup.

**Two properties make it the right tool here.** It needs **no GitHub App install** — no operator action, per `feedback_never_defer_operator_actions`, whereas adopting Renovate would require the operator to install and configure an App on the org. And `rule-audit.yml` **already exists on `origin/main`** with `cron: '0 9 1,15 * *'` and `permissions: {contents: read, issues: write}`, so the `new-scheduled-cron-prefer-inngest` PreToolUse hook does not fire (it denies *new* `scheduled-*.yml` files) and no permission change is needed.

**One thing changes versus the first draft.** With Renovate gone, nothing else watches upstream, so this step can no longer be a mere offline age gate — it must **poll upstream directly**. See Phase 4b: it compares the pinned version against `gh api repos/project-zot/zot/releases/latest` in addition to running the offline staleness script.

### Option B — Inngest cron + `safeCommitAndPr`. REJECTED as over-built.

`apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` exports `safeCommitAndPr(config: SafeCommitConfig)` with `allowedPaths`, `DEFAULT_MAX_DELETIONS = 10`, and `SYNTHETIC_CHECK_NAMES` (which solves the bot-token/CI-gating objection). Ten cron functions already use it; `cron-content-vendor-drift.ts` is a near-exact structural analogue. It is the sanctioned agentic-PR path and it would work.

**This is the runner-up, and the only option that literally opens a PR.** The first draft rejected it on the premise that "Renovate already does this specific job, is already installed, already runs weekly" — **that premise is false** (§Premise Validation), so the original rejection does not stand and is withdrawn.

It is rejected on **cost against a `single-user incident` change to the sole pull path**: it needs a new Inngest cron function, a Sentry cron monitor (`infra/sentry/cron-monitors.tf`), an `allowedPaths` allowlist, and an upstream-release poller — four new moving parts, each with its own failure mode, versus one step on a workflow that already runs. The PR it would open still cannot merge unattended (the staleness gate reddens until a human stamps the sidecar), so the extra machinery buys a *draft artifact*, not an outcome. Option A reaches the same outcome — a human opens a real, CI-gated PR — with one step.

**Recorded as the explicit upgrade path.** If the issue-filing cadence proves too weak in practice (issues filed and ignored), Option B is the next move and `cron-content-vendor-drift.ts` is the near-exact structural analogue to clone; `SYNTHETIC_CHECK_NAMES` already solves the bot-token CI-gating objection.

### Option C — Renovate `customManagers` + a CI staleness/coherence gate. **REJECTED — Renovate is not installed.**

**This was the first draft's choice, and it was wrong.** The deciding measurement (§Premise Validation, 2026-08-05): **zero** Renovate-authored PRs in this repo's entire history, and **no** Dependency Dashboard issue. `renovate.json5` configures a GitHub App that has never run here.

Had this shipped, the cadence would have been **100% inert and silently so** — a `customManagers` regex evaluated by nobody. Worse, the first draft's own AC5 (`npx renovate --platform=local --dry-run=lookup`) would have **passed**, because a local dry run proves the regex parses, not that any bot executes it in production. That is precisely the *"guard that tested the one case that cannot happen"* shape this plan cites as its own motivating learning — reproduced, at plan level, inside the plan meant to prevent it.

**Adopting Renovate for real is not a substitute.** Installing a GitHub App is an operator action on a non-technical operator (`feedback_never_defer_operator_actions`), and it would put an automerge-capable bot on the sole pull path's binary as its *first* production responsibility. Not the place to onboard it.

The analysis below is **retained verbatim as reference**, because it is correct *conditional on Renovate existing* and would be the required homework for any future adoption — in particular the `default:automergeDigest` hazard, which is the reason casually installing Renovate later would be dangerous rather than free:

- `enabledManagers: ["dockerfile", "github-actions", "custom.regex"]`, with the verbatim comment *"Only manage the three target categories -- suppress npm/Terraform/other auto-detected managers"*. **`custom.regex` is already enabled**, so a `customManagers` entry adds the zot pin **without re-enabling the terraform manager** — the 2022-era suppression decision is untouched, not overridden.
- The config extends `docker:pinDigests`, `default:automergeDigest`, `schedule:weekly`, `platformAutomerge: true`.

**`default:automergeDigest` is a hazard here and must be explicitly disabled for this dep — verified against the resolved config, not inferred.** `renovate.json5`'s three `packageRules` are:

1. `{matchDatasources: ["docker"], matchUpdateTypes: ["digest","pin"], groupName: "docker-digests"}`
2. `{matchManagers: ["github-actions"], matchUpdateTypes: ["digest","pin"], groupName: "github-actions-digests"}`
3. `{matchUpdateTypes: ["major","minor","patch"], automerge: false}`

Two consequences, both load-bearing:

- **A version bump is already safe.** Rule 3 catches `major|minor|patch`, so v2.1.20 → v2.1.21 arrives as a PR for review. Good.
- **A digest-only bump is NOT.** The new manager uses `datasourceTemplate: "docker"`, so its deps match **rule 1** — and rule 1 sets no `automerge`, leaving `default:automergeDigest` (from `extends`) in force. If upstream ever re-pushes a tag to a new digest, the inherited preset would **automerge a digest change to the sole pull path's binary with no human review**. The new `packageRules` entry must therefore set `automerge: false` across **every** update type including `digest` and `pin`. This is the single most important line in the Renovate change.

**The `groupName` is load-bearing for the same reason, and must not be "simplified" away.** Without a distinct group the zot deps join rule 1's shared `docker-digests` branch alongside the node base image. Renovate resolves automerge **per branch**, so an `automerge: false` on one member of a shared branch changes automerge behaviour for the *whole* branch — a side effect well outside this PR's scope, and in the wrong direction (it would stop the node digest automerging, which is working as intended). A distinct `groupName` isolates the zot deps onto their own branch so `automerge: false` binds only them, and it is also what keeps arm64 and amd64 in one PR.

**Why a CI gate is not optional alongside it.** Detection alone lets the pin move while the changelog goes unread and the provenance sidecar goes stale — the "the leader moves, the followers rot" shape recorded in `knowledge-base/project/learnings/2026-07-29-my-guard-tested-the-one-case-that-cannot-happen-in-production.md`:

> For any 'keep in sync' guard, grep the named leader and check `renovate.json5` for whether a bot bumps it.

**For the zot pin there is no leader** — nothing above it is bot-bumped today, and it is a root with nothing to be coherent *with*. So a coherence guard against a sibling is the wrong shape; an **age gate against a committed provenance sidecar** is the right one, and the sidecar↔pin digest assertion then *also* makes coherence checkable. The coupling is the point: **any PR that moves the pin without updating the sidecar goes RED in CI on that very PR**, so the changelog cannot go unread — the analysis is a merge precondition, not an intention.

**That applies with more force now that a human opens the PR, not a bot.** The gate was originally justified as a check *on the bot*; with the cadence filing an issue instead, the gate is the only thing standing between "someone bumped the digest because an issue told them to" and a schema break on the sole pull path.

The enforcement precedent is `apps/web-platform/infra/cosign-trusted-root-staleness.test.sh` — `MAX_AGE_DAYS` constant, capture date read from a **committed sidecar** (`cosign-trusted-root.provenance.md`) so the check is deterministic and offline, sha256 drift assertion, future-date guard, unparseable-date → FAIL, and it **fails CI rather than warning**. It also survives the failure mode a cron cannot: GitHub disables `schedule:` after 60 days of repository inactivity, and this repo has already been bitten (`workspaces-luks-verify.yml`: *"on 2026-05-26 it dropped a scheduled run outright"*).

#### The gate needs TWO triggers, because CI registration alone does not give it one

**Self-caught defect in the first draft of this plan.** `.github/workflows/infra-validation.yml` is `on: pull_request` with a **`paths:` filter** (`apps/*/infra/**`, `infra/**`, plus named workflows/scripts). Registering the gate there means:

- **Coherence assertions fire exactly when needed.** Any PR that touches `zot-registry.tf` or the sidecar is under `apps/*/infra/**`, so every bump PR runs the gate. This half is precise.
- **The age assertion does NOT fire on a non-infra PR.** The first draft claimed "RED in CI on the next PR after the threshold" — that is **false**. It is "RED on the next *infra-touching* PR." If Renovate dies and nobody touches infra for months, the pin ages silently — which is the exact #7282 recurrence this plan exists to prevent.

So the gate gets a second, time-based trigger: **a step on the existing `.github/workflows/rule-audit.yml`** (`cron: '0 9 1,15 * *'`, already `permissions: {contents: read, issues: write}`), cloned from its `- name: Detect model drift` step — exit-code contract, then find-or-update **one idempotent issue** via `gh issue list --label <label> --state open --json number --jq '.[0].number // empty'`.

This is the **correct** reading of the issue's "mirror the `model-launch-review` shape": that shape *is* a step bolted onto `rule-audit.yml` filing one idempotent issue. It is used here for the half it is actually good at — time-based detection with no PR to hang a check on — and, per Phase 4b-ii, extended with a live upstream poll so that "upstream moved" is detected too. The first draft assigned that second half to Renovate; with Renovate absent, the same cron step carries both, which is why 4b-ii is a *new* requirement rather than a restatement. Because `rule-audit.yml` already exists on `origin/main`, the `new-scheduled-cron-prefer-inngest` hook does not fire — editing an existing scheduled workflow is a soft warn, not a denial.

**Three triggers, three distinct conditions, no redundancy:**

| Trigger | Fires when | Mechanism | Output |
|---|---|---|---|
| `rule-audit.yml` (1st + 15th) | **upstream moves** | **live** `gh api repos/project-zot/zot/releases/latest` vs. the pinned version | one idempotent `zot-pin-drift` issue |
| `infra-validation.yml` (per-PR) | **someone touches the pin** | offline staleness test, **arch-keyed** coherence assertions | RED check on that PR |
| `rule-audit.yml` (1st + 15th) | **time passes** — sidecar ages past `MAX_AGE_DAYS` even if upstream is quiet | offline staleness script, exit-code contract | the same idempotent issue |

Bi-monthly against `MAX_AGE_DAYS=90` gives ~6 firings before the threshold, so the backstop is not itself a single point of failure.

**The upstream poll and the age gate are genuinely different failures, and both are needed.** The poll catches "upstream released and we are behind" within ~15 days. The age gate catches "the poll itself broke" — a revoked token, a GitHub API shape change, an upstream repo rename — because it needs no network and reddens on the sidecar's own recorded date. Wiring only the poll would rebuild the single point of failure this plan exists to remove; wiring only the age gate would leave a fresh-looking sidecar that is 18 releases behind, which is exactly today's #7282 state.

**Why the poll lives on a cron and not in `infra-validation.yml`:** a network call in a per-PR gate reddens CI on upstream's outage. The offline script is the PR-blocking gate; the networked poll only ever files an issue.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-096** (`…/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`) with a **"Pin freshness"** clause. No new ADR: the decision is registry-scoped, and ADR-096 is where the sole-pull-path criticality already lives (its 2026-07-30 amendment is what makes an 18-release gap load-bearing rather than cosmetic).

The amendment records: (a) the pin has a **named freshness owner** (the `rule-audit.yml` upstream-poll step) and a **named enforcement gate** (`zot-image-staleness.test.sh`); (a-ii) **`renovate.json5` was removed, with the measurement that justified it** — zero Renovate PRs ever, no Dependency Dashboard — so a future reader does not re-add it believing it once worked, and a note that any future Renovate adoption must first neutralise `default:automergeDigest`, which would otherwise automerge the sole pull path's binary; (b) **nothing auto-writes the pin** — the cadence files an issue and a human opens the CI-gated PR; (c) the reference form is `name:vX.Y.Z@sha256:…` so the version is machine-readable and `crane digest <tag>` is a live coherence check; (d) v2.1.20 is the target and v2.1.19 the floor, with the #4204/#4213 reason; (e) the two version-scoped capability claims and their re-verification status.

Ordinal note: this is an **amendment**, so no new ordinal is claimed and `/ship`'s ADR-Ordinal Collision Gate has nothing to re-derive.

### C4 views

All three of `model.c4`, `views.c4`, `spec.c4` were read (not grepped for "zot"). The enumeration below is the C4 completeness mandate's output — external actors, external systems, containers/data stores, and access relationships — and it found **three genuine gaps plus two false descriptions**. `spec.c4` needs no change (its zot comment at the `system` styling block is still accurate).

| Category | Item | Modeled today? | Action |
|---|---|---|---|
| External system | **`ghcr.io/project-zot` — the PUBLIC upstream registry the registry host pulls its OWN binary from at boot** | **NO.** The `ghcr` element (`model.c4`) is scoped to *our private* `ghcr.io/jikig-ai/*` packages and the `hetzner -> ghcr` edge is marked DEAD. The upstream public pull is a **live** edge and is unmodeled. | **ADD** element (`#external`) + edge `zotRegistry -> projectZot` describing the bootstrap paradox (`zot-registry.tf`: *"Pulled from the PUBLIC upstream registry at boot — NEVER from our own zot"*), digest-pinned, and its freshness owner is the `rule-audit.yml` upstream poll (internal), not a bot. |
| External system | **Renovate** (GitHub App writing PRs to this repo) | **NO.** Zero hits across all three `.c4` files. | **DO NOT ADD — correctly absent.** The first draft added it, on the premise that it "already writes PRs today". **It does not** (§Premise Validation): zero Renovate PRs, ever. The C4 was right and the plan was wrong. Adding the element would have drawn a **trust boundary that does not exist** into the architecture diagram — a worse defect than the omission it purported to fix, because a reader would then treat the pin as bot-managed. The real freshness owner is internal (`rule-audit.yml`), so it needs no external element. |
| Container / access relationship | `zotRegistry` description | Present, but **carries two false claims** | **FIX** (both pre-existing, both one-line, both in a description this PR is already editing — `rf-review-finding-default-fix-inline`): it says the host is **"cx33, 4 vCPU / 8 GB"** — `var.registry_server_type` default is **`cx23`** (2 vCPU / 4 GB), reverted by #6497/#6463 on 2026-07-16, and `model.c4` **contradicts itself** by correctly listing "soleur-registry (cx23)" in its own DR-gap enumeration. It also says **"an ADR-062 `--memory=7168m` cap"** — the cap is derived as `memory × 1024 − 1024`, i.e. **3072m** on a 4 GB type (`variables.tf` states this explicitly). **ADD** the running zot version + its freshness owner. |
| External human actor | none | — | No new human actor, and no new external system: the freshness owner is an internal workflow step. |
| Views | `views.c4` element enumerations | — | **ADD `projectZot`** to the **context** and **containers** `include` lists, or it will not render. **`views.c4` has THREE `include` enumerations, not two** — context, containers, and the L3 *components of platform.plugin*; `projectZot` does **not** belong in the L3 plugin view. No `renovate` element is added (row above). A `view include` naming an undefined element fails `apps/web-platform/test/c4-render.test.ts`, not `tsc`. |

### Sequencing

No sequencing deferral — the ADR amendment and the C4 edits describe the state this PR ships (the pin has an owner, the reference form changed), not a future state. The *apply* is separately tracked and does not change any C4 relationship.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/zot-registry.tf` **only**, and only inside the existing first `locals` block:

- `zot_image_arm64`, `zot_image_amd64` — new digests, and the reference form gains an explicit version tag.
- The surrounding comment block — replace the "DIGEST-PINNED, v2.1.2" prose and the manual `crane digest` instruction with a pointer to the sidecar + the `rule-audit.yml` poll step (the comment is currently the *entire* freshness mechanism, and a prose instruction to a human is exactly what let the pin sit 18 releases behind). It must not claim a bot manages the pin — none does.

No new provider, no new provider version, no new `variable`, no new resource, no new sensitive value, no `TF_VAR_*`. `hr-tf-variable-no-operator-mint-default` does not fire.

### Apply path

**(d) — deliberately none in this PR.** The sanctioned reprovision path is the guarded `apply_target=registry-host-replace` dispatch, and it is blocked by B1/B2/B3. Merging is inert by the `OPERATOR_APPLIED_EXCLUSIONS` contract.

Expected blast radius **when it eventually applies**: full `hcloud_server.registry` destroy-then-create, minutes of registry downtime on the sole pull path, zot OCI store volume preserved by the gate's `store_destroyed==0` assertion.

### Distinctness / drift safeguards

- `zot-registry.tf` is excluded from the per-PR `-target=` allow-list — this is the mechanism that makes staging safe, and it must not be "improved".
- `hcloud_server.registry` carries **no** `lifecycle.ignore_changes = [user_data]`, by design (*"that replace is the intended replace-to-reprovision path"*). This plan does **not** add one — doing so would defeat the reprovision path for a cosmetic drift-report win.
- The drift detector will surface the pending replace; §Phase 0 P4 measures whether it already does.
- No secret enters `terraform.tfstate` from this change.

### Vendor-tier reality check

No vendor tier, and **no new vendor relationship is created** — the cadence runs on GitHub Actions minutes this repo already consumes, authenticated by the built-in `GITHUB_TOKEN`. `wg-record-recurring-vendor-expense-before-ready` does not fire. (The first draft asserted "Renovate is already installed and free"; it is not installed — §Premise Validation.) The relevant *stock* reality check is B3.

## Encryption Posture

Detection fires on `.tf` + `cloud-init-*.yml`. **No new store and no new connection** — this section records the **unchanged** posture because its plaintext-exception is what blocks the plan.

```yaml
at_rest:
  - store: hcloud_volume.registry (zot OCI store, 60 GB, hel1)
    mechanism: plaintext-exception   # code-declared LUKS, live plaintext ext4
    evidence: "hcloud_volume.registry declared RAW (no `format`); cloud-init-registry.yml
               luksFormat/luksOpen → /dev/mapper/registry, keyed by random_password.registry_luks
               via doppler_secret.registry_luks_key. Both TF resources are ABSENT FROM STATE
               (run 30926215332, out_of_scope=2), so the live device is still plaintext."
    defends_against: "nothing today — the declared posture is not the live one"
    does_not_defend: "Hetzner-side volume snapshot/seizure; a detached-volume read"
    disclosed_as: "encryption-posture-ledger.json + model.c4 zotRegistry (CODE-DECLARED / LIVE-PENDING)"
    live_verification: "blocked — same host-replace path this plan is blocked on"
in_transit:
  - connection: web hosts / CI → zot, 10.0.1.30:5000
    tls: false
    cert_verification: off        # no TLS at all; plain HTTP on the private net
    does_not_defend: "an on-private-network attacker reading or altering blob bytes in flight"
    disclosed_as: "ADR-096 + model.c4 (`Plain-HTTP on the private net (integrity via cosign
                   digest-pinning, not TLS)`); deny-all-public firewall is the boundary"
exception:
  justification: "Both are pre-existing ADR-096/#6929 postures. This plan neither creates nor
                  widens them; it is BLOCKED BY the at-rest one. Integrity on the pull path
                  comes from cosign digest-pinning verified offline, not from transport TLS."
  tracking_issue: "#6929 (LUKS recut, unfired) / #7277 (recut gate has no PASS condition)"
  reevaluate_when: "the registry-host-replace or registry-luks-recut path is unblocked"
  expires_on: "re-evaluated with #6929; this PR must not extend the exception's scope"
```

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_ZOT_DISK (5-min, Better Stack Logs source 2457081) — gains a NEW
         `zot_image_digest` field so the RUNNING image is readable off-host.
         Plus the existing 60s zot-liveness-heartbeat.timer and 900s disk beat."
  cadence: "5 min (SOLEUR_ZOT_DISK) / 60 s (liveness beat)"
  alert_target: "Better Stack heartbeats (absence) + scheduled-zot-restart-loop.yml (*/30)"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml (LINE= assembly, and the
                  zot-liveness-heartbeat.timer unit)"
error_reporting:
  destination: "Better Stack Logs (zot_last_err + zot_last_err_src, 3 ranked tiers) and
                Sentry via the cloud-init boot fatal-emit trap (model.c4 hetzner -> sentry)"
  fail_loud: true
failure_modes:
  - mode: "The pin is bumped in the repo but production still runs v2.1.2 (the EXPECTED steady
           state until B1-B3 clear). Today this is INVISIBLE: nothing in telemetry reports
           which image is running."
    detection: "`zot_image_digest` in SOLEUR_ZOT_DISK compared against local.zot_image_* in
                zot-registry.tf. This is the ONLY off-host way to answer 'did the bump land'."
    alert_route: "the apply-tracking issue (Phase 9) carries the exact betterstack-query.sh
                  invocation; no dashboard eyeballing (hr-no-dashboard-eyeball-pull-data-yourself)"
  - mode: "v2.1.20 introduces a fatal on this exact config → crash loop, sole pull path dark"
    detection: "zot_last_err_src=panic|error + a zot_restarts delta in SOLEUR_ZOT_DISK.
                The scraper's grep already covers slog AND zerolog level shapes, so the
                v2.1.9 log migration cannot blind it (asserted in Phase 0, not assumed)."
    alert_route: "scheduled-zot-restart-loop.yml (*/30, Better Stack log query → issue)"
  - mode: "A bump lands ONE arch only (upstream publishes arm64 late), or the two digests
           are SWAPPED between arches — the swap boots an arm64 binary on an amd64 host"
    detection: "zot-image-staleness.test.sh checks 2/3/4/5 — arch-keyed pin form, cross-arch
                version coherence, cross-arch digest DISTINCTNESS, and arch-keyed sidecar
                equality. Set-membership formulations pass a swap; these do not."
    alert_route: "RED on that PR, in infra-validation.yml"
  - mode: "The pin is bumped and the provenance sidecar left stale — the changelog is
           never read and the analysis never redone"
    detection: "zot-image-staleness.test.sh sidecar↔tf digest-coherence assertion"
    alert_route: "RED on that PR — it cannot merge until the sidecar is stamped"
  - mode: "Renovate is removed/disabled and the pin silently ages again (the #7282 recurrence)"
    detection: "zot-image-staleness.test.sh MAX_AGE_DAYS gate against the sidecar capture date"
    alert_route: "TWO triggers, because infra-validation.yml carries a `paths:` filter and
                  therefore cannot fire on a non-infra PR: (1) RED on the next infra-touching
                  PR; (2) an idempotent `zot-pin-drift` issue from the rule-audit.yml step
                  (1st + 15th), which is independent of PR cadence. Messages are runbook lines."
logs:
  where: "Better Stack Logs source 2457081 (SOLEUR_ZOT_DISK); host journald (the container
          runs --log-driver journald)"
  retention: "Better Stack plan retention; journald persistent (terraform_data.journald_persistent)"
discoverability_test:
  command: |
    # 1. offline, deterministic, no network, no ssh:
    bash apps/web-platform/infra/zot-image-staleness.test.sh
    # 2. which image is production ACTUALLY running (no ssh):
    doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
      --since 1h --grep SOLEUR_ZOT_DISK | grep -o 'zot_image_digest=[^ ]*' | sort -u
  expected_output: |
    1. "RESULT: N passed, 0 failed"
    2. Pre-apply (expected until B1-B3 clear): the v2.1.2 digest 073f30d9… (amd64).
       Post-apply: 95a837a0… . Divergence between (2) and the repo pin is the
       staged-not-applied state, and it is now MEASURABLE rather than assumed.
```

**No `ssh` verb appears in any command above** (`hr-no-ssh-fallback-in-runbooks`). The registry host has no SSH ingress at all — the tunnel's `ssh.` route reaches web-1, not the registry (#7278) — which is precisely why the `zot_image_digest` field is load-bearing rather than a nicety: without it, "is the new zot running?" is unanswerable by any means available to this project.

### Affected-surface observability (2.9.2)

The registry host is a **blind execution surface**: deny-all-public firewall, no SSH, no shell. Phase 5 satisfies the in-surface requirement — `zot_image_digest` is emitted **from the host itself**, by the host's own probe, and it discriminates the competing hypotheses for "the deploy still fails after the bump" in one event: `zot_image_digest` (which binary) × `zot_last_err_src` (panic vs error vs warn vs fallback) × `zot_restarts` (looping vs stable) × `exit_code`. A host-side gate cannot observe any of these.

## User-Brand Impact

**If this lands broken, the user experiences:** the sole pull path goes dark on the next registry reprovision. `cloud-init-registry.yml`'s readiness loop never sees `/v2/` answer, the host boots without a serving zot, and **every production deploy fails at image pull** — plus any web host replaced in that window cannot boot at all. The concrete artifact is a stalled `Web Platform Release` run and a production `build_sha` frozen behind main. This is not hypothetical: #7247 is the same failure shape, measured at 22 hours and 6 blocked releases.

**If this leaks, the user's workflow is exposed via:** a wrong or hostile digest on the sole pull path. Every image the fleet runs would transit a registry binary nobody verified. The mitigations are the reason `automerge: false` is the load-bearing line of the Renovate change: digest pinning + human review + the sidecar's recorded `crane digest` provenance. No user PII is touched by this change.

**Brand-survival threshold:** `single-user incident`.

Consequences, per the tiered sign-off model: CPO sign-off is required at plan time (`requires_cpo_signoff: true` in frontmatter); `user-impact-reviewer` is invoked at review time; plan-review escalates to the 5-agent panel (+`architecture-strategist`, +`spec-flow-analyzer`).

## Domain Review

**Domains relevant:** Engineering.

### Engineering (CTO)

**Status:** reviewed (inline — infrastructure/tooling change, no cross-domain surface).
**Assessment:** The load-bearing engineering judgements are (a) *detection and enforcement are separate mechanisms and both are required* — Renovate alone rots the sidecar, a gate alone never notices upstream; (b) *`default:automergeDigest` must be explicitly overridden*, or the cadence itself becomes an unreviewed write path onto the sole pull path; (c) *the pin bump must not invent a staging mechanism* — `OPERATOR_APPLIED_EXCLUSIONS` already provides one, and adding a flag would be redundant machinery guarding a property the repo already has; (d) *the version-scoped `MEASURED` claims in `ci-deploy.sh` must be re-measured, not re-reasoned* — they underpin a live failure-classification arm.

### Product/UX Gate

Not applicable. The mechanical UI-surface override does **not** fire: `## Files to Create` and `## Files to Edit` contain zero paths matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, and no UI-surface term. Product = **NONE**.

**GDPR / compliance (2.7):** skipped. No schema, migration, auth flow, API route, or `.sql` file; no new processing activity; no LLM/external-API processing of operator data; no new artifact distribution surface. None of triggers (a)–(d) fire.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` returned no issue whose body names `apps/web-platform/infra/zot-registry.tf`, `renovate.json5`, `apps/web-platform/infra/cloud-init-registry.yml`, `apps/web-platform/infra/ci-deploy.sh`, or `model.c4`.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/infra/zot-image.provenance.md` | The provenance sidecar. Records target version, both digests, the `crane digest` capture date (UTC), the config-compatibility table, the non-adoption decisions, and the known `registry-boot-guard.test.sh` coupling. This is the artifact the age gate reads — mirrors `cosign-trusted-root.provenance.md`. |
| `apps/web-platform/infra/zot-image-staleness.test.sh` | The enforcement gate. Deterministic, offline, fails CI. Clone of `cosign-trusted-root-staleness.test.sh`'s shape. |
| `apps/web-platform/infra/registry-userdata-budget.sh` | Makes AC7 runnable. Renders the registry `user_data` via `templatefile()`/`base64gzip()` in an **empty scratch dir** with stub values of matching shape — both are terraform builtins, so this needs **no provider, no S3 backend, and no credentials**, and never touches state. Modelled on the existing `git-data-userdata-budget.sh`, whose header documents exactly this technique. Without it AC7 is an operator-credentialed step wearing a pre-merge badge: the real root's registry `templatefile()` map consumes `hcloud_volume.registry.id`, `doppler_service_token.registry.key`, and two `betteruptime_heartbeat` URLs, so measuring on it would require Doppler `prd_terraform` and be unrunnable on a fork PR. |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/zot-registry.tf` | `zot_image_amd64` / `zot_image_arm64` → v2.1.20 tag+digest form; rewrite the surrounding freshness comment to point at the sidecar + the `rule-audit.yml` poll step. |
| `renovate.json5` | **DELETE** (§Phase 5). Configures a GitHub App that has never run against this repo; it is the false premise that produced the first draft's dead cadence. |
| `apps/web-platform/infra/cloud-init-registry.yml` | Add `zot_image_digest` to the `SOLEUR_ZOT_DISK` `LINE=` assembly + its derivation; re-scope the `"zot v2.1.2 exposes no sanctioned on-demand gc HTTP endpoint"` claim. |
| `apps/web-platform/infra/ci-deploy.sh` | Re-scope the `zot v2.1.2 … MEASURED: GET /v2/ answers 200 or 401 — NEVER 403` block to the measured version; replace the stale `zot-registry.tf:55` citation with a content anchor. |
| `apps/web-platform/infra/ci-deploy.test.sh` | Same: the `"reproduced against the pinned zot (v2.1.2)"` fixture comment. |
| `.github/workflows/infra-validation.yml` | Register `zot-image-staleness.test.sh` (sibling of the existing `cosign-trusted-root-staleness.test.sh` step) — the per-PR coherence trigger. |
| `.github/workflows/rule-audit.yml` | Add `- name: Detect zot pin staleness`, cloned from `- name: Detect model drift` — the time-based trigger. No permission change; the job already has `issues: write`. |
| `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` | "Pin freshness" amendment. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Add the `projectZot` element and its edge (**no `renovate` element** — it would model a bot that does not run here); fix `zotRegistry`'s cx33→cx23 and 7168m→3072m; add the pin + freshness owner. |
| `knowledge-base/engineering/architecture/diagrams/views.c4` | Add `projectZot` to the **context** and **containers** `include` enumerations (the file has three; not the L3 plugin view). |

## Implementation Phases

### Phase 0 — Preconditions (read-only, no writes)

- **P1.** Re-run `crane digest ghcr.io/project-zot/zot-linux-{amd64,arm64}:v2.1.20`. **FAIL the phase** on any mismatch with the §Target-version table. Also re-list `gh api repos/project-zot/zot/releases` — if a release newer than v2.1.20 exists, re-run the §Config-compatibility analysis against it before moving the target.
- **P2.** Assert the log-scraper claim rather than assuming it: `grep -n 'level=(error|fatal)' apps/web-platform/infra/cloud-init-registry.yml` must show all three level shapes in one alternation.
- **P3.** Re-read `apps/web-platform/infra/zot-registry.tf` in full (`hr-always-read-a-file-before-editing-it`) and confirm the digests still sit in the first `locals` block, unchanged from the plan's quoted text.
- **P4.** **Measure** whether the drift detector already reports a pending `hcloud_server.registry` replace (see §How merging a staged pin behaves). Record the answer verbatim in the PR body. Do not assert either way from inference.
- **P5.** `gh pr view 7280 --json state,mergedAt` — record whether #7280 has landed; it determines which base AC7 is measured on.

### Phase 1 — RED: the staleness/coherence gate

Write `apps/web-platform/infra/zot-image-staleness.test.sh` **before** the sidecar and before the pin bump (`cq-write-failing-tests-before`). It must fail now, for the right reasons.

Shape, cloned from `cosign-trusted-root-staleness.test.sh` (read it first — adopt its `assert`/`PASS`/`FAIL` harness and its `[[ "$FAIL" -eq 0 ]]` terminal contract verbatim rather than re-deriving):

1. **Files present** — `zot-registry.tf` and `zot-image.provenance.md`.
2. **Pin form, per arch, arch-keyed.** For **each** arch independently: the value of `zot_image_<arch>` matches `ghcr\.io/project-zot/zot-linux-<that same arch>:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}` and matches **exactly once** (`n -eq 1`, the decoy-in-a-comment guard from `apps/web-platform/scripts/lib/in-image-copy-src.test.sh` check 9 — a commented-out pin must not satisfy the assertion).
   **The arch in the local's NAME must equal the arch in its VALUE.** Do **not** implement this as one alternation (`(amd64|arm64)`) counted across the file: an alternation is satisfied by two well-formed lines regardless of which arch each one names, so `zot_image_amd64 = …zot-linux-arm64…` passes it.
3. **Cross-arch version coherence** — the tag in `zot_image_amd64` equals the tag in `zot_image_arm64`. Catches a half-landed bump where only one arch moved.
4. **Cross-arch digest DISTINCTNESS** — `zot_image_amd64`'s digest **must not equal** `zot_image_arm64`'s. Two arches never share a manifest digest, so equality means one value was pasted into both slots.
5. **Sidecar↔pin coherence, arch-keyed.** `tf_amd64_digest == sidecar_amd64_digest` **and** `tf_arm64_digest == sidecar_arm64_digest`, as two separate assertions — **not** set membership over the two digests. Likewise the version. Set membership passes a swap; arch-keyed equality does not.

**Why checks 2/4/5 are written this way (the defect they exist to catch).** `zot_registry.tf` selects at apply time with `local.registry_arch == "arm64" ? local.zot_image_arm64 : local.zot_image_amd64`, and `registry_arch` is `amd64` today. If the two digests are swapped — a trivially plausible copy-paste across a two-row table — the amd64 host pulls the **arm64** binary, `exec format error`, zot never answers `/v2/`, cloud-init's readiness loop never completes, and **the sole pull path goes permanently dark**. That is the §User-Brand Impact outcome, reached through the front door of this very gate. Under a set-membership or alternation formulation, *every* assertion in this file still passes on a swap. Arch-keying is the whole point of the check, not a stylistic preference.
6. **Age gate** — parse the sidecar's capture date, compute `age_days`, FAIL above `MAX_AGE_DAYS`. **`MAX_AGE_DAYS=90`**, with the cadence justification inline: upstream's recent release interval is ~30 days (v2.1.15 2026-03-08 → v2.1.20 2026-08-04, 5 releases), and the `rule-audit.yml` poll runs on the 1st and 15th, so 90 days is ~3 upstream releases and ~6 poll firings — a genuine stall, not routine lag. Guard `age_days < 0` (future date) → FAIL. Unparseable date → **FAIL, never a silent pass**.
7. Failure messages are runbook lines naming the remedy (`re-run crane digest for both arches, re-read the changelog since <pinned>, stamp the sidecar`), not bare assertion text.

**No network.** The `crane digest` cross-check is a documented procedure in the sidecar and a Phase-0 step, not a test dependency — a test that needs the network is a test that reddens on upstream's outage.

**Expected at end of Phase 1: RED** (sidecar absent, pin lacks a version tag).

### Phase 2 — The provenance sidecar

Create `apps/web-platform/infra/zot-image.provenance.md`, modelled on `cosign-trusted-root.provenance.md` (read it first for the table shape the sibling age gate parses). Contents:

- **Capture table** — version, both digests, capture date (UTC), and the exact `crane digest` commands that produced them. **The capture-date row must be byte-compatible with the sibling gate's parser**: `cosign-trusted-root-staleness.test.sh` reads `grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*'`, and `cosign-trusted-root.provenance.md` carries `| Capture date (UTC) | **2026-07-04** |`. Use that exact row shape so the two gates share one format rather than each inventing its own.
- **The §Config-compatibility analysis table**, with its upstream source anchors (`type RetentionPolicy`, `func updateDistSpecVersion`, `DockerManifestV2SchemaV2`, `type AccessControlConfig`) — anchors, never line numbers (`cq-cite-content-anchor-not-line-number`).
- **Non-adoption decisions** — `storage.FastRestart` (new in v2.1.19, defaults false, deliberately not adopted); `storage.retention.policies[].keepUntagged` (new in v2.1.19, deliberately not adopted).
- **Version-scoped claim register** — the two claims from §Config-compatibility, each with its re-verification status from Phase 6.
- **Known coupling** — `registry-boot-guard.test.sh` asserts the config JSON with byte-literal `grep -qF`; a future schema migration that reflows that JSON breaks it even when semantics are preserved.
- **The refresh recipe** the age gate's failure message points at — i.e. the *re-stamp* recipe for a merely-aged capture date.
- **`## Previous known-good pin`** — the superseded version, **both** digests, and the date superseded. Read by staleness check 8, and the artifact §Rollback step 1 depends on. Two lines; see AC16.
- **`## Bump procedure`** — the *bump* recipe, which is a materially heavier and different procedure from the re-stamp recipe above, and which the first draft performed once in prose and never encoded. It must enumerate: the four upstream source anchors to re-diff (`func updateDistSpecVersion`, `type RetentionPolicy`, `type AccessControlConfig`, `DockerManifestV2SchemaV2`), the two version-scoped claims to re-measure by `docker run` (Phase 6), the `registry-boot-guard.test.sh` byte-literal coupling to re-check, and the requirement to move the current pin into `## Previous known-good pin` first.
  **The failure message must be an invocation, not a description.** This repo's operator is non-technical, and "re-read the changelog and stamp the sidecar" is Go-source-diffing engineering work. The age gate's remedy line therefore reads:
  `/soleur:one-shot "refresh the zot pin provenance sidecar for <newVersion> per apps/web-platform/infra/zot-image.provenance.md §Bump procedure"`
  — an agent entry point, so the recurring obligation the cadence creates has a discharge path rather than accruing on a human who cannot perform it.

Still RED (the pin has not moved).

### Phase 3 — GREEN: the pin bump

Edit the first `locals` block in `zot-registry.tf`:

- Both locals to `ghcr.io/project-zot/zot-linux-<arch>:v2.1.20@sha256:<arch digest>`.
- Rewrite the freshness comment. Keep what is still true (third-party upstream, digest-pinned, pulled from the PUBLIC registry at boot, the bootstrap paradox, and the arch derivation from `var.registry_server_type`). **Replace** the manual `crane digest` instruction — it is currently the entire freshness mechanism, and a prose instruction to a human is exactly what let this pin sit 18 releases behind. Point at `zot-image.provenance.md` (the analysis of record) and at the `rule-audit.yml` poll step (the detector) instead.
- **The comment must not claim a bot manages this pin.** No bot does. It says a **cron step files an issue** and a **human opens the PR** — the honest mechanism, so the next reader does not assume coverage that is not there. That false assumption is precisely what `renovate.json5` induced in this plan's own first draft.
- Do **not** touch the `hcloud_server.registry` `lifecycle` block. Do **not** add `ignore_changes = [user_data]`.

**Expected: GREEN.** Run the Phase-1 test.

### Phase 4 — Register the gate on BOTH triggers

**4a — per-PR coherence.** Add a step to `.github/workflows/infra-validation.yml` beside the existing `run: bash apps/web-platform/infra/cosign-trusted-root-staleness.test.sh` step. Same job, same shape. Note this workflow carries a `paths:` filter (`apps/*/infra/**`, `infra/**`, …) — that is *correct* for the coherence half and *insufficient* for the age half.

**4b — time-based backstop.** Add a `- name: Detect zot pin staleness` step to `.github/workflows/rule-audit.yml`, cloned from its existing `- name: Detect model drift` step. Adopt that step's contract verbatim rather than re-deriving it:

- run the script, capture `RC`; **an unexpected rc fails the step** (the model-drift step does exactly this — an unparseable detector is not a pass);
- on the drift rc, `gh label create zot-pin-drift --color FBCA04 --force`;
- find-or-update **one** idempotent issue: `gh issue list --label zot-pin-drift --state open --json number --jq '.[0].number // empty'` → `gh issue comment` if it exists, else `gh issue create`.

The staleness script therefore needs a **distinct exit code for "stale" vs "broken"** so the cron can tell drift from detector failure. Use the `audit-models.sh` convention: `0` = fresh, a dedicated non-1 code = stale, anything else = the detector itself failed. Do not overload `1`.

**4b-ii — the upstream poll (new; this is the half Renovate was going to do).** The same step also compares the pinned version against upstream's current release:

```bash
latest=$(gh api repos/project-zot/zot/releases/latest --jq .tag_name)   # e.g. v2.1.20
pinned=$(grep -oE 'zot-linux-amd64:v[0-9]+\.[0-9]+\.[0-9]+' "$TF" | head -1 | grep -oE 'v[0-9.]+$')
```

- `latest != pinned` → **behind**: file/update the same idempotent `zot-pin-drift` issue, naming both versions and linking upstream's compare view.
- **A failed API call is a detector failure, not "fresh".** `gh api` non-zero, an empty `tag_name`, or an unparseable version **fails the step loudly** — never silently reports up-to-date. An empty result read as "no drift" is the silent-green shape this plan exists to prevent (`hr-when-a-command-exits-non-zero-or-prints`).
- The poll is **advisory only** — it files an issue and never edits the pin. Nothing auto-writes the sole pull path's binary reference; a human opens the real PR, which is then CI-gated and CLA-checked.
- **`GITHUB_TOKEN` is sufficient** — `repos/project-zot/zot/releases/latest` is a public read. No PAT, no App credential (`hr-github-app-auth-not-pat` does not fire: no write to another repo).
- Both conditions (behind-upstream, sidecar-aged) route to **one** issue, not two, so a pin that is both stale and behind does not open duplicates.

`rule-audit.yml` already grants `contents: read` + `issues: write`; no permission change. It already exists on `origin/main`, so the `new-scheduled-cron-prefer-inngest` hook does not fire.

### Phase 5 — Remove the inert `renovate.json5`

**Replaces the first draft's "add a Renovate `customManagers` entry".** That phase is deleted: adding a manager to a bot that does not run is worse than adding nothing, because the config reads as coverage.

`renovate.json5` (repo root, added in `1e20c4bb5`, #820) configures a GitHub App that has **never executed against this repository** — zero PRs, no Dependency Dashboard (§Premise Validation). Delete the file.

**This is not tidying — the file has caused measurable harm.** It is the direct cause of this plan's first draft choosing a dead cadence for the sole pull path, and it would have shipped had the premise not been re-probed. A config that reads as active coverage while providing none is worse than an empty repo: it *suppresses* the very work it appears to do. Anyone auditing supply-chain posture here sees `docker:pinDigests` + `helpers:pinGitHubActionDigests` and concludes digests and Actions SHAs rotate. **None of them have ever rotated.**

- **Delete `renovate.json5`.** Do not replace it with a commented-out or "disabled" variant — a disabled config is the same trap with extra steps.
- **Record the removal in the ADR-096 amendment** (§Architecture Decision), with the measurement that justified it, so a future reader does not re-add it assuming it once worked.
- **State the residual gap plainly** in the PR body: the pins `renovate.json5` *claimed* to manage — GitHub Actions SHA pins and the Dockerfile/base-image digests — have **no** freshness mechanism, and removing the file does not create that gap, it makes an existing one visible. The generalization follow-through (Phase 9) is widened to name it.

**Do not install Renovate as part of this PR.** It is an operator App install, and its `default:automergeDigest` inheritance would make its first production responsibility an automerge-capable write path onto the sole pull path's binary. If Renovate is ever adopted, the retained Option C analysis (§Cadence) is the required homework.

**Scope check.** Deleting a root config file is a repo-wide change on a `single-user incident` plan. It is in scope here by explicit operator decision (2026-08-05) to fold the inert-config finding into this PR rather than defer it, and because the file is load-bearing *evidence* for this plan's central decision — leaving it would leave the next reader with the same false premise this plan just corrected.

### Phase 6 — Re-verify the two version-scoped capability claims

Both are **measurements**, so both are re-measured, not re-reasoned (`hr-verify-repo-capability-claim-before-assert`).

- Run the pinned v2.1.20 image locally with this repo's exact `config.json` and htpasswd: `docker run --rm -v <cfg>:/etc/zot/config.json:ro … ghcr.io/project-zot/zot-linux-amd64@sha256:95a837a0… serve /etc/zot/config.json`.
- **Claim 2** (`ci-deploy.sh`): `curl -sS -o /dev/null -w '%{http_code}' http://localhost:5000/v2/` unauthenticated and with each of the pull/push users. Confirm 200-or-401, never 403. If it holds, restate the claim scoped to v2.1.20 (with the same MEASURED framing) and fix the stale `zot-registry.tf:55` citation to a content anchor. **If it does not hold**, the `authz_denied` arm changes from tripwire to live — stop, downgrade the claim to `UNMEASURED against v2.1.20`, and file a tracking issue rather than shipping a false comment.
- **Claim 1** (`cloud-init-registry.yml`): probe whether v2.1.20 exposes an on-demand gc endpoint. Re-scope the sentence to the measured version either way. This does **not** mean adopting an on-boot gc trigger — only that the claim stops naming a version we no longer pin.
- Record both outcomes in the sidecar's version-scoped claim register.

### Phase 7 — `zot_image_digest` telemetry

`cloud-init-registry.yml`. Derive the running image's registry digest and append it to the `SOLEUR_ZOT_DISK` `LINE=` assembly.

- **Join the field into the EXISTING `docker inspect` call — do not add a second one.** The probe already runs one call, and the file's own comment records that as a deliberate decision: *"StartedAt joins THIS call rather than getting its own (#7247). A second `docker inspect` …"*. The existing format string is `'{{.Id}} {{.RestartCount}} {{.State.Status}} {{.State.OOMKilled}} {{.State.ExitCode}} {{.State.StartedAt}}'`; append **`{{.Config.Image}}`** and widen the `read -r` that consumes it.
  - **`.Config.Image`, not `RepoDigests`.** `RepoDigests` is a field of the *image* object, so it would require a second inspect against a different object — the thing the #7247 comment forbids. `.Config.Image` is on the *container* object and carries the exact reference the container was created with, i.e. the pin itself.
  - Keep the emitted field short: extract the digest's leading 12 hex chars (`zot_image_digest=95a837a0afac`), not the ~90-char full reference. 12 hex is unambiguous against a known pin set and keeps the line bounded.
  - The existing failure arm already sets sentinels (`ID=; ZOT_RESTARTS=-1; STATE_STATUS=unknown; …`) when the inspect fails — add `ZOT_IMAGE_DIGEST=none` to that same arm rather than inventing a separate fallback, so a dead container reports `none` by the same path as every sibling field.
- **Field placement is load-bearing.** `zot_last_err` must stay **LAST** — the file's own comment says so, and `scripts/lib/zot-telemetry-parse.sh` strips the literal ` zot_last_err=` tail to bound its trusted region. Insert `zot_image_digest=` **before** it, next to `boot_id`.
- Byte cost accounted in §Byte budget.

This is the field that makes "did the bump land?" answerable off-host on a surface with no shell.

### Phase 8 — ADR-096 amendment + C4

Per §Architecture Decision. Order: ADR first, then `model.c4`, then `views.c4`.

After the `.c4` edits, run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` — a `view … include` naming an undefined element fails there, not at `tsc`.

### Phase 9 — Follow-throughs

- **Apply-tracking issue** (`action-required` label, so `operator-digest` surfaces it — a PR body would not): *"Apply the staged zot v2.1.20 pin once #7277/#7278/#6929/#6460/#7280 clear."* **This is a dependency, not an operator step** — it cannot be automated today because the gates that block it are fail-closed by design and `hr-menu-option-ack-not-prod-write-auth` reserves the authorization for the menu-ack dispatch.

  **The body must NOT lead with the `registry-host-replace` invocation.** The first draft specified carrying *"the exact `gh workflow run … -f apply_target=registry-host-replace …` invocation"* in the body. **Fired in today's state that command darks the registry permanently** — §B2: the new host's boot guard requires `/dev/mapper/registry` while the live volume is still plaintext ext4, so it FATALs. Both the recut runbook (§*"Do NOT use `registry-host-replace` for this"*) and #6929's own body say so. A copy-pasteable command that destroys the sole pull path, handed to a non-technical operator inside an `action-required` issue, is the worst artifact this plan could produce.

  **The body carries, in this order:**
  1. The **ordered** path, with host-replace stated as the *last* step and explicitly unsafe before it: fix #7277's gate → the recut runbook's five REQUIRED cold-vehicle re-verifications (enumerated as gating checkboxes with their commands) → fire `registry-luks-recut` → fire a release to close the empty-store window → record the new volume id → **then** `registry-host-replace`.
  2. A **live precondition probe block** the operator (or an agent) runs to determine current state, rather than a command to fire blind: the `.server_types.available` stock read, `gh pr view 7280 --json state,mergedAt`, and the absolute `user_data < 32768` check.
  3. The rollback constraints from §Rollback, including the stock re-probe and the one-way-door acceptance.
  4. The `betterstack-query.sh` verification from §Observability as the **closure criterion** — the closing comment must carry the workflow run URL and the observed `zot_image_digest`.
  - Prefer a single `/soleur:` entry point that reads live state and determines the correct next dispatch, over any copy-pasteable destructive command.

  **Blocker-list corrections** (the first draft's five conditions were not all closable):
  - **#6460 is not an unblocker for B3.** B3 is "Hetzner has no `cx23` stock in hel1-dc2"; #6460 is a fleet-capacity-audit reconcile chore. Closing it changes nothing about Hetzner inventory. The real unblock is stock returning (nobody controls it) **or** flipping `var.registry_server_type` to `cpx22` — which re-derives the ADR-062 memory cap and invalidates the `model.c4` description this PR is fixing. State that fallback and its consequences; do not list #6460 as a blocker for the apply.
  - **Closing #6929 ≠ the volume is encrypted.** #6929 only *adds* the guarded dispatch; the recut must then be **fired**. Gate on the recut having succeeded, not on the issue being closed.
  - **#7280 is a PR, not an issue** — any watcher must require `mergedAt != null`, not `state != OPEN`, or a closed-without-merge false-positives as "cleared".
- **#7247 linkage** — record the falsifiable check, **not** a verdict: query Better Stack `SOLEUR_ZOT_DISK` for an event with `zot_last_err_src=panic` since #7274's fix merged (2026-08-04, `8565210d6`); if the captured panic header names a frame inside the #4204 / #4213 code paths, v2.1.20 is the fix; otherwise it is not and #7247's diagnosis continues on the probe. **This is not an acceptance criterion of this PR** — the deciding datum does not exist yet, and a hypothesis table may not read CONFIRMED while its discriminator is unobserved.
- **Generalization issue — widened by the Renovate finding.** Three other digest pins have no freshness mechanism at all: `ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a… # v3.1.1` (`ci-deploy.sh`, `readonly COSIGN_IMAGE=`), `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.24@sha256:6cdaa63d…` (`cloud-init-inngest.yml`, first-party), and the two node-base follower copies in `apps/web-platform/scripts/{plugin-root-propagation-verify,sandbox-canary-verify}-in-image.sh`.

  **Add the surface `renovate.json5` falsely claimed:** every **GitHub Actions SHA pin** (`helpers:pinGitHubActionDigests`) and every **Dockerfile base-image digest** (`docker:pinDigests`) in this repo. None has ever rotated, because the App that would have rotated them was never installed. Removing the config (Phase 5) does not create this gap — it makes an existing, previously-masked one visible, and that visibility is the point.

  File **one** issue proposing the same cron-poll + age-gate pattern this PR establishes, with re-evaluation criteria and a milestone from `knowledge-base/product/roadmap.md` (`wg-when-deferring-a-capability-create-a`). Note explicitly that the zot pin was done first because it is the sole pull path, not because it was the only stale pin.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** **Two anchored, arch-keyed greps — never one alternation.** Each returns exactly **1**:
  ```bash
  grep -cE '^\s*zot_image_amd64\s*=\s*"ghcr\.io/project-zot/zot-linux-amd64:v2\.1\.20@sha256:95a837a0[0-9a-f]{56}"' apps/web-platform/infra/zot-registry.tf
  grep -cE '^\s*zot_image_arm64\s*=\s*"ghcr\.io/project-zot/zot-linux-arm64:v2\.1\.20@sha256:56230c5a[0-9a-f]{56}"' apps/web-platform/infra/zot-registry.tf
  ```
  and `grep -c '073f30d99fbdbcd8869334231c9ca45c75e535e4bdc6e28cc8a1541abe7a3f71\|c3fc47782d98b731d5928a24182b495e28cc92f9dcf1d5317f7dbd632e10bf30' apps/web-platform/infra/zot-registry.tf` returns **0** (both v2.1.2 digests gone).
  **The alternation form the first draft used (`(amd64|arm64)` counted `-c` over the file, expecting 2) is rejected for two independent reasons.** (i) It cannot bind a digest to an arch, so a swapped pair returns 2 and passes — the registry-dark defect in §Phase 1. (ii) It counts *lines* in a file whose surrounding comment block **this same PR rewrites** (Phase 3): a rewritten comment carrying an example reference makes the count 3 and false-fails. Anchoring on `^\s*<local name> =` fixes both.
  **Scope is deliberately narrow, and this is the carve-out.** A repo-wide sweep of the old digests was run at plan time: they appear in exactly three places — the two live pins in `zot-registry.tf`, and `knowledge-base/project/specs/feat-registry-oidc-migration/phase-0-spike-evidence.md`, which records the pin *as it was at that spike*. That file is a point-in-time record and **must keep the old digest** (same class as the `**/archive/**` and own-migration-artifact carve-outs). Do not widen AC1 to a repo-wide absence assertion — it would demand rewriting history.
- **AC2.** `bash apps/web-platform/infra/zot-image-staleness.test.sh` prints **an exact, pinned count** — `RESULT: <N> passed, 0 failed` where `<N>` is written into this AC as a literal once the assertion set is final — and exits 0.
  **An unbound `N` does not satisfy this AC.** The harness's terminal contract is `[[ "$FAIL" -eq 0 ]]`, so a test whose assertions all silently match nothing prints `RESULT: 0 passed, 0 failed` and exits 0. Accepting any `N` accepts that run. Pin the number; a change to it is then a deliberate edit rather than a silent regression.
- **AC3.** The gate actually fails when it should. **One mutation per assertion** — the first draft's three covered only three of eight. Each applied, asserted to make the test exit non-zero, then reverted:
  - (a) change one arch's digest only → check 5
  - (b) change one arch's version tag only → checks 3 and 5 (note these **mask** each other; assert the specific failing check, not merely non-zero exit)
  - (c) back-date the sidecar capture date past `MAX_AGE_DAYS` → check 6a
  - **(d) SWAP the two digests** → checks 2 and 5. **This is the most important mutation in the set** and the first draft had no equivalent: a swap introduces no novel value, so (a) cannot catch it, and it is the mutation that ends in a permanently dark registry.
  - (e) paste one arch's digest into **both** slots → check 4 (distinctness)
  - (f) add a **commented-out** second pin → check 2's `n -eq 1` decoy guard
  - (g) set the capture date to a **future** date → check 6b
  - (h) set the capture date to **garbage** (`not-a-date`) → check 6c, which must FAIL rather than silently pass
  - (i) delete the `## Previous known-good pin` row → check 8 (§Rollback)
  **A gate that has never been seen red is not a gate** — and an all-green run is equally consistent with the assertions matching nothing. Checks (f)/(g)/(h) are exactly the "cannot go red" class this repo has already been bitten by twice (#7248, #7274), so they are not optional polish.
- **AC4.** Both triggers are wired. (a) `.github/workflows/infra-validation.yml` contains `run: bash apps/web-platform/infra/zot-image-staleness.test.sh`. (b) `.github/workflows/rule-audit.yml` contains a `Detect zot pin staleness` step that invokes the same script and files a `zot-pin-drift`-labelled idempotent issue. (c) `actionlint` is clean on **both** files. (d) The script's exit codes are distinct — `0` fresh, a dedicated non-1 code for stale, anything else = detector failure — proven by driving each path and recording the observed rc.
- **AC5.** **The upstream poll is proven live against real data, in both directions.** Run the Phase 4b-ii poll logic locally:
  - **Behind-detection (the case that matters):** with the pinned version forced to `v2.1.19`, the poll reports drift and names both versions. A detector only ever exercised on the no-drift path is untested.
  - **Fresh:** at the real pin (`v2.1.20` at plan time), the poll reports no drift — or reports drift correctly if upstream has moved by /work time, which is a **pass**, not a failure, provided §Target-version is re-run per Phase 0 P1.
  - **Detector-failure:** with `gh api` forced to fail (bad repo path), the step exits with the detector-failure code and **does not** report "fresh". Capture the observed rc for each of the three paths.
  **Replaces the first draft's Renovate dry-run AC**, which would have passed while proving nothing — a local `--dry-run=lookup` shows the regex parses, not that any bot executes it, and no bot does (§Premise Validation).
- **AC6.** **`renovate.json5` is gone and nothing references it.** `test ! -e renovate.json5` succeeds, and `grep -rn 'renovate' --include='*.yml' --include='*.yaml' --include='*.json' --include='*.json5' --include='*.md' .github/ apps/ knowledge-base/engineering/` returns no hit that asserts Renovate manages anything in this repo (matches inside this plan, its archive, and the ADR-096 amendment's *historical* record of the removal are expected and allowed).
  Also assert **no `renovate.json` was created as a side effect**: `test ! -e renovate.json`. A stray `renovate.json` outranks `renovate.json5` in Renovate's own config resolution, so a leftover from any JSON5 tooling would be worse than the file just deleted.
- **AC7.** **Byte delta, not absolute** (base-independent), and it has a **runnable invocation**: `bash apps/web-platform/infra/registry-userdata-budget.sh --json` on this branch and on the merge base. Measured with terraform's own `base64gzip` — **never `gzip -9`**, which `git-data-userdata-budget.sh` forbids because it overstates headroom.
  **MEASURED 2026-08-05, and the AC is stated from the measurement rather than the reverse.** The delta must be reported in BOTH regimes, because they differ by an order of magnitude and only one of them is the regime the apply can occur in:
  | regime | merge base | branch | delta |
  |---|---|---|---|
  | unstripped (today's `main`) | 34,800 B | 36,072 B | **+1,272 B** |
  | rationale-stripped (post-#7280) | 9,252 B | 9,388 B | **+136 B** |
  **Bound: the stripped delta must be ≤ 160 B.** That is the functional cost — the `:vX.Y.Z` tag plus the `zot_image_digest` telemetry field — and it is the number that survives into the regime where a host can actually be created.
  **This AC was drafted at ≤ 120 B before measuring and the measurement came back 136 B.** The bound is corrected to 160 B rather than the measurement being trimmed to fit, because 136 B buys the only off-host answer to "did the bump land" on a shell-less host; and the correction is recorded rather than silently applied, since a bound quietly relaxed to match its result is not a bound. Do not widen it further without the same treatment.
  **The unstripped +1,272 B is rationale prose and must NOT be traded away for bytes** (§Byte budget): #7280's `local.registry_rationale_strip` removes comments *before* measurement, so it goes to ~0 the moment #7280 lands — and until #7280 lands no host can be created at any size, because the absolute is already breached on `main` (see below).
  **The absolute is NOT dropped — it moves to where it binds.** BOTH bases exceed the 32,768 B cap unstripped (merge base −2,032 B, branch −3,304 B). **This PR does not create that breach; it inherits it**, and it independently confirms §Byte budget's claim that **#7280 is a de-facto prerequisite for the bump to ever apply**. `rendered < 32768` is therefore carried as a **hard, copy-pasteable precondition in the Phase 9 tracking issue**, above the dispatch path. Firing host-replace over-cap means hcloud rejects the create **after** the destroy succeeded — a stranded registry, which is the §Rollback one-way door reached by arithmetic.
  **The absolute is NOT dropped — it moves to where it binds.** A delta-only AC lets this PR merge without ever asserting the apply is *possible*; on today's `main` the absolute is breached by 1,860 B. So `rendered < 32768` is carried as a **hard, copy-pasteable precondition in the Phase 9 tracking issue**, above the dispatch path. Firing host-replace over-cap means hcloud rejects the create **after** the destroy succeeded — a stranded registry, which is the §Rollback one-way-door scenario reached by arithmetic.
- **AC8.** The two version-scoped claims name the measured version, and **zero** line-number citations into `zot-registry.tf` remain **in live code**:
  ```bash
  grep -rnE 'zot-registry\.tf:[0-9]+' apps/    # must return nothing
  ```
  **Scoped to `apps/` deliberately, and widened from `:55` to `:[0-9]+`.** Two corrections to the first draft:
  - *Scope.* Run repo-wide, the first draft's command returns 11 hits, and two fall outside its prose carve-out: `knowledge-base/engineering/operations/post-mortems/zot-gate-login-failed-postmortem.md` and `knowledge-base/project/learnings/2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md`. Both are frozen historical records and both statements are **true as history**. The AC would fail on a correct implementation, and the pressure to green it would drive /work to rewrite a post-mortem — and specifically a learning file titled *"a false comment shipped the bug then plan, guard, ADR and tests each restated it"*, where editing it to satisfy a grep would be a fifth restatement. Historical records are not fixed; live code is.
  - *Pattern.* `cq-cite-content-anchor-not-line-number` is about the **class**, not the instance — a future `:59` must be caught too.
  Today this returns exactly one hit, which is the one this PR fixes: `apps/web-platform/infra/ci-deploy.sh`.
- **AC9.** **Anchored on the `SOLEUR_ZOT_DISK` assembly, not on bare tokens.** The file contains **two** `LINE=` assemblies and **both** currently end in `zot_last_err=` (the `SOLEUR_ZOT_DISK` one and the `SOLEUR_PRIVATE_NIC` one), so a naive tail grep returns 2 and cannot tell which line survived:
  ```bash
  last=$(grep -o 'LINE="SOLEUR_ZOT_DISK .*"' apps/web-platform/infra/cloud-init-registry.yml \
         | grep -oE ' [a-z_0-9]+=' | tail -1 | tr -d ' ')
  [[ "$last" == "zot_last_err=" ]] || { echo "FAIL: tail field is '$last'"; exit 1; }
  grep -o 'LINE="SOLEUR_ZOT_DISK .*"' apps/web-platform/infra/cloud-init-registry.yml \
    | grep -q 'zot_image_digest=' || { echo "FAIL: field not in the DISK line"; exit 1; }
  ```
  **The second assertion is the load-bearing one.** The first draft's `grep -c 'zot_image_digest=' <file> ≥ 1` is a bare token over a file that is mostly comments — put the field in a comment and it passes with zero telemetry shipped, because nothing required the field to be *inside* the `SOLEUR_ZOT_DISK` line. AC9 cited `cq-assert-anchor-not-bare-token` and then violated it in its own first clause.
- **AC10.** `bash apps/web-platform/infra/registry-boot-guard.test.sh` passes (the config JSON is unchanged; this AC proves it).
- **AC11.** `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass; `model.c4` declares the upstream **`projectZot`** element and it appears in the **context** and **containers** view `include` enumerations in `views.c4`; and the **`zotRegistry` element block** no longer says `cx33` or `7168m`.
  Three corrections to the first draft:
  - **No `renovate` element.** The first draft added one, describing a bot that writes PRs here. It does not (§Premise Validation) — modelling it would put a false trust boundary in the architecture diagram, which is worse than the omission it was fixing.
  - **Scope the `cx33`/`7168m` assertion to the `zotRegistry` block, not the file.** `grep -n 'cx33\|7168m' model.c4` returns lines **182, 272, 458**, and **182 and 458 are TRUE** — web-1 and soleur-grok-dogfood really are `cx33`. A file-scoped `== 0` check would drive deletion of correct facts.
  - **Name the two views explicitly.** `views.c4` has **three** `include` enumerations (context, containers, and the L3 *components of platform.plugin*), not two. `projectZot` belongs in the first two; adding it to the L3 plugin view would be wrong.
- **AC12.** ADR-096 carries the "Pin freshness" amendment naming: the **owner** (the `rule-audit.yml` upstream-poll step, not Renovate), the **gate** (`zot-image-staleness.test.sh`), the **rollback** pointer (§Rollback + the sidecar's previous-known-good row), and the **measured reason `renovate.json5` was removed** — so a future reader does not re-add it believing it once worked.
- **AC13.** Every `knowledge-base/` path cited in this plan resolves: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` prints nothing.
- **AC14.** The PR body records, as measured facts: whether the drift detector already reported a pending `hcloud_server.registry` replace (Phase 0 P4), and #7280's merge state at ship time.
- **AC15.** The apply-tracking issue and the generalization issue exist and are linked. The PR body carries `Closes #7282` **on its own body line**, plus `Ref #7247 #7277 #7278 #6929 #6460 #7280`.
  - **`#7280` added** — §Byte budget calls it "a de-facto prerequisite" and AC14 requires recording its merge state, so omitting it from the Ref list was inconsistent.
  - **Own line, and no other close-keyword anywhere in title or body.** `.github/workflows/pr-auto-close-scanner.yml` matches close-keywords **anywhere in title or body, including code blocks and prose** — and this body will quote Phase-0 measured output and describe the tracking issue, so quoted material is likely. Assert the absence of stray `Closes|Fixes|Resolves` outside the one intended line (`wg-use-closes-n-in-pr-body-not-title-to`).
- **AC16.** **The rollback target survives.** `apps/web-platform/infra/zot-image.provenance.md` contains a `## Previous known-good pin` section recording the superseded version, **both** digests, and the date it was superseded; and staleness **check 8** asserts that section exists **and** that its digests differ from the current pin. Proven red by AC3 mutation (i).
  Without this, AC1 deliberately erases both v2.1.2 digests from the `.tf`, leaving the last-known-good pin only in git history and an archived plan — turning §Rollback step 1 into a git-archaeology exercise under incident pressure on a shell-less host.

**On `Closes #7282`.** #7282's four scope checkboxes are all repo-scoped (bump the pin, read the changelog, establish a cadence, record the #7247 linkage) and all four are completed here; the issue itself already records that the *apply* is blocked and names its prerequisites. The ops-remediation `Ref #N` convention does not apply, because the blocked apply is tracked as a **separate** issue rather than being this PR's own deferred fix. If review disagrees, the fallback is `Ref #7282` plus a closing comment once the apply lands — state the choice explicitly rather than letting it be relitigated.

### Post-merge

**None currently actionable — but "none" is a statement about authorization, not about the journey, and the first draft conflated the two.**

- **One blocked operator action exists:** the production apply. It is a **dependency** on #7277/#7278/#6929/#6460/#7280, tracked by the Phase 9 issue, and its authorization is reserved to the menu-ack dispatch (`hr-menu-option-ack-not-prod-write-auth`). It is not a checklist item in this PR (`wg-block-pr-ready-on-undeferred-operator-steps`, `hr-ship-message-no-operator-checklist`).
- **Four steps downstream of that apply are genuinely authorization-reserved** and stay human: fixing #7277's gate, the recut runbook's five cold-vehicle re-verifications, firing `registry-luks-recut`, and firing `registry-host-replace`.
- **Four more are automatable and are automated here:** upstream-drift detection (Phase 4b poll, replacing "someone runs `/soleur:operator-digest` and notices"), sidecar-staleness detection (Phase 4b age gate), coherence enforcement (Phase 4a), and the arch-swap guard (Phase 1 check 2/4/5).
- **One recurring obligation the cadence CREATES and must not hide:** every future bump needs the changelog re-read and the sidecar re-stamped. That is real ongoing cost, it is engineering work rather than operator work, and Phase 2's **Bump procedure** section plus the failure message's `/soleur:one-shot` invocation are how it is discharged rather than silently accrued.

Stating this honestly costs nothing and is the difference between a reviewer seeing the blocked path and not.

## Rollback — if v2.1.20 crash-loops after the apply

**The first draft had no rollback section at all.** Its §Risks offered only *detection* (`zot_image_digest` × `zot_last_err_src` × `zot_restarts`, plus `scheduled-zot-restart-loop.yml`). Detection with no recovery is an alarm, not a plan — and #7278 states the operational surface for a crash-looping zot is *currently empty*: no in-place restart, no shell, and `--restart unless-stopped` already demonstrated 5,000+ useless restarts in #7247.

**The recovery path, written down because it is currently written down nowhere:**

1. Revert the two locals in `zot-registry.tf` to the previous known-good pin (recorded in the sidecar — see below).
2. Merge. Inert by `OPERATOR_APPLIED_EXCLUSIONS`, as always.
3. Re-fire `registry-host-replace`.

**Why this works, and why it is worth stating explicitly:** cloud-init pulls zot from the **public upstream registry**, never from our own zot (`zot-registry.tf`'s own bootstrap-paradox comment). So a dark zot **does not block its own replacement**. That is the one genuinely working recovery lever available today.

**Two hard constraints on it, both of which must be accepted before the apply is fired:**

- **The rollback target must survive AC1.** AC1 asserts both v2.1.2 digests are *gone* from the `.tf`, so after this PR the last-known-good pin exists only in git history and in an archived plan. Under incident pressure on a shell-less host, "what were we running before" must not be a git-archaeology exercise. **The sidecar therefore carries a `## Previous known-good pin` row** (version + both digests + the date it was superseded), and **staleness check 8 asserts that row exists and differs from the current pin.** Two lines; highest-value item in the sidecar.
- **The revert needs a second successful host create, subject to the same `stock_preflight_gate` that is ABORTing today (B3).** If capacity blocked the apply for weeks, a same-day revert may be un-orderable — leaving a crash-looping registry with no forward and no back. **The apply is therefore one-way with no capacity reservation.** The Phase 9 issue must require a **live stock re-probe immediately before firing**, and must state the abort rule: do not fire unless the type is orderable *and* the operator accepts that recovery depends on a second create succeeding. Prefer firing immediately before a planned release window, the same discipline the recut runbook already mandates.

**#7278 is therefore a rollback dependency, not merely a prerequisite.** The first draft listed it only as a thing blocking the apply. It is also the thing that makes a cheaper remedy than full host-replace possible at all, so firing the apply while #7278 is open should not be treated as acceptable even if the other blockers clear.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Target **v2.1.19** instead of v2.1.20 | Same fixes, 11 hours more soak — but the v2.1.19→v2.1.20 delta is a zui bump (inert: no `extensions` block in our config) plus an upstream-CI-only pin. Taking N-1 buys no real soak and leaves the cadence opening a bump PR on day one. Recorded as the documented fallback floor. |
| Target **v2.1.18** | Contains neither #4204 nor #4213 — disqualified by the issue's own safety motivation. |
| Keep the digest-only pin form (no version tag) | **The tag survives the Renovate finding on independent grounds.** The original reason (Renovate's docker datasource needs a `currentValue`) is void, but the tag is now what the **upstream poll parses** to learn the pinned version, and what makes the cross-arch version-coherence assertion (check 3) and the sidecar↔pin version assertion (check 5) expressible at all. The alternative — capturing the version from a trailing comment — reintroduces exactly the comment-vs-artifact drift this plan removes, and forfeits `crane digest <tag>` as a live coherence check. Cost is ~10 B of a 23,696 B budget. |
| **Renovate `customManagers`** (the first draft's choice) | **Renovate is not installed here** — zero PRs ever, no Dependency Dashboard. The cadence would have been inert and silently so, and its AC would have passed. Rejected on measurement, not preference. Installing it is also an operator App install whose `default:automergeDigest` inheritance would make its first production job an automerge path onto the sole pull path. |
| **Inngest cron + `safeCommitAndPr`** | **The runner-up, and the only option that literally opens a PR.** Rejected on cost, not capability: a cron function + Sentry monitor + allowlist + release poller, versus one step on a workflow that already runs — and the PR it opens still cannot merge until a human stamps the sidecar, so the machinery buys a draft, not an outcome. Recorded as the explicit upgrade path if issue-filing proves too weak; clone `cron-content-vendor-drift.ts`. |
| **Mirror `model-launch-review`** (the issue's own suggestion) | **CHOSEN** — see §Cadence Option A. It files an issue rather than opening a PR, which the first draft treated as disqualifying; with Renovate absent the comparison is issue-filer vs. *nothing*, and the repo's own SKILL.md argues a bot-token PR is the weaker artifact (no CI, no CLA). A *new* `scheduled-*.yml` would be hook-denied, but this adds a step to `rule-audit.yml`, which already exists on `origin/main` — so the hook does not fire. |
| Add `lifecycle.ignore_changes = [user_data]` to silence the drift report | Would defeat the intended replace-to-reprovision path for a cosmetic win. The file's own comment forbids it. |
| Build a feature flag / commented-out pin to "stage" the bump | Redundant. `OPERATOR_APPLIED_EXCLUSIONS` already makes merging inert; a second mechanism would guard a property the repo already has. |
| Widen the `registry_host_replace_gate` allow-set to admit the two LUKS creates | The gate's own header forbids it and explains why the abort is correct. Would convert B1 into B2 (permanently dark registry). |
| Fold the other three unmanaged pins in now | Real scope creep on a `single-user incident` change to the sole pull path. Deferred with a tracking issue (Phase 9). |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The cadence is built on a bot that does not run** — the failure this plan's own first draft made | **Realised, then corrected.** The first draft chose Renovate; Renovate has never executed here. Mitigation is now structural: AC5 proves the poll live **against real data in all three directions** (behind / fresh / detector-failure), which a config diff or a local dry run cannot do. **A cadence mechanism may not be accepted on the evidence that its config exists.** |
| The upstream poll silently reports "fresh" because the API call failed | Phase 4b-ii fails the step loudly on non-zero `gh api`, empty `tag_name`, or unparseable version — never conflated with no-drift. Proven by AC5's forced-failure path. Backstop: the offline age gate needs no network and reddens on the sidecar's own date. |
| The age gate reddens CI on an unrelated infra PR in 90 days | By design — the `cosign-trusted-root-staleness.test.sh` precedent at 150 days is accepted in this repo. The failure message is a runbook line naming the remedy, now an executable `/soleur:one-shot …` invocation (Phase 2). A bump resets the clock naturally via the sidecar update. **Note the scope word:** `infra-validation.yml` carries a `paths:` filter, so this is "the next *infra-touching* PR", which is why the `rule-audit.yml` cron exists as the PR-cadence-independent trigger. |
| Removing `renovate.json5` is read as removing working automation | It removed **no** automation — measured: zero PRs, ever. The ADR amendment and the PR body both carry the measurement, and the generalization issue names the now-visible Actions-SHA / base-image gap so the honesty is not mistaken for a regression. |
| v2.1.20 breaks on this exact config in a way source-reading missed | Phase 6 runs the pinned image locally with the repo's exact config before shipping. Post-apply, `zot_image_digest` × `zot_last_err_src` × `zot_restarts` discriminate in one event; `scheduled-zot-restart-loop.yml` already alarms on recurrence. |
| The pin sits staged indefinitely because nobody notices it never applied | This is the failure the `zot_image_digest` field exists to make visible; before it, "is the new zot running?" was unanswerable on a shell-less host. **The `action-required` issue alone is NOT sufficient and must not be cited as if it were:** `operator-digest` is a **manually invoked skill** (no workflow runs it), so "the digest will surface it" reduces to *a human remembering to run the digest that exists to remind them* — circular. The non-circular mechanism is the `rule-audit.yml` cron, which fires on its own schedule and is where the staged-vs-applied check belongs. |
| #7280 lands first and AC7's absolute numbers shift | AC7 asserts a **delta**, which is base-independent; the absolute is recorded for context alongside which base it was taken on. |
| The `zot_image_digest` derivation returns empty and the field ships as a silent blank | It rides the existing `docker inspect` call and its existing sentinel arm (`ZOT_IMAGE_DIGEST=none` beside `STATE_STATUS=unknown`), so a dead container reports `none` by the same path as every sibling field. Inserted before `zot_last_err`, so a blank cannot corrupt the trusted region `zot-telemetry-parse.sh` bounds. |
| `zot_image_digest` is read as "the bump landed" when the container never started | `.Config.Image` reports the reference the container was *created with*. On a host that booted the new pin but whose zot crash-loops, the field reports the NEW digest while `state_status`/`exit_code`/`zot_restarts` report the failure — which is the correct discrimination, not a false positive. If no container exists at all, the field is `none`, not a stale digest. |
| Re-measuring the `ci-deploy.sh` 401 claim reveals v2.1.20 now answers 403 | Then `authz_denied` is a live arm, not a tripwire — Phase 6 stops and files rather than shipping a false comment. This is a genuine possible outcome of #4165, not a formality. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, placeholder, or missing the threshold fails `deepen-plan` Phase 4.6. This one declares `single-user incident`, which also escalates plan-review to the 5-agent panel and adds `user-impact-reviewer` at PR review.
- **Do not edit `.worktrees/feat-one-shot-7278-registry-restart-lever`.** Read it for state only.
- The `crane digest` figures in this plan were captured 2026-08-04. **Re-resolve at /work time** and fail on mismatch — a digest quoted from a plan and never re-checked is exactly the drift digest-pinning exists to prevent.
- Measure `user_data` with terraform's own `base64gzip`. `gzip -9` on the raw file is forbidden (`git-data-userdata-budget.sh`) because it **overstates** headroom, and on a hard gate an optimistic measurement is worse than none.
- `zot_last_err` must remain the final field of the `SOLEUR_ZOT_DISK` line. `scripts/lib/zot-telemetry-parse.sh` strips the literal ` zot_last_err=` tail to bound its trusted region; inserting after it corrupts the parse.
- The two version-scoped claims are **measurements**. Re-deriving them from upstream source is not re-verification — `docker run` the pinned image or downgrade the claim.
- **Registering a gate in a workflow is not the same as giving it a trigger.** `infra-validation.yml` carries a `paths:` filter, so a gate registered there fires only on infra-touching PRs. The first draft of this plan claimed "RED in CI on the next PR" and was wrong. Before claiming any CI gate "fails on the next PR", read that workflow's `on:` block **and** its `paths:` filter.
- Nothing in this plan may assert that v2.1.20 fixes #7247. The deciding datum (the panic header) has not been observed since #7274's fix merged. A hypothesis table may not read CONFIRMED while its discriminator is invisible.
- **A config file is not a running system. Never accept "X is installed" from the presence of `X.json`.** This plan's first draft built its entire cadence on `renovate.json5` and asserted, in four separate sections, that Renovate "is already installed, already runs weekly, and already opens digest PRs against this repo." **Zero Renovate PRs exist in this repo's history, and there is no Dependency Dashboard issue.** The config had been inert since #820. Before naming any bot, App, or external service as a mechanism owner, prove it has **executed here**: `gh pr list --state all -L 300` grouped by author, plus the artifact the tool creates at onboarding. The cheap check would have taken one command; skipping it nearly shipped a dead cadence onto the sole pull path — the exact failure class #7282 is about.
- **The corollary, which is the more dangerous half:** the first draft's AC for that cadence (`npx renovate --platform=local --dry-run=lookup`) **would have passed**. A local dry run proves a regex parses; it cannot prove any bot runs it in production. When an AC validates a *config* rather than an *execution*, it certifies the wrong thing — and a green AC over an inert mechanism is indistinguishable from a green AC over a working one. Assert on observed behaviour in the real environment, or assert nothing.
- **Do not model an unused external system in C4.** The first draft added a `renovate` element and a `renovate -> github` edge. Drawing a trust boundary that does not exist is worse than the omission it fixes: every later reader treats the pin as bot-managed and stops looking for an owner.
- **`views.c4` has THREE `include` enumerations** (context, containers, L3 components-of-platform.plugin), not two. Adding an element to "both" lists is an instruction that cannot be followed correctly; name the views.
- **The `zotRegistry` C4 description is not the only place `cx33` appears.** `grep -n 'cx33\|7168m' model.c4` returns lines 182, 272, 458 — and **182 and 458 are correct** (web-1 and soleur-grok-dogfood really are cx33). Scope the fix to the `zotRegistry` element block; a file-scoped `== 0` assertion would drive deletion of true facts.
