---
title: "fix(7898 §2): transport-confine the five Resend-forwarding infra scripts"
date: 2026-09-11
slug: fix-resend-five-infra-scripts-transport-confinement
branch: feat-one-shot-7898-resend-five-transport-confinement
issue: 7898
closes: none
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO new infrastructure and prescribes NO manual step. Every
     `systemctl` token below DESCRIBES the existing Terraform-managed `remote-exec` in
     apps/web-platform/infra/server.tf (terraform_data.*_install) that the merge-triggered
     apply-web-platform-infra.yml already runs — the same descriptive false-positive recorded in
     knowledge-base/project/learnings/best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply.md. -->

## Enhancement Summary

**Deepened on:** 2026-09-11
**Sections enhanced:** Proposed Solution (pin grammar, `emit_refusal()`, early-return refusals, `unset` list), Harness rows, Guard Contract, Files to Edit/Create, Acceptance Criteria (AC2/AC6/AC14/AC15/AC17), Test Scenarios, Dependencies & Risks, Hypotheses (new), Precedent diff (new), Non-Goals, Drawdown recipe (new)
**Research agents used:** repo-research-analyst, learnings-researcher, functional-discovery (plan phase); CTO ×2, CPO, fable advisor (gates); DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer (plan-review); security-sentinel, observability-coverage-reviewer, silent-failure-hunter, test-design-reviewer, git-history-analyzer, pattern-recognition-specialist, user-impact-reviewer, sonnet verify-the-negative sweep (deepen)

### Key Improvements
1. The off-box half of "a refused send is never silent" is bought by Vector Source 2 + one `logger -p user.crit` line per branch (measured PRIORITY 2), not by an 8-file Source 4 enrollment — and every early return *in the alert path* that skips a send now emits a crit row (`SEND_FAILED` for a failure, `SEND_SKIPPED` for a deliberate skip such as cooldown or an unset channel). The four per-tick early returns in the two Resend-only monitors (`ENV_FILE` missing, key unset, `df` failed) stay on-box by decision (Non-Goals; AC14's apply log is their detector).
2. The Sentry host pin is a positive DNS-label grammar (refuses `%2F`, empty labels and non-DNS bytes on its own), markers carry reason tokens only (a pasted DSN can never ship the public key), and the merged region is verified against the live prd triple post-merge without SSH.
3. The bootstrap's `--config` directive-injection guard has a committed harness (fake key by `env -i`, fd asserted in-process) after the "CODEOWNERS-gated" premise for cutting it was falsified.

### New Considerations Discovered
- The repo-wide lint summary counts files that FIRE (`100 … 66` today), not baseline lines (103 / 67) — both move by five; ACs assert both.
- `local.host_scripts_content_hash` moves on merge: no fresh web host should be born between the infra apply and the release run.
- The `unset` prologue precedent leaves `OPENSSL_CONF`/`LD_PRELOAD`-class vectors to the same actor; this PR closes them and records the lift for the §5 scripts.
- A `SOLEUR_*_SEND_FAILED` row is queryable but nothing pages on it — a Better Stack alert rule is filed as a follow-up with its user-visible consequence.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed); the lane-inference table's `security` / `infra` triggers give the same answer.

