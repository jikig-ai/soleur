---
title: "fix: SENTRY_AUTH_TOKEN recorded in published build provenance — close the build-arg secret channel"
date: 2026-08-10
type: fix
issue: 7389
branch: feat-one-shot-7389-provenance-buildarg-secret
lane: cross-domain
brand_survival_threshold: single-user incident
brand_survival_threshold_status: PROVISIONAL — derived from a pending Art. 4(12) determination; see "Threshold flip conditions"
requires_cpo_signoff: true
cpo_signoff: CHANGES REQUESTED (B1–B7) — addressed in this revision; re-confirm at deepen-plan
---

# fix: `SENTRY_AUTH_TOKEN` is recorded in published build provenance (#7389)

> Spec lacks valid `lane:` — no spec.md exists for this branch. Defaulted to `cross-domain` (TR2 fail-closed).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  IaC-routing ack (Phase 2.8 reviewed). Rotation writes an externally-minted vendor credential via
  `doppler secrets set` / `gh secret set` rather than a `doppler_secret` Terraform resource.
  Deliberate: `doppler_secret` resources (apps/web-platform/infra/git-data-luks.tf) carry values
  Terraform GENERATES, where tfstate custody is unavoidable. These tokens are minted at Sentry, so
  routing them through Terraform would newly persist live bearer tokens in terraform.tfstate on the
  R2 backend — a worse posture for a plan whose subject is a credential landing in a durable
  artifact. CLI-write for externally-minted credentials is established in 10+ runbooks. Per ADR-031,
  `SENTRY_IAC_AUTH_TOKEN` is a GitHub repo secret by documented divergence from AP-008.
  This plan touches NO .tf file — the required-check promotion was dropped in review.
-->

## Overview

