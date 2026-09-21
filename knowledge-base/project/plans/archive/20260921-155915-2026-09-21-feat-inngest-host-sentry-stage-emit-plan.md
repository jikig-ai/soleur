---
title: "feat(inngest): the dedicated soleur-inngest host reports its bootstrap-pull outcome on the Sentry stage: schema"
date: 2026-09-21
slug: feat-inngest-host-sentry-stage-emit
branch: feat-one-shot-6500-inngest-sentry-stage
issue: 6500
closes: none
type: feat
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# feat(inngest): the dedicated soleur-inngest host reports its bootstrap-pull outcome on the Sentry `stage:` schema

**Ref #6500 — this PR must NOT close #6500.** The PR body uses `Ref #6500`, never `Closes`/`Fixes`/`Resolves`.
#6500 closes only when an operator posts `RESULT: PASS` (probe: `scripts/followthroughs/inngest-zot-client-authz-6500.sh`),
because closing it authorizes the irreversible GHCR PAT revoke (ADR-096 tasks 5.3-5.5). Nothing in this plan rotates,
revokes or reads the GHCR PAT.

## Enhancement Summary

**Deepened on:** 2026-09-21
**Agents used:** framework-docs-researcher (cloud-final unit semantics), security-sentinel (with a verify-the-negative
pass), observability-coverage-reviewer, test-design-reviewer, architecture-strategist (with the post-edit self-audit),
learnings-researcher. The plan-time panel before this was: advisor, CTO, DHH, Kieran and code-simplicity.

### Key Improvements

1. **Call sites are foreground `|| true` again.** Upstream `cloud-final.service` (cloud-init `25.1.4`/`main`) has no
   `KillMode` line, so the default `control-group` applies. The fallback arm exits seconds after the emit, so a
   backgrounded emit could be killed before it POSTs.
2. **The DSN file is read with `sed`, never sourced, and the DSN shape is checked before curl.** This closes
   root-shell execution from a malformed `var.sentry_dsn` and `curl -K -` config injection. The added G3 rows 7-8 and
   G4 row 4 cover both.
3. **New `## Downtime & Cutover` section.** Blue-green is impossible for the ADR-100 singleton, so a bounded window is
   used, with the pre-dispatch `INNGEST_CUTOVER_FLIP` check from the inherited-`done` runbook section (a 76-minute
   stranding happened on 2026-09-17). The rollback wording is corrected.
4. **Test harness realism.**
   - Key-count bounds go from 17 to 18.
   - Each guard row is homed in a suite that can actually run it: G2/G3/G4 in-suite in the render-owning
     `inngest-boot-emitter.test.sh`, G6 rows 6-7 by mutating the relocated soak copy, and G1 row 10 in the soak suite.
   - A per-arm extractor is added.
   - The phone-home stub exits 3, so G3 row 1 is no longer an equivalent mutant.
   - `run_soak` gets a fixture-body parameter.
5. **Factual fixes.**
   - The `inngest-host-replace` job reads no `confirm` input.
   - The `model.c4:712-722` comment says "Deliberately NO `inngest -> sentry` edge" and must be rewritten.
   - ADR-096's 2026-08-13 amendment gets supersession pointers.
   - The metadata-API exposure is broader than root-only.
   - The Sentry denominator event is forgeable, so the Better Stack corroboration (PM2) is required before
     `RESULT: PASS`.

### New Considerations Discovered

- A lost fallback emit is an accepted residual. That boot fails anyway (the GHCR leg 401s), so the inngest liveness
  heartbeat pages.
- `var.sentry_dsn` has no Terraform `validation` block. The emitter-side shape check makes this harmless for this
  host. Adding a validation block is left out of scope (AC2 keeps `variables.tf` untouched).

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