Section 2 of the credential-forwarding confinement tracker (#7898) names five scripts under
`apps/web-platform/infra/` that forward `RESEND_API_KEY` over `curl` with no transport confinement:
`disk-monitor.sh`, `resource-monitor.sh`, `container-restart-monitor.sh`, `cron-egress-alarm.sh` and
`resend-inbound-bootstrap.sh`. This plan applies the confinement pattern the plugins/** drawdown (§5,
merge commit b29131393 = PR #7986) and the Sentry-audit drawdown (open PR #8023) established, to
exactly those five files, and removes their five entries from the Rule D baseline so the repo-wide
lint proves the drawdown. The tracker itself stays open: §1 is blocked on an image-bake host window
and the 58 unnamed Rule D members are untriaged. The PR body says **part of #7898**, never `Closes`.

Four edits per file, measured against the classifier in the scratchpad before this plan was written
(every prescribed shape below was run through `scripts/lint-shell-trace-credential-refusal.py` on a
copy and returned `OK: 1 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)`):

1. the #7797 xtrace refusal as the first statement after `set …` (Rule A), unconditional arm;
2. `curl --disable --noproxy '*' --proto '=https' -g` as the literal first four arguments of every
   credentialed `curl` (Rule D transport limbs; HTTPS-only; no URL globbing);
3. the TLS-subversion `unset` prologue (`SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR
   CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS`), placed AFTER the `ENV_FILE` source where one exists;
4. a destination adjudication wherever Rule D reports an env-settable destination: the Sentry ingest
   triple in two files, and the `resend_api()` path + key shape in the bootstrap.

Plus: a refusal that reports rather than skips (stderr line + `SOLEUR_<UNIT>_{HALT,REFUSED}` marker
on stdout, and — where a second alert channel survives — the refusal text rides that channel), the
two baseline drawdowns (D 67 → 62, A/B/C 103 → 98, both re-derived from `origin/main` at plan time),
and argv-position assertions in the three exec harnesses so the runtime argv — not only the text the
linter reads — carries the flags in position.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (measured) | Plan response |
|---|---|---|
| "None of these five run under cloud-init / set -e in the host-bootstrap path" | True for the cloud-init path (none is in `cloud-init.yml` `runcmd`). Three of the five DO run under `set -euo pipefail` (`disk-monitor.sh:2`, `resource-monitor.sh:2`, `resend-inbound-bootstrap.sh:32`); the other two are `set -uo pipefail`. | Refusals use explicit `exit` / `return`, never a failing command, so `-e` is irrelevant to them. |
| "resend-inbound-bootstrap.sh: check whether server.tf hashes it into triggers_replace / user_data" | **Not hashed anywhere.** `grep -n resend-inbound-bootstrap apps/web-platform/infra/*.tf` hits only a comment at `dns.tf:128`. It is a one-shot run from a laptop shell under `doppler run -p soleur -c prd` (its own header, lines 24-26). | Edit it. Its refusals exit non-zero with a readable message on the invoking terminal. |
| (unstated) the four monitors are plain host scripts | **All four ARE hashed into `terraform_data` `triggers_replace` with SSH provisioners** (`server.tf` › `terraform_data.disk_monitor_install`, `resource_monitor_install`, `container_restart_monitor_install`, and `cron-egress-alarm.sh` folded into `terraform_data.cron_egress_firewall.config_hash`). `apply-web-platform-infra.yml` fires on the path-glob `apps/web-platform/infra/**` (`:69-72`) and its SSH `-target` set names all four (`:1239-1249`). A merge therefore re-runs each provisioner on web-1: file push + timer re-enable for the three monitors, and file push + `cron-egress-postapply-assert.sh` (which restarts `cron-egress-firewall.service`, gap-free) for the alarm. `hcloud_server.web` is NOT recreated (`ignore_changes=[user_data]`). | This is the established IaC delivery path for running hosts (server.tf's own comment: "Cloud-init handles new servers; this provisioner handles the existing one"), classed safe-to-merge in `knowledge-base/project/learnings/best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply.md`. Not a host-replacement window. Recorded in `decision-challenges.md` so `ship` renders "this merge restarts web-1's egress firewall" into the PR body. |
| "§1 … server.tf triggers_replace re-provisions the live host on merge; must ride a PR already taking that window" | `web-private-nic-guard.sh` is delivered by the SAME shape (`terraform_data.private_nic_guard_install`, in the same SSH `-target` set) as the four monitors here — so by the issue's own logic §1 site 3 would be equally routine. What actually blocks §1 is `soleur-host-bootstrap.sh`: it is in `local.host_script_files` (baked into the image, `server.tf:146`) and runs ONLY from cloud-init on a fresh host, so an edit lands nowhere until a host is rebuilt. | Out of scope and stays out; the reasoning correction is surfaced in the PR body's follow-up section for the tracker author, not decided here. |
| "expect D 67 -> 62; re-derive the count from main" | `origin/main` (8be1ba1a9) D baseline = **67** non-comment lines; the five are at lines 15, 16, 19, 25, 26. PR #8023 is OPEN (unmerged) and its two D deletions are at lines 41 and 71 — hunks `@@ -38,7` and `@@ -68,7` — so no textual overlap with this PR's deletions. A/B/C baseline = **103**, the five at lines 13, 14, 17, 32, 33. | ACs assert `count(main) − 5` for both baselines rather than a literal, so the AC survives #8023 merging first (D would then be 65 → 60). Rebase before the baseline edit and again before ship, per the constraints. |
| "a SOLEUR_* marker on stdout so it reaches the vector allowlist / Better Stack" | **None of the four monitor units is in Vector Source 4's `include_matches.SYSLOG_IDENTIFIER` allowlist** (`apps/web-platform/infra/vector.toml` › `[sources.host_scripts_journald]`; grep for `disk-monitor|resource-monitor|container-restart|cron-egress` returns only a comment at `:333`). Their units carry no `SyslogIdentifier=` (`cloud-init.yml:151-161,187-197`; `container-restart-monitor.service`; `cron-egress-alarm@.service`), their stdout/stderr is journald PRIORITY 6, and Source 2 ships PRIORITY 0-2 only. So today every line these four print is journald-only. | Source 4 is not the only sink. **Source 2** (`vector.toml` › `[sources.system_journald]`, lines 61-64) ships PRIORITY 0-2 from ANY unit (only `inngest-server.service` / `vector.service` excluded, no identifier filter) into the same scrub → Better Stack pipeline (`inputs = [… "system_journald" …]` at `:365`). So a `logger -p user.crit -t <unit> 'SOLEUR_<UNIT>_… '` line in each refusal branch reaches Better Stack today with zero unit / `vector.toml` / cloud-init edits and a row quota of "one row per refusal" (CTO finding, verified by reading the source block). `logger -t` is already used by host scripts (`ci-deploy.sh` › `logger -t "$LOG_TAG"`), so `util-linux` is present. That line is carried in THIS PR; Source 4 enrollment (which would also ship the per-tick narration) is documented in-place as a Non-Goal with no user-visible consequence left to file. Caveat recorded: #6551 (OPEN) observed a PRIORITY-3 row shipping that no source admits — the shipper's filter behaviour is under-explained in the over-shipping direction; nothing suggests under-shipping of PRIORITY 2. |
| "destination pinned to the Resend API host … case-folded / trailing-dot-tolerant host match" | The Resend destination is a **literal** in all five (`"https://api.resend.com/emails"` ×4; `RESEND_API="https://api.resend.com"` in the bootstrap). Rule D's pin clause fires only on env-settable destinations and reports none for Resend. It DOES report `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` (both files) and `SENTRY_PUBLIC_KEY` (alarm only, where it sits in the URL) — findings the §2 text does not mention but which must clear for the files to leave the D baseline. | The case-fold / trailing-dot pattern (from `scripts/betterstack-query.sh` › the `_bs_host` chain) is applied where it is real: `SENTRY_INGEST_DOMAIN`. Resend gets nothing — pinning a literal is theatre (a `readonly` on the constant was cut at plan-review for the same reason). |
| "the A/B/C baseline is out of scope; if the edit incidentally clears an entry, remove it" | In `--changed` / explicit-path mode the linter bypasses BOTH baselines (`main()`: `baseline = set() if scoped …`). Touching the five exposes their Rule A findings in the `lint-bot-statuses` job (advisory, not in `scripts/required-checks.txt`, but red is red), and the A/B/C baseline header itself says "any PR that edits a listed script must remediate it". | Add the refusal to all five and remove their five A/B/C entries (103 → 98). Same five files — not hunting. |
| §5 form `curl --disable --noproxy '*' …` | PR #8023 (concurrent, unmerged) extended the form to `--disable --noproxy '*' --proto '=https' -g` and measured that a later duplicate `--noproxy ''` silently supersedes the first (its F16 finding). The §2 text asks for HTTPS-only. | Adopt the four-flag form; the harness asserts exactly-once `--noproxy` cardinality. `-g` matters here because two URLs interpolate substituted values (`${SENTRY_INGEST_DOMAIN}`, `${path}`). The uncredentialed loopback `curl … "$METRICS_URL"` in `resource-monitor.sh` (http://127.0.0.1:3000) is NOT touched — `--proto '=https'` would break it and Rule D does not classify it. |
| `resend-inbound-bootstrap.sh` header: the key "reaches curl through --config on a process-substitution FD, so it exists only as an unlinked pipe" | True, and the classifier reads the key and `$path` as destination operands of that call. Measured locally with a synthetic value: a `RESEND_API_KEY` containing `\nurl = "http://127.0.0.1:9/exfil"` makes an unconfined `curl --config <(printf 'header = …' "$k")` fetch **both** the injected URL and the intended one (`url_effective=…/exfil` then `…/intended`); `--proto '=https'` refuses only an `http://` injection, not an `https://` one. | The key-shape check (`^re_[A-Za-z0-9_-]+$` — live prd key measured: `re_` prefix, 36 chars, `[A-Za-z0-9_]`; `-` admitted because it cannot open a directive boundary and lowers rotation-breakage risk, CTO finding) and the path allowlist (`^(/domains|/webhooks)(/[A-Za-z0-9_-]+)?$`, covering all eight in-file call sites) are real guards against config-directive injection and authority smuggling, not classifier appeasement. The CTO independently reproduced the injection WITH all four transport flags present: the injected `url = "https://127.0.0.1:9/exfil"` was still attempted. |
| "the 15-script drawdown … the merge into b29131393" | b29131393 IS the squash-merge commit of PR #7986, not a target it merged into. | Cite it as the merge commit. |

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 7898`: OPEN, labels `priority/p2-medium type/chore type/security`, `closedBy: []`. Premise holds.
- `gh pr view 8023`: OPEN, not draft, `mergedAt: null`, head `feat-one-shot-7997-sentry-curl-transport-confinement`; touches `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` (2 deletions, lines 41/71), the two Sentry scripts, three workflows, `review/SKILL.md`, `work/SKILL.md`, and ADR-202 (which already exists on `origin/main`, dated 2026-09-04 — #8023 AMENDS it, it does not author it). Does NOT touch the classifier `.py`, the A/B/C baseline, or any of the five files here.
- The five files exist on `origin/main` and all five are in BOTH baselines (line numbers above). The classifier on the unedited five reports **22 violations** (5 × Rule A absent refusal; 8 transport-limb findings, one per credentialed curl; 9 destination-pin findings) — this is the RED state for `cq-write-failing-tests-before`.
- `b29131393` exists on `origin/main` and is the §5 merge (PR #7986: "confine credential forwarding in the fifteen shipped plugin scripts, pin the Better Stack destination, and partition the BYOK concurrency outcomes").
- ADR corpus grep for the mechanism (`--disable`, `noproxy`, "destination pin", "test seam"): ADR-214 (a test seam for a destination pin must never be env-declared) is the governing decision; nothing in any ADR's rejected-alternatives table rejects transport flags or host allowlists. ADR-052 (a hostname pin is not automatically a boundary) governs the residual disclosure. ADR-031 (`## Sentry host glossary`, table row `**Ingest**`) is the authority for the ingest host shapes `o<id>.ingest.de.sentry.io` / `o<id>.ingest.us.sentry.io`.
- Live values, read from Doppler prd (read-only, values not printed): `SENTRY_INGEST_DOMAIN` = `o<orgid>.ingest.de.sentry.io` (matches the `*.ingest.de.sentry.io` arm); `SENTRY_PROJECT_ID` numeric; `SENTRY_PUBLIC_KEY` 32 hex; `RESEND_API_KEY` `re_`-prefixed, `[A-Za-z0-9_]` only. Every prescribed adjudication accepts the live value on its first tick.
- No relevant brainstorm in `knowledge-base/project/brainstorms/` (last five are unrelated: prebake, headroom, serena, omnigent).

### Property List (Phase 0.6b)

- P1. Every credentialed `curl` in the five files ignores `~/.curlrc` and every proxy variable (Rule D transport limbs).
- P2. Every credentialed `curl` speaks only HTTPS and does not glob-expand a substituted URL.
- P3. No credentialed request's destination can be re-pointed by an env-settable or caller-settable value (`SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` / `SENTRY_PUBLIC_KEY`; `resend_api` `$path` and the `--config` directive line).
- P4. The TLS trust store and session-key log cannot be substituted from the environment the request runs in — including the environment the `ENV_FILE` source adds after the prologue.
- P5. A trace-enabled shell cannot print a bound credential (Rule A/B/C), and the guard names no credential it might miss (unconditional arm — three of the five bind the key by `source` BELOW the prologue, exactly the vacuous-hatch shape §5 measured).
- P6. A refused send is never silent: stderr line + stdout marker, and the refusal text rides the surviving channel where one exists.
- P7. The repo-wide lint proves the drawdown: both baselines lose exactly these five entries; the classifier is byte-unchanged.
- P8. The runtime argv (what the stub `curl` receives), not only the text the linter reads, carries the four flags in position, with `--noproxy` exactly once.
- P9. A FAILED or SUPPRESSED alert send after confinement is visible off-box: the pre-existing `Resend … POST failed` branches (the failure a wrong flag would produce — today on-box only for the two Resend-only monitors) and the alarm's cooldown/`jq`/unset branch emit a crit row. Added at plan-review: the simplification panel asked that this line either be cut or own a property; it owns one because a send that silently fails after this PR is the one regression the PR itself could introduce.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property | Already covered by / why cut |
|---|---|---|
| Case-folded, trailing-dot-tolerant pin on the **Resend** host | P3 | The Resend host is a literal in all five; Rule D's own census reports no Resend pin finding. The fold idiom is applied to `SENTRY_INGEST_DOMAIN` instead, where the value is env-settable. |
| Vector Source 4 enrollment of the four monitor units (so markers reach Better Stack) | P6 (off-box half) | Cut: Source 2 already ships PRIORITY 0-2 from every unit, so one `logger -p user.crit` line per refusal branch buys the off-box half of P6 without touching a unit, `vector.toml` or cloud-init (CTO finding). Source 4 enrollment would additionally ship per-tick narration — no property in the list needs that. |
| Per-file fixtures in `scripts/lint-shell-trace-credential-refusal.test.sh` | P7 | That harness is a per-LIMB synthetic corpus (`scripts/fixtures/shell-trace-refusal/`, "one fixture per limb, ALONE"), not per repo file; adding repo files there would land them in the excluded `fixtures/` walk. The five files' own harnesses under `apps/web-platform/infra/*.test.sh` are the per-file pattern. |
| A new `resend-inbound-bootstrap.test.sh` | P3/P8 for the bootstrap | KEPT after deepen-plan (an earlier cut rested on a false premise: the one-line `run: bash …` registration in `infra-validation.yml` is NOT review-gated — `require_code_owner_review` is unset on the CI ruleset and one-shot PRs add such lines routinely, e.g. #7954, #7965). The Rule D linter only proves a comparison EXISTS; loosening `^re_[A-Za-z0-9_-]+$` to `^re_` passes it and re-opens the measured injection, so a committed harness is the only durable guard (test-design finding). |
| A `readonly …_PINNED` constant compared against the Resend URL | P3 | §5 measured on `provision-doppler.sh` that a differently-named constant adjudicates nothing — `_adjudicated()` is called with the variable the tokenizer mistook for the destination. Pinning a literal is theatre. |
| Classifier edits of any kind | — | Forbidden by the ask; and none is needed — every shape passes unmodified (measured). |

### Relevant files (edit targets and their consumers)

- `apps/web-platform/infra/disk-monitor.sh` (108 lines; one Resend curl at `send_alert()`; sources `ENV_FILE` at line 18).
- `apps/web-platform/infra/resource-monitor.sh` (143; one Resend curl at `send_alert()`; one UNcredentialed loopback curl at `sample_active_sessions()` — leave it alone; sources `ENV_FILE` at line 25).
- `apps/web-platform/infra/container-restart-monitor.sh` (263; Sentry store curl in `sentry_event()`, Resend curl in `resend_email()`; `set -uo pipefail` at line 34; sources `ENV_FILE` at line 61; Sentry env arrives from the doppler-wrapped unit).
- `apps/web-platform/infra/cron-egress-alarm.sh` (73; Sentry cron check-in with `${SENTRY_PUBLIC_KEY}` IN THE URL PATH at lines 27-29; Resend curl at lines 59-63; `set -uo pipefail` at line 15; all env from the doppler-wrapped `cron-egress-alarm@.service`).
- `apps/web-platform/infra/resend-inbound-bootstrap.sh` (221; `resend_api()` is the sole curl chokepoint with two branches; EIGHT call sites at lines 91, 100, 112, 131, 150, 165, 176, 211 — all `/domains…` or `/webhooks…`).
- Content-shaped `.ts` consumers that must stay green (they parse the scripts' source): `apps/web-platform/test/resend-sender-domain.test.ts` (the `from` senders of all four monitors — no new `--arg from`) and `apps/web-platform/test/sentry-container-restart-alert-op-contract.test.ts` (the monitor's `op:` tag set — the refusal marker introduces no `op:` string).
- Harnesses: `disk-monitor.test.sh` (11 assertions), `resource-monitor.test.sh` (11), `container-restart-monitor.test.sh` (18; fixture `SENTRY_INGEST_DOMAIN="ingest.example.test"` at line 65 and `sentry_hit()` at line 135 grep that host — both must move to a vendor-shaped synthetic host once the pin exists, per ADR-214), `cron-egress-firewall.test.sh` (static `assert_grep` rows over `$ALARM` at lines 666-668; no exec harness for the alarm). All four run in `infra-validation.yml` › `deploy-script-tests` (PR-triggered on `apps/*/infra/**`) AND in the required `test` check via `scripts/test-all.sh` › nested `apps/web-platform/infra/run-registered-suites.sh` (derives its list from that workflow).
- Blocking arm of the lint: `scripts/test-all.sh:1643` `run_suite "scripts/lint-shell-trace-credential-refusal-repo" python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide, baselines applied) inside the required `test` check. Advisory arm: `.github/workflows/ci.yml:180` `--changed --base origin/main` in `lint-bot-statuses` (not required).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` rows 106-112, 155-156 count P1b operand sites per file with ROW-BY-ROW EQUALITY; none of the prescribed constructs adds a relative-path operand (agent-verified against the counting families), but the suite must be run post-edit and, if a row moved, regenerated in the same commit with the reason (`bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline`).
- `apps/web-platform/infra/doppler-injection-bound.test.sh:256` carries a prose ledger string citing `container-restart-monitor.sh:61` (the `. "$ENV_FILE"` line). It is not asserted on, but this edit moves that line; update the citation to the content anchor (`container-restart-monitor.sh › the ENV_FILE source`) per `cq-cite-content-anchor-not-line-number` (the rule grandfathers old citations; this one is being touched).
- Delivery: `apps/web-platform/Dockerfile:208-216` COPYs the four monitor scripts into the image (`local.host_script_files`), so the merge ALSO fires `web-platform-release.yml` (paths `apps/web-platform/**`) — a container rebuild + deploy in addition to the infra apply.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-09-six-of-my-errors-were-the-class-i-was-reviewing-for.md` (PR #7986, the §5 drawdown): anchor assertions on syntax (`^\s*curl …`), never bare tokens that a comment can satisfy; run the instrument against a known case before trusting its verdict — this plan ran the classifier on the unedited five (22 findings) and on the edited probes (0) before prescribing anything.
- `knowledge-base/project/learnings/2026-09-07-the-class-recurred-in-three-days-and-every-instrument-was-broken.md` (#7873): read the runner's own summary line as the verdict (`OK: N scanned file(s), A baselined (A/B/C), D baselined (D)`), never a hand-rolled grep over its output.
- `knowledge-base/project/learnings/test-failures/2026-08-19-my-stub-could-not-express-the-failure-so-the-fix-reverted-green.md` (#7590): a `mk_curl_stub` ending in unconditional `exit 0` cannot express transport failure. The monitor stubs here already honour `MOCK_CURL_FAIL=1`; the new argv rows write a `violations` file rather than exiting, so a violation cannot be masked by the stub's own exit code.
- `knowledge-base/project/learnings/test-failures/2026-09-02-my-fake-curl-put-the-seam-above-everything-the-vendor-validates.md`: the stub sits above what the vendor validates; the rows here assert only argv shape (which is exactly what the stub can see), and the vendor-side properties are covered by the measured probes in this plan, not by the stub.
- `knowledge-base/project/learnings/best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply.md`: any edit under `apps/web-platform/infra/**` fires the infra apply; `cron-egress-alarm.sh` is in `cron_egress_firewall.config_hash`, so the merge restarts web-1's live egress firewall (gap-free). No new `ASSERT-FAILED:` sentinel is added, so no runbook row is required by that suite.
- `knowledge-base/project/learnings/2026-07-18-adr-ordinal-collision-sweep-and-off-box-journald-cost-surface.md` (#6438): shipping a unit's stderr off-box for the first time is a trust + quota change requiring a per-line sweep and `SOLEUR_PROBE_VERBOSE` gating of happy-path narration — the measured reason Source 4 enrollment is its own PR.
- `knowledge-base/project/learnings/integration-issues/2026-04-05-shell-mock-testing-and-disk-monitoring-provisioning.md` (#1409): the monitor mocks capture `$*` to a file; parse with `grep`, never `${!@}`.
- `knowledge-base/project/learnings/2026-09-07-my-guard-pinned-the-three-attributes-the-vendor-already-refuses.md`: pin the un-enforced sibling. `--disable`/`--noproxy` already close `.curlrc`/proxy; what they do NOT close is the trust store (`unset` prologue), URL globbing (`-g`), scheme (`--proto`), and the `--config` directive line (key shape) — each adjudication here targets one of those, not a property another flag already enforces.
- `knowledge-base/project/learnings/2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md` (#4177): if the merge-triggered SSH apply fails, diagnose L3 (CF tunnel bridge / `var.admin_ips`) before L7 (key); the workflow's own `gh run view --log` is the no-SSH probe.

### CLAUDE.md / AGENTS conventions carried

`cq-write-failing-tests-before` (RED state measured: 22 findings; harness rows written before the script edits), `cq-assert-anchor-not-bare-token`, `cq-cite-content-anchor-not-line-number`, `cq-test-fixtures-synthesized-only` (synthetic org id `o0000000`, fake key `re_test_fake_key_123`), `hr-observability-layer-citation`, `hr-no-ssh-fallback-in-runbooks`, `hr-verify-repo-capability-claim-before-assert` (every "X is not in Y" above names the grep), `wg-defer-only-after-inline-triage` (Non-Goals), `wg-use-closes-n-in-pr-body-not-title-to` (here: `part of #7898`, no `Closes`).

### Related issues and PRs

- #7898 (tracker; stays open), #7873 (Rule D + baselines), #7797 (xtrace refusal lint), #7986 / b29131393 (§5 drawdown), #8023 (Sentry curl confinement, concurrent; same D baseline file, non-overlapping hunks), #6551 (a `Failed to start <unit>` PRIORITY-3 systemd row reached Better Stack although no Source admits it — an unresolved observation, NOT relied on here), #7775 (doppler-injection ledger; the `container-restart-monitor.service` ack entry is prose-only).

## Problem Statement / Motivation

Every one of the eight credentialed `curl` sites in these five files reads `~/.curlrc` and honours `ALL_PROXY`/`HTTPS_PROXY` before it honours the literal `api.resend.com` in its own argv (Rule D's header, reproduced against a local listener in #7873). On web-1 the environment these run in is Terraform-written and root-owned, so the practical adversary is narrower than for the plugins/** scripts — but the Resend key can send mail **as `noreply@soleur.ai` to any customer**, which is a brand event at a single message. The two Sentry-bearing scripts additionally build their URL from three doppler-injected variables with no shape check at all, and the bootstrap writes the key into a curl config file where a newline is a directive boundary (measured). The lint already names all of this; the baseline is what lets it stay.

## Proposed Solution

### Common prologue (all five)

Why inline in five files rather than a sourced helper (so the next drawdown does not re-litigate it):
(a) `server.tf` › `local.host_script_files` is an explicit per-file allow-list feeding the Dockerfile
COPY, the cloud-init extraction and the per-resource SSH provisioners — a runtime lib needs three new
delivery paths; (b) Rule A requires the refusal to be the FIRST statement after `set …`, and a
`source lib.sh` above it is itself a violation; (c) the bootstrap runs from a laptop. The two Sentry
blocks are kept identical by a parity row instead (Guard 1 harness rows).

Immediately after the script's `set …` line (Rule A: zero commands may precede it; `readonly X=` counts as a command):

```bash
# (#7797) Refuse to run under shell tracing. UNCONDITIONAL — the credential this file handles is
# bound BELOW this line (sourced from ENV_FILE / injected by the doppler-wrapped unit), so a
# `${VAR:+x}` hatch would test an empty variable, open, and trace the bind itself.
case "$-" in
  *x*)
    printf 'SOLEUR_<UNIT>_HALT reason=xtrace-credential-bound issue=7797\n'
    printf '[<unit>] refusing to run under xtrace: this unit handles a live credential and -x would print it\n' >&2
    exit 78
    ;;
esac
```

`<UNIT>` ∈ `DISK_MONITOR`, `RESOURCE_MONITOR`, `CONTAINER_RESTART_MONITOR`, `CRON_EGRESS_ALARM`,
`RESEND_INBOUND_BOOTSTRAP` — the existing `SOLEUR_<COMPONENT>_<CLASS>` convention
(`SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED`, `SOLEUR_CHARDEV_SWEEP_FAILED`, `SOLEUR_PRIVATE_NIC …`).
Marker on stdout (agent runtimes and journald capture stdout; the constitution's stream rule), human
line on stderr. Exit 78 matches `trigger-cron/scripts/trigger.sh` and the linter's remedy.

In the FOUR host monitors (not the laptop-run bootstrap) the halt arm inlines the three emit lines
with the LITERAL tag (`-t disk-monitor` …) — a function definition and a `LOG_TAG=` assignment are
both commands, so neither may precede the `case` under Rule A; `LOG_TAG` (where not already defined)
and `emit_refusal()` are defined right after it — and its `logger -p user.crit` leg reaches Better Stack through
Vector Source 2 (PRIORITY 0-2, any unit — measured 2026-09-11: `logger -p user.crit` lands as
`PRIORITY=2`). No credential is bound at that point, so the traced `logger` line itself leaks
nothing. Each monitor's pre-existing `WARNING: Resend … POST failed` branch calls
`emit_refusal "SOLEUR_<UNIT>_SEND_FAILED channel=resend http_code=$code"` — property P9; the code is
`%{http_code}`, never a body. In `cron-egress-alarm.sh` the `RESEND_API_KEY unset/suppressed`
branch (cooldown active / `jq` missing / key unset — which `OnFailure=` re-enters every timer tick
for the whole 30-minute cooldown) also calls `emit_refusal "SOLEUR_CRON_EGRESS_ALARM_SEND_FAILED channel=resend reason=<cooldown|jq|unset> unit=$FAILED_UNIT"`,
so the unit-failure signal itself is never journald-only in that window (flow finding). `FAILED_UNIT`
is systemd's `%i` (root-controlled argv, default `unknown-unit`) and is the one non-literal token any
marker carries, so it is validated before the first emit: `[[ "$FAILED_UNIT" =~ ^[A-Za-z0-9@._-]+$ ]] || FAILED_UNIT=invalid-unit-name`
(security-sentinel finding).

Then the TLS-subversion unset. In the three scripts that `set -a; . "$ENV_FILE"; set +a`, the unset
goes IMMEDIATELY AFTER that source (the env file is root 0600 and Terraform-written, but an unset
above a source is an unset the source can undo); in the other two it follows the refusal:

```bash
# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy vars, but neither touches
# the env that subverts TLS itself: SSLKEYLOGFILE writes the session keys and the CA vars substitute
# the trust store. Unset AFTER the env-file source so nothing sourced can re-arm them.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS \
      OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT
```

The second line EXTENDS the §5 / #8023 list (security-sentinel finding): the same actor who can
plant `SSL_CERT_FILE` can plant `OPENSSL_CONF` (OpenSSL 3 loads a `providers` section — an
arbitrary `.so` into the curl process, strictly stronger than a trust-store swap) or `LD_PRELOAD`
(applies to the curl child even though it already applied to bash). `CURL_HOME` is redundant once
`--disable` is first (kept for parity with the precedent). The divergence from the precedent list is
recorded in the precedent-diff table; a follow-up may lift it into the §5 scripts.

In the two Sentry-bearing scripts and the bootstrap, also `export LC_ALL=C` (the `[[:cntrl:]]` and
`[a-f0-9]` classes below are locale-defined; `betterstack-query.sh` pins it for the same reason).
Scope checked: every downstream command in those three files (`date +%s`, `hostname`, `jq`,
`journalctl … --no-pager`, `stat -c %Y`, `column -t`, the existing `doppler secrets set … > /dev/null`)
is locale-neutral for the ASCII text they handle; the email bodies are ASCII.

### Transport flags (all eight credentialed sites)

Every credentialed `curl` becomes `curl --disable --noproxy '*' --proto '=https' -g <existing flags…>`.
Position is load-bearing (`--disable` aborts `.curlrc` parsing only when first). The `resource-monitor.sh`
loopback `curl -s --max-time 2 "$METRICS_URL"` is NOT credentialed and is NOT changed.

### Sentry destination adjudication (`container-restart-monitor.sh`, `cron-egress-alarm.sh`)

Computed once, before the Sentry curl, following the one-hop derivation Rule D's `_adjudicated()` walks
and the `betterstack-query.sh` `_bs_host` idiom:

```bash
# (#7898 §2) The Sentry ingest triple arrives from the doppler-wrapped environment and is interpolated
# into the request URL, so each part is adjudicated before a credentialed byte moves. Host: case-fold
# and strip ONE trailing dot (DNS is case-insensitive and `host.` is a valid absolute FQDN; a `case`
# glob is neither), refuse the userinfo/path/query/fragment/port family first (a glob `*` crosses `/`),
# then allow the ingest apexes from ADR-031's host glossary. The leading dot is load-bearing.
# Residual (ADR-052): `*.ingest.de.sentry.io` admits every Sentry EU tenant's org host, not ours.
# BEGIN sentry-dest-pin (#7898) — byte-identical in container-restart-monitor.sh and cron-egress-alarm.sh
sentry_dest_ok=0; sentry_refuse_reason=""; _si_host=""
if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
  _si_host="${SENTRY_INGEST_DOMAIN%.}"
  _si_host="${_si_host,,}"
  if [[ "$_si_host" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.ingest\.(de\.|us\.)?sentry\.io$ ]]; then
    sentry_dest_ok=1
  else
    sentry_refuse_reason=host-shape
  fi
  if (( sentry_dest_ok )) && [[ ! "$SENTRY_PROJECT_ID" =~ ^[0-9]+$ ]]; then sentry_dest_ok=0; sentry_refuse_reason=project-shape; fi
  if (( sentry_dest_ok )) && [[ ! "$SENTRY_PUBLIC_KEY" =~ ^[a-f0-9]{32}$ ]]; then sentry_dest_ok=0; sentry_refuse_reason=key-shape; fi
fi
# END sentry-dest-pin (#7898)
```

The host arm is a POSITIVE label grammar (security-sentinel finding), not the `betterstack-query.sh`
deny-list: a deny arm of `cntrl @ / ? # :` outsources `%`, `\`, space and bytes ≥ 0x80 to curl's own
hostname check (`evil.example%2F.ingest.de.sentry.io` passes the deny arm and only curl 8.5's
CVE-2022-27780 fix refuses it), while the positive grammar refuses it, the empty label
`.ingest.de.sentry.io`, and every non-DNS byte on its own — measured on all five inputs; the
classifier accepts the `=~ ^[…` form (measured: `OK … 0 baselined (D)` with `https://${_si_host}/`).
All three variables are initialised BEFORE the `if`, so the triple-UNSET path reads nothing unbound
under `set -u` (user-impact finding — an unbound read there would abort the alarm before its Resend
channel). The two `=~` limbs are guarded on `sentry_dest_ok` so the FIRST failing limb names the
reason.

The project-id and key regexes are the repo's existing definition of a valid Sentry triple —
`apps/web-platform/server/inngest/functions/_cron-shared.ts` › `SENTRY_PROJECT_RE = /^\d+$/`,
`SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/` (same malformed → skip-and-report semantics) — adopted
verbatim so the tree has one definition (CTO finding; the live prd key is 32 hex, measured). The host
arm is deliberately TIGHTER than that file's `SENTRY_DOMAIN_RE` (`^[a-z0-9.-]+\.sentry\.io$`): these
two scripts only ever talk to the INGEST cluster, so the apex allowlist is the property.
In `container-restart-monitor.sh` this lives at the top of `sentry_event()` (the key is in a header
there, but the same predicate keeps the two files identical in shape and the `_si_host` derivation is
what Rule D's walk needs); in `cron-egress-alarm.sh` it replaces the bare `-n` test of Channel 1.

Refusal semantics (P6): when the triple is SET but fails adjudication, the script prints
`SOLEUR_<UNIT>_REFUSED channel=sentry reason=<host-shape|project-shape|key-shape>` on stdout, a `WARNING:` line on
stderr, and the same marker off-box through `logger -p user.crit -t <unit>` (Vector Source 2 ships
PRIORITY 0-2 from any unit — see Research Reconciliation; `|| true` because a missing `logger` must
never fail-stop the alarm) — all three via `emit_refusal()`, reason token only — sets `SENTRY_CHANNEL_NOTE="sentry channel refused: destination failed the #7898 pin"`, and
**continues to the Resend channel**, whose email body gets `${SENTRY_CHANNEL_NOTE:-}` appended. When the
triple is UNSET the existing "Sentry env unset — skipping" branch is kept verbatim. The monitor's
`exit 0` contract is untouched — a refused Sentry post never fail-stops the alarm.

**Where the adjudication runs:** lazily, at the top of `sentry_event()` in
`container-restart-monitor.sh` — the exact shape `cron-egress-alarm.sh`'s Channel 1 already has —
so the two blocks are identical (a parity row diffs them) and no new state file appears. A quiet
tick attempts no send, so nothing is refused and P6 does not reach it; a cooldown-suppressed alert
tick calls neither channel (`container-restart-monitor.sh` › the `COOLDOWN_ACTIVE` branch) and is a
quiet tick for refusal purposes; the first UNsuppressed alert tick under a drifted config refuses
loudly (crit row + email note). Considered and cut at plan-review: a startup adjudication + a
once-per-hour "Sentry channel refused" email + stamp file for quiet ticks (the advisor consult's
proposal) — both simplification reviewers and the flow lens found it a new alert class for a state
no property names, with an un-gated crit row (288 rows/day under drift) and stamp/cooldown
interactions of its own; the drift is caught by the next real alert.

**Both Sentry URLs interpolate the FOLDED host** (`https://${_si_host}/api/…`), not the raw
`${SENTRY_INGEST_DOMAIN}` — otherwise the must-PASS uppercase/trailing-dot row sends the unfolded
value and the stub's case-sensitive `sentry_hit()` grep fails it. The classifier accepts
`https://${_si_host}/…` (measured: `OK: 1 scanned file(s) …`; `_si_host` derives from the
adjudicated variable one hop, which `_adjudicated()` walks).

**Markers never carry the env value.** The refusal branch is exactly the case where the value is
NOT a sane hostname — the realistic misconfig is a whole DSN pasted into `SENTRY_INGEST_DOMAIN`,
which the `*@*` arm refuses and which contains the public key. Folding (`%.` + `,,`) sanitizes
nothing (measured: a trailing newline survives it). So a refusal emits a REASON TOKEN only —
`reason=host-shape | project-shape | key-shape` — and never the host, on every
channel (stdout, stderr, `logger`, the email note).

**The note is appended inside `resend_email()`** (`body="${2}${SENTRY_CHANNEL_NOTE:+$'\n\n'$SENTRY_CHANNEL_NOTE}"`),
never at `BODY` build time — in `container-restart-monitor.sh` the alert body is built BEFORE
`sentry_event()` runs, so an append at build time would always see an empty note (silent-failure
finding); the recovery email's literal body is covered by the same function-level append.

**Every early return that skips a send calls `emit_refusal`.** In `container-restart-monitor.sh`:
`sentry_event()`'s `jq … || return 0` → `emit_refusal "… SEND_FAILED channel=sentry reason=jq"`;
`resend_email()`'s unset-key and missing-`jq` returns → `emit_refusal "… SEND_FAILED channel=resend reason=unset|jq"`.
The Sentry curls gain `-w '%{http_code}'` and `emit_refusal "… SEND_FAILED channel=sentry http_code=$code"`
on a non-2xx (a shape-valid but REJECTED key — 401/403 — was previously indistinguishable from
success), mirroring what the Resend branch already does. The Resend curls' `|| HTTP_CODE="000"`
becomes `|| { rc=$?; HTTP_CODE="000"; }` and the marker carries `rc=$rc` (curl's exit code never
contains a credential; the alarm's cron URL keeps its `2>/dev/null` because that URL embeds the
key). The cooldown-arming semantics (`COOLDOWN_FILE` written after both channels regardless of
outcome) are pre-existing and untouched — bounding inbox storms is its purpose, and the failure is
now visible off-box via the crit rows; recorded in `decision-challenges.md`, not changed here.

**One emitter, not four.** Each script defines a short helper so a refusal is written once — named
`emit_refusal()` to match the tree's `emit_fail()`/`emit_drift()` marker writers (it emits and RETURNS;
`die()` is the fail-stop family), and tagged with the script's `LOG_TAG` (`container-restart-monitor.sh`
and `cron-egress-alarm.sh` already define one; `disk-monitor.sh` / `resource-monitor.sh` gain
`readonly LOG_TAG="disk-monitor"` / `"resource-monitor"` — the same derivation
`inngest-bootstrap.sh` documents for the Source 4 tag inventory):

```bash
# Emit a refusal/halt marker on every channel that survives it: stdout (journald, agent runtimes),
# stderr (humans), and the crit row Vector Source 2 ships off-box (#7898). Reason tokens only —
# never an env value, a host, a body or a credential. A missing `logger` must not take the alert
# down with it, but must not be silent either.
emit_refusal() {
  printf '%s\n' "$1"
  printf '[%s] %s\n' "$LOG_TAG" "$1" >&2
  logger -p user.crit -t "$LOG_TAG" "$1" 2>/dev/null || printf '[%s] logger=absent (%s not shipped off-box)\n' "$LOG_TAG" "${1%% *}" >&2
}
```

and every branch calls `emit_refusal "SOLEUR_<UNIT>_REFUSED channel=sentry reason=host-shape"` (or
`…_HALT reason=xtrace-credential-bound issue=7797`, `…_SEND_FAILED channel=resend http_code=$code`).
The bootstrap's helper omits the `logger` call (laptop surface) and writes the marker to BOTH
stdout and stderr, because all eight `resend_api` call sites are `var="$(resend_api …)"` — a
stdout-only marker from inside the function is captured into the variable and never reaches the
terminal (flow finding).

### `resend-inbound-bootstrap.sh`

- After the existing `-z "${RESEND_API_KEY:-}"` check: `[[ "$RESEND_API_KEY" =~ ^re_[A-Za-z0-9_-]+$ ]]`
  or print `SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED reason=key-shape`, an `ERROR:` line naming the
  `--config` directive-injection reason, `exit 2`.
- `resend_api()`: keep the three `local` declarations on ONE line (work-phase measurement INVERTED the
  plan's original "split them" prescription: with `local path="$2"` on its own line the classifier reads
  `path` as a non-env assignment and passes even with the allowlist deleted; on one line it reads `path`
  as never-assigned → env-settable → REQUIRES the pin) and add, before either branch,
  `[[ "$path" =~ ^(/domains|/webhooks)(/[A-Za-z0-9_-]+)?$ ]]` or print
  `SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED reason=path-shape`, `ERROR:`, `exit 2`. Both curls get the
  four flags. The process-substitution `--config` stays exactly as it is (the key never reaches argv).

### Baselines

Delete exactly the five `apps/web-platform/infra/{container-restart-monitor,cron-egress-alarm,disk-monitor,resend-inbound-bootstrap,resource-monitor}.sh`
lines from BOTH `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` and
`scripts/lint-shell-trace-credential-refusal.baseline.txt`, by hand — never `--write-baseline*`,
which rewrite from a full-tree scan and would silently re-baseline anything that drifted in.
`arm-heartbeats.sh` and `cutover-verify.sh` stay.

### Harness rows (written RED first, before any script edit)

- `disk-monitor.test.sh`, `resource-monitor.test.sh`, `container-restart-monitor.test.sh`: extend the
  `curl` stub so that, for any invocation whose argv contains `api.resend.com` or `.sentry.io`, it
  appends `ARGV_ORDER host=<h>` to `$mock_dir/curl_violations` unless `$1 == --disable && $2 == --noproxy
  && $3 == '*' && $4 == --proto && $5 == =https && $6 == -g`, and appends `NOPROXY_COUNT n=<k>` unless
  exactly one `--noproxy` is present; it also increments `$mock_dir/curl_checked`. New rows assert
  `curl_violations` absent AND `curl_checked ≥ 1` for the single-member scripts, `curl_checked == 2` on the alert rows of `container-restart-monitor.test.sh` (two members — a host filter that silently drops `.sentry.io` would otherwise read `1` and pass; under a full mock an invocation count is not a wall-clock quantity, so pinning it is sound). An absolute-path `/usr/bin/curl` bypass is RED in the blocking Rule D arm, whose `CURL_INVOKE` recognises path-qualified curl. The stub's `'*'` comparison is written inside a QUOTED heredoc (or the compare is `"$3" == '*'`) — an unquoted `== *` matches anything and makes the row vacuous. The stub records `curl_args` in the `MOCK_CURL_FAIL` branch too, so the SEND_FAILED row can assert the flags were present on the failing call. The argv inspection runs BEFORE the stub's `MOCK_CURL_FAIL` branch (today that branch exits before `echo "$*" >> curl_args`, so a failed-send row would otherwise record `curl_checked=0`).
- `container-restart-monitor.test.sh`: `setup_mocks_and_run` hardcodes the Sentry fixture today
  (`SENTRY_INGEST_DOMAIN="ingest.example.test"`, `SENTRY_PUBLIC_KEY="pubkey_test"`); it gains
  `MOCK_SENTRY_HOST` / `MOCK_SENTRY_KEY` overrides (default = the POSITIVE fixture
  `o0000000.ingest.de.sentry.io` / `0123456789abcdef0123456789abcdef`, synthetic; curl is stubbed, no
  network), and `sentry_hit()` greps the positive host. The old `ingest.example.test` / `pubkey_test`
  values are KEPT as the NEGATIVE fixtures (the natural refused cases — do not delete them).
  New rows: (a) alert tick with `MOCK_SENTRY_HOST=ingest.example.test` → no Sentry curl, marker
  `SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=host-shape` on stdout, Resend curl
  still fires and its payload contains `sentry channel refused`, exit 0; (b) `O0000000.INGEST.DE.SENTRY.IO.`
  → Sentry curl fires to the FOLDED host (must-PASS non-canonical); (c) `o0000000.ingest.de.sentry.io/?x=`
  → refused with `reason=host-shape`; (d) `MOCK_SENTRY_KEY=pubkey_test` → refused with `reason=key-shape`;
  (e) TRIPLE UNSET (`MOCK_SENTRY_HOST=""` etc.) on an alert tick → no Sentry curl, the pre-existing
  "Sentry env unset" log line, the Resend curl STILL fires, exit 0 (user-impact finding: an unbound
  read on this path under `set -u` would abort the only surviving channel; the same row exists for
  the alarm in `cron-egress-firewall.test.sh`).
- All three exec harnesses stub `logger` on PATH (record argv; exit 0) and assert the crit emission
  on the refusal / failed-send rows: `-p user.crit` present, `-t <LOG_TAG>` present, marker present,
  and NO argv token equal to the fixture key or containing the fixture host (rubric item 6 — the
  emitted line carries a reason token, never an env value). One row per harness removes `logger`
  from PATH entirely and asserts the script still exits per its contract AND stderr carries
  `logger=absent` (the only off-box path must neither take the alert down nor vanish silently).
- `cron-egress-firewall.test.sh`: `assert_grep` rows over `$ALARM` anchored on syntax:
  `^[[:space:]]*curl --disable --noproxy '\*' --proto '=https' -g` (count 2 via a `grep -cE` equality,
  not `-q`), the positive host regex present (`grep -cF 'ingest\\.(de\\.|us\\.)?sentry\\.io$'` = 1, matched as a fixed string), and an
  `assert_not_grep` for any `^[[:space:]]*curl -s` line (a bare, unconfined curl).

## Technical Considerations

### Attack Surface Enumeration (for security fixes)

Credentialed `curl` sites (the linter's `_curl_commands` census on the five files): `disk-monitor.sh`
1 (Resend), `resource-monitor.sh` 1 (Resend; +1 uncredentialed loopback, excluded), `container-restart-monitor.sh`
2 (Sentry store, Resend), `cron-egress-alarm.sh` 2 (Sentry cron check-in, Resend), `resend-inbound-bootstrap.sh`
2 (Resend, `--config` channel). Eight sites, one chokepoint each except the bootstrap (one function, two branches).

| Redirection / leak vector | Closed by | Checked here |
|---|---|---|
| `~/.curlrc` (`CURL_HOME`, `HOME`) | `--disable` first; `CURL_HOME` unset | yes |
| `ALL_PROXY` / `HTTPS_PROXY` / `NO_PROXY` inversion | `--noproxy '*'` (exactly once — a later `--noproxy ''` supersedes) | yes (harness cardinality row) |
| Scheme downgrade / `http://` injection | `--proto '=https'` | yes |
| URL globbing of a substituted value (`[ ] { }`) | `-g` | yes |
| `CURL_CA_BUNDLE` / `SSL_CERT_FILE` / `SSL_CERT_DIR` trust-store swap, `SSLKEYLOGFILE` | `unset` prologue, placed after the `ENV_FILE` source | yes |
| Resolver env (`HOSTALIASES`, `LOCALDOMAIN`, `RES_OPTIONS`) | `unset` prologue | yes |
| Env-settable Sentry host / project / key in the URL | shape + apex allowlist (case-fold, one trailing dot) | yes (2 files) |
| `resend_api` caller-controlled path (`@`, `//`, `..`, `?`) | path allowlist | yes |
| Curl config-directive injection through a newline in the key value | key-shape check (measured vector) | yes |
| `set -x` tracing the `ENV_FILE` source / doppler env | Rule A refusal before the source | yes |
| `/etc/hosts`, the host resolver, `/etc/default/<unit>` (root 0600, Terraform-written), the doppler prd config itself | — | out of scope: these are the trust root; an actor writing them already holds the key |
| Unit-level `Environment=`/`EnvironmentFile=` injecting proxy vars | — | verified absent: no `*PROXY*`/`curlrc` in `server.tf`, `cloud-init.yml`, `soleur-host-bootstrap.sh` or any `.service`; and `--noproxy '*'` would neutralise it anyway |
| The `*.ingest.de.sentry.io` apex admitting any Sentry EU tenant | — | residual, disclosed (ADR-052). Upgrade trigger: an org-host equality pin (`o<orgid>.ingest.de.sentry.io`) becomes available once the org id is a Terraform-derived value rather than a script literal — `local.sentry_dsn_parts.host` in `server.tf` already parses it, so the tighter pin is one templatefile away when wanted. |

### Invocation contexts and refusal semantics (per file)

| File | Runs as | Creds bound | On xtrace | On pin refusal | On curl failure |
|---|---|---|---|---|---|
| `disk-monitor.sh` | `disk-monitor.timer` → oneshot, every 5 min (unit heredoc in `server.tf` + `cloud-init.yml`) | `ENV_FILE` source (line 18) | marker + stderr, exit 78 (unit fails; timer keeps firing) | n/a (literal host) | pre-existing `WARNING: Resend API POST failed (HTTP …)`; exit 0 |
| `resource-monitor.sh` | `resource-monitor.timer`, same shape | `ENV_FILE` source (line 25) | same | n/a | same |
| `container-restart-monitor.sh` | `container-restart-monitor.timer` → doppler-wrapped `ExecStart` (`container-restart-monitor.service:28`) | Sentry triple from doppler env; Resend from `ENV_FILE` (line 61) | same | Sentry post skipped, marker + stderr, note appended to the Resend email; exit 0 | pre-existing: Sentry channel reports a Resend failure (`resend_email()` comment) |
| `cron-egress-alarm.sh` | `cron-egress-alarm@%n.service`, `OnFailure=` of the two firewall units, doppler-wrapped | all from doppler env | same | Sentry check-in skipped, marker + stderr, note in the email; exit 0 | pre-existing `WARNING:` lines |
| `resend-inbound-bootstrap.sh` | laptop shell under `doppler run -p soleur -c prd` | env | marker + stderr, exit 78 | `ERROR:` + marker, exit 2 | `set -e` aborts (pre-existing) |

### `hr-prod-host-config-change-immutable-redeploy`

The four monitor edits reach web-1 through the Terraform-managed `terraform_data` SSH provisioners
the merge-triggered `apply-web-platform-infra.yml` runs behind the CF tunnel bridge — the IaC path
server.tf itself documents for running hosts — and reach future fresh hosts through the image bake
(`local.host_script_files` → `Dockerfile` COPY → cloud-init extraction). No in-place or rescue edit
is prescribed anywhere in this plan.

## Files to Edit

- `apps/web-platform/infra/disk-monitor.sh` — prologue (after `set -euo pipefail`, halt arm inlining the three emit lines), `readonly LOG_TAG="disk-monitor"`, `emit_refusal()` helper, unset (14 names) after the `ENV_FILE` source, four flags on the `send_alert()` curl, `rc` capture and `emit_refusal "SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=$HTTP_CODE rc=$rc"` in the existing non-2xx branch. No new `--arg from` (the `resend-sender-domain.test.ts` suite parses the senders of all four monitors).
- `apps/web-platform/infra/resource-monitor.sh` — same edits (`readonly LOG_TAG="resource-monitor"`); the `sample_active_sessions()` curl untouched.
- `apps/web-platform/infra/container-restart-monitor.sh` — prologue (after `set -uo pipefail` at line 34), `emit_refusal()` helper (uses the existing `LOG_TAG`), unset (14 names) after the `ENV_FILE` source, `export LC_ALL=C`, the `# BEGIN/END sentry-dest-pin (#7898)` block at the top of `sentry_event()` (`emit_refusal` + `SENTRY_CHANNEL_NOTE` + `return 0` when refused; URL uses `${_si_host}`; `-w '%{http_code}'` + `emit_refusal … SEND_FAILED channel=sentry http_code=$code` on non-2xx; the `jq … || return 0` early return calls `emit_refusal … reason=jq`), `resend_email()` appends `${SENTRY_CHANNEL_NOTE:+…}` to the body it receives, its unset-key / missing-`jq` early returns call `emit_refusal … SEND_FAILED channel=resend reason=unset|jq` (and the "(Sentry still posted)" wording becomes conditional on the note being empty), `emit_refusal … SEND_FAILED channel=resend http_code=$http rc=$rc` on non-2xx, four flags on both curls. No new `op:` tag string (the `sentry-container-restart-alert-op-contract.test.ts` suite parses them).
- `apps/web-platform/infra/cron-egress-alarm.sh` — prologue (after `set -uo pipefail` at line 15), `emit_refusal()` helper (existing `LOG_TAG`), unset (14 names), `LC_ALL=C`, `FAILED_UNIT` charset validation, Channel 1 rewritten around the `BEGIN/END sentry-dest-pin` block (`emit_refusal` on refusal; URL uses `${_si_host}`; `-w '%{http_code}'` + `emit_refusal … SEND_FAILED channel=sentry http_code=$code` on non-2xx), the email `--arg text` gains the note, the cooldown log line `(Sentry check-in still posted)` becomes conditional on `${SENTRY_CHANNEL_NOTE:-}` being empty (it is false after a refusal — CTO finding; the cooldown itself is kept, a sustained misconfig must not spam), `emit_refusal … SEND_FAILED channel=resend reason=<cooldown|jq|unset> unit=$FAILED_UNIT` in the `unset/suppressed` branch and `emit_refusal … SEND_FAILED channel=resend http_code=$HTTP_CODE` on the `Resend POST failed` branch, four flags on both curls.
- `apps/web-platform/infra/resend-inbound-bootstrap.sh` — prologue (after `set -euo pipefail` at line 32), `emit_refusal()` (stdout + stderr, no logger), unset, `LC_ALL=C`, key-shape check, `resend_api()` path allowlist + split `local`s + four flags on both branches.
- `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` — delete the five lines (67 → 62; `main − 5`).
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` — delete the five lines (103 → 98; `main − 5`).
- `apps/web-platform/infra/disk-monitor.test.sh` — argv-order + cardinality + `≥ 1` checked-count rows in the stub (inspection before the `MOCK_CURL_FAIL` branch, `'*'` compared quoted) and two new assertions (WARNING and CRITICAL paths); a PATH-stub `logger` that records its argv so the `MOCK_CURL_FAIL=1` row can assert `-p user.crit` + `SOLEUR_DISK_MONITOR_SEND_FAILED` + `rc=` (RED before the edit); one `logger`-absent row.
- `apps/web-platform/infra/resource-monitor.test.sh` — same (three rows), gated on the `api.resend.com` invocation only.
- `apps/web-platform/infra/container-restart-monitor.test.sh` — stub rows (`curl_checked == 2` on alert rows); `MOCK_SENTRY_HOST` / `MOCK_SENTRY_KEY` overrides + positive fixture + `sentry_hit()` needle (which must grep the SENTRY host, not `curl_args` as a whole — the Resend body lands there too); five pin rows (refused apex / non-canonical accepted / smuggled path refused / bad key refused / triple unset still emails) + the email-note assertion + one `logger`-absent row.
- `apps/web-platform/infra/cron-egress-firewall.test.sh` — three static rows over `$ALARM` (count-equality confined-curl grep = 2, the positive host regex present, no-bare-curl), FOUR labelled exec rows (PATH-shim `curl`/`logger`/`jq`; refused host → marker + single Resend curl carrying the note + exit 0; folded uppercase host → two curls; cooldown stamp present → zero curls + `SEND_FAILED reason=cooldown` crit argv; triple unset → one Resend curl + exit 0), and ONE parity row diffing the predicate-only `BEGIN/END sentry-dest-pin` region between `$ALARM` and `container-restart-monitor.sh` with a non-empty guard on both extractions.
- `apps/web-platform/infra/doppler-injection-bound.test.sh` — the `:61` prose citation → content anchor (one string edit; the mutation row's `ENTRY` regex keys on the unit name, not the prose).
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — ONLY if `bash plugins/soleur/test/fixture-relative-assert.test.sh` reports a moved row for one of the edited files; regenerate in the same commit and state which row and why in the commit body.
- `knowledge-base/project/specs/feat-one-shot-7898-resend-five-transport-confinement/decision-challenges.md` — append the merge-side-effect record (the SSH apply re-fires four `terraform_data` resources on web-1: three timers re-enabled, the egress firewall restarted gap-free; the container image rebuilds) for `ship` to render.

- `.github/workflows/infra-validation.yml` — ONE added `run: bash apps/web-platform/infra/resend-inbound-bootstrap.test.sh` step in `deploy-script-tests` (registration only; no trigger/permission change).
- `apps/web-platform/test/infra/vector-pii-scrub.test.sh` — one drift-fixture row asserting `[sources.system_journald]` keeps `include_matches.PRIORITY = ["0", "1", "2"]`, the two-unit `exclude_units`, and membership in `pii_scrub_drop_userdata.inputs` (the Source 2 analog of the Source 4 allowlist fixture — the sink every new crit row depends on; observability-coverage finding).

Not touched: `scripts/lint-shell-trace-credential-refusal.py` (AC asserts an empty diff), `apps/web-platform/scripts/sentry-monitors-audit.sh`, `scripts/sentry-alert-live-fidelity.sh`, `arm-heartbeats.sh`, `cutover-verify.sh`, `vector.toml`, `server.tf`, `cloud-init.yml`, any `.service`, any other workflow.

## Files to Create

- `apps/web-platform/infra/resend-inbound-bootstrap.test.sh` — runs under `env -i PATH=<shims>:$PATH RESEND_API_KEY=re_test_fake_key_123 …` (a fake key by construction; the shim asserts on the `--config` fd contents IN-PROCESS and prints only `PASS`/`FAIL` + counts, so no key — fake or inherited — is ever written to a log or artifact). Rows: (a) key with an embedded newline → exit 2, `reason=key-shape` on stderr, shim never invoked; (b) `resend_api GET '/domains/../webhooks'` and `GET '@evil.example/domains'` (function sourced via `sed -n '/^resend_api()/,/^}/p'`) → exit 2, `reason=path-shape` on stderr; (c) `GET /domains/3f1a2b3c-4d5e-4f60-8a71-b2c3d4e5f607` → shim records argv[1..6] = the four flags and reads its `--config` fd: exactly one `header =` line, zero `url =` lines; (d) `bash -x` with the fake key → exit 78, `SOLEUR_RESEND_INBOUND_BOOTSTRAP_HALT` on stdout, no shim invoked; (e) `grep -cE '(if|\|\||&&)[^\n]*\$\(resend_api' <script>` = 0 (a wrapper around a call site would swallow the in-function `exit 2`). Registered as one `run: bash apps/web-platform/infra/resend-inbound-bootstrap.test.sh` step in `.github/workflows/infra-validation.yml` › `deploy-script-tests` (the `run-registered-suites.sh` derivation picks it up for the required `test` shard; `lint-orphan-test-suites.sh` requires the registration).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (65 issues) matched none of the planned paths (checked each of the five scripts, both baselines, `vector.toml`). Two adjacent open issues noted for the follow-up section, not overlapping: #6551 (a PRIORITY-3 systemd row reached Better Stack unexplained) and #7775 (doppler-injection ledger).

## User-Brand Impact

- **If this lands broken, the user experiences:** a web-1 disk-full / OOM-restart-storm / egress-firewall failure that ops is never emailed about, because a monitor's alert curl now refuses or fails — the user then meets the outage (a 502 from `app.soleur.ai`, a stalled Concierge session) before anyone at Soleur does. That exposure is **pre-existing and unchanged** for the monitors' own self-reporting (their failure lines have always been on-box only — see `## Observability`); what this PR could newly break is the alert send itself. Bounded by: the classifier and three exec harnesses prove every prescribed shape; every adjudication was checked against the live prd values before being written; a refused Sentry post still sends the email; and `exit 0` contracts are preserved.
- **If this leaks, the user's [workflow / trust] is exposed via:** `RESEND_API_KEY` reaching a proxy or a `.curlrc`-redirected host, after which the holder can send mail **as `noreply@soleur.ai`** to that user — a phishing message from the brand's own domain. `SENTRY_PUBLIC_KEY` re-pointed lets an attacker forge error events into our Sentry project (a paging-noise / cover vector), not a user-data exposure.
- **Brand-survival threshold:** `single-user incident` — one forged `noreply@soleur.ai` message to one customer is the incident. `noreply@soleur.ai` is a DKIM- and DMARC-aligned sender (`apps/web-platform/infra/dns.tf` › `cloudflare_record.dkim_resend_send`, `cloudflare_record.dmarc`), so a message sent with a leaked key passes every trust signal the customer's mail client shows; the adversary must already hold env-write on web-1 or the doppler prd config, which narrows probability but not blast radius. (CPO sign-off: granted-with-conditions, 2026-09-11 — conditions folded into this section, AC11 and AC17.)

CPO sign-off is required at plan time (`requires_cpo_signoff: true`); `user-impact-reviewer` is
invoked at review time by `review/SKILL.md`'s conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: "unchanged — the four monitors have no liveness heartbeat today (grep heartbeat-manifest.ts / betterstack*.tf for disk|resource|container-restart|cron-egress: none); their timers re-arm on the merge-triggered SSH apply, whose remote-exec prints each `list-timers <unit>.timer` line into the workflow log"
  cadence: "per merge (apply-web-platform-infra.yml) + every 5 min on-host (timers) + on-failure (cron-egress-alarm@)"
  alert_target: "the workflow run (red job) for delivery; ops@jikigai.com via Resend for the monitors' own signal"
  configured_in: "apps/web-platform/infra/server.tf › terraform_data.{disk_monitor_install,resource_monitor_install,container_restart_monitor_install,cron_egress_firewall}; .github/workflows/apply-web-platform-infra.yml (SSH -target set)"

error_reporting:
  destination: "Sentry project web-platform via the doppler-injected SENTRY_INGEST_DOMAIN/SENTRY_PROJECT_ID/SENTRY_PUBLIC_KEY (store API in container-restart-monitor.sh; cron check-in in cron-egress-alarm.sh) — direct envelope posts adjacent to layer 3, tagged feature=container-restart-monitor (the sentry_issue_alert.container_restart_burst rule pages on it)"
  fail_loud: "stdout marker `SOLEUR_<UNIT>_REFUSED channel=sentry reason=<token>` + stderr WARNING + a PRIORITY-2 `logger` row (Vector Source 2), AND the same text inside the Resend email body (the surviving channel); a Resend HTTP non-2xx keeps the pre-existing `WARNING: Resend … failed (HTTP …)` line and ships `SOLEUR_<UNIT>_SEND_FAILED channel=resend http_code=<code> rc=<curl rc>`; a deliberate skip (cooldown, jq missing, a channel's env unset) ships `SOLEUR_<UNIT>_SEND_SKIPPED channel=<c> reason=<token>` — a separate class so no alert rule on SEND_FAILED pages on configuration. The alarm's skip rows are per OnFailure fire (the resolve timer is 1/min), i.e. up to ~1,400/day for the duration of a sustained resolve failure that is already paging through Sentry (measured at review; ~1.4% of the Better Stack free tier)"

failure_modes:
  - mode: "xtrace refusal fires on a host unit (exit 78)"
    detection: "layer 3 (Vector journald shipper → Better Stack) via Source 2: the halt arm runs `logger -p user.crit -t <unit> 'SOLEUR_<UNIT>_HALT …'` and `[sources.system_journald]` ships PRIORITY 0-2 from any unit (`vector.toml:61-64`) — queryable with `scripts/betterstack-query.sh --grep SOLEUR_<UNIT>_HALT`; plus the unit's own stdout marker and the systemd `status=78` record on-box. (The unit's stdout itself is PRIORITY 6 and not shipped — the `logger` line is the off-box path, not the printf.)"
    alert_route: "Better Stack (no alert rule today — the state is unreachable without root on web-1, so a query-on-suspicion is proportionate)"
  - mode: "Sentry destination refused by the pin (env value drifted or substituted)"
    detection: "the Resend email to ops@ carries `sentry channel refused: destination failed the #7898 pin` as a note in the alert body on the first unsuppressed alert tick (container-restart-monitor.sh; cron-egress-alarm.sh only runs on a unit failure so every refusal rides the alarm email or, inside the Resend cooldown, its own SEND_FAILED crit row) — the monitor's own alert channel, off-box, human-read; AND layer 3 via Source 2: `logger -p user.crit -t <unit> 'SOLEUR_<UNIT>_REFUSED channel=sentry reason=…'`; + stdout marker; the Sentry-side absence is also visible as the `container_restart_burst` rule going quiet during a storm the email reports"
    alert_route: "ops@jikigai.com (Resend), same as the alert itself"
  - mode: "Resend send fails after confinement (e.g. a proxy the host silently depended on — verified: none configured)"
    detection: "container-restart-monitor.sh / cron-egress-alarm.sh: the Sentry event/check-in still posts (channel 1) — Sentry, the `container_restart_burst` issue alert; ALL four: the pre-existing `WARNING: Resend … failed (HTTP …)` branch now also runs `logger -p user.crit -t <unit> 'SOLEUR_<UNIT>_SEND_FAILED channel=resend http_code=<code>'` → layer 3 via Source 2 (previously on-box only for the two Resend-only monitors — this PR closes that)"
    alert_route: "Sentry issue alert (two files); Better Stack query for all four (no alert rule today — the follow-up alert on `SOLEUR_*_SEND_FAILED` is a one-line Better Stack rule; the substring is deterministic, nothing needs observing first, and deliberate skips ride the separate `SOLEUR_*_SEND_SKIPPED` class so the rule cannot page on a cooldown or an unset channel)"
  - mode: "the merge-triggered SSH apply fails to deliver (L3 bridge / L7 key)"
    detection: "`gh run list --workflow apply-web-platform-infra.yml --branch main --limit 1` red; `gh run view <id> --log | grep -E 'list-timers|ASSERT-FAILED|Error'` — layer 6 (workflow-run log), no SSH"
    alert_route: "the workflow's failure notification + postmerge"
  - mode: "bootstrap refuses a legitimate key or path (shape drift)"
    detection: "synchronous stdout on the invoking laptop shell (layer 7 shape, not a hosted path): `SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED reason=key-shape|path-shape` + ERROR line, exit 2; the live key shape was measured before the regex was written"
    alert_route: "the person running it"

logs:
  where: "the systemd journal on web-1 per unit (`disk-monitor.service`, `resource-monitor.service`, `container-restart-monitor.service`, `cron-egress-alarm@<unit>.service`), persistent per terraform_data.journald_persistent; the per-tick narration is NOT shipped (not in Vector Source 4 — see Non-Goals); the refusal / failed-send markers ARE shipped (Vector Source 2, PRIORITY 2 via `logger -p user.crit`) to Better Stack; bootstrap: the invoking shell"
  retention: "journald persistent retention on web-1 (journald-soleur.conf); Better Stack retention for the crit rows"

discoverability_test:
  command: "python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/infra/disk-monitor.sh apps/web-platform/infra/resource-monitor.sh apps/web-platform/infra/container-restart-monitor.sh apps/web-platform/infra/cron-egress-alarm.sh apps/web-platform/infra/resend-inbound-bootstrap.sh && grep -c 'logger -p user.crit -t' apps/web-platform/infra/disk-monitor.sh apps/web-platform/infra/resource-monitor.sh apps/web-platform/infra/container-restart-monitor.sh apps/web-platform/infra/cron-egress-alarm.sh"
  expected_output: "OK: 5 scanned file(s), 0 baselined (A/B/C), 0 baselined (D) — then the four monitors each report 2 (the halt arm + emit_refusal, the sink pins that AC17(a) asserts on vector.toml)"
```

Layer citations use the list in `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`
(layers 1-7). The honest statement of this plan is: every new refusal branch, and every pre-existing
failed-send branch in the four monitors, reaches Better Stack through Vector Source 2 (layer 3) via a
`logger -p user.crit` line, and additionally rides the monitor's surviving alert channel (Resend email
/ Sentry) wherever one exists. The per-tick happy-path narration stays on-box (Non-Goals). Rubric item
6 (connecting an emitter to a sink is a security act) was applied to the new lines: each carries a
marker, a reason token, an HTTP code or a FOLDED host — never a credential, a raw env value or a body.

## Guard Contract

### Guard 1 — Sentry ingest destination pin (runtime, two scripts)

**Property.** No Sentry-bound credentialed `curl` in `container-restart-monitor.sh` or `cron-egress-alarm.sh` executes unless `SENTRY_INGEST_DOMAIN` — case-folded, one trailing dot stripped, and free of `@ / ? # :` and control characters — ends in `.ingest.de.sentry.io`, `.ingest.us.sentry.io` or `.ingest.sentry.io`, `SENTRY_PROJECT_ID` is all digits, and `SENTRY_PUBLIC_KEY` is exactly 32 lowercase hex (the `_cron-shared.ts` definition).

**Assembly.** Each script has exactly ONE Sentry curl (the linter's `_curl_commands` census: `container-restart-monitor.sh:79`, `cron-egress-alarm.sh:27` on the unedited files); both flow through the `sentry_dest_ok` predicate computed immediately above them — in `sentry_event()` for the monitor, in the Channel 1 block for the alarm. There is no second Sentry call site in either file (grep `sentry.io\|SENTRY_INGEST_DOMAIN` returns those two plus the `-z` tests). The Resend curls are NOT members: their host is a literal.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Harness sets `MOCK_SENTRY_HOST=ingest.example.test` (the kept negative fixture; all else valid) on an ALERT tick | RED unless the stub records NO `example.test` curl AND stdout carries `SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=host-shape` AND the Resend payload contains `sentry channel refused` AND no `logger` argv token contains `example.test` |
| 2 | `MOCK_SENTRY_HOST=o0000000.ingest.de.sentry.io/?x=` (path/query smuggling), and `evil.example%2F.ingest.de.sentry.io` (percent-encoded separator a deny-list would pass) | RED unless refused with `reason=host-shape` |
| 3 | `MOCK_SENTRY_KEY=pubkey_test` (not 32 hex) with a valid host; and, in the alarm exec row, `SENTRY_PROJECT_ID=4321/../evil` | RED unless refused with `reason=key-shape` / `reason=project-shape` |
| 4 | Guard's own dispatch: delete the `sentry_dest_ok=1` arm (or the whole `case`) so the predicate is never true | RED: the must-PASS rows (H2/H3) fail because the Sentry curl never fires — a guard that refuses everything is caught by the must-PASS, not by the RED rows |
| 5 | Second member after a compliant first: add a second Sentry curl below the guarded one that skips the predicate | RED in the Rule D linter ONLY if the member interpolates the raw `${SENTRY_INGEST_DOMAIN}` in a BARE (uncaptured) curl. Measured at review: a member interpolating the derived `${_si_host}` is invisible to the classifier (it does not follow a derivation from a curl operand back to its env-settable source), and ANY `var="$(curl …)"` site is masked by `_mask_cmdsubs()` — so the shipped Sentry curls (captured for `-w '%{http_code}'`) are outside the classifier's destination limb. The exec rows (refused host → no Sentry curl; `checked == 2`) and the parity row are the guard for this member class; the classifier gap is recorded in the PR body as an upgrade trigger. |
| 6 | Reorder: move the predicate BELOW the curl | RED: row 1 (the curl fires before the refusal) |

**Harness rows:** (H1) delete the refused-host assertion from `container-restart-monitor.test.sh` → the suite's results line drops below the post-edit count the AC pins; (H2) must-PASS non-canonical: `O0000000.INGEST.DE.SENTRY.IO.` (uppercase + trailing dot) → the Sentry curl fires and the stub records the folded request; (H3) must-PASS canonical live shape `o0000000.ingest.de.sentry.io` → fires. For `cron-egress-alarm.sh`, rows 1-3 run as committed exec rows in `cron-egress-firewall.test.sh` (already CI-registered, so no orphan-suite problem): PATH-shim `curl` + `logger` + `jq`, `SENTRY_INGEST_DOMAIN=ingest.example.test`, a fake `RESEND_API_KEY` → stdout carries `SOLEUR_CRON_EGRESS_ALARM_REFUSED channel=sentry reason=host-shape`, the shim recorded exactly one curl (Resend) whose `-d` payload contains `sentry channel refused`, exit 0; a second invocation with `O0000000.INGEST.DE.SENTRY.IO.` records two curls, the first to the folded host; a third with the cooldown stamp present records zero curls and a `logger` argv carrying `SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED channel=resend reason=cooldown`; a fourth with the triple UNSET records exactly one (Resend) curl and exit 0 — LABELLED rows, not one bundled verdict (the review round added project-shape / key-shape, Resend 500, Sentry 500, curl exit 7 and hostile-`%n` rows). Row 5 is NOT the linter's for the shipped shape (see the mutation table: the classifier is blind to the derived host and to captured curls); the exec rows and parity row carry it. A parity row in the same suite diffs the `# BEGIN sentry-dest-pin (#7898)` … `# END sentry-dest-pin (#7898)` region between the two scripts (the shape `cron-egress-firewall.test.sh` › the `SENTRY_SLUG` resolver-vs-alarm row already uses). The markers bracket ONLY the predicate (initialisation, the `_si_host` derivation, the three `=~` limbs) — never the `emit_refusal`/`return` that differ between a function body and top-level flow — and the row FAILS if either extraction is empty (a missing marker must not diff two empty strings green); the mutation set includes "delete one END marker → RED".

### Guard 2 — argv-position transport confinement (three exec harnesses)

**Property.** Every `curl` the three monitor scripts execute against `api.resend.com` or a `.sentry.io` host receives `--disable --noproxy * --proto =https -g` as argv[1..6] and exactly one `--noproxy`.

**Assembly.** All `curl` executions resolve through `PATH` to the harness stub (`$mock_dir/curl`), which is the chokepoint; the stub inspects every invocation carrying one of the two vendor hosts (host-filtered, so `resource-monitor.sh`'s loopback metrics curl is excluded by construction, not by name). Members: `disk-monitor.sh` 1, `resource-monitor.sh` 1, `container-restart-monitor.sh` 2. The stub also counts inspected calls into `curl_checked`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `--disable` from `send_alert()` | RED (`ARGV_ORDER`) |
| 2 | Move `--disable` after `-s` (present, wrong position) | RED (position is the property) |
| 3 | Append a second `--noproxy ''` after the four flags | RED (`NOPROXY_COUNT n=2`) |
| 4 | Guard's own dispatch: change the stub's host filter so it matches nothing | RED: the `curl_checked ≥ 1` assertion (vacuity floor) |
| 5 | Second member: add a second Resend curl without the flags in `container-restart-monitor.sh` | RED (the stub inspects every matching invocation, not the first) |
| 6 | (P9, not argv) delete the `emit_refusal … SEND_FAILED` call from the failed-send branch | RED (the `MOCK_CURL_FAIL=1` row asserts the stubbed `logger` argv) |

**Harness rows:** (H1) delete the new assertion block → results line count drops (AC pins it); (H2) must-PASS: `--disable --noproxy '*' --proto '=https' -g -sS -o /dev/null -w …` with the trailing flags in a different order than disk-monitor's → accepted (only the prefix and cardinality are pinned).

### Guard 3 — `resend_api` path allowlist and key shape (bootstrap)

**Property.** The bootstrap never sends its key unless `RESEND_API_KEY` matches `^re_[A-Za-z0-9_-]+$` (no directive boundary can be injected into the curl config file) and `$path` matches `^(/domains|/webhooks)(/[A-Za-z0-9_-]+)?$` (no authority, traversal or query smuggling into the literal `RESEND_API`).

**Assembly.** `resend_api()` is the only function that invokes `curl` (two branches, one predicate above both); the key check runs once, before the first call. All eight call sites pass a literal prefix plus an id.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Key value `re_x` + newline + `url = "https://127.0.0.1:9/exfil"` (PATH-shimmed curl records argv + config file contents) | RED unless exit 2 + `reason=key-shape` and no curl execution |
| 2 | `resend_api GET '/domains/../webhooks'` | RED unless exit 2 + `reason=path-shape` on STDERR (the stdout copy is swallowed by the `$( … )` capture at every call site) |
| 3 | `resend_api GET '@evil.example/domains'` | RED unless refused |
| 4 | Delete either `=~` line (path or key) — the guard's own dispatch | RED in the Rule D linter: the corresponding `sends to $path` / `sends to $RESEND_API_KEY … never compared` finding returns (measured: the unedited file reports exactly those two) |

**Harness rows:** rows 1-3 are committed rows in the new `resend-inbound-bootstrap.test.sh` (see Files to Create; fake key by `env -i`, fd asserted in-process); the Rule D linter is a second oracle for row 4 (H1: run it on the unedited file and confirm exactly those two findings appear — the instrument is checked against a known case before its verdict is trusted); (H2) delete the harness's key-shape row → results count drops; must-PASS non-canonical: `resend_api GET /domains/3f1a2b3c-4d5e-4f60-8a71-b2c3d4e5f607` (a UUID id) and `PATCH /domains/<id>` with a body → accepted.

## Acceptance Criteria

### Pre-merge (PR)

1. `python3 scripts/lint-shell-trace-credential-refusal.py apps/web-platform/infra/disk-monitor.sh apps/web-platform/infra/resource-monitor.sh apps/web-platform/infra/container-restart-monitor.sh apps/web-platform/infra/cron-egress-alarm.sh apps/web-platform/infra/resend-inbound-bootstrap.sh` prints exactly `OK: 5 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)` (RED before the edits: 22 violations).
2. `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide, after `git fetch origin main`) exits 0 and prints `OK: N scanned file(s), <A> baselined (A/B/C), <D> baselined (D)` where `<A>`/`<D>` are the SAME summary line printed on `origin/main` minus 5 each. Two different quantities are in play and both move by exactly five: the summary line counts files that FIRE and are suppressed (`main()` › `len(offenders)`, today `100 baselined (A/B/C), 66 baselined (D)` — one A/B/C-baselined file and one D-baselined file no longer fire), so the expected summary is `95 … 61` against today's main (`93 … 59` if #8023 merges first); the baseline FILES lose five lines each (67 → 62, 103 → 98), asserted by AC4. Derive both from `origin/main` at verification time; never from this paragraph.
3. `git diff --stat origin/main -- scripts/lint-shell-trace-credential-refusal.py scripts/lint-shell-trace-credential-refusal.test.sh scripts/fixtures/shell-trace-refusal` is empty (classifier untouched).
4. Both baselines lose exactly the five lines and nothing else: `git diff origin/main -- <baseline> | grep -c '^-apps/web-platform/infra/'` = 5 and `… | grep -c '^+[^+]'` = 0 for each (measured shape: a simulated single deletion yields `1` / `0`); `grep -cE 'arm-heartbeats|cutover-verify' scripts/lint-shell-trace-credential-refusal-d.baseline.txt` = 2 (the two deliberately-baselined siblings stay).
5. `bash -n` on all five exits 0; `bash scripts/lint-shell-trace-credential-refusal.test.sh` results line unchanged from main.
6. `bash apps/web-platform/infra/disk-monitor.test.sh`, `resource-monitor.test.sh`, `container-restart-monitor.test.sh`, `cron-egress-firewall.test.sh` each end `N/N passed, 0 failed` with N = (main's count: 11, 11, 18, and the firewall suite's) + (3, 3, 7, 8) respectively — the delta is the load-bearing claim; the NEW `bash apps/web-platform/infra/resend-inbound-bootstrap.test.sh` ends `5/5 passed, 0 failed`; `bash scripts/lint-orphan-test-suites.sh` green (the new suite is registered); `bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` green with its new Source 2 row; and `cd apps/web-platform && ./node_modules/.bin/vitest run resend-sender-domain sentry-container-restart-alert-op-contract` green (the two suites that parse these scripts' source).
7. `grep -nE '^[[:space:]]*([A-Za-z_]+=\"?\$\()?curl ' <each of the five> | grep -vE "curl --disable --noproxy '\*' --proto '=https' -g"` returns ONLY `resource-monitor.sh`'s loopback metrics line (`body=$(curl -s --max-time 2 "$METRICS_URL" …`) — the one curl that must NOT be confined (measured: the command as written returns exactly that line on a confined probe, and all nine curl lines on the unedited tree).
8. `PATH=<dir with a no-op logger>:$PATH bash -x apps/web-platform/infra/disk-monitor.sh` with `ENV_FILE=<fixture containing RESEND_API_KEY=re_test_fake_key_123>` exits 78, prints `SOLEUR_DISK_MONITOR_HALT reason=xtrace-credential-bound` on stdout, and the trace contains no `RESEND_API_KEY=` line (the source never ran) — the runtime property Rule A's text check stands in for.
9. `bash plugins/soleur/test/fixture-relative-assert.test.sh` green; if the baseline had to be regenerated, the commit body names the moved row and why.
10. `grep -n 'container-restart-monitor.sh:61' apps/web-platform/infra/doppler-injection-bound.test.sh` returns nothing (citation moved to a content anchor); that suite still green.
11. The PR body contains `part of #7898` and does NOT contain `Closes #7898`; its follow-up section carries: (a) the in-place Non-Goal on Vector Source 4 (why it is not filed: the refusal/failed-send markers ship via Source 2); (b) the §1 reasoning correction (image-bake, not triggers_replace, is the blocker); (d) the measured "no delivery path runs these scripts under `-x`" grep and its empty result; (e) the Better Stack `SOLEUR_*_SEND_FAILED` alert-rule follow-up (filed by `ship`, with the user-visible consequence sentence and the measured size); (c) the open question for the person who owns #7898, phrased for a non-technical reader: "Do we close #7898 when the *named* problems (sections 1-7) are fixed, or only when *every* script the scanner still flags (62 after this PR, 58 of them never individually looked at) is fixed? Choosing 'named' means the rest becomes a separate cleanup ticket; choosing 'all' means #7898 stays open for several more months." — surfaced with a recommended default (close at 1-7; batch the remainder as `deferred-scope-out` for `drain-labeled-backlog`), not decided.

Process steps (mutation evidence in `session-state.md` — Guard 2 row 2 and Guard 1 row 4 mandatory; the `decision-challenges.md` merge-side-effect record; rebase before the baseline edit and before ready; the untouched-file list) live in tasks.md, not here — an AC is a post-condition on the merged tree, not a step.

### Post-merge (verified by OUTCOME, `postmerge`)

12. Required checks on the merge commit all green: `gh api repos/jikig-ai/soleur/commits/<sha>/check-runs --paginate --jq '.check_runs[] | "\(.name)\t\(.conclusion)"'` filtered to the names in `scripts/required-checks.txt` shows only `success` — the required set, not this PR's own checks (the §5 drawdown merged green while a required check was red repo-wide).
13. On `main`: `python3 scripts/lint-shell-trace-credential-refusal.py` exits 0 and its summary line reads the pre-merge `origin/main` summary minus 5 on both counts (AC2's two-quantity note applies).
14. `gh run list --workflow apply-web-platform-infra.yml --branch main --limit 1` → `success`; `gh run view <id> --log | grep -E 'list-timers (disk|resource|container-restart)-monitor\.timer|host-egress-ok|ASSERT-FAILED'` shows the three `list-timers` lines AND `host-egress-ok` (the alarm's provisioner ran its post-apply assertion — a skipped provisioner would otherwise satisfy an absence-only grep) and zero `ASSERT-FAILED`.
15. The MERGED pin accepts the live prd triple (user-impact finding — plan-time measurement validated the PRESCRIBED regex; lazy adjudication means the first real evaluation could be weeks away): on a laptop, against the MERGED bytes (never the checkout's), with the locale the host pins: `git fetch origin main && doppler run -p soleur -c prd -- bash -c 'export LC_ALL=C; eval "$(git show origin/main:apps/web-platform/infra/cron-egress-alarm.sh | sed -n "/# BEGIN sentry-dest-pin/,/# END sentry-dest-pin/p")"; echo "sentry_dest_ok=$sentry_dest_ok reason=$sentry_refuse_reason"'` prints `sentry_dest_ok=1 reason=` (values never printed; no SSH; the region is byte-identical in both files by the parity row). Run in the same postmerge session, not as a follow-up.
16. `gh run list --workflow web-platform-release.yml --branch main --limit 1` → `success`, and `curl -sS --max-time 10 https://app.soleur.ai/health` returns 200 (deploy healthy).
17. The off-box sink for the new markers is asserted deterministically, not by waiting for an ambient row (`cq-ac-must-not-depend-on-concurrent-sessions`): (a) `awk '/^\[sources.system_journald\]/,/^$/' apps/web-platform/infra/vector.toml | grep -c 'include_matches.PRIORITY = \["0", "1", "2"\]'` = 1 and `grep -c 'inputs = \[.*"system_journald".*\]' apps/web-platform/infra/vector.toml` ≥ 1 (the source admits PRIORITY 2 and feeds the sink chain — unchanged by this PR, asserted so a later `vector.toml` edit that narrows it is visible); (b) `logger -p user.crit` lands as PRIORITY 2 — measured on 2026-09-11 (`journalctl -o json` shows `PRIORITY=2`) and pinned by the harness `logger` stub asserting the `-p user.crit` argv on every refusal / failed-send row; (c) `grep -c 'logger -p user.crit -t' <each of the four monitors>` = 2 — the inlined halt arm (which uses the LITERAL tag, because `LOG_TAG=` is itself a command Rule A forbids above the `case`) + `emit_refusal()` (which uses `"$LOG_TAG"`). Any live Better Stack read is informational only: `scripts/betterstack-query.sh --grep` compiles to `raw LIKE '%X%'` over double-encoded JSON, so a `PRIORITY=2` grep can never match (flow finding) — if attempted, use `--raw-only` and `jq -r '.raw|fromjson|select(.PRIORITY=="2" and ._SYSTEMD_UNIT!="inngest-server.service")'`, and record the result in the PR body. The #6551 caveat (shipper over-ships in one observed case) is noted, never relied on. Attribution note: Source 2 filters by `exclude_units` (inngest-server, vector) and PRIORITY only, so which unit journald attributes the `/dev/log` datagram to cannot exclude it; the `pii_scrub_string` transform between source and sink strips control characters and rewrites `@`-shaped substrings — irrelevant now that markers carry reason tokens only.

## Test Scenarios

- T1 (RED→GREEN, primary): the per-file linter command in AC1 — 22 findings before, `OK` after.
- T2 (RED first): the three harnesses' new argv rows fail on the unedited scripts (`ARGV_ORDER` violations), pass after.
- T3: `container-restart-monitor.test.sh` pin rows (refused / must-PASS folded / smuggled path) + the email-note assertion.
- T4: `cron-egress-firewall.test.sh` static rows (count-equality confined-curl grep = 2; case arm present; no bare `curl -s` line in `$ALARM`).
- T5: the committed `cron-egress-alarm.sh` exec row in `cron-egress-firewall.test.sh` (Guard 1 harness rows) plus the `BEGIN/END sentry-dest-pin` parity row; and `cd apps/web-platform && ./node_modules/.bin/vitest run resend-sender-domain sentry-container-restart-alert-op-contract` green.
- T6: repo-wide linter summary line (AC2) and `bash scripts/lint-shell-trace-credential-refusal.test.sh` unchanged.
- T7: `bash plugins/soleur/test/fixture-relative-assert.test.sh` row-by-row equality.
- T8: xtrace refusal (AC8) on `disk-monitor.sh`, with `logger` PATH-stubbed so the developer journal is not written (a committed row in `resend-inbound-bootstrap.test.sh` covers the bootstrap's halt); and on `resend-inbound-bootstrap.sh` with a fake key: exit 78, no `doppler`/`curl` executed (PATH shim records nothing).
- T9: bootstrap Guard 3 rows 1-3 as committed rows in `resend-inbound-bootstrap.test.sh` (`env -i`, fake key, fd asserted in-process) — a PATH shim: the shim receives `--config /dev/fd/NN` and `cat`s it (measured: a function receiving `<(printf …)` can read the fd path), asserting exactly one `header =` line and zero `url =` lines when the key check passes, and that the shim is never invoked when it refuses. Whole-string `=~` semantics measured: `re_x` + newline + `url = …` and `re_x` + trailing newline are both refused by `^re_[A-Za-z0-9_-]+$` (measured with the `_`-only form; `-` does not change newline handling); `re_ok_123` accepted.
- T11: the harnesses run from the repo root (a non-empty cwd) so an UNQUOTED `--noproxy *` in a script would glob-expand before reaching the stub and fail the argv[3] == `*` check — the quoting is part of what the row pins.
- T10: `bash -n` × 5; `shellcheck` if installed (advisory).

## Dependencies & Risks

- **#8023 merges first** → the D baseline count moves 67 → 65 before this PR; hunks do not overlap (lines 41/71 vs 15-26), so the rebase is clean; ACs are written as `main − 5`. Rebase before the baseline edit and before ready.
- **The merge re-fires four `terraform_data` provisioners on web-1** (three timer re-enables + a gap-free `cron-egress-firewall.service` restart via `cron-egress-postapply-assert.sh`) AND rebuilds/redeploys the container image — a prod container stop → start (`ci-deploy.sh` › the cron-drain block, `docker stop --time=12`) that cuts in-flight Concierge streams, identical to every `apps/web-platform/**` merge and stated here so it is not implied (user-impact finding). Both are the established merge paths; both are verified post-merge by workflow outcome (AC14, AC16). If the SSH apply fails: L3 first (`cf-tunnel-ssh-bridge` step, `var.admin_ips`), then L7 (key), per `hr-ssh-diagnosis-verify-firewall`; the workflow log is the probe, never SSH.
- **A pin that refuses the live value** would silence the Sentry channel of two monitors while the email keeps flowing — mitigated by measuring the live prd values before writing the regexes (all four pass) and by the email carrying the refusal note.
- **`--noproxy '*'` breaking a proxy the host depended on** — verified absent (no proxy env in any unit, `server.tf`, `cloud-init.yml` or the bootstrap script); and the ask itself mandates the flag.
- **`fixture-relative-assert` row drift** — the P1b families do not count any prescribed construct (agent-verified), but the suite is run and the baseline regenerated only with a named reason.
- **The uncredentialed loopback curl in `resource-monitor.sh`** must NOT receive `--proto '=https'` (it is `http://127.0.0.1:3000`); AC7 pins that it is the one unconfined line.
- **`set -u` + the new `${SENTRY_CHANNEL_NOTE:-}`** — every read uses the `:-` form.
- **The unconditional xtrace refusal would fire under any `bash -x` ExecStart or provisioner debug invocation** and, mid-apply, could leave `terraform_data.cron_egress_firewall` half-replaced. Measured 2026-09-11: `grep -nE 'bash -x|sh -x|set -x|xtrace|SHELLOPTS|BASH_ENV'` over `container-restart-monitor.service`, `cron-egress-alarm@.service`, `cloud-init.yml`, `server.tf`, `cron-egress-postapply-assert.sh`, `cron-egress-firewall.service`, `cron-egress-resolve.service` returns nothing — no delivery path traces these scripts. The PR body states this grep and its result (AC11(d)).
- **`local.host_scripts_content_hash` moves on merge** (`server.tf` folds the four monitors into it and passes it to `templatefile(cloud-init.yml)`, which compares it to the baked image at fresh boot and `exit 1`s on mismatch). Ignored on live hosts (`ignore_changes=[user_data]`), fixed-width so no budget change — but a FRESH web host created between the infra apply finishing and the release pushing the new image boots against an old image and aborts. Pre-existing for any `host_script_files` edit; recorded in `decision-challenges.md`: do not birth a web host until AC16's release is green.

## Hypotheses — Network-Outage Deep-Dive (deepen-plan Phase 4.5, resource-shape trigger)

The plan body names no outage, but the merge drives `terraform apply` on four `terraform_data`
resources whose definitions carry `provisioner "file"` + `provisioner "remote-exec"` + a
`connection { type = "ssh" }` block, so SSH is a hard apply-time dependency. The apply runs from
CI, never from a laptop, so the layers are verified against CI's path, L3 → L7:

| Layer | Question | Status | Artifact |
|---|---|---|---|
| L3 firewall allow-list | Is the runner's egress in `var.admin_ips`? | **Not applicable by design** — the runner IP is NOT allow-listed; the job reaches web-1 through the CF Tunnel SSH bridge (`.github/actions/cf-tunnel-ssh-bridge`), gated by the CI-SSH service token synced to Doppler in the preceding step. | `apply-web-platform-infra.yml:20-27` (header), steps `Sync CF Access CI-SSH service token to Doppler` → `Check CI-SSH token presence (gates the SSH apply)` → `CF Tunnel SSH bridge (gated)` |
| L3 DNS / routing | Does the bridge resolve and route today? | **Verified** — the latest `push`-triggered run on `main` (id 34532702614, 2026-09-10T21:32Z) completed `CF Tunnel SSH bridge (gated)` and `Terraform apply (SSH-provisioned resources, over the bridge)` with `success`. | `gh run view 34532702614 --json jobs` (job `apply`, both steps `success`); two earlier runs the same day also `success` |
| L7 TLS / proxy | Cloudflare Access in front of the tunnel serving the expected host? | **Verified transitively** by the same green run — the bridge step fails closed on an Access/TLS mismatch. | same run |
| L7 application (sshd / provisioner) | Do the provisioners execute? | **Verified** — same run applied the SSH-provisioned set; this PR adds no new provisioner, only changes the hashed file contents. | same run; `server.tf` › the four `terraform_data` blocks unchanged by this PR |

If the merge-triggered SSH apply fails: read the workflow log (layer 6), check the bridge step's
outcome BEFORE any provisioner/sshd hypothesis (`hr-ssh-diagnosis-verify-firewall`), then the
`Check CI-SSH token presence` gate (L7 credential — `2026-05-20-l3-network-fix-vs-l7-credential-fix-on-ssh-provisioner-chain.md`).
No SSH from a laptop is prescribed at any point.

## Precedent diff (deepen-plan Phase 4.4)

| Pattern | Precedent (on `origin/main`) | This plan | Divergence, and why |
|---|---|---|---|
| Host adjudication | `scripts/betterstack-query.sh` › deny-list shape arm `*[[:cntrl:]]*\|*@*\|*/*\|*\?*\|*\#*\|*:*:*\|""` → `_bs_auth`/`_bs_host` strips (`%%/*`, `%%\?*`, `%%#*`, `##*@`, `%%:*`, `%.`, `,,`) → `case … in *.betterstackdata.com)` → refuse `exit 2` | `%.` + `,,` → ONE positive label-grammar regex `^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.…)*\.ingest\.(de\.\|us\.)?sentry\.io$` → refuse by skip, never `exit` | (a) positive grammar instead of a deny arm: the deny arm leaves `%`, `\`, space and bytes ≥ 0x80 to curl's own hostname check; the grammar refuses them and the empty label itself (measured on five inputs); (b) the precedent's authority strips are unnecessary because the grammar admits no `@ / ? # :`; (c) refusal semantics differ by design — the query script IS the credentialed call, the monitors have a second channel to fall through to. The classifier accepts the `=~ ^[` form (measured). |
| Triple-shape regexes | `apps/web-platform/server/inngest/functions/_cron-shared.ts` › `SENTRY_DOMAIN_RE /^[a-z0-9.-]+\.sentry\.io$/i`, `SENTRY_PROJECT_RE /^\d+$/`, `SENTRY_PUBLIC_KEY_RE /^[a-f0-9]{32}$/` | project + key identical; host TIGHTER (ingest apex only) | the TS helper serves API + ingest callers; these two scripts only ever post to ingest. |
| xtrace prologue | `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` › unconditional `case "$-" in *x*)` printing a module-shaped marker on stdout + a human line, `exit 78` | identical shape; marker `SOLEUR_<UNIT>_HALT reason=xtrace-credential-bound issue=7797`; host monitors add the `logger -p user.crit` leg | the plugin script is layer 7 (stdout is the sink); the monitors are layer 3 (journald → Source 2 is the sink). |
| TLS-env unset | `scripts/betterstack-query.sh`, `zot-inventory.sh`, the fifteen §5 scripts: `unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS` immediately after the prologue | the same eight PLUS `OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT`, placed AFTER the `ENV_FILE` source in the three scripts that source one | (a) an unset above a `source` is an unset the source can undo; the precedents source nothing; (b) the six extra names close the OpenSSL-3 config/provider and dynamic-loader vectors the precedent list leaves to the same actor — a superset, not a contradiction; lifting them into the §5 scripts is a one-line follow-up recorded in Non-Goals. |
| Transport flags | §5 scripts: `curl --disable --noproxy '*' …`; PR #8023 (unmerged): `curl --disable --noproxy '*' --proto '=https' -g …` | the #8023 four-flag form | HTTPS-only per the ask; `-g` because two URLs interpolate substituted values. |
| Payload hoisting | `plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh` › `SA_PAYLOAD=…` hoisted so the invocation is single-shaped for the classifier | `resend_api()`: the `local` stays on ONE line (measured: splitting it disarms the classifier's path-pin requirement — the reverse of the plan's first reading) | the classifier's visibility of a positional-parameter `local` depends on line shape; recorded as a classifier gap in the PR body. |

No novel pattern: every block has a sibling on `main`.

## Non-Goals (recorded, not work)

- **Vector Source 4 enrollment of the four monitor units** — documented in place, NOT filed. The user-visible consequence that would have justified an issue ("a refused/failed alert on web-1 is invisible off-box") is closed in this PR by the `logger -p user.crit` line in every refusal/failed-send branch, which Vector Source 2 already ships. What Source 4 enrollment would add is the per-tick happy-path narration (`resource-monitor.sh` and `container-restart-monitor.sh` each print one line per 5-min tick ≈ 288 rows/day/host) — a quota decision with no user-visible consequence, and its measured size (`SyslogIdentifier=` on four units across three delivery paths: `server.tf` heredocs + `cloud-init.yml` parity guarded by `web-host-provisioner-parity-mutation.test.sh` and the user_data byte budget, two shipped `.service` files; four tags in `vector.toml` + its drift fixture `test/infra/vector-pii-scrub.test.sh`; a per-line emitter sweep per rubric item 6) is why it is not a line in this PR's tail. Triple test fails on "user-visible consequence" → no issue (`wg-when-deferring-a-capability-create-a`). Upgrade trigger: the first time a per-tick metric line is needed off-box.
- §1 sites 2 and 3 (`soleur-host-bootstrap.sh`, `web-private-nic-guard.sh`) — out of scope; the correction that the real blocker is the image bake, not `triggers_replace`, is surfaced in the PR body for the tracker author.
- §3 YAML scope gap, §4 `CURL_BIN` seam, §6 Better Stack apex residual, §7 `BETTERSTACK_LOGS_TOKEN` asymmetry — recorded decisions with upgrade triggers in #7898; untouched.
- The 58 unnamed D members and whether #7898 closes at D=0 or at "sections 1-7 resolved" — an operator question, surfaced in the PR body's follow-up section, not decided here.
- The `*.ingest.de.sentry.io` tenant-wide residual — disclosed in-code (ADR-052); upgrade trigger recorded in the attack-surface table.
- A shared test lib for the curl argv check — none exists on `origin/main` (repo norm is per-harness stubs; `apps/cla-evidence/scripts/*.test.sh` carry three copies), and a lib would need a companion `.test.sh` registered in `infra-validation.yml`. Upgrade trigger: the fourth exec harness adopting the check → extract to `apps/web-platform/infra/test-lib/curl-confinement-check.sh`. Stub-snippet parity across the three harnesses is not guarded (the Rule D linter polices the scripts, which is what matters).
- **A Better Stack alert rule on `SOLEUR_*_SEND_FAILED`** — the crit rows are queryable, not paging. Better Stack Logs alert rules are not Terraform-managed here (the `betterstack*.tf` roots manage uptime/heartbeats + the ingest token only) and the Logs alert API shape is unverified in this repo, so it is not a line in this PR's tail. Triple test: user-visible consequence — yes ("a disk-full email fails and nobody is paged; the user meets the outage"); concrete trigger — the first `SEND_FAILED` row this PR makes shippable; measured size — one API-created alert (or one TF resource if the provider supports Logs alerts). → `ship` files it (AC11(e)).
- **Lifting the six extra `unset` names into the fifteen §5 scripts and `betterstack-query.sh`** — same actor class, one line each; recorded here so the next drawdown carries it.
- `disk-monitor.sh` / `resource-monitor.sh` with `RESEND_API_KEY` unset (`exit 0` + stderr WARNING, on-box only) — a Terraform-provisioned state (`server.tf` writes the env file in the same `remote-exec` that installs the script; AC14 asserts that provisioner ran). Flow review proposed a stamp-gated crit row; not adopted — it would add a stamp to two scripts for a state the apply log already shows. Recorded as a Taste decision.

## Drawdown recipe (for the next Rule D plan)

The remaining 61 firing entries follow the same six steps; cite these sections in order: (1) measure
RED — run the classifier on the unedited files and record the finding count (`### Premise
Validation`); (2) `### Common prologue` (refusal placement, unconditional arm, `emit_refusal()` helper,
`unset` after any `ENV_FILE` source); (3) `### Transport flags` (four flags, the one uncredentialed
curl that must NOT get `--proto`); (4) a destination adjudication ONLY where Rule D reports an
env-settable destination, in the `betterstack-query.sh` / `_cron-shared.ts` shape, URLs built from
the folded variable, reason tokens only in markers — never a constant that pins a literal
(`### Cut List`); (5) `### Baselines` — hand-delete, never `--write-baseline*`, ACs as "summary line
on main − N" AND "baseline file − N" (two different quantities); (6) `### Harness rows` — extend the
file's OWN exec harness stub (argv position + cardinality + `≥ 1` floor, inspection before any fail
branch), never the linter's per-limb corpus. Once #8023's amendment to ADR-202 merges, cite
ADR-202 for the four-flag form instead of restating it.