`.github/workflows/reusable-release.yml` passes a live Sentry API bearer token to
`docker/build-push-action` as a **build-arg**. BuildKit records it in the SLSA provenance
attestation published with the image, and `crane copy` mirrors that attestation into the zot
registry. Measured exposure window: **2026-03-28 → present (~4.5 months)**, opened by commit
`90b5b7fd5` (#1235) and renamed in place 2026-05-19 by `071c8ec53` (#4105).

The functional fix is about fifteen lines. The plan around it does four other things:

1. **Contain first, decoupled from this PR** (Phase 1). Containment and remediation are independent;
   the only thing coupling them was the *secret name*. Break the name and the leaked credential can
   be revoked **today**, without waiting for the rest of this plan to merge.
2. **Split the identity** (Phase 1). The deeper defect is not scope width — it is that an
   IaC-admin credential was handed to a source-map upload. `apply-sentry-infra.yml` says the token
   "is dedicated to this IaC pipeline"; the release build needs only `project:releases` + `org:read`.
3. **Close the class** with one script in two modes, plus a release-time attestation gate. Both are
   needed because **CI never runs the Docker build**.
4. **Discharge the record** — Art. 33(5) determination note and an Article 30 PA-8 amendment.

**The asymmetry that let this survive review:** the build-arg key is `SENTRY_AUTH_TOKEN` but the
secret is `secrets.SENTRY_IAC_AUTH_TOKEN`. A grep for `secrets.SENTRY_AUTH_TOKEN` finds nothing.

**Why the gates are proportionate** (they are *not*, judged on this leak alone — the measured
audience is two principals). The forward-looking argument is the real one: the **Phase 5 roadmap
milestone commits to code signing for macOS + Windows distribution**. Signing and notarization
credentials are exactly this class of secret, on exactly this channel, in artifacts distributed to
*users' machines* rather than a private package. The scanner's value is being in place before that
lands.

## Premise Validation

| Cited artifact | Check | Result |
| --- | --- | --- |
| Issue #7389 | `gh issue view` | **OPEN**, `type/security`, milestone Post-MVP/Later. |
| Build-arg + Dockerfile `ARG` | Read | **Confirmed** at `reusable-release.yml` build-args block and `Dockerfile` builder stage. |
| GHCR package visibility | `gh api` | **`visibility: private`** on a **public** repo. Anonymous read empirically closed (manifest + `tags/list` both 403). |
| Enumerated audience | `gh api members` + `collaborators` | **`deruelle` (admin) + `Elvalio` (outside collaborator, write)** — Elvalio granted access *mid-window*. |
| Data subjects in `jikigai-eu` Sentry | `audits/2026-05-17-sentry-ingest-window-auth-users-audit.md` | **10 accounts, all operator-adjacent. Zero arms-length external.** The alpha tester runs the self-hosted CLI plugin, which emits no telemetry into this org. |
| Exposure window start | `git log -S` | **2026-03-28**, `90b5b7fd5` (#1235). |
| Token consumers | `grep -rl secrets.SENTRY_IAC_AUTH_TOKEN .github/workflows/` | **Six workflows**, not four: `reusable-release.yml`, `apply-sentry-infra.yml`, `apply-web-platform-infra.yml`, `deploy-docs.yml`, `scheduled-followthrough-sweeper.yml`, `sentry-audit-gate.yml`. Plus `cron-community-monitor`, which is **not a workflow** — it is `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`, running in the deployed container. |
| #5506 (cited as the Playwright blocker) | `gh issue view 5506` | **CLOSED — COMPLETED.** The earlier draft cited it as an open tooling-retry. It is not; see Phase 1.2. |
| PR #7379 / ADR-169 | `gh pr view 7379 --json files` | ADR-169 is `MODIFIED`, not newly claimed. **172 is free outright**; 167 is a gap. Zero file overlap with this plan. |
| Rule id | grep ×3 | **Free** in AGENTS.md, AGENTS.rules.md, retired-rule-ids.txt. |

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured) | Plan response |
| --- | --- | --- |
| **R0.** Docs say build-args are excluded at `mode=min`; the issue measured them present. | Neither "docs bug" nor "version drift" is established. The most likely reading: `.buildDefinition.externalParameters.request.args` is the **frontend request attribute map** (the raw opts BuildKit received — `build-arg:*`, `label:*`, `target`, …), plausibly governed by a different rule from the build-args-in-provenance rule the docs describe, and plausibly **mode-independent by design**. The issue's "min confirmed" inference was *negative* (`buildConfig` absent), which cannot distinguish that from a wrapper artefact. | **Do not pin a causal claim in the ADR.** Phase 0.1 replaces the GHCR re-fetch with a **local A/B canary build** that settles mode-dependence directly. Whatever it shows, the fix is unchanged — secret-mount values are never recorded at any mode. |
| **R1.** "The token 403s on a read, so it may be narrower." | Live scope `[event:read, org:read, project:admin, alerts:*, project:*]`. It **has** `event:read`; the 403 was a **`team:read`** 403. The token is **wider** than supposed, with a write limb. | Report measured scope. Correct the false comment (Phase 6). |
| **R2.** Suggested allowlist `^NEXT_PUBLIC_\|^BUILD_`. | **A prefix allowlist alone re-opens the class.** Verified by running the plan's own regex + allowlist: `BUILD_DEPLOY_TOKEN` → *admitted*; `NEXT_PUBLIC_SECRET_KEY` → *admitted*. Both are credential-shaped and both pass. | **The allowlist is a conjunction**: a key is admissible only if it matches an allowlist entry **AND** does not match the credential-shape regex. RED cases for both names above. This is the single highest-value correction in the review. |
| **R2b.** Credential-shape regex `TOKEN\|SECRET\|KEY\|…\|PAT\|_DSN$`. | Unanchored `PAT` matches **`PATH`** — the most common `ENV` line in Docker. `AUTH` matches `AUTHOR`/`NEXTAUTH_URL`/`OAUTH_*`; `KEY` matches `CACHE_KEY`. | Anchor to word parts: `(^\|_)(TOKEN\|SECRET\|KEY\|PASSWORD\|PASSWD\|CREDENTIALS?\|AUTH\|PAT)($\|_)\|_DSN$`, with the false-positive list as explicit GREEN test cases. |
| **R3.** "There are sibling instances." | Exactly one `build-args:` block in `.github/`; one committed Dockerfile; zero `LABEL`, OCI annotations, `metadata-action`, or secrets reaching `$GITHUB_OUTPUT`. | No sibling fixes. Recorded in the PR body; it is the scanner's green baseline. |
| **R4.** The comment's `mode=min` reads as provenance. | It is `cache-to: type=gha,mode=min` — the layer cache. The step sets **no `provenance:` key**. | Disambiguate, and pin `provenance: mode=min` **by value** (Phase 3.3) — Phase 4's gate is fail-closed and cannot fetch an attestation that `provenance: false` would suppress. |
| **R5.** "CI catches a bad build-arg pre-merge." | **CI never runs the Docker build.** | Two modes. Plus the scanner runs as a **pre-build step in the release job** (Phase 4.4), which closes the preventive gap for free. |
| **R6.** "Add a semgrep / `skill-security-scan` rule." | semgrep: no CI job, `languages:` ts/js/bash/python, agent filters to source extensions. `skill-security-scan`: one markdown file, always exits 0, hook only on `.claude/skills/**`. Also verified: **gitleaks cannot detect this class** — it matches secret *values* by pattern/entropy, and `${{ secrets.X }}` is a zero-entropy reference; `.gitleaks.toml` has zero `build-arg`/`dockerfile`/`provenance` hits. Not misconfigured — structurally incapable. | All three **assessed and rejected with reasons**, not deferred. |
| **R7 (workflow gap).** Phase 2.7's regulated-path regex would not have fired here. | Keyed on data-*handling* surfaces; blind to credential-*plumbing* surfaces that unlock them. | **File an issue against the regex in `plugins/soleur/skills/gdpr-gate/SKILL.md` and cite its number here.** A finding recorded only in an archived plan is not recorded. |
| **R8.** `[scanner-enforced:]` makes the rule enforced. | `scripts/lint-agents-enforcement-tags.py` defines only `HOOK_TAG_RE` and `SKILL_TAG_RE` — **`[scanner-enforced:]` targets are never resolved**, so a wrong path passes CI silently. | Keep the tag (no better one exists) but do not claim the linter verifies it, and do not call this gate "fail-soft" — it is required and blocking. |

## Open Code-Review Overlap

64 open `code-review` issues queried; every planned path matched against their bodies. **None.**

## User-Brand Impact

**Measured population, by role — not a surface list.**

| Role | Exposure | Evidence |
| --- | --- | --- |
| **Operator (`deruelle`), as data subject** | Real. His own error events are in `jikigai-eu`, and he is one of the 10 accounts. | `audits/2026-05-17-sentry-ingest-window-auth-users-audit.md` |
| **The 9 other Sentry account holders** | Real but operator-adjacent (test/staff accounts), not arms-length users. | Same audit |
| **Alpha tester (Skouer)** | **Explicitly scoped OUT.** He runs the self-hosted CLI plugin, which emits no server-side telemetry into this org. He is not exposed via this vector. | `roadmap.md`, `alpha-tester-onboarding.md` |
| **Outside collaborator (`Elvalio`)** | **Audience, not subject** — holds write on a public repo and read on the private package, granted *mid-window*. His authorisation status is the entire §(i) enumeration for Phase 7, and it is answerable by asking him. | `gh api collaborators` |
| **Arms-length external users** | **Zero.** | Same audit |

**If this leaks further:** a package-read holder gets `event:read` on `jikigai-eu` — a read path into
event message/breadcrumb/tag/`user.*` values that `server/sentry-scrub.ts` does **not** remove
(PA-8 §(g), the controller's own recorded assessment) — plus `project:admin`/`alerts:*`, enough to
delete projects or silence the very Sentry monitors PA-8 §(b)(ii) designates as the **Art. 33
first-observed-at clock anchor**.

**If this lands broken, the two highest-probability harms are operational, and they are the ones a
solo founder actually feels:**
- **All releases blocked.** The gate is release-blocking and the zot mirror is the sole pull path, so
  a gate misfire means production cannot ship while it keeps serving the previous image. Mitigated by
  the break-glass (Phase 4.6) — without it, a false positive halts the company.
- **Rotation half-lands.** Six workflow consumers plus a container-resident cron; a partial rotation
  breaks the release audit, the follow-through sweeper, the community monitor, the docs deploy, and
  the Sentry Terraform apply at once. Mitigated by the value-enumeration (1.1) and the rollback
  holding key (1.5).

**Brand-survival threshold:** `single-user incident` — **PROVISIONAL.**

It cannot be lower (`none` requires no credential surface; this is one by construction). It is not
`aggregate pattern` **today**, because that definition requires systemic *impact*, and the measured
impact set is 10 operator-adjacent accounts with an audience of two. But the *capability* is org-wide,
so a realized unauthorized read would be systemic by construction.

**Threshold flip conditions** — any one flips Art. 4(12) positive, re-classifies to
`aggregate pattern`, and makes Art. 34 live. Each is a Phase 7 measurement, not a judgement call:

1. Sentry Org Audit Log shows activity in the 2026-03-28 → revocation window from an actor not
   attributable to the operator or CI.
2. Token last-used outside CI release windows.
3. Any `project:admin` / `alerts:*` **write** activity in the window — this also means the PA-8
   §(b)(ii) clock anchor is itself untrustworthy, so the determination cannot rely on Sentry monitor
   timing.
4. Any package read-principal beyond `deruelle` / `Elvalio` / CI, **or** evidence that package access
   was ever repo-inherited while the repo was public. The package is private *today*; that is the
   load-bearing control and it is one settings toggle from failing, across 4.5 months.
5. Any arms-length external signup discovered in the window.

## Architecture Decision (ADR/C4)

### ADR

**ADR-172** — *"A non-public credential's only correct channel into an image build is a BuildKit
secret mount; and a build-time credential is a distinct identity from an IaC credential."*

Two decisions, because the review established the second is the deeper one. Write it as a
**measurement record**: the Phase 0.1 A/B result (key names and value lengths only) plus the Phase
0.4 mount-contract answers, which otherwise land nowhere durable. **Do not** assert a cause for R0
the A/B did not establish — this repo has a learning about a false comment being restated by the
plan, the guard, the ADR, and the tests.

172 is free outright (#7379 modifies ADR-169 rather than claiming it). `/ship` re-derives against
`origin/main` for races with other in-flight branches; on any renumber, sweep this plan, `tasks.md`,
and every AC naming the ordinal.

### C4 views

**Read-only enumeration.** Read all three `.c4` files and confirm: external actors — none added;
external systems — Sentry, GHCR, zot; containers — none added; access relationships — none changed.
The credential channel is below C4 granularity. If any of the three systems is unmodeled, **file an
issue and cite it in the AC** — do not attach diagram work to a credential fix.

## Infrastructure (IaC)

**No Terraform change.** The earlier draft promoted the scanner to a standalone required check,
editing `ruleset-ci-required.tf`, `required-checks.txt`, and the canonical JSON. Review converged
against it, and one measurement killed the supposed benefit: **CODEOWNERS gating is a no-op here.**
`.github/CODEOWNERS` line 11 is `*  @deruelle` (global fallback — every file is already owned), and
no `github_repository_ruleset` declares `require_code_owner_review`; the CODEOWNERS header says so
itself. So "CODEOWNERS-pin the allowlist" grants zero incremental protection, and any "needs owner
review" cost/benefit argument is void.

**Route: run the source sweep inside the already-required `credential-path-guard` job**, blocking
from the first run, with an `::error::` naming the scanner.

**But that route is only sound if the bot green is EARNED, and the earlier draft missed this.**
`required-checks.txt` documents `credential-path-guard` as the one entry that is *"EARNED, NOT
FABRICATED"* — the composite action reproduces its scanner in the Phase-4 ceiling — and
`required-checks-canonical-parity.test.sh` Test 8 anchors on that reproduction. Folding a second
scanner in makes the context vouch for something the action does not run. Because the new scanner is
**zero-argument and full-sweep**, earning it is one line in
`.github/actions/bot-pr-with-synthetic-checks/action.yml` beside the existing reproduction, plus a
sibling parity Test 9 and a re-derived intersection note in the `credential-path-guard` comment
block. (The intersection *is* empty — `ALLOWED_PATHS` = {`weakness-digest.md`, `rule-metrics.json`}
∩ {`**/Dockerfile*`, `.github/workflows/**`, `.github/actions/**`} = ∅ — but the file's own note says
it "must be RE-DERIVED per gate, never inherited," and for a full-sweep gate the green asserts *the
repository is clean*, which unreachability alone does not establish.)

So `required-checks.txt` **is** edited on this route — for its comment block, not for a new context.

The `## Encryption Posture` gate no longer fires (detection is keyed on `\.tf$`, migrations,
cloud-init, docker-compose — none touched). Assessed and skipped.

Stale-framing correction: the earlier draft warned a never-reported required context wedges "every PR
**and every merge-queue entry**." There is **no merge queue** — `ruleset-ci-required.tf` records it
as REVERTED (#5780, 2026-06-30). Do not let an inflated hazard drive the routing decision. Do,
however, honour `ci.yml`'s live invariant that a job producing a required context must not gate on
`event_name == 'pull_request'`.

## Observability

The failure mode that matters is an **inert gate** — green because it inspected nothing — and its
mirror image, a gate whose only operator-facing message says the wrong thing.

```yaml
liveness_signal:
  what: "the gate prints `provenance-buildarg-gate: verdict=clean, N request key(s) + M config key(s)
         inspected, both positive controls OK`"
  cadence: every release run of web-platform-release.yml
  alert_target: "the release job AND the existing `Email notification (release FAILED)` step —
                 the operator's real first touchpoint (ADR-166 / #7242)"
  configured_in: .github/workflows/reusable-release.yml
error_reporting:
  destination: "`::error::` annotations + a three-valued `verdict` output carried into the failure email"
  fail_loud: true
failure_modes:
  - mode: "a secret VALUE appears anywhere in the attestation or image config"
    detection: "primary, channel-agnostic: exit-status-only scan of the raw bytes for each known
                sensitive value (raw + base64). Independent of BuildKit's recording shape."
    alert_route: "verdict=violation → release fails; the email says a credential was published,
                  re-running republishes it, ROTATE FIRST"
  - mode: "a non-allowlisted key is recorded (a NEW build-arg whose value the gate does not hold)"
    detection: "secondary, deny-by-default over the WHOLE request-attribute map — unknown prefix
                rejects, not just `build-arg:`"
    alert_route: verdict=violation
  - mode: "the attestation or image config cannot be fetched or parsed"
    detection: "explicit arm — never conflated with clean"
    alert_route: "verdict=could-not-inspect → the email says this is a TOOLING failure, not a leak;
                  production is unaffected and still serving the previous image; re-running is safe"
  - mode: "recording shape drifts so a key extractor matches nothing"
    detection: "TWO positive controls, because provenance and image config are different documents:
                `build-arg:BUILD_SHA` in the provenance predicate, AND `BUILD_SHA` in
                `.config.Env` of the image config. A provenance-only control cannot certify the
                image-config half was fetched at all."
    alert_route: verdict=could-not-inspect
  - mode: "source sweep fail-opens over an empty scan set"
    detection: "asserts a non-empty scan set PER GLOB SET, not merely '>=1 Dockerfile and >=1 workflow'"
    alert_route: CI job failure
logs:
  where: GitHub Actions run logs (release + CI); the failure email carries the verdict
  retention: GitHub default
discoverability_test:
  command: "gh run list --workflow web-platform-release.yml --limit 5 --json conclusion,displayTitle,url,createdAt"
  expected_output: "always emits rows keyed on conclusion — no log-scraping, no silent-on-failure
                    grep, no ssh. The actual diagnosis lives in the verdict field of the [BLOCKED] email."
```

The earlier draft's `discoverability_test` was a `gh run view --log | grep` that exits silently on
four distinct causes (gate broke, run in progress, logs aged out, unauthenticated) — indistinguishable
blanks for a non-technical operator, and a spurious FAIL in preflight Check 10, which *executes* this
command.

## Domain Review

**Domains relevant:** Engineering, Legal, Operations

### Engineering
**Status:** reviewed — 5-agent panel + `cto` + `cpo` + a scoped strong-model consult.
**Assessment:** Load-bearing decisions after review: one script two modes; a **conjunctive** allowlist
in a single data file; value-scan-first so the gate cannot decay into fail-always; two positive
controls across two documents; `required=true` instead of a CI branch the builder stage cannot
express; and containment decoupled from the PR.

### Legal
**Status:** reviewed — `soleur:gdpr-gate` invoked. **Advisory; `clo` + `legal-compliance-auditor`
before merge.**
**Assessment:** No Art. 9 match, no schema migration → **no gate-`Critical`**. Art. 32(1)(b) and
32(1)(d) apply unconditionally — (d) is the sharp one: `mode=min` was *believed* to suppress
recording, a comment encoded the belief, and it was never tested against the emitted attestation. An
untested measure is not an effective measure; the gate is the remediation. Art. 4(12) is **PENDING,
not negative**. Art. 30: **amend PA-8 §(g); do not mint PA-36.**

### Operations
**Status:** reviewed
**Assessment:** Six workflow consumers plus a container-resident Inngest cron. Two verification
traps: `deploy-docs.yml` deliberately `exit 0`s with a `::warning::` on Sentry auth failure (so
exit-status verification reads green under a dead token), and `sentry-audit-gate.yml` /
`apply-sentry-infra.yml` cannot be run on demand without a PR or an apply.

### Product/UX Gate
Not applicable — no UI-surface path. **Tier: NONE.**

## Implementation Phases

### Phase 0 — Measure and decide topology (no code)

0.1 **Local A/B canary build** — replaces the earlier draft's GHCR re-fetch, which may not be
executable at all (the interim GHCR read PAT is revoked per AP-016, so there is no local pull
credential; the *release job* is fine, it logs in with `github.token`):
```bash
docker buildx build --provenance=mode=min --build-arg CANARY=<<synthetic>> --output type=oci,dest=min.tar .
docker buildx build --provenance=mode=max --build-arg CANARY=<<synthetic>> --output type=oci,dest=max.tar .
```
Inspect both attestations. This settles mode-dependence, pins the exact field path, and needs no
registry credential. **Print key names and value LENGTHS only.**
0.2 **Pin the extractor.** Recursive descent visits every nesting depth and `imagetools` wraps
provenance per-platform, so a key appears more than once — dedupe is required, and `null` renders as
`"null"` (`value_len=4`), which must be an explicit case rather than a silent 4:
```
[.. | objects | to_entries[] | select(.key|startswith("build-arg:"))
 | {key, len:(.value | if type=="string" then length else (tostring|length) end)}] | unique_by(.key)
```
The earlier draft's success condition ("recovers all 11 keys") would not have read 11.
0.3 **Re-probe live scope** — `GET https://jikigai-eu.sentry.io/api/0/` → `.auth.scopes`.
0.4 **Verify the mount contract.** (i) `required=true` honoured by the built-in frontend with no
`# syntax=` directive — note `env=` genuinely needs Dockerfile v1.10+, so the **file form is
mandatory** here; (ii) a local build with `--secret id=sentry_auth_token,src=/dev/null` succeeds.
Record both answers **into ADR-172**, or they land nowhere durable.
0.5 **Decide token topology now, before Phase 3 commits a secret name.** Deferring this to rotation
(as the earlier draft did) means Phase 3 merges one name and Phase 7 changes it, requiring a second
workflow edit. Measured requirements: `apply-sentry-infra.yml` drives the Sentry Terraform provider
over monitors/alerts/projects and needs **write**; `sentry-audit-gate.yml` Gates 2/3 explicitly test
`project:read` + `project:releases`; the release build needs only `project:releases` + `org:read`.
**Decision: split the identity** —
- `SENTRY_RELEASE_TOKEN` → `[project:releases, org:read]` → `reusable-release.yml` (build + audit
  step) and `deploy-docs.yml`.
- `SENTRY_IAC_AUTH_TOKEN` → fresh value, measured minimum → `apply-sentry-infra.yml`,
  `apply-web-platform-infra.yml`, `sentry-audit-gate.yml`, `scheduled-followthrough-sweeper.yml`,
  `scripts/followthroughs/`, and the container cron.

### Phase 1 — Containment (pre-merge, standalone, same-day)

Independent of everything below. The leaked token stays live for exactly as long as this takes, so it
does not wait for the rest of the plan.

1.1 **Enumerate by VALUE, not key name** — the same asymmetry the scanner exists to defeat.
`.env.example` declares `SENTRY_AUTH_TOKEN`, `SENTRY_API_TOKEN`, `SENTRY_ISSUE_RW_TOKEN`,
`SENTRY_ISSUE_RO_TOKEN` as distinct keys; revoking destroys a **value**, not a key. Pull every Doppler
key across every config and every GitHub secret name, compare by last-4 + a `GET /api/0/` scope probe
per distinct value (never the raw value), and grep `secrets\.` / `process.env.` for every matched
name. That set is the consumer set.
1.2 **Mint both replacements via the API method that actually worked.** #5506 is **CLOSED —
COMPLETED**, and its closing comment records that the Playwright form-driving recipe was *abandoned*
(the browser context closed repeatedly) and that a **same-origin authenticated `fetch`** succeeded:
`POST /api/0/sentry-apps/` with `{name, organization:'jikigai-eu', isInternal:true, scopes:[…]}` →
201 (the org-scoped collection is GET-only, 405 on POST), then
`POST /api/0/sentry-apps/<slug>/api-tokens/` → 201, token returned **only at creation**. It also
documents secret handling (capture via `browser_evaluate`'s `filename` param, never printed, piped to
Doppler on stdin, temp file shredded) and orphan cleanup. **Prescribe that path; Playwright UI is the
fallback, not the primary.** Precondition it never states: the browser profile must hold a live
authenticated Sentry session — probe for it and name the remedy if absent.
1.3 **If the mint blocks, the fallback terminating action is to narrow the existing integration's
scopes in place** — dropping `project:admin` and `alerts:*` removes the write limbs that threaten the
Art. 33 clock anchor. A tooling-retry chore is *not* a terminating action for a live disclosed
credential.
1.4 **Repoint consumers to the new names** across the six workflows + the container cron.
1.5 **Rollback holding key, before any overwrite.** `doppler secrets set` and `gh secret set`
overwrite in place, and GitHub secrets are write-only — once overwritten the old value is
unrecoverable. Capture it first into `SENTRY_IAC_AUTH_TOKEN_PREV` (piped, never echoed); delete the
holding key only after 1.7 succeeds. Rollback is a **named runbook step**, not prose.
1.6 **Verify each consumer with an assertion, not an exit code.** `deploy-docs.yml` degrades to
`::warning::` + `exit 0` on Sentry auth failure, so exit status reads green under a dead token —
assert the monitor state actually flipped via a direct API read, or grep the run log for absence of
the warning. For consumers that cannot be run on demand (`sentry-audit-gate.yml` needs a PR touching
its paths; `apply-sentry-infra.yml` needs an apply), the accepted fallback is a direct `GET /api/0/`
probe proving the **scope** the consumer needs is present — state that as the verification rather
than leaving 1.7 gated on something nobody can discharge.
1.7 **The container is a consumer the ordering does not otherwise cover.** If the running
web-platform container reads the token from its boot environment, a Doppler write does not change the
process env — revoking would break `cron-community-monitor` in production until the next deploy.
Probe it via `soleur:trigger-cron` and redeploy before revoking if the value is boot-time.
1.8 **Revoke the leaked token.** `reusable-release.yml` then interpolates a dead string into the
build-arg — it leaks nothing further. Record last-4 only, and the **revocation timestamp** (the
exposure window's end boundary, required by Art. 33(5)).

### Phase 2 — RED tests first (`cq-write-failing-tests-before`)

Synthesized fixtures only (`cq-test-fixtures-synthesized-only`), with non-alphanumeric placeholder
wrappers so GitHub push protection does not reject the branch. **One battery**,
`scripts/lint-buildarg-secret-channels.test.sh`, registered in `scripts/test-all.sh` via `run_suite`
(unregistered → `lint-orphan-test-suites.sh` fails, a CI job).

**Assert per-case exit codes, not "the suite fails."** The earlier draft's closing instruction was
polluted: its repo-baseline case is *supposed* to be red at this phase (the bug is still present), so
a red suite proved nothing about the other cases being wired.

Source-sweep cases — RED: `FOO_TOKEN=${{ secrets.BAR }}`; the name asymmetry
(`SENTRY_AUTH_TOKEN=${{ secrets.SENTRY_IAC_AUTH_TOKEN }}`); **`BUILD_DEPLOY_TOKEN` and
`NEXT_PUBLIC_SECRET_KEY`** (the conjunction cases — both pass a prefix-only allowlist); a
credential-shaped `ARG`; a `LABEL` interpolating one; a `--build-arg` in a shell script; a
`build-args:` block missing `BUILD_SHA=`; an empty scan set. GREEN: `NEXT_PUBLIC_X`; **`PATH`,
`NODE_PATH`, `AUTHOR`, `NEXTAUTH_URL`, `CACHE_KEY`** (the anchoring cases); the repo baseline after
Phase 3.

`--provenance` cases — RED: a synthetic secret value present; a non-allowlisted key under any request
prefix; unparseable input; either positive control missing. GREEN: allowlisted keys, no value.

### Phase 3 — Dockerfile and workflow

3.1 Delete `ARG SENTRY_AUTH_TOKEN`. Convert the build step:
```dockerfile
RUN --mount=type=secret,id=sentry_auth_token,required=true \
    SENTRY_AUTH_TOKEN="$(cat /run/secrets/sentry_auth_token)" \
    npm run build
```
No `|| true`, no CI branch. **The builder stage has no CI signal to branch on** — `CI` is not set
inside a Docker build, and `BUILD_SHA`/`BUILD_VERSION` are declared in the *runner* stage. Worse,
`next.config.ts` reads `silent: !process.env.CI`, so the Sentry plugin already runs silent during
every release build — an empty token would vanish without trace. `required=true` makes a plumbing
regression fail everywhere, immediately. Local builds pass
`--secret id=sentry_auth_token,src=/dev/null`; document that flag in the comment.
3.2 **Check `RUN npm run build:server`** (a second builder-stage build invocation) — confirm it does
not need the token, or it silently loses what the ambient `ARG` was giving it.
3.3 Note in the comment that removing the `ARG` also removes the token from the layer **cache key**
(BuildKit excludes secrets), so a rotated token no longer invalidates that layer — a benefit, but one
that could be misread as a failed upload on a cache hit.
3.4 Workflow: remove the build-arg; add `secrets: | sentry_auth_token=${{ secrets.SENTRY_RELEASE_TOKEN }}`;
pin **`provenance: mode=min`** by value; annotate `BUILD_SHA` as the gate's positive control.
3.5 Rewrite the false-safety comment from the Phase 0.1 measurement — naming the two distinct
`mode=min` settings, confining the stage-scoping argument to the gha cache, and pointing at the
scanner by path.

### Phase 4 — The gate and the scanner

4.1 `scripts/buildarg-key-allowlist.txt` — the single SSOT, prefix vs exact distinguished by an
explicit marker. Both modes read it; a drift test asserts both consumers resolve the same file.
**Not CODEOWNERS-pinned** (a no-op here). The real protection is the **conjunction**: a
credential-shaped key is rejected *regardless of allowlist membership*, so widening the allowlist
cannot admit one. Where an ack is genuinely needed, reuse the existing
`allowlist-diff (.gitleaks.toml paths surface)` label/trailer pattern rather than inventing one.
4.2 `scripts/lint-buildarg-secret-channels.py` — one script, two modes.
**Default (source sweep, pre-merge):** full repo sweep, not `--changed` (double-vacuity trap). Glob
sets: `.github/workflows/**`, `.github/actions/**`, `**/Dockerfile*` + `**/*.dockerfile` +
`**/Containerfile*`, `**/*.sh`, `**/{docker-,}compose*.y*ml`. **Flag any non-allowlisted
`build-args:`/`args:` key regardless of value expression** — the earlier draft matched only
`secrets.*`/`env.*`, missing `steps.*.outputs`, `vars.*`, and literals. Also assert that any workflow
calling `docker/build-push-action` with `push: true` invokes the release gate — otherwise the gate
covers one of three image-building workflows. Non-empty assertion **per glob set**.
**`--provenance` mode:** value-scan first (channel-agnostic, exit-status only, never echoed);
deny-by-default over the **whole request-attribute map**; **two documents, two fetches, two positive
controls** — `--format '{{json .Provenance}}'` for the attestation and `--format '{{json .Image}}'`
for the image config, since `ENV`/`LABEL`/entrypoint live in the config, not the attestation. The
earlier draft conflated them and its single provenance-side control could not certify the config half
was fetched at all.
4.3 Emit a **three-valued `verdict`** (`clean` / `could-not-inspect` / `violation`) as a step output.
4.4 **Wire the source sweep as a pre-`docker_build` step in the release job.** It takes no arguments
and scans exactly the files that introduce this bug, so the release itself refuses to *build* a bad
configuration — closing the preventive window for the realistic surface at the cost of one step.
4.5 **Wire the attestation gate between `docker_build` and `Install cosign`** — not merely "before
the mirror." Placing it after cosign lets a known-bad image acquire a Sigstore signature and a Rekor
entry.
4.6 **Break-glass.** Model on the existing `allow_unmirrored_reason` `workflow_dispatch` escape hatch
so an override is *recorded with a reason* rather than silent. `continue-on-error` remains rejected.
4.7 **Amend the `Email notification (release FAILED)` step** to carry the verdict. Its current body
says *"re-running this workflow is safe"* — true for every existing failure, actively dangerous on a
`violation`, where the image and attestation are already pushed and re-running republishes the
disclosure. Per ADR-166 the first touchpoint must be triageable without opening the run.
4.8 Note that `lint-workflow-errexit-capture.py` and `lint-workflow-step-env-refs.py` will scan the
new `run:` blocks.

### Phase 5 — Rule corpus

New id **`hr-no-secret-in-buildarg-or-image-metadata`**; pointer in `AGENTS.md`, body in
`AGENTS.rules.md`, tagged `[scanner-enforced: …]`. **Measured: the draft body is 394 B**, not the
≤300 the earlier plan claimed — under the 600 B cap, and the full linter set passes with
`B_ALWAYS=44847` (1153 B under reject). Target ≤400 B; the two tags alone cost 107 B. Give `**Why:**`
a clause, not a bare `#7389` (every existing body pairs the id with one). Phase 5 must also run
`lint-rule-bodies.py` — a **new** id needs no hash regeneration and no ack, worth stating so nobody
hunts for one.

### Phase 6 — Review-pipeline wiring and collateral corrections

6.1 `security-sentinel` §5 — a ~3-line dispatch entry (path patterns, severity `critical`) pointing
at the scanner. This is the one surface that catches *shape* variants a regex cannot.
6.2 **No preflight Check 13, no `soleur:review` agent.** The scanner is un-scoped and already runs in
a required blocking job; a preflight check could never surface anything CI will not, nor SKIP
meaningfully, and would add a row to an aggregate table the skill already carries stale.
6.3 Correct the false `event:read` 403 comments in `apply-web-platform-infra.yml` and
`scripts/sentry-issue.sh`.
6.4 File the R7 issue against the gdpr-gate canonical regex and cite its number.

### Phase 7 — Legal record

7.1 `knowledge-base/legal/audits/2026-08-10-sentry-provenance-buildarg-disclosure.md`: the measured
audience (a **citation**, not an investigation — the package is private and anonymous read is
empirically 403); zot reachability citing `hcloud_firewall.registry` deny-all ingress; Sentry Org
Audit Log for **both** read and write activity; the window `2026-03-28 → revocation`; the express
Art. 4(12) conclusion and Art. 33(5) discharge. **Note the evidence limit honestly:** GHCR exposes a
*principal set*, not a per-package read log, so actual-read evidence must come from the Sentry side.
7.2 **Amend PA-8 §(g)**; do **not** mint PA-36. Link the rotation guidance from it.
7.3 Add an Active Item to `## Active Compliance Items` in `compliance-posture.md` (verified present at
line 109 — a reviewer claimed otherwise and the file was read to settle it).
7.4 **Record that user-facing communication was considered and declined**, with the population
evidence as the reason. Art. 34 is not reached and no notification is required — but the repo is
public and these very artifacts, plus the PR body, publish the incident in detail regardless. Silence
on a considered question reads at audit as an unconsidered one.
7.5 Update the re-minting section of `runbooks/sentry-issue-read.md` — **do not** create a 61st
runbook forking Sentry rotation knowledge across two files. #5506's closing comment already left this
as an open follow-up.

## Acceptance Criteria

### Pre-merge

Commands are parses or anchored greps, never text ranges — the file legitimately contains
`SENTRY_AUTH_TOKEN` at the audit step, in guards, and in the very comments this PR writes.

1. **Build-args cleared (YAML parse, not grep).** Load `reusable-release.yml`, select the step with
   `id: docker_build`, assert `'SENTRY_AUTH_TOKEN=' not in with['build-args']`.
2. Same parse: `with['secrets']` contains `sentry_auth_token=`, and `with['provenance'] == 'mode=min'`
   — the **value**, not the key's presence.
3. **Dockerfile ARG gone, comment-immune:**
   `! grep -qE '^[[:space:]]*ARG[[:space:]]+SENTRY_AUTH_TOKEN([[:space:]=]|$)' apps/web-platform/Dockerfile`
   (the earlier draft's `grep -c … returns 0` both matched the new comment and inverted its own exit
   code). The file contains `--mount=type=secret,id=sentry_auth_token,required=true` and no `|| true`
   on the secret read.
4. `grep -qF 'recorded in the published provenance attestation'` in both edited files — a pinned
   literal spanning no punctuation boundary.
5. `python3 scripts/lint-buildarg-secret-channels.py` exits 0 over the real repo with a non-zero
   scanned count **per glob set**.
6. `scripts/buildarg-key-allowlist.txt` exists and both consumers resolve that one path (drift test).
7. **The conjunction holds:** the battery's `BUILD_DEPLOY_TOKEN` and `NEXT_PUBLIC_SECRET_KEY` cases
   are RED, and the `PATH` / `AUTHOR` / `CACHE_KEY` cases are GREEN.
8. **CI wiring is asserted, not assumed:** `ci.yml`'s `credential-path-guard` job contains the
   scanner step, with no `paths:` filter, no sparse-checkout, and no `event_name` gate.
9. **The bot green is earned:** `action.yml`'s Phase-4 ceiling reproduces the scanner, parity Test 9
   asserts it, and the `credential-path-guard` comment block carries the re-derived intersection.
10. Release job invokes the scanner **before** `docker_build`, and the attestation gate **between**
    `docker_build` and `Install cosign`.
11. The failure-notification step carries the three-valued verdict with a value-conditional closing
    sentence.
12. AGENTS budget and rule-id linters pass; the body is ≤600 B.
13. `bash scripts/test-all.sh` passes **in full** — the gate's own invocation, not a hand-enumerated
    subset. This subsumes the per-battery and parity assertions.
14. ADR-172 exists and contains the Phase 0.1 A/B result and the Phase 0.4 mount answers.
15. C4: Sentry/GHCR/zot present in `model.c4` and both `c4-*.test.ts` pass, or an issue is filed and
    cited.
16. `security-sentinel` §5 dispatch entry present (assert the anchor line, not the words "Check 13").
17. R7 issue filed and its number cited in this plan.
18. PR body reports measured token scope, package visibility, the audience, the exposure window
    (`2026-03-28`, `90b5b7fd5`), and the sweep result.

### Post-merge (automated, in-session)

19. Ordering is explicit: **first release → then verify → then the legal record.** Containment
    (Phase 1) already completed pre-merge, so the first post-fix release builds under
    `SENTRY_RELEASE_TOKEN` and the leaked token is already dead.
20. The gate prints `verdict=clean` with both positive controls OK.
21. **Verified by measurement, not inference:** the new attestation contains neither the token value
    nor `build-arg:SENTRY_AUTH_TOKEN`, while allowlisted keys remain. **The only criterion that
    proves the fix worked.**
22. Sentry source maps still uploaded for the new release.
23. Token topology is as decided in 0.5: `SENTRY_RELEASE_TOKEN` scope is a **strict subset** of
    `{event:read, org:read, project:admin, alerts:*, project:*}` with `project:admin ∉` and
    `alerts:* ∉`; all Phase 1.6 consumers verified by assertion; holding key deleted.
24. Historical-attestation deletion attempted with a **named command**, and the outcome recorded —
    deleting a provenance attestation means deleting the `sha256-<digest>.att` referrer tag, which
    needs `delete:packages`; if the available token lacks it, that is the recorded outcome.
25. Art. 33(5) note committed with all elements incl. the flip conditions; PA-8 §(g) amended; Active
    Item added; **no new PA minted**; considered-and-declined disclosure recorded.

## Risks & Mitigations

- **R1 — Recording shape is not what the plan assumes.** *Mitigation:* the local A/B settles it before
  code; the primary invariant is value-absence, which is shape-independent; two positive controls
  across two documents.
- **R2 — The gate decays into fail-always.** *Mitigation:* value-layer positive controls, not
  key-shaped ones; plus the break-glass.
- **R3 — BuildKit image floats.** `setup-buildx-action` has no `driver-opts: image=moby/buildkit:vX`,
  and there is no dependabot, so the one component emitting the provenance can change with no commit
  here. *Mitigation:* pin the BuildKit image in Phase 3.4 and record it in ADR-172, so a shape change
  arrives as a reviewable bump rather than a surprise release outage.
- **R4 — Allowlist widening admits a credential.** *Mitigation:* the conjunction (credential-shaped
  keys rejected regardless of allowlist). CODEOWNERS is **not** a mitigation here and is not claimed
  as one.
- **R5 — Rotation half-lands or cannot be rolled back.** *Mitigation:* value-enumeration (1.1),
  holding key (1.5), per-consumer assertions (1.6), container probe (1.7).
- **R6 — The mint blocks.** *Mitigation:* the #5506 API path is primary, Playwright is fallback, and
  1.3 names in-place scope narrowing as the fallback *terminating* action.
- **R7 — Historical attestations cannot be un-published.** *Mitigation:* stated plainly; 24 records
  the deletion attempt; no implication the disclosure is undone.
- **R8 — The threshold is provisional.** *Mitigation:* five named flip conditions, each a Phase 7
  measurement.

## Sharp Edges

- **A prefix-only allowlist re-opens the class.** `BUILD_DEPLOY_TOKEN` and `NEXT_PUBLIC_SECRET_KEY`
  both pass `^BUILD_`/`^NEXT_PUBLIC_`. The allowlist must be a conjunction with the credential-shape
  regex. Verified by execution, not inspection.
- **Unanchored `PAT` matches `PATH`**; `AUTH` matches `AUTHOR`/`NEXTAUTH_URL`; `KEY` matches
  `CACHE_KEY`. Anchor to word parts.
- **Provenance and image config are different documents.** `ENV`/`LABEL`/entrypoint are not in the
  attestation. Two fetches, two positive controls.
- **Recursive descent double-counts** and renders `null` as `value_len=4`. Dedupe; make null explicit.
- **The obvious AC greps self-match the comments this PR writes.** Parse the YAML; anchor the
  Dockerfile grep to the directive. `grep -c` exits 1 on zero, so "returns 0" and "passes" are
  opposite conditions.
- **CODEOWNERS is a global `*  @deruelle` fallback with no `require_code_owner_review` ruleset** —
  pinning a file grants nothing. Do not build a mitigation on it.
- **Folding a second scanner into `credential-path-guard` breaks its "EARNED, NOT FABRICATED"
  claim** unless the composite action reproduces it too.
- **`deploy-docs.yml` exits 0 with a warning on Sentry auth failure** — exit-status verification reads
  green under a dead token.
- **There is no merge queue** (reverted, #5780). Do not inflate the required-check hazard.
- **`[scanner-enforced:]` targets are never resolved by the tag linter** — a wrong path passes CI.
- **An unregistered `scripts/*.test.sh` fails `lint-orphan-test-suites.sh`**, a CI job.
- **Do not assert a cause for R0 the A/B did not establish.**

## Files to Edit

`.github/workflows/reusable-release.yml` (build-args, `secrets:`, `provenance: mode=min`, BuildKit
pin, positive-control annotation, comment rewrite, pre-build scanner step, attestation gate before
cosign, verdict-carrying failure email, break-glass) · `apps/web-platform/Dockerfile` (drop ARG,
secret mount, comments) · `.github/workflows/ci.yml` (scanner step in `credential-path-guard`) ·
`.github/actions/bot-pr-with-synthetic-checks/action.yml` (Phase-4 reproduction) ·
`scripts/required-checks.txt` (re-derived intersection comment) ·
`plugins/soleur/test/required-checks-canonical-parity.test.sh` (Test 9) · `scripts/test-all.sh` ·
`AGENTS.md` + `AGENTS.rules.md` · `plugins/soleur/agents/engineering/review/security-sentinel.md` ·
the six consumer workflows (repoint to the split identities) ·
`apps/web-platform/server/inngest/functions/cron-community-monitor.ts` (if it names the secret) ·
`.github/workflows/apply-web-platform-infra.yml` + `scripts/sentry-issue.sh` (false 403 comments) ·
`knowledge-base/legal/article-30-register.md` · `knowledge-base/legal/compliance-posture.md` ·
`knowledge-base/engineering/operations/runbooks/sentry-issue-read.md` (re-minting section).

## Files to Create

`scripts/lint-buildarg-secret-channels.py` · `scripts/lint-buildarg-secret-channels.test.sh` ·
`scripts/buildarg-key-allowlist.txt` · `tests/fixtures/provenance/*.json` ·
`knowledge-base/engineering/architecture/decisions/ADR-172-*.md` ·
`knowledge-base/legal/audits/2026-08-10-sentry-provenance-buildarg-disclosure.md`.

## Alternative Approaches Considered

| Alternative | Verdict | Reason |
| --- | --- | --- |
| `provenance: false` | Rejected | Discards supply-chain provenance; also breaks the fail-closed gate. |
| Post-hoc attestation redaction | Rejected | Published at push time. |
| `^SENTRY_` or any prefix-only allowlist | Rejected | Verified to admit credential-shaped keys. |
| Two separate scripts | Rejected on review | Identical verdict function; duplicated the security-boundary allowlist across two languages. |
| Standalone required status check (+ `.tf`, SSOT parity, CODEOWNERS round) | Rejected on review | The CODEOWNERS benefit is a measured no-op; the merge-queue hazard is stale; the `credential-path-guard` step blocks from the first run. |
| Splitting the PR (fix first, gates later) | **Not taken — dissolved.** | Its motivation was the live-token window. Phase 1 closes that window pre-merge without splitting, so the operator's "a merged PR" direction stands. |
| Stage-then-promote (quarantine tag → inspect → `imagetools create`) | Considered; not taken | Would make the gate preventive for one retag, but `push: false` breaks four coupled things at once — attestations cannot be loaded into the daemon, `outputs.digest` (consumed by cosign and the zot digest-match) changes meaning, the gha cache export path changes, and a `crane push` would produce a different digest from the one cosign signed. The pre-build scanner (4.4) captures most of the benefit for one step. Worth revisiting as its own change. |
| preflight Check 13 | Rejected on review | Could never surface what the required CI job will not, nor SKIP meaningfully. |
| semgrep / `skill-security-scan` / gitleaks / trufflehog / hadolint / docker scout | Rejected, not deferred | Each checked against "does it detect a secret expression reaching a build-args block?" — gitleaks and trufflehog match secret *values* (a `${{ secrets.X }}` reference has zero entropy); hadolint has no such rule and does not read workflows; docker scout is CVE/policy and subscription-gated; semgrep has no CI job and its agent filters out Dockerfiles and YAML. |
| Narrow one shared token | Rejected on review | Cannot satisfy Terraform write and release-only read simultaneously; and it leaves the real defect — an IaC-admin credential doing source-map upload — in place. |
| Mint Article 30 PA-36 | Rejected | A credential-handling defect is not a processing activity. Amend PA-8 §(g). |
| Defer rotation to the operator | Rejected | API mint path is documented and worked; Playwright is the fallback. |
| `doppler_secret` Terraform for the rotation | Rejected | Would persist live bearer tokens in `terraform.tfstate`. |

## Decision Challenges (headless — surfaced, not auto-applied)

Persisted to `knowledge-base/project/specs/<branch>/decision-challenges.md` for `/ship` to render:

- **DHH proposed splitting this into two PRs** (fix+gate, then scanner/rule/ADR/legal) to shorten the
  live-credential window. That changes the operator's stated "a merged PR" direction, so it is a
  User-Challenge rather than a mechanical simplification. **Recommendation: decline** — Phase 1
  closes the window pre-merge, which achieves the same containment without changing the deliverable.
  Recorded so the operator can overrule.
