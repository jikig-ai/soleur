---
title: "Self-refreshing GitHub /meta CIDR generator for cron egress firewall"
issue: 5284
branch: feat-one-shot-github-meta-cidr-generator-5284
type: infra-feature
classification: infra-tooling
lane: cross-domain
brand_survival_threshold: aggregate pattern
date: 2026-06-14
deepened: 2026-06-14
---

## Enhancement Summary

**Deepened on:** 2026-06-14
**Agents used:** repo-research-analyst, learnings-researcher, architecture-strategist, Explore (precedent-diff).

### Key design correction (deepen-pass)
The regenerator is now an **Inngest cron** (`cron-github-cidr-refresh.ts`) modeled on
`cron-content-vendor-drift.ts`, routing through `safeCommitAndPr` (ADR-054) with
`mergeMode: "direct"` + synthetic checks — **not** a raw GHA `gh pr create + gh pr merge --auto`
workflow. Rationale: the raw-GHA design (modeled on `cla-evidence-timestamp.yml`, which targets
the non-`main` `cla-signatures` branch) would have hit a **stuck-PR-on-main** failure — auto-merge
+ the CLA-signed-author gate (`wg-cla-signed-author-before-merge`) + required checks block a
`github-actions[bot]` PR to `main`, and the workflow exits green after merely *opening* the PR, so
a never-merging PR is invisible — reintroducing the exact "silent missed unattended refresh" class
#5284 exists to kill. `cron-content-vendor-drift.ts` is the canonical "regenerate-from-external-
source → PR to main" precedent and already solves CLA/auto-merge via `safeCommitAndPr` synthetic
checks (`_cron-safe-commit.ts:43-44` knows `cla-check`/`cla-evidence`). This regenerator needs NO
terraform/cloud credentials (only an unauthenticated `/meta` fetch + repo write via the App
installation token), so it fits the **app-runtime Inngest + safeCommitAndPr** lane, not the
credential-heavy `scheduled-terraform-drift` lane.

### Other deepen-pass corrections
1. **Date-header churn (was a daily-spurious-PR bug):** the generator must NOT stamp a fresh
   `Snapshot: <date>` on every run, or `git diff` is never quiet and a no-op refresh opens a PR +
   churns `config_hash` daily. The diff/no-op decision is made on the **CIDR body only**; the date
   is restamped only when the body actually changes.
2. **Drift-guard de-circularized:** the offline CI guard asserts generator **determinism** against
   a synthesized fixture (fixture-in → golden-out) + structural floor asserts; it does NOT assert
   the live-derived committed file equals fixture output (impossible — different inputs). Live
   correctness is proven by the on-demand `comm -23` probe + the cron at runtime, not offline CI.
3. **Over-broad-CIDR reject:** `0.0.0.0/0` (and any prefix shorter than a sane floor) is
   *structurally valid* and passes BOTH the generator's and the loader's shape-validators — the one
   allow-all vector defense-in-depth misses. The generator rejects any prefix `< /8`.
