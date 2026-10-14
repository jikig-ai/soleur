---
title: "feat: make the installed Soleur plugin version visible (manifest stamp, help header, SessionStart banner, /soleur:version)"
date: 2026-10-11
slug: plugin-version-visibility
branch: feat-one-shot-plugin-version-visibility
type: feat
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# feat: make the installed Soleur plugin version visible

## Enhancement Summary

**Deepened on:** 2026-10-11
**Research/review agents used:** learnings-researcher, CTO, CLO, DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, CPO (all read-only), plus direct measurement and
live verification below. Mandatory deepen halts: 4.6 User-Brand Impact pass (`single-user
incident`), 4.7 Observability pass (discoverability command is an allowlisted verb, no SSH,
sub-second, literal `expected_output`), 4.8 no PAT-shaped variables, 4.9 not a UI plan (skip),
4.10 no new store or Terraform (skip), 4.11 Guard Contract pass (`scripts/lint-guard-contract.py`
rc=0, 3 guards), 4.12 Scope Check pass (one unfenced section, Ask Mapping / Provenance / Split).

### Key improvements

1. Item 1 re-scoped from "edit marketplace.json and plugin.json in a release commit" to a gated,
   dark-launched Slice B stamping `plugin.json` only, in its own `workflow_run` workflow, with the
   release-loop, deploy-chain, prod-drift and rollback holes found in review closed.
2. Items 2-4 made independent of item 1 via one shared, keyless-compatible resolver with an explicit
   SHA-vs-tag compare rule (D3b).
3. Execution gate added so `soleur:work` stops after Slice A unless the operator confirms DC-1
   (CPO CHANGES REQUESTED on Slice B).

### New considerations discovered

- Merge-queue lag for bot PRs is 41-112 min (n=6); delivery of a stamped release also waits on
  release success and stamp-PR CI. A frozen stamp is the #7471 shape: `--remove-key` rollback required.
- `resolve-target` fails closed on a skipped caller job, so the web gate must make `check_changed`
  decline, not skip `release`.
- A `workflow_dispatch` of `version-bump-and-release.yml` cuts a real release (`force_run=true`).
- The rule-body edit needs a human-owned, hash-bound ack (CODEOWNERS WORM).
- Legal: the explicit `/soleur:version` call needs the privacy carve-out too, not only the opt-in hook.

### Live verification performed in this deepen pass

```text
$ git ls-tree --name-only origin/main knowledge-base/engineering/architecture/decisions/ | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -2
ADR-283
ADR-284                      # ADR-285 is the next free ordinal (provisional; ship re-verifies)
$ gh pr view 9745 / 7390     # both OPEN, isDraft=true;   gh issue view 7471 -> CLOSED
$ git show origin/main:plugins/soleur/.claude-plugin/plugin.json | grep -c '"version"'   -> 0
$ git show origin/main:AGENTS.rules.md | grep -c 'id: wg-never-bump-version-files-in-feature' -> 1
$ time git ls-remote --tags --refs https://github.com/jikig-ai/soleur.git 'refs/tags/v*'
real 0m0.630s, 116836 bytes (includes vinngest-v*); strict-regex max = v3.335.9
$ gh api repos/jikig-ai/soleur/compare/b78d30e919ff...main  -> status=diverged ahead_by=8 behind_by=2
```

M5 preliminary result: `ls-remote` is cheap (0.63 s, 117 KB) so D3 stands; the 5 s cap has ~8x
headroom. The compare API accepts a 12-char SHA. **D3b amendment from the live reading:** the
status can be `diverged` when the installed commit is not an ancestor of the target (this install,
`b78d30e919ff`, is on a branch not in `main`'s history); `diverged` maps to `relation=unknown`
("installed commit is not on main"), never to "newer exists" or "up to date". Phase 0 still owns
the formal M2/M4/M5 readings.

## Overview

Today `claude plugin list` and `/plugin` show an opaque 12-character commit hash for Soleur
(for example `4fea15312139`), because no manifest carries a `version` key (ADR-182 Decision 1,
ADR-017, AGENTS rule `wg-never-bump-version-files-in-feature`). The release tags (`vX.Y.Z`)
exist only in git. This plan makes the installed version human-visible in four places:

1. **Manifest stamp (Slice B, gated).** The plugin release workflow stamps `version` into
   `plugins/soleur/.claude-plugin/plugin.json` after each release, so `/plugin` shows a real
   version and `claude plugin update` compares real versions.
2. **`/soleur:help` header** shows the installed version.
3. **SessionStart banner** prints `Soleur vX.Y.Z`; an opt-in, cached, non-blocking network check
   warns when a newer release tag exists.
4. **`/soleur:version` command** prints installed version and latest release.

Items 2-4 (Slice A) ship on one shared resolver script that works with OR without the
manifest key, so they do not depend on item 1. Item 1 (Slice B) reverses a measured incident
fix (#7471) and is therefore gated by a Phase 0 measurement and dark-launched (see
"Critical finding" below).

### Execution gate (result of plan review; read this before `soleur:work`)

Plan review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CPO, plus the CTO
and CLO domain reviews) converged: **Slice A is signed off; Slice B is not.** CPO verdict:
"CHANGES REQUESTED" for Slice B (not proportionate to a display feature, stale window not
acceptable as a default, failure path unbounded). Because Slice B is operator-requested scope,
it is NOT deleted from this plan (never-Mechanical, ADR-084) — it is held behind an explicit
gate:

- `soleur:work` executes **Slice A + Phase 0** unconditionally.
- `soleur:work` executes **Slice B (Phase 4 and the Slice-B-only parts of Phase 5) only after
  the operator confirms DC-1 in `decision-challenges.md`** AND Phase 0 is Go AND the CPO
  conditions in "Slice B conditions" below are met. Absent that confirmation, the work phase
  files the follow-up issue (text under "Deferral tracking") and stops after Slice A.
- Slice-B-only deliverables (ADR-182/017 amendments, ADR-285, rule-body edit, prose edits,
  Guards 1-3, soak script) are skipped when Slice B is skipped. Slice A needs only the runbook
  note, the README paragraph, the legal carve-out and C4 description tweaks.

### Critical finding the brief did not carry: item 1 reverses ADR-182 Decision 1

