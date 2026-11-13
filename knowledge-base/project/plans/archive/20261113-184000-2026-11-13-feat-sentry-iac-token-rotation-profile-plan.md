---
title: "feat: extend the Sentry token rotation tool to the IaC integration token, and correct postmerge's Sentry token guidance"
date: 2026-11-13
slug: feat-sentry-iac-token-rotation-profile
branch: feat-one-shot-sentry-iac-token-rotation
type: feat
lane: single-domain
domain: engineering
brand_survival_threshold: aggregate pattern
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Enhancement Summary

**Deepened on:** 2026-11-13. The pass was kept proportionate for a small tooling and docs PR. Plan-review had already run DHH, Kieran, code-simplicity, the CTO devex lens and the full sharp-edges catalogue pass, so no further agent fan-out was spawned.
**Sections enhanced:** Risks and Sharp Edges (precedent diff), `tasks.md` (brought in line with the post-review design).
**Gates run:**

- Phase 4.6 (User-Brand Impact): present, threshold `aggregate pattern`.
- Phase 4.7 (Observability): 5 fields; `bash` verb; literal `--profile`.
- Phase 4.8 (PAT patterns): none.
- Phases 4.9, 4.10 and 4.13: not triggered.
- Phase 4.11: `lint-guard-contract.py` green.
- Phase 4.12 (Scope Check): 1 unfenced section, `Recommendation:` present.
- `technical-ruling-gate.sh --branch`: PASS, 14 rows.
- All cited rule ids are present in `AGENTS.md`.
- All cited issues and PRs were resolved live: #8681 open, #12740 open, #7942 open, #12665 merged, #7797 open.
- `gh secret set --help` lists `--no-store`.

### Key Improvements

1. `tasks.md` previously carried the pre-review design: seven probes, a conditional `prd_terraform` write and a per-branch digest loop. It now matches this plan: four probes, an unconditional two-config write with read-back, a non-blocking stale-copies report, a three-list reporter, and the SKILL.md byte plan.
2. A precedent diff against `scripts/mint-origin-ca-cert.sh` (Phase 4.4) is recorded under Risks and Sharp Edges.

### New Considerations Discovered

- The literal strings are consistent across the Implementation, AC, Observability and Test sections, checked by grep: `do NOT revoke the old token yet`, `HOLD THE NEW TOKEN`, `UNVERIFIED (value unknown)`, `STILL HOLD THE OLD TOKEN`, `STALE COPIES (no known reader in repo)`, `doppler preflight failed`.

## Overview

Two Sentry-token fixes in one PR.