## Architecture Decision (ADR/C4)

No new decision: this applies ADR-214's pattern (and the #7873 property) to five more sites. C4 check performed against all three model files: Resend (`model.c4` › `resend = system "Resend"`) and Sentry (`sentry = system "Sentry"`) are already modeled as external systems; no new actor, system, container or access relationship is introduced; no cardinality embedded in an edge description changes (no monitor/heartbeat count moves — `apps/web-platform/test/c4-count-parity.test.sh` is expected unchanged and is run as part of the required `test` shard). No `.c4` edit.

## Domain Review

**Domains relevant:** engineering (CTO), product (CPO sign-off — threshold-driven)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** (structural pass) Decision 1 (merge blast radius) classification confirmed against `server.tf:479-600, 1897-1915`, `server.tf:467` (`ignore_changes=[user_data]`), the workflow `-target` set and `Dockerfile:212-228`; gap-free firewall restart confirmed (`cron-egress-nftables.sh` one `nft -f -` transaction, `die` before flush). Findings, all applied: (P1) Vector Source 2 already ships PRIORITY 0-2 from any unit, so the refusal markers reach Better Stack via a one-line `logger -p user.crit` in this PR — the 8-file Source 4 follow-up is not filed (this also satisfies the CPO's condition 3 by closing the consequence instead of deferring it); (P2) Sentry project/key regexes aligned to `_cron-shared.ts` › `SENTRY_PROJECT_RE` / `SENTRY_PUBLIC_KEY_RE`, cited; apex allowlist over org-equality confirmed correct under ADR-214; (P2) the alarm's cooldown log line no longer claims "Sentry check-in still posted" after a refusal; (P2) bootstrap has eight `resend_api` call sites, key charset admits `-`; the CTO reproduced the `--config` injection with all four flags present. No fail-open or fail-stop defect found. Complexity: medium. No new architecture decision.

### Product/UX Gate

**Tier:** none (no UI surface) — CPO consulted for the `single-user incident` sign-off only
**Decision:** reviewed — sign-off granted-with-conditions (all conditions applied in this plan)
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO (2026-09-11): (1) `single-user incident` is correct, not overstated — `noreply@soleur.ai` is DKIM/DMARC-aligned (`dns.tf` › `dkim_resend_send`, `dmarc`), so a forged message is indistinguishable from a real one to a customer, and the brand guide's #1 objection is trust; cited in `## User-Brand Impact`. (2) The "user meets the outage first" exposure is pre-existing for the monitors' self-reporting and this PR improves the refusal path (refusal text rides the surviving channel); the first User-Brand bullet now says so explicitly. (3) The Vector Source 4 Non-Goal must be a tracked, milestoned item carrying the user-visible consequence verbatim — superseded by the CTO's P1: the consequence is closed in this PR (Source 2 + `logger -p user.crit`), so nothing with a user-visible consequence is deferred; AC17 now asserts the sink deterministically instead. (4) The "D=0 vs sections 1-7" question rephrased for a non-technical reader with counts and a recommended default — AC11(c) amended. #7898 is milestone "Post-MVP / Later"; this plan is a partial drawdown, not a closer.

## Plan Review (panel, 2026-09-11)

Eng panel: DHH, code-simplicity (per-mechanism, Goal Verification rendered), Kieran,
architecture-strategist, spec-flow-analyzer (5-agent panel at the `single-user incident`
threshold); named panel: CTO (devex lens); plus the Phase 2.5 CTO (structural) and CPO
(sign-off) and the Step 4.5 advisor consult. **Decision: reviewed.**

Mechanical findings applied (both simplification reviewers AND the flow lens fired on the same
scope → delete): the quiet-tick refusal email + stamp + startup hoist (cut; lazy adjudication in
`sentry_event()` mirroring the alarm); four hand-written emitters → one `emit_refusal()` helper;
markers carry REASON TOKENS only — never the host (Kieran/architecture: a pasted DSN would ship
the public key through both sinks; folding sanitizes nothing, measured); Sentry URLs interpolate
`${_si_host}` (Kieran: the raw value defeats the must-PASS row); `?*.ingest…` (empty label,
measured); `MOCK_SENTRY_HOST`/`MOCK_SENTRY_KEY` harness overrides; stub inspection before the
`MOCK_CURL_FAIL` branch; per-row exact `curl_checked` equality + static no-bypass grep → a `≥ 1`
floor; mutation matrices deduplicated (20 → 13 rows); `readonly RESEND_API` cut; the scratchpad-only
alarm probe → a committed exec row + `BEGIN/END sentry-dest-pin` parity row; the bootstrap marker
written to stderr too (spec-flow: `$( … )` swallows stdout at all eight call sites); the alarm's
cooldown/`jq`/unset branch emits `SEND_FAILED` (spec-flow: the unit-failure signal was journald-only
for the whole 30-min cooldown); AC2/AC13 corrected to the summary line's quantity (Kieran: the
runner prints firing files, `100 … 66` today, not baseline lines); AC14 adds the `host-egress-ok`
positive token; AC16's live query shape corrected (spec-flow: `--grep` cannot match a field);
the two `.ts` source-parsing suites added to AC6 (architecture); the `host_scripts_content_hash`
side effect recorded (architecture); ACs 21 → 16 with process steps moved to tasks.md; `LC_ALL=C`
scope stated; inline-vs-lib rationale and a `## Drawdown recipe` added; a test-lib upgrade trigger
recorded.

