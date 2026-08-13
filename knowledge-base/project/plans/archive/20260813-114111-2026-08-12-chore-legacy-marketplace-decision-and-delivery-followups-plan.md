---
title: "chore: close the legacy-marketplace decision and the post-delivery follow-ups"
date: 2026-08-12
slug: chore-legacy-marketplace-decision-and-delivery-followups
branch: feat-one-shot-7489-7490-marketplace-retire-delivery-followups
issue: 7489
closes: [7489, 7490]
type: chore
lane: cross-domain
domain: engineering
priority: p2
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-08-12. Two rounds: a four-agent plan review (architecture, spec-flow, simplicity,
scoped strong-model advisor), then a deepen pass (verify-the-negative sweep, post-edit self-audit,
spec-flow re-check). Every finding below was verified against the repo or the live CLI before it was
applied — none was taken on assertion.

### What the rounds changed

1. **The canary became a second job, not extra steps.** The first draft assumed it could append to the
   drift step's `findings` array; that array and `sanitize()` are shell locals of the `check` step, and
   `scripts/marketplace-drift-check.test.sh` extracts that step and re-executes it hermetically without
   network. Verified count-neutral against `c4-count-parity.test.sh`, which counts workflow *files* and
   *distinct* slug values.
2. **The alarm was blind to the thing it was being given.** The filing step and the heartbeat both gate
   on `steps.check.*` only, so a canary-only failure would have filed nothing and checked in `ok`. Both
   expressions are now in scope, and mutation row 8 tests it.
3. **The content assertion split into three independent conjuncts.** A declared-subset byte comparison
   cannot see under-delivery — which is the defect that produced ADR-182 (64 skills against 96). The
   reference is now pinned at the delivered commit (measured working, byte-identical), freshness is
   exact rather than tolerance-bounded, and completeness compares sets with a cardinality assertion.
4. **The metadata boundary was cosmetic and is now honest.** Measurement showed `claude plugin list
   --json` is a projection of `installed_plugins.json` — mutating the file changed the CLI output
   verbatim. The exclusion is now over *fields*, not files, and the runbook's own "content, not
   metadata" block is corrected for the same reason.
5. **The decision changed hands.** The legacy install is project-scoped to a different repository, so
   migrating it is not this repo's tidy-up. Headless execution was withdrawn, the recorded decision was
   made non-provisional so the tracker closes honestly, and the arms are conditioned by a three-valued
   rule because Phase 2 can return unverified as well as true or false.
6. **A pre-existing observability defect surfaced and is repaired here.** `actionlint` reports the
   heartbeat step missing three inputs its composite declares required — the very check-in this plan's
   liveness signal depends on. Confirmed byte-identical to `origin/main`; fixed in Phase 4.5b because
   shipping a canary whose alarm cannot check in reproduces the failure the canary exists to catch.

### New considerations discovered

- The CLI carries **seven** `CLAUDE_CODE_PLUGIN_*` variables, two of which bear directly on the failure
  modes both trackers describe — the trackers name one.
- The steady-state refresh is `git pull`, not a clone, so the standing cost is small and the **tail
  risk** is the real subject.
- The settings precedence chain has more declaration sites than one machine reveals; the probe is
  written against the chain and mutation-tests the managed-policy and project-scope sites.

---

## Overview

Two consolidated trackers left open by the plugin-delivery fix that merged earlier today (ADR-182).
The first asks whether the monorepo marketplace entry is retired or deliberately kept. The second
carries three post-delivery follow-ups: an install canary that asserts delivered content rather than
recorded metadata, a measurement of whether a settings-file environment block reaches the plugin git
path and the background refresh, and the filing of this repository's measured evidence against the
upstream CLI defects.

Plan-time measurement changed the shape of both, and a four-agent review round changed it again. Four
readings are load-bearing and each one moved a decision:

- The refresh is an incremental `git pull`, not a clone per cycle. The recurring cost is small; the
  tail risk is what matters.
- `claude plugin install` needs no credentials at all, so the canary's blocking feasibility question
  is answered yes.
- The one legacy install is project-scoped to **a different repository**, so removing it is not a
  tidy-up of this repo's own state and is not something to do unasked.
- `claude plugin list --json` is a projection of `installed_plugins.json`, so an assertion cannot
  escape the metadata by reading the CLI instead of the file. What it can escape is letting any
  metadata *field* into the verdict.

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec directory existed
> for this branch at plan time.

## Research Reconciliation — Issue Claims vs. Measured Reality

Every row was measured during planning on CLI `2.1.228`, git `2.53.0`, on the operator machine or in
a scratch `HOME`. Raw readings are reproduced in `## Research Insights`.

| Claim (as filed) | Measured reality | Plan response |
|---|---|---|
| #7489 title: the entry "still clones 181 MiB" | **The steady-state refresh is an incremental `git pull`, not a clone.** The legacy checkout's reflog reads: `clone` once on 2026-08-11 19:10, then `pull origin HEAD: Fast-forward` at 2026-08-12 10:11, 15:44 and 20:59. Corroborated by the CLI bundle's own strings — `git pull failed, will re-clone:` and `git pull failed, keeping existing clone (CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE)`. The 181 MiB clone is the **add** path and the **re-clone-after-pull-failure** path. | Re-state the standing cost as three separate things: 378 MiB held indefinitely, one `git pull` per refresh, and a latent destructive path on any pull failure. The tail risk — not the recurring cost — is what makes the entry worth a decision. Correct ADR-182's Context, which states the clone as the refresh mechanism. |
| #7489: closing needs "confirmation that no install remains on the `soleur@soleur` id" | **Currently false, and the install is not where the tracker assumes.** `installed_plugins.json` records `soleur@soleur` at `scope: project`, **`projectPath: /home/jean/git-repositories/skouer/Skouer`** — a different repository from this one — `version: 0.0.0-dev`, `gitCommitSha: 98ad03aa…`. The registration lives in **two** files: `~/.claude/plugins/known_marketplaces.json` and `extraKnownMarketplaces` in `~/.claude/settings.json`, each carrying its own `autoUpdate: true`. `~/.claude/plugins/marketplaces/soleur` is **378 MiB** (`.git` 122 MiB, shallow). No `.bak` present. | The condition is not a tidy-up of this repo's state. Migrating it changes the tooling of another project, which is a decision rather than a chore. Ship the probe and the recorded decision; offer the migration as the one question. |
| #7489 implied: the legacy install is load-bearing for the operator | Here it is not — `~/.claude.json` `pluginUsage` records `soleur@inline` at **29,814** uses against `soleur@soleur` at **5**, and this session's `claude plugin list` reports the legacy plugin `enabled: false`. **But `enabled` is evaluated per project**, and the install's own project is a different one, so its state there was not observed. | Do not infer that the install is idle in its own project. The question names the project explicitly and the plan does not assume the answer. |
| #7489: "autoUpdate not remotely revocable" | True and unchanged remotely. **Locally it persists**: `autoUpdate: false` hand-written into a scratch `known_marketplaces.json` survived a subsequent CLI invocation with `lastUpdated` unchanged. Whether it *suppresses the refresh* was **not** established, and `autoUpdate: true` exists in two files so which one the refresh reads is also unestablished. | Persistence measured; suppression and authoritative-site both **unverified** and measured in Phase 2. Arm B does not ship until they resolve. |
| #7489: on failure the refresh destroys the checkout, with no mitigation named | **A client-side mitigation exists in the CLI.** `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE` selects `keeping existing clone` over `will re-clone` + `.bak`. Upstream 42306 (closed) records it as undocumented. | Measure whether it can be made persistent, then either ship it or record that it cannot be. Documenting a mitigation nobody deployed is the failure mode to avoid. |
| #7490.1: "can a scheduled CI job run `claude plugin install` at all (the CLI needs credentials)" | **Answered yes, measured.** Clean `HOME`, `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `CLAUDE_CODE_OAUTH_TOKEN` all unset, `CI=true`, no TTY: `marketplace add` rc=0 in **7 s**, `install --scope user` rc=0 in **20 s**. Delivered tree carried `scripts/lib/session-state.sh` and **96** skill directories. | The blocking question is discharged at plan time. The canary is buildable and consumes no secrets. |
| #7490.1 unstated: the CLI reaches GitHub the same way CI would | **It does not, by default.** The CLI constructs an **SSH** remote from `owner/repo` — `Cloning via SSH: git@github.com:…`. On the operator machine that is silently rewritten by `~/.gitconfig`'s `url."https://github.com/".insteadOf`. With the rewrite removed and SSH forced to fail fast, the CLI logged `SSH clone failed, retrying with HTTPS` and still succeeded in 7 s. | The canary sets `CLAUDE_CODE_PLUGIN_PREFER_HTTPS` so the SSH attempt is skipped rather than survived. Untreated, that attempt is the stall in upstream 77927. |
| #7490.2: `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` is the knob | **It is one of seven.** `grep -aoE 'CLAUDE_CODE_PLUGIN_[A-Z0-9_]+'` over the CLI bundle returns exactly: `_BINARY_ASSETS`, `_CACHE_DIR`, `_GIT_TIMEOUT_MS`, `_KEEP_MARKETPLACE_ON_FAILURE`, `_PREFER_HTTPS`, `_SEED_DIR`, `_USE_ZIP_CACHE`. | Measure the two that bear on the failure modes; record the rest from the bundle without inventing behaviour. |
| #7490.3: "at least three undocumented identity-recording modes" | **The modes are not exclusive, which is the sharper finding.** A scratch keyless install recorded `version = 43c7d3d79542-31fddb37` (a compound: the 12-char prefix of `main` HEAD plus an 8-char half that is **not** the marketplace repo HEAD `d0dc506e…` and is unidentified) with `gitCommitSha` carrying the full 40. The legacy install simultaneously carries `version: 0.0.0-dev` **and** a valid `gitCommitSha`. So identity lands in two independent fields with undocumented population rules, and only the `version` string is read by the update comparator. | Report it as "two fields, undocumented and non-exclusive population, one comparator" rather than counting modes. Record the 8-char half as unidentified rather than guessing. |
| #7490.3: file/attach upstream | 76882 **open**, 2 comments, both from a third party. 77927 **open**, **0 comments**. Upstream already carries a DOCS family: 58859 open (`_PREFER_HTTPS`), 42306 closed (`_KEEP_MARKETPLACE_ON_FAILURE`), 28040 closed (`_GIT_TIMEOUT_MS`). | Search-before-file with an explicit contradiction rule. Do not open a DOCS issue on a variable already tracked. |
| Implicit: the canary can share the drift job's step state | **It cannot.** `findings=()` and `sanitize()` are shell locals of the `check` step's `run:` block and do not survive a step boundary. Separately, `scripts/marketplace-drift-check.test.sh` (registered in `scripts/test-all.sh`) extracts that step by id and executes it hermetically with no network — canary logic placed inside it would run there with no `claude` binary. | The canary is a **second job**, publishing via job outputs. Verified count-neutral against `c4-count-parity.test.sh`. |
| Implicit: `claude plugin list --json` is a different authority from `installed_plugins.json` | **It is a projection of it.** Mutating `installed_plugins.json` changed the `plugin list --json` output verbatim (a sentinel version and installPath both appeared). The CLI adds only `id` and `enabled`. | Restate the exclusion honestly: no metadata **field** may participate in the content verdict. `installPath` is a location, and a stale record names an older cache directory, which fails closed. |
| Implicit: nothing in CI installs the published plugin | `test-pretooluse-hooks.yml` **does** — `plugin_marketplaces: …/soleur-marketplace.git`, `plugins: soleur@soleur-marketplace` — but it is `workflow_dispatch:`-only, asserts hook behaviour rather than content, and consumes `ANTHROPIC_API_KEY`. | Named in the Cut List as prior art and rejected as a substitute. |

