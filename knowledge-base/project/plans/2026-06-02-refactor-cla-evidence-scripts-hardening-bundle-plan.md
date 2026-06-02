---
title: cla-evidence scripts hardening bundle (Ref #3939)
type: refactor
issue: "#3950"
ref_only: true            # use "Ref #3950", NOT "Closes" — do-not-autoclose
branch: feat-one-shot-3950-cla-evidence-hardening
lane: cross-domain        # no spec.md present → TR2 fail-closed default
priority: p3
brand_survival_threshold: single-user incident
requires_cpo_signoff: false   # threshold "single-user incident" for one item; see User-Brand Impact
date: 2026-06-02
---

# Refactor: cla-evidence scripts hardening bundle (Ref #3939)

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).
>
> **IaC note:** this plan introduces NO new infrastructure provisioning. It edits existing bash scripts. The Doppler-secrets-push line in `infra/bootstrap.sh` is *pre-existing* and untouched — cited only as a placement anchor. See `## Infrastructure (IaC)`.

## Enhancement Summary

**Deepened on:** 2026-06-02
**Gates cleared:** 4.4 precedent-diff (helper extraction — precedents are the existing inline forms, diffed below), 4.45 verify-the-negative + post-edit self-audit, 4.6 User-Brand Impact halt (PASS — `single-user incident`), 4.7 Observability halt (PASS — 5 fields, no SSH), 4.8 PAT-shaped-variable halt (PASS — none). Network-outage gate not triggered (no SSH/timeout/handshake keywords). Scheduled-work gate not triggered (no new cron/job).

### Key verifications (live, this pass)

1. **Negative claim "bearer not reachable to the aws process" holds.** The 2 `doppler run -- aws` sites (`gdpr-override.sh:307-311`, `:412-418`) carry NO `CF_ADMIN_TOKEN` argument — the only `Bearer $CF_ADMIN_TOKEN` near line 307 is the curl PUT-restore header at `:317` inside the DELETE-failure recovery branch, a *different* command. So `env -u CF_ADMIN_TOKEN` (item 2) strips a bearer the aws child never consumes — the scrub is pure attack-surface reduction, no functional change. Confirmed.
2. **Tombstone schema_version is `"1.0"`** (`gdpr-override.sh:403 --arg sv "1.0"`), so `inspect-evidence.sh`'s existing `assert_schema_version` (which accepts `1.0`) accepts tombstones unchanged — Phase 4's reuse of `assert_schema_version` / `fetch_and_print` is sound.
3. **`assert_r2_endpoint` placement anchor confirmed:** `gdpr-override.sh` env-validation block is at `:106-115` (requires `R2_CLA_EVIDENCE_ENDPOINT` at `:108`), which precedes the DRY_RUN guard at `:150` — validation lands before dry-run as designed.
4. **The bootstrap behavior upgrade is real:** `infra/bootstrap.sh:88` captures `CF_ADMIN_TOKEN_ID` with `// ""` and does NOT hard-fail on empty — adopting `cf_token_verify` (which hard-fails per `gdpr-override.sh:216-219`) changes this. This is the issue's stated "bootstrap gains the driver's id-capture-error path" — flagged as a Sharp Edge.
5. **by-pr hint anchor:** `inspect-evidence.sh:103` (`echo "no records for PR #${pr}"`) is the message to extend with the `tombstone <sha>` hint.

### Precedent diff (Phase 4.4 — helper extraction)

The helper extraction has TWO in-repo precedents that are themselves the duplication being removed:

| Behavior | `gdpr-override.sh` (driver) | `infra/bootstrap.sh` | Helper supersedes with |
| --- | --- | --- | --- |
| token verify | `:204-220` — verify → status==active → capture id → **hard-fail on empty id** (`:216-219`) | `:81-88` — verify → status==active → capture id with `// ""`, **no empty-id guard** | the driver's hard-fail form (more defensive) |
| self-revoke | `:186-198` — DELETE id, warn-not-fail, warn-on-empty-id | `:288-301` — DELETE id, warn-not-fail, warn-on-empty-id | identical shape; single source |