4. **Atomic-write canonical form:** `mktemp` in the **target dir** (same filesystem — cross-device
   `mv` loses atomicity) + `mv -f` + `trap 'rm -f "$tmp"' EXIT` (precedent: `infra-config-install.sh:118,127`).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan adds NO new Terraform/server/secret/vendor.
     The only `systemctl restart cron-egress-firewall.service` references in the
     prose describe the EXISTING, already-Terraform-managed apply path
     (terraform_data.cron_egress_firewall, server.tf:842, shipped in #5285) that
     the regenerated CIDR file flows through unchanged. No manual provisioning is
     introduced. See ## Infrastructure (IaC). -->

# feat(infra): self-refreshing GitHub /meta CIDR generator for cron egress firewall

## Overview

`apps/web-platform/infra/cron-egress-allowlist-cidr.txt` is today a **hand-snapshotted**
list of GitHub's `/meta` `.git`+`.api` IPv4 union (52 ranges, snapshot 2026-06-14). GitHub
rotates the Azure `20.x`/`4.x` `/32` hosts that `api.github.com`/`github.com` load-balance
across, so the static list **will go stale**. When it does, a cron fire that lands on a
newly-rotated GitHub IP is default-dropped by the container egress firewall → no GitHub call
→ (for crons) no Sentry heartbeat → a missed check-in. This is the exact failure mode that
took down `scheduled-ruleset-bypass-audit` on 2026-06-14 (Sentry incident 5516336), fixed by
the static-snapshot PR #5281 — which only buys time until the next `/meta` rotation.

This plan makes the file **self-refreshing** so the firewall self-heals on rotation without an
operator edit, while **keeping every existing fail-loud guard** (the #5268 reject-whole-file
validator in the loader, and a drift-guard in `cron-egress-firewall.test.sh`).

> Spec lacks valid `lane:` (no spec.md) — defaulted to `cross-domain` (TR2 fail-closed).

### Design decision — three regen hooks, only one is correct

The issue lists three candidate hooks. Research (`repo-research-analyst` + `learnings-researcher`)
disqualified two:

| Hook | Verdict | Why |
|---|---|---|
| **Host `cron-egress-resolve.timer` regen** (every minute) | **Rejected** | Adds a live `api.github.com/meta` fetch to the firewall's own containment hot-path (every 60s). The resolve loop must come up even when GitHub is unreachable; a network dependency in the containment layer is wrong. It also cannot commit, so the committed file silently drifts from runtime — the opposite of self-healing. The resolve script today does zero git/HTTP-to-GitHub work (`cron-egress-resolve.sh`). |
| **Pre-plan regen in `apply-web-platform-infra.yml`** (uncommitted on-disk mutation) | **Rejected as primary mechanism** | terraform `file()` IS evaluated at plan time, so an on-disk regen *would* be seen (`server.tf:729`) — but it is never committed → permanent working-tree drift, `triggers_replace.config_hash` would replace on every apply, and the drift-guard `count==52` test is bypassed. Confirmed by research Q3. |
| **Inngest cron regenerator → `safeCommitAndPr` (direct-merge) → existing apply path re-applies** | **Chosen** (revised at deepen-pass) | Matches `cron-content-vendor-drift.ts` — the canonical "regenerate-from-external-source → PR to `main`" cron (`{ cron: … }`, Octokit fetch, `safeCommitAndPr` with `mergeMode: "direct"` + synthetic checks + Sentry heartbeat). `safeCommitAndPr` (ADR-054) handles the CLA gate + merge-to-`main` that a raw `gh pr merge --auto` cannot. The committed file stays the source of truth; the existing `terraform_data.cron_egress_firewall` already re-applies on merge (config_hash keys on `file(...)`); the firewall self-heals with **zero new apply-path logic**. *(Earlier draft used a raw GHA `scheduled-*.yml` + `gh pr create/merge --auto` — rejected at deepen-pass: stuck-PR-on-main, see Enhancement Summary.)* |

The heart of the issue is therefore three artifacts:

1. **A committed generator** `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh` —
   idempotent: fetch `/meta`, extract `(.git+.api)[]|select(test(":")|not)`, `sort -u`,
   validate every line with the **same** `is_valid_ipv4_cidr` regex the loader uses (#5268),
   atomic-write the file with a `DO NOT EDIT — generated` header + snapshot date.
2. **A drift-guard rewrite** in `cron-egress-firewall.test.sh` — replace the brittle magic
   `count==52` with: (a) run the generator against a **committed fixture** `/meta` JSON and
   assert byte-equality of the *body* (count drifts on every rotation; the generator's
   determinism does not), and (b) keep the existing per-line validator unit tests.
3. **An Inngest refresh cron** `apps/web-platform/server/inngest/functions/cron-github-cidr-refresh.ts`
   (modeled on `cron-content-vendor-drift.ts`) — fetches `/meta` via Octokit inside `step.run`
   (replay-memoized, ADR-033 I1), runs the **same** generator extraction/validation logic, and if
   the committed CIDR body drifts, persists via `safeCommitAndPr({ mergeMode: "direct", … })` so
   merge → `apply-web-platform-infra.yml` re-applies → firewall self-heals. The cron schedule is
   Inngest-native (ADR-033); the five-registry lockstep applies (see Phase 3 / Non-Goals).

The #5268 loader validator and the loader's fail-open-on-bootstrap behavior are **untouched** —
the generator is an upstream producer; the loader remains the last-line fail-loud consumer.

## Research Reconciliation — Spec vs. Codebase

| Issue / claim | Reality (verified) | Plan response |
|---|---|---|
| "Wire into `cron-egress-resolve.timer` … (already runs every minute)" | `cron-egress-resolve.sh` resolves DNS hostnames + reconciles nft sets; it makes **no** call to `api.github.com/meta` and has no git/PR capability. Adding a live `/meta` fetch to the 60s containment loop is an availability regression. | Reject the resolve-timer hook; use a scheduled GHA regenerator + bot PR. |
| "a pre-apply step in `apply-web-platform-infra.yml`" | terraform `file()` reads disk at plan time (`server.tf:728-729`), so an on-disk regen is picked up **but never committed** → state/repo divergence + `config_hash` churn + drift-guard bypass (research Q3 a/b/c). | Reject as the self-refresh mechanism. The *only* apply-path change is the drift-guard test (already runs in `infra-validation.yml`). |
| "Keep the #5268 reject-whole-file validator + drift-guard count check" | The validator (`is_valid_ipv4_cidr`, `cron-egress-nftables.sh:70-93`) and the `count==52` guard (`cron-egress-firewall.test.sh:166-172`) both exist. | Keep the validator verbatim (and reuse its regex in the generator). **Replace** the magic `count==52` with a generator-output-equality guard — a fixed count is itself a staleness trap (a rotation that swaps one /32 for another keeps count==52 while the ranges are wrong). |
| "CI could run [the `comm -23` gap check] as an early-warning" | No CI job today makes a live drift call for this file. `scheduled-terraform-drift.yml` is the precedent (Inngest-dispatched, ephemeral GHA, creates issues on drift). | The scheduled refresh workflow IS that early-warning, but goes one better: instead of only filing an issue, it opens an auto-merge PR (deterministic file, no human review value — `2026-03-02-github-actions-auto-push-vs-pr-for-bot-content`). |
| "Scheduled jobs: Inngest > GH Actions per ADR-033" | This regenerator needs NO terraform/cloud creds (only an unauthenticated `/meta` fetch + repo write via the App installation token), so the credential-heavy ephemeral-runner carve-out does NOT apply — it fits the app-runtime Inngest + `safeCommitAndPr` lane (`cron-content-vendor-drift.ts`), which runs entirely in the app container via Octokit. | Implement as an **Inngest cron** (`{ cron: … }`), not a GHA workflow. `safeCommitAndPr({ mergeMode: "direct" })` does the merge-to-`main` (handles CLA synthetic checks) — the schedule fires unattended from merge (no deferred dispatcher). |

## User-Brand Impact

**If this lands broken, the user experiences:** a self-refresh job that silently produces a
malformed or empty `cron-egress-allowlist-cidr.txt` (truncated `/meta` response, jq shape
change) and commits it. The loader's #5268 validator then `die`s → firewall fail-open on
bootstrap (no default-drop) **or**, if the empty file passes (empty set = no-op), GitHub crons
get dropped → missed Sentry check-ins across every GitHub-dialing cron. The blast radius is
the cron fleet, not a single end user.

**If this leaks, the user's data/workflow is exposed via:** the generator ingests an **untrusted
external** `/meta` response and writes it into an nftables ruleset. An attacker who could spoof
`/meta` (or a GitHub-side bug) could try to smuggle `0.0.0.0/0` (allow-all egress) or an
nft-injection line into the firewall. Mitigated by: HTTPS pin to `api.github.com`, the
generator's own per-line `is_valid_ipv4_cidr` validation, AND the loader's independent #5268
validator at load time (defense in depth — a bad line is rejected at both producer and consumer).

**Brand-survival threshold:** aggregate pattern. (A single stale/malformed refresh degrades the
cron fleet's GitHub reachability — an aggregate operational regression, not a per-user data
incident. The egress firewall is a containment control, not a user-data surface; the threshold
is below `single-user incident`. Reason recorded for preflight Check 6.)

## Files to Create

- `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh` — the idempotent generator
  (~70 lines; reuses the `is_valid_ipv4_cidr` regex from `cron-egress-nftables.sh:72`).
- `apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh` — generator unit tests
  (drives the generator against a committed fixture; asserts header + body shape + fail-loud
  on malformed input). Registered in `.github/workflows/infra-validation.yml` next to the
  existing `cron-egress-firewall.test.sh` step.
- `apps/web-platform/infra/test-fixtures/github-meta-sample.json` — a **synthesized**
  (`cq-test-fixtures-synthesized-only`) minimal `/meta` JSON (a handful of `.git`/`.api`
  IPv4 + IPv6 entries, including a `0.0.0.0/0` over-broad entry for the reject test) so the
  generator test is deterministic and offline. The `test-fixtures/` dir exists (confirmed).
- `apps/web-platform/server/inngest/functions/cron-github-cidr-refresh.ts` — the Inngest refresh
  cron (modeled on `cron-content-vendor-drift.ts`): Octokit `/meta` fetch in `step.run`, drift
  detect, `safeCommitAndPr({ mergeMode: "direct", allowedPaths: ["apps/web-platform/infra/cron-egress-allowlist-cidr.txt"] })`,
  Sentry heartbeat (own monitor slug). The extraction/validation logic is shared with the shell
  generator (the cron may shell out to `gen-github-egress-cidr.sh` via the workspace, OR
  re-implement the identical jq+validator — Phase 3 picks one and tests parity).
- `apps/web-platform/server/inngest/functions/cron-github-cidr-refresh.test.ts` — handler unit
  test (drift-detect, direct-merge path, heartbeat).

## Files to Edit

- `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` — regenerate via the new script so
  its header reflects the generator (`# DO NOT EDIT — regenerate via
  apps/web-platform/infra/scripts/gen-github-egress-cidr.sh`) and the body is byte-identical
  to the generator's output. (Content unchanged from #5281 if `/meta` has not rotated since;
  the diff is the header.)
- `apps/web-platform/infra/cron-egress-firewall.test.sh` — replace the magic `count==52`
  block (lines ~161-172) with a **generator-equality** drift-guard: run
  `gen-github-egress-cidr.sh --check` (or generate to a tmp file from the fixture) and assert
  the committed file's CIDR body matches the generator's deterministic output; keep the
  existing GitHub-octet presence asserts (140.82, Azure 20.x/4.x) and the per-line
  `is_valid_ipv4_cidr` unit tests (lines 213-255) untouched. **Do NOT** keep a hardcoded count.
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` — update the
  "GitHub LB pool / CIDR coverage gap" remediation (lines 74-95): the manual `curl … | jq …`
  recipe becomes "run `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh`" (single
  command); note the scheduled refresh job auto-heals on rotation; keep the `comm -23`
  discoverability check as the on-demand gap probe.
- `knowledge-base/engineering/operations/post-mortems/ruleset-bypass-audit-cron-egress-cidr-gap-postmortem.md`
  — close the open action item ("self-refreshing generator (#5284)") with the PR link.
- **Inngest five-registry lockstep** (`2026-06-05-new-inngest-cron-requires-five-registry-lockstep`)
  — the new cron requires byte-identical slug across: the handler file (above), `route.ts`
  registration, `apps/web-platform/server/inngest/cron-manifest.ts`, the manifest-count test
  (`apps/web-platform/test/server/internal/trigger-cron-route.test.ts`), and the Sentry monitor
  (`apps/web-platform/infra/sentry/*` + `apply-sentry-infra.yml`). Enumerate each at Phase 3 and
  verify the slug matches (`grep` all five). Self-failure routing per
  `2026-06-12-detector-cron-must-route-its-own-self-failure-ops-and-register-new-sentry-alert-in-apply-target`.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

- [ ] Confirm `apps/web-platform/infra/test-fixtures/` exists and is the right home for the
      synthesized `/meta` fixture (it is — `ls` confirmed).
- [ ] Confirm `ubuntu-24.04` GHA runners ship `jq` + `curl` (they do — both preinstalled).
- [ ] Live-probe the jq shape against real `/meta`:
      `curl -fsS --max-time 30 https://api.github.com/meta | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u | wc -l`
      — confirm it returns the IPv4 union (the `select(test(":")|not)` drops IPv6). This is the
      **exact** shape already in the file header (line 28) and the runbook (line 81) — adopt
      verbatim, do not invent a new jq filter.
- [ ] Confirm the loader's regex anchor so the generator's validator is byte-identical:
      `[[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]]`
      plus octet/prefix `<= 255 / <= 32` range check (`cron-egress-nftables.sh:72-78`).

### Phase 1 — The generator script (TDD: test first)

Write `gen-github-egress-cidr.test.sh` (RED) then `gen-github-egress-cidr.sh` (GREEN).

`gen-github-egress-cidr.sh` contract:
```bash
#!/usr/bin/env bash
# gen-github-egress-cidr.sh — regenerate cron-egress-allowlist-cidr.txt from
# GitHub /meta (#5284). Idempotent + fail-loud. DO NOT hand-edit the output file.
#
# Usage:
#   gen-github-egress-cidr.sh            # fetch live /meta, write the file
#   gen-github-egress-cidr.sh --check    # exit 0 if committed file == fresh gen, 1 if drift
#   META_JSON_FILE=fixture.json gen-...  # read /meta from a file (test/offline)
set -euo pipefail
OUT="${OUT:-$(dirname "$0")/../cron-egress-allowlist-cidr.txt}"
META_URL="https://api.github.com/meta"
# 1. FETCH (fail-loud): curl -fsS --max-time 30 (or read META_JSON_FILE for tests).
#    -f → non-2xx is a hard error (no partial body); --max-time bounds the hang.
# 2. EXTRACT: jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u   (verbatim, Phase 0).
# 3. VALIDATE every line with is_valid_ipv4_cidr (regex copied from the loader);
#    a single bad line → exit 1 (reject-whole-file; never write a partial).
#    ALSO reject any prefix < /8 (and 0.0.0.0/0): both shape-validators pass an
#    over-broad-but-valid CIDR, so the breadth check is the generator's job (the
#    one allow-all vector defense-in-depth misses). Floor: prefix >= 8.
# 4. GUARD non-empty: zero lines → exit 1 (a truncated /meta must not blank the file).
# 5. DATE-HEADER CHURN GUARD: decide no-op on the CIDR BODY ONLY. If the freshly
#    generated body == the committed file's body, exit 0 WITHOUT rewriting (so the
#    Snapshot: date does not advance and `git diff` stays quiet → no daily spurious
#    PR / config_hash churn). Only when the body changed do we restamp date + write.
# 6. WRITE atomically: mktemp IN THE TARGET DIR (same fs — cross-device mv loses
#    atomicity), trap 'rm -f "$tmp"' EXIT (fail-loud leaves file untouched), mv -f.
#    Precedent: infra-config-install.sh:118,127. Header: generated marker, source URL,
#    snapshot date (date -u +%F), range count, COVERAGE prose carried from current file.
```

Test scenarios (`gen-github-egress-cidr.test.sh`):
- `META_JSON_FILE=fixture` → output body == expected fixture-derived CIDR list (golden).
- Output header contains `DO NOT EDIT`, the source URL, and a `Snapshot:` line with today's date.
- IPv6 entries in the fixture are dropped (`select(test(":")|not)`).
- Duplicate entries in the fixture collapse (`sort -u`).
- Malformed `/meta` (`{}`, non-JSON, an entry `0.0.0.0/0}; add rule …`) → exit 1, file untouched.
- **Over-broad CIDR** (fixture entry `0.0.0.0/0` or `10.0.0.0/4`) → exit 1 (prefix-floor reject).
- Empty extraction (fixture with only IPv6) → exit 1 (non-empty guard).
- **Date-header no-op:** running against a fixture whose body == committed body leaves the file
  byte-unchanged (the `Snapshot:` date does NOT advance) → `git diff` quiet.
- `--check` exits 0 when committed body matches, 1 when it drifts (diff a mutated body copy).
- Re-running twice with the same fixture yields byte-identical output (idempotent → stable
  `triggers_replace` hash).
- Atomic-write: a forced-failure mid-write (e.g. bad line after partial) leaves NO stray tmp file
  (the EXIT trap fires) and the original file untouched.

### Phase 2 — Regenerate the committed file + rewrite the drift-guard

- [ ] Run `gen-github-egress-cidr.sh` against live `/meta`; commit the regenerated
      `cron-egress-allowlist-cidr.txt` (new generated header; body unchanged from #5281 unless
      `/meta` rotated). Run the `comm -23` gap check to prove zero coverage gap.
- [ ] In `cron-egress-firewall.test.sh`: delete the magic `count==52` block and replace it with
      **structural, offline** asserts that do NOT depend on live `/meta` (avoids the circularity:
      the committed file is live-derived, the fixture is synthetic — they can't be asserted equal):
      - keep `140.82.112.0/20` presence + the `^20[.]…/32` + `^4[.]…/32` Azure presence asserts;
      - keep the `is_valid_ipv4_cidr` unit-test block (213-255) unchanged;
      - add a **floor count** assert (`count >= 40`, not `== 52`) so a partial-revert/truncation
        to the 4 big blocks (the incident-5516336 regression) is still caught — a floor is NOT a
        staleness trap (rotation swaps keep count ~constant; only truncation trips it);
      - add an **over-broad reject** assert: no committed line has prefix `< /8`.
      Generator **determinism** (fixture-in → golden-out) is asserted in `gen-…test.sh`, NOT here.
      Live correctness is proven by the on-demand `comm -23` probe + the cron at runtime.
- [ ] Register `gen-github-egress-cidr.test.sh` as a step in `infra-validation.yml` adjacent
      to the existing `cron-egress-firewall.test.sh` step (line ~166).

### Phase 3 — The Inngest refresh cron (template: `cron-content-vendor-drift.ts`)

`apps/web-platform/server/inngest/functions/cron-github-cidr-refresh.ts` — copy the structure of
`cron-content-vendor-drift.ts` (the canonical regenerate-from-external-source → PR-to-`main` cron):

1. `inngest.createFunction({ id, … }, { cron: "<expr>" }, async ({ step }) => …)` — pick a daily
   schedule (e.g. `"23 7 * * *"`); Inngest-native, no GHA `schedule:`.
2. `step.run("mint-installation-token", …)` — App installation token (ADR-033 I1, hr-github-app-auth-not-pat).
3. `step.run("detect-drift", …)` — Octokit `GET /meta` (or `request("GET /meta")`), run the
   **shared** extraction (`(.git+.api)[]|select(test(":")|not)|sort -u`) + per-line validator +
   `0.0.0.0/0`/over-broad reject + non-empty guard, and compare the resulting **CIDR body** (NOT
   the date header) to the committed file's body. Return a deterministic shape (I5).
4. **No drift** → `step.run("sentry-heartbeat", ok)` and return (no PR).
5. **Drift** → `step.run("safe-commit-pr", () => safeCommitAndPr({ … mergeMode: "direct",
   allowedPaths: ["apps/web-platform/infra/cron-egress-allowlist-cidr.txt"],
   scheduledIssueLabel: SENTRY_MONITOR_SLUG, … }))`. `safeCommitAndPr` (ADR-054) handles the
   scoped commit, CLA synthetic checks, direct-merge to `main`, and deletion guard — this is the
   piece a raw `gh pr merge --auto` cannot do on `main`.
   - Merge → `apply-web-platform-infra.yml` fires (CIDR file is in its `paths: apps/web-platform/infra/**`
     filter — **verified**: workflow lines 67-72) → `terraform_data.cron_egress_firewall`
     config_hash changes → file-provisioned + the existing Terraform-managed service-restart step
     (#5285, server.tf:842, unchanged) → firewall self-heals. **No new apply logic, no new infra.**
6. `step.run("sentry-heartbeat", …)` on every path (slug = `SENTRY_MONITOR_SLUG`, e.g.
   `cron-github-cidr-refresh`) so a dead cron surfaces as a missed check-in (no-SSH channel).

**Five-registry lockstep** (`2026-06-05-…-five-registry-lockstep`) — verify the slug is
byte-identical across handler, `route.ts`, `cron-manifest.ts`, the manifest-count test
(`test/server/internal/trigger-cron-route.test.ts`), and the Sentry monitor
(`infra/sentry/*` + `apply-sentry-infra.yml`). Register the cron's own self-failure ops route
(`2026-06-12-detector-cron-must-route-its-own-self-failure-ops`).

**Extraction parity (pick one, test it):** either (a) the cron shells out to
`gen-github-egress-cidr.sh` reading `/meta` from the Octokit response (one source of truth, but
needs the script on the container path), or (b) the cron re-implements the identical jq filter +
validator in TS — in which case add a parity test asserting the TS path and the shell path produce
byte-identical output for the synthesized fixture. Prefer (a) if the script is reachable.

### Phase 4 — Docs + post-mortem closure

- [ ] Runbook: replace the manual `curl|jq` regen recipe with the generator command; note
      auto-heal via the scheduled job; keep `comm -23` as the on-demand probe.
- [ ] Post-mortem: close the "#5284 self-refreshing generator" action item.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — generator determinism:** `gen-github-egress-cidr.sh` run twice against the
      committed fixture produces byte-identical output (proves stable `triggers_replace` hash).
- [ ] **AC2 — jq shape verbatim:** the generator's extraction is exactly
      `jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u` (matches file header line 28 +
      runbook line 81). `git grep -c 'select(test(":")|not)'` across the generator + runbook +
      file ≥ 3 occurrences and all identical.
- [ ] **AC3 — fail-loud on bad input:** generator exits non-zero and leaves the output file
      unmodified for: non-2xx fetch, non-JSON body, empty extraction, a line containing an
      nft-injection payload (`0.0.0.0/0}; add rule …`), AND an over-broad-but-valid CIDR
      (`0.0.0.0/0`, prefix `< /8`). Asserted in `gen-github-egress-cidr.test.sh`.
- [ ] **AC4 — validator parity:** the generator's `is_valid_ipv4_cidr` regex + octet/prefix
      bounds are byte-identical to `cron-egress-nftables.sh:72-78`
      (`diff <(sed -n '70,80p' cron-egress-nftables.sh) <(grep -A8 is_valid_ipv4_cidr gen-…sh)`
      shows the function body matches, modulo surrounding context).
- [ ] **AC5 — committed file regenerated:** `cron-egress-allowlist-cidr.txt` header contains
      `DO NOT EDIT` + `gen-github-egress-cidr.sh` + a `Snapshot:` line; its CIDR body equals
      the generator's deterministic output against live `/meta`
      (`gen-github-egress-cidr.sh --check` exits 0).
- [ ] **AC6 — zero coverage gap:** the runbook `comm -23 <(live /meta) <(committed file)`
      returns empty (full coverage at merge time).
- [ ] **AC7 — drift-guard de-magicked (no circularity):** `grep -c 'eq 52' cron-egress-firewall.test.sh`
      == 0 (the hardcoded count is gone) AND a floor `count >= 40` assert + an over-broad-reject
      assert are present. The CI drift-guard does NOT call live `/meta` and does NOT assert the
      committed file equals fixture output. The #5268 per-line validator unit tests (213-255) are
      unchanged (`git diff` touches only the count block).
- [ ] **AC7b — no-op determinism (date-header):** running the generator against a fixture whose
      body matches the committed body leaves the file byte-unchanged (the `Snapshot:` date does not
      advance); `git diff --quiet` after the run. Prevents the daily-spurious-PR / config_hash churn.
- [ ] **AC8 — loader untouched:** `git diff apps/web-platform/infra/cron-egress-nftables.sh`
      is empty (the #5268 reject-whole-file validator and fail-open-bootstrap behavior are
      preserved verbatim).
- [ ] **AC9 — cron five-registry lockstep:** the cron slug is byte-identical across the handler,
      `route.ts`, `cron-manifest.ts`, the manifest-count test, and the Sentry monitor
      (`infra/sentry/*` + `apply-sentry-infra.yml`) — verified by grepping all five for the slug.
      `safeCommitAndPr` is used with `mergeMode: "direct"` and `allowedPaths` scoped to the single
      CIDR file (no `git add -A` equivalent). The cron typechecks
      (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`).
- [ ] **AC10 — infra-validation registers the new test:** `infra-validation.yml` has a step
      running `gen-github-egress-cidr.test.sh`; `bash gen-github-egress-cidr.test.sh` is green.
      Generator passes `bash -n` (asserted inside its test, per repo convention).
- [ ] **AC11 — fetch timeout pinned:** every `/meta` fetch (shell `curl -fsS --max-time 30` and the
      cron's Octokit request) is bounded — no unbounded network call (`2026-04-28` timeout learning).
- [ ] **AC12 — extraction parity:** the shell generator and the cron's extraction path produce
      byte-identical CIDR bodies for the synthesized fixture (parity test), OR the cron shells out
      to the one script (single source of truth).

### Post-merge (operator / automation)

- [ ] **AC13 — apply path re-fires:** confirm merge of a CIDR-file change triggers
      `apply-web-platform-infra.yml` and `terraform_data.cron_egress_firewall` registers a
      replace (config_hash changed) — verified via the existing apply post-checks
      (`cidr-set-github` / `cidr-set-api-pool` asserts, `server.tf:856,868`). Automatable via
      the existing workflow run; no SSH.
- [ ] **AC14 — refresh cron dry-fires green:** trigger the cron via the existing
      `POST /api/internal/trigger-cron` route (`/soleur:trigger-cron`) against the just-merged
      (already-fresh) file → "no drift", no PR, OK Sentry check-in. No SSH; no `gh workflow run`.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned zero open scope-outs touching
`cron-egress-allowlist-cidr.txt`, `cron-egress-firewall.test.sh`, `cron-egress-nftables.sh`,
`apply-web-platform-infra.yml`, or `cron-egress-blocked.md` (verified at plan time).

## Non-Goals / Deferred

- **Host-side resolve-timer regen.** Rejected by design (above).
- **Raw GHA `scheduled-*.yml` + `gh pr merge --auto`.** Rejected at deepen-pass (stuck-PR-on-main
  via CLA/auto-merge gate; invisible non-merge). The Inngest cron + `safeCommitAndPr` is the
  canonical replacement — and it fires the refresh unattended from day one (no deferred dispatcher;
  the cron schedule IS the trigger), so the "self-refreshing" promise is met on merge.
- **Migrating the Sentry `/store/` event API.** Out of scope; the generator/workflow only adds
  a Crons check-in, not event posting.

## Infrastructure (IaC)

### Terraform changes
**One** new Terraform resource: a Sentry Crons monitor for the new cron (slug
`cron-github-cidr-refresh`) under `apps/web-platform/infra/sentry/`, applied via the existing
`apply-sentry-infra.yml` — the standard per-cron lockstep, identical to every other Inngest cron's
monitor (e.g. `scheduled-content-vendor-drift`). No new provider/variable. **No new server,
secret, vendor account, DNS record, or firewall rule.** The egress-firewall apply path itself is
**unchanged**: the regenerated `cron-egress-allowlist-cidr.txt` flows through the existing
`terraform_data.cron_egress_firewall` (`server.tf:719-886`) whose `triggers_replace.config_hash`
already keys on `file("…/cron-egress-allowlist-cidr.txt")` (line 729), is already file-provisioned
(line 777-780), and runs the existing service-restart step (line 842, #5285). The cron handler
itself is **app-runtime code** (Inngest function under `apps/web-platform/server/`), not infra.

### Apply path
(b) cloud-init + existing idempotent restart — unchanged. The self-refresh is a *content* change
to an already-provisioned artifact; the apply path that picks it up already exists and was
hardened in #5281/#5285. Expected blast-radius on refresh-merge: one `terraform apply` of the
firewall resource (file re-provision + the existing `systemctl restart` of
`cron-egress-firewall.service`), which populates the CIDR set BEFORE the default-drop
(availability ordering, asserted in `cron-egress-firewall.test.sh`) → no egress gap. This
restart is the *existing* Terraform-managed step (server.tf:842), not a new manual action.

### Distinctness / drift safeguards
The generator is deterministic and idempotent, and decides no-op on the CIDR **body only** (not the
date header) → a no-op refresh produces no diff → no spurious PR / no `config_hash` churn. The
offline CI drift-guard (structural floor + over-broad reject + validator parity) catches a
hand-edited or truncated file. The Inngest cron is the runtime safeguard against `/meta` rotation;
the `comm -23` probe is the on-demand coverage check.

### Vendor-tier reality check
`api.github.com/meta` is an unauthenticated, free, public endpoint (no token, no tier gate).
No `count = var.x_paid_tier ? 1 : 0` needed.

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in for the refresh cron
  cadence: per cron fire (daily, Inngest-native schedule — fires unattended from merge)
  alert_target: Sentry Crons monitor slug `cron-github-cidr-refresh` (missed check-in alert)
  configured_in: apps/web-platform/server/inngest/functions/cron-github-cidr-refresh.ts (heartbeat step) + infra/sentry/* + apply-sentry-infra.yml (monitor), modeled on cron-content-vendor-drift.ts
error_reporting:
  destination: GitHub Actions run log (workflow failure) + Sentry Crons error check-in on non-zero generator exit
  fail_loud: true — generator exits non-zero on bad /meta; workflow step fails; missed/error check-in surfaces
failure_modes:
  - mode: /meta unreachable or non-2xx during scheduled refresh
    detection: curl -f non-zero -> generator exit 1 -> workflow step red + Sentry error check-in
    alert_route: Sentry Crons monitor (error/missed) + red workflow run
  - mode: /meta returns malformed/truncated JSON (would blank or corrupt the file)
    detection: jq/empty-guard/validator in the generator -> exit 1 (file untouched)
    alert_route: same as above
  - mode: committed file drifts from /meta (rotation) but refresh job is dead
    detection: missed Sentry Crons check-in for cron-github-cidr-refresh; backstop = the next egress-blocked event still pages via cron-egress-resolve.sh:281 (existing)
    alert_route: Sentry (cron-egress-firewall feature) — existing egress-blocked event path is the backstop
  - mode: generated file hand-edited (drift from generator)
    detection: cron-egress-firewall.test.sh generator-equality drift-guard fails in infra-validation.yml
    alert_route: red CI on the PR
logs:
  where: GitHub Actions run logs (refresh workflow); host journald for the firewall apply (existing)
  retention: GitHub Actions default 90d; journald per journald-soleur.conf (existing)
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 30 https://api.github.com/meta
  expected_output: 200
  full_coverage_probe: "curl -fsS --max-time 30 https://api.github.com/meta | jq -r '(.git+.api)[]|select(test(\":\")|not)' | sort -u | comm -23 - <(grep -vE '^[[:space:]]*(#|$)' apps/web-platform/infra/cron-egress-allowlist-cidr.txt | sort -u)  # empty == zero coverage gap (manual; multi-stage pipe). Cron liveness via the Sentry monitor `cron-github-cidr-refresh` + `/api/internal/trigger-cron` dry-fire — no SSH."
```

## Hypotheses

(Network-outage checklist — fired by `firewall` + `unreachable` + `timeout` keywords.) This
plan does not diagnose an SSH/network outage; it *prevents* a recurrence of the GitHub-egress
drop class. The L3→L7 order is honored structurally: the firewall allowlist (L3/L4 egress
CIDR) is the layer being self-healed, BEFORE any service-layer hypothesis. The prior incident
(5516336) was already root-caused to the CIDR allowlist gap (post-mortem); this plan closes
that root cause durably rather than re-diagnosing it.

## Domain Review

**Domains relevant:** Engineering (infra/CI).

No `## Files to Create`/`Files to Edit` path matches any UI-surface term/glob → Product/UX Gate
not triggered (NONE). No Legal, Finance, Sales, Marketing, Support, or Operations-vendor
implications (pure infra-tooling change against an already-provisioned firewall; no user-facing
surface, no new vendor, no regulated-data surface).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold = aggregate
  pattern with recorded reason.)
- **Do not let the scheduled workflow open a PR on a no-op refresh.** The generator is
  deterministic; gate the PR step behind `git diff --quiet` so an unchanged `/meta` produces
  no branch/PR churn (every false PR is operator noise + a needless `config_hash` apply).
- **The drift-guard must NOT re-introduce a hardcoded count.** Count==N is itself a staleness
  trap — a rotation that swaps one /32 for another keeps the count constant while the ranges
  drift. Assert generator-output-equality, not a magic number.
- **Reuse the loader's `is_valid_ipv4_cidr` regex byte-for-byte.** If the generator's validator
  diverges from the loader's (#5268), the generator could pass a line the loader later `die`s
  on (or vice-versa) → fail-open bootstrap on the next apply. Copy the function; do not
  reimplement.
- **Pin `curl --max-time`.** An unbounded `/meta` fetch in CI can hang the runner (2026-04-28
  network-timeout learning). `-fsS --max-time 30`.
- **Use `Closes #5284` deliberately.** This PR *implements* #5284, so `Closes #5284` is correct
  in the PR body (not title). The deferred Inngest-dispatcher tracking issue gets `Ref`, not
  `Closes`.
- **Commit must be path-scoped.** `safeCommitAndPr`'s `allowedPaths` is set to the single CIDR
  file — never a broad stage (`hr-never-git-add-a-in-user-repo-agents`; `safeCommitAndPr` enforces
  this structurally via its deletion guard + allowedPaths, which is the whole reason to use it).
- **Date-header churn (deepen-pass).** If the generator stamps a fresh `Snapshot:` date on every
  run, `git diff` is never quiet → the cron opens a spurious PR + churns `config_hash` daily.
  Decide no-op on the CIDR **body only**; restamp the date only when the body changes (AC7b).
- **Drift-guard circularity (deepen-pass).** The committed file is live-`/meta`-derived; the test
  fixture is synthetic. NEVER assert the committed file equals fixture output (fails every real PR)
  and NEVER make the offline CI guard call live `/meta` (flaky). Determinism is asserted against
  the fixture in `gen-…test.sh`; live correctness via the `comm -23` probe + the cron at runtime.
- **`0.0.0.0/0` / over-broad CIDR (deepen-pass).** Both the generator's and the loader's validators
  are *shape* validators — they accept a structurally-valid `0.0.0.0/0` (the loader test explicitly
  accepts it, `cron-egress-firewall.test.sh:244`). The generator must add a *breadth* reject
  (prefix `< /8`) — the one allow-all vector defense-in-depth otherwise misses.
- **Atomic-write filesystem (deepen-pass).** `mktemp` in the **target dir** (cross-device `mv`
  silently loses atomicity) + `trap 'rm -f "$tmp"' EXIT`. Precedent: `infra-config-install.sh:118,127`.