The dedicated Inngest host (`hcloud_server.inngest`, 10.0.1.40) already pulls its bootstrap image zot-first with a
GHCR fallback (#7516, merged 2026-08-14), and it reports the outcome only to Better Stack. The GHCR-retirement soak
(`scripts/followthroughs/zot-soak-6122.sh`) counts fresh-boot outcomes from Sentry `stage:` tags, so it cannot see
this host. That is the only remaining technical half of #6500's close condition 2.

This plan adds a host-local, best-effort Sentry emitter to the inngest host. It is named `soleur-boot-emit`, takes
the web emitter's `<stage> [level]` arguments (plus a literal third `detail` argument, a deliberate divergence), and sends the
same event message and tag key set, and it is called on both pull-outcome
arms (`inngest_zot` info, `inngest_ghcr_fallback` warning). The Sentry DSN is baked from the existing root variable
`var.sentry_dsn` through the Terraform template, the same way #7516 baked the zot credential, so the Doppler
`soleur-inngest/prd` secret set and its exact-equality isolation check stay unchanged. The soak is tightened in the
fail-closed direction only: its blocker corroboration now also requires the Sentry-shaped call sites, and a new
denominator arm needs at least one `inngest_zot` event before it can PASS.

## Research Reconciliation — Spec vs. Codebase

| Claim (from the brief / #6500 body) | Reality on `origin/main` (2026-09-21) | Plan response |
|---|---|---|
| Rollout is an `apply_target=inngest-host` dispatch | That job is **additive-only**: it aborts with `server_touched` on any update/replace of `hcloud_server.inngest` (`.github/workflows/apply-web-platform-infra.yml:1807`). A user_data change is delivered by `apply_target=inngest-host-replace` (`:1842-1851`, scoped gate `tests/scripts/lib/inngest-host-replace-gate.sh`, shared `deploy-inngest-restart` mutex) | Rollout names **`inngest-host-replace`** in an ADR-100 maintenance window. `inngest-host` is named only as the target that must NOT be used. |
| Doppler isolation is "5 dark / 6 live" | The comment at `cloud-init-inngest.yml:1181` says "5 dark / 7 live"; the regex at `:1241` admits 11 names; the check at `:1242` is `n_total -ne n_inngest \|\| n_inngest -lt 5` | This plan does not change any of it. A new test pins the admitted-name line by exact value, so a future edit must change the pin as well. |
| The web host's `inngest_zot`/`inngest_ghcr_fallback` Sentry events are live | Those calls are in `cloud-init.yml:743`, inside the **colocated** inngest block gated by `web_colocate_inngest` (default `false`, `variables.tf`). The block is gated off, not deleted: a web host born with `web_colocate_inngest = true` would emit both stages again. With the default, `[freshboot]` has had no live producer since ADR-100 | The dedicated host becomes the live producer of both stages. `[freshboot]` stays bare, because a bare count only adds failures. The new `inngest_zot` denominator is pinned to `host_name:"soleur-inngest"`, because a colocated web host must never satisfy it (advisor + CTO finding). |
| `zot-soak-6122.sh:459-465` predicates accept the inngest shape | True, but they accept the **Better Stack** call (`inngest-boot-phone-home.sh inngest_zot`), which does not meet close condition 2 ("reports on the Sentry `stage:` schema") | Add an **AND**-ed predicate that requires the Sentry call sites. The existing predicates stay byte-identical. |
| The alarm will need a new rule | `sentry_alert.zot_mirror_fallback_rate` already matches `stage eq inngest_ghcr_fallback` (`sentry/issue-alerts.tf:1971`, `value = 0`) | No alert change. The dedicated host's fallback now pages through the existing rule. |

## Research Insights

**Premise validation (Phase 0.6).** #6500 is OPEN (P1, `follow-through`); PR #8488 is an OPEN draft; #7516 is MERGED;
#7462 and #7674 are CLOSED; #6462 is CLOSED. The zot pull arm exists at `cloud-init-inngest.yml:1358` (`IREF=`),
`:1402` (`ZIREF=`) and `:1411-1432` (pull, then `IREF="$ZIREF"` or fallback). The Better Stack stage calls are at
`:1418` and `:1431`. The comment describing the gap is at `:1420-1429`. The zot credential bake is at `:1138`, with the
render map at `inngest-host.tf:420-422`. All confirmed. One premise was stale: the rollout target (see the
reconciliation table). Out-of-scope issues confirmed OPEN and left alone: #7077, #7243, #7596, #8425.

**The DSN source decision.** The web host's `soleur-boot-emit` gets its DSN from the Terraform root variable
`var.sentry_dsn` (`variables.tf:555`, `sensitive = true`, fed by `TF_VAR_sentry_dsn` from Doppler `prd_terraform`
`SENTRY_DSN`). It is baked into user_data at `server.tf:357` and spliced into the emitter at
`soleur-host-bootstrap.sh:364`. The same variable is already threaded to git-data (`git-data.tf:338`). **The inngest
host is in the same Terraform root**, so `sentry_dsn = var.sentry_dsn` in the `inngest-host.tf` templatefile map
needs no new variable. Every apply of this root already resolves that variable, so there is no whole-apply hazard
(the #7516 comment at `inngest-host.tf:394-397` describes that hazard). The DSN never enters Doppler `soleur-inngest/prd`.
**Decision: bake, not Doppler.** A runtime Doppler read cannot work here anyway: the host's token is scoped to the
isolated `soleur-inngest` project (`inngest-host.tf:342-347`), which cannot read `soleur/prd`.

**Relevant files.**

- `apps/web-platform/infra/cloud-init-inngest.yml`: `write_files` (`:42`), phone-home emitter (`:271-332`),
  `inngest-redact.sh` (`:342-363`), runcmd (`:460`), zot bake (`:1138`), isolation check (`:1237-1253`), pull block
  (`:1356-1459`).
- `apps/web-platform/infra/inngest-host.tf`: templatefile map (`:322-433`), the `user_data` precondition (`:516`), no
  `ignore_changes=[user_data]` (`:461`, `:476-478`).
- `apps/web-platform/infra/soleur-host-bootstrap.sh:295-379`: the web emitter heredoc (`EMITEOF`), body format at
  `:356`, curl at `:357-360`.
- `scripts/followthroughs/zot-soak-6122.sh`: `FAIL_QUERIES` (`:245-251`), cardinality floor (`:261`), `APP_ZOT`
  denominator (`:322-339`), blocker arm (`:377-468`), predicates (`:459-465`), the remaining-gap note (`:470-477`).
- `apps/web-platform/infra/sentry/issue-alerts.tf:1862-1981`: `zot_mirror_fallback_rate`.
- Test suites: `inngest-boot-emitter.test.sh` (renders the template through `terraform console` at `:222`, with a
  key-set parity check against the `.tf`, registered at `infra-validation.yml:920`); `cloud-init-inngest-bootstrap.test.sh`
  Guard 1 (`:652-870`); `cloud-init-inngest-zot-pull-mutation.test.sh` (mutation battery for Guard 1, `infra-validation.yml:1292`);
  `inngest-host.test.sh` (`:199-204` isolation pins, `infra-validation.yml:1518`);
  `scripts/followthroughs/zot-soak-6122.test.sh` (`scripts/test-all.sh:2076`, with fixture "after #6500" at `:91-111`,
  which already uses `soleur-boot-emit inngest_zot info` in `cloud-init-inngest.yml`);
  `inngest-userdata-budget.sh` (template stub map `:166-185`, `infra-validation.yml:1947-1959`);
  `plugins/soleur/test/cloud-init-user-data-size.test.ts` (`INNGEST_GZIP_BUDGET = 18_000`, `:220`);
  `doppler-download-error-channel.test.sh:35` (the awk extractor for the web `EMITEOF` body; not needed after review, see
  Plan Review Revisions).
- Measured payload headroom: stored 10,892 B / headroom 21,876 B against Hetzner's 32,768 B cap (`inngest-host.tf:311-312`).

**Institutional learnings applied.**

- `2026-07-06-cloud-init-user-data-cap-bake-bodies-and-set-e-scope-fix-ungates-security-checks.md`: runcmd is ONE `/bin/sh`,
  so a `set -e` set in one item reaches later items. The pull block sets `set -e` right after the zot pull, so a
  foreground call site needs `|| true`, and that is the form used (backgrounding was considered and reversed at deepen
  time, see Phase 0). The emitter must also never be asserted into existence under `set -e`
  (see `2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot.md`).
- `2026-07-09-sentry-fallback-rate-alarm-pre-bootstrap-emitter-and-issue-group-grouping.md`: `soleur-boot-emit` events share
  one always-hot issue group (the static message), and a `value = 0` rule is what makes a first event page.
- `2026-07-19-my-own-mutation-battery-was-the-false-confidence.md` and `2026-08-13-...guard-was-green-with-its-property-inverted...`:
  mutation rows are derived from the design (below), include a must-PASS non-canonical input, and include a harness row.
- `workflow-patterns/2026-08-06-an-observability-plan-can-name-a-sink-the-code-cannot-reach.md`: confirm the sink is reachable.
  `hcloud_firewall.inngest` (`inngest-host.tf:596`) has no `direction = "out"` rule, and the host nftables declares an
  `input` chain only (`inngest-host.tf:414-416`). Egress to the Sentry ingest host over public HTTPS is the same route
  the Better Stack phone-home already uses.
- The git-data emitter precedent (`apps/web-platform/infra/cloud-init-git-data.yml:44-52` and `:352-357`, and the
  git-data row in `scripts/encryption-posture-ledger.json`): pass the auth header via `curl -K -` on stdin, as
  `printf 'header = "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=%s"\n' "$KEY" | curl -K - …`, so no
  credential appears in `/proc/<pid>/cmdline`. The web emitter does not do this, and this
  plan does not copy that gap.

**Property List (Phase 0.6b).**

- P1: every fresh boot of the dedicated inngest host that attempts the zot leg produces exactly one Sentry event
  tagged `stage:inngest_zot` (zot served) or `stage:inngest_ghcr_fallback` (zot missed), with the web emitter's message
  and tag key set, and `host_name:soleur-inngest`.
- P2: the emit can never block, delay without bound, or fail the boot.
- P3: the DSN and its key never appear in logs, shipped tails, or process argv.
- P4: `soleur-inngest/prd` and its isolation check are unchanged.
- P5: the soak cannot PASS without a host-pinned Sentry `inngest_zot` event in the window and the anchored call sites
  in code (fail-closed), and nothing in it gets weaker. **The event is unauthenticated**: the DSN is public, so a
  third party could forge it. The count is therefore evidence, not proof. The Better Stack marker, whose token is not
  public, is the corroboration an operator must read before posting `RESULT: PASS` (PM2).
- P6: the change reaches the live host only through a planned `inngest-host-replace`. An unplanned replace in the
  meantime is visible after the fact, and the owed window is tracked by the soak itself.

**Cut List (Phase 0.6b).**

- Adding `SENTRY_DSN` to `soleur-inngest/prd` (P1): cut. Baking `var.sentry_dsn` achieves the same thing and leaves P4
  untouched.
- A new Sentry alert rule for the inngest fallback: cut. The existing `zot_mirror_fallback_rate` already matches the
  stage.
- A new soak `FAIL_QUERIES` entry: cut. `[freshboot]` is already a bare `stage:"inngest_ghcr_fallback"` query, and
  the cardinality floor stays at 5.
- Moving the web emitter into a shared file used by both hosts: cut. It would touch the web host-script bundle and
  its tests to buy byte-sharing. The only Sentry consumers read the message and the `stage`/`host_name` tags, which G2
  pins by value.
- (Plan review) A tmpfs `/run` staging item, a `sentry-dsn-EMPTY` runcmd item, a detail-shape allowlist, an outer
  `timeout 30`, a no-endpoint `else` arm, a byte-identical cross-file format guard and a permanent isolation-regex
  pin: all cut. Each either guarded a property another mechanism already covers or guarded a path that cannot run.
  See Plan Review Revisions.
- Emitting every phone-home stage to Sentry: cut. Only the two pull-outcome stages count toward any Sentry consumer.
- A Doppler runtime fallback for the DSN, as the web emitter has: cut. It is unreachable on this host by construction.

**CLI verification.** No CLI invocation lands in user-facing docs. The workflow dispatch named below uses flags
already documented in `apply-web-platform-infra.yml:206` and `:217-273`.

## Problem Statement

`zot-soak-6122.sh` guards an irreversible action (the GHCR PAT revoke). Its `[freshboot]` query counts
`stage:"inngest_ghcr_fallback"` in Sentry. The only Sentry emitters of that stage sit in the colocated block of
`cloud-init.yml`, which is gated off by default (`web_colocate_inngest = false`). The live dedicated host emits the
same stage name to Better Stack only (`cloud-init-inngest.yml:1431`). So a zero `[freshboot]` count says nothing
about the live scheduler, and the soak's own trailer admits this (`zot-soak-6122.sh:470-477`). #6500's close
condition 2 is unmet.

## Proposed Solution

### Architecture

```text
write_files (init stage, before runcmd)
  /etc/default/soleur-sentry-dsn   0600 root  SOLEUR_SENTRY_DSN=${sentry_dsn}   (NEW; the #7516 /etc/default/soleur-zot-read shape)
  /usr/local/bin/soleur-boot-emit  0755 root  no secret inside                   (NEW)

runcmd pull block (ONE /bin/sh; set -e live from :1413)
  zot hit  → inngest-boot-phone-home.sh inngest_zot ...            (Better Stack, unchanged)
           → soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true              (NEW, Sentry, foreground, bounded)
  zot miss → inngest-boot-phone-home.sh inngest_ghcr_fallback ...  (Better Stack, unchanged)
           → soleur-boot-emit inngest_ghcr_fallback warning "rc=$zot_rc" || true  (NEW, Sentry, foreground, bounded)

soleur-boot-emit <stage> [level] [detail]
  DSN READ (sed, never sourced) from /etc/default/soleur-sentry-dsn (read-only seam: SOLEUR_SENTRY_DSN_FILE)
    empty/missing → phone home sentry-emit-FAILED "stage=<s> rc=nodsn", exit 0
    not ^https://[A-Za-z0-9]+@[A-Za-z0-9.-]+/[0-9]+$ → phone home rc=baddsn, exit 0 (no curl)
  body: message "soleur-cloud-init boot stage", tags {stage, host_id, region:"cloud-init", host_name:"soleur-inngest", detail}
  printf 'header = "X-Sentry-Auth: …sentry_key=%s"' | curl -K - -sf --connect-timeout 5 --max-time 8 --retry 1 --retry-max-time 15 …/store/
    rc != 0 → phone home sentry-emit-FAILED "stage=<s> rc=<n>"   (seam: SOLEUR_INNGEST_PHONE_HOME)
  always exit 0
```

### Implementation Phases

#### Phase 0: Runtime assumption (resolved at deepen time; no work item)

The first draft backgrounded the call sites (`… &`). That was **reversed at deepen time**. Upstream
`systemd/cloud-final.service` (canonical/cloud-init `main` and tag `25.1.4`, the noble-updates version) sets
`Type=oneshot` and `RemainAfterExit=yes` and does **not** set `KillMode`, so the default `KillMode=control-group`
applies. Research sources disagreed on whether a process left in the cgroup after the runcmd script exits survives,
and the fallback arm reaches `exit "$pull_rc"` (`:1455`) seconds after the emit. The plan therefore **does not rely
on orphan survival**. Both call sites run in the **foreground**, ending in `|| true`, with the emitter's curl bounded
by `--connect-timeout 5 --max-time 8` (review: `--retry` dropped — curl reports a declined 429 retry as rc 0). The worst case is about 16 s of added boot time (8 s emit + the 8 s failure phone-home),
and only when Sentry is unreachable. The emit then completes before the fallback arm's `exit`, deterministically.

Verification command (no credentials):
`curl -s https://raw.githubusercontent.com/canonical/cloud-init/25.1.4/systemd/cloud-final.service | grep -nE 'KillMode|Type|RemainAfter'`
prints `14:Type=oneshot` and `23:RemainAfterExit=yes`, and no `KillMode` line.

#### Phase 1: Tests first (RED)

Write the Guard Contract assertions below before any product edit, and confirm each fails against `origin/main`:

1. `apps/web-platform/infra/inngest-boot-emitter.test.sh`:
   - Add `sentry_dsn="https://pubKEYx7@o1.ingest.invalid/42"` to the hand-kept render map at `:222`. The key must be
     alphanumeric to pass the emitter's DSN shape check; it is short and non-hex, so the redaction backstop cannot
     catch it.
   - **Bump the key-count floor and ceiling from 17 to 18** (the `-ge 17` / `-le 17` arms at about `:258-270`, and
     their comment). Without this the over-read guard stays RED after Phase 2. The key-set parity arm goes RED until
     `inngest-host.tf` threads the key, which is the intended tripwire.
   - Add the G2, G3 **and G4** cases here, because this suite already owns the `terraform console` render. G4's
     `inngest-redact.sh` body contains `$${vals[@]}`, which is valid bash only after rendering.
   - The cases extract the rendered `write_files` bodies and run them with a stub `curl` on PATH. The stub records
     argv, stdin and the `-d` body to files, and its exit code is configurable. `SOLEUR_INNGEST_PHONE_HOME` points at
     a recording stub that **exits 3**, so G3 row 1 cannot survive as an equivalent mutant.
   - Call `curl` by bare name in the emitter so the PATH stub shadows it.
   - Each mutation row is implemented **in-suite**: copy the rendered body, apply a `sed` mutation, assert the
     mutation landed (a diff is non-empty), and run the case expecting RED. This follows the landed-diff contract of
     `cloud-init-inngest-zot-pull-mutation.test.sh`. That battery's sandbox copies only `infra/` + `.github/` and runs
     only `cloud-init-inngest-bootstrap.test.sh`, so it cannot host G2, G3 or G4.
2. `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: add a "Guard 1b" section after Guard 1.
   - Add a new **per-arm extractor**. It splits `DED_BLOCK_FILE` (`:697`) at `[ "$zot_rc" -eq 0 ]` / `else` / `fi`
     into a zot-arm file and a fallback-arm file, each with a non-empty line-count floor.
   - Strip comments from those arm files as well, because `DED_BLOCK_FILE` is extracted from the raw file (`:691`).
   - Assert exactly one anchored call per arm, with the right stage in the right arm.
   - Assert the `write_files` entries and their permissions.
3. `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`: add the G1 rows that mutate
   `cloud-init-inngest.yml` or `inngest-host.tf` (rows 1-8, 11-13) to the existing battery, using its landed-mutation
   diff contract. Row 9 is proven in-suite by `inngest-boot-emitter.test.sh`'s parity arm. Row 10 is proven in
   `zot-soak-6122.test.sh`, the only suite that sees both files.
4. `apps/web-platform/infra/inngest-host.test.sh`: no new cases. The existing isolation fragment pins (`:199-204`)
   remain, and AC3 covers this PR.
5. `scripts/followthroughs/zot-soak-6122.test.sh`:
   - add `soleur-inngest=1` as the **first** key of `$HEALTHY` (`:154`) and of every inline spec that reaches past the
     `APP_ZOT` arm, including `:201` (thin sample). The stub matches keys as substrings in order, first match wins, and
     returns HTTP 500 on no match. Without this, every case that passes `APP_ZOT` turns TRANSIENT instead of its
     expected verdict (the OPEN case at `:170`, thin sample at `:201`, unreadable at `:244`, the old fixture at `:259`).
     The key `soleur-inngest` matches only the host-pinned query.
   - update the "after #6500" fixture (`:103-111`) so it carries both Sentry call sites in the exact form Phase 3.4
     prescribes.
   - **extend `run_soak`** with a fixture-body parameter. Its `yes`/`old` modes cannot express G6 rows 2-3 (one call
     site, or calls present only as comments).
   - implement G6 rows 6-7 **in-suite** by `sed`-mutating the relocated soak copy that `run_soak` already makes (with
     the landed-diff check), so no new battery file is needed.
   - add the G1 row 10 parity assertion: the emitter's `HOST_NAME` literal in `cloud-init-inngest.yml` equals the
     `host_name:` value in the soak's denominator query.
   - add the G6 cases.

#### Phase 2: Terraform threading

1. `apps/web-platform/infra/inngest-host.tf`: add `sentry_dsn = var.sentry_dsn` to the templatefile map (`:322-433`).
   The comment goes in the `.tf` (prose there is free, per `:320-321`) and says: this is the root variable already baked
   into web-1 and git-data; it is not a Doppler key, so the `soleur-inngest/prd` identity check is untouched; an empty
   value makes the emitter phone home `rc=nodsn`, and the soak denominator fails closed.
2. `apps/web-platform/infra/inngest-userdata-budget.sh`: add a `sentry_dsn` stub to the map (`:166-185`), 128 B in the
   DSN shape, and list it among the documented upper bounds in the header (`:25-50`).
3. Every other hand-kept render map of `cloud-init-inngest.yml`. Enumerate with
   `git grep -ln 'zot_pull_token *=' -- '*.sh' '*.ts' '*.py'`. On `origin/main` that finds
   `inngest-boot-emitter.test.sh` and `inngest-userdata-budget.sh` for this template (the registry hits belong to
   another template). `plugins/soleur/test/cloud-init-user-data-size.test.ts` `SECRET_LENGTHS` needs **no** entry: it
   carries none for git-data, which already threads `var.sentry_dsn`. If that suite reddens anyway, add
   `sentry_dsn: 128`.

#### Phase 3: Host-side emitter (cloud-init-inngest.yml)

1. **`write_files` `/etc/default/soleur-sentry-dsn`** (`owner: root:root`, `permissions: '0600'`), content
   `SOLEUR_SENTRY_DSN='${sentry_dsn}'` (single-quoted). It is written at cloud-init's init stage, before runcmd, so
   it needs no runcmd item. It is the same shape and trust boundary as `/etc/default/soleur-zot-read`. **No consumer
   sources this file.** Both consumers read it with `sed` (security finding: a sourced file is shell code run as
   root, and `var.sentry_dsn` has no `validation` block, per `variables.tf:555-560`). `write_files` applies the mode
   after writing. That window is accepted for this ingest-only, semi-public value and recorded in Encryption Posture.
2. **`write_files` `/usr/local/bin/soleur-boot-emit`** (`0755`, root:root), placed directly after `inngest-redact.sh`.
   Its body:
   - `#!/bin/sh`, then `( set +e … ) || true` and `exit 0`, following the web emitter's structure
     (`soleur-host-bootstrap.sh:296-363`).
   - Usage `soleur-boot-emit <stage> [info|warning|fatal] [detail]`. The first two positional arguments mean what they
     mean in the web emitter. **The third is a deliberate divergence:** the web emitter reads detail from
     `/run/soleur-stage-detail.d/<stage>` through a sanitizer (`soleur-host-bootstrap.sh:323-354`). This host has no
     such channel, and its call sites pass only literal `rc=<n>`/`ep=<ip:port>` values pinned by G1.
   - Read-only seams, brace-free like `:277-281`:
     `f=/etc/default/soleur-sentry-dsn; [ -n "$SOLEUR_SENTRY_DSN_FILE" ] && f="$SOLEUR_SENTRY_DSN_FILE"` and
     `ph=/usr/local/bin/inngest-boot-phone-home.sh; [ -n "$SOLEUR_INNGEST_PHONE_HOME" ] && ph="$SOLEUR_INNGEST_PHONE_HOME"`.
     The DSN seam selects a file to **read**, never to execute (the same class as the phone-home token seam).
   - `DSN=$(sed -n "s/^SOLEUR_SENTRY_DSN='\(.*\)'$/\1/p" "$f" 2>/dev/null | head -n 1)`.
     - Empty: `[ -x "$ph" ] && "$ph" sentry-emit-FAILED "stage=$STAGE rc=nodsn"`, then exit 0.
     - Otherwise check the shape: `printf '%s' "$DSN" | grep -qE '^https://[A-Za-z0-9]+@[A-Za-z0-9.-]+/[0-9]+$'`. On
       a mismatch, phone home `rc=baddsn` and exit 0 **before any curl**. This closes `curl -K -` config injection (a
       key containing `"`, `\` or a newline) and prevents a malformed DSN from reaching curl's argv as the URL.
   - `KEY`/`SHOST`/`PROJ` parsed with the web emitter's three `sed -E` expressions (`soleur-host-bootstrap.sh:310-312`).
     After the shape check they are each restricted to a safe charset by construction.
   - `HOST_ID` from `/var/lib/cloud/data/instance-id` with a `hostname` fallback. `HOST_NAME='soleur-inngest'` is a
     literal, because the soak denominator filters on it (G1 row 10 pins the two equal). It also equals the
     `hcloud_server.inngest` name (`inngest-host.tf:443`).
   - `BODY=$(printf '{"message":"soleur-cloud-init boot stage","level":"%s","tags":{"stage":"%s","host_id":"%s","region":"cloud-init","host_name":"%s","detail":"%s"}}' …)`.
     This is the web format at `soleur-host-bootstrap.sh:356`. It contains no `%{` and no `${`, so templatefile renders
     it byte-for-byte (G2 row 4; see `knowledge-base/project/learnings/best-practices/2026-07-14-cloud-init-templatefile-escaping-and-ci-deploy-payload-testing.md`:
     "an edit must satisfy the EARLIEST parser first").
   - `printf 'header = "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=%s"\n' "$KEY" | curl -K - -sf --connect-timeout 5 --max-time 8 --retry 1 --retry-max-time 15 -X POST "https://$SHOST/api/$PROJ/store/" -H 'Content-Type: application/json' -d "$BODY" >/dev/null 2>&1`.
     This is the git-data precedent (`cloud-init-git-data.yml:50-52`, which also uses `--connect-timeout`). Capture
     `crc`. If it is non-zero: `[ -x "$ph" ] && "$ph" sentry-emit-FAILED "stage=$STAGE rc=$crc"`. That is numeric
     only, per the #7228 rule that a silent emitter failure must land somewhere.
   - Comments in the body stay minimal (`local.inngest_rationale_strip` removes whole-line `# ` comments anyway;
     `#!/bin/sh` survives because `#` is followed by `!`).
3. **`inngest-redact.sh`** (`:342-363`): add an explicit enumeration line after the zot line (`:354`), reading the value
   (never sourcing it), with the same read-only seam:
   `sf=/etc/default/soleur-sentry-dsn; [ -n "$SOLEUR_SENTRY_DSN_FILE" ] && sf="$SOLEUR_SENTRY_DSN_FILE"; sdsn="$(sed -n "s/^SOLEUR_SENTRY_DSN='\(.*\)'$/\1/p" "$sf" 2>/dev/null | head -n 1)"; vals+=("$sdsn"); vals+=("$(printf %s "$sdsn" | sed -E 's#https://([^@]+)@.*#\1#')")`.
   That covers the whole DSN and its key. It must not rely on the `[0-9a-f]{32,}` / `{40,}` backstop. (A 6-byte
   minimum already skips empty values, per `:360`.) In the rendered template, the `\(`/`\1` escapes pass through
   templatefile unchanged. There is no `$${` in this line, and G4 runs against the rendered body.
4. **Call sites** in the pull block. Each is its own line, starts with the **bare** name `soleur-boot-emit`
   (not `/usr/local/bin/…`, which this file otherwise uses), and has **exactly one space** between tokens, so each
   matches the soak's `^[[:space:]]*soleur-boot-emit inngest_zot ` anchors and AC1. Each is **foreground**, ending in
   `|| true`:
   - zot arm, after `:1418`: `soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true`
   - fallback arm, after `:1431`: `soleur-boot-emit inngest_ghcr_fallback warning "rc=$zot_rc" || true`
   `|| true` is load-bearing: `set -e` is live from `:1413`, and a missing binary (127) must not abort the boot.
   Foreground rather than backgrounded: see Phase 0. The no-endpoint path (`ZOT_EP` empty) gets no call site.
   `local.registry_endpoint` is a compile-time constant (`:1396-1398`), so that path cannot run, and if it ever did,
   the host-pinned soak denominator would read 0 and FAIL.
5. **Rewrite the comment at `:1420-1429`.** It currently says this host has no `soleur-boot-emit` and that the
   `[freshboot]` count is web-host-only. Both become false. It should say this host now has its own `soleur-boot-emit`,
   that the stage name is shared on purpose (the bare `[freshboot]` query covers both hosts), and that the Better Stack
   marker is kept as the second channel.

#### Phase 4: Soak tightening (fail-closed only)

1. `zot-soak-6122.sh` blocker corroboration: add
   ```bash
   _zot_reports_sentry_stage() {
     grep -qE '^[[:space:]]*soleur-boot-emit inngest_zot ' "$1" \
       && grep -qE '^[[:space:]]*soleur-boot-emit inngest_ghcr_fallback ' "$1"
   }
   ```
   and extend the condition at `:466` with `|| ! _zot_reports_sentry_stage "$INNGEST_CI"`. `_zot_path_in_code`,
   `_zot_reports_offbox`, `BLOCKER=6500`, the OPEN/CLOSED/`COMPLETED` arms and the FAIL token
   `blocker-closed-but-condition-unmet` stay byte-identical. The predicate is kept even though the denominator below is
   stronger evidence of a report *in the window*: the denominator cannot see a later revert of the call sites, and this
   predicate can. It is the #6500 close-condition-2 term in the same syntax-anchored form as its siblings.
2. A new denominator arm, placed right after the `APP_ZOT` arm (`:339`) and before the sample arm:
   `INNGEST_ZOT=$(sentry_count 'stage:"inngest_zot" host_name:"soleur-inngest"')`. The string guard comes before any
   arithmetic (the TRANSIENT-sentinel rule at `:311-321`). A hardcoded `== 0` gives
   `FAIL(no-inngest-freshboot-evidence)`, with no knob, for the reasons at `:326-333`. The message says a
   `soleur-inngest` fresh boot must happen inside `[START, END]` (an `inngest-host-replace` dispatch carrying this change),
   because otherwise the host was unobserved, not clean.
   **The denominator is host-pinned and `[freshboot]` stays bare.** The colocated web block (`cloud-init.yml:743`) is
   gated by `web_colocate_inngest`, not deleted. A web host born with it on would emit `inngest_zot` and satisfy a bare
   denominator while the dedicated host never reported, which is a false PASS on the gate that authorizes the revoke. A
   filter on a denominator can only fail closed (a wrong value reads 0 and FAILs), and a bare FAIL query can only add
   failures. This is an AND of two tag terms, not a prefixed `stage:` value, so the bare-stage rule at
   `zot-soak-6122.sh:44-52` still holds.
3. Prose-only updates to the soak's comments: the header note (`:92-110`) and the trailer (`:470-477`) now say the host
   reports on Sentry, with the Better Stack read kept as a second opinion. The PASS line (`:479`) names the `INNGEST_ZOT`
   count.
4. `FAIL_QUERIES` and its `!= 5` cardinality floor are **unchanged**, so the op-contract parity pinned by
   `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` (alarm size == soak FAIL-set size == 5)
   stays intact.

#### Phase 5: Architecture record

1. **ADR-096**: add `## Amendment 2026-09-21 (#6500) — the inngest pull outcome reaches the Sentry stage: schema, by BAKE`
   after the 2026-08-13 amendment (`ADR-096-…md:1045`). Keep it to about 10-15 lines, covering:
   - the bake-not-Doppler decision and its reason (the `soleur-inngest/prd` identity check);
   - the host-local `soleur-boot-emit`, and the host-pinned soak denominator;
   - the **new coupling**: rotating `SENTRY_DSN` in `prd_terraform` changes this host's user_data, so a DSN rotation
     force-replaces the sole scheduler at its next `hcloud_server.inngest` apply. Web hosts avoid this through
     `ignore_changes=[user_data]` (`server.tf:467`), which this host deliberately lacks;
   - what it does NOT do: close #6500 or authorize 5.3;
   - an explicit **supersession pointer** for the 2026-08-13 amendment's "What this does and does NOT do" bullet
     (`ADR-096-…md:1104-1113`: "zero `soleur-boot-emit` occurrences", "Routing these markers to Sentry … was
     deliberately cut", "a live gap"), plus a one-line pointer next to that bullet, so the two amendments do not
     contradict each other. The earlier cut was a #7516 scope decision, not a design objection. The Phase-3 residuals
     line at `:343` ("structurally blind") gets the same pointer.
2. **C4** (`knowledge-base/engineering/architecture/diagrams/model.c4`): add an `inngest -> sentry` edge next to
   `inngest -> betterstack` (`:620`), described as "Fresh-boot bootstrap-pull outcome (stage inngest_zot /
   inngest_ghcr_fallback, host_name soleur-inngest) POSTed to the Sentry store API with the baked ${sentry_dsn}; no
   Doppler dependency". **Also rewrite the comment block at `model.c4:712-722`.** It says "Deliberately NO
   `inngest -> sentry` edge" (the #4273 Vector-sink pivot). It must now say that the *Vector sink* stays on Better
   Stack while the *boot emitter* POSTs to Sentry, and the "Three emitters" count at `:712` becomes four.
   `views.c4:51-54` already includes both endpoints. Run
   `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

<!-- lint-infra-ignore start: this section names an IaC workflow_dispatch (terraform via apply-web-platform-infra.yml) and its timing; it prescribes no manual provisioning -->
#### Phase 6: Rollout (post-merge, maintenance window, IaC dispatch)

- **Merge does not touch the host.** The push-triggered apply is an explicit `-target=` allow-list that contains no
  `hcloud_server.*` (`inngest-host.tf:292-298`), so merging never plans `hcloud_server.inngest`.
- **Delivery.** `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='<why>'`,
  inside an ADR-100 maintenance window, following `## Downtime & Cutover` below. The `inngest_host_replace` job reads
  **no** `confirm` input and has no reviewer environment (`apply-web-platform-infra.yml:127`, `:1850-2080`), so the
  dispatch itself is the authorization. It runs a stock preflight and the inherited-`done` warning step. That job is the scoped `-replace` that keeps the Redis AOF volume and shares the
  `deploy-inngest-restart` mutex (`apply-web-platform-infra.yml:1842-1870`). Do NOT use `apply_target=inngest-host`: it
  is additive-only and correctly aborts (`:1807`). A replace delivers **everything** on `main` that touches
  `cloud-init-inngest.yml`, not just this PR. The job's printed plan summary is the review point.
- **The gap between merge and window.**
  - *Prevention:* no automated path plans the server. The per-merge apply is `-target`-scoped as noted above. The
    `inngest-host` job refuses `server_touched`. The only untargeted apply is the operator-local
    `OPERATOR_APPLIED_EXCLUSIONS` full apply (`apply-web-platform-infra.yml:2444`), whose plan the ADR-096 apply-path
    ruling already requires reviewing.
  - *Detection, stated honestly:* no automated detector singles out this pending replace. The daily untargeted
    `scheduled-terraform-drift.yml` plan already exits non-zero on every run (#7904, cited at its `:1561`), so it reminds
    no one, and this plan does not claim it does. What does exist: (a) an unplanned replace is visible **after the
    fact** through the new host's Better Stack `runcmd-entered` marker and its Sentry `inngest_zot` event; (b) the owed
    window is tracked by the soak itself, because once `ZOT_SOAK_START` is pinned, `zot-soak-6122.sh` FAILs
    `no-inngest-freshboot-evidence` on every sweep until a replace carrying this change lands inside the window; (c) the
    PR body states that delivery requires an `inngest-host-replace` window.
  - This is not new exposure: every `cloud-init-inngest.yml` edit since ADR-100 has had the same property, and the
    replace dispatch is the documented delivery path.
- **Rollback.** A second `inngest-host-replace` dispatched with `--ref` set to a branch or tag carrying the prior
  `cloud-init-inngest.yml` (a dispatch cannot target a bare SHA; it also runs that ref's workflow file). It needs a
  second window and strands the scheduler the same way (see Downtime & Cutover). It does **not** recover a zot miss:
  the GHCR leg 401s on either code, so a zot outage fails the boot regardless of this PR.
- **Post-replace verification (no SSH).** Read `stage:"inngest_zot" host_name:"soleur-inngest"` (or
  `inngest_ghcr_fallback`) in Sentry inside the window, and cross-check the Better Stack marker with
  `scripts/betterstack-query.sh --grep inngest_zot`. Both reads need credentials, and local Doppler is currently locked,
  so these are post-merge steps, not planning blockers.
<!-- lint-infra-ignore end -->

## Downtime & Cutover

- **Offline-inducing operation.** Force-replacing `hcloud_server.inngest` (any `cloud-init-inngest.yml` user_data
  change) takes down the **sole Inngest scheduler**: cron functions and app-dispatched background jobs.
- **Zero-downtime evaluated, and not available.**
  - **Blue-green is ruled out by ADR-100.** It is a single-host singleton. Two schedulers would fire every cron twice,
    and the Redis AOF volume attaches to one server.
  - **Rolling does not apply** to a singleton.
  - **State-only re-address does not deliver user_data.**
  - ADR-100 already records that every `cloud-init-inngest.yml` change implies a cron-outage window.
- **Accepted: a bounded maintenance window.** The window runs from destroy through first-boot `runcmd` to
  `inngest-server` bind. Crons due inside the gap fire **zero** times, not late. This PR adds at most about 16 s (8 s emit + 8 s failure phone-home) to
  that window, and only when Sentry is unreachable.
- **Known way a replace strands the scheduler** (`runbooks/inngest-server.md` § "Inherited `done` after a host
  replace (#7228)"). If Doppler `soleur-inngest/prd` `INNGEST_CUTOVER_FLIP=done`, every replace leaves
  `inngest-server` refusing to start (76 min with no scheduler on 2026-09-17). Before dispatching:
  1. Read the flag state without credentials leaving CI. The job's inherited-`done` warning step reports it.
  2. If the flag is `armed` or `flipping`, do **not** replace. These states have no one-dispatch recovery.
  3. If it is `done`, plan the `cutover-inngest.yml op=resume` recovery, which waits on a required reviewer, into the
     same window.
- **Per-stage verification.** Check each stage without SSH:
  1. The job's plan summary shows only the scoped recreate.
  2. The Better Stack `runcmd-entered` marker.
  3. The Sentry `stage:"inngest_zot" host_name:"soleur-inngest"` event.
  4. The existing inngest liveness probes are green.
- **Rollback.** See Phase 6.
- **Sign-off.** The window is an operator-scheduled act (PM1). Nothing in this PR dispatches it.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Add `SENTRY_DSN` to Doppler `soleur-inngest/prd` and read it at boot | It trips the exact-equality isolation check (`n_total -ne n_inngest` goes FATAL: no boot) unless the regex, the `-lt 5` floor and the "5 dark / 7 live" comments all move together. It gains nothing over the bake. |
| Make `inngest-boot-phone-home.sh` dual-ship to Sentry | That script `exit 0`s early when the Better Stack token is missing (`:306-314`), so a Better Stack failure would also silence Sentry. |
| Extract the web emitter into one shared file used by both hosts | It changes the web host-script bundle, its heredoc extractor (`doppler-download-error-channel.test.sh:35`) and 20+ web emitter tests. |
| Name the inngest emitter differently | The soak predicate, the "after #6500" test fixture (`zot-soak-6122.test.sh:109`) and #6500's own close text all key on `soleur-boot-emit`. |
| Bake the DSN into the emitter body (0700) | Viable, and suggested in review. Not chosen: `inngest-redact.sh` must enumerate the value, and reading one 0600 `/etc/default` file (with `sed`, never sourced) serves both consumers without parsing a script. Same trust boundary as `soleur-zot-read`. |
| Background the call sites (`… &`) to keep the emit off the boot path | This was the first-draft choice, reversed at deepen time. `cloud-final.service` uses the default `KillMode=control-group` (no `KillMode` line upstream), the fallback arm `exit`s seconds after the emit, and orphan survival could not be established. Foreground with a curl bound (about 16 s worst case) is deterministic. |
| Add a Better Stack `sentry-emit-FAILED` / fallback-count cross-check arm to the soak | A lost fallback emit coincides with a failed boot: the GHCR leg 401s since AP-016 lapsed, so the scheduler is down and the existing inngest liveness probes page. Adding a Better Stack read to the soak needs new sweeper secrets and widens this PR. It is recorded as a residual: the soak trailer keeps its instruction to read Better Stack before 5.3. |
| Stage the DSN in `/run` (tmpfs) from runcmd | The first draft did this. Cut in review: cloud-init already persists the rendered user_data under `/var/lib/cloud/instance/`, so tmpfs bought no at-rest property, and it cost a runcmd item. |
| An `else` arm emitting on an empty zot endpoint | The endpoint is a compile-time constant (`:1396-1398`), so the arm is unreachable. The host-pinned denominator fails closed on that path anyway. |
| Hard-fail `inngest-host-replace` on an empty `SENTRY_DSN` (the ADR-128 R1 web precedent) | That job is also the LUKS-recut recovery route (`apply-web-platform-infra.yml:2379-2438`). A hard fail would block an emergency recovery over a value the boot does not need. Recorded as Taste T2 in `decision-challenges.md`. |

## User-Brand Impact

- **If this lands broken, the user experiences:** at the next `inngest-host-replace`, the sole Inngest scheduler fails
  to boot, and every scheduled cron and app-dispatched background job (email triage, reminders, KB sync) stops until a
  rollback replace. That is the only user-facing failure mode, and P2 exists to prevent it: every call site is a
  foreground `… || true` (it cannot fail the boot, and it adds at most about 16 s, only when Sentry is unreachable),
  and the emitter is `set +e`, always exits 0, and has a curl-bounded runtime (G1 rows 3a/3b, G3).
- **If this leaks, the user's workflow is exposed via:** a leaked Sentry DSN lets a third party inject junk events into
  the web-platform Sentry project (the key is ingest-only). No user data is involved. The DSN is already semi-public (it
  ships in the client JS bundle, per `variables.tf:556`).
- **Brand-survival threshold:** `aggregate pattern`. A soak defect could authorize the irreversible PAT revoke on a false
  PASS. This PR only tightens the soak, and the tightening is guarded by G6.

## Observability

```yaml
liveness_signal:
  what: "Sentry event stage:inngest_zot host_name:soleur-inngest (info) on every zot-served fresh boot of the dedicated host; counted by zot-soak-6122.sh's new INNGEST_ZOT denominator"
  cadence: "per fresh boot of hcloud_server.inngest (each inngest-host-replace dispatch)"
  alert_target: "zot-soak-6122.sh FAIL(no-inngest-freshboot-evidence) posted by scripts/sweep-followthroughs.sh when the window holds no such event"
  configured_in: "apps/web-platform/infra/cloud-init-inngest.yml (pull block call sites + soleur-boot-emit write_files); scripts/followthroughs/zot-soak-6122.sh"

error_reporting:
  destination: "Sentry web-platform project via the baked ${sentry_dsn} (var.sentry_dsn); fallback channel Better Stack source 2457081 via inngest-boot-phone-home.sh"
  fail_loud: "stage:inngest_ghcr_fallback (warning) pages through sentry_alert.zot_mirror_fallback_rate (value = 0); an emit failure or empty DSN phones home SOLEUR_INNGEST_BOOT_STAGE stage=sentry-emit-FAILED rc=<n|nodsn>"

failure_modes:
  - mode: "zot miss on fresh boot (GHCR fallback, which 401s since AP-016 lapsed)"
    detection: "Sentry monitor sentry_alert.zot_mirror_fallback_rate (stage eq inngest_ghcr_fallback, value = 0) + Better Stack phone-home inngest_ghcr_fallback + oci-pull-ALL-LEGS-FAILED"
    alert_route: "Sentry monitor zot_mirror_fallback_rate email to issue owners; zot-soak [freshboot] FAIL; the boot then fails (GHCR 401), which also trips the existing inngest liveness heartbeat (INNGEST_HEARTBEAT_URL)"
  - mode: "Sentry POST fails (egress, 4xx, timeout)"
    detection: "soleur-boot-emit curl rc != 0, then Better Stack phone-home stage=sentry-emit-FAILED rc=<n>; if that POST also fails, vector (layer 3) ships journald tag inngest-boot-phone-home SOLEUR_INNGEST_BOOT_TRACE_LOST"
    alert_route: "the zot-soak INNGEST_ZOT denominator stays 0 and FAILs closed (sweeper comment on #6122's tracker); Better Stack markers are the diagnosis channel, not a pager"
  - mode: "TF_VAR_sentry_dsn empty at render"
    detection: "Better Stack phone-home stage=sentry-emit-FAILED rc=nodsn (or rc=baddsn for a malformed value)"
    alert_route: "zot-soak FAIL(no-inngest-freshboot-evidence)"
  - mode: "emitter binary missing (write_files failed)"
    detection: "the foreground '|| true' call site absorbs rc 127 and the boot continues; no Sentry event; soak denominator 0"
    alert_route: "zot-soak FAIL(no-inngest-freshboot-evidence); Sentry monitor zot_mirror_fallback_rate stays silent, so the denominator is the only detector for this mode"

logs:
  where: "Sentry issue stream (tags stage/host_id/region/host_name/detail); Better Stack source 2457081 (SOLEUR_INNGEST_BOOT_STAGE); on-host /var/log/cloud-init-output.log (not shipped)"
  retention: "Sentry project retention (90 d); Better Stack source retention"

discoverability_test:
  command: "grep -cE '^[[:space:]]*soleur-boot-emit inngest_(zot|ghcr_fallback) ' apps/web-platform/infra/cloud-init-inngest.yml"
  expected_output: "2"
```

## Encryption Posture

```yaml
at_rest:
  - store: "/etc/default/soleur-sentry-dsn on hcloud_server.inngest (root disk, 0600 root:root)"
    mechanism: plaintext-exception
    evidence: "apps/web-platform/infra/cloud-init-inngest.yml write_files '/etc/default/soleur-sentry-dsn' permissions '0600'; same shape as /etc/default/soleur-zot-read (:1138). cloud-init also persists the rendered user_data (with the DSN) under /var/lib/cloud/instance/, root-only, as for every other baked credential on this host"
    defends_against: "a file-read primitive held by a non-root account (0600 root)"
    does_not_defend: "anyone with host access reading Hetzner user_data through the metadata API (cloud-init-inngest.yml:1125 records it as retrievable by anyone with host access, not only root); code execution as root reading /var/lib/cloud/instance/; the brief window in which cloud-init write_files creates the file before applying 0600; an image of the unencrypted root disk. All of these already expose more sensitive baked credentials (doppler token, zot pull token, GHCR read token)"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:deny-all-public host with no SSH; verified by the rendered-template tests (G1, G4) instead"
in_transit:
  - connection: "hcloud_server.inngest -> Sentry ingest (https://<dsn host>/api/<project>/store/)"
    enforced_at: "apps/web-platform/infra/cloud-init-inngest.yml soleur-boot-emit write_files body (curl https:// with no -k/--insecure)"
    tls: "HTTPS, TLS 1.2+ (curl default negotiation against Sentry ingest)"
    cert_verification: on
    does_not_defend: "a compromised Sentry ingest endpoint; the event body is not signed; the DSN key authorizes event injection by anyone who holds it"
    disclosed_as: not-publicly-claimed
exception:
  justification: "The Sentry DSN is an ingest-only, semi-public credential (it already ships in the web client JS bundle). It cannot be encrypted at rest on this host because its durable source, Hetzner user_data, is plaintext by construction, as with every other baked credential here."
  tracking_issue: "#6500"
  reevaluate_when: "the host gains a non-root metadata-endpoint drop (the git-data #7772 pattern), or a Sentry key is issued with a scope wider than ingest"
  expires_on: "2026-12-20"
```

## Guard Contract

Every mutation row below was written by the plan author. Per
`knowledge-base/project/learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`,
a self-graded battery is evidence about its author's imagination. The review phase must add **independently chosen**
mutations as the control, and the harness rows below exist so a vacuous harness cannot pass silently.

### Guard 1 — inngest pull-outcome arms emit on the Sentry stage schema

**Property.** On the dedicated host, each of the two zot-leg outcome arms (served, missed) calls `soleur-boot-emit` exactly once, in the foreground and guarded by `|| true`, in the exact anchored form, with its own stage (`inngest_zot` info in the served arm, `inngest_ghcr_fallback` warning in the missed arm). The emitter's `HOST_NAME` literal equals the soak denominator's `host_name:` value, the DSN file is `0600`, and the template receives `sentry_dsn`.

**Assembly.** The chokepoint is the zot `if` block inside the pull runcmd item of `cloud-init-inngest.yml`, the only place `ZOT_LEG` is assigned. It is split by a new **per-arm extractor** at `[ "$zot_rc" -eq 0 ]` / `else` / `fi` into two comment-stripped arm files, each with a line-count floor. Supporting members: the two `write_files` entries (`/etc/default/soleur-sentry-dsn`, `/usr/local/bin/soleur-boot-emit`), the `sentry_dsn` key in the `inngest-host.tf` templatefile map, and the `host_name:` literal in `zot-soak-6122.sh`. Rows 1-8 and 11-13 run in `cloud-init-inngest-zot-pull-mutation.test.sh`. Row 9 is proven by `inngest-boot-emitter.test.sh`'s key-set parity arm. Row 10 is proven by `zot-soak-6122.test.sh`, the only suite that sees both files.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `soleur-boot-emit inngest_zot info …` call from the served arm | RED |
| 2 | Delete the `soleur-boot-emit inngest_ghcr_fallback warning …` call from the missed arm | RED |
| 3a | Strip `|| true` from the served-arm call | RED |
| 3b | Strip `|| true` from the missed-arm call | RED |
| 4 | Move the served-arm call into the missed arm (both calls then sit in one arm) | RED (per-arm placement assertion) |
| 5 | Add a second `soleur-boot-emit inngest_zot info` in the served arm after a compliant first | RED (exactly-one-per-arm count) |
| 6 | Rename the stage to `inngest_zot_ok` | RED |
| 7 | Write the call as `/usr/local/bin/soleur-boot-emit inngest_zot …` (this file's usual absolute-path convention) | RED (misses the soak anchor) |
| 8 | Double the space between `soleur-boot-emit` and the stage | RED (misses the soak anchor) |
| 9 | Remove `sentry_dsn = var.sentry_dsn` from the `inngest-host.tf` map | RED (render fails; the parity arm names the key) |
| 10 | Change the emitter's `HOST_NAME` literal to `soleur-inngest-1` (the soak query unchanged) | RED |
| 11 | Change `/etc/default/soleur-sentry-dsn` permissions to `0644` | RED |
| 12 | Dispatch: the per-arm extractor returns an empty arm file (anchor drifted) | RED (harness abort, never PASS) |
| 13 | Harness row: the mutation sed matches nothing, so the landed-diff check fires | HARNESS ABORT |

### Guard 2 — the inngest event has the web emitter's shape

**Property.** A POST the rendered inngest emitter makes carries the message `soleur-cloud-init boot stage`, the given `level`, and exactly the tag key set `{stage, host_id, region, host_name, detail}` with `region = "cloud-init"` and `host_name = "soleur-inngest"`. This is the shape the web `soleur-boot-emit` produces (`soleur-host-bootstrap.sh:356`), and every Sentry consumer (the soak queries, `zot_mirror_fallback_rate`) keys on it.

**Assembly.** The `-d` body the stub `curl` records in G3 case 1, parsed with `jq`. It is produced only by the single `BODY=$(printf …)` line of the rendered `/usr/local/bin/soleur-boot-emit` body. Rows run in-suite in `inngest-boot-emitter.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `"region":"cloud-init"` in the inngest body | RED |
| 2 | Drop the `host_name` key | RED |
| 3 | Add an extra tag key (`"shipper":"x"`) | RED (the key set is asserted exactly, not as a subset) |
| 4 | Put a Terraform directive (`%{`) or `${` into the `BODY` line, so the rendered bytes differ from the raw bytes | RED (the case asserts the rendered `BODY` line equals the raw one) |
| 5 | Dispatch: the stub recorded no body on the DSN-present case | RED |
| 6 | Must-PASS regression check (next to rows 1-3 as positive controls): `level = warning` with `detail = rc=7` | PASS |

### Guard 3 — the emitter is best-effort, bounded and non-leaking

**Property.** Run on its own under any condition (DSN missing, empty, malformed or present; curl failing or succeeding), the rendered `soleur-boot-emit` exits 0. It POSTs at most one event, and only when a well-formed DSN is present. It reports every non-delivery to the phone-home seam with a numeric, `nodsn` or `baddsn` reason. It carries its curl time bounds. It never writes the DSN or its key to stdout, stderr or process argv.

**Assembly.** The rendered `write_files` body, driven in `inngest-boot-emitter.test.sh` with:
- a stub `curl` on PATH that records argv, stdin and body, and exits with a configurable code;
- `SOLEUR_SENTRY_DSN_FILE` pointing at a fixture file;
- `SOLEUR_INNGEST_PHONE_HOME` pointing at a recording stub that **exits 3**, so a removed wrapper surfaces as a non-zero exit instead of an equivalent mutant.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the final `exit 0` / the `( … ) || true` wrapper, then run with stub curl exiting 7 (the phone-home stub exits 3) | RED (non-zero exit) |
| 2 | Pass the auth header on argv (`-H "X-Sentry-Auth: …$KEY"`) instead of `-K -` | RED (key found in recorded argv) |
| 3 | Add `echo "$DSN" >&2` | RED (DSN in captured stderr) |
| 4 | Remove `--connect-timeout`, `--max-time` or `--retry-max-time` from the curl line | RED (recorded argv lacks the bound) |
| 5 | Remove the `sentry-emit-FAILED` phone-home on curl rc 7 | RED |
| 6 | Remove the `rc=nodsn` phone-home on an empty DSN file | RED |
| 7 | Remove the DSN shape check, then run with fixture DSN `https://a"b@h/1` or a DSN with no `@` | RED (curl invoked; the fixture reaches recorded argv or stdin config) |
| 8 | Replace the `sed` read with `. "$f"`, then run with fixture `SOLEUR_SENTRY_DSN='x';touch $SENTINEL;'` | RED (the sentinel file exists) |
| 9 | Dispatch: the extracted emitter body is empty, or the stub curl was never invoked on the well-formed-DSN case | RED |
| 10 | Must-PASS: DSN file absent, so exit 0, zero curl invocations, one `rc=nodsn` phone-home, no stdout | PASS |

### Guard 4 — the DSN is in `inngest-redact.sh`'s explicit enumeration

**Property.** `inngest-redact.sh` replaces the literal DSN value and its key by value, without relying on the `[0-9a-f]{32,}` / `[A-Za-z0-9_+/-]{40,}` pattern backstop, and it reads the DSN file without executing it.

**Assembly.** The `vals+=` enumeration block of the **rendered** `inngest-redact.sh` `write_files` body (`cloud-init-inngest.yml:342-363`). It is the only value list feeding every shipped log tail (`zot_tail`, `pull_tail`, `boot_tail`, `unit_journal`). Driven in `inngest-boot-emitter.test.sh`, the suite that owns the render, with `SOLEUR_SENTRY_DSN_FILE` pointing at a fixture whose DSN is `https://pubKEYx7@o1.ingest.invalid/42`, a short non-hex key the backstop cannot catch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the Sentry DSN enumeration line | RED (fixture DSN survives in the output) |
| 2 | Enumerate the DSN but not its key | RED (a tail holding only `pubKEYx7` survives) |
| 3 | Point the line at a path neither `write_files` nor the seam writes (`/run/soleur-sentry-dsn`) | RED |
| 4 | Replace the `sed` read with sourcing | RED (sentinel fixture as in G3 row 8) |
| 5 | Dispatch: the redact-body extractor returns empty | RED |
| 6 | Must-PASS regression check (next to rows 1-2 as positive controls): a tail with no secret passes through byte-identical | PASS |

### Guard 6 — the soak cannot PASS without host-pinned Sentry evidence and the anchored call sites

**Property.** `zot-soak-6122.sh` exits 0 only if Sentry holds at least one `stage:"inngest_zot" host_name:"soleur-inngest"` event in `[START, END]`, AND `cloud-init-inngest.yml` carries both anchored `soleur-boot-emit inngest_zot` and `soleur-boot-emit inngest_ghcr_fallback` call sites. Every pre-existing arm and predicate stays byte-identical. The event is unauthenticated evidence (see P5), not proof.

**Assembly.** The soak's exit-0 path is its last line, reachable only by passing the `FAIL_QUERIES` loop, the `APP_ZOT` arm, the new `INNGEST_ZOT` arm, the sample arm, the blocker `OPEN`/`COMPLETED` arms and the corroboration `if`. The chokepoint is the new denominator plus the corroboration `if`. Driven by `zot-soak-6122.test.sh`'s PATH-stubbed `curl`/`gh` (substring keys, first match wins, HTTP 500 on no match), `run_soak`'s new fixture-body parameter, and in-suite `sed` mutations of the relocated soak copy.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture carries only the Better Stack `inngest-boot-phone-home.sh inngest_zot` call (today's code), #6500 CLOSED/COMPLETED | RED (`blocker-closed-but-condition-unmet`) |
| 2 | Fixture carries `soleur-boot-emit inngest_zot` but not `inngest_ghcr_fallback` | RED |
| 3 | Fixture carries both calls only as `#` comment lines | RED |
| 4 | Stub returns `soleur-inngest=0` with everything else passing | RED (`no-inngest-freshboot-evidence`) |
| 5 | Stub returns HTTP 500 for the host-pinned query only | exit 2 (TRANSIENT), never 0 |
| 6 | Delete the `INNGEST_ZOT` arm from the relocated soak copy | RED (case 4 turns PASS, so the suite fails) |
| 7 | Remove `_zot_reports_sentry_stage` from the corroboration `if` in the relocated copy | RED (case 1 turns PASS) |
| 8 | Stub spec `soleur-inngest=0;inngest_zot=1` (a colocated web host reported, the dedicated host did not); this is also the discriminator for a dropped `host_name:` filter | RED (`no-inngest-freshboot-evidence`) |
| 9 | Must-PASS: fixed fixture with both calls, #6500 CLOSED/COMPLETED, `soleur-inngest=1` | exit 0 |
| 10 | Harness row: the stub does not shadow the real `curl`/`gh` (existing resolve assertion at `:129-135`) | HARNESS ABORT |

**Anchor.** `BLOCKER=6500` reads live issue state. Closing #6500 is an operator authorization act that no diff can perform.

(Guard numbering skips 5. The first draft's Guard 5, a permanent exact-value pin of the isolation regex, was cut in review: AC3 proves this PR leaves the regex alone, and the existing fragment pins at `inngest-host.test.sh:199-204` remain.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC0: every new call site is foreground, ending in `|| true`: `grep -cE '^[[:space:]]*soleur-boot-emit inngest_(zot|ghcr_fallback) .*\|\| true$' apps/web-platform/infra/cloud-init-inngest.yml` prints `2`. No line has the form `soleur-boot-emit … &`.
- [x] AC1: `grep -cE '^[[:space:]]*soleur-boot-emit inngest_(zot|ghcr_fallback) ' apps/web-platform/infra/cloud-init-inngest.yml` prints `2`.
- [x] AC2: `inngest-host.tf`'s templatefile map carries `sentry_dsn = var.sentry_dsn`. `git diff origin/main -- apps/web-platform/infra/variables.tf` is empty (no new root variable).
- [x] AC3: `git diff origin/main -- apps/web-platform/infra/cloud-init-inngest.yml | grep -E '^[-+].*(n_inngest|n_total|BETTERSTACK_LOGS_TOKEN\)\$)'` is empty (the isolation lines are untouched).
- [x] AC4: `git diff origin/main -- apps/web-platform/infra/soleur-host-bootstrap.sh apps/web-platform/infra/sentry/` is empty (no web emitter or alert change).
- [x] AC5: G4 passes: `inngest-redact.sh` enumerates the DSN and its key explicitly, and no consumer sources the DSN file. `grep -nE '(^|;)[[:space:]]*\.[[:space:]]+("?\$(f|sf)"?|[^ ;]*soleur-sentry-dsn)' apps/web-platform/infra/cloud-init-inngest.yml` prints nothing.
- [x] AC6: the soak's pre-existing guards are byte-identical. Each of these prints nothing:
  `diff <(git show origin/main:scripts/followthroughs/zot-soak-6122.sh | sed -n '/^_zot_path_in_code() {/,/^}/p;/^_zot_reports_offbox() {/,/^}/p;/^declare -A FAIL_QUERIES=(/,/^)/p;/FAIL_QUERIES\[@\]} != 5/p;/^BLOCKER=/p') <(sed -n '/^_zot_path_in_code() {/,/^}/p;/^_zot_reports_offbox() {/,/^}/p;/^declare -A FAIL_QUERIES=(/,/^)/p;/FAIL_QUERIES\[@\]} != 5/p;/^BLOCKER=/p' scripts/followthroughs/zot-soak-6122.sh)`,
  with the extracted text non-empty on both sides.
- [x] AC7: every Guard 1, 2, 3, 4 and 6 mutation row is executed by the suite its Assembly names, and goes RED (or HARNESS ABORT or TRANSIENT where stated). Every must-PASS row passes. The suites are `inngest-boot-emitter.test.sh` (G2, G3, G4, G1 row 9), `cloud-init-inngest-bootstrap.test.sh` with its battery `cloud-init-inngest-zot-pull-mutation.test.sh` (G1 rows 1-8 and 11-13), all registered in `infra-validation.yml`, and `scripts/followthroughs/zot-soak-6122.test.sh` (G6 and G1 row 10; `scripts/test-all.sh:2076`). `inngest-boot-emitter.test.sh`'s key-count bounds read 18.
- [x] AC8: `bash apps/web-platform/infra/inngest-userdata-budget.sh` passes, and the stored-payload delta against `origin/main` is recorded in the PR body (expected well under 1 KB against 21,876 B of headroom).
- [x] AC9: `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` are green, and `model.c4` has an `inngest -> sentry` edge.
- [x] AC10: ADR-096 has the `Amendment 2026-09-21 (#6500)` section, including the DSN-rotation coupling and supersession pointers at the 2026-08-13 bullet and at `:343`. `model.c4`'s "Deliberately NO `inngest -> sentry` edge" comment is rewritten (`grep -c 'Deliberately NO .inngest -> sentry. edge' knowledge-base/engineering/architecture/diagrams/model.c4` prints `0`).
- [ ] AC11: the PR body contains `Ref #6500` and no closing keyword for it. `gh pr view 8488 --json body --jq .body | grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?):? #6500'` prints `0`. The body must not put any closing verb (close/fix/resolve, in any tense) directly before `#6500`, not even in a negated sentence ("does not close #6500" still matches both this grep and GitHub's keyword parser). Write "leaves issue 6500 open" instead. An accidental auto-close would authorize the PAT revoke.
- [x] AC12: `terraform validate` in `apps/web-platform/infra` passes, and the existing size `lifecycle.precondition` on `hcloud_server.inngest` is byte-unchanged. (Review amendment: a SECOND precondition refusing a malformed `var.sentry_dsn` was added beside it.)

### Post-merge (operator window, not a merge blocker)

- [ ] PM1: `inngest-host-replace` dispatched in an ADR-100 maintenance window, after the `## Downtime & Cutover` pre-dispatch flag check (Phase 6). The job's plan shows only the scoped server recreate. `Automation: not feasible in-session because` the window is an operator-scheduled downtime of the sole scheduler (ADR-100). The dispatch itself is one `gh workflow run`.
- [ ] PM2: Sentry shows one `stage:inngest_zot` (or `inngest_ghcr_fallback`) event with `host_name:soleur-inngest` for that boot, Better Stack shows the matching `SOLEUR_INNGEST_BOOT_STAGE stage=inngest_zot` marker, and there is no `sentry-emit-FAILED` marker. This Better Stack corroboration is **required** before anyone posts `RESULT: PASS` on #6500, because the Sentry event alone is forgeable with the public DSN (P5).
  Runnable (an agent can execute it; `T0` = the replace dispatch time, UTC):
  ```bash
  T0=<dispatch UTC, 2026-..T..:..:..>; T1=<T0 + 60 min>
  doppler run -p soleur -c prd -- scripts/sentry-issue.sh --host-events soleur-inngest --stage inngest_zot --start "$T0" --end "$T1"            # PASS: >= 1 row
  doppler run -p soleur -c prd -- scripts/sentry-issue.sh --host-events soleur-inngest --stage inngest_ghcr_fallback --start "$T0" --end "$T1"  # expect 0 rows
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since "<T0 as YYYY-MM-DD HH:MM:SS>" \
    --grep 'stage=inngest_zot' --grep sentry-emit-FAILED --grep SOLEUR_INNGEST_BOOT_TRACE_LOST
  # PASS: >= 1 SOLEUR_INNGEST_BOOT_STAGE stage=inngest_zot, 0 sentry-emit-FAILED, 0 TRACE_LOST
  ```
  The soak is the 7-day gate, not the one-boot verifier: right after a replace it usually stops at
  its `MIN_SAMPLE` arm before printing the `INNGEST_ZOT` count.
- [ ] PM3: #6500 stays OPEN until an operator posts `RESULT: PASS`. This PR does not change that.
- [ ] PM4: after the replace, `zot-soak-6122.sh`'s `INNGEST_ZOT` count for the window is at least 1 once `ZOT_SOAK_START` is pinned (the pin itself is tracked on #6122).

## Test Scenarios

1. The rendered emitter, with a DSN present and a succeeding stub curl, makes one POST to `https://o1.ingest.invalid/api/42/store/`. The body has tags `stage=inngest_zot`, `region=cloud-init`, `host_name=soleur-inngest` and `detail=ep=10.0.1.30:5000`, the key `pubKEYx7` appears only on stdin, and the emitter exits 0 (G2, G3 rows 2 and 8).
2. The DSN file is missing or empty: exit 0, zero curl calls, one `sentry-emit-FAILED rc=nodsn` phone-home (G3 row 6).
   A malformed DSN (`https://a"b@h/1`, or no `@`): exit 0, zero curl calls, one `rc=baddsn` phone-home (G3 row 7).
   A DSN file containing a shell payload is read, not executed (G3 row 8, G4 row 4).
3. Stub curl exits 7: exit 0, and the phone-home stub receives `sentry-emit-FAILED "stage=inngest_ghcr_fallback rc=7"` (G3 row 5).
4. Redaction: a tail containing the fixture DSN, and separately its bare key, comes out with both replaced by `REDACTED` (G4).
5. The Guard 1 static and mutation rows (1-13, with 3a/3b).
6. The soak cases from Guard 6 (rows 1-10).
7. `inngest-boot-emitter.test.sh`'s key-set parity arm passes with `sentry_dsn` on both sides.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** (CTO domain leader, consulted at plan time.) This is an infrastructure and observability change on the
sole Inngest scheduler's first-boot path. It adds no vendor, secret store or Terraform variable. The risks:

- **Boot-path safety under a shared `set -e` shell.** Handled by foreground `|| true` call sites and a `set +e`,
  curl-bounded emitter.
- **Payload growth against the 32 KB cap.** About 21.8 KB of headroom.
- **Delivery requires a force-replace.** Handled by the scoped `inngest-host-replace` dispatch in a maintenance window.

The soak edits are fail-closed only. Four CTO findings were folded in: the host-pinned denominator, the corrected drift
claim, the DSN-rotation coupling recorded in the ADR, and the corrected at-rest evidence. The CTO also proposed an
empty-endpoint `else` arm. It was cut in review because the path is unreachable (see Alternatives).

No product, marketing, legal, finance, sales, support or operations implications. There is no user-facing surface and
no UI file in the edit lists.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/inngest-host.tf`: one new templatefile map key, `sentry_dsn = var.sentry_dsn`. There are no
  new resources, providers or variables. The sensitive input `TF_VAR_sentry_dsn` is already sourced from Doppler
  `prd_terraform` `SENTRY_DSN` for this root.

### Apply path

(c) Scoped force-replace through `apply_target=inngest-host-replace` (ADR-100 maintenance window). The gate preserves
the Redis AOF volume. The blast radius is one scheduler downtime window, as for every previous
`cloud-init-inngest.yml` delivery.

### Distinctness / drift safeguards

There is no `ignore_changes=[user_data]`, on purpose (`inngest-host.tf:461`). The DSN lands in `terraform.tfstate` (R2
backend) inside `user_data`, as the existing baked credentials do. A `SENTRY_DSN` rotation now force-replaces this
host (recorded in ADR-096).

### Vendor-tier reality check

No new Sentry resources. Event volume is at most one event per inngest-host fresh boot.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-096** (Phase 5.1). This extends its 2026-08-13 inngest-bake amendment, so it needs no new ADR ordinal.

### C4 views

Container view: add the relationship `inngest -> sentry`. It was checked against all three `.c4` files:

- **Actors:** none new. The founder is already paged via `sentry -> founder` (`model.c4:730`).
- **Systems:** `sentry` (`:407`), `betterstack` (`:400`) and `inngest` (`:264`) all exist.
- **Relationship:** `inngest -> sentry` is missing, and is added.

`views.c4:51-54` already includes both endpoints. The counts on the `github -> sentry` edge (`:728`) do not move.
`c4-count-parity.test.sh` must stay green.

### Sequencing

The amendment describes the state after the replace, marked "adopting — delivered at the next `inngest-host-replace`".

## Open Code-Review Overlap

None. Checked on 2026-09-21: `gh issue list --label code-review --state open` (the full open set) was matched against the issue bodies with `jq contains` for each planned path (`cloud-init-inngest.yml`, `inngest-host.tf`, `zot-soak-6122.sh`, the five test suites, `inngest-userdata-budget.sh`, ADR-096, `model.c4`). Zero matches.

## Plan Review Revisions

Review ran with a scoped advisor consult, the CTO domain leader, DHH, Kieran and code-simplicity. All changes below
are Mechanical unless marked otherwise. The two Taste items are in `decision-challenges.md`.

- **Denominator pinned to `host_name:"soleur-inngest"`** (advisor + CTO). The colocated web block is gated off, not
  deleted.
- **Call sites backgrounded** (advisor), then **reversed at deepen time**. Upstream `cloud-final.service` has no
  `KillMode` line, so the default `control-group` applies. The fallback arm exits within seconds (Kieran), and orphan
  survival could not be established. The final design is foreground `|| true` with a curl bound (see Phase 0).
- **Drift-detection claim corrected** (CTO). The untargeted drift plan is perpetually red (#7904).
- **DSN-rotation coupling** recorded in the ADR amendment (CTO).
- **Cut:** the `/run` staging item, `sentry-dsn-EMPTY` (folded into the emitter as `rc=nodsn`), the detail allowlist,
  `timeout 30`, the no-endpoint `else` arm, the cross-file byte-parity extractor (replaced by the G2 value assertion),
  the permanent isolation pin (Guard 5), and the timing-based behavioural pull-block row (DHH, simplicity, Kieran).
- **Kept against a simplicity suggestion:** `_zot_reports_sentry_stage`. It catches a revert of the call sites after
  in-window evidence exists, which the denominator cannot see.
- **Kieran corrections:**
  - a phone-home test seam;
  - one exact call-site form, bare name and single spaces, with RED rows for both deviations;
  - soak stub-spec updates for every case past `APP_ZOT`;
  - AC6 made mechanically checkable;
  - G6 renumbered;
  - a `%{`/`${` rendered-equals-raw row;
  - the `SECRET_LENGTHS` decision;
  - the "runcmd continues for minutes" claim corrected.

## Dependencies & Risks

- **A boot-path regression on the sole scheduler.** Mitigated by:
  - G1 rows 3a/3b and 7-8;
  - G3 (a foreground `|| true` call site, `set +e`, exit 0, curl bounded at 8 s with no retry, about 16 s worst case with the failure phone-home);
  - a planned window with a documented rollback (Phase 6).
- **A lost fallback emit.** Residual, accepted: a missed-arm boot fails anyway (the GHCR leg 401s), so the scheduler
  is down and the existing inngest liveness probes page. See Alternatives.
- **A forged Sentry event** can satisfy the denominator (the DSN is public). Mitigated by the required Better Stack
  corroboration in PM2 before `RESULT: PASS`.
- **The soak denominator blocks the soak until an inngest replace falls inside the window.** This is intended
  (fail-closed), and the FAIL message names the remedy. It is Taste T1.
- **An undelivered change bundle.** The replace delivers all of `main`'s `cloud-init-inngest.yml`. The job's plan
  summary is the review point.
- **Dependency:** a non-empty `TF_VAR_sentry_dsn` at dispatch time. An empty one is surfaced by `rc=nodsn` and by the
  denominator.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- Inside `cloud-init-inngest.yml`, a literal shell dollar-brace must be written `$${...}`, and `%{` is a Terraform
  directive. A bare `$VAR` renders literally. Every test seam here stays brace-free, as at `:277-281`.
- `local.inngest_rationale_strip` deletes whole-line `# ` comments, including inside `write_files` bodies. Do not depend
  on a comment line surviving.
- The `[freshboot]` query must stay a bare `stage:"…"` query. The denominator is an AND of `stage:"inngest_zot"` with
  `host_name:"soleur-inngest"`, not a prefixed stage value (`zot-soak-6122.sh:44-52`).
- The soak test stub matches keys as substrings, first match wins. Put `soleur-inngest=` before any `inngest_zot=` key.
- Run every AC grep with **GNU grep** (`/usr/bin/grep`), as CI does. On the planning workstation, `grep` resolves to
  ugrep 7.8.4, which returned 0 for AC5's grouped-alternation regex on inputs GNU grep matched (measured 2026-09-21).
  A green AC under ugrep is not evidence.