Taste / user-challenge (persisted to `decision-challenges.md` for `ship`): P9 (`SEND_FAILED` crit
rows) is a small scope ADD beyond the five-file confinement the operator named — kept, surfaced.
DHH's "the `SENTRY_PUBLIC_KEY` regex in the monitor is symmetry, not a pin" — kept as-is (the
`_cron-shared.ts` precedent validates the triple as a unit and the parity row needs identical
blocks). Spec-flow's stamp-gated crit row for `RESEND_API_KEY`-unset in the two Resend-only monitors
— not adopted (Non-Goals). All three recorded, none silently applied.

## Deepen-plan pass (2026-09-11)

Gates: 4.6 User-Brand (pass), 4.7 Observability (5 fields, `python3` verb, no ssh — pass), 4.8 PAT (pass),
4.11 Guard Contract (lint green, 3 entries), 4.5 resource-shape trigger (fired → the Hypotheses
deep-dive above), 4.55 downtime (no trigger — `user_data`-only, `ignore_changes`-covered), 4.4
precedent diff (table above), 4.10 encryption posture (no new store or connection — skipped), 4.9
wireframe (no UI — skipped). Rule-id citations all resolve to active `[id: …]` entries.

Agents: security-sentinel, observability-coverage-reviewer, silent-failure-hunter,
test-design-reviewer (score 7.5/10 before fixes), git-history-analyzer, pattern-recognition-specialist,
user-impact-reviewer, plus a sonnet verify-the-negative sweep (11 present-tense file claims, all
`confirms`).