The brief reconciles item 1 with the *first half* of `wg-never-bump-version-files-in-feature`
(feature PRs must not bump versions; CI does). The rule's *second half* is the real conflict:
"No plugin manifest carries a `version` key; never add one back — `plugin update` compares
version strings, so a constant one always compares equal and the update no-ops while reporting
success (#7471)". The same prohibition is asserted by:

- ADR-182 Decision 1 and the post-mortem `plugin-delivery-path-silent-staleness-postmortem.md`
  (3 months of silent staleness, `brand_survival_threshold: single-user incident`);
- `scripts/marketplace-manifest-validate.sh` + `.github/workflows/scheduled-marketplace-drift.yml`
  Assertion 1 (`.plugins[0]` must have no `version` key, on the PUBLISHED manifest);
- `plugins/soleur/test/plugin-version-fallback.test.ts` (asserts both in-repo manifests keyless);
- prose in `plugins/soleur/AGENTS.md`, `CONTRIBUTING.md`, `plugins/soleur/commands/help.md`,
  `ship/SKILL.md`, `work/SKILL.md`, `release-announce/SKILL.md`.

A stamped version is NOT a constant, so it does not reproduce #7471 by itself — but it is
*stale* between the content merge M and the stamp merge R. Measured baseline for that window
(`gh pr list --state merged --author app/soleur-infra`, n=6 bot PRs): created-to-merged
**41, 43, 77, 80, 88, 112 minutes** (merge queue is `max_entries_to_merge = 1`,
`check_response_timeout_minutes = 75`). During that window `claude plugin update` compares
equal version strings and no-ops — the #7471 failure shape, bounded by queue latency instead of
infinite. That is why Slice B is gated on measurement, ships dark, and has a drift canary.

## Research Insights

### Premise Validation (Phase 0.6)

No issue/PR numbers cited by the brief for blockers. Checked on `origin/main`:

- Holds: `plugin.json` has no `version` key; `.claude-plugin/marketplace.json` `plugins[0]` has
  none (top-level `version: "1.0.0"` is the manifest-format version); `hooks.json` has four
  SessionStart blocks; `commands/` holds `go.md`, `help.md`, `sync.md`.
- Holds: open draft PRs #9745 (`plugins/soleur/commands/help.md`, cursor CLI hook captures) and
  #7390 (`.github/workflows/reusable-release.yml`, provenance build-arg) exist and are drafts.
  Neither touches `version-bump-and-release.yml`, `hooks.json` or `plugin.json`.
- **Stale premise in the brief:** "write the version into plugin.json AND marketplace.json".
  Claude Code docs (`plugins/loading` "How Claude Code computes the version"; `plugins-reference`
  "Metadata precedence"): the **manifest's** `version` overrides the marketplace entry's.
  Stamping `marketplace.json` is redundant (one more drift surface). The PUBLISHED manifest in
  `jikig-ai/soleur-marketplace` MUST stay keyless (drift Assertion 1 + ADR-182 Decision 4:
  "a release publishes nothing to the marketplace repo"). Plan stamps `plugin.json` only.
- **Stale premise:** "from the release workflow in the release commit, matching the version it
  tags". `reusable-release.yml` creates a draft release with no `--target`, so the tag lands on
  default-branch HEAD at publish time (the content commit M). The ruleset requires PR + merge
  queue, so a "release commit" can only exist as a LATER bot PR merge R. The tag therefore
  never contains its own version stamp. Documented, not worked around (immutable releases).
- Premise check on the mechanism vs ADR corpus: ADR-182 Decision 1 and ADR-017 rule the
  mechanism out as written; both are amended by this plan (see Architecture Decision).

### Property List and Cut List (Phase 0.6b)

Properties:

- P1. A user can see which Soleur release they have installed, in-session, offline.
- P2. `claude plugin update` keeps detecting every content change (no #7471 regression).
- P3. A user can opt in to learn a newer release exists; default is zero network.
- P4. One command prints installed version and latest release.
- P5. No feature PR bumps versions; release CI is the only writer; no release loop; main
  branch protection is not weakened.

Cut List (mechanism -> property -> what already covers it):

- Stamp `.claude-plugin/marketplace.json` `plugins[0].version` -> P1/P2 -> covered by the
  manifest-wins precedence; cut.
- Direct push of a release commit to main / new `always` bypass actor on the CI ruleset -> P1 ->
  covered by the ADR-232 bot-PR pattern; cut (widens a standing bypass set audited by
  `cron-ruleset-bypass-audit`).
- Synthetic-check bot PR (`bot-pr-with-synthetic-checks`) -> faster merge -> its ALLOWED_PATHS
  ceiling (ADR-139) covers only `weakness-digest.md` and `plugin.json` carries `mcpServers`;
  widening it would let a bot PR change executable config without CI; cut.
- Stamped non-manifest `VERSION` label file (CTO suggestion) -> P1 -> same loop/queue problem
  as the manifest stamp, adds a second surface; cut. Fallback when Slice B is no-go is the
  keyless path (SHA + tag lookup), which needs no repository write.
- Editing `reusable-release.yml` -> P1 -> the plugin-only caller `version-bump-and-release.yml`
  already receives `needs.release.outputs.{version,tag,released}`; cut (avoids merge
  conflict with draft #7390 and keeps the generic workflow generic).
- New telemetry/install-id for adoption -> none of P1-P5; cut (also would create an Art. 30
  processing activity, see Domain Review).

### Repo and docs facts used

- Claude Code docs: version resolution order is manifest `version`, then marketplace-entry
  `version`, then source SHA (12 chars); `git-subdir` SHA versions carry a path hash. The cache
  dir is `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` and `${CLAUDE_PLUGIN_ROOT}`
  points at it, so keyless `basename "$CLAUDE_PLUGIN_ROOT"` is the 12-char SHA (matches
  `b78d30e919ff` on this machine). SessionStart: top-level `systemMessage` is shown to the
  user; `hookSpecificOutput.additionalContext` goes to Claude; default hook timeout 600 s.
  Unrecognized top-level manifest keys are stripped (so no custom key can carry a label).
- `.github/workflows/version-bump-and-release.yml` triggers on push to main with
  `paths: ['plugins/soleur/**', 'plugin.json']`; `reusable-release.yml` `check_changed` is
  `git diff --name-only HEAD~1 -- plugins/soleur/`, so a stamp-only commit would release again.
  `web-platform-release.yml` triggers on `plugins/soleur/**` minus `docs/**` and `test/**` and
  would build and deploy a Docker image for a stamp-only commit.
- ADR-232 is the template for a workflow-authored bot PR: `soleur-infra` App token via
  `.github/actions/mint-infra-app-token` (job `environment: infra-privileged`), never
  `GITHUB_TOKEN` (PRs from it trigger no workflows) and never a PAT; reconcile to semver-max
  rather than the triggering tag; deterministic branch; reuse an existing PR.
- `welcome-hook.sh` documents that plugin hooks are GLOBAL (fire in every project); dedupe/cache
  state must live outside the project tree under XDG dirs. `compaction-state.sh` documents that a
  hung SessionStart hook blocks the session: wrap in `timeout`, fail open.
- Component-count surfaces for a new command: `plugins/soleur/README.md` (`| Commands | 3 |`
  and the Commands table), `invocation-axis.test.ts` (`commands/*.md` min 3),
  `components.test.ts` (slash-name uniqueness, command frontmatter), docs-site counts via
  `release-docs`, harness mirrors (`cursor/commands`, `.grok/commands`, codex/devin).
- Skill description budget has zero headroom (`SKILL_DESCRIPTION_WORD_BUDGET`); a COMMAND
  (`commands/version.md`) is used, not a skill. No `soleur:version` skill exists.
- Legal (CLO, see Domain Review): `docs/legal/privacy-policy.md` Section 4.1 says the plugin
  "does not phone home"; opt-in networking needs a one-sentence carve-out.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Write `version` into plugin.json AND marketplace.json | Manifest wins over entry; published manifest must stay keyless (drift Assertion 1, ADR-182 D4) | Stamp `plugin.json` only; keep `.claude-plugin/marketplace.json` and the published manifest keyless; add an assertion that they stay keyless while plugin.json is stamped |
| Do it "in the release commit", matching the tag | Tag is created at HEAD (content commit M); main is PR+merge-queue only, so the stamp is a later bot-PR merge R | Bot PR authored by `soleur-infra[bot]`; document tag/stamp skew; resolver never assumes a tag contains its own stamp |
| "reconcile with wg-never-bump-version-files-in-feature (feature PRs must not bump)" | Rule also forbids the key entirely; ADR-182 D1; four test/guard surfaces assert absence | Amend rule body, ADR-182, ADR-017 (deliverables); replace "key absent" tests with a "no non-bot PR changes `.version`" guard |
| "check branch protection / bot push rights" | CI Required ruleset: PR required, strict checks, merge queue (max 1, 75 min timeout); bypass = OrgAdmin + Admin role in `pull_request` mode only; bot PRs merged in 41-112 min | PR path via ADR-232 pattern; no ruleset change; lag measured and bounded by canary |
| (implicit) one stamp per release | Merge queue is serial; several releases can land before one stamp merges | Stamp job reconciles to semver-max tag; one deterministic branch/PR; coalesces |
| "Show the version in help.md header read from plugin.json" | help.md Step 1 currently says "do not report a version read from it" | Resolver reads manifest when stamped, else SHA + (cached) tag; rewrite that paragraph |

## User-Brand Impact

**If this lands broken, the user experiences:** `claude plugin update soleur@soleur-marketplace`
printing "already at the latest version" and exiting 0 while delivering nothing (a stale or
never-advancing stamp), or a session that hangs/spams at start because the SessionStart hook blocked
on the network, or a release loop that rebuilds and redeploys the web image on every stamp merge.

**If this leaks, the user's workflow is exposed via:** the opt-in update check sends an IP and
user-agent to GitHub (no Jikigai endpoint, no identifier). A stamp PR must never carry anything
but a version string. No credential is read by the hook; the cache file holds one tag string.

**Brand-survival threshold:** single-user incident

(Inherited from the #7471 post-mortem: a silently non-updating plugin was a single-user incident.
`requires_cpo_signoff: true` — CPO sign-off must be recorded before `soleur:work` starts;
`soleur:engineering:review:user-impact-reviewer` runs at review time.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "(1) write a `version` field into plugins/soleur/.claude-plugin/plugin.json and marketplace.json from the release workflow in the release commit, matching the version it tags" [brief] | Slice B: Phase 4 (`stamp-plugin-version.yml`, `stamp-plugin-version.sh`); narrowed to plugin.json only (DC-2) | mapped (gated: Execution gate, DC-1) |
| 2 | "check branch protection / bot push rights and document or handle any needed exception" [brief] | Research Reconciliation row 4; D6; Cut List (direct push / bypass actor / synthetic checks rejected); ADR-285 | mapped |
| 3 | "reconcile with AGENTS.md rule wg-never-bump-version-files-in-feature" [brief] | Architecture Decision (ADR/C4): rule-body edit, ADR-182/017 amendments; Guard 3 / D8 | mapped (Slice B) |
| 4 | "(2) Show the version in plugins/soleur/commands/help.md header" [brief] | Phase 3: `help.md` Step 1 + header line | mapped |
| 5 | "(3) Add a SessionStart hook in plugins/soleur/hooks/hooks.json that prints \"Soleur vX.Y.Z\" and warns when a newer release tag exists" [brief] | Phase 2: `version-banner.sh` + `hooks.json` block | mapped |
| 6 | "the network check must be cached and off by default (opt-in)" [brief] | D4 (24 h XDG cache, `SOLEUR_UPDATE_CHECK=1`) | mapped |
| 7 | "(4) Add a tiny /soleur:version command printing installed version and latest release" [brief] | Phase 3: `commands/version.md`, D5 | mapped |
| 8 | "keep edits minimal and flag merge-conflict risk in the plan" [brief] | Merge-conflict risk section; help.md two hunks; `reusable-release.yml` limited to one input (Slice B) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `stamp-plugin-version.yml` + `stamp-plugin-version.sh` | asks 1-2 ("write a `version` field ... from the release workflow") | asked |
| `plugin-version.sh` shared resolver | asks 4, 5, 7 (help header, hook, command all need the installed version) | inferred — justification: three consumers would otherwise each parse the manifest and re-derive the keyless SHA fallback; one script and one test keep them from drifting |
| `is-plugin-version-stamp-commit.sh` + `gate` job + `check_changed` input | ask 1 | inferred — justification: without it each stamp merge re-triggers `version-bump-and-release.yml` and `web-platform-release.yml` (release loop and a Docker rebuild/deploy) |
| Guard 2 stale-stamp canary in `scheduled-marketplace-drift.yml` | ask 1 | inferred — justification: the #7471 post-mortem lesson that a remediation's own liveness must be observable; a stalled stamp is the #7471 failure |
| Guard 3 / D8 `.version` PR guard, `plugin-version-fallback.test.ts` update | ask 3 ("reconcile with ... wg-never-bump-version-files-in-feature") | asked |
| ADR-182/017 amendments, ADR-285, rule-body edit, prose edits | ask 3 | asked |
| `--remove-key` rollback | ask 1 | inferred — justification: CPO/architecture review blocker; a frozen stamp is the constant-version failure and needs a tested exit |
| Soak follow-through script | ask 1 | inferred — justification: plan Phase 2.9.1 enrollment is required for a soak-gated closure; `soleur:ship` blocks without it |
| `docs/legal` carve-out, mirrors, SHA pins | ask 6 ("off by default (opt-in)" network check) | inferred — justification: the policy states the plugin "does not phone home"; CLO finding that the opt-in and the explicit command make it false without a carve-out |
| `commands/version.md`, README count, harness mirrors | ask 7 | asked |
| `hooks/version-banner.sh` + test | ask 5, ask 6 | asked |
| `workflow-run-deploy-invariants.test.sh`, `prod-version-drift-check.sh` edits | ask 1 | inferred — justification: the stamp commit would otherwise page the prod drift check and break the deploy `resolve-target` logic |
| Phase 0 measurements | ask 1 ("so update detection compares versions") | inferred — justification: the post-mortem records that an unmeasured mechanism claim propagated into six governance files; M1 verifies the premise before building on it |

### Split Assessment

- Subsystems touched: 5 — `plugins/soleur`, `.github`, `scripts`, `knowledge-base`, `docs` (plus `apps/web-platform` for the legal SHA pin)
- Planned files: ~48 (Slice A ~22, Slice B ~26) | Estimated changed lines: ~2400
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — Slice A (resolver, hook, command, help header, legal carve-out, README) is one PR; Slice B (stamp workflow, gates, guards, ADR/rule reversal) is a second PR gated on Phase 0 and DC-1. Plan review (CPO, DHH, code-simplicity, architecture) independently reached the same boundary; the Execution gate encodes it, and the two slices may ride one branch only if the operator confirms DC-1.

## Design Decisions

- **D1 (User-Challenge, headless: persisted to `specs/feat-one-shot-plugin-version-visibility/decision-challenges.md`).**
  The brief's item 1 reverses ADR-182 D1. CTO recommends Option B (keyless default) first. This
  plan keeps the brief's direction (Option A) but as gated Slice B, with Option B (keyless
  resolver: SHA + tag lookup) as both the shipped baseline in Slice A and the no-go fallback.
- **D2.** One resolver: `plugins/soleur/scripts/plugin-version.sh` with modes
  `--installed`, `--latest [--refresh]`, `--cached-latest`, `--compare`. Precedence for installed:
  manifest `.version` matching `^[0-9]+\.[0-9]+\.[0-9]+$` (parsed with `jq` when present, else a
  `sed` fallback — users may lack `jq` and the hook must fail open), else the basename of
  `${CLAUDE_PLUGIN_ROOT}` matching `^[0-9a-f]{12}(-[0-9a-f]{8})?$` (the optional suffix is the
  `git-subdir` path hash the docs describe; Phase 0 M2 records the exact shape and this regex is
  corrected to it), reported as `commit <sha12>`, else `unknown`. Output is `key=value` lines so
  callers and tests parse one shape. Never reports a version it did not read. When the root is
  unset (non-Claude harness) it prints `source=none` and callers print nothing.
- **D3.** Latest release = highest tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$` from
  `git ls-remote --tags https://github.com/jikig-ai/soleur.git 'refs/tags/v*'` (no token, no API
  rate limit; strict regex excludes `vinngest-v*`, `web-v*`, `zot-image-*` and prerelease
  suffixes; `sort -V`; peeled `^{}` lines kept to read the tag's commit). Fixed URL, never read
  from a manifest or env. `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=/bin/true`.
- **D3b (keyless compare rule — fixes spec-flow #1 and Kieran #5).** `ls-remote` maps tags to
  commits; it cannot say whether an installed commit is older or newer than a tag (the installed
  commit is a `main` commit, usually not the tagged one). `--compare` therefore makes ONE
  unauthenticated call `GET https://api.github.com/repos/jikig-ai/soleur/compare/<sha12>...<latest-tag>`
  and reads `ahead_by`: `> 0` means the tag has commits the install lacks (a newer release
  exists); `0` (status `identical` or `behind`) means the install is at or past the latest
  release. Status `diverged` (installed commit not on `main`) prints `relation=unknown` ("installed commit is not on main"). Any failure prints `relation=unknown` and the human text says "cannot compare", never
  "up to date". For a stamped install the comparison is plain semver of `.version` vs the latest
  tag, plus the stamp-lag note (below). M5 measures both calls.
- **D4.** Hook: `SOLEUR_UPDATE_CHECK=1` (exactly `1`; `0`, empty, anything else is off) enables
  the network (default off); `SOLEUR_DISABLE_VERSION_BANNER=1` silences the banner (matches the
  repo's `SOLEUR_DISABLE_*` kill-switch convention). Matcher `startup` only. Skips silently when
  `CLAUDE_PLUGIN_ROOT` is unset or on the same non-Claude markers `welcome-hook.sh` uses
  (`CODEX_THREAD_ID`, `PLUGIN_ROOT`). User-visible channel is top-level `systemMessage`; no
  `additionalContext` (zero token cost). Cache `${XDG_CACHE_HOME:-$HOME/.cache}/soleur/latest-release`
  (dir `0700`, file `0600`, atomic temp+`mv`; a future-dated mtime counts as stale), TTL 24 h. A
  stale cache triggers a detached background refresh launched with `setsid nohup` and stdin,
  stdout and stderr all redirected to `/dev/null` (otherwise the hook's pipes stay open and the
  session waits); the hook uses the stale value now and never blocks on the network. The hook
  test waits on a sentinel file, not a sleep. Hook `timeout` 10. Fail open (exit 0, no output on
  any error). First-run: the banner and the `welcome-hook.sh` message are two separate JSON
  objects from two hooks; the plan accepts two stacked lines and the welcome hook already runs
  once per project.
- **D5.** `/soleur:version` is the explicit-invocation path: synchronous lookup (timeout 8 s,
  writes the cache) regardless of `SOLEUR_UPDATE_CHECK`, because the user asked. It prints:
  installed version + source (manifest/commit); latest release; the compare result; the update
  commands from `plugin-delivery-recovery.md` (Claude Code only; other harnesses get
  harness-appropriate text or no command); a one-line opt-in hint for the SessionStart check
  (set `SOLEUR_UPDATE_CHECK=1` in the Claude Code settings `env` block; remove it to turn off); and
  the stamp-lag note ("a new release can take up to ~2 hours to reach `plugin update` while its
  version stamp merges") when the manifest is stamped. Explicit messages for offline, `git`
  missing, 8 s timeout, zero tags returned, and unreadable cache — each says WHY latest is
  missing, never reading as "up to date".
- **D6 (Slice B).** Stamp via bot PR in its OWN workflow `stamp-plugin-version.yml`
  (`workflow_run` after "Version Bump and Release" completes + `workflow_dispatch` with
  `dry_run`, default true), reconcile-to-max, deterministic branch `soleur/plugin-version`,
  commit/PR identity `soleur-infra[bot]`, token scope `contents:write` + `pull_requests:write`
  on repo `soleur` only (ADR-232 grant check; the script pattern lives in
  `.github/scripts/bump-inngest-bootstrap-pin.sh`, workflows `build-inngest-bootstrap-image.yml`
  / `mint-inngest-bootstrap-tag.yml`), job `environment: infra-privileged` (main-only branch
  policy: a branch dry-run must not request the environment), concurrency group
  `plugin-version-stamp` (`cancel-in-progress: false`), arm auto-merge, `timeout-minutes: 10`.
  Dark-launched: live path runs only when repo variable `PLUGIN_VERSION_STAMP` equals `on`;
  otherwise it prints a `would-stamp` summary (the diff) and exits 0.
- **D7 (Slice B).** Loop gate is content-based, not message-based, and the rationale is recorded
  because a path negation would be simpler and wrong (a `paths: '!...plugin.json'` filter would
  drop `mcpServers`-only releases):
  `scripts/is-plugin-version-stamp-commit.sh <sha>` exits 0 iff the commit's diff against its
  first parent is exactly `plugins/soleur/.claude-plugin/plugin.json` and
  `jq -S 'del(.version)'` of old and new are identical. A PR title cannot spoof it. It fails
  closed: any error means "not a stamp" and the normal release proceeds. Call sites:
  (i) a `gate` job in `version-bump-and-release.yml` — `actions/checkout` `fetch-depth: 2`; the
  step maps ANY script error to `stamp=false` with the job staying green (a red gate would skip
  `release` through `needs:` and silently lose a content release);
  (ii) `web-platform-release.yml` — `release` is a `uses:` reusable-workflow job and cannot hold
  steps, and its `workflow_run` deploy arm's `resolve-target` treats a SKIPPED `release` job as a
  fault (`release_job_unresolvable` / `release_failed`); only `check_changed` declining gives the
  clean `upstream_concluded_unpublished` skip. Therefore the web gate needs ONE small change in
  `reusable-release.yml`'s `check_changed` step (a new optional input, default empty, naming a
  script whose exit 0 makes `changed=false`), not a skipped job. This is the single place Slice B
  touches `reusable-release.yml`; the hunk (the `check_changed` step, ~lines 150-183) is far from
  draft #7390's provenance build-arg region (Docker build steps, ~line 785 onward). Slice B
  decision point: if that edit is judged too risky, Slice B stays deferred. Guard 1 members:
  both workflows, `workflow-run-deploy-invariants.test.sh`, `prod-version-drift-check.sh`.
- **D8 (Slice B).** Feature PRs still must not change `.version`. Replace "key absent" tests with
  a guard (five lines of `jq` in the existing `ci.yml` validator step unless a standalone script
  proves necessary): a PR whose author is not `soleur-infra[bot]` may not change the value of
  `.version` in `plugin.json`, including adding or deleting the key. It runs on the
  `pull_request` event only; on `merge_group` it no-ops green (there is no PR payload there, and
  the PR-level run already judged the same diff). No bootstrap exception: the first stamp is
  bot-authored through the normal path; the escape hatch is `--remove-key`.

## Architecture Decision (ADR/C4)

Detected: reversal of ADR-182 Decision 1 and ADR-017; new privileged workflow-authored PR path
to main; new network edge from the installed plugin to GitHub.

### ADR

- Amend `ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md`: dated amendment
  narrowing Decision 1 from "no manifest carries a `version` key" to "no CONSTANT version; the
  in-repo `plugin.json` may carry a release-stamped version under conditions (a) stamp reconciles
  to the semver-max tag, (b) published manifest and `.claude-plugin/marketplace.json` stay
  keyless, (c) stamp lag is bounded and monitored". Add the rejected alternatives (direct push,
  synthetic-check bot PR, label file, stamping marketplace.json) to its table.
- Amend `ADR-017-version-from-git-tags.md` (versions still come from tags; the stamp is derived).
- New ADR, provisional ordinal ADR-285 (ship's collision gate re-verifies against `origin/main`;
  if renumbered, sweep plan + tasks + AC for the old ordinal): "Release-stamped plugin
  version via a workflow-authored bot PR, with a content-based loop gate" — status `adopting`
  (true only after Phase 0 passes and the dark-launch flag is flipped).
- Edit `AGENTS.rules.md` rule body `wg-never-bump-version-files-in-feature` (feature PRs never
  bump; the key is release-stamped by `soleur-infra[bot]` only; never commit a constant). Rule
  body edits are gated by the `rule-body-lint` required check (ADR-092, AP-017): the ack is
  per-change and hash-bound in `.claude/rule-weakening-acks.txt` (CODEOWNERS WORM) — a HUMAN
  gate. Slice-B-only (see Execution gate).
- Edit prose that states the old rule: `plugins/soleur/AGENTS.md` (Manifest versioning),
  `CONTRIBUTING.md`, `ship/SKILL.md` (line ~3024 bullet), `work/SKILL.md`, `release-announce/SKILL.md`,
  `scheduled-marketplace-drift.yml` comments, `plugin-delivery-recovery.md`, post-mortem
  cross-reference note.

### C4 views

Read all three of `model.c4`, `views.c4`, `spec.c4` before editing (completeness mandate; a
keyword grep is not evidence). Known-affected, from a first pass (deepen-plan re-verifies):

- `model.c4` `platform.plugin` (~line 166) and `soleurMarketplace` (~373-380) descriptions
  assert "keyless"; adjust to "the published entry is keyless; the plugin manifest carries a
  release-stamped version".
- New edge `platform.plugin -> github` "Opt-in latest-release tag lookup (git ls-remote), 24 h
  cache, default off" (external actor/system check: GitHub already modeled at ~366; the human
  actor `founder` already installs the plugin; no new actor or data store).
- New edge `github -> github` is NOT added; the bot-PR stamp is inside the GitHub CI system. If
  the `soleur-infra` App is already modeled as a CI identity, add the sentence to its
  description, otherwise add it as a description note only.
- Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
  `bash plugins/soleur/test/c4-count-parity.test.sh` after edits (no component/command-count
  claim in edge prose may go stale: Commands 3 -> 4).

### Sequencing

ADR text describes the target state with `status: adopting`; it flips to `accepted` only after the
post-merge soak follow-through (see Acceptance Criteria, Post-merge).

## Implementation Phases

### Phase 0 — Falsification gate (measure before building Slice B)

Output: `knowledge-base/project/specs/feat-one-shot-plugin-version-visibility/measurements.md`.
Reuse the clean-`HOME`, local-marketplace harness style of `feat-one-shot-7471-plugin-delivery-path/measurements.md` section 1.9.

- M1. Two commits of a fixture plugin (git-subdir AND relative-path sources) with `plugin.json`
  `version` "1.0.0" then "1.0.1" and changed content: `claude plugin update` must fetch the new
  content (arm B); same-version-different-content must no-op (arm A, re-confirms #7471).
- M2. Recorded `version` and cache directory name in `installed_plugins.json` for stamped vs
  keyless installs (confirms `basename "$CLAUDE_PLUGIN_ROOT"` is the version dir).
- M3. Published-channel shape: keyless marketplace entry + versioned `plugin.json` at the
  `git-subdir` path resolves to the manifest version, and `claude plugin validate` accepts it.
- M4. A plugin SessionStart hook emitting `{"systemMessage": "..."}` is shown to the user (run
  `claude --plugin-dir plugins/soleur -p ... --output-format stream-json --include-hook-events`).
  If it is not rendered, D4 falls back to a one-line `additionalContext` (answer-only-if-asked).
- M5. `git ls-remote --tags --refs <url> 'refs/tags/v*'` latency and bytes on this repo; must
  finish well under the 5 s cap. If not, switch D3 to the unauthenticated releases API.
- M6. Stale-window baseline refresh: created-to-merged minutes for the last 30 `app/soleur-infra`
  PRs. Go/no-go for Slice B requires M1 arm B pass AND p95 recorded; the lag is then stated in
  the ADR and README rather than hidden.

Go for Slice B iff M1 (arm A no-op, arm B updates, both source shapes), M3 pass, AND M6 shows
p95 stamp lag <= 120 minutes AND the operator has confirmed DC-1 (Execution gate). Otherwise:
no-go, Slice B tasks (and its governance edits) are skipped, a follow-up issue is filed
(milestone from `knowledge-base/product/roadmap.md`), and Slice A ships alone. M2 additionally
records the exact cache dir-name shape for a `git-subdir` install (D2 regex), and M5 measures
both `git ls-remote` and the compare API call (D3b).

### Phase 1 — Shared resolver and its tests (Slice A)

Create `plugins/soleur/scripts/plugin-version.sh` (D2, D3) and
`plugins/soleur/test/plugin-version.test.sh` (fixtures synthesized; a stub `git` on `PATH` for
`ls-remote`). Cases: stamped manifest; keyless manifest + SHA-named root; neither; garbage
version string ignored; tag filter (`vinngest-v1.1.50`, `web-v0.9.9`, `zot-image-v2.1.20`,
`v3.335.8-rc1` rejected; `v3.335.8` vs `v3.335.10` ordered numerically); stale cache; corrupt
cache; unwritable cache dir (still exits 0); no network (timeout path); output identical with
and without the manifest key apart from `source=`.

### Phase 2 — Hook (Slice A)

Create `plugins/soleur/hooks/version-banner.sh` and register one SessionStart block in
`hooks.json` (matcher `startup`, `timeout: 10`, `bash "${CLAUDE_PLUGIN_ROOT}/hooks/version-banner.sh"`),
placed after the `welcome-hook.sh` block. Create `plugins/soleur/test/version-banner-hook.test.sh`
modelled on `compaction-state-hook.test.sh`: default-off makes zero network calls (stub `git`
records invocations and the suite asserts none); opt-in with fresh cache prints the warning
without calling git; opt-in with stale cache prints the stale result and spawns one background
refresh; kill switch silences; output is a single valid JSON object; hook exits 0 when `HOME` is
read-only. Keep the other-harness behavior consistent with `welcome-hook.sh` (`CODEX_THREAD_ID`,
`PLUGIN_ROOT` skip) and skip silently when `CLAUDE_PLUGIN_ROOT` is unset (print nothing, never
`(version unknown)` noise). Extra rows from review: the detached refresh closes all three fds and
the test waits on a sentinel file; a future-dated cache mtime is treated as stale; a downgrade
(installed newer than the cached latest) prints no warning; two concurrent starts do not
double-fetch (atomic `mv`, one refresh per TTL); `SOLEUR_UPDATE_CHECK=0` and empty are off; the
resolver works with `jq` removed from `PATH` (sed fallback).

### Phase 3 — `/soleur:version` and help header (Slice A)

- Create `plugins/soleur/commands/version.md` (frontmatter `name`, `description`,
  `argument-hint`; body runs the resolver via Bash and prints a fixed block).
- Edit `plugins/soleur/commands/help.md` minimally: replace the Step 1 "carries no `version`
  key" paragraph with a resolver call, and add one header line `Soleur <version>` to the Claude
  Code block. Do NOT touch Step 2.5 or the Cursor column (draft #9745 edits those regions).
- Update counts: `plugins/soleur/README.md` (Commands 3 -> 4 and table row),
  `invocation-axis.test.ts` floor stays valid, slash-name uniqueness (confirm no skill named
  `version`), harness mirrors for commands (cursor/grok/codex/devin per their generators; run the
  `cursor-plugin`, `codex-plugin`, `devin-plugin`, `harness-parity` suites), `release-docs` counts.
- Legal (CLO; the carve-out must cover BOTH the opt-in hook AND an explicit `/soleur:version`
  run, since D5 makes that call without opt-in; the default-zero-network claim stays true only for
  the hook): add the one-sentence carve-out to `docs/legal/privacy-policy.md` Section 4.1 and
  `docs/legal/data-protection-disclosure.md`, mirror to `plugins/soleur/docs/pages/legal/`, re-pin
  `apps/web-platform/lib/legal/legal-doc-shas.ts`, run the five legal CI gates listed in the CLO
  note; grep the Cookie Policy and Disclaimer for "no network" claims.
- `/soleur:version` text per D5 (explicit failure messages, opt-in hint, stamp-lag note, compare
  rule D3b, harness-aware update commands: Claude Code prints `claude plugin ...`; Cursor/Codex/
  Devin/Grok print the harness's own reinstall pointer or none). `/soleur:help` header in the
  unknown state prints no version line, only a fix hint pointing at `/soleur:version`.
- README/doc: how to opt in (`"env": {"SOLEUR_UPDATE_CHECK": "1"}` in Claude Code settings).

### Phase 4 — Stamp pipeline (Slice B; runs only past the Execution gate AND Phase 0 Go)

Corrected by plan review (architecture-strategist B3/H1/H2/M2): the stamp lives in its OWN
workflow, not a job in `version-bump-and-release.yml`, because (a) a `workflow_dispatch` of that
caller passes `force_run=true` and would publish a REAL tag/release — a "dry-run" there is not a
dry-run; (b) a separate `workflow_run` workflow runs only after the release is published and the
tag exists (resolves tag/stamp ordering); (c) it keeps edits to the shared release callers to a
single gate job each.

- Create `.github/workflows/stamp-plugin-version.yml`: `on: workflow_run` of "Version Bump and
  Release" (`types: [completed]`, `branches: [main]`, success only) plus `workflow_dispatch` with
  `dry_run` (default `true`). Job `environment: infra-privileged`, App token (D6), concurrency
  group `plugin-version-stamp` (`cancel-in-progress: false`), `timeout-minutes: 10`, and an
  `if:` on repo variable `PLUGIN_VERSION_STAMP == 'on'` (otherwise the dry-run summary only).
  Dry-run opens no PR, mints no token beyond the grant check, and creates no release.
- Create `scripts/stamp-plugin-version.sh` (reconcile-to-max over tags merged into main,
  deterministic branch, idempotent, asserts the diff is exactly the version line, refuses under
  `set -x` with a token set, mirrors `bump-inngest-bootstrap-pin.sh` stages and
  `result=opened|existing|noop|skipped|error`). Two extra rules from review:
  1. **Queued-PR rule (H3):** if the open stamp PR is already in the merge queue or has
     auto-merge armed (`gh pr view --json mergeQueueEntry,autoMergeRequest`), leave it untouched;
     the next release's run follows up after it merges. Never force-update a queued branch.
  2. **`--remove-key` mode (B1 rollback):** opens a bot PR that deletes `.version` (same gates,
     same identity). Runbook entry + invoked on no-go-after-stamp, on soak failure, and before
     flipping the variable off for good. A frozen stamp on main is the #7471 shape and must have
     a tested exit.
  Plus `scripts/stamp-plugin-version.test.sh`.
- Create `scripts/is-plugin-version-stamp-commit.sh` + test (D7).
- Edit `.github/workflows/version-bump-and-release.yml`: add a `gate` job; `release` gets
  `needs: gate` and `if: needs.gate.outputs.stamp != 'true'`. Nothing else.
- Edit `.github/workflows/reusable-release.yml` `check_changed` step ONLY (D7(ii)): a new
  optional input (default empty) naming a repo-relative script; exit 0 makes `changed=false`, which
  yields the clean `upstream_concluded_unpublished` skip that `resolve-target` already handles.
  `web-platform-release.yml` passes `scripts/is-plugin-version-stamp-commit.sh`; the plugin caller
  does not need it (it uses its own `gate` job). Do NOT skip the `release` job in the web
  workflow: `resolve-target` treats a skipped caller job as a fault (`release_job_unresolvable`).
  Extend `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` (mutation rows on exactly this
  logic) — a Guard 1 member. Merge-conflict note: draft #7390 edits this file in the Docker build
  region; this hunk is the `check_changed` step; rebase order decided at merge time.
- Edit `scripts/prod-version-drift-check.sh` (+ its test, byte-parity row B8): its PATHSPEC is
  pinned to `web-platform-release.yml`; a gated stamp-only commit matches `plugin.json` but is
  never deployed, so the drift check would go red on every release. Mirror a carve-out for stamp
  commits (use the same `is-plugin-version-stamp-commit.sh`) and add a regression row.
- Create `scripts/plugin-version-pr-guard.sh` + test (D8), `pull_request` event only (a
  `merge_group` run has no PR payload — the guard no-ops there, by design), wired into `ci.yml`
  beside `marketplace-manifest-validate.sh` (line ~632); register suites in `scripts/test-all.sh`.
  Simplicity review: if the PR guard can be five lines of `jq` in the existing step, do that
  instead of a standalone script.
- Update `plugins/soleur/test/plugin-version-fallback.test.ts`: the "no version key" assertions
  become "if a version is present it is semver; marketplace entry and published manifest stay
  keyless; `mcpServers` intact". These test edits land in the SAME change that stamps (Slice B),
  never in Slice A (Slice A leaves the key-absent tests green).
- Extend `scheduled-marketplace-drift.yml` with the stale-stamp assertion (G2): main
  `plugin.json` version vs semver-max `v*` tag. **SLO = 3 h** (not 6 h: the measured window is
  41-112 min; a ceiling far above it hides a stuck stamp). Red when lag exceeds the SLO; also
  red when the stamp is ahead of the max tag. Keep Assertion 1 (published entry keyless) verbatim.

#### Slice B conditions (CPO; all required before the flag flips)

1. M6 p95 over the last 30 bot PRs is recorded and published in the README and the runbook; **Go
   requires p95 stamp lag <= 120 minutes** (explicit ceiling, not just "recorded").
2. M1 arm A (constant version no-ops) AND arm B (changed version updates) both reproduce, on
   both source shapes.
3. Dark launch with `dry_run` green on `main`, then ONE staged live stamp observed end to end
   (App token, required checks on the one-file PR, auto-merge, no release run and no web build on
   the stamp SHA) before any soak count starts; abort path = `--remove-key` PR.
4. Soak is >= 7 days AND >= 3 releases (a quiet week must not pass vacuously).
5. Tested rollback (`--remove-key`) with its own gate pass, plus the documented recovery for a
   user stuck on a stamped version (reinstall via the runbook's `marketplace update` path).
6. CLO sign-off on the privacy carve-out lands before merge (Slice A, see Phase 3).
7. All governance reversals (ADR-182/017 amendments, ADR-285, rule-body edit, removal of
   key-absent tests, Guard 3 bootstrap allowance, drift canary) land in the SAME change as the
   stamp, conditional on Go. If Slice B is deferred to a second PR, NONE of them are in the first.
8. ADR-285 records the delivery-coupling tradeoff: stamped delivery depends on release success,
   then stamp-PR CI, then queue latency (any failed release or red stamp PR silently no-ops
   `plugin update` for everyone); it also records the extra serial merge-queue entry per release
   (coalesced to <= 1 open stamp PR) as accepted cost.
9. The rule-body edit needs the per-change, hash-bound ack required by AP-017 / ADR-092
   (`rule-body-lint`) — read ADR-092 before editing; it is not a free-text ack.
10. Guard 3 bootstrap: the first stamp is authored by `soleur-infra[bot]` through the normal path
    (the guard permits bot authors); a human-authored key add never passes. The escape hatch for a
    bad stamp is `--remove-key`, not a guard exception.

### Phase 5 — Docs, ADR, rule edits (both slices)

ADR amendments + ADR-285, rule body edit, prose edits listed under Architecture Decision, C4
edits and validations, runbook note in `plugin-delivery-recovery.md` explaining the stamp window
and how to read `claude plugin list` (version vs SHA).

### Phase 6 — Verification

Run the new suites, `bash plugins/soleur/test/c4-count-parity.test.sh`, `components.test.ts`,
marketplace validator/test, `actionlint` on both edited workflows, plus a `workflow_dispatch`
of `stamp-plugin-version.yml` with `dry_run=true` (never of the release caller: its dispatch cuts a
real release); the dry-run must not request the `infra-privileged` environment. Post-merge steps are in
Acceptance Criteria.

## Files to Edit

- `plugins/soleur/commands/help.md` (Step 1 paragraph + one header line only)
- `plugins/soleur/hooks/hooks.json` (one new SessionStart block)
- `plugins/soleur/README.md` (command count/table, opt-in docs)
- `.github/workflows/version-bump-and-release.yml` (Slice B: `gate` job + `needs`/`if` on `release`)
- `.github/workflows/reusable-release.yml` (Slice B: ONE optional input on the `check_changed` step; see D7)
- `.github/workflows/web-platform-release.yml` (Slice B: pass the gate script input)
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh`, `scripts/prod-version-drift-check.sh`,
  `scripts/prod-version-drift-check.test.sh` (Slice B: stamp carve-out + regression row; B8 parity)
- `.github/workflows/scheduled-marketplace-drift.yml` (Slice B: stale-stamp assertion; comments)
- `.github/workflows/ci.yml` (Slice B: PR guard + stamp script suites)
- `scripts/test-all.sh` (register new suites)
- `plugins/soleur/test/plugin-version-fallback.test.ts` (Slice B)
- `plugins/soleur/.claude-plugin/plugin.json` (NOT edited by this PR; stamped by the bot only)
- `AGENTS.rules.md` (rule body `wg-never-bump-version-files-in-feature`), `plugins/soleur/AGENTS.md`,
  `CONTRIBUTING.md`, `plugins/soleur/skills/ship/SKILL.md`, `plugins/soleur/skills/work/SKILL.md`,
  `plugins/soleur/skills/release-announce/SKILL.md`
- `knowledge-base/engineering/architecture/decisions/ADR-182-*.md`, `ADR-017-*.md`,
  `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` only if an edge needs a view line)
- `knowledge-base/engineering/operations/runbooks/plugin-delivery-recovery.md`
- `docs/legal/privacy-policy.md`, `docs/legal/data-protection-disclosure.md`, their
  `plugins/soleur/docs/pages/legal/` mirrors, `apps/web-platform/lib/legal/legal-doc-shas.ts`
- harness command mirrors/generated stubs for the new command per their generators

Every glob above was checked against `git ls-files`; `.claude-plugin/marketplace.json` and
`infra/github/soleur-marketplace-manifest.json` are deliberately NOT edited.

## Files to Create

- `plugins/soleur/scripts/plugin-version.sh`, `plugins/soleur/test/plugin-version.test.sh`
- `plugins/soleur/hooks/version-banner.sh`, `plugins/soleur/test/version-banner-hook.test.sh`
- `plugins/soleur/commands/version.md`
- `.github/workflows/stamp-plugin-version.yml` (Slice B)
- `scripts/stamp-plugin-version.sh`, `scripts/stamp-plugin-version.test.sh` (Slice B)
- `scripts/is-plugin-version-stamp-commit.sh`, `scripts/is-plugin-version-stamp-commit.test.sh`
- `scripts/plugin-version-pr-guard.sh`, `scripts/plugin-version-pr-guard.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-285-release-stamped-plugin-version-via-bot-pr.md`
- `knowledge-base/project/specs/feat-one-shot-plugin-version-visibility/{tasks.md,measurements.md,decision-challenges.md}`
- `scripts/followthroughs/plugin-version-stamp-soak-<issue>.sh` (soak enrollment, see below)

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies searched for every file path in
Files to Edit; zero matches.)

## Merge-conflict risk (open draft PRs)

- **#9745** (`feat(cursor): record the CLI hook captures`) edits `plugins/soleur/commands/help.md`
  (cursor harness docs). This plan touches only Step 1 and the header line of the Claude Code
  block. Risk: low-to-medium (adjacent hunks if #9745 also edits the top of the file). Mitigation:
  keep the diff to two hunks; whoever merges second rebases; no reformatting of the file.
- **#7390** (`WIP: provenance build-arg secret`) edits `.github/workflows/reusable-release.yml`.
  Slice A does NOT touch that file (risk: none). Slice B edits ONE optional input on the
  `check_changed` step (D7); #7390 edits the Docker build region, so hunks do not overlap, but it
  is the same file: whoever merges second rebases, and Slice B is the one that waits if #7390 is
  still open. `web-platform-release.yml`'s `with:` block gets one added input line.
- `hooks.json`, `plugin.json`, `version-bump-and-release.yml`: verified against the open-PR file
  lists (`gh pr list --state open --json files`); only #9745 (help.md) and #7390
  (reusable-release.yml) match any file this plan touches.

## Acceptance Criteria

### Pre-merge (PR) — Slice A (always)

- [ ] Phase 0 `measurements.md` committed with M2, M4, M5 (needed by Slice A) and, if Slice B is
  in play, M1, M3, M6 and an explicit Go/No-go line.
- [ ] `bash plugins/soleur/scripts/plugin-version.sh --installed` prints `version=`/`source=` lines
  for a stamped root, a keyless SHA-named root (both dir-name shapes) and no root (`source=none`);
  suite includes tag-filter, corrupt-cache, unwritable-cache, no-`jq` and no-network rows.
- [ ] `--compare` rows: `ahead_by > 0` -> newer exists; `0` -> at/past latest; API failure ->
  `relation=unknown` and the text says "cannot compare" (never "up to date").
- [ ] Default-off proof: with `SOLEUR_UPDATE_CHECK` unset (or `0`/empty) the hook suite asserts zero
  `git` invocations; set with a fresh cache, still zero; only a stale cache spawns one refresh
  (sentinel-awaited), with fds closed.
- [ ] Hook output on startup is one JSON object whose `systemMessage` matches
  `^Soleur (v[0-9]+\.[0-9]+\.[0-9]+|commit [0-9a-f]{12})`; with no plugin root it prints nothing.
- [ ] `/soleur:help` header shows the version line; Step 2.5 and the Cursor column are
  byte-identical to `origin/main` (diff check).
- [ ] `commands/version.md` exists with the D5 messages; README counts Commands = 4;
  `components.test.ts`, `invocation-axis.test.ts`, harness parity suites green; no skill named
  `version`.
- [ ] Legal carve-out (covers hook AND explicit command) in privacy policy + DPD + mirrors, SHA
  pins updated, five legal gates green; CLO sign-off recorded.
- [ ] The existing key-absent tests (`plugin-version-fallback.test.ts`), the published-manifest
  validator and the drift Assertion 1 are UNCHANGED and green (Slice A must not touch them).
- [ ] CPO sign-off for Slice A recorded (frontmatter `requires_cpo_signoff: true`);
  `decision-challenges.md` carries DC-1..DC-3; a tracking issue exists and is cited (see Deferral
  tracking); PR body carries `## Changelog`, `semver:minor`, and `Ref #<tracking issue>`.

### Pre-merge (PR) — Slice B (only past the Execution gate and Phase 0 Go)

- [ ] All "Slice B conditions" 1-10 above hold; M6 p95 <= 120 min recorded in README + runbook.
- [ ] Guard 1/2/3 suites green with their full mutation matrices; `actionlint` clean on every
  edited workflow; `workflow-run-deploy-invariants.test.sh` and `prod-version-drift-check.test.sh`
  (B8) green with the stamp carve-out rows.
- [ ] `stamp-plugin-version.yml` `workflow_dispatch` with `dry_run=true` prints `would-stamp`,
  opens no PR, cuts no release, and requests no environment.
- [ ] `.claude-plugin/marketplace.json` `plugins[0]` and `infra/github/soleur-marketplace-manifest.json`
  remain keyless; validator and its test pass.
- [ ] The PR does not itself modify `plugin.json` `.version` (Guard 3 passes on this PR).
- [ ] ADR-182/017 amended, ADR-285 written (`adopting`, with the delivery-coupling and queue-load
  tradeoffs and the `--remove-key` rollback), rule body edited with the per-change hash-bound ack
  in `.claude/rule-weakening-acks.txt` — that file is CODEOWNERS-owned WORM, so the ack is a
  human gate the agent cannot self-grant (surface it at ship), C4 files updated and C4 tests
  green.

### Post-merge (Slice B; operator-free, agent-run)

- [ ] `gh variable set PLUGIN_VERSION_STAMP --body on` only after a green `dry_run` on `main`;
  then ONE staged live stamp is observed end to end before the soak starts.
- [ ] That stamp PR merges and its push produces NO plugin release run and NO `Web Platform
  Release` build, and `scheduled-prod-version-drift` stays green (verify via `gh run list` for
  the stamp SHA).
- [ ] `claude plugin list --json` on a clean `HOME` install shows the semver version; a second
  release moves it (M1 behavior observed on the real channel).
- [ ] Soak follow-through enrolled: >= 7 days AND >= 3 releases with lag below the 3 h SLO, then
  ADR-285 `adopting -> accepted`; failure action = `--remove-key` PR.

## Guard Contract

### Guard 1 — stamp-commit loop gate

**Property.** A push to main whose diff against its first parent is exactly a `.version` change
in `plugins/soleur/.claude-plugin/plugin.json` starts no plugin release and no web-platform
build, and any other change under `plugins/soleur/` (including a non-version edit to
`plugin.json`) still releases.

**Assembly.** Every workflow that fires on `plugins/soleur/**`: `version-bump-and-release.yml`
(release job via its `gate` job), `web-platform-release.yml` (the `check_changed` gate input and
the `workflow_run` deploy arm / `resolve-target` that consume it),
`scripts/prod-version-drift-check.sh` (PATHSPEC parity with the web workflow), plus any
other push-triggered workflow whose `paths:` include `plugins/soleur/**` (enumerate with
`git grep -n "plugins/soleur" .github/workflows` and classify each as release-class or
check-class). The chokepoint is the single script `scripts/is-plugin-version-stamp-commit.sh`;
both workflows must call it, and a test asserts the set of release-class workflows equals the
set that calls it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Commit changes `.version` AND `mcpServers.context7.url` in plugin.json | gate returns "not a stamp" (non-zero) |
| 2 | Commit changes `.version` in plugin.json AND adds one file under `plugins/soleur/skills/` | gate non-zero |
| 3 | Stamp-only commit, then a second compliant stamp-only commit (two members) | both exit 0; a third commit mixing in a doc edit exits non-zero (a check that stops at the first member fails) |
| 4 | Remove the gate input from `web-platform-release.yml` (or the `check_changed` branch from `reusable-release.yml`) | workflow-coverage assertion reds (guard's own dispatch) |
| 4b | Replace the web gate with a skipped `release` job | `workflow-run-deploy-invariants.test.sh` reds (`release_job_unresolvable`) |
| 4c | Stamp-only commit with `PATHSPEC` unchanged in `prod-version-drift-check.sh` | drift-check test reds (counts an undeployed stamp) |
| 4d | Gate script errors out inside the `gate` job | job stays green with `stamp=false`, release still runs |
| 5 | Script run in a repo with no parent commit / corrupt blob / invalid JSON | exits non-zero (fail closed), never 0 |
| 6 | PR title spoofing `chore(release): stamp plugin version` on a content change | gate non-zero (content-based, not message-based) |

Harness rows: (a) neuter the script to `exit 0` -> rows 1-3, 5, 6 must red; (b) a must-PASS
input that is NOT the canonical stamp: plugin.json with different key ordering/indentation but
identical after `jq -S 'del(.version)'` must still be treated as a stamp; (c) the suite prints
`checked=N` and fails on `N=0`.

**Anchor.** The gate compares against the commit's own first parent (git object), so one diff
cannot move both sides; the workflow-coverage set is derived from the checked-in workflows, and
the floor is set identity (named workflows), not a count.

### Guard 2 — stale-stamp drift canary

**Property.** `plugin.json` `.version` on main equals the semver-max `^v[0-9]+\.[0-9]+\.[0-9]+$`
tag within the SLO, and the published entry and `.claude-plugin/marketplace.json` stay keyless.

**Assembly.** The scheduled job in `scheduled-marketplace-drift.yml` reading (1) raw `plugin.json`
at `main`, (2) `git ls-remote` tags, (3) the published manifest, (4) the in-repo marketplace
entry; its heartbeat check-in; and the validator `marketplace-manifest-validate.sh` for the
source manifest.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Stamp lags 2 tags behind for longer than the SLO | red with a lag message |
| 2 | Add `"version"` to the published manifest source | validator red (existing Assertion 1) |
| 3 | Add `"version"` to `.claude-plugin/marketplace.json` `plugins[0]` | new keyless assertion red |
| 4 | Stamp ahead of the max tag (version with no tag) | red (stamp must never invent a release) |
| 5 | Canary reads 0 tags (ls-remote empty) | red, never "ok" |

Harness rows: stub-gh/stub-git fixtures; a must-PASS where lag is inside the SLO.

**Anchor.** Tags are the external source of truth (immutable releases); the manifest value
cannot be edited to also move the tag.

### Guard 3 — no feature PR changes `.version`

**Property.** Only `soleur-infra[bot]` may change the value of `.version` in
`plugins/soleur/.claude-plugin/plugin.json`.

**Assembly.** The CI step `plugin-version-pr-guard` over the PR's diff of that file; PR author is
read from the PR event, not from commit trailers.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Human PR edits `.version` from 3.335.8 to 3.335.9 | red |
| 2 | Human PR adds the key where absent (outside the bootstrap allowance) | red |
| 3 | Human PR deletes the key | red |
| 4 | Human PR edits only `mcpServers` | green (precondition satisfied, property holds) |
| 5 | Bot-authored PR changes `.version` | green |

Harness rows: author spoof via commit message; guard step exits 0 with `checked=0`.

**Anchor.** Author identity comes from the GitHub event payload, which the PR diff cannot edit.

## Observability

```yaml
liveness_signal:
  what: scheduled-marketplace-drift.yml stale-stamp assertion + Sentry heartbeat check-in
  cadence: daily
  alert_target: Sentry cron monitor (existing marketplace-drift slug) + Slack ops via existing notify path
  configured_in: .github/workflows/scheduled-marketplace-drift.yml
error_reporting:
  destination: stamp job failure -> the release workflow's existing Slack/email failure steps; hook/resolver run on customer machines (layer 7) and emit NO telemetry by design (CLO)
  fail_loud: stamp job red run + GitHub Actions summary; hook fails open (silent) by design
failure_modes:
  - mode: stamp PR never merges (CI red / queue starvation)
    detection: Guard 2 lag > SLO
    alert_route: drift workflow failure -> ops notification
  - mode: stamp merge re-triggers release/web deploy (loop)
    detection: Guard 1 coverage test pre-merge; post-merge gh run list assertion in the soak script
    alert_route: soak follow-through script exits non-zero -> tracker stays open + comment
  - mode: hook blocks session start
    detection: hook suite asserts no network on the synchronous path and a 10 s hook timeout
    alert_route: pre-merge test failure (no runtime telemetry on user machines)
logs:
  where: GitHub Actions run summaries (stamp job result=opened|existing|noop|skipped|error)
  retention: GitHub default
discoverability_test:
  command: bash plugins/soleur/scripts/plugin-version.sh --installed
  expected_output: source=
```

Soak follow-through enrollment (Phase 2.9.1): tracker carries
`<!-- soleur:followthrough script=scripts/followthroughs/plugin-version-stamp-soak-<issue>.sh earliest=<deploy+7d> secrets=... -->`
plus the `follow-through` label; the script exits 0 when, over the last 7 days, every `v*`
release was followed by exactly one stamp merge within the SLO and no stamp SHA produced a
release or web build. Any new `secrets=` is wired into
`.github/workflows/scheduled-followthrough-sweeper.yml`.

## Infrastructure (IaC)

No new infrastructure. Reuses the existing `soleur-infra` GitHub App, `infra-privileged`
environment and `.github/actions/mint-infra-app-token`. No ruleset or Terraform change (the
`infra/github/` rulesets and bypass actors are untouched; this is the reason direct push was cut).
Repo variable `PLUGIN_VERSION_STAMP` is created post-merge by `gh variable set` (agent-run), not
by a human dashboard step. Host fan-out: not applicable.

## Domain Review

**Domains relevant:** engineering, legal, product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Top risks: (1) stale window can reintroduce #7471 for real users, merge-queue
latency unbounded; (2) release loop on the stamp commit, including a web-platform rebuild and
deploy; (3) the gate must be content-based and fail closed in both workflows; (4) tag and stamp
skew; (5) governance reversal needs ADR + narrow token. Recommended Option B (keyless) as the
default and shipping items 2-4 first, enabling the stamp only if Phase 0 proves update detection.
Plan response: Slice A is Option B plus resolver; Slice B is gated, dark-launched, with the loop
gate, canary and ADR. Pitfalls to test (concurrency pending-slot displacement, stamp gate before
the concurrency group, deterministic branch, auto-merge timeout, keyless-entry assertion) are in
Guards 1-2 and Phase 4.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Opt-in is sufficient (ePrivacy 5(3): user-initiated, local cache strictly
necessary); no Art. 30 entry (no Jikigai server, credential or identifier); privacy policy
Section 4.1 "does not phone home" needs a one-sentence carve-out mirrored in the DPD and in
`plugins/soleur/docs/pages/legal/`, with SHA re-pin and five legal gates. Constraints to keep:
default off, no Jikigai endpoint, no install id, generic user-agent, no telemetry, fail silent.

### Product/UX Gate

**Tier:** none (no new page, flow or interactive UI surface; terminal text and a command)
**Decision:** reviewed
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

### Product (CPO advisory, plan review)

**Status:** reviewed. **Verdict:** Slice A SIGNED OFF; Slice B CHANGES REQUESTED (reasons and
nine conditions folded into "Slice B conditions"). Roadmap fit: Phase 4 alpha-support triage;
no tracking issue existed (now specified under Deferral tracking). Slice A conditions: opt-in
default-off with honest privacy wording, hook fails open under a timeout, minimal `help.md`
hunks, M4 verified before the banner ships.

CPO sign-off is required by the threshold (`requires_cpo_signoff: true`); Slice A sign-off is
given, Slice B sign-off is withheld until the operator confirms DC-1 (`decision-challenges.md`).

## Test Scenarios

- Installed stamped plugin, opt-in off: banner `Soleur v3.335.8`, no network (stub asserts).
- Installed keyless plugin (SHA root): banner `Soleur commit b78d30e919ff`; `/soleur:version`
  reports the compare result via the API call (D3b) when online, else "cannot compare"; offline
  prints installed only and says why latest is missing.
- Opt-in on, cache fresh and newer tag known: warning with the two update commands; same tag:
  no warning.
- Cache corrupt/unwritable, DNS down, `git` missing: exit 0, no stack trace, banner still printed.
- Two releases merge before one stamp: exactly one stamp PR, value = max tag.
- Stamp push: no release run, no web build run.
- Feature PR that edits `.version`: guard red.

## Risks and Sharp Edges

- Bounded-by-release-health stale window (41-112 min measured for the PR leg alone; delivery
  also waits on release success and stamp-PR CI) where `plugin update` no-ops after a content
  merge; the stamp is therefore a display/accuracy feature with a delivery cost, which is
  why it is dark-launched and canaried. A stamp that stops advancing is the #7471 failure again.
- Release/web loop if either gate call is missing; test asserts coverage of every
  `plugins/soleur/**`-triggered release-class workflow, not just the two known today.
- `concurrency: release-plugin` keeps one pending run: a stamp-triggered run must be gated out
  BEFORE it enters the group or it can displace a queued content release (gate job precedes
  `release`; the stamp job is `needs: release` in the same run, not a new run).
- The bot's PR needs real required checks: the App token (not `GITHUB_TOKEN`) is mandatory.
  Required-check path filters on a one-file PR must still report (verify on the dry-run).
- `systemMessage` rendering at SessionStart is unmeasured until M4; fallback is specified.
- `${CLAUDE_PLUGIN_ROOT}` changes per version; the hook must resolve the version fresh each run
  (no state in the plugin root) and keep cache under `$XDG_CACHE_HOME`.
- `git ls-remote` prompts for credentials when a user has an insteadOf rule or an SSH-only
  config: set `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=/bin/true`, and `-c protocol.version=2`;
  fixed https URL; never inherit `GIT_*` overrides blindly.
- Plan-time: a plan whose `## User-Brand Impact` section is empty, TBD or lacks the threshold
  fails `deepen-plan` Phase 4.6; this one declares `single-user incident`.
- Deferred and tracked: if Phase 0 is no-go, file the follow-up issue (what, why, re-evaluation
  trigger: upstream CLI changes how `plugin update` compares, or the merge-queue p95 drops below
  15 min) with a milestone from `knowledge-base/product/roadmap.md`.

## Deferral tracking (issues to file; this plan run did not create them)

The planning run was restricted to plan/spec files, so the following GitHub issues are specified
here for the pipeline (`ship` Phase 6 / `soleur:work`) to file with `gh issue create`, milestone
"Phase 4" (internal tooling, per CPO; confirm against `knowledge-base/product/roadmap.md`):

1. **Tracking issue for this feature** — `feat: make the installed Soleur plugin version visible`
   (Slice A scope); the PR cites it with `Ref #<N>` (CPO finding: the plan had no issue/milestone).
2. **Deferred: release-stamped `version` in plugin.json (Slice B)** — what: stamp via
   `soleur-infra[bot]` PR, content-based loop gate, canary, ADR-182/017 reversal. Why deferred:
   CPO CHANGES REQUESTED (display feature vs #7471-shaped 41-112 min stale window; failure path
   depends on release-pipeline health). Re-evaluation criteria: merge-queue p95 stamp lag < 15
   minutes, OR a cohort need for semver in `/plugin` (alpha support triage), OR upstream changes
   how `claude plugin update` compares. Blocked-by: Phase 0 measurements M1/M3/M6 and operator
   confirmation of DC-1.

## Plan Review Outcome (2026-10-11)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CPO; CTO and CLO ran as
domain leaders earlier. Classification per ADR-084:

- **Mechanical, applied:** Kieran/architecture correctness fixes — separate `stamp-plugin-version.yml`
  (dispatch of the release caller cuts a real release); web gate must not skip the `release` job
  (`resolve-target` fails closed) -> `check_changed` input; `prod-version-drift-check.sh` and
  `workflow-run-deploy-invariants.test.sh` added to Guard 1; gate job maps errors to
  `stamp=false` and checks out depth 2; Guard 3 `pull_request` only; queued-PR rule;
  `--remove-key` rollback; SLO 6 h -> 3 h; Go criterion p95 <= 120 min; soak >= 3 releases;
  keyless compare rule (API compare, never "nearest" via ls-remote); detached-refresh fd
  hygiene; no-`jq` fallback; dir-name regex with path-hash suffix; harness skip matrix; `/soleur:version`
  failure messages, opt-in hint, stamp-lag note; legal carve-out covers the explicit command;
  rule-ack is a human gate.
- **User-Challenge (operator-requested scope; persisted in `decision-challenges.md`, not
  auto-applied):** DHH, code-simplicity and CPO all recommend cutting Slice B from this PR (and,
  for DHH/simplicity, cutting the hook and its cache/legal work). The plan keeps every asked item
  but places Slice B behind the Execution gate; the hook stays (explicitly asked: "cached,
  opt-in network"). DC-4 records the cut-the-hook alternative (banner without network; only
  `/soleur:version` networks).
- **Taste (surfaced):** fold the version into help only and skip `commands/version.md` (DHH #7);
  not applied because item 4 asks for the command.