1. **Rotation tool.** Add a `--profile ro|iac` selector to `scripts/rotate-sentry-actions-ro-token.sh`
   (default `ro`, so today's invocations and runbook steps stay valid unchanged). The `iac` profile
   runs the same one-process capture, normalise, verify, store and shred chain for the
   `iac-terraform-prd` Internal Integration token (`SENTRY_IAC_AUTH_TOKEN`): exact sorted scope
   equality, four read-only GET probes (one per IaC consumer class, all on the org-subdomain host),
   then stores on stdin to the GitHub repo secret, Doppler `soleur/prd` and Doppler
   `soleur/prd_terraform`, reads each Doppler store back by digest, and prints a three-list
   partial-state report (HOLD NEW / UNVERIFIED / STILL HOLD OLD) when a later store fails after an
   earlier one landed.
2. **postmerge Sentry token guidance.** Make every issue/event read in the postmerge skill name a
   token measured to return 200 on the issues API, keep the cron-monitor read on the token that
   already works there, and repair the stale degradation rows and the dead `jikigai` org fallback —
   inside a 9-byte `SKILL.md` budget.

Nothing here mints, rotates or stores a real token. All verification in this PR runs against stubs.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured / read 2026-11-13) | Plan response |
|---|---|---|
| "Extend the existing test (find via grep -rl …)" | No test exists. `git grep -l rotate-sentry-actions-ro-token` hits only the script itself, the runbook, ADR-031 and archived plans/specs. | Create `scripts/rotate-sentry-actions-ro-token.test.sh`. Commit 1 characterises the unchanged `ro` behaviour; commit 2 adds the profile + `iac` rows (CTO ruling, item 5). |
| postmerge "Phase 3.5 and `references/sentry-error-count-delta.md` currently fetch `SENTRY_AUTH_TOKEN` (fallback `SENTRY_API_TOKEN`)" for issue reads | Phase 3.5 reads **only** `/monitors/` with that token, and that read returns 200. The reference's single-issue GET already uses `SENTRY_ISSUE_RO_TOKEN` → `SENTRY_ISSUE_RW_TOKEN` (GET-only fallback) and explicitly forbids `SENTRY_AUTH_TOKEN`. The stale pointers are elsewhere: `SKILL.md` §Production Debugging names `SENTRY_API_TOKEN` (403 on issues, measured), `references/graceful-degradation.md` ties the delta phase to `SENTRY_AUTH_TOKEN` / `SENTRY_ISSUE_RW_TOKEN`, and both blocks fall back to the dead slug `jikigai`. | Fix the stale pointers and the slug; keep the RO-first GET ladder (CTO ruling, item 1 — see Decisions). |
| `SENTRY_IAC_AUTH_TOKEN` returns 200 on issues; `SENTRY_AUTH_TOKEN` 403s | Confirmed. Codes only (bodies discarded, values never printed) on `https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=is:unresolved`: `SENTRY_ISSUE_RO_TOKEN` 200, `SENTRY_ISSUE_RW_TOKEN` 200, `SENTRY_IAC_AUTH_TOKEN` 200, `SENTRY_AUTH_TOKEN` 403, `SENTRY_API_TOKEN` 403. On `/monitors/`: all five 200. | The narrowest token that reads issues (`SENTRY_ISSUE_RO_TOKEN`, scopes `[event:read, org:read]`) stays first; `SENTRY_IAC_AUTH_TOKEN` is named as the last-resort read. |
| Doppler `soleur/prd` + `soleur/prd_terraform` are two stores | Correct, and they are **independent**: Doppler branch configs here do not inherit live from the root (`prd_terraform` lacks 2 secret names the `prd` root carries and has 39 of its own, names-only census 2026-11-13; same finding recorded 2026-08-02 in `scheduled-terraform-drift.yml`'s "Cloudflare token drift" comment). All 8 `prd_*` branch configs also carry `SENTRY_IAC_AUTH_TOKEN` as independent copies (digest-equal to the root today). No repo code reads the key from any branch other than `prd_terraform`. | Write `prd` and `prd_terraform` unconditionally, read each back; report the other carriers as `STALE COPIES (no known reader in repo)` without writing them and without blocking the revoke; cleanup tracked in #12740 (CTO ruling, item 2b). |
| "extend dry-run to prove the Doppler store form without writing if the CLI allows" | The Doppler CLI's `secrets set --help` (v3.77.1): no dry-run / no-store flag. | The script header and the test both say so. The dry run runs the read-only Doppler preflight; the test pins the exact store argv + stdin (CTO ruling, item 4). |

## Research Insights

**Premise Validation.** No GitHub issue is cited by the brief. The cited file paths all exist on this
branch (`scripts/rotate-sentry-actions-ro-token.sh`, the runbook, ADR-031, the four workflows, the
postmerge SKILL.md + reference). Two premises were stale: the "existing test" (none exists) and
"postmerge issue reads use `SENTRY_AUTH_TOKEN`" (they use the RO→RW ladder; the stale pointers are the
Production Debugging bullet, the graceful-degradation rows and the `jikigai` fallback). ADR-031
§"Why a dedicated Internal Integration" holds: the live `SENTRY_IAC_AUTH_TOKEN` returned exactly
`["alerts:read","alerts:write","event:read","org:read","project:admin","project:read","project:write"]`
from `GET https://jikigai-eu.sentry.io/api/0/` (2026-11-13), matching the 2026-09-11 archived probe
(`knowledge-base/project/specs/archive/20260911-192621-feat-one-shot-7946-sentry-org-token-retire/phase-0-scope-probe.md`).
No environment-scoped secret shadows the repo secret: `gh secret list --env <e>` for
`sentry-infra-apply`, `infra-privileged`, `web-platform-infra-apply`, `release-publish` lists no Sentry name.

**Property List.**

- P1: an `iac` token is stored nowhere unless its `.auth.scopes` sorted equals the ADR-031 set exactly and every IaC consumer endpoint class returns 200 with it.
- P2: the plaintext never reaches argv, xtrace, stdout or stderr; it lives only inside one trap-scoped 0700 directory and is shredded on every exit.
- P3: after a green run, the GitHub repo secret, Doppler `prd` and Doppler `prd_terraform` hold the new value, the two Doppler stores proven by read-back digest.
- P4: when a store fails after another landed, the operator is told exactly which targets hold new, which are unverified and which still hold old, and that the old token must not be revoked yet.
- P5: a dry run writes nothing anywhere and still proves every store form the CLIs allow.
- P6: the `ro` profile's observable behaviour is unchanged (default, argv, stores, messages).
- P7: postmerge's issue/event reads name a token measured 200 on the issues API; its monitors read keeps working; the token-shape guard and stdin-config curl pattern stay; `SKILL.md` stays within its byte ceiling.

**Cut List.**

- A separate `rotate-sentry-iac-token.sh` → P1-P5 → the existing chain already buys P2/P5; a second copy would fork the safety properties. Cut; generalise instead (the brief's direction).
- Control-host `regionUrl` read + region pin for `iac` → no IaC consumer touches `sentry.io` or `de.sentry.io`. Cut for `iac`; kept for `ro` (CTO item 3).
- Seven-probe `iac` set (org detail, detectors, releases on top of the four) → P1 → exact scope equality already proves permissions; the extra three add no evidence on the same host. Cut to the brief's four (plan-review, CTO item 3b).
- Conditional `prd_terraform` write and per-branch digest loop → P3 → configs are independent copies, so the conditional branch is always taken and the loop would block every revoke. Replaced by an unconditional write + read-back and a non-blocking stale-copies report (CTO item 2b).
- Two separate `doppler configs get` calls → P4/P5 → one `doppler configs -p soleur --json` enumeration in the preflight proves login and both configs' existence (CTO item 8).
- Switching the postmerge single-issue GET to `SENTRY_IAC_AUTH_TOKEN` → P7 → already satisfied by `SENTRY_ISSUE_RO_TOKEN` (200, narrower). Not done (CTO item 1).
- A `doppler_secret` Terraform resource for the Doppler copies → P3 → Terraform cannot mint this token and a TF-var-fed resource would put it in state (terraform-architect + CTO item 6b).

**Value proposition.** Not a cost/performance claim; Phase 0.6c does not fire.

**Relevant files.**

- `scripts/rotate-sentry-actions-ro-token.sh` — constants block (`readonly SECRET_NAME`, `readonly EXPECTED_SCOPES` declared BEFORE argument parsing), arg loop, tool preflight, trap scope, normalise (python3), dry-run branch (`gh secret set ZZ_DRYRUN_7946 --no-store`, ciphertext-length check using a variable named `want`), `get()` (header file, `--disable --noproxy '*'`), region-pin block, `probes=( … )`, store block (literal `gh secret set SENTRY_ACTIONS_RO_TOKEN < "$TOK"` + `gh secret list` + `grep -c "^${SECRET_NAME}\b"`).
- Doppler stdin store form already in the repo: `scripts/mint-origin-ca-cert.sh` `mc_set()` (value on stdin from a file, `-p … -c … --no-interactive`, stdout+stderr to `/dev/null`) and its read-back digest comparison (§"7. Write to prd … read back"). `doppler secrets get --plain` appends one LF when piped (measured on the non-secret `SENTRY_ORG`: 11 bytes for `jikigai-eu`). `doppler configs -p soleur --json` objects carry the keys `created_at, environment, inheritable, inheritedBy, inherits, initial_fetch_at, last_fetch_at, locked, name, project, root` (measured, key names only).
- IaC consumers read for the probe set: `.github/workflows/apply-sentry-infra.yml` + `scheduled-terraform-drift.yml` (terraform `jianyuan/sentry`, `base_url = "https://${var.sentry_org}.sentry.io/api/"`; types `data.sentry_project`, 57 `sentry_alert`, 28 `sentry_cron_monitor`, 4 `sentry_uptime_monitor`, `data.sentry_project_issue_stream_monitor`); `scheduled-sentry-alert-drift.yml` → `scripts/sentry-alert-live-fidelity.sh` (`organizations/{org}/workflows/`); `sentry-audit-gate.yml` (org read; pins `SENTRY_API_HOST == ${SENTRY_ORG}.sentry.io`) → `apps/web-platform/scripts/sentry-monitors-audit.sh` (`organizations/{org}/`, `projects/{org}/{project}/`, `releases/`, `monitors/`, `workflows/`, `detectors/`). Plus operator/agent org issue search (`AGENTS.rules.md` `hr-no-dashboard-eyeball-pull-data-yourself`).
- Live probe of the current `SENTRY_IAC_AUTH_TOKEN` on the org subdomain, 2026-11-13 (codes only): `projects/jikigai-eu/web-platform/` 200, `workflows/` 200, `monitors/` 200, `issues/` 200 (also `organizations/jikigai-eu/`, `detectors/`, `releases/` 200). The `iac` probe set therefore passes on today's token.
- Test conventions: `scripts/rotate-supabase-db-credential.test.sh` (stub `doppler`/`curl` on PATH, synthesized values, one owning trap, stdin captured only on the `secrets set` arm). Registration is an explicit `run_suite` in `scripts/test-all.sh`; `scripts/lint-orphan-test-suites.sh` builds its population from `git ls-files '*.test.sh'`, so it sees the new suite only once tracked; a new suite needs its weight row (`python3 scripts/regenerate-shard-manifest.py --incremental --write` updates `scripts/suite-durations.tsv` + `scripts/suite-shard-legs.tsv`) or `scripts/test-all-corpus-weight-budget.test.sh` reds main (#12665). The name-stem convention (`<x>.test.sh -> <x>.sh`) covers the affected-set edge.
- postmerge pins: `plugins/soleur/test/skill-body-budget.json` caps `postmerge` at **48,000 bytes**; `SKILL.md` is **47,991** today (9 bytes headroom), enforced by `scripts/lint-skill-body-budget.py --base <ref>`. `tests/scripts/test-argv-bearer-sweep.sh` S7 executes the ONE fenced block in `postmerge/SKILL.md` holding `--config -` and `monitors/`, stubbing `doppler secrets get` per name, and asserts the good-token stdin config is `Authorization: Bearer <synth>-SENTRY_AUTH_TOKEN` and that a refused token prints `SKIPPED` + `SENTRY_TOKEN`; the same suite's S7 scan covers `references/sentry-error-count-delta.md`.
- `scripts/lint-shell-trace-credential-refusal.py` excludes `*.test.sh`; its Rule E (credential header on curl argv) is already satisfied by the script's `-H @file`. It takes `--changed --base <ref>`.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-09-11-every-sentence-my-runbook-inherited-was-false-when-measured.md` — measure, do not inherit, every claim (every token/endpoint/inheritance claim above is a 2026-11-13 measurement; the inheritance assumption in an earlier draft of this plan was exactly such an inherited claim, falsified by the names census).
- `scripts/rotate-x-api-secret-bootstrap.sh` header (cited by the script): `gh secret set --body -` stores the literal `-`; stdin with no body flag is the only correct form.
- `scripts/rotate-supabase-db-credential.test.sh` header (#7966): a rotation script that never completed a run went unnoticed because no end-to-end test existed.

**Related issues.** #8681 (open: the IaC token is an admin-scoped repo secret outside ADR-241 tiering); #12740 (filed by this plan: remove the unread `SENTRY_IAC_AUTH_TOKEN` copies from the `prd_*` branch configs).

**CLAUDE.md / AGENTS conventions.** `hr-never-paste-secrets-via-bang-prefix`, `cq-test-fixtures-synthesized-only`, `hr-never-run-commands-with-unbounded-output`, `cq-cite-content-anchor-not-line-number`. Local test runs are single files only (machine saturated): never `test-all.sh`, `run-registered-suites.sh` or an affected battery.

## Implementation Phases

### Phase 1 — Characterise `ro` (commit 1, script unchanged)

1.1 Create `scripts/rotate-sentry-actions-ro-token.test.sh` (`set -euo pipefail`, one owning trap, every
fixture synthesized). The script under test always runs with `< /dev/null`. Stubs on a per-case `PATH` dir:

- `gh`: records argv to `$T/rec/gh.<n>.argv`. Only the `secret set` arm reads stdin (`timeout 2 cat` into `$T/rec/gh.<n>.stdin`). `secret set <X> --no-store` prints an `A`-filled string of length `((48 + stdin_bytes + 2) / 3 * 4)` (what the script's ciphertext check computes, minus gh's newline). `secret set <X>` (store) appends `<X>` to `$T/gh-secrets`. `secret list` prints one `<NAME>\t2026-11-13T00:00:00Z` line per stored name plus a fixed unrelated name. Failure injection: `STUB_GH_SET_RC`, `STUB_GH_LIST_RC`.
- `curl`: records argv. It routes on the URL argument and writes the `-o` file: `/api/0/` → `{"auth":{"scopes":$STUB_SCOPES}}`; `organizations/jikigai-eu/` on `https://sentry.io` → `{"links":{"regionUrl":"$STUB_REGION"}}`; everything else `[]`. It prints the HTTP code from a per-URL-substring override map (default 200). It never reads stdin.
- `doppler` (used by `iac` rows; `ro` rows assert it is never called): per-config state `$T/dop/<cfg>/<NAME>` (seeded with the OLD value for `prd`, `prd_terraform` and two other `prd` branches, plus one branch WITHOUT the key). `configs -p soleur --json` prints a fixture array carrying the measured keys (`name`, `root`, `environment`, …). `secrets -p soleur -c <c> --only-names --json` prints `{"<NAME>":{}…}`. `secrets get <NAME> -p soleur -c <c> --plain` prints the stored value followed by `\n`, like the real CLI. `secrets set <NAME> -p soleur -c <c> --no-interactive` reads stdin into the state file and prints a canary line `STUB-ALL-OTHER-SECRETS-CANARY` to stdout, mimicking the real CLI. Failure injection: `STUB_DOP_CONFIGS_RC`, `STUB_DOP_SET_RC_<cfg>`, `STUB_DOP_GET_RC_<cfg>`, `STUB_DOP_GET_CORRUPT_<cfg>`.
- `agent-browser`: `get value <sel>` prints the synthesized token; argv recorded.

`TMPDIR=$T/tmp` so the script's `mktemp -d` lands where the test can assert it was removed. Synthesized token: a 64-char non-hex string (for example `synthIAC` repeated), inside `TOKEN_MINLEN..TOKEN_MAXLEN` and clear of secret scanners. Rows R1-R8 (Test Scenarios). The suite ends with an exact executed-assertion count check.
1.2 Register `run_suite "scripts/rotate-sentry-actions-ro-token" bash scripts/rotate-sentry-actions-ro-token.test.sh` in `scripts/test-all.sh` beside the `rotate-supabase-db-credential` registration, with a one-line why-comment.
1.3 `git add` the test file and `scripts/test-all.sh`, then run `python3 scripts/regenerate-shard-manifest.py --incremental --write` and confirm its summary names the new suite as new.
1.4 Run `bash scripts/rotate-sentry-actions-ro-token.test.sh` and (with the file now tracked) `bash scripts/lint-orphan-test-suites.sh`. Both must be green against the UNCHANGED script. Commit.

### Phase 2 — `--profile` + `iac` (commit 2, RED then GREEN)

2.1 Add the `iac` rows (I1-I12) and H2 to the test, and run it. The `iac` rows fail on `unknown argument '--profile'` (exit 2). That is the RED.
2.2 Edit `scripts/rotate-sentry-actions-ro-token.sh`:

- **Constants:** remove the early `readonly` from `SECRET_NAME` and `EXPECTED_SCOPES`. Reassigning a readonly aborts with rc 1, which Kieran measured. Set them in a `case "$PROFILE"` after parsing, then declare `readonly SECRET_NAME EXPECTED_SCOPES …` once.
- **Arg loop:** `--profile <ro|iac>`. A value is required, and any other value is a usage error (exit 2). The default is `PROFILE=ro`. The usage string names the flag.
- **`ro` profile:** keeps its triple, the region-pin block, today's six probes, the GitHub-only store with the literal line `gh secret set SENTRY_ACTIONS_RO_TOKEN < "$TOK"`, and today's messages.
- **`iac` profile:**
  - `SECRET_NAME=SENTRY_IAC_AUTH_TOKEN` and `INTEGRATION=iac-terraform-prd`.
  - `EXPECTED_SCOPES='["alerts:read","alerts:write","event:read","org:read","project:admin","project:read","project:write"]'`. The comment cites ADR-031 §"Why a dedicated Internal Integration" and names this constant the executable copy.
  - No region read.
  - Four probes on the literal `${ORG_HOST}` (`https://jikigai-eu.sentry.io`), each commented with its consumer:
    - `/api/0/projects/jikigai-eu/web-platform/`: project read (terraform `data.sentry_project`, `sentry-monitors-audit.sh`)
    - `/api/0/organizations/jikigai-eu/workflows/?per_page=1`: alert rules read (terraform `sentry_alert`, `sentry-alert-live-fidelity.sh`, audit)
    - `/api/0/organizations/jikigai-eu/monitors/?per_page=1`: monitors read (terraform `sentry_cron_monitor`, audit)
    - `/api/0/organizations/jikigai-eu/issues/?query=is:unresolved&limit=1&statsPeriod=24h`: org issues search (operator/agent issue reads)
- **`iac` preflight**, before the trap scope and before any capture:
  - Tools: `doppler`, `sha256sum`, `sed`.
  - One `doppler configs -p soleur --json` enumeration with output to a variable. A config list is metadata, not a secret.
  - Assert: `prd` has `root==true`; `prd_terraform` has `root==false` and `environment=="prd"`; there is at least one branch.
  - For every other `environment=="prd"` config, `doppler secrets -p soleur -c <c> --only-names --json | jq -e 'has("SENTRY_IAC_AUTH_TOKEN")'` builds `STALE_COPIES`.
  - Targets: `TARGETS=("GitHub repo secret SENTRY_IAC_AUTH_TOKEN" "Doppler soleur/prd" "Doppler soleur/prd_terraform")`.
  - Any failure exits 2 with `[FATAL] doppler preflight failed (<which>) — nothing was stored`. With `--from-file`, add `<path> still holds the plaintext; shred it (shred -u <path>) or re-run`, because the copy-and-shred has not happened yet. Kieran's point 4.
  - The preflight runs in dry-run and live alike (CTO items 4, 6, 8).
- **Header:** document `--profile` and the `iac` targets. State that the tool needs GNU userland (`shred`, `sed -z`, `sha256sum`) and that the filename keeps its historical `ro` name. Add one sentence: *Doppler's `secrets set` has no no-store mode, so the dry run cannot prove the Doppler store form without writing; it proves Doppler login and both target configs read-only, and the exact store argv + stdin is pinned by `scripts/rotate-sentry-actions-ro-token.test.sh`.*
- **Dry run (`iac`):** the preflight, then the unchanged normalise + sentinel diff + `gh secret set ZZ_DRYRUN_7946 --no-store` ciphertext-length check. Then print `[ok] dry run: Doppler login and soleur/prd + soleur/prd_terraform verified read-only; Doppler has no no-store mode — store form pinned by the test (nothing written)` and the `STALE COPIES` line. No Doppler write and no curl call.
- **Store (`iac`), after verification.** Lists: `HOLD_NEW=()`, `UNVERIFIED=()`; `STILL HOLD OLD` is derived as `TARGETS − HOLD_NEW − UNVERIFIED`. Every Doppler write sends stdout and stderr to `/dev/null`, because the CLI prints every other secret on a write. Only its exit code is read.
  1. `gh secret set SENTRY_IAC_AUTH_TOKEN < "$TOK"` (a literal line). A failure here, with nothing landed, prints today's revoke-the-NEW-token message.
     - Then `gh secret list`. If the list fails or omits the name, append to `UNVERIFIED` ("GitHub repo secret: possibly holds new") and call `store_fail`.
     - Otherwise append to `HOLD_NEW`.
  2. The Doppler stdin write of `SENTRY_IAC_AUTH_TOKEN` to `-p soleur -c prd --no-interactive < "$TOK" >/dev/null 2>&1`.
     - A non-zero rc calls `store_fail`, and `prd` stays in STILL HOLD OLD.
     - Otherwise run `dig_of prd`. A read failure or a mismatch appends to `UNVERIFIED` and calls `store_fail`. A match appends to `HOLD_NEW`.
  3. The same steps for `-c prd_terraform`, unconditionally (CTO item 2b).
  - `want_digest="$(sha256sum < "$TOK" | cut -d' ' -f1)"`. The name `want` is already taken by the dry run.
  - `dig_of <cfg>` runs `doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c "$1" --plain 2>/dev/null | sed -z 's/\n$//' | sha256sum | cut -d' ' -f1` under `pipefail`. Capture its rc explicitly.
  - A non-zero rc, or the empty-string digest `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`, is a READ FAILURE: UNVERIFIED, never a match. Kieran point 1, CTO item 8.
  - Only digests are ever compared. The value is never printed and never assigned to a variable.
- **`store_fail <what failed>`:**
  - When `HOLD_NEW` and `UNVERIFIED` are both empty, print today's message: nothing holds the new token, revoke the NEW token in-page (last four `…$TAIL4`), then retry.
  - Otherwise print, in order:
    - `[FATAL] <what failed>`
    - `HOLD THE NEW TOKEN (…$TAIL4): <each HOLD_NEW>`
    - `UNVERIFIED (value unknown): <each>`
    - `STILL HOLD THE OLD TOKEN: <each>`
    - `do NOT revoke the old token yet — re-run the rotation with a freshly minted token, then revoke both the old token and this new token (…$TAIL4) in-page`. The shredded token cannot be re-stored (CTO items 6, 9).
  - Exit 1.
- **`iac` success:** print the revoke-old guidance only when `HOLD_NEW` equals all three targets. Then print `STALE COPIES (no known reader in repo): <names> — not written; removal tracked in #12740`; this line does not block anything. Then print a pointer to the runbook's prove-then-revoke step.
2.3 Run the test (GREEN), then `shellcheck` and `bash -n` on both files. Commit.

### Phase 3 — Runbook IaC section

Add `## IaC token rotation (SENTRY_IAC_AUTH_TOKEN, iac-terraform-prd)` to `knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md`. The heading carries the literal secret name so a grep finds it. Keep the section short; the script header stays the one home of the mechanics.

- Integration `iac-terraform-prd` on `jikigai-eu`, with scopes per ADR-031. The executable copy is the script's `iac` `EXPECTED_SCOPES`.
- Mint: `agent-browser --headed --session-name sentry open https://jikigai-eu.sentry.io/settings/developer-settings/` → `iac-terraform-prd` → Tokens → *New Token*. The sanctioned login handoff and the `get value`-only discipline are the same as in the `ro` recipe.
- Dry run: `bash scripts/rotate-sentry-actions-ro-token.sh capture --profile iac --selector '#tok' --dry-run --expect ZZQP-SENTINEL-7947`, run against the local sentinel page.
- Live: `bash scripts/rotate-sentry-actions-ro-token.sh capture --profile iac --selector 'input[aria-label="Generated token"]'`.
- Store targets: the GitHub repo secret `SENTRY_IAC_AUTH_TOKEN`, Doppler `soleur/prd` and Doppler `soleur/prd_terraform`. All three are written. Doppler configs here are independent copies, not inherited. The other `prd_*` carriers are reported as stale copies (#12740) and are not written.
- Prove, then revoke (CTO item 10). Only after the script reports all three targets in HOLD NEW:
  - Dispatch `gh workflow run scheduled-sentry-alert-drift.yml` and `gh workflow run scheduled-terraform-drift.yml`.
  - Watch each by run id.
  - The revoke gate has two conditions: the alert-drift run concludes `success`, and the terraform-drift run's Sentry leg log shows no Sentry 401/403/auth error. That workflow is plan-only, and its exit 2 means drift, so a red run for a non-Sentry cause does not block.
  - Then revoke the previous token in the Tokens panel, identified by its masked last four. `agent-browser get count '<token row selector>'` must return 1.
- Add failure-table rows:
  - the partial-store report (three lists, and "do NOT revoke the old token yet");
  - `doppler preflight failed`;
  - a Sentry auth error in the terraform-drift Sentry leg after a store.
- Frontmatter `tags` gains `iac-terraform-prd`. The opening "One store" sentence is scoped to the `ro` token.

### Phase 4 — postmerge guidance (CTO ruling item 1, option C) — SKILL.md budget-bound

`SKILL.md` has 9 bytes of headroom (47,991 / 48,000). Its edits are limited to two substitutions, net **+8 bytes**:

- Phase 3.5 code block: `echo "jikigai")` → `echo "jikigai-eu")` (+3). This keeps exactly one fenced block holding `--config -` and `monitors/`. It also keeps the `SENTRY_AUTH_TOKEN`-first resolution, the shape guard and the `SKIPPED`/`SENTRY_TOKEN` warning text, all pinned by the S7 executed row.
- §Production Debugging bullet: `` `SENTRY_API_TOKEN` in Doppler `prd` `` → `` `SENTRY_ISSUE_RO_TOKEN` in Doppler `prd` `` (+5). The bullet's existing `scripts/sentry-issue.sh` pointer stays, and it already implements the RO → RW ladder.

The rest of the guidance goes in references, which have no byte ceiling:

- `references/sentry-error-count-delta.md`:
  - Change the fallback literal `"jikigai"` → `"jikigai-eu"`.
  - Add one dated paragraph under Prerequisites. Measured 2026-11-13: on the issues API, RO, RW and `SENTRY_IAC_AUTH_TOKEN` all return 200, while `SENTRY_AUTH_TOKEN`/`SENTRY_API_TOKEN` (Doppler `prd`) return 403. `SENTRY_AUTH_TOKEN` is therefore the Phase 3.5 monitors-only token. For an org-level issue search, use `SENTRY_ISSUE_RO_TOKEN` first and `SENTRY_IAC_AUTH_TOKEN` only as the last-resort read.
  - The GET ladder, the PUT, the shape guards and the stdin-config pattern are unchanged.
- `references/graceful-degradation.md`:
  - Row "No `SENTRY_AUTH_TOKEN`" → skips the cron-monitor check only (the monitors-only token).
  - Row "No `SENTRY_ISSUE_RW_TOKEN`" → skips the auto-resolve PUT only. The GET runs on `SENTRY_ISSUE_RO_TOKEN`; if neither RO nor RW is set, the error-count delta is `SKIPPED`.

There is no `description:` frontmatter edit. `bun test plugins/soleur/test/components.test.ts` still runs.

### Phase 5 — Verification (single files only, scratch under `/var/tmp`)

- `bash scripts/rotate-sentry-actions-ro-token.test.sh`
- `bash scripts/lint-orphan-test-suites.sh` (after `git add`)
- `bash scripts/test-all-corpus-weight-budget.test.sh`
- `python3 scripts/lint-skill-body-budget.py --base origin/main`
- `shellcheck scripts/rotate-sentry-actions-ro-token.sh scripts/rotate-sentry-actions-ro-token.test.sh`
- `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
- `timeout 600 bash tests/scripts/test-argv-bearer-sweep.sh > /var/tmp/argv-sweep.log 2>&1; tail -n 40 /var/tmp/argv-sweep.log`
- `bun test plugins/soleur/test/components.test.ts`
- `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch`
- `npx markdownlint-cli2 knowledge-base/project/plans/2026-11-13-feat-sentry-iac-token-rotation-profile-plan.md knowledge-base/project/specs/feat-one-shot-sentry-iac-token-rotation/tasks.md knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md`

No battery runners (`test-all.sh`, `run-registered-suites.sh`, affected sets).

## Files to Edit

- `scripts/rotate-sentry-actions-ro-token.sh`: adds `--profile`, the profile table, the `iac` preflight, the `iac` store, read-back and three-list reporter, and the header text.
- `scripts/test-all.sh`: one `run_suite` line and a comment.
- `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`: changed only by running `regenerate-shard-manifest.py --incremental --write`.
- `knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md`: the IaC section, three failure rows, the scoped "One store" sentence, and a tag.
- `plugins/soleur/skills/postmerge/SKILL.md`: two substitutions, net +8 bytes.
- `plugins/soleur/skills/postmerge/references/sentry-error-count-delta.md`: the `jikigai-eu` fallback and one dated paragraph.
- `plugins/soleur/skills/postmerge/references/graceful-degradation.md`: two corrected rows.

## Files to Create

- `scripts/rotate-sentry-actions-ro-token.test.sh`
- `knowledge-base/project/specs/feat-one-shot-sentry-iac-token-rotation/decision-challenges.md` (written at plan time)
- `knowledge-base/project/specs/feat-one-shot-sentry-iac-token-rotation/tasks.md` (written at plan time)

## Open Code-Review Overlap

One open scope-out names a planned file: #7942, which says two `*.mutation.sh` batteries under `plugins/soleur/test/` run in no gate, and mentions `scripts/test-all.sh`. **Acknowledge:** it is a different concern (unregistered mutation batteries). This PR adds one ordinary `run_suite` line and does not touch those batteries.

## Infrastructure (IaC)

Phase 2.8 fired on the Doppler write in the script. `soleur:engineering:infra:terraform-architect` reviewed it and ruled **SCRIPT-STORE-IS-CORRECT** on 2026-11-13; the CTO agent ratified that ruling (item 6b). The reasons:

- **Terraform cannot mint this token.** It is issued only through the Sentry web UI. The mint API needs `org:admin`/`org:integrations` or `org:write`, and no Soleur credential holds those (runbook §"Why the API path is closed", ADR-031 §Rotation).
- **The repo's `doppler_secret` precedents split on exactly that point.** `egress-audit.tf` is fed by a Terraform-minted `random_id`. The TF-var-fed ones (`cf-cert-reissue-token.tf`, `anthropic-ci-key.tf`) each needed an `hr-tf-variable-no-operator-mint-default` justification.
- **A TF-var-fed resource would weaken the design.** It would put the token in plaintext state and skip the scope/probe gate. It would also split the rotation across two tools, since the GitHub secret cannot move to Terraform here, and make the Sentry root manage its own credential.

`git grep SENTRY_IAC_AUTH_TOKEN -- '*.tf'` is empty, so nothing moves. These Doppler keys are deliberately not Terraform-managed. The reason is recorded here and in the script header.

### Terraform changes

None.

### Apply path

Not applicable, because no resources change. If a live rotation runs (outside this PR), it reaches every consumer of the repo secret: Sentry IaC applies, the drift legs, the alert-fidelity probe and the audit gate. The three-list report and the prove-then-revoke gate keep the old token valid until a consumer run is green.

### Distinctness / drift safeguards

The Doppler `prd` root and its branch configs are independent copies. The script writes the two named targets and reads them back. It also lists every other carrier as a stale copy, derived from the live enumeration rather than a hard-coded list; their removal is #12740. `dev` configs are untouched, because the IaC token exists only in `prd`.

### Vendor-tier reality check

Each Internal Integration allows up to 20 tokens (runbook, measured 2026-09-11). A re-run after a partial failure mints one more, so the revoke step brings the panel back to one row.

## Observability

```yaml
liveness_signal:
  what: "the rotation script's final line `[ok] done. The trap shreds the plaintext on exit.` with exit 0; for the STORED token, the scheduled consumers that read it — scheduled-sentry-alert-drift.yml and the sentry leg of scheduled-terraform-drift.yml — go red on a dead or under-scoped token"
  cadence: "per rotation (agent-run on incident or scope change); the two consumers on their existing schedules"
  alert_target: "the invoking agent's terminal (workstation layer); the consumers' existing run status and failure issues (GitHub Actions layer)"
  configured_in: "scripts/rotate-sentry-actions-ro-token.sh; .github/workflows/scheduled-sentry-alert-drift.yml; .github/workflows/scheduled-terraform-drift.yml"
error_reporting:
  destination: "stderr `[FAIL]`/`[FATAL]` lines plus a non-zero exit (1 verification/store, 2 usage/precondition, 78 xtrace, 130/143 signal) on the workstation; no Sentry emission — the tool handles a Sentry credential and runs where Sentry reporting would itself need that credential"
  fail_loud: true
failure_modes:
  - mode: "scope set differs from ADR-031"
    detection: "`[FAIL] .auth.scopes is … expected exactly …`, exit 1, nothing stored"
    alert_route: "workstation terminal"
  - mode: "a consumer endpoint class is not 200"
    detection: "`[FAIL] <code> <url-without-query>`, exit 1, nothing stored"
    alert_route: "workstation terminal"
  - mode: "Doppler unreachable, logged out, or a target config missing"
    detection: "`[FATAL] doppler preflight failed (<which>)`, exit 2, before capture"
    alert_route: "workstation terminal"
  - mode: "a later store fails or cannot be read back after an earlier one landed"
    detection: "`HOLD THE NEW TOKEN` / `UNVERIFIED` / `STILL HOLD THE OLD TOKEN` lists and `do NOT revoke the old token yet`, exit 1"
    alert_route: "workstation terminal"
  - mode: "stored token dead or under-scoped in CI"
    detection: "scheduled-sentry-alert-drift.yml red, or a Sentry 401/403 in the scheduled-terraform-drift.yml sentry leg"
    alert_route: "existing workflow failure reporting"
logs:
  where: "workstation terminal only (no file: the run handles a live credential, and only length + last four are ever logged)"
  retention: "session scrollback"
discoverability_test:
  command: "bash scripts/rotate-sentry-actions-ro-token.sh --help"
  expected_output: "--profile"
```

## Guard Contract

### Guard 1 — verify-before-store gate and read-back

**Property.** No store target receives a token unless its sorted `.auth.scopes` equals the selected profile's `EXPECTED_SCOPES` exactly AND every probe of the selected profile returns 200. An `iac` run tells the operator to revoke the old token only when the GitHub repo secret, Doppler `prd` and Doppler `prd_terraform` are all confirmed to hold the new value. For the two Doppler targets, confirmed means a successful, non-empty read-back digest.

**Assembly.**

- **Verification chokepoint.** One `fails` counter is evaluated once before the store block. It is fed by three checks: the scopes comparison, the region pin (`ro` only) and the single `for u in "${probes[@]}"` loop. The profile table is the only writer of `EXPECTED_SCOPES` and `probes`.
- **Store block.** It has three write sites: `gh secret set`, the Doppler `prd` write and the Doppler `prd_terraform` write.
- **Read-back.** One helper, `dig_of`, produces every Doppler verdict. One `gh secret list` check produces the GitHub verdict.
- **Revoke instruction.** It is printed from exactly one place, guarded by `HOLD_NEW == TARGETS`.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| M1 | the `iac` curl stub returns the `ro` triple as scopes | I5: exit 1 and zero `gh secret set` / Doppler write records |
| M2 | first `iac` probe 200, **second** (`workflows/`) 403 | I6: exit 1, zero store records, and the third and fourth probe URLs still recorded (the loop does not stop at the first failing member) |
| M3 | the `iac` profile ships with an empty `probes=()` (the gate's own dispatch) | I2 asserts the recorded curl URL list equals `/api/0/` plus the four `iac` paths in order, so a vacuous loop reds |
| M4 | `dig_of` compares without stripping the appended LF | I2 reds (the stub appends LF like the CLI): a correct store reads as UNVERIFIED |
| M5 | `dig_of` ignores the pipeline rc (a failed get hashes the empty string) | I9 reds: the read failure must land in UNVERIFIED with no revoke-old line |
| M6 | the `prd_terraform` write is removed, leaving a compliant `prd` write | I2 reds: exactly two Doppler writes, `prd` then `prd_terraform`, are required, and `prd_terraform` must read back new |
| M7 | the store block moved above the verification block (reorder, not delete) | I5/I6 red: a store record exists although verification failed |
| M8 | the stale-copies list is hard-coded or drops its second member | I2 reds: both fixture carriers (`prd_alpha`, `prd_beta`) must be named, and the key-less `prd_gamma` must not be |

**Harness rows.**

- H1 (edit to the SUITE): replace the doppler stub's `secrets set` arm with one that ignores stdin. I2's stdin-equals-token assertion must red.
- H2 (must-PASS, non-canonical): an enumeration with no other carriers. The run exits 0, prints no `STALE COPIES` names, and still prints the revoke-old guidance.
- H3: the suite asserts its exact executed-assertion count, so a skipped row cannot pass silently.

**Anchor.** ADR-031 §"Why a dedicated Internal Integration" and the 2026-09-11 archived probe anchor the `iac` `EXPECTED_SCOPES` outside the commit. A change to the constant without an ADR-031 amendment is a review finding.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing at merge, because the tool runs only during a rotation. A broken `iac` rotation would leave the Sentry IaC applies and the alert-drift and terraform-drift checks unable to authenticate. The alert rules that page the operator when users hit OAuth or BYOK failures could then drift or go unmanaged without anyone noticing.

**If this leaks, the user's data is exposed via:** the `iac` token (`project:admin`, `alerts:write`, `event:read`). It exposes event titles, messages, stack context and tags for every user's errors; user email and IP are null on this project (measured 2026-09-11). It also gives the ability to disable the alert rules that route user-facing failures to the operator. Every existing leak control stays: the xtrace refusal, the header passed via a file, stdin-only stores and the shred. Doppler write output is suppressed. The postmerge change narrows the token used for issue reads rather than widening it. The tool also does not spread a new live admin token into the unread branch copies (#12740).

**Brand-survival threshold:** aggregate pattern. A leak or a broken rotation degrades every user's error visibility at once rather than exposing one user's data or session, so no per-PR CPO sign-off is required.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Generalize scripts/rotate-sentry-actions-ro-token.sh with a --profile ro\|iac selector (default ro, existing callers/tests unchanged)" | Phase 2.2 arg loop + profile table; R1-R8 unchanged | mapped |
| 2 | "iac profile: Sentry Internal Integration iac-terraform-prd on org jikigai-eu, exact sorted scope equality [alerts:read, alerts:write, event:read, org:read, project:admin, project:read, project:write]" | Phase 2.2 `iac` `EXPECTED_SCOPES`; I2, I5 | mapped |
| 3 | "read-only GET probes, one per IAC consumer class (project read, alert rules read, monitors read, org issues search GET /api/0/organizations/jikigai-eu/issues/?query=...) chosen by reading .github/workflows/apply-sentry-infra.yml, scheduled-sentry-alert-drift.yml, sentry-audit-gate.yml, scheduled-terraform-drift.yml" | Phase 2.2 `iac` probes (the four named classes, each commented with its consumer) | mapped |
| 4 | "after verification store via STDIN only (never argv, never --body) to GitHub repo secret SENTRY_IAC_AUTH_TOKEN and Doppler soleur/prd + soleur/prd_terraform key SENTRY_IAC_AUTH_TOKEN" | Phase 2.2 store steps 1-3 | mapped |
| 5 | "confirm the doppler CLI stdin form for `doppler secrets set` from `doppler secrets set --help` and existing repo usage via grep of scripts/ for `doppler secrets set`; pin it in a test" | Research Insights (`--help`, `mc_set`); I2 argv+stdin assertions | mapped |
| 6 | "verify each store (gh secret list shows the name; Doppler: compare sha256 of value read back via `doppler secrets get --plain` piped into sha256sum, never printed)" | `gh secret list` check; `dig_of` | mapped |
| 7 | "if any store fails after another succeeded, print exactly which targets hold the new value and instruct \"do NOT revoke the old token yet\"" | `store_fail`; I7, I8, I9, I12 | mapped |
| 8 | "Keep all existing safety properties (xtrace refusal, single trap scope + shred, header via file -H @file, --disable --noproxy '*', literal pinned hosts, dry-run sentinel that writes nothing" | R1-R8 + I1, I2 | mapped |
| 9 | "extend dry-run to prove the Doppler store form without writing if the CLI allows — if not, say so in the script header and in the test" | header sentence; I1 + test comment; read-only preflight | mapped |
| 10 | "Extend the existing test (find via grep -rl rotate-sentry-actions-ro-token scripts plugins/soleur/test apps) with iac-profile rows using stubs for gh/doppler/curl/agent-browser like the existing test" | new test file (none existed); I1-I12 | mapped (premise stale, so the test is created) |
| 11 | "Update runbook knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md with a short IAC section (integration name, URL <https://jikigai-eu.sentry.io/settings/developer-settings/> -> iac-terraform-prd -> Tokens, the --profile iac invocation, store targets, then revoke old by masked last four)" | Phase 3 | mapped |
| 12 | "Make issue/event reads use SENTRY_IAC_AUTH_TOKEN, keep monitors working (SENTRY_AUTH_TOKEN), keep the existing token-shape guard and stdin-config curl pattern" | Phase 4 | mapped, with a divergence: reads keep the narrower `SENTRY_ISSUE_RO_TOKEN` first and name IAC as the last-resort read (CTO item 1; surfaced in decision-challenges.md) |
| 13 | "Watch skill-description/size budget tests" | Phase 4 byte plan (+8 of 9); Phase 5 `lint-skill-body-budget.py`, `components.test.ts` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/rotate-sentry-actions-ro-token.sh` | asks 1-9 | asked |
| `scripts/rotate-sentry-actions-ro-token.test.sh` | ask 10 | asked |
| `scripts/test-all.sh` run_suite line | — | inferred. Justification: `scripts/lint-orphan-test-suites.sh` fails on an unregistered `*.test.sh`, and an unregistered test gates nothing |
| `scripts/suite-durations.tsv` / `suite-shard-legs.tsv` | — | inferred. Justification: `test-all-corpus-weight-budget` reds main on an unmeasured suite (#12665) |
| Doppler preflight (enumeration) | ask 9 ("prove the Doppler store form without writing if the CLI allows") | asked; it also serves P4 (CTO items 4, 8) |
| Stale-copies report + #12740 | ask 6 ("verify each store") | inferred. Justification: every `prd_*` branch carries an independent copy, and naming them is what makes the "revoke the old token" consequence visible (CTO item 2b) |
| runbook edits | ask 11 | asked |
| postmerge `SKILL.md`, `sentry-error-count-delta.md` | ask 12 | asked |
| `graceful-degradation.md` rows | — | inferred. Justification: the rows contradict the token ladder that ask 12 keeps, so a reader following them would skip a phase that would run |
| `jikigai` → `jikigai-eu` fallback | — | inferred. Justification: it sits on the lines ask 12 edits, and the legacy slug is measured dead for every credential (2026-09-11 archived probe) |

### Split Assessment

- Subsystems touched: 3 (`scripts/`, `knowledge-base/engineering/operations/`, `plugins/soleur/skills/postmerge/`)
- Planned files: 9 (+2 generated tsv) | Estimated changed lines: ~520 (test ~330, script ~110, docs ~80)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- AC1: `bash scripts/rotate-sentry-actions-ro-token.test.sh` passes in two states. On commit 1 it runs R1-R8 against the unchanged script. On commit 2 it runs R1-R8 unchanged plus I1-I12 and H2, with the exact assertion count matching.
- AC2: `--profile` absent ≡ `--profile ro`. R4 runs in both forms and the recorded gh/curl argv files and stdout are byte-identical. An unknown profile value exits 2 (R2).
- AC3: `iac` happy path (I2):
  - exit 0.
  - The recorded curl URLs are exactly `https://jikigai-eu.sentry.io/api/0/` plus the four `iac` probe URLs (query strings included), in order. No `https://sentry.io/` or `de.sentry.io` URL appears.
  - Every curl argv carries `--disable`, `--noproxy`, `*` and `-H @<file>`.
  - There is one `gh secret set SENTRY_IAC_AUTH_TOKEN` with stdin byte-equal to the token and no `--body`.
  - There are exactly two Doppler writes, in order, with argv `secrets set SENTRY_IAC_AUTH_TOKEN -p soleur -c prd --no-interactive` then the same with `-c prd_terraform`, each with stdin byte-equal to the token.
  - Both stub state files hold the new value.
  - `STALE COPIES` names `prd_alpha` and `prd_beta` and not `prd_gamma`.
  - The revoke-old guidance is printed.
- AC4: the synthesized token appears in no recorded argv file and in neither stdout nor stderr of any row. The Doppler stub's `STUB-ALL-OTHER-SECRETS-CANARY` never appears in script output.
- AC5: no store record exists in I5 (scope mismatch), I6 (second probe 403) or I10 (preflight failure). In I6 the third and fourth probe URLs are still recorded.
- AC6: the partial rows each exit 1 and print the correct three lists and `do NOT revoke the old token yet`, with no revoke-old guidance:
  - I7: the Doppler `prd` write fails. GitHub is in HOLD NEW, and `prd` and `prd_terraform` are in STILL HOLD OLD.
  - I8: the `prd` read-back mismatches. `prd` is in UNVERIFIED.
  - I9: the `prd_terraform` read-back exits non-zero. `prd_terraform` is in UNVERIFIED, and it is not reported as a match.
  - I12: `gh secret list` fails after a write. GitHub is in UNVERIFIED and there are zero Doppler writes.
- AC6b: I11 (the GitHub write fails first) prints the revoke-the-NEW-token message and records zero Doppler writes.
- AC7: the `iac` dry run (I1):
  - exits 0 with zero Doppler write records and zero curl records;
  - records exactly one `gh secret set ZZ_DRYRUN_7946 --no-store` and one `doppler configs -p soleur --json`;
  - removes the trap directory under `$TMPDIR`.
  - The script header contains the sentence stating that Doppler has no no-store mode, and the test carries the same statement as a comment on I1.
- AC8: preflight rows:
  - I10: `doppler configs` fails, the run uses `--from-file`, and it exits 2 before capture. The source file still exists and the message names it.
  - I10b: `prd_terraform` is absent from the enumeration, and the run exits 2.
  - Both produce zero store records.
- AC9: `bash scripts/lint-orphan-test-suites.sh` (with the file tracked) and `bash scripts/test-all-corpus-weight-budget.test.sh` are green, and `shellcheck` is clean on both files.
- AC10: postmerge.
  - `python3 scripts/lint-skill-body-budget.py --base origin/main` passes.
  - `wc -c < plugins/soleur/skills/postmerge/SKILL.md` ≤ 48000.
  - `grep -c 'echo "jikigai")'` reports 0 and `grep -c 'echo "jikigai-eu")'` reports 1, in each of `SKILL.md` and `references/sentry-error-count-delta.md`.
  - On the single `SKILL.md` line containing `For production debugging use Sentry API`, `SENTRY_ISSUE_RO_TOKEN` is present and `SENTRY_API_TOKEN` is absent: `grep 'For production debugging use Sentry API' plugins/soleur/skills/postmerge/SKILL.md | grep -c SENTRY_API_TOKEN` → 0. The Phase 3.5 occurrences of `SENTRY_API_TOKEN` stay.
  - `graceful-degradation.md` carries the two corrected rows.
  - The `tests/scripts/test-argv-bearer-sweep.sh` S7 rows are green.
  - `bun test plugins/soleur/test/components.test.ts` is green.
- AC11: the runbook's IaC section names:
  - `iac-terraform-prd` and `https://jikigai-eu.sentry.io/settings/developer-settings/`;
  - the `--profile iac` dry-run and live invocations;
  - all three store targets and the stale-copies pointer to #12740;
  - the two-workflow prove gate with its two conditions;
  - revoking by masked last four.
- AC12: `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` passes.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** the CTO agent ruled on every fork. Full table: `decision-challenges.md`.

- Keep the RO-first issue-read ladder and fix the stale prose.
- Write `prd` and `prd_terraform` unconditionally and read each back. Report the other independent branch copies without blocking, and file #12740.
- Probe only the org subdomain for `iac`, with four probes.
- The dry run checks Doppler read-only, and the test pins the store form.
- Characterise `ro` in a separate first commit.
- Store order: GitHub, then Doppler `prd`, then `prd_terraform`. Run the preflight before any write, and use a three-list partial-state report.
- The runbook revokes only after a two-workflow prove gate.

The terraform-architect agent confirmed the script store over a `doppler_secret` resource.

There is no Product/UX surface (no UI files) and no Legal trigger: no new processing activity, and the postmerge change narrows the credential used.

## Test Scenarios

`ro` characterisation (commit 1, unchanged script; the script always runs with `< /dev/null`):

- R1 `bash -x …` and `SHELLOPTS=xtrace bash …` → 78, zero stub records.
- R2 no args → 2; `--dry-run` without `--expect` → 2; both `--selector` and `--from-file` → 2; (commit 2) `--profile xyz` → 2.
- R3 dry run `--from-file` with the sentinel: exit 0, one `gh secret set ZZ_DRYRUN_7946 --no-store` with stdin == sentinel, zero curl, zero Doppler records, trap dir gone, source file shredded.
- R4 live happy: exit 0; curl URLs are `/api/0/`, the control-host org read and the six `ro` probes; `gh secret set SENTRY_ACTIONS_RO_TOKEN` stdin == token; `gh secret list` called; zero Doppler records. (Commit 2: run again with `--profile ro`; records identical.)
- R5 scopes superset → exit 1, no `gh secret set`. R6 one probe 403 → exit 1, no store. R7 `regionUrl` ≠ `https://de.sentry.io` → exit 1, no store. R8 `--selector` capture through the `agent-browser` stub → same outcome as R4.

`iac` (commit 2):

- I1 dry run (AC7).
- I2 happy path (AC3). The stub appends LF on `get --plain`.
- I5 `ro` triple returned as scopes → exit 1, no stores.
- I6 `workflows/` 403 after the `projects/` 200 → exit 1, no stores, and probes 3-4 are still recorded.
- I7 the Doppler `prd` write exits 1 → partial report.
- I8 the `prd` read-back returns a different value → UNVERIFIED.
- I9 the `prd_terraform` read-back exits non-zero → UNVERIFIED, never matched.
- I10 the preflight `doppler configs` fails while `--from-file` is in use → exit 2, and the source still exists.
- I10b `prd_terraform` is missing from the enumeration → exit 2.
- I11 `gh secret set` fails → the revoke-NEW message, and zero Doppler writes.
- I12 `gh secret list` fails after the write → GitHub UNVERIFIED, and zero Doppler writes.
- H1 and H2 from the Guard Contract, and the exact assertion count (H3).

## Risks and Sharp Edges

- **The `postmerge/SKILL.md` byte budget.** The file has 9 bytes of headroom, and the two substitutions use 8. Any other edit to that file needs an equal trim, and it must be measured with `lint-skill-body-budget.py --base origin/main`, not estimated.
- **Hooks that match the Doppler store subcommand.**
  - The Claude Code PreToolUse hook blocks any Bash command whose text contains it without `> /dev/null`, and that includes a `grep` for it. When searching, split the literal (`P='secrets s''et'`).
  - The plan/spec write guard also flags the literal. This plan carries the reviewed Phase 2.8 acknowledgement, and `tasks.md` avoids the literal.
- **Doppler branch configs are independent copies.** The root write does not reach them, which is why `prd_terraform` is written explicitly. An earlier draft assumed inheritance; the names census falsified that.
- **The empty-string digest.** `dig_of` must treat a non-zero pipeline rc, or `e3b0c442…b855`, as a read failure. Otherwise a failed `get` would be compared as if it were data.
- **`TOKEN_MINLEN=40`.** Synthesized fixtures must be ≥ 40 chars and non-hex, to stay clear of secret scanners.
- **Test setup.** The test must set `TMPDIR`, and run the script with `< /dev/null`, before invoking it. Stubs read stdin only on their `set` arms.
- **The S7 executed row.** The row in `tests/scripts/test-argv-bearer-sweep.sh` extracts the ONE fenced block in `postmerge/SKILL.md` containing `--config -` and `monitors/`. Adding a second such block, or changing the Phase 3.5 token resolution order, reds it.
- **Precedent diff (deepen Phase 4.4), Doppler store + read-back.** `scripts/mint-origin-ca-cert.sh` is the closest sibling.

  | Aspect | `mint-origin-ca-cert.sh` | This plan's `iac` store | Why it differs |
  |---|---|---|---|
  | Write | `mc_set`: value on stdin from a file, `--no-interactive`, stdout+stderr → `/dev/null` | same form, `< "$TOK" >/dev/null 2>&1` | — |
  | Read-back | `mc_get` into a shell variable, then `printf '%s' "$got" \| sha256sum` | `doppler … --plain 2>/dev/null \| sed -z 's/\n$//' \| sha256sum`, digest only | The value must never be assigned to a variable (P2). `sed -z` strips the CLI's LF, the same way `$(…)` does in the precedent. |
  | Read failure | `mc_get … \|\| state=unreadable` | rc captured explicitly, and the empty-string digest also rejected | The precedent's variable path cannot hash "" by accident. The pipeline path can. |
  | Failure handling | `mc_fail_restore` writes the previous value back | no restore: the previous token stays valid until the revoke, and the three-list report says what holds what | A restore would need the old plaintext read into the trap dir, which widens exposure. The vendor-side token stays live, so a rollback is not needed. |

- **The `## User-Brand Impact` section.** A plan whose section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.

## Plan Review Revisions (2026-11-13)

The panel was DHH, Kieran and code-simplicity, plus the named CTO devex lens and a sharp-edges catalogue pass. Mechanical findings were applied:

- `dig_of` now checks the rc and rejects the empty digest (Kieran P1).
- The Doppler enumeration moved into the preflight, replacing the two `configs get` calls (Kieran, CTO 8).
- The AC3 URL count was corrected to `/api/0/` plus 4 (Kieran).
- A `--from-file` preflight message was added (Kieran).
- Stub stdin is read only on `set` arms, and the script runs with `< /dev/null` (Kieran, CTO F3).
- A Doppler stub state model was added (Kieran).
- The `readonly` handling, the literal store lines and the `want_digest` rename were added (Kieran).
- M2 now names its position, and the `gh secret list` failure row I12 was added (Kieran).
- The UNVERIFIED list was added (CTO F2).
- The runbook now has a two-workflow prove gate with a precise criterion (CTO F1/10).
- The `SKILL.md` byte budget is now planned, at +8 of 9 bytes (sharp-edges).
- The orphan lint runs after `git add` (sharp-edges).
- The AC10 grep is scoped to the bullet line (sharp-edges).
- The doppler JSON keys were measured (sharp-edges).
- Inheritance wording was replaced by the measured independent-copy fact (sharp-edges, CTO 2b).
- Exact lint invocations and the technical-ruling-gate and markdownlint checks were added (sharp-edges).

Simplifications applied:

- The probe set was cut from 7 to 4 (DHH, simplicity, CTO 3b).
- The conditional `prd_terraform` write and the per-branch digest loop were replaced (CTO 2b).
- Redundant test rows were cut: I3, I4, I13, I14 and the old H1 (DHH, simplicity).

Taste items are persisted to `decision-challenges.md`.

## Decisions

Full table: `knowledge-base/project/specs/feat-one-shot-sentry-iac-token-rotation/decision-challenges.md`. The CTO agent ruled items 1-10 on 2026-11-13, and ratified the terraform-architect store ruling. Item 7 (the rule-corpus wording) is an operator scope row. The named-panel taste items are recorded there for the operator.