## Property List and Cut List

**Property List** — what the two trackers are actually for, restated as observable outcomes.

- **P1.** #7489 reaches a terminal state: the decision about the legacy channel is recorded with its consequences named, and the machine state it applies to is on the record.
- **P2.** Any machine can be asked, mechanically, whether it still resolves to `jikig-ai/soleur`, across every site a registration or install can live in.
- **P3.** A fresh install from the published channel is continuously asserted to carry the plugin content that `main` serves — including **completeness**, since the historical defect was under-delivery (64 skills against 96), not corruption.
- **P4.** The runbook's guidance states measured facts, labels the unmeasured, and does not instruct a user into the destructive path.
- **P5.** This repository's measured evidence reaches upstream, where it can change the CLI's behaviour.

**Cut List** — mechanisms removed before any of them were researched or designed.

| Mechanism | Property it claimed | Why cut |
|---|---|---|
| GitHub traffic API as a population signal for P2 | P2 | Measured and rejected. `jikig-ai/soleur` 14-day traffic is `count=69,838 uniques=1,238` — CI-dominated and unable to distinguish an installer from a runner. `jikig-ai/soleur-marketplace` reads `count=0 uniques=0` *despite* real installs performed against it during this planning session. A signal that did not register a known event cannot support a negative claim. |
| A new dedicated canary workflow | P3 | The existing workflow already carries the cron, the `sentry-heartbeat` check-in, the issue file/close loop and the serialised concurrency group. A new workflow moves `c4-count-parity.test.sh`'s C1 (10→11) and C2 (6→7), needs a new `sentry_cron_monitor` and a full-root `apply-sentry-infra.yml` apply. A second **job** in the existing file is count-neutral — C1 counts files, C2 counts files, C5 counts distinct slug values — and was verified as such. |
| Canary logic as extra **steps** in the existing `check` step or job | P3 | Not implementable: `findings=()` and `sanitize()` are shell locals of that step. And `scripts/marketplace-drift-check.test.sh` extracts the `check` step by id and runs it hermetically without network, so canary logic inside it would execute there with no `claude` binary. |
| Scheduling `test-pretooluse-hooks.yml` instead of building a canary | P3 | Nearest existing mechanism; it does install the published plugin. Rejected because it asserts hook behaviour rather than content and runs through `claude-code-action` with `ANTHROPIC_API_KEY`, where the measured alternative needs no credentials. Kept as prior art. |
| Retiring the entry (deleting the root manifest's `plugins[0]`) | P1 | Measured to buy nothing for a stranded install: the marketplace checkout is cloned *before* the manifest is read, so removing the manifest does not reduce anyone's clone cost. It would only block new installs on the slow path, which the README already de-advertises. Recorded as a rejected alternative in the ADR, not as a deliverable. |
| A byte-comparison of a *declared subset* of delivered files | P3 | Cut during review. The historical defect was under-delivery; a subset comparison goes green while 30 skill directories are missing. Replaced by a full recursive file-list comparison with a cardinality assertion. |
| A separate upstream DOCS issue for the identity-recording modes | P5 | The 8-char half of the compound version is unidentified. A new issue on a third party's repo describing a mode that cannot be explained is noise; the evidence folds into the 76882 comment, which is the same subject. |
| A soak-gated follow-through | — | No criterion here is time-gated. **But the follow-through mechanism itself is retained** for the post-merge criteria, with `earliest` set just after merge rather than after a soak window — rejecting the soak must not remove the only carrier for post-merge verification. |

## Research Insights

### Measured readings taken during planning

All commands were run non-interactively. Scratch-`HOME` runs wrote nothing to the operator's
`~/.claude`; every `installPath` observed resolved under the temporary directory.

- **Live install state** — `installed_plugins.json` → `soleur@soleur`: `scope: project`, `projectPath: /home/jean/git-repositories/skouer/Skouer`, `installPath: <home>/.claude/plugins/cache/soleur/soleur/0.0.0-dev`, `version: 0.0.0-dev`, `gitCommitSha: 98ad03aa8c06044f1eb74fbeb9d59f156be2f798`, `installedAt: 2026-08-11T16:43:42Z`.
- **Registration lives in two files** — `~/.claude/plugins/known_marketplaces.json` → `soleur → {source: {github, jikig-ai/soleur}, autoUpdate: true}`; `~/.claude/settings.json` → `extraKnownMarketplaces.soleur → {source: {github, jikig-ai/soleur}, autoUpdate: true}`. `enabledPlugins` in the same file carries **no** soleur key. `soleur-marketplace` is registered in neither.
- **Legacy footprint** — `du -sh ~/.claude/plugins/marketplaces/soleur` = **378 MiB**; `.git` = 122 MiB with `.git/shallow` present; `cache/soleur` = 13 MiB. No `soleur.bak`.
- **Refresh mechanism** — reflog shows one `clone` (2026-08-11 19:10) and three `pull origin HEAD: Fast-forward` entries on 2026-08-12. Not sparse (`.git/info/sparse-checkout` absent); `remote.origin.url` is the HTTPS form.
- **Unauthenticated install** — scratch `HOME`, all Claude credential variables unset, `CI=true`: `marketplace add jikig-ai/soleur-marketplace` rc=0 / 7 s; `install soleur@soleur-marketplace --scope user` rc=0 / 20 s. Resolved `installPath` carried `scripts/lib/session-state.sh` and 96 skill directories.
- **Recorded identity** — `version: "43c7d3d79542-31fddb37"`, `gitCommitSha: "43c7d3d79542e0909b3825ec17a3d58e193524de"`. `git ls-remote https://github.com/jikig-ai/soleur.git HEAD` = the same 40-char SHA. `git ls-remote …/soleur-marketplace.git HEAD` = `d0dc506e9cb698c8cbb3c8c0495de0d7fe802efe`, which does **not** match the `31fddb37` half.
- **SHA-pinned reference fetch works, and matches** — `curl https://raw.githubusercontent.com/jikig-ai/soleur/<delivered-sha>/plugins/soleur/.claude-plugin/plugin.json` returned HTTP 200 / 1027 bytes, and its `sha256` equalled the delivered copy's byte for byte. The freshness half held too: the delivered SHA equalled `main` HEAD.
- **`plugin list --json` is a projection** — mutating `installed_plugins.json` to a sentinel `version` and `installPath` changed `claude plugin list --json` output verbatim; restoring the file restored the output.
- **Transport** — `Cloning via SSH: git@github.com:…`; `~/.gitconfig` carries `[url "https://github.com/"] insteadOf = git@github.com:`. With `GIT_CONFIG_GLOBAL=/dev/null` and a fail-fast `GIT_SSH_COMMAND`: `SSH clone failed, retrying with HTTPS`, rc=0, 7 s.
- **Timeout instrument** — `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=1` → `✘ Failed to add marketplace: … Git clone timed out after 0s`, rc=1, 4 s. Deterministic, cheap, unambiguous; this is Phase 2's instrument.
- **`autoUpdate: false` persistence** — hand-written into a scratch `known_marketplaces.json`, it survived a subsequent `claude plugin list` with `lastUpdated` unchanged. Persistence measured; **suppression not measured**.
- **Env family** — seven names, verbatim above. Bundle context shows `PREFER_HTTPS` is read as `CLAUDE_CODE_REMOTE || CLAUDE_CODE_PLUGIN_PREFER_HTTPS`, and `USE_ZIP_CACHE` requires `CLAUDE_CODE_PLUGIN_CACHE_DIR` (`throw Error("Plugin zip cache is not enabled")`).
- **Settings sites the bundle knows about** — `settings.json`, `settings.local.json` and `managed-settings.json` all appear in the 2.1.228 bundle alongside `extraKnownMarketplaces` and `enabledPlugins`. The plan-time five-site enumeration was two-plus sites short; Guard 2 is written against the precedence chain rather than that list.

### Repository facts the phases depend on

- `.github/workflows/scheduled-marketplace-drift.yml` — one job `drift-check`, `timeout-minutes: 5`, `permissions: {contents: read, issues: write}`, `concurrency: scheduled-marketplace-drift` with `cancel-in-progress: false`, no `actions/checkout` by design. Its filing step gates on `steps.check.outcome == 'success' && steps.check.outputs.verdict == 'MISMATCH'`; its heartbeat status expression gates on `steps.check.*` only. **Both are blind to a canary-only failure as written.** Its header comment is a load-bearing gate-override rationale.
- `scripts/marketplace-drift-check.test.sh` — registered at `scripts/test-all.sh` line 700. Extracts the `check` step's `run:` body by `id` and executes it under a hermetic harness with a `curl` shim and no network. It also asserts that no `secrets.*` other than `GITHUB_TOKEN` appears, and that any step condition referencing `steps.check.outputs` also carries `steps.check.outcome == 'success'`.
- `plugins/soleur/test/c4-count-parity.test.sh` parses hard-coded counts out of `model.c4` prose against live derivations: C1 = heartbeat **workflow files** (10), C2 = those with a `schedule` key (6), C4 = `sentry_cron_monitor` resources (55), C5 = distinct `monitor-slug:` values (11). A second job in an existing file with no new slug moves none of them. `c4-model-freshness.test.sh` requires the committed `model.likec4.json` to match a fresh `scripts/regenerate-c4-model.sh` render.
- `scripts/test-all.sh` line 1175 auto-globs `plugins/soleur/test/*.test.sh`, `plugins/soleur/scripts/*.test.sh`, `.claude/hooks/*.test.sh`, `scripts/lib/*.test.sh` and others — but **not** repo-root `scripts/*.test.sh`, which are enumerated by hand (164 `run_suite` lines). `scripts/lint-orphan-test-suites.sh` is itself a registered blocking suite that walks `scripts/*.test.sh`, so forgetting registration reds CI rather than passing silently.
- `model.c4` carries **three** occurrences of the "sole/only control" claim: the `soleurMarketplace` element description, the `github -> soleurMarketplace` edge, and — inside the count-anchored clause block — the `github -> sentry` edge.
- `knowledge-base/engineering/architecture/principles-register.md` AP-021, enforced by `scripts/lint-diagnosis-claims.sh`: a CI-emitted message may only name a cause the job measured.
- `scripts/check-adr-ordinals.sh` exists and gates ADR ordinals.
- Follow-through directive: `<!-- soleur:followthrough script=scripts/followthroughs/<name>-<issue>.sh earliest=<ISO> secrets=<NAME> -->` plus the `follow-through` label; exit 0 = PASS, 1 = FAIL, anything else = TRANSIENT. `scripts/followthroughs/` holds 62 files.
- No script anywhere reads local plugin install state. Searched `scripts/` and its subdirectories, `plugins/soleur/scripts/`, every `plugins/soleur/skills/*/scripts/` directory (42 at plan time), `.claude/hooks/`, `tests/`, `.github/`. The `claude plugin list --json` invocations that exist are runbook and README prose.
- The runbook's `--sparse` guidance lives under **Symptom 2**, headed "If the legacy channel must be kept, use `--sparse` rather than raising the timeout" — not in the persistence section. The same undifferentiated advice appears in `README.md` and `plugins/soleur/README.md`.
- Root `.claude-plugin/marketplace.json` — `plugins[0]` is keyless; the top-level `"version": "1.0.0"` is the manifest-format version.

### Institutional learnings that constrain this plan

- `knowledge-base/project/learnings/2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md` — a suite can be green while the workflow never reaches the code under test. **Constraint:** the canary logic lives in a committed script and a static wiring gate asserts the workflow invokes it.
- `knowledge-base/project/learnings/2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md` and `.../2026-08-03-the-verification-i-shipped-could-not-fail-and-my-instrument-measured-the-wrong-machine.md` — assertions certify something adjacent to what they name. **Constraint:** this plan reproduced that class in its own first draft (a filing gate blind to the canary) and the fix is explicit in Phase 4.
- `knowledge-base/project/learnings/integration-issues/2026-04-29-webpack-chunk-relocation-invalidates-bundle-content-canary.md` — a content canary anchored on a hardcoded path breaks silently. **Constraint:** the compared set is the delivered tree's own recursive listing, not a hand-written list.
- `knowledge-base/project/learnings/workflow-issues/2026-06-01-unverified-inference-stated-as-fact-against-prod-writes.md` — inference must not carry fact-grade confidence. **Constraint:** every runbook claim is labelled, and arms that depend on an unresolved measurement do not ship until it resolves.
- `knowledge-base/project/learnings/2026-06-12-gh-search-api-empty-cross-repo-under-in-action-app-token.md` — `gh … --search` returns empty cross-repo under an in-action token. **Constraint:** the upstream duplicate search uses the List API plus client-side `jq`, in-session.
- `knowledge-base/project/learnings/best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply.md` — each new sentinel needs a runbook row in the same change.
- `knowledge-base/project/learnings/2026-06-16-adr-c4-update-is-a-plan-deliverable-not-a-deferred-issue.md` — the ADR/C4 edit ships with the change.
- `knowledge-base/project/learnings/2026-07-30-one-blocked-mechanism-is-not-a-blocked-capability.md` — suffix-variant siblings are the trap. **Applied:** the seven-member env family was enumerated from the defining binary, and the settings-site family from the same binary after review showed the plan-time list was short.

### Premise Validation

Both target issues are `OPEN` and `type/chore`, titles as quoted. ADR-182, `knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/measurements.md` (§1.0, §2B, §1.9, §1.6/2B.6, §1.2/1.3, §1.4), the recovery runbook and the drift workflow all exist and were read in full. Upstream `76882` and `77927` were fetched and are both open with the titles the tracker describes. No spec directory existed for this branch. Nothing cited was stale; the stale material was inside the issue bodies, and — after review — inside this plan's own first draft, which is recorded in the table above rather than quietly corrected.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 64 issues; none of their bodies contains `.github/workflows/scheduled-marketplace-drift.yml`, `scripts/marketplace-drift-check.test.sh`, `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md`, `ADR-182`, `scripts/plugin-`, `apps/web-platform/infra/sentry/cron-monitors.tf`, `knowledge-base/engineering/architecture/diagrams/model.c4`, or `README.md`.

## User-Brand Impact

**If this lands broken, the user experiences:** a recovery runbook that destroys their working plugin
checkout. The runbook's Symptom 2 recommends `claude plugin marketplace add jikig-ai/soleur --sparse …`
as the mitigation for a stranded legacy install, and the CLI's own string `sparse-checkout reconcile
requires re-clone:` sits directly beside `.bak` in the same code path — so applying `--sparse` to an
*existing* plain checkout appears to force the re-clone, which is the 329 s operation that cannot finish
inside the 120 s default. A user following the runbook during an outage would trigger exactly the
destruction the runbook exists to prevent. The same undifferentiated advice appears in both READMEs.

**If this leaks, the user's workflow is exposed via:** the upstream defect reports. They are public
posts on a third party's repository built from readings taken on the operator's own machine — home
directory paths, the layout and names of unrelated local repositories (the legacy install's
`projectPath` names one), install timestamps and machine-identifying detail all appear verbatim in the
raw measurements.

**Brand-survival threshold:** single-user incident.

The threshold is what forces three things: the `--sparse` correction is targeted at the exact text a
user reads mid-outage rather than at the file in general; the scrub gate covers all four exposure
categories and is asserted against the body actually posted, not only the local copy; and the migration
of another project's install is asked rather than assumed.

## The one operator decision

One genuine choice remains. Plan-time measurement narrowed it and also changed who it belongs to: the
legacy install is **project-scoped to `/home/jean/git-repositories/skouer/Skouer`**, a different
repository from the one this pipeline runs in. Migrating or removing it changes that project's tooling,
and this session cannot observe whether the plugin is enabled or in use there. That is a judgment call,
not a chore, and it is the single question this plan surfaces.

- **A — migrate that project onto the published channel.** The four commands measured green at the
  default timeout, run with `--scope project` from that project's directory, then reclaim the orphaned
  cache. Reversible in one documented command measured at 78 s.
- **B — keep the registration, mitigated.** Set `autoUpdate: false` at whichever file Phase 2 measures
  as authoritative, and `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE` if Phase 2 finds a persistent
  mechanism for it.
- **C — keep it as it is,** with the tail risk recorded as accepted and unmitigated.

**Every arm is conditional on Phase 2, and the conditioning rule is three-valued because Phase 2 is.**
Phase 2 can return `measured-true`, `measured-false`, or `unverified` for each mechanism, and the
distinction matters: 2.3 and 2.4 share one instrument (a backdated `lastUpdated` fixture), so a single
instrument failure leaves *both* of arm B's mechanisms unverified rather than falsified. A binary
"withdraw if falsified" rule would then offer arm B as a live choice resting on two unmeasured
mechanisms — the exact shape the cited "unverified inference stated as fact" learning names. The rule:

| Phase 2 verdict for an arm's mechanism | Phase 3 treatment |
|---|---|
| `measured-true` | Offer the arm normally. |
| `measured-false` | **Withdraw the arm.** If every mechanism an arm depends on is falsified, it collapses into arm C and is not presented. |
| `unverified` | Offer the arm **with the unverified label carried in the arm's own text**, naming which mechanism is unmeasured and what would measure it. Never present it as equivalent to a measured arm. |

Arm A is conditioned too, not just arm B. Phase 2.7 measures whether `marketplace remove` cleans both
declaration sites; if it does not, arm A's "no resolver remains" outcome is false as stated, and the arm
is offered only with the additional hand-removal step named — or withdrawn if that step is not
established.

**Mode handling.** Two independent signals make a session headless, and the plan states both because the
first is not sufficient. (i) The repo's executable classifier, `[[ ! -t 0 ]] && [[ -n "${CLAUDECODE:-}" ]]`
(`.claude/hooks/session-rules-loader.sh`) — a **conjunction**, not a disjunction. (ii) Execution inside a
Task subagent, which is headless regardless of the TTY because `AskUserQuestion` cannot reach an operator
from there. **A `/soleur:one-shot` context or a plan-file-path argument is not by itself a headless
signal**; treating it as one would make the attached branch dead code in exactly the pipeline that runs
this plan. Phase 3 records which signal fired. Attached: ask once via `AskUserQuestion`, execute the
answer, record it. Headless: **execute no arm**; append the question, Phase 2's verdicts and the measured
`projectPath` to `knowledge-base/project/specs/<branch>/decision-challenges.md`, which `ship` renders into
the PR body and files as an `action-required` issue.

**The recorded decision is not provisional, and that is what makes the close honest.** #7489's own second
closing condition is "a decision to leave the entry live indefinitely with that consequence accepted and
recorded". That decision is **taken** in this PR under every branch: the entry stays live, its consequences
are enumerated and accepted in the ADR amendment, and the machine state it applies to is committed as a
probe reading. Arms A and B are *additive cleanups an operator may choose later*, not competing answers
that would retract the acceptance — migrating one project's install afterwards does not make "the entry
stays live" false, because the entry and every other install remain. So the question Phase 3 asks is
"do you also want this project migrated?", not "which of three answers closes the issue". Both artefacts
are pre-merge; nothing about the close waits on the answer.

## Implementation Phases

Ordering is load-bearing in three places: the probe must exist and run **before** any arm executes, or
the pre-state evidence is destroyed by the thing it is evidence for; Phase 2 must precede Phase 3
because Phase 3 presents Phase 2's verdicts; and the canary's integration shape must be settled before
its script is written, because the shape determines how findings leave the job.

### Phase 1 — The legacy-resolver probe, and the pre-state reading

1. Write `scripts/plugin-legacy-resolver-probe.sh`. It reports every marketplace registration and every
   installed plugin that resolves to a target repository, defaulting to `jikig-ai/soleur`. Design points
   that are load-bearing rather than stylistic, each from Guard 2's Assembly:
   - It walks the CLI's settings **precedence chain**, not a frozen list: `known_marketplaces.json`,
     then `settings.json` / `settings.local.json` at user scope, the same pair at project scope, and
     the managed-policy file. It prints the resolved path and read status of every site it consults.
   - It uses a **two-stage predicate**. Stage one matches `source.repo` at registration sites and
     collects the set of local aliases pointing at the target. Stage two joins `installed_plugins.json`
     and `enabledPlugins` back through that alias set — neither carries a `repo` field, so a
     repo-predicate cannot be applied to them directly.
   - An alias it cannot resolve is reported as an **explicit unknown**, never as clean.
   - It emits the site **list**, not only a count, so a later-discovered site cannot silently shrink it.
   - It emits each registration's **`autoUpdate` value per site**. Without this the probe cannot
     distinguish "arm B executed" from "arm B silently no-op'd" — arm B's only machine write *is* an
     `autoUpdate` value, so its pre-state and post-state readings would otherwise be byte-identical. The
     same field is what Phase 2.4 needs to answer which site is authoritative.
2. Write `scripts/plugin-legacy-resolver-probe.test.sh` implementing Guard 2's mutation matrix against
   synthesized `HOME` fixtures. Fixtures are synthesized, never copied from the operator's machine.
3. Register both suites with explicit `run_suite` lines in `scripts/test-all.sh`.
4. Run the probe on this machine and commit the reading into
   `knowledge-base/project/specs/<branch>/measurements.md` as the dated pre-state, with home paths and
   unrelated repository names redacted.

### Phase 2 — The environment-variable family and the destructive paths, measured

Every arm uses a scratch `HOME` and the deliberately-tiny-timeout instrument validated at plan time
(`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=1` → `Git clone timed out after 0s`, rc=1, 4 s). A raised timeout
proves nothing, because success at the default is indistinguishable from success at the raised value;
only a value that *forces* failure is falsifiable.

1. **Control.** Confirm the instrument fires on the CLI version under test.
2. **Claim (a) — does a settings-file `env` block reach the plugin git path?** Scratch `HOME` whose
   `.claude/settings.json` contains `{"env": {"CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS": "1"}}` and no such
   variable in the process environment. Run `marketplace add`. A timeout failure means the block reaches
   the git path; a 7 s success means it does not.
3. **Claim (b) — does it reach the background refresh?** Same scratch `HOME`, marketplace registered
   with `autoUpdate: true` and `lastUpdated` backdated so a refresh is due. Start the CLI
   non-interactively and observe. **If the refresh cannot be triggered deterministically, record claim
   (b) as unverified and state what would verify it — do not infer it from claim (a).**
4. **`autoUpdate: false` suppression, and which file is authoritative.** The same backdated fixture with
   `autoUpdate: false` written to `known_marketplaces.json` only, then to `extraKnownMarketplaces` only,
   then to both. Persistence is already measured; suppression and the authoritative site are not, and
   arm B depends on both.
5. **`CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE`.** Force a pull failure on a scratch checkout and
   measure whether the checkout survives with the variable set and moves to `.bak` without it. Then
   measure whether it can be set persistently by whatever mechanism claim (a) established. If it can,
   Phase 3 ships it under every arm that keeps the registration; if it cannot, that is recorded and no
   arm claims it.
6. **The `--sparse` re-clone hazard.** This is the `single-user incident` finding and it currently rests
   on CLI strings rather than a measurement. On a scratch plain checkout, run
   `marketplace add … --sparse …` against the already-added entry and observe whether the checkout is
   re-cloned and whether a `.bak` appears. If the hazard cannot be reproduced, the runbook states it as
   unverified — the asymmetry favours warning.
7. **`marketplace remove` symmetry.** Add a marketplace, confirm it appears in both declaration sites,
   remove it, and check both again. Arm A's "no resolver remains" claim depends on removal cleaning
   both sites, which is inferred rather than measured today.
8. **The remaining four siblings** (`_USE_ZIP_CACHE`, `_SEED_DIR`, `_BINARY_ASSETS`, `_CACHE_DIR`) are
   recorded from the bundle in `measurements.md` with behaviour marked unmeasured. They do not enter the
   runbook — four knobs nobody will set, in a document read during an outage, is anti-value.
9. Append every reading to `measurements.md` with the command, the CLI version and the verdict.

### Phase 3 — The #7489 decision, recorded

1. Detect attachment and record which branch was taken.
2. Compose the question from `## The one operator decision`, **with Phase 2's verdicts attached and any
   falsified arm withdrawn**.
3. Attached: ask once, execute the answer, record it. Arm A runs the four commands with `--scope project`
   from the install's own `projectPath` — the runbook already carries that caveat and it is the caveat
   the first draft of this plan dropped — followed by the orphan-cache reclaim behind the runbook's
   existing print-then-delete guard. Arm B writes `autoUpdate: false` to the site Phase 2 measured as
   authoritative and ships `KEEP_MARKETPLACE_ON_FAILURE` if Phase 2 found a persistent mechanism. Arm C
   writes nothing to the machine.
4. Headless: execute nothing. Append the question and its verdicts to `decision-challenges.md`.
5. Re-run the Phase 1 probe and commit the post-state reading beside the pre-state one **under every
   arm and under the headless branch**, so the record shows machine state at the moment of the decision
   whether or not anything changed.
6. Record the decision — the arm, the reason, and the branch taken — in the ADR amendment written in
   Phase 6. Under the headless branch the recorded decision is arm C, explicitly marked as the default
   pending the operator's answer.

### Phase 4 — The delivery canary

Built as a **second job** in `.github/workflows/scheduled-marketplace-drift.yml`, verified count-neutral
against `c4-count-parity.test.sh` (C1 and C2 count workflow *files*; C5 counts distinct slug values).
A second job — not extra steps — is forced by three facts: `findings` and `sanitize()` are shell locals
of the `check` step; `scripts/marketplace-drift-check.test.sh` extracts that step and runs it hermetically
without network; and the canary needs a different privilege and timeout profile from a two-`curl` check.

1. Write `scripts/plugin-delivery-canary.sh`. It obtains a **version-pinned** Claude Code CLI, installs
   `soleur@soleur-marketplace` into a scratch `HOME` with `CLAUDE_CODE_PLUGIN_PREFER_HTTPS` set, resolves
   `installPath`, and makes **three independent assertions** — the same three conjuncts Guard 1
   quantifies over, in the same order:
   - **Completeness** — the delivered file list is compared as a **set** against the file list `main`
     serves under `plugins/soleur`, with an explicit cardinality assertion. The historical defect was
     under-delivery (64 skills against 96); a subset comparison cannot see it. Two parameters this
     conjunct needs and which are **not** yet measured, so Phase 4.2 measures them before the script is
     written: (i) **the reference-listing mechanism.** `raw.githubusercontent.com` serves single files,
     not directory listings — it is the only reference transport measured at plan time, and it cannot
     produce this list. The candidate is the unauthenticated GitHub trees API
     (`/repos/jikig-ai/soleur/git/trees/<sha>?recursive=1`), which must be probed for whether it works
     unauthenticated at the required depth and whether its rate limit is survivable from a shared runner
     IP. If it is not, the canary declares the completeness conjunct unavailable rather than silently
     downgrading to a subset. (ii) **the inherent delta.** The plan-time scratch install materialised 891
     files against 894 tracked; that delta is determined once, and each excluded path is named and
     justified individually. The exclusion set is capped at the measured delta and an AC asserts the cap.
   - **Integrity** — every delivered file's digest equals the digest of the same path fetched from
     `raw.githubusercontent.com/jikig-ai/soleur/<delivered-sha>/plugins/soleur/…`, pinned to the commit
     the install resolved. Pinning removes the race and the CDN-staleness ambiguity that comparing
     against `main` would introduce; both halves were verified working at plan time.
   - **Freshness** — the delivered commit **equals** `main` HEAD. There is no tolerance window: a
     tolerance that is never stated cannot be tested, and a loose one makes the conjunct inert, which is
     the failure splitting it out was meant to prevent. The one sanctioned exception is a merge landing
     between the install and the freshness read; the script detects that by re-reading `main` HEAD once
     and treating "HEAD moved during the run" as a distinct, non-alarming outcome rather than as
     staleness. Integrity without freshness passes forever on a stale self-consistent mirror; freshness
     without integrity passes on a correct label over wrong bytes.
   - **No metadata field participates in any verdict.** The exclusion is about fields, not files:
     `claude plugin list --json` is a projection of `installed_plugins.json`, so reading the CLI does
     not escape the metadata. `installPath` is consumed as a location and `gitCommitSha` only as the
     reference pin; neither `version` nor `gitCommitSha` may stand in for a content check. A stale
     record names an older cache directory, which fails the comparison closed.
2. Give it a `--self-test` mode exercising the assertion logic against a synthesized fixture with no
   network and no credentials. This is the `discoverability_test` command.
3. The script emits `compared=<N>` and `expected=<M>` and fails when they disagree or when `N` is zero,
   so "0 comparisons" can never read as "no differences".
4. Add the `canary` job: `permissions: contents: read`, its own `timeout-minutes` sized for CLI
   acquisition plus the measured ~27 s install, `actions/checkout` scoped to this job alone so the
   committed script is available without disturbing the `drift-check` job's deliberate no-checkout
   property. Findings leave the job as **job outputs**, sanitized on the way out.
5. Wire the verdict into the alarm. The filing step and the heartbeat currently gate on
   `steps.check.*` only, so a canary-only failure would file nothing and check in `ok` — the exact class
   this plan's own cited learning names. Both expressions change to consider the canary job's verdict
   via `needs:`, and every new condition referencing job outputs keeps the `outcome == 'success'`
   conjunct that `scripts/marketplace-drift-check.test.sh` asserts.
5b. **Repair the heartbeat step's missing inputs, which is a pre-existing defect in the liveness signal
   this plan depends on.** `actionlint` reports that the `Sentry check-in (final)` step omits
   `sentry-ingest-domain`, `sentry-project-id` and `sentry-public-key`, all three declared
   `required: true` by `./.github/actions/sentry-heartbeat`, while every sibling scheduled workflow
   passes them from secrets. The composite fail-softs when secrets are missing, so the symptom is a
   check-in that silently never lands rather than a red run — which would make the `## Observability`
   block's liveness claim false on arrival. Confirmed byte-identical to `origin/main`, so it is
   pre-existing rather than introduced here; it is fixed in this PR because the plan already edits this
   exact step's `status:` expression and because shipping a canary whose alarm cannot check in would be
   the same silent-observability failure the canary exists to prevent.
6. Branch the issue's title and remediation by finding class. AP-021 forbids a CI message naming a cause
   the job did not measure, and the existing title and its five remediation steps are all about the
   manifest; filing them for a `content_mismatch` would misdiagnose it.
7. Update the workflow's header rationale. Its "pure GH op … reads two public URLs unauthenticated"
   characterisation does not survive a job that downloads a CLI and materialises executable plugin
   content. The mitigating facts — no secrets, `contents: read` on that job, the payload coming from the
   protected monorepo — are stated rather than assumed.
8. Extend `scripts/marketplace-drift-check.test.sh` for the new job's structure, and write
   `scripts/plugin-delivery-canary.test.sh` implementing Guard 1's mutation matrix plus the static
   wiring assertion that the workflow invokes the script. Register the new suite explicitly.

### Phase 5 — Upstream defect reports

1. Search first, with the List API and client-side `jq` filtering rather than `--search`.
2. Compose four evidence sections in `knowledge-base/project/specs/<branch>/upstream-reports.md`, one
   per row of the routing table below, so the evidence is durable here regardless of what upstream does
   with it. Each cites only measured readings with the command that produced them. **Four sections, three
   postings:** the two rows routed to 77927 are posted as a single combined comment, because they are one
   root-cause argument split for readability rather than two independent reports. `upstream-reports.md`
   records the section-to-posting mapping explicitly so the counts in AC23 are unambiguous.
3. **Scrub, then read back.** Remove home paths in both `/home/...` and `~` form, the names and layout of
   unrelated local repositories, install timestamps and machine identifiers — all four categories named
   in `## User-Brand Impact`, not just the first. Re-read each body against the rule as a discrete step.
4. Route per this table. Contradictions between the table and step 1's search are resolved by rule, not
   by improvisation, and the rule covers both directions: **table says new issue, search finds an
   existing open one → comment on the existing one. Table says comment, but the target is closed or
   locked → open a new issue that links the closed one rather than reviving it.** Either way, record the
   contradiction and the substitution in `upstream-reports.md`. A contradiction is not a stall. Both
   directions are live shapes here: the table itself records 42306 and 28040 as already-closed siblings.

   | Evidence | Destination | Reason |
   |---|---|---|
   | Metadata does not follow delivered content, **plus** the two-field non-exclusive identity recording and the unidentified compound-version half | comment on **76882** | Exactly that issue's subject. The identity evidence folds in here rather than opening a separate docs issue for a mode that cannot yet be explained. |
   | 120 s default insufficient — 329 s measured, ~2.7× over, deterministic | comment on **77927** | Same failure family; 77927 has no comments and its ~60 s SSH stall is a narrower instance. |
   | SSH-first transport, with the HTTPS fallback reached only after the SSH attempt terminates | comment on **77927** | Root-cause contribution, measured both with and without the local rewrite. |
   | Failed refresh moves the checkout to `.bak`, and a later invocation deletes both | **new issue** | Fail-open and destructive, distinct from a timeout report, no existing issue found. |

5. Do not open a DOCS issue for `_PREFER_HTTPS` — 58859 already tracks it. If the search shows it open
   and the transport evidence adds to it, that posting gets its own section in `upstream-reports.md` so
   it is scrubbed and counted like the rest.
6. **Sending is operator-gated.** These are posts to a third party's public repository and they are this
   plan's named leak vector. Attached: send after the read-back, then fetch each posted body back via
   `gh api` and re-run the scrub grep against what upstream actually stores — the posted body is the
   artefact that leaks, and the local copy is not proof about it.
7. **Headless: send nothing, and make the unsent state visible rather than pending.** Commit the bodies,
   then append the send request to `decision-challenges.md` alongside Phase 3's question so `ship` files
   it as an `action-required` issue. The follow-through does **not** carry the send: it observes state
   and has no send capability, so treating it as the carrier would leave canary-green-plus-postings-unsent
   evaluating to neither PASS nor FAIL — a permanent TRANSIENT that re-runs forever and alarms never.
   The follow-through's role here is limited to *reporting* which routes landed; the operator-visible
   artefact is the issue.

### Phase 6 — Records: ADR, C4, runbook, disclosure

1. **ADR-182 amendment** — three in-place corrections, each a refinement rather than a new decision: the
   Context's "clones the whole monorepo" sentence, corrected to pull-first with the 181 MiB / 329 s
   figures kept attached to the add and re-clone paths where they remain true; Decision 5's disposition,
   recording the arm taken and the consequence accepted; and the rejected retire-the-entry alternative
   with its measured reason.
2. **ADR-182 Decision 6 — the second control.** The canary is not a refinement of Decision 5: it changes
   the control topology of the distribution path, it has its own alternatives (extra steps, second job,
   new workflow, scheduling the existing dispatch-only install), its own accepted risk (a job that
   downloads a CLI and materialises executable content in the same workflow as a write-capable token),
   and it bears directly on the posture recorded at #7493, whose Alternatives frame the space as
   detection versus prevention. It gets its own numbered Decision with those alternatives stated, so a
   reader arriving from #7493 finds the reasoning rather than an amendment about a different repo.
3. **C4.** Edit **all three** occurrences of the sole/only-control claim in `model.c4` — the
   `soleurMarketplace` element description, the `github -> soleurMarketplace` edge, and the
   `github -> sentry` edge. The third sits inside the clause block `c4-count-parity.test.sh` anchors on,
   so the edit must leave `check-ins from 10 workflows`, `6 GHA-\`schedule:\`-fired`, `Of 55 cron
   monitors`, `11 check in from here` and `44 from webapp` untouched. Then regenerate and commit
   `model.likec4.json` and run both C4 suites. No new element and no `views.c4` change: the canary is a
   new capability of the existing `github -> soleurMarketplace` edge.
4. **Runbook.** Three separate edits, in three different sections:
   - **Symptom 2** — correct the `--sparse` guidance, which is the text a stranded user reads and the
     reason this plan carries a `single-user incident` threshold. Distinguish the fresh-add case (safe,
     78 s, measured) from the existing-checkout case (forces a re-clone, which is the destructive path).
     Add `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE` as the standing mitigation for anyone who
     stays on the legacy channel, at whatever persistence Phase 2 established.
   - **Symptom 1** — the verification block says "on content, not on metadata" and then resolves its
     path from `claude plugin list --json`, which is a projection of `installed_plugins.json`. The
     assertions are content-based and correct; the path resolution is not independent of the metadata
     the block warns about. State that, and give a cross-check against the cache directory listing.
   - **Making the timeout persistent** — replace with Phase 2's verdicts, each labelled `measured:` or
     `unverified:`. **If claim (a) is measured false**, the honest replacement is that no persistent
     mechanism has been found and migration is the answer; that outcome is authorised here so the
     rewrite is not left without a sanctioned form. Add a row for every canary finding token.
5. **Disclosure.** Both READMEs carry the same undifferentiated `--sparse` advice and must receive the
   same fresh-add-versus-existing-checkout distinction. Then verify the corrected cost model against
   both: the README's "may time out" framing is right for a fresh add, and nothing may state or imply a
   clone per refresh.
6. **Follow-through enrolment for the post-merge criteria.** Write
   `scripts/followthroughs/plugin-delivery-canary-7490.sh` and enrol it on the tracker with `earliest`
   set just after merge — not a soak window. It exits 0 when the canary's most recent scheduled run is
   green and the upstream postings are recorded, 1 when the canary ran red, and anything else when the
   run has not happened yet. Without this the post-merge criteria have no carrier: both trackers close
   at merge, and nothing else would notice a red first run.

## Files to Create

- `scripts/plugin-legacy-resolver-probe.sh`
- `scripts/plugin-legacy-resolver-probe.test.sh`
- `scripts/plugin-delivery-canary.sh`
- `scripts/plugin-delivery-canary.test.sh`
- `scripts/followthroughs/plugin-delivery-canary-7490.sh`
- `knowledge-base/project/specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/measurements.md`
- `knowledge-base/project/specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/upstream-reports.md`
- `knowledge-base/project/specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/decision-challenges.md` (headless branch only; written by Phase 3.4)
- `knowledge-base/project/specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/tasks.md` (written by this skill's Save Tasks step, not by an implementation phase)

## Files to Edit

- `.github/workflows/scheduled-marketplace-drift.yml` — the `canary` job, the filing and heartbeat conditions, the branched issue title and remediation, the header rationale
- `scripts/marketplace-drift-check.test.sh` — extend for the new job's structure
- `scripts/test-all.sh` — explicit `run_suite` registration for both new suites
- `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md` — Symptom 1, Symptom 2 and the persistence section
- `knowledge-base/engineering/architecture/decisions/ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md` — amendment plus Decision 6
- `knowledge-base/engineering/architecture/diagrams/model.c4` — three occurrences
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` — regenerated
- `README.md` and `plugins/soleur/README.md` — the `--sparse` distinction and the cost model

## Guard Contract

### Guard 1 — Delivery canary (`scripts/plugin-delivery-canary.sh`)

**Property.** Installing `soleur@soleur-marketplace` on a machine with no prior Claude Code state
materialises, at the resolved `installPath`, the **complete** set of `plugins/soleur` files that
`jikig-ai/soleur` serves at the delivered commit, byte for byte, and that commit is current.

**Assembly.** The property has three independent conjuncts and the guard must quantify over each
separately, because a guard that collapses them passes on the failure the other two would have caught.
**Completeness** quantifies over the delivered tree's own recursive listing compared as a set against
the listing `main` serves — never a hand-declared subset, because the historical defect was
under-delivery and a subset comparison is structurally blind to it. **Integrity** quantifies over every
member of that set, each compared against the same path fetched at the **delivered commit**, so the
reference is pinned and a merge landing mid-run cannot masquerade as corruption. **Freshness** is a
single comparison of the delivered commit against `main` HEAD, and it is what stops a stale but
self-consistent mirror passing forever. Cutting across all three is the metadata boundary, and it is a
boundary over **fields**, not files: `claude plugin list --json` is a projection of
`installed_plugins.json`, so no verdict can escape the metadata by reading the CLI instead of the file.
`installPath` may be consumed as a location and `gitCommitSha` as the reference pin; neither `version`
nor `gitCommitSha` may stand in for a content comparison. The whole guard runs in one place — a
committed script the workflow invokes — so that the wiring itself is assertable.

**Mutation matrix.**

| # | Mutation | Required guard behaviour |
|---|---|---|
| 1 | Skip the install so `installPath` resolves empty (guard's own dispatch) | RED with `installpath_unresolved`; `compared=0` must fail, never green-by-vacuity |
| 2 | Delete one delivered file after install, leaving every remaining file byte-identical | RED on the completeness conjunct — this is the #7471 under-delivery shape and a subset comparison would miss it |
| 3 | Corrupt the **second** file in the compared set, leaving the first identical | RED — catches a loop that stops at the first member |
| 4 | Make a verdict satisfiable by `version` or `gitCommitSha` while delivered bytes are wrong | RED — no metadata field may participate, which is the 76882 mutation restated as a field boundary |
| 5 | Pin the delivered commit to an older SHA whose bytes are internally consistent | RED on the freshness conjunct alone, with integrity and completeness green |
| 6 | Make the reference fetch return an empty body or an HTML error page | RED with `reference_unreadable` — fail closed, never "0 differences, therefore green" |
| 7 | Remove the workflow step that invokes the script | RED from the static wiring assertion — a guard the workflow never reaches is not a guard |
| 8 | Emit a canary failure while the manifest assertions pass | The drift issue is filed and the Sentry check-in is `error` — the alarm must not be gated on the manifest verdict alone |

### Guard 2 — Legacy-resolver probe (`scripts/plugin-legacy-resolver-probe.sh`)

**Property.** On the machine it runs on, the probe reports every marketplace registration and every
installed or enabled plugin that resolves to `jikig-ai/soleur`, whatever local alias it was registered
under and whichever settings site it was declared in.

**Assembly.** The property quantifies over the CLI's **settings precedence chain**, and the chain — not
a list of sites observed on one machine — is the chokepoint. The first draft of this guard enumerated
five sites measured at plan time; reading the CLI bundle showed `settings.local.json` and
`managed-settings.json` alongside `settings.json`, so the enumeration was short and a snapshot is
therefore not an assembly. The probe derives its site list from the chain (user and project
`settings.json` and `settings.local.json`, the managed-policy file, and
`~/.claude/plugins/known_marketplaces.json`) and prints each site's resolved path and read status, so a
site that cannot be read is visible rather than absent. Cutting across the chain is a **two-stage
predicate**, required because the sites do not share a schema: registration sites carry `source.repo`
and are matched on it, never on the alias key, which is chosen locally at add time; but
`installed_plugins.json` carries no repo field at all (its records are `scope` / `projectPath` /
`installPath` / `version` / `gitCommitSha`) and `enabledPlugins` is a `plugin@alias` boolean map, so
both must be joined back through the alias set stage one produced. An alias that cannot be resolved to
a repo is an explicit unknown, because reporting it as clean is the exact false-negative this guard
exists to prevent.

**Mutation matrix.**

| # | Mutation | Required guard behaviour |
|---|---|---|
| 1 | Register the target repo under a different local alias, e.g. `"legacy"` | Still reported — alias-key matching would miss it |
| 2 | Declare it only in `extraKnownMarketplaces` in a settings file, absent from `known_marketplaces.json` | Still reported — the second declaration site, which is live on this machine |
| 3 | Declare it only in `settings.local.json`, absent from both of the above | Still reported — the site the plan-time enumeration missed |
| 4 | Declare it only in the **managed-policy** file | Still reported — this is the precedence-winning site, the one place a declaration cannot be overridden, and the one a chain-derived probe must not skip |
| 5 | Declare it only in a **project-scope** settings file, with the user scope clean | Still reported, with the project path named — the live install is project-scoped, so a user-scope-only walk is blind to the actual population |
| 6 | Leave an install in `installed_plugins.json` whose alias no longer resolves to any registration | Reported as an explicit unknown, never as clean — the join has no repo field to match on |
| 7 | Point the probe at a `HOME` with no `.claude` directory (guard's own dispatch) | Emits the site list with read statuses and an explicit absent verdict; "no file" must never render as "no legacy install" |
| 8 | Flip `autoUpdate` from `true` to `false` at one site, leaving every registration otherwise identical | The reading changes — otherwise arm B's execution is indistinguishable from arm C's non-execution |

## Observability

```yaml
liveness_signal:
  what: Sentry cron check-in from the existing scheduled-marketplace-drift monitor, with its status expression extended to consider the canary job's verdict as well as the manifest check's
  cadence: daily, cron "37 6 * * *"
  alert_target: Sentry cron monitor slug scheduled-marketplace-drift
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf, checked in via ./.github/actions/sentry-heartbeat in .github/workflows/scheduled-marketplace-drift.yml
error_reporting:
  destination: GitHub issue labelled ci/marketplace-drift + action-required, filed by the existing loop with its title and remediation branched by finding class per AP-021
  fail_loud: true
failure_modes:
  - mode: delivered content differs from the reference at the delivered commit
    detection: per-file digest comparison in scripts/plugin-delivery-canary.sh, finding token content_mismatch
    alert_route: drift issue (canary title variant) + Sentry error check-in
  - mode: delivered file set is smaller than the set main serves (the #7471 under-delivery shape)
    detection: set-cardinality assertion, finding token incomplete_delivery
    alert_route: drift issue (canary title variant) + Sentry error check-in
  - mode: delivered commit is behind main beyond tolerance
    detection: freshness comparison against main HEAD, finding token stale_delivery
    alert_route: drift issue (canary title variant) + Sentry error check-in
  - mode: install fails outright (marketplace add or plugin install non-zero)
    detection: recorded rc, finding token install_failed
    alert_route: drift issue (canary title variant) + Sentry error check-in
  - mode: installPath cannot be resolved, so the canary compares nothing
    detection: compared=<N> against expected=<M>, finding token installpath_unresolved
    alert_route: drift issue (canary title variant) + Sentry error check-in
  - mode: the reference fetch is unreadable, so expectations cannot be formed
    detection: empty or non-conforming body, finding token reference_unreadable
    alert_route: drift issue (canary title variant) + Sentry error check-in
  - mode: the CLI cannot be obtained, or the job aborts before emitting any finding
    detection: the canary job's own outcome is consumed by the heartbeat expression, so an aborted job checks in error rather than being silently absent; finding token cli_unavailable when the job survives to emit one
    alert_route: Sentry error check-in; drift issue when the job survives
  - mode: the canary step is removed from the workflow while the script survives
    detection: static wiring assertion in scripts/plugin-delivery-canary.test.sh
    alert_route: required test check on every PR
logs:
  where: GitHub Actions run log for scheduled-marketplace-drift, plus the drift issue body carrying the sanitized findings
  retention: 90 days (GitHub Actions default); the issue body is durable
discoverability_test:
  command: bash scripts/plugin-delivery-canary.sh --self-test
  expected_output: "SELF-TEST OK: <N> assertions exercised, 0 unexpected"
```

`--self-test` exercises the assertion logic against a synthesized fixture with no network access and no
credentials, so it runs unchanged in a sandbox. No `credentials_required` declaration: the canary's real
path was measured to need none.

## Hypotheses

Gate 4.5 fires on this plan (`SSH`, `timeout`), so the L3→L7 discipline applies. The network surface
here is not a host under this project's control — it is a GitHub-hosted runner reaching `github.com`
and `raw.githubusercontent.com`, and the "outage" under analysis is the CLI's transport choice rather
than an unreachable host. Each layer is answered with an artifact or an opt-out citing one, in order.

1. **L3 — firewall allow-list.** Not applicable, with an artifact rather than an assertion: no host in
   this project's firewall scope participates. The endpoints are GitHub's public HTTPS and SSH
   frontends, reached from a GitHub-hosted runner. Verification artifact: the unauthenticated
   `marketplace add` completing rc=0 in 7 s from an unprivileged scratch `HOME`, and again in 7 s with
   the local gitconfig neutralised.
2. **L3 — DNS / routing.** Verified. `git ls-remote https://github.com/jikig-ai/soleur.git HEAD`
   resolved and returned `43c7d3d79542e0909b3825ec17a3d58e193524de`, and
   `git ls-remote …/soleur-marketplace.git HEAD` returned `d0dc506e…`. Both endpoints resolve and route.
3. **L7 — TLS / proxy.** Verified. `curl -fsS --proto '=https' --max-redirs 0` against
   `raw.githubusercontent.com/jikig-ai/soleur/<sha>/plugins/soleur/.claude-plugin/plugin.json` returned
   `http=200 bytes=1027`, and the body's `sha256` matched the delivered file byte for byte. The
   certificate chain and the redirect ceiling were exercised by the same command the canary will use.
4. **L7 — application (the CLI's transport selection).** Verified from the service's own log lines,
   which is where the actual finding lives. The CLI emits `Cloning via SSH: git@github.com:…` and, when
   that attempt terminates, `SSH clone failed, retrying with HTTPS`. On the operator machine the SSH
   form never reaches the network because `~/.gitconfig` rewrites it. **The hypothesis this ordering
   produces, and which the plan carries upstream:** the fallback is reached only *after* the SSH attempt
   terminates, so an environment where SSH stalls rather than fails fast consumes the clone budget
   before HTTPS is ever tried — which is the shape upstream 77927 reports. This is a hypothesis about
   the CLI's timeout accounting, **not verified**: the planning probes forced SSH to fail fast
   (`BatchMode=yes`), so the stall case was not reproduced. Phase 2 does not attempt it either; it is
   reported upstream as a mechanism proposal with the fail-fast measurement attached, and labelled as
   such.

No layer above the application layer is unverified, so no service-layer hypothesis here rests on an
unchecked lower layer. The canary's mitigation — `CLAUDE_CODE_PLUGIN_PREFER_HTTPS` — acts at layer 4
by removing the SSH attempt rather than by waiting for it to fail.

## Encryption Posture

No persistent store is introduced, so `at_rest` has no entries: the canary writes only to a scratch
`HOME` on an ephemeral runner, discarded with the job, and nothing in this change creates a volume,
bucket, table, queue, cache, backup target or log sink. The new cross-component connections are the
canary's outbound clone and its reference fetches.

```yaml
at_rest: []   # no persistent store introduced; scratch HOME on an ephemeral runner only
in_transit:
  - connection: runner -> github.com (git clone of the marketplace repo and the plugin subtree)
    tls: TLS 1.2+ via git over HTTPS, forced by CLAUDE_CODE_PLUGIN_PREFER_HTTPS so the SSH attempt is skipped
    cert_verification: on
    does_not_defend: a compromise of the marketplace repo's contents — the manifest is unreviewed by construction, which is what the drift assertions in the sibling job cover
    disclosed_as: ADR-182 Consequences, "the published manifest is unreviewable by construction"
  - connection: runner -> raw.githubusercontent.com (reference fetch, pinned to the delivered commit)
    tls: TLS 1.2+, curl with --proto '=https' --max-redirs 0 as the existing steps already use
    cert_verification: on
    does_not_defend: a compromise of jikig-ai/soleur main itself, which would make reference and delivery agree while both are wrong
    disclosed_as: same ADR section
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-182 in place** for three things that are refinements rather than decisions: the Context's
statement that the refresh clones the monorepo (a factual error about a mechanism, corrected by the
reflog and the CLI's own strings, with the clone figures kept attached to the paths that still clone);
Decision 5's disposition (which arm, what was accepted); and the rejected retire-the-entry alternative.

**Add Decision 6 to ADR-182 for the canary.** Review established that this is a distinct decision, not a
refinement of Decision 5 — Decision 5 is about the legacy monorepo entry, while the canary changes the
control topology of the published distribution path. It carries its own alternatives (extra steps in the
existing step, a second job, a new workflow, scheduling the existing dispatch-only install), its own
accepted risk (a job that downloads a CLI and materialises executable plugin content inside a workflow
that also holds `issues: write`), and a direct bearing on the posture recorded at #7493, whose
Alternatives frame the space as detection versus prevention: the canary strengthens detection without
converting it to prevention, and a reader arriving from there needs to find that stated. Placing it as a
numbered Decision inside ADR-182 keeps it under an ordinal without claiming a new one, so no
ordinal-collision probe is needed.

### C4 views

**Three** descriptions become false, not two — the plan's first draft named two and a full re-read of
`model.c4` found a third. All three are edited; no element is added and `views.c4` is untouched, because
the canary is a new capability of the existing `github -> soleurMarketplace` edge rather than a new node.

- `soleurMarketplace` element description — *"scheduled-marketplace-drift.yml in jikig-ai/soleur is its only control."*
- The `github -> soleurMarketplace` edge — *"the sole control on a repo with no CI, no review and no CODEOWNERS"*.
- The `github -> sentry` edge — *"-marketplace-drift (#7471 — the sole control on the published distribution manifest …)"*. This one sits inside the clause block `c4-count-parity.test.sh` parses, so the edit must not disturb `check-ins from 10 workflows`, `6 GHA-\`schedule:\`-fired`, `Of 55 cron monitors`, `11 check in from here` or `44 from webapp`.

The completeness check read all three of `model.c4`, `views.c4` and `spec.c4` rather than grepping for
the feature's own noun. External human actors were enumerated (`founder`, `emailSender`, `betaContact`,
`contributor`): **there is no actor for a plugin installer distinct from the operator**, and installs are
attributed to `founder`. That conflation is a real modelling gap; it predates this change and this change
does not widen it, since the canary is a CI traversal from `github` rather than a new human actor. It is
recorded here so a later reader finds it named. External systems were enumerated; `github`, `sentry` and
`soleurMarketplace` all exist, and GitHub Actions has no separate element — CI is modelled as edges from
`github`, so the canary needs no new node. Counts hold because a second job in an existing file changes
neither the count of heartbeat workflow files nor the set of distinct monitor slugs.
`model.likec4.json` is regenerated because `c4-model-freshness.test.sh` requires byte-identity.

### Sequencing

Both records ship in this PR. Neither is gated on a later slice.

## Acceptance Criteria

### Pre-merge

1. `scripts/plugin-legacy-resolver-probe.sh --json` emits a `sites` array in which every element carries a resolved path, a read status and (for registration sites) each registration's `autoUpdate` value. The array is derived from the settings precedence chain rather than a hardcoded literal — assert by running the probe against a fixture `HOME` where a settings site is *absent* and then *present*, and confirming the entry's **read status changes while the array length stays constant**. Length growth is the wrong assertion: Guard 2 row 7 requires absent sites to be listed, so they are already present as entries.
2. `bash scripts/plugin-legacy-resolver-probe.test.sh` passes with all eight Guard 2 mutation rows implemented as named cases, each demonstrated to change the probe's verdict when applied and restore it when reverted. Rows 4 and 5 (managed-policy site, project-scope site) are the two the plan-time enumeration missed and are not optional.
3. The probe reports an install whose alias resolves to no registration as an explicit unknown: a fixture with `installed_plugins.json` carrying `soleur@soleur` and no registration anywhere yields a non-clean verdict.
4. `bash scripts/plugin-delivery-canary.sh --self-test` prints `SELF-TEST OK:` with a non-zero assertion count and `0 unexpected`, exits 0, with no network access and no credentials available.
5. `bash scripts/plugin-delivery-canary.test.sh` passes with all eight Guard 1 mutation rows implemented as named cases. Row 2 (a deleted file) and row 5 (an older but internally consistent commit) each fail exactly one conjunct, demonstrating that completeness, integrity and freshness are independently observable.
6. The canary's verdict is not satisfiable by metadata: mutation row 4's case shows the guard RED when `version` and `gitCommitSha` are correct and delivered bytes are wrong.
7. `grep -c '^\s*run_suite .*plugin-delivery-canary' scripts/test-all.sh` and `grep -c '^\s*run_suite .*plugin-legacy-resolver-probe' scripts/test-all.sh` each return 1 — anchored on the `run_suite` token, not a bare mention.
8. The canary is a second job in `.github/workflows/scheduled-marketplace-drift.yml`; the file still contains exactly one distinct `monitor-slug:` value, and `grep -c 'uses: ./.github/actions/sentry-heartbeat'` is unchanged from `origin/main`.
9. The filing step's condition and the heartbeat's status expression both reference the canary job's verdict; a canary-red / manifest-green fixture files an issue and produces an `error` check-in. Demonstrated by mutation row 8, not asserted.
10. Every new step condition that references job or step outputs carries the `outcome == 'success'` conjunct that `scripts/marketplace-drift-check.test.sh` requires; `bash scripts/marketplace-drift-check.test.sh` passes.
11. The drift issue's title and remediation branch by finding class; a canary-only finding produces a title that does not claim the published manifest changed. `bash scripts/lint-diagnosis-claims.sh` passes.
12. `grep -c 'sole control\|only control' knowledge-base/engineering/architecture/diagrams/model.c4` returns 0.
13. After the Phase 6.3 edit lands, the five count-anchored literals in `model.c4`'s `github -> sentry` edge are byte-identical to `origin/main`: `git diff origin/main -- knowledge-base/engineering/architecture/diagrams/model.c4 | grep -cE 'check-ins from [0-9]+ workflows|[0-9]+ GHA-|Of [0-9]+ cron monitors|[0-9]+ check in from here|[0-9]+ from webapp'` returns 0 for removed lines carrying a *changed* count.
14. `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash plugins/soleur/test/c4-model-freshness.test.sh` both pass against the committed `model.likec4.json`.
15. The runbook's **Symptom 2** section distinguishes the fresh-add `--sparse` case from the existing-checkout case, and both READMEs carry the same distinction. Assert by locating the correction within the Symptom 2 heading's own body, not anywhere in the file: `awk '/^\*\*If the legacy channel must be kept/{f=1} f&&/^---$/{exit} f' <runbook> | grep -c 'existing checkout'` returns at least 1.
16. The runbook's **Symptom 1** block states that `claude plugin list --json` is a projection of `installed_plugins.json` and gives a cross-check that does not depend on it.
17. The runbook's persistence section contains one labelled claim per Phase 2 arm, each beginning `measured:` or `unverified:`. Assert against the section, not the file: `awk '/^## Making the timeout persistent/{f=1;next} f&&/^## /{exit} f' <runbook> | grep -cE '^\s*[-*] +(measured|unverified):'` returns at least 4, and `grep -c '^## Making the timeout persistent' <runbook>` returns 1 (deleting the section does not satisfy this).
18. The runbook contains a row for every canary finding token: `for t in content_mismatch incomplete_delivery stale_delivery install_failed installpath_unresolved reference_unreadable cli_unavailable; do grep -qF "$t" <runbook> || echo MISSING "$t"; done` prints nothing.
19. `measurements.md` records, for each of Phase 2's arms 1-7, the command run and a verdict of `measured` with a result or `unverified` with a statement of what would verify it. An arm recorded as neither fails this criterion, so writing `unmeasured` everywhere does not satisfy it. **Arms 1, 2, 6 and 7 must carry `measured`** — each has a deterministic instrument already validated at plan time (the tiny-timeout falsification for 1 and 2, a scratch checkout for 6, an add/remove round trip for 7), so an `unverified` verdict there is a gap rather than a finding. Only arms 3, 4 and 5, which depend on triggering a background refresh, may land `unverified`.
20. `measurements.md` carries the Phase 1 pre-state probe reading and the Phase 3 post-state reading, both dated, under every arm and under the headless branch.
21. ADR-182 carries the amendment (Context correction, Decision 5 disposition, rejected alternative) **and** a numbered Decision 6 for the canary with its alternatives and its #7493 relationship stated. `bash scripts/check-adr-ordinals.sh` passes.
22. The recorded decision names the arm actually taken and the mode branch (attached or headless) it was taken under, and matches what `decision-challenges.md` says when the headless branch fired.
23. `upstream-reports.md` contains four evidence sections and an explicit section-to-posting mapping, and every section is scrubbed against all four exposure categories: `grep -cE '/home/|/Users/|~/\.claude|/git-repositories/|[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:' <file> || true` returns 0. The same grep is re-run against each body **as posted** (fetched back via `gh api`), not only against the local copy — the posted body is the artefact that leaks.
24. `scripts/followthroughs/plugin-delivery-canary-7490.sh` exists, is executable, and its header states the exit contract (0 PASS / 1 FAIL / other TRANSIENT). The tracker carries the `follow-through` label and a `soleur:followthrough` directive whose `earliest` is after the merge date.
25. `python3 scripts/lint-guard-contract.py <this plan>` exits 0.
26. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0 — the gate's own invocation, not a hand-enumerated path list.
27. `bash scripts/lint-workflows.sh` exits 0, and `actionlint .github/workflows/scheduled-marketplace-drift.yml` exits 0 **with no `missing input` findings** — which requires Phase 4.5b's repair, because on `origin/main` that command reports three (`sentry-ingest-domain`, `sentry-project-id`, `sentry-public-key`). Measured at plan time; the AC is written against the post-repair state deliberately, not against a wrapper whose ratchet tolerates the finding.
28. `bash scripts/test-all.sh` passes, or every failure is confirmed pre-existing on `origin/main`.

### Post-merge (carried by the Phase 6.6 follow-through, not by memory)

29. The first scheduled or dispatched run of `scheduled-marketplace-drift.yml` completes with the canary job green and a non-zero comparison count, verified from the run log. If it is red, the follow-through exits 1 and **comments the failure on the (already-closed) tracker and files an `action-required` issue** — it cannot "leave the tracker open", because `closes:` fires at merge, and no exit code in the sweeper contract reopens an issue. That is the defined path; no phase treats a red first run as terminal.
30. The upstream postings the plan authorises are made and their URLs recorded in `upstream-reports.md`, and each posted body is fetched back via `gh api` and re-scrubbed. Partial success is recorded as partial: the follow-through reports which routes landed, and unsent routes surface as an `action-required` issue rather than as a re-running TRANSIENT.

## Domain Review

**Domains relevant:** Engineering, Product.

### Engineering

**Status:** reviewed
**Assessment:** Four-agent review moved three structural decisions. The canary became a second job rather
than extra steps, because the shared-array integration the first draft assumed does not survive a step
boundary and because an existing hermetic suite extracts and re-executes the step it would have joined.
The alarm wiring became explicit, because the filing gate and the heartbeat both keyed on the manifest
check alone and would have reported green through a canary failure. And the content assertion split into
completeness, integrity and freshness, because a declared-subset byte comparison is structurally blind to
under-delivery — which is the defect that produced ADR-182 in the first place. Remaining engineering risk
is concentrated in the CLI acquisition path, which is new to this repo and is the reason the canary
carries its own timeout and its own privilege scope.

### Product/UX Gate

**Tier:** none
**Decision:** not applicable
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

No file in `## Files to Create` or `## Files to Edit` matches a UI-surface path — no `components/**`, no
`app/**/page.tsx`, no `app/**/layout.tsx`. The mechanical UI-surface override does not fire. The
operator-facing surface is a runbook, two READMEs and a CLI probe.

**CPO sign-off** is required by the `single-user incident` threshold and is requested on the runbook
Symptom 2 correction specifically — that is the artefact a user follows while their install is broken,
and the hazard it currently instructs them into is what set the threshold.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The `--sparse` re-clone hazard is inferred from CLI strings, not measured, yet it sets the threshold | Phase 2 arm 6 exists specifically to measure it, on a scratch checkout. If it cannot be reproduced, the runbook states it as unverified rather than dropping it — the asymmetry favours warning. |
| A flaky canary drowns the manifest assertions it shares a workflow with | Separate job, separate timeout, separate privilege scope, and a title branched by finding class. If flake appears, the canary job can be made non-blocking for the manifest verdict without unwinding the design. |
| Obtaining the CLI in CI is a new dependency with a large payload and no precedent in this repo | Pin the version explicitly; treat acquisition failure as its own token and let the job's own outcome reach the heartbeat, so an abort before any finding still alarms. |
| The canary executes downloaded code in a workflow that also holds `issues: write` | The canary job carries `contents: read` only; the write-capable filing step stays in the sibling job and consumes the canary's verdict through job outputs. Stated in ADR-182 Decision 6 rather than left implicit. |
| Arm B may have no working mechanism | Phase 2 arms 4 and 5 decide it before Phase 3 asks. An arm whose mechanism is falsified is withdrawn from the question, not offered and then discovered inert. |
| Arm A touches a project this session cannot observe | Not executed headless. Asked once when attached, with the `projectPath` named in the question. |
| Upstream posting fails or is partially applied | Sending is operator-gated; bodies are committed first so the evidence is durable regardless, and the follow-through reports which routes landed. |
| Both trackers close at merge while two criteria are post-merge | #7489 closes on its recorded-decision condition, which is a pre-merge artefact. The post-merge criteria are carried by the Phase 6.6 follow-through rather than by memory. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- `findings` and `sanitize()` in `scheduled-marketplace-drift.yml` are shell locals of the `check` step. Anything that needs them must either live in that step — where `scripts/marketplace-drift-check.test.sh` will execute it hermetically without network — or cross the boundary through outputs with its own sanitizer.
- Repo-root `scripts/*.test.sh` is not covered by `scripts/test-all.sh`'s auto-glob (which does cover `scripts/lib/*.test.sh` and `plugins/soleur/test/*.test.sh`). Registration is by hand. Forgetting it reds `scripts/lint-orphan-test-suites.sh` rather than passing silently, but the suite still gates nothing until registered.
- `claude plugin list --json` is a projection of `installed_plugins.json`, verified by mutating the file and observing the CLI output change. Any advice or assertion that treats the CLI as an independent authority is wrong, including the advice currently in the recovery runbook.
- The compound `version` string means the plugin cache directory name changes on every commit, so each update leaves the previous directory behind. ADR-182 records this as a per-update orphan; the canary's scratch `HOME` is discarded per run, but a long-lived runner cache would accumulate it.
- `model.c4`'s `github -> sentry` edge carries five literals that `c4-count-parity.test.sh` parses. Editing prose in that clause block without preserving them reds the suite.

## Non-Goals

- Retiring the monorepo marketplace entry. Measured to buy nothing for stranded installs and recorded as a rejected alternative in ADR-182 rather than deferred to an issue.
- Terraform ownership of the published manifest's contents, and a push-restricting ruleset on the marketplace repo. Both are already recorded in ADR-182's Alternatives Considered as deferred with reasons and are tracked at #7493; this plan does not re-decide them, though Decision 6 states how the canary changes that posture.
- Automating the orphaned plugin-cache reclaim. There is no CLI verb for it and the runbook's print-then-delete guard is the deliberate shape.
- Identifying the 8-character half of the compound version string beyond recording that it is not the marketplace repo's HEAD. It is reported upstream as unidentified rather than guessed.
- Any change to the plugin's own payload, manifests, or release path.