Corrections applied: ADR-202 already exists on `origin/main` (#8023 amends it — the plan had said
it authored it); the bootstrap harness cut rested on a false "CODEOWNERS-gated workflow edit" premise
(`require_code_owner_review` is unset on the CI ruleset) → a committed
`resend-inbound-bootstrap.test.sh` + one registration line, run under `env -i` with a fake key and
in-process fd assertions (security: the earlier scratchpad `cat` of the `--config` fd could have
recorded a live key); the host pin is a positive label grammar (security: a deny arm passes
`%2F`), which also fixes the `\*\.ingest` static-grep contradiction and the empty-label case; the
`unset` list gains `OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT`;
`FAILED_UNIT` charset-validated before it is emitted; pin variables initialised before the `if`
(user-impact: an unbound read on the triple-unset path under `set -u` would abort the alarm before
its only surviving channel) + a triple-unset harness row per dual-channel script; the stub's `'*'`
compare must be quoted; `curl_checked == 2` on the two-member harness's alert rows; the parity
region scoped to the predicate with a non-empty guard; reason-token last-wins fixed; the email note
appended inside `resend_email()`; every early return that skips a send calls `emit_refusal`; Sentry
curls gain an HTTP-status check; `rc=` on failed Resend sends; a `logger`-absent row per harness
and a `logger=absent` stderr line; `emit_refusal()` (not `refuse()`), `-t "$LOG_TAG"`, `http_code=`
and `# … (#7898)` on both region markers, all per the tree's dominant conventions; a Source 2 drift
row in `vector-pii-scrub.test.sh`; a post-merge AC evaluating the MERGED pin against the live prd
triple without SSH; the container stop → start named in Risks. Not adopted (recorded): changing
the pre-existing cooldown-arming semantics; `return 1` from `sentry_event()` (only needed for that
change); a Better Stack alert rule in this PR (filed as a follow-up with its consequence).

## References & Research

- `scripts/lint-shell-trace-credential-refusal.py` › `check_rule_d()`, `_destination_vars()`, `_adjudicated()`, `_pin_re()`, `unconditional_reason()` — the classifier every shape here was measured against.
- `scripts/betterstack-query.sh` › the `_bs_auth`/`_bs_host` derivation and the `*.betterstackdata.com` case — the host-pin idiom.
- `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` › the unconditional refusal + `SOLEUR_TRIGGER_CRON_HALT` marker shape; `plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh` › the hoisting note.
- PR #8023 diff: the four-flag form, the `--noproxy` cardinality finding, `mk_curl_stub`'s positional assertion.
- `knowledge-base/engineering/architecture/decisions/ADR-214-a-test-seam-for-a-destination-pin-must-never-be-env-declared.md`, `ADR-031-sentry-as-iac.md` (host glossary), `ADR-052`.
- `apps/web-platform/infra/server.tf` › `terraform_data.disk_monitor_install` (and siblings), `local.host_script_files`; `.github/workflows/apply-web-platform-infra.yml` (paths + SSH `-target` set); `apps/web-platform/infra/vector.toml` › `[sources.host_scripts_journald]`.
- Learnings listed under Research Insights.
