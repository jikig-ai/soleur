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

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

The dedicated Inngest host (`hcloud_server.inngest`, 10.0.1.40) already pulls its bootstrap image zot-first with a
GHCR fallback (#7516, merged 2026-08-14), and it reports the outcome only to Better Stack. The GHCR-retirement soak
(`scripts/followthroughs/zot-soak-6122.sh`) counts fresh-boot outcomes from Sentry `stage:` tags, so it cannot see
this host. That is the only remaining technical half of #6500's close condition 2.

This plan adds a host-local, best-effort Sentry emitter to the inngest host. It is named `soleur-boot-emit`, takes
the same arguments as the web host's emitter and sends the same event body, and it is called on both pull-outcome
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
  foreground call site would need `|| true`. This plan goes further and backgrounds each call (`… >/dev/null 2>&1 &`), so
  the emit can neither fail nor delay the boot. The emitter must also never be asserted into existence under `set -e`
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
- P5: the soak cannot PASS unless the dedicated host has actually reported on Sentry (fail-closed), and nothing in it
  gets weaker.
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
           → soleur-boot-emit inngest_zot info "ep=$ZOT_EP" >/dev/null 2>&1 &              (NEW, Sentry)
  zot miss → inngest-boot-phone-home.sh inngest_ghcr_fallback ...  (Better Stack, unchanged)
           → soleur-boot-emit inngest_ghcr_fallback warning "rc=$zot_rc" >/dev/null 2>&1 &  (NEW, Sentry)

soleur-boot-emit <stage> [level] [detail]
  DSN from /etc/default/soleur-sentry-dsn (seam: SOLEUR_SENTRY_DSN_FILE)
    empty/missing → phone home sentry-emit-FAILED "stage=<s> rc=nodsn", exit 0
  body: message "soleur-cloud-init boot stage", tags {stage, host_id, region:"cloud-init", host_name:"soleur-inngest", detail}
  printf 'header = "X-Sentry-Auth: …sentry_key=%s"' | curl -K - -sf --max-time 8 --retry 2 --retry-max-time 20 …/store/
    rc != 0 → phone home sentry-emit-FAILED "stage=<s> rc=<n>"   (seam: SOLEUR_INNGEST_PHONE_HOME)
  always exit 0
```

### Implementation Phases

#### Phase 0: Verify the one runtime assumption

The call sites are backgrounded, and on the fallback arm the runcmd script reaches `exit "$pull_rc"` (`:1455`) within
seconds of the emit (the GHCR leg 401s because AP-016 lapsed). So the emit must outlive the script. That holds only if
`cloud-final.service` does not kill its control group when runcmd exits. Verify this against cloud-init's shipped unit
(upstream `systemd/cloud-final.service.tmpl`, expected `KillMode=process`) for the Ubuntu 24.04 cloud-init version on
this host, and record the line and version in the PR body. **If it is not `KillMode=process`, switch the two call sites
to foreground `… || true`.** The emitter's curl bound (at most about 28 s, and only when Sentry is unreachable) then
becomes boot latency. That is acceptable, and the G1 anchors are unchanged because the line still starts with
`soleur-boot-emit`.

#### Phase 1: Tests first (RED)

Write the Guard Contract assertions below before any product edit, and confirm each fails against `origin/main`:

1. `apps/web-platform/infra/inngest-boot-emitter.test.sh`: add `sentry_dsn="https://pubKEYx-7@o1.ingest.invalid/42"`
   to the hand-kept render map at `:222`. Its key-set parity arm then goes RED until `inngest-host.tf` threads the key,
   which is the intended tripwire. Add the G2 and G3 behavioural cases. These extract the rendered
   `/usr/local/bin/soleur-boot-emit` `write_files` body and run it with a stub `curl` on PATH (the stub records argv,
   stdin and the `-d` body to files) and `SOLEUR_INNGEST_PHONE_HOME` pointing at a recording stub. Call `curl` by bare
   name in the emitter so the PATH stub shadows it.
2. `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`: add a "Guard 1b" section after Guard 1, with the G1
   static assertions over the comment-stripped `DED_CODE_FILE` (`:685`) and the pull block `DED_BLOCK_FILE` (`:697`).
3. `apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh`: add the G1 mutation rows to the existing
   battery, using its landed-mutation diff contract.
4. `apps/web-platform/infra/inngest-host.test.sh`: add the G4 redaction cases. They extract the rendered
   `inngest-redact.sh` body and run it with the enumeration path redirected to a fixture file (brace-free seam, see
   Phase 3.3).
5. `scripts/followthroughs/zot-soak-6122.test.sh`:
   - add `soleur-inngest=1` as the **first** key of `$HEALTHY` (`:154`) and of every inline spec that reaches past the
     `APP_ZOT` arm, including `:201` (thin sample). The stub matches keys as substrings in order, first match wins, and
     returns HTTP 500 on no match. Without this, every case that passes `APP_ZOT` turns TRANSIENT instead of its
     expected verdict (the OPEN case at `:170`, thin sample at `:201`, unreadable at `:244`, the old fixture at `:259`).
     The key `soleur-inngest` matches only the host-pinned query.
   - update the "after #6500" fixture (`:103-111`) so it carries both Sentry call sites in the exact form Phase 3.4
     prescribes.
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
   `SOLEUR_SENTRY_DSN=${sentry_dsn}`. It is written at cloud-init's init stage, before runcmd, so it needs no runcmd
   item and has no ordering dependency. It is the same shape and trust boundary as `/etc/default/soleur-zot-read`.
2. **`write_files` `/usr/local/bin/soleur-boot-emit`** (`0755`, root:root), placed directly after `inngest-redact.sh`.
   Its body:
   - `#!/bin/sh`, then `( set +e … ) || true` and `exit 0`, following the web emitter's structure
     (`soleur-host-bootstrap.sh:296-363`).
   - Usage `soleur-boot-emit <stage> [info|warning|fatal] [detail]`. The first two positional arguments mean what they
     mean in the web emitter.
   - Seams, brace-free like `:277-281`: `f=/etc/default/soleur-sentry-dsn; [ -n "$SOLEUR_SENTRY_DSN_FILE" ] && f="$SOLEUR_SENTRY_DSN_FILE"`
     and `ph=/usr/local/bin/inngest-boot-phone-home.sh; [ -n "$SOLEUR_INNGEST_PHONE_HOME" ] && ph="$SOLEUR_INNGEST_PHONE_HOME"`.
   - `. "$f" 2>/dev/null`. Empty `SOLEUR_SENTRY_DSN`: `[ -x "$ph" ] && "$ph" sentry-emit-FAILED "stage=$STAGE rc=nodsn"`,
     then exit 0.
   - `KEY`/`SHOST`/`PROJ` parsed with the web emitter's three `sed -E` expressions (`soleur-host-bootstrap.sh:310-312`).
   - `HOST_ID` from `/var/lib/cloud/data/instance-id` with a `hostname` fallback. `HOST_NAME='soleur-inngest'` is a
     literal, because the soak denominator filters on it (G1 pins the two equal).
   - `BODY=$(printf '{"message":"soleur-cloud-init boot stage","level":"%s","tags":{"stage":"%s","host_id":"%s","region":"cloud-init","host_name":"%s","detail":"%s"}}' …)`.
     This is the web format at `soleur-host-bootstrap.sh:356`. It contains no `%{` and no `${`, so templatefile renders it
     byte-for-byte (G2 row 4 checks this).
   - `printf 'header = "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=%s"\n' "$KEY" | curl -K - -sf --max-time 8 --retry 2 --retry-max-time 20 -X POST "https://$SHOST/api/$PROJ/store/" -H 'Content-Type: application/json' -d "$BODY" >/dev/null 2>&1`.
     This is the git-data precedent (`cloud-init-git-data.yml:50-52`). Capture `crc`. If it is non-zero:
     `[ -x "$ph" ] && "$ph" sentry-emit-FAILED "stage=$STAGE rc=$crc"`. That is numeric only, per the #7228 rule that
     a silent emitter failure must land somewhere.
   - Comments in the body stay minimal (`local.inngest_rationale_strip` removes whole-line `# ` comments anyway;
     `#!/bin/sh` survives because `#` is followed by `!`).
3. **`inngest-redact.sh`** (`:342-363`): add an explicit enumeration line after the zot line (`:354`), with a
   brace-free seam for G4:
   `sf=/etc/default/soleur-sentry-dsn; [ -n "$SOLEUR_SENTRY_DSN_FILE" ] && sf="$SOLEUR_SENTRY_DSN_FILE"; . "$sf" 2>/dev/null; vals+=("$SOLEUR_SENTRY_DSN"); vals+=("$(printf %s "$SOLEUR_SENTRY_DSN" | sed -E 's#https://([^@]+)@.*#\1#')")`.
   That covers the whole DSN and its key. It must not rely on the `[0-9a-f]{32,}` / `{40,}` backstop. (A 6-byte
   minimum already skips empty values, per `:360`.)
4. **Call sites** in the pull block. Each is its own line, starts with the **bare** name `soleur-boot-emit`
   (not `/usr/local/bin/…`, which this file otherwise uses), has **exactly one space** between tokens, and is
   **backgrounded**. That keeps them matching the soak's `^[[:space:]]*soleur-boot-emit inngest_zot ` anchors and AC1:
   - zot arm, after `:1418`: `soleur-boot-emit inngest_zot info "ep=$ZOT_EP" >/dev/null 2>&1 &`
   - fallback arm, after `:1431`: `soleur-boot-emit inngest_ghcr_fallback warning "rc=$zot_rc" >/dev/null 2>&1 &`
   Backgrounded rather than `|| true` because `set -e` is live from `:1413` and an async list never returns non-zero,
   so a missing binary cannot abort the boot. It also keeps up to about 28 s of emit latency (only when Sentry is
   unreachable) off the sole scheduler's boot path. Phase 0 is the precondition. The no-endpoint path (`ZOT_EP` empty)
   gets no call site: `local.registry_endpoint` is a compile-time constant (`:1396-1398`), so that path cannot run, and
   if it ever did, the host-pinned soak denominator would read 0 and FAIL.
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
   - what it does NOT do: close #6500 or authorize 5.3.
2. **C4** (`knowledge-base/engineering/architecture/diagrams/model.c4`): add an `inngest -> sentry` edge next to
   `inngest -> betterstack` (`:620`), described as "Fresh-boot bootstrap-pull outcome (stage inngest_zot /
   inngest_ghcr_fallback, host_name soleur-inngest) POSTed to the Sentry store API with the baked ${sentry_dsn}; no
   Doppler dependency". `views.c4:51-54` already includes both endpoints. Run
   `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

<!-- lint-infra-ignore start: this section names an IaC workflow_dispatch (terraform via apply-web-platform-infra.yml) and its timing; it prescribes no manual provisioning -->
#### Phase 6: Rollout (post-merge, maintenance window, IaC dispatch)

- **Merge does not touch the host.** The push-triggered apply is an explicit `-target=` allow-list that contains no
  `hcloud_server.*` (`inngest-host.tf:292-298`), so merging never plans `hcloud_server.inngest`.
- **Delivery.** `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f confirm=<token from the job header>`,
  inside an ADR-100 maintenance window. That job is the scoped `-replace` that keeps the Redis AOF volume and shares the
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
- **Post-replace verification (no SSH).** Read `stage:"inngest_zot" host_name:"soleur-inngest"` (or
  `inngest_ghcr_fallback`) in Sentry inside the window, and cross-check the Better Stack marker with
  `scripts/betterstack-query.sh --grep inngest_zot`. Both reads need credentials, and local Doppler is currently locked,
  so these are post-merge steps, not planning blockers.
<!-- lint-infra-ignore end -->

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Add `SENTRY_DSN` to Doppler `soleur-inngest/prd` and read it at boot | It trips the exact-equality isolation check (`n_total -ne n_inngest` goes FATAL: no boot) unless the regex, the `-lt 5` floor and the "5 dark / 7 live" comments all move together. It gains nothing over the bake. |
| Make `inngest-boot-phone-home.sh` dual-ship to Sentry | That script `exit 0`s early when the Better Stack token is missing (`:306-314`), so a Better Stack failure would also silence Sentry. |
| Extract the web emitter into one shared file used by both hosts | It changes the web host-script bundle, its heredoc extractor (`doppler-download-error-channel.test.sh:35`) and 20+ web emitter tests. |
| Name the inngest emitter differently | The soak predicate, the "after #6500" test fixture (`zot-soak-6122.test.sh:109`) and #6500's own close text all key on `soleur-boot-emit`. |
| Bake the DSN into the emitter body (0700) | Viable, and suggested in review. Not chosen: `inngest-redact.sh` must enumerate the value, and sourcing one 0600 `/etc/default` file serves both consumers without parsing a script. Same trust boundary as `soleur-zot-read`. |
| Stage the DSN in `/run` (tmpfs) from runcmd | The first draft did this. Cut in review: cloud-init already persists the rendered user_data under `/var/lib/cloud/instance/`, so tmpfs bought no at-rest property, and it cost a runcmd item. |
| An `else` arm emitting on an empty zot endpoint | The endpoint is a compile-time constant (`:1396-1398`), so the arm is unreachable. The host-pinned denominator fails closed on that path anyway. |
| Hard-fail `inngest-host-replace` on an empty `SENTRY_DSN` (the ADR-128 R1 web precedent) | That job is also the LUKS-recut recovery route (`apply-web-platform-infra.yml:2379-2438`). A hard fail would block an emergency recovery over a value the boot does not need. Recorded as Taste T2 in `decision-challenges.md`. |

## User-Brand Impact

- **If this lands broken, the user experiences:** at the next `inngest-host-replace`, the sole Inngest scheduler fails
  to boot, and every scheduled cron and app-dispatched background job (email triage, reminders, KB sync) stops until a
  rollback replace. That is the only user-facing failure mode, and P2 exists to prevent it: every call site is
  backgrounded (it cannot fail the boot, and it adds no latency), and the emitter is `set +e`, always exits 0, and has a
  curl-bounded runtime (G1 rows 3 and 9, G3).
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
    detection: "Sentry stage:inngest_ghcr_fallback + Better Stack inngest_ghcr_fallback + oci-pull-ALL-LEGS-FAILED"
    alert_route: "sentry_alert.zot_mirror_fallback_rate email to issue owners; zot-soak [freshboot] FAIL"
  - mode: "Sentry POST fails (egress, 4xx, timeout)"
    detection: "soleur-boot-emit curl rc != 0, then Better Stack stage=sentry-emit-FAILED rc=<n>"
    alert_route: "Better Stack query; the zot-soak INNGEST_ZOT denominator stays 0 and FAILs closed"
  - mode: "TF_VAR_sentry_dsn empty at render"
    detection: "Better Stack stage=sentry-emit-FAILED rc=nodsn"
    alert_route: "zot-soak FAIL(no-inngest-freshboot-evidence)"
  - mode: "emitter binary missing (write_files failed)"
    detection: "the backgrounded call site cannot abort the boot; no Sentry event; soak denominator 0"
    alert_route: "zot-soak FAIL(no-inngest-freshboot-evidence)"

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
    does_not_defend: "code execution as root; a root-level read of /var/lib/cloud/instance/ or of Hetzner user_data through the metadata endpoint, both of which already hold more sensitive baked credentials (doppler token, zot pull token, GHCR read token); an image of the unencrypted root disk"
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

### Guard 1 — inngest pull-outcome arms emit on the Sentry stage schema

**Property.** On the dedicated host, each of the two zot-leg outcome arms (served, missed) calls `soleur-boot-emit` exactly once, backgrounded, in the exact anchored form, with its own stage (`inngest_zot` info, `inngest_ghcr_fallback` warning). The emitter's `HOST_NAME` literal equals the soak denominator's `host_name:` value, and the template receives `sentry_dsn`.

**Assembly.** The chokepoint is the zot `if` block inside the pull runcmd item of `cloud-init-inngest.yml`, the only place `ZOT_LEG` is assigned. Its two arms are `[ "$zot_rc" -eq 0 ]` and its `else`. Supporting members: the two `write_files` entries (`/etc/default/soleur-sentry-dsn`, `/usr/local/bin/soleur-boot-emit`), the `sentry_dsn` key in the `inngest-host.tf` templatefile map, and the `host_name:` literal in `zot-soak-6122.sh`. The static rows are asserted over the comment-stripped `DED_CODE_FILE`/`DED_BLOCK_FILE` (`cloud-init-inngest-bootstrap.test.sh:685-714`), so a comment can satisfy nothing.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `soleur-boot-emit inngest_zot info …` call from the zot arm | RED |
| 2 | Delete the `soleur-boot-emit inngest_ghcr_fallback warning …` call from the else arm | RED |
| 3 | Strip the trailing `&` from either call site | RED |
| 4 | Move the zot-arm call into the else arm (both calls then sit in one arm) | RED |
| 5 | Add a second `soleur-boot-emit inngest_zot info` in the same arm after a compliant first | RED |
| 6 | Rename the stage to `inngest_zot_ok` | RED |
| 7 | Write the call as `/usr/local/bin/soleur-boot-emit inngest_zot …` (this file's usual absolute-path convention) | RED (misses the soak anchor) |
| 8 | Double the space between `soleur-boot-emit` and the stage | RED (misses the soak anchor) |
| 9 | Remove `sentry_dsn = var.sentry_dsn` from the `inngest-host.tf` map | RED (render fails, and `inngest-boot-emitter.test.sh`'s key-set parity arm names the key) |
| 10 | Change the emitter's `HOST_NAME` literal to `soleur-inngest-1` (the soak query unchanged) | RED |
| 11 | Change `/etc/default/soleur-sentry-dsn` permissions to `0644` | RED |
| 12 | Dispatch: the block extractor returns an empty `DED_BLOCK_FILE` (anchor drifted) | RED (harness abort, never PASS) |
| 13 | Harness row: the mutation sed matches nothing, so the landed-diff check fires | HARNESS ABORT |

### Guard 2 — the inngest event has the web emitter's shape

**Property.** A POST the rendered inngest emitter makes carries the message `soleur-cloud-init boot stage`, the given `level`, and exactly the tag key set `{stage, host_id, region, host_name, detail}` with `region = "cloud-init"` and `host_name = "soleur-inngest"`. This is the shape the web `soleur-boot-emit` produces (`soleur-host-bootstrap.sh:356`) and the shape every Sentry consumer (soak queries, `zot_mirror_fallback_rate`) keys on.

**Assembly.** The `-d` body the stub `curl` records in G3 case 1, parsed with `jq`. It is produced only by the single `BODY=$(printf …)` line of the rendered `/usr/local/bin/soleur-boot-emit` body.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `"region":"cloud-init"` in the inngest body | RED |
| 2 | Drop the `host_name` key | RED |
| 3 | Add an extra tag key (`"shipper":"x"`) | RED (the key set is asserted exactly, not as a subset) |
| 4 | Put a Terraform directive (`%{`) or `${` into the `BODY` line, so the rendered bytes differ from the raw bytes | RED (the case asserts the rendered `BODY` line equals the raw one) |
| 5 | Dispatch: the stub recorded no body on the DSN-present case | RED |
| 6 | Must-PASS: `level = warning` with `detail = rc=7` | PASS |

### Guard 3 — the emitter is best-effort, bounded and non-leaking

**Property.** Run on its own under any condition (DSN missing, empty or present; curl failing or succeeding), the rendered `soleur-boot-emit` exits 0, POSTs at most one event and only when a DSN is present, reports every non-delivery to the phone-home seam with a numeric or `nodsn` reason, carries its curl time bounds, and never writes the DSN or its key to stdout, stderr or process argv.

**Assembly.** The rendered `write_files` body, driven in `inngest-boot-emitter.test.sh` with a stub `curl` on PATH (it records argv, stdin and body, and exits with a configurable code), `SOLEUR_SENTRY_DSN_FILE` pointing at a fixture file, and `SOLEUR_INNGEST_PHONE_HOME` pointing at a recording stub.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the final `exit 0` / the `( … ) || true` wrapper, then run with stub curl exiting 7 | RED (non-zero exit) |
| 2 | Pass the auth header on argv (`-H "X-Sentry-Auth: …$KEY"`) instead of `-K -` | RED (key found in recorded argv) |
| 3 | Add `echo "$SOLEUR_SENTRY_DSN" >&2` | RED (DSN in captured stderr) |
| 4 | Remove `--max-time` or `--retry-max-time` from the curl line | RED (recorded argv lacks the bound) |
| 5 | Remove the `sentry-emit-FAILED` phone-home on curl rc 7 | RED |
| 6 | Remove the `rc=nodsn` phone-home on an empty DSN file | RED |
| 7 | Dispatch: the extracted emitter body is empty, or the stub curl was never invoked on the DSN-present case | RED |
| 8 | Must-PASS: DSN file absent, so exit 0, zero curl invocations, one `rc=nodsn` phone-home, no stdout | PASS |

### Guard 4 — the DSN is in `inngest-redact.sh`'s explicit enumeration

**Property.** `inngest-redact.sh` replaces the literal DSN value and its key by value, without relying on the `[0-9a-f]{32,}` / `[A-Za-z0-9_+/-]{40,}` pattern backstop.

**Assembly.** The `vals+=` enumeration block of the rendered `inngest-redact.sh` `write_files` body (`cloud-init-inngest.yml:342-363`). It is the only value list feeding every shipped log tail (`zot_tail`, `pull_tail`, `boot_tail`, `unit_journal`). Driven with `SOLEUR_SENTRY_DSN_FILE` at a fixture whose DSN is `https://pubKEYx-7@o1.ingest.invalid/42`, a short non-hex key the backstop cannot catch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the Sentry DSN enumeration line | RED (fixture DSN survives in the output) |
| 2 | Enumerate the DSN but not its key | RED (a tail holding only `pubKEYx-7` survives) |
| 3 | Point the line at a path this host never writes (`/run/soleur-sentry-dsn`) with no seam | RED |
| 4 | Dispatch: the redact-body extractor returns empty | RED |
| 5 | Must-PASS: a tail with no secret passes through byte-identical | PASS |

### Guard 6 — the soak cannot PASS on a host that never reported on Sentry

**Property.** `zot-soak-6122.sh` exits 0 only if Sentry holds at least one `stage:"inngest_zot" host_name:"soleur-inngest"` event in `[START, END]`, AND `cloud-init-inngest.yml` carries both anchored `soleur-boot-emit inngest_zot` and `soleur-boot-emit inngest_ghcr_fallback` call sites. Every pre-existing arm and predicate stays byte-identical.

**Assembly.** The soak's exit-0 path is its last line, reachable only by passing the `FAIL_QUERIES` loop, the `APP_ZOT` arm, the new `INNGEST_ZOT` arm, the sample arm, the blocker `OPEN`/`COMPLETED` arms and the corroboration `if`. The chokepoint is the new denominator plus the corroboration `if`. Driven by `zot-soak-6122.test.sh`'s PATH-stubbed `curl`/`gh` (substring keys, first match wins, HTTP 500 on no match) and the relocated-repo fixtures (`:95-128`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture carries only the Better Stack `inngest-boot-phone-home.sh inngest_zot` call (today's code), #6500 CLOSED/COMPLETED | RED (`blocker-closed-but-condition-unmet`) |
| 2 | Fixture carries `soleur-boot-emit inngest_zot` but not `inngest_ghcr_fallback` | RED |
| 3 | Fixture carries both calls only as `#` comment lines | RED |
| 4 | Stub returns `soleur-inngest=0` with everything else passing | RED (`no-inngest-freshboot-evidence`) |
| 5 | Stub returns HTTP 500 for the host-pinned query only | exit 2 (TRANSIENT), never 0 |
| 6 | Delete the `INNGEST_ZOT` arm from the soak | RED (case 4 turns PASS, so the suite fails) |
| 7 | Remove `_zot_reports_sentry_stage` from the corroboration `if` | RED (case 1 turns PASS) |
| 8 | Drop `host_name:"soleur-inngest"` from the denominator query | RED (the stub records each decoded query, and the case asserts one of them is exactly `stage:"inngest_zot" host_name:"soleur-inngest"`) |
| 9 | Stub spec `soleur-inngest=0;inngest_zot=1` (a colocated web host reported, the dedicated host did not) | RED (`no-inngest-freshboot-evidence`) |
| 10 | Must-PASS: fixed fixture with both calls, #6500 CLOSED/COMPLETED, `soleur-inngest=1` | exit 0 |
| 11 | Harness row: the stub does not shadow the real `curl`/`gh` (existing resolve assertion at `:129-135`) | HARNESS ABORT |

**Anchor.** `BLOCKER=6500` reads live issue state. Closing #6500 is an operator authorization act that no diff can perform.

(Guard numbering skips 5. The first draft's Guard 5, a permanent exact-value pin of the isolation regex, was cut in review: AC3 proves this PR leaves the regex alone, and the existing fragment pins at `inngest-host.test.sh:199-204` remain.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC0: Phase 0's `KillMode` finding (line and cloud-init version) is recorded in the PR body, and the call-site form matches it (backgrounded if `KillMode=process`, else foreground `|| true`).
- [ ] AC1: `grep -cE '^[[:space:]]*soleur-boot-emit inngest_(zot|ghcr_fallback) ' apps/web-platform/infra/cloud-init-inngest.yml` prints `2`.
- [ ] AC2: `inngest-host.tf`'s templatefile map carries `sentry_dsn = var.sentry_dsn`. `git diff origin/main -- apps/web-platform/infra/variables.tf` is empty (no new root variable).
- [ ] AC3: `git diff origin/main -- apps/web-platform/infra/cloud-init-inngest.yml | grep -E '^[-+].*(n_inngest|n_total|BETTERSTACK_LOGS_TOKEN\)\$)'` is empty (the isolation lines are untouched).
- [ ] AC4: `git diff origin/main -- apps/web-platform/infra/soleur-host-bootstrap.sh apps/web-platform/infra/sentry/` is empty (no web emitter or alert change).
- [ ] AC5: G4 passes: `inngest-redact.sh` enumerates the DSN and its key explicitly.
- [ ] AC6: the soak's pre-existing guards are byte-identical. Each of these prints nothing:
  `diff <(git show origin/main:scripts/followthroughs/zot-soak-6122.sh | sed -n '/^_zot_path_in_code() {/,/^}/p;/^_zot_reports_offbox() {/,/^}/p;/^declare -A FAIL_QUERIES=(/,/^)/p;/FAIL_QUERIES\[@\]} != 5/p;/^BLOCKER=/p') <(sed -n '/^_zot_path_in_code() {/,/^}/p;/^_zot_reports_offbox() {/,/^}/p;/^declare -A FAIL_QUERIES=(/,/^)/p;/FAIL_QUERIES\[@\]} != 5/p;/^BLOCKER=/p' scripts/followthroughs/zot-soak-6122.sh)`,
  with the extracted text non-empty on both sides.
- [ ] AC7: every Guard 1, 2, 3, 4 and 6 mutation row is executed by a registered suite and goes RED (or HARNESS ABORT or TRANSIENT where stated), and every must-PASS row passes. The suites are `inngest-boot-emitter.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-zot-pull-mutation.test.sh`, `inngest-host.test.sh` (all in `infra-validation.yml`) and `scripts/followthroughs/zot-soak-6122.test.sh` (`scripts/test-all.sh:2076`).
- [ ] AC8: `bash apps/web-platform/infra/inngest-userdata-budget.sh` passes, and the stored-payload delta against `origin/main` is recorded in the PR body (expected well under 1 KB against 21,876 B of headroom).
- [ ] AC9: `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` are green, and `model.c4` has an `inngest -> sentry` edge.
- [ ] AC10: ADR-096 has the `Amendment 2026-09-21 (#6500)` section, including the DSN-rotation coupling.
- [ ] AC11: the PR body contains `Ref #6500` and no closing keyword for it. `gh pr view 8488 --json body --jq .body | grep -ciE '(close[sd]?|fix(e[sd])?|resolve[sd]?):? #6500'` prints `0`. The body must not put any closing verb (close/fix/resolve, in any tense) directly before `#6500`, not even in a negated sentence ("does not close #6500" still matches both this grep and GitHub's keyword parser). Write "leaves issue 6500 open" instead. An accidental auto-close would authorize the PAT revoke.
- [ ] AC12: `terraform validate` in `apps/web-platform/infra` passes, and the `lifecycle.precondition` on `hcloud_server.inngest` (`:516`) is unchanged.

### Post-merge (operator window, not a merge blocker)

- [ ] PM1: `inngest-host-replace` dispatched in an ADR-100 maintenance window (Phase 6). The job's plan shows only the scoped server recreate. `Automation: not feasible in-session because` the window is an operator-scheduled downtime of the sole scheduler (ADR-100). The dispatch itself is one `gh workflow run`.
- [ ] PM2: Sentry shows one `stage:inngest_zot` (or `inngest_ghcr_fallback`) event with `host_name:soleur-inngest` for that boot, Better Stack shows the matching `SOLEUR_INNGEST_BOOT_STAGE stage=inngest_zot` marker, and there is no `sentry-emit-FAILED` marker.
- [ ] PM3: #6500 stays OPEN until an operator posts `RESULT: PASS`. This PR does not change that.

## Test Scenarios

1. The rendered emitter, with a DSN present and a succeeding stub curl, makes one POST to `https://o1.ingest.invalid/api/42/store/`. The body has tags `stage=inngest_zot`, `region=cloud-init`, `host_name=soleur-inngest` and `detail=ep=10.0.1.30:5000`, the key `pubKEYx-7` appears only on stdin, and the emitter exits 0 (G2, G3 rows 2 and 8).
2. The DSN file is missing or empty: exit 0, zero curl calls, one `sentry-emit-FAILED rc=nodsn` phone-home (G3 row 6).
3. Stub curl exits 7: exit 0, and the phone-home stub receives `sentry-emit-FAILED "stage=inngest_ghcr_fallback rc=7"` (G3 row 5).
4. Redaction: a tail containing the fixture DSN, and separately its bare key, comes out with both replaced by `REDACTED` (G4).
5. The Guard 1 static and mutation rows (1-13).
6. The soak cases from Guard 6 (rows 1-11).
7. `inngest-boot-emitter.test.sh`'s key-set parity arm passes with `sentry_dsn` on both sides.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** (CTO domain leader, consulted at plan time.) This is an infrastructure and observability change on the
sole Inngest scheduler's first-boot path. It adds no vendor, secret store or Terraform variable. The risks:

- **Boot-path safety under a shared `set -e` shell.** Handled by backgrounded call sites and a `set +e` emitter.
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
- **Call sites backgrounded** (advisor), and **Phase 0 added** to verify that `cloud-final.service` does not kill the
  backgrounded emit (DHH, simplicity, Kieran). Kieran also found that the fallback arm exits within seconds, so the
  emit really does have to outlive the script.
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

- **A boot-path regression on the sole scheduler.** Mitigated by G1 rows 3 and 7-8, G3 (backgrounded calls, `set +e`,
  exit 0, curl bounds), Phase 0, and a planned window with a known rollback (re-dispatch on the prior commit).
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