No novel pattern — both forms exist; the helper is the canonical merge of two siblings. Reviewers should scrutinize only the cross-directory `source` (Sharp Edge #1) and the bootstrap empty-id behavior change (Sharp Edge, item-3 upgrade).

## Overview

Four review-origin hardening items on `apps/cla-evidence/` bash scripts, surfaced by the 10-agent `/soleur:review` of PR #3939 and deferred to issue #3950 (label `deferred-scope-out`, `do-not-autoclose`). All four are local bash refactors against a well-understood codebase with strong existing patterns (the PR #3939 bearer-vs-HMAC sentinel in `infra/main.test.sh`, the `.test.sh` convention, the sidecar/consumer-boundary pattern). **No new dependency, no new infrastructure, no new data processing.**

The four items, in the issue's prescribed sequence (item 3 first; items 1 & 2 fold into the helper):

1. **(Item 3, FIRST)** Extract shared `cf_token_verify` / `cf_token_self_revoke` into a new sourced helper `apps/cla-evidence/scripts/_cf-admin-token.sh`, adopt in `gdpr-override.sh` + `infra/bootstrap.sh`.
2. **(Item 1)** Pin the R2 endpoint hostname via a regex check, extracted into a sourced helper, applied at every script that *consumes* `R2_CLA_EVIDENCE_ENDPOINT`.
3. **(Item 2)** Wrap every `doppler run -- aws` invocation as `env -u CF_ADMIN_TOKEN doppler run -- aws …` so the bearer is not visible via `/proc/<pid>/environ` to the child aws process.
4. **(Item 4)** Extend `inspect-evidence.sh` with tombstone visibility (`tombstone <sha>` subcommand + a `by-pr` 404 hint toward `tombstones/<sha>.deleted.json`), plus `inspect.test.sh` coverage.

Item 5 (policy-lint sentinel for bare `aws s3api`) already landed in PR #3939 — **out of scope, do not touch the `infra/main.test.sh` sentinel except to confirm it still passes.**

## Research Reconciliation — Spec vs. Codebase

The issue body (#3950) paraphrases file lists that **do not match the codebase**. Every claim below was verified by `git grep` / `Read` at plan time. The plan follows the verified column.

| Issue-body claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| "6 scripts consume `R2_CLA_EVIDENCE_ENDPOINT`: gdpr-override, upload-bypass, upload-evidence, inspect-evidence, sentinel-pr, bootstrap" | **Actual consumers (non-test):** `gdpr-override.sh` (4 refs, 2 live `aws` sites), `inspect-evidence.sh:28`, `r2-conditional-put.sh:54`, `infra/bootstrap.sh:226`. `upload-bypass.sh` (0 refs — `exec`s `r2-conditional-put.sh`), `upload-evidence.sh` (refs in comment only — also `exec`s `r2-conditional-put.sh`), `sentinel-pr.sh` (**0 refs — does not consume the var at all**). | Item-1 regex applied at the **4 real consumers**: `gdpr-override.sh`, `inspect-evidence.sh`, `r2-conditional-put.sh`, `infra/bootstrap.sh`. NOT in `upload-bypass.sh` / `upload-evidence.sh` (they delegate; validating in `r2-conditional-put.sh` covers both) and NOT in `sentinel-pr.sh` (no consumption). |
| Item 2 touches "gdpr-override.sh (2 sites), bootstrap.sh, upload-bypass.sh, upload-evidence.sh, sentinel-pr.sh" | `git grep 'doppler run.*aws'` → **only `gdpr-override.sh:307` (DELETE) and `:412` (tombstone PUT)**. `bootstrap.sh` uses Doppler config/secret writes + curl `--aws-sigv4` (no `doppler run -- aws`). upload-bypass/upload-evidence/sentinel-pr have no `doppler run -- aws`. | Item-2 `env -u CF_ADMIN_TOKEN` applied at the **2 real sites** in `gdpr-override.sh`. No other file has the pattern. |
| Item 3: helper at `apps/cla-evidence/scripts/_cf-admin-token.sh`, adopt in `bootstrap.sh + gdpr-override.sh` | `bootstrap.sh` is at **`apps/cla-evidence/infra/bootstrap.sh`**, NOT `scripts/`. Verify block `:81-88`, self-revoke `:288-301`. gdpr-override verify `:204-220`, `_self_revoke` `:186-198`. | Helper lives in `scripts/` per issue; `infra/bootstrap.sh` sources it via the relative path `../scripts/_cf-admin-token.sh` resolved from `${BASH_SOURCE[0]}` dir. Cross-directory sourcing is the one Sharp Edge for this item. |
| Item 4: inspect-evidence has "zero awareness of `tombstones/`" | Confirmed: `grep -n tombstone inspect-evidence.sh` → no hits. Tombstone key shape `tombstones/<PRIOR_SHA>.deleted.json` written at `gdpr-override.sh:399`; tombstone schema has `schema_version: "1.0"`. | Add `tombstone <sha>` mode + `by-pr` 404 hint. Reuse existing `assert_schema_version` (tombstone is `1.0` too). |
| (Not in issue) Test fixtures use non-canonical endpoints | **7 test sites** set `R2_CLA_EVIDENCE_ENDPOINT` to `https://stub.r2.example` or `https://example.invalid` — both **fail** the item-1 canonical regex. | **Load-bearing cross-effect** (see Sharp Edges + Phase 2). All 7 must switch to a canonical-shaped synthetic endpoint, OR the validation must be gated. Chosen: update fixtures to a canonical-shaped synthetic hostname (no test-only bypass backdoor that would defeat the security gate). |

## User-Brand Impact

**If this lands broken, the user experiences:** a GDPR Art. 17 erasure run (`gdpr-override.sh`) that silently no-ops — the offending CLA-signature object is NOT deleted, a fake-success tombstone is written, and the contributor who requested erasure still has their data in R2 under 10-year Object Lock. OR: `inspect-evidence.sh` returns a 404 for a signature an operator knows was erased, hiding the tombstone audit trail.

**If this leaks, the user's data/workflow is exposed via:** the `env -u CF_ADMIN_TOKEN` item exists precisely because the 53-char CF bearer admin token is currently visible in the child `aws` process's `/proc/<pid>/environ` for the lifetime of the DELETE/PUT calls — any process able to read `/proc` on the runner host can scrape it. The endpoint-pinning item closes a redirect-to-attacker-sink surface (mis-sourced `.envrc` → DELETE goes nowhere, tombstone PUT goes nowhere, real object remains).

**Brand-survival threshold:** `single-user incident` — a single botched erasure run (silent no-op leaving a requester's data live under WORM) is a GDPR Art. 17 compliance breach attributable to one user. Items 1 and 2 directly harden that path. The threshold drives the **deepen-plan precedent-diff gate** (Phase 4.4) on the helper-extraction + the deterministic-test discipline below; it does NOT require new CPO sign-off because the approach was already framed by PR #3939's review (the items are review findings, not a new approach), and `requires_cpo_signoff` stays false since no new user-facing surface or data processing is introduced — only existing-path hardening.

## Implementation Phases

> Phase order is load-bearing: the helper (Phase 1) must exist before consumers source it (Phases 2-3). RED-first per `cq-write-failing-tests-before` within each phase.

### Phase 0 — Preconditions (verify before any edit)

0.1. `grep -n 'cf_token_verify\|cf_token_self_revoke' apps/cla-evidence/` → confirm zero existing helper (new file).
0.2. Confirm cross-dir source path resolves: from `infra/bootstrap.sh`, `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/_cf-admin-token.sh` must exist. (bootstrap already computes `INFRA_DIR` at `:97` — reuse that anchor.)
0.3. `git grep -nE 'R2_CLA_EVIDENCE_ENDPOINT=' apps/cla-evidence/` → re-confirm the 7 test sites (Phase 2 fixture sweep target list) and the 4 live consumers.
0.4. Confirm prod endpoint shape `https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com` (32 lowercase-hex) satisfies the chosen regex (`infra/variables.tf:21`, `infra/main.tf:6`).
0.5. Run the existing suite GREEN as a baseline: `for t in apps/cla-evidence/scripts/*.test.sh; do bash "$t"; done && bash apps/cla-evidence/infra/main.test.sh`.

### Phase 1 — Item 3: shared CF-admin-token helper (FIRST)

**New file:** `apps/cla-evidence/scripts/_cf-admin-token.sh` (sourced, not executed; `# shellcheck shell=bash` header, no `set -euo pipefail` — sourced helpers inherit the caller's options).

Expose two functions matching the **superset** of both call sites' current behavior:

- `cf_token_verify <bearer>` → curls `https://api.cloudflare.com/client/v4/user/tokens/verify`, asserts `.result.status == "active"`, echoes the captured `.result.id` to stdout (callers assign `CF_ADMIN_TOKEN_ID=$(cf_token_verify "$TOKEN")`). MUST adopt gdpr-override's **more-defensive id-capture-error path** (`gdpr-override.sh:216-219` hard-fails on empty id) — the issue explicitly calls this out as the upgrade bootstrap gains. Return non-zero on verify-fail / non-active / empty-id so callers keep their existing `||` error branches.
- `cf_token_self_revoke <bearer> <token_id>` → curl DELETE `…/user/tokens/<id>`; warn (not fail) on error; warn-and-return-0 on empty id. Mirrors `gdpr-override.sh:186-198` + `bootstrap.sh:288-301`.

**Logging contract:** the helper must NOT hard-code `red`/`green`/`yellow` — both callers define those but with different stream/format conventions. Either (a) the helper assumes the caller has defined `red`/`green`/`yellow` (document as a sourcing precondition — both callers do, `gdpr-override.sh:30-34`, `bootstrap.sh:56-59`), or (b) the helper emits plain `printf` to stderr. **Choose (a)** — keeps each caller's existing color/stream semantics; add a sourcing-precondition comment. (Verify at deepen-plan that both callers' helper definitions precede the `source` line.)

**Adopt in `gdpr-override.sh`:** `source "$(dirname "${BASH_SOURCE[0]}")/_cf-admin-token.sh"` near the top (after log helpers, before Step 1). Replace inline Step-1 verify (`:204-220`) with `CF_ADMIN_TOKEN_ID=$(cf_token_verify "$CF_ADMIN_TOKEN") || exit 1`. Replace `_self_revoke()` body (`:186-198`) to call `cf_token_self_revoke "$CF_ADMIN_TOKEN" "$CF_ADMIN_TOKEN_ID"`. **Keep `_self_revoke` as a thin wrapper** — it is called in 4 places with no args (`:232, :290, :327`) and the trap-handler context; do not rewrite all call sites.

**Adopt in `infra/bootstrap.sh`:** `source "$INFRA_DIR/../scripts/_cf-admin-token.sh"` (after `INFRA_DIR` is computed at `:97`, OR compute the script-dir anchor earlier — verify ordering at deepen-plan; the verify block at `:81-88` runs BEFORE `:97`, so the `source` and the `INFRA_DIR` computation may need to move up). Replace verify block `:81-88` with `CF_ADMIN_TOKEN_ID=$(cf_token_verify "$CF_ADMIN_TOKEN_BOOTSTRAP")` (note: bootstrap currently does NOT hard-fail on empty id at `:88` — adopting the helper *changes* this to hard-fail; this is the documented behavior upgrade, but it means a previously-tolerated empty-id now aborts bootstrap. Flag as a Sharp Edge: confirm hard-failing bootstrap on empty token-id is desired — it is, per the issue's "more defensive" framing). Replace self-revoke block `:288-301` with `cf_token_self_revoke "$CF_ADMIN_TOKEN_BOOTSTRAP" "$CF_ADMIN_TOKEN_ID"`.

**Tests:** new `apps/cla-evidence/scripts/_cf-admin-token.test.sh` — PATH-stub `curl`, assert: (a) verify returns id on active+id present, (b) non-zero on status≠active, (c) non-zero on empty id (the upgrade), (d) self-revoke warns-not-fails on curl error, (e) self-revoke warns-and-returns-0 on empty id. Follow the `inspect.test.sh` / `gdpr-override.test.sh` PATH-shadow stub pattern (no bats — bats is NOT installed; the suite convention is `.test.sh` with PATH-shadowed mocks).

### Phase 2 — Item 1: R2 endpoint hostname pinning

**New file:** `apps/cla-evidence/scripts/_r2-endpoint.sh` exposing `assert_r2_endpoint <url>`:

```bash
assert_r2_endpoint() {
  [[ "$1" =~ ^https://[a-f0-9]{32}\.r2\.cloudflarestorage\.com/?$ ]] || {
    echo "::error::R2_CLA_EVIDENCE_ENDPOINT does not match canonical R2 hostname" >&2
    exit 64
  }
}
```

(Open question for deepen-plan/plan-review: one combined `_cla-evidence-lib.sh` vs. two single-purpose helpers `_cf-admin-token.sh` + `_r2-endpoint.sh`. Default: **two single-purpose helpers** — `_cf-admin-token.sh` is sourced by 2 files, `_r2-endpoint.sh` by 4; different consumer sets, keep them orthogonal. DHH/simplicity reviewers may prefer one lib — defer the call to plan-review.)

**Apply at the 4 real consumers** (Research Reconciliation row 1):
- `gdpr-override.sh` — source + `assert_r2_endpoint "$R2_CLA_EVIDENCE_ENDPOINT"`. **Placement: at the env-validation block (`:108` requires the var), BEFORE the `DRY_RUN` guard at `:150-153`** — a malformed endpoint must be caught even in dry-run.
- `inspect-evidence.sh` — after `:28` (`endpoint=…`).
- `r2-conditional-put.sh` — after `:54` (`endpoint=…`). This covers `upload-evidence.sh` + `upload-bypass.sh` transitively (both `exec` it).
- `infra/bootstrap.sh` — after `R2_ENDPOINT` is set (`:219`) and before the Doppler-secrets push that persists it (`:222-227`); validate the value bootstrap is about to persist.

**Fixture sweep (load-bearing — 7 sites):** change every test `R2_CLA_EVIDENCE_ENDPOINT=` to a canonical-shaped synthetic value, e.g. `https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com` (32 hex, clearly synthetic, passes the regex):
- `gdpr-override.test.sh:167`, `:247` (default-substitution form `${R2_CLA_EVIDENCE_ENDPOINT-…}`), `:443`
- `inspect.test.sh:62`
- `upload-bypass.test.sh:67`, `:244`
- `upload-evidence.test.sh:62`

Add **one negative test** in `_r2-endpoint.test.sh`: a malformed endpoint (`https://evil.example.com`) → exit 64 with the `::error::` annotation. This is the security invariant; without it the regex is unverified.

### Phase 3 — Item 2: `env -u CF_ADMIN_TOKEN` wrapping

At the **2 real sites** in `gdpr-override.sh`:
- `:307` — `env -u CF_ADMIN_TOKEN doppler run -p soleur -c prd_cla -- aws … delete-object …`
- `:412` — `env -u CF_ADMIN_TOKEN doppler run -p soleur -c prd_cla -- aws … put-object …`

**Sentinel compatibility (verify, do not break):** `infra/main.test.sh:129-135` awk-checks that `doppler run -p soleur -c prd_cla` appears within 3 lines preceding each `aws --endpoint-url`. Prepending `env -u CF_ADMIN_TOKEN ` keeps the literal `doppler run -p soleur -c prd_cla` substring on the SAME line — the awk regex `L[i] ~ /doppler run -p soleur -c prd_cla/` still matches. **No sentinel edit needed**; add an AC that re-runs `main.test.sh` GREEN after the wrap.

**Test interplay:** `gdpr-override.test.sh` PATH-shadows `doppler` (a stub at `:160-172` that `exec "$@"`s after `unset CF_ADMIN_TOKEN`). `env -u CF_ADMIN_TOKEN doppler …` resolves `doppler` via PATH → still the stub. `env -u` strips `CF_ADMIN_TOKEN` from the env before exec — the stub already `unset`s it, so behavior is unchanged. Add an assertion (or confirm an existing one) that the stub's logged env does NOT contain `CF_ADMIN_TOKEN` (proves the scrub). Verify at deepen-plan that the test harness can observe the child env.

### Phase 4 — Item 4: inspect-evidence tombstone visibility

In `inspect-evidence.sh`:
- Add `tombstone <sha>` mode to the `case "$mode"` switch (`:81`): fetch `tombstones/<sha>.deleted.json` via `fetch_and_print` (reuses `assert_schema_version`, which already accepts `1.0` — tombstone schema is `1.0`). On 404, print `no tombstone for <sha>` to stderr, exit 0.
- **`by-pr` 404 handling:** per the issue, "by-pr 404 fall-through to tombstones/<sha>.deleted.json". **Design caveat:** `by-pr` filters by `.pr_of_record.number`, but a tombstone is keyed by `<sha>`, and the tombstone schema (`gdpr-override.sh:402-410`) has NO `pr_of_record` field — so `by-pr` cannot map a PR number to a tombstone sha. **Resolution:** ship the explicit `tombstone <sha>` subcommand as primary; update the `by-pr` "no records for PR #N" message (`:103`) to hint `try: inspect-evidence.sh tombstone <prior-object-sha> if the record was GDPR-erased`. (The issue offered "or" — this is the coherent branch.)
- Update the usage heredoc (`:18-23`) to document the new mode.

**Tests** in `inspect.test.sh`: extend the `aws` stub to recognize `s3 cp s3://…/tombstones/<sha>.deleted.json`. Add: (a) `tombstone <sha>` with a `1.0` tombstone body → exit 0, body echoed with `_key`; (b) tombstone with `schema_version: "2.0"` → exit 3 (consumer-boundary assertion holds for tombstones too); (c) `tombstone <sha>` on a missing key → exit 0 with `no tombstone` message.

### Phase 5 — Full-suite gate

`for t in apps/cla-evidence/scripts/*.test.sh; do echo "→ $t"; bash "$t" || exit 1; done && bash apps/cla-evidence/infra/main.test.sh` → all GREEN. Plus `shellcheck` on every edited/new `.sh` if available (`command -v shellcheck`).

## Files to Edit

- `apps/cla-evidence/scripts/gdpr-override.sh` — source both helpers; replace Step-1 verify + `_self_revoke`; `env -u CF_ADMIN_TOKEN` at 2 aws sites; `assert_r2_endpoint`.
- `apps/cla-evidence/scripts/inspect-evidence.sh` — `assert_r2_endpoint`; `tombstone <sha>` mode; usage heredoc; by-pr hint.
- `apps/cla-evidence/scripts/r2-conditional-put.sh` — `assert_r2_endpoint` after `:54`.
- `apps/cla-evidence/infra/bootstrap.sh` — source `_cf-admin-token.sh` (cross-dir); replace verify + self-revoke blocks; `assert_r2_endpoint` before the existing Doppler-secrets push.
- `apps/cla-evidence/scripts/gdpr-override.test.sh` — canonical-shaped endpoints (`:167, :247, :443`); env-scrub assertion for item 2.
- `apps/cla-evidence/scripts/inspect.test.sh` — canonical endpoint (`:62`); tombstone-mode stub + 3 new cases.
- `apps/cla-evidence/scripts/upload-bypass.test.sh` — canonical endpoints (`:67, :244`).
- `apps/cla-evidence/scripts/upload-evidence.test.sh` — canonical endpoint (`:62`).

## Files to Create

- `apps/cla-evidence/scripts/_cf-admin-token.sh` — `cf_token_verify`, `cf_token_self_revoke`.
- `apps/cla-evidence/scripts/_cf-admin-token.test.sh` — 5 cases.
- `apps/cla-evidence/scripts/_r2-endpoint.sh` — `assert_r2_endpoint`.
- `apps/cla-evidence/scripts/_r2-endpoint.test.sh` — positive + negative (malformed → exit 64).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` matched only **#3950 itself** (the issue this plan targets) against the planned file paths — no other open scope-out touches `apps/cla-evidence/scripts/**` or `infra/bootstrap.sh`.

## Acceptance Criteria

### Pre-merge (PR)

- AC1 — `apps/cla-evidence/scripts/_cf-admin-token.sh` exists and is sourced (not exec'd) by `gdpr-override.sh` AND `infra/bootstrap.sh`; `grep -c 'source.*_cf-admin-token' <both files>` returns ≥1 each.
- AC2 — `cf_token_verify` hard-fails (non-zero) on empty token-id; `_cf-admin-token.test.sh` case (c) asserts this. (The bootstrap behavior upgrade.)
- AC3 — `assert_r2_endpoint` is invoked in all 4 live consumers: `git grep -c assert_r2_endpoint apps/cla-evidence/scripts/gdpr-override.sh apps/cla-evidence/scripts/inspect-evidence.sh apps/cla-evidence/scripts/r2-conditional-put.sh apps/cla-evidence/infra/bootstrap.sh` → each ≥1.
- AC4 — Negative endpoint test: a malformed `R2_CLA_EVIDENCE_ENDPOINT` (e.g. `https://evil.example.com`) causes exit 64 with `::error::…canonical R2 hostname`. Asserted in `_r2-endpoint.test.sh`.
- AC5 — `git grep -c 'env -u CF_ADMIN_TOKEN doppler run' apps/cla-evidence/scripts/gdpr-override.sh` → exactly 2 (the DELETE + tombstone-PUT sites); no un-wrapped `doppler run -- aws` remains.
- AC6 — Item-2 env scrub proven: `gdpr-override.test.sh` asserts the PATH-shadowed `doppler` stub's observed child env does NOT contain `CF_ADMIN_TOKEN`.
- AC7 — `inspect-evidence.sh tombstone <sha>` returns the tombstone JSON with `_key` on a `1.0` body (exit 0), exits 3 on `2.0`, exits 0 with `no tombstone` on a missing key. Asserted in `inspect.test.sh`.
- AC8 — PR #3939 sentinel still passes: `bash apps/cla-evidence/infra/main.test.sh` GREEN (no edit to the sentinel block; the `env -u` prefix keeps `doppler run -p soleur -c prd_cla` on the matched line).
- AC9 — Full suite GREEN: every `apps/cla-evidence/scripts/*.test.sh` + `infra/main.test.sh` exit 0. No `stub.r2.example` / `example.invalid` remains: `git grep -c 'stub.r2.example\|example.invalid' apps/cla-evidence/` → 0.
- AC10 — `shellcheck` clean on all 4 new/created `.sh` and the edited driver scripts (if `shellcheck` available; else note "shellcheck not installed" and rely on suite GREEN).
- AC11 — PR body uses **`Ref #3950`** (NOT `Closes`) — `do-not-autoclose` label is set on the issue; auto-close would falsely resolve a deferred bundle.

### Post-merge (operator)

- AC12 — None. This is a pure code/test change; CI runs the `.test.sh` suites (`infra-validation.yml` runs `main.test.sh`; `cla-evidence.yml` exercises the upload paths). No migration, no infra apply, no manual step. Issue #3950 stays OPEN (do-not-autoclose); close manually only after the next cla-evidence change confirms no regression, per the issue's re-evaluation note. **Automation-feasibility note:** there is no automatable post-merge action — the verification IS the CI suite, which runs on merge.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/Compliance (CLO — touches the GDPR Art. 17 erasure path).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Pure bash refactor in a self-contained app dir with an established `.test.sh` convention and an existing policy-lint sentinel. The only cross-cutting risks are the cross-directory `source` from `infra/bootstrap.sh` into `scripts/` and the 7-site fixture-endpoint sweep — both enumerated and gated by ACs. No new dependency, no new infra, no new runtime process. Sequencing (helper first) is correct and load-bearing.

### Legal / Compliance (CLO)

**Status:** reviewed
**Assessment:** Items 1 & 2 *harden* the Art. 17 erasure driver (endpoint pinning prevents silent-no-op erasures that would leave a requester's data live under WORM; token-env scrub reduces bearer exposure). Item 4 improves auditability of erasures (tombstone visibility to operators/agents). No change to *what* data is processed or *which* records are erased — the override logic, tombstone schema (`schema_version 1.0`), and runbook §7 contract are untouched. No new lawful-basis question, no new special-category processing. The bootstrap "hard-fail on empty token-id" upgrade is defense-in-depth, not a compliance regression.

### Product/UX Gate

Not applicable — Product domain NOT relevant. No user-facing surface; operator-only bash scripts.

## Test Scenarios

| ID | Scenario | Expected |
| --- | --- | --- |
| TS1 | `cf_token_verify` on active token w/ id | echoes id, exit 0 |
| TS2 | `cf_token_verify` status≠active | non-zero, caller's `||` branch fires |
| TS3 | `cf_token_verify` empty `.result.id` | non-zero (bootstrap upgrade) |
| TS4 | `cf_token_self_revoke` curl error | warn, exit 0 (best-effort) |
| TS5 | `cf_token_self_revoke` empty id | warn, exit 0 |
| TS6 | `assert_r2_endpoint` canonical 32-hex host | no-op, continues |
| TS7 | `assert_r2_endpoint` malformed host | exit 64 + `::error::` |
| TS8 | gdpr-override dry-run w/ canonical stub endpoint | reaches dry-run exit 0 (no regression) |
| TS9 | gdpr-override DELETE/PUT child env has no `CF_ADMIN_TOKEN` | scrub asserted |
| TS10 | `inspect-evidence.sh tombstone <sha>` 1.0 body | exit 0, JSON + `_key` |
| TS11 | tombstone 2.0 body | exit 3 |
| TS12 | tombstone missing key | exit 0, `no tombstone` |
| TS13 | full suite + main.test.sh | all GREEN |

## Sharp Edges

- **Cross-directory source from `infra/bootstrap.sh`.** The helper lives in `scripts/`; bootstrap is in `infra/`. Source via `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/_cf-admin-token.sh"`. bootstrap's verify block (`:81-88`) runs BEFORE `INFRA_DIR` is computed (`:97`) — the `source` line (and possibly an earlier script-dir anchor) must be hoisted above the verify block. Verify ordering at deepen-plan / GREEN.
- **Logging-helper sourcing precondition.** `_cf-admin-token.sh` calls `red`/`green`/`yellow`, which both callers define but only define BEFORE their respective `source` points. The `source` must come after each caller's log-helper definitions. (gdpr-override defines at `:30-34`; bootstrap at `:56-59`.) If hoisting the bootstrap source above `:56` is needed for the `INFRA_DIR` issue above, the log helpers must move too — or the helper must emit plain `printf` to stderr. Decide at deepen-plan.
- **7 fixture endpoints fail the new regex (load-bearing).** `https://stub.r2.example` and `https://example.invalid` do NOT match `^https://[a-f0-9]{32}\.r2\.cloudflarestorage\.com/?$`. Every one of the 7 test sites must switch to a canonical-shaped synthetic hostname BEFORE Phase 2 validation is added, or the suite goes red. Do NOT add a test-only env bypass to skip validation — that backdoor defeats the security gate (the anti-pattern the LLM-security-test and `write-boundary-sentinel` learnings warn against).
- **`by-pr` → tombstone fall-through cannot resolve a sha from a PR number.** The tombstone schema has no `pr_of_record`; it is keyed by `<sha>`. A literal "by-pr 404 → fetch tombstones/<sha>" is incoherent because `by-pr` never holds the sha. Ship the explicit `tombstone <sha>` subcommand as primary; replace the automatic fall-through with a "no records for PR #N — try `tombstone <sha>`" hint.
- **`env -u` resolves `doppler` via PATH.** In tests `doppler` is PATH-shadowed; `env -u CF_ADMIN_TOKEN doppler …` still hits the stub (env modifies the environment, not PATH resolution). Compatible with the existing `gdpr-override.test.sh` stub.
- **Do not touch the PR #3939 sentinel.** Item 5 already landed in `infra/main.test.sh`. The `env -u` prefix is sentinel-compatible (keeps `doppler run -p soleur -c prd_cla` on the matched line). Only ADD an AC that re-runs it GREEN.
- **Plan filename date is write-time.** This plan is dated 2026-06-02; do not prescribe a fixed-date learning filename — let the author pick at write-time (`knowledge-base/project/learnings/best-practices/<topic>.md`).
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with a `single-user incident` threshold — do not blank it.

## Observability

This is a CLI/bash-script change with no new runtime service. Observability is GitHub Actions annotations + exit codes (operator-visible, no SSH).

```yaml
liveness_signal:
  what: cla-evidence .test.sh suites (incl. new _cf-admin-token.test.sh, _r2-endpoint.test.sh) + main.test.sh
  cadence: per-PR on cla-evidence path change + infra-validation.yml
  alert_target: CI red blocks the PR
  configured_in: .github/workflows/cla-evidence.yml, .github/workflows/infra-validation.yml
error_reporting:
  destination: GitHub Actions ::error:: annotations (assert_r2_endpoint, schema_version, self-revoke warns)
  fail_loud: true
failure_modes:
  - mode: malformed R2 endpoint
    detection: assert_r2_endpoint regex
    alert_route: "::error:: + exit 64 (script aborts before any aws call)"
  - mode: tombstone schema drift (not 1.0)
    detection: assert_schema_version in inspect-evidence.sh tombstone mode
    alert_route: "::error::schema_version mismatch + exit 3"
  - mode: CF admin token empty-id (verify upgrade)
    detection: cf_token_verify non-zero return
    alert_route: caller red() + exit 1 (gdpr-override) / abort (bootstrap)
logs:
  where: GitHub Actions job logs (no persistent store; scripts are operator-run or CI-run)
  retention: GitHub Actions default (90d)
discoverability_test:
  command: bash apps/cla-evidence/scripts/_r2-endpoint.test.sh
  expected_output: "ALL _r2-endpoint.sh tests passed."
  # Single command (no shell-active tokens) so preflight Check 10 can execute it
  # offline. Proves the endpoint-pin security gate is live. The full suite is
  # `for t in apps/cla-evidence/scripts/*.test.sh; do bash "$t"; done && bash
  # apps/cla-evidence/infra/main.test.sh` (run by CI's scripts shard +
  # infra-validation.yml) — kept here as prose, not as the probe command.
```

## Infrastructure (IaC)

Not applicable — no new server, service, cron, vendor account, DNS record, secret, or firewall rule. The change edits existing bash scripts under `apps/cla-evidence/scripts/` and `apps/cla-evidence/infra/bootstrap.sh` (an existing operator-run provisioning script — not new infra). No Terraform change.

**Phase 2.8 review note:** This plan introduces NO new Doppler-secret write, no Doppler config create, no vendor-dashboard click-path, no SSH step. The Doppler-secrets push in `infra/bootstrap.sh:222-227` is *pre-existing and untouched* — cited only as the placement anchor for the new `assert_r2_endpoint` call, which runs *before* that existing push. The R2 endpoint is already provisioned via Terraform (`infra/main.tf`, `infra/variables.tf`); this plan adds a regex *check* on the env value, not a new write. No `.tf` resource is created or needed.

## Alternative Approaches Considered

| Approach | Decision | Rationale |
| --- | --- | --- |
| One combined `_cla-evidence-lib.sh` | Deferred to plan-review | Two single-purpose helpers (`_cf-admin-token.sh` ×2 consumers, `_r2-endpoint.sh` ×4) keep orthogonal concerns separate; DHH may prefer one lib. |
| Test-only env bypass to skip endpoint validation | **Rejected** | A `SKIP_R2_ENDPOINT_CHECK` backdoor defeats the security gate it adds. Switch fixtures to canonical-shaped synthetic endpoints instead. |
| Automatic `by-pr` → tombstone fall-through | **Rejected** (replaced by hint) | Tombstone is keyed by sha; `by-pr` never holds the sha. Explicit `tombstone <sha>` subcommand + a hint is the coherent design. |
| Validate endpoint AFTER dry-run guard in gdpr-override | Rejected | A malformed endpoint should be caught even in dry-run; validate at the env-validation block. |

## Deferral Tracking

No items deferred to a later phase. The `by-pr` automatic fall-through is not deferred — it is replaced by a coherent design (subcommand + hint), not punted. If plan-review wants the combined-lib refactor, that is a same-PR decision, not a deferral.
