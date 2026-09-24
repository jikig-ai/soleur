# Sentry IaC root

Manages Sentry-hosted infrastructure for `app.soleur.ai`:

- **33 `sentry_alert` rules** (33 alert rules total) — #7650 Phase 2, #7985 Phase 3.4, #8451, #8505. 31 are
  fully Terraform-owned: `ignore_changes = [environment]` only, real
  `trigger_conditions` and `action_filters`, read through the non-deprecated
  `organizations/{org}/workflows/` endpoint.

  **TWO are FROZEN (#8451).** `auth-per-user-loop` and `sandbox-startup-failure`
  trigger on `event_unique_user_frequency_count`, which the pinned provider's
  `trigger_conditions` does not offer (upstream
  jianyuan/terraform-provider-sentry issue 950, fixed on main but unreleased). They
  were `sentry_issue_alert` until Sentry removed the legacy alert-rule API (a
  persistent 410 on every plan since 2026-09-18). They are now adopted as
  `sentry_alert` with the trigger carried by type in `legacy_trigger_conditions`
  and `lifecycle { ignore_changes = all }`: any provider write would re-send the
  trigger with `comparison: true` and destroy the threshold, so
  `scripts/sentry-issue-alert-create-tripwire.sh` refuses create/update/replace and
  `scripts/sentry-alert-live-fidelity.sh` pins their live content against the
  committed capture. **Editing these two blocks is inert** — Terraform owns their
  existence only, until #7985's native conversion. No resource reads the legacy
  endpoint, and `apply-sentry-infra.yml`'s brownout retry was deleted in #8451.

  `configure-sentry-alerts.sh` is NOT deleted, but it is not a repair path: its `rules/`
  endpoint returns 410 and it owns none of the rules; `auth-per-user-loop` is
  repaired by a PUT from the committed capture (#4781). Older rules that terraform
  owns from real `conditions_v2`/`filters_v2`/`actions_v2` include the
  BYOK-delegations rules (`byok-art-33-breach`, `byok-cap-exceeded`, #4364).
  `byok-art-33-breach` uses `action_match = "any"` over three event-lifecycle
  conditions (`first_seen_event` + `reappeared_event` + `regression_event`) so a
  recurring cross-tenant breach re-pages and re-starts the Art. 33 72h clock
  (#4656 item 1 — the only rule here using `"any"`). After every apply,
  `apply-sentry-infra.yml` runs a read-only `assert-byok-rules-exist.sh` liveness
  check asserting both BYOK rules still exist by name (#4656 item 5).
- **59 cron monitors** — vendor-hosted heartbeat for the scheduled GitHub
  Actions workflows that touch secrets (closes #3236). Auto-applied on
  push-to-main via `.github/workflows/apply-sentry-infra.yml`. A monitor for
  `scheduled-cf-token-expiry-check` is deferred until that workflow's
  `schedule:` block is re-enabled (currently manual-dispatch only).
- **4 uptime monitors** — vendor-hosted HTTP checks, auto-applied on the same
  push-to-main path.

ADR: [ADR-031 — Sentry alert and cron monitor configuration as IaC](../../../../knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md)

Plan: [feat-sentry-monitors-alerts-adapt-plan.md](../../../../knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md)

## Authentication

Unlike the main `apps/web-platform/infra/` root (which uses Doppler `prd_terraform`
for HCloud/Cloudflare/Resend tokens), Sentry secrets live in **GitHub repository
secrets**:

- `SENTRY_AUTH_TOKEN` — auth-token for the provider (project:write scope for apply,
  project:read for plan-only).
- `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` — DSN-derived,
  consumed by the workflow check-in steps. Not read by Terraform.
- `SENTRY_ACTIONS_RO_TOKEN` — the org-level read-only Internal Integration
  `actions-read-prd` (`[event:read, org:read, project:read]`, ADR-031 amendment
  2026-09-11). Read by `scripts/followthroughs/*.sh` via the sweeper and by the
  fresh-host boot-trail step; not read by Terraform. Repository secret only, never
  mirrored into Doppler. Rotation:
  `knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md`.

R2 backend credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) come from
Doppler `prd_terraform` via `doppler secrets get --plain` — same pattern as
`scheduled-terraform-drift.yml` extracts them. See ADR-031 §secret-store-divergence.
(The drift leg reads the Sentry token from the same repository secret as the apply.)

## Local invocation

```bash
cd apps/web-platform/infra/sentry

# All three creds live in Doppler prd_terraform — no personal-token mint needed.
# The provider reads SENTRY_AUTH_TOKEN; source it from the IaC token that CI uses
# (SENTRY_IAC_AUTH_TOKEN). Export each individually — `doppler secrets get` on the
# installed CLI does NOT support the `--no-quote`/`--format env` combo.
export SENTRY_AUTH_TOKEN="$(doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain -p soleur -c prd_terraform)"
export AWS_ACCESS_KEY_ID="$(doppler secrets get AWS_ACCESS_KEY_ID --plain -p soleur -c prd_terraform)"
export AWS_SECRET_ACCESS_KEY="$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain -p soleur -c prd_terraform)"

terraform init -input=false
terraform plan
```

## First-time import — COMPLETE, runbook retired (#7590)

First-time adoption of the issue-alert rules is done. Since #7650 Phase 2 this root
declared **29 `sentry_alert` + 2 `sentry_issue_alert`** resources (it was 29
`sentry_issue_alert`). Since #8451 the last two are adopted as frozen
`sentry_alert` blocks (see the top of this file), so every rule is a `sentry_alert`.

`git-data-boot-warning` WAS a third `sentry_issue_alert` — it landed after the
Phase 2 adoption capture was taken and so was never in that migration's scope.
Phase 3.4 (#7985) migrated it, which took this paragraph to 28 + 2. It now
says 29 + 2 because #7989 ADDED a rule (`ops_email_delivery_failure`) rather than
migrating one — the only entry here whose +1 is a new rule, not a type change.
(That was the count before #8451; #8442 then added `art17_erasure_incomplete`,
and #8451 adopted the last two as frozen `sentry_alert`, so the root declares 32
and 0. #8505 then added `anthropic_credit_exhausted`, a new rule, taking it to 33. The current count
is at the top of this file, pinned by T25.)
Historical note, kept because this count has been wrong twice: this paragraph
said **2** until 2026-09-06 (#7826) while line 5 of this same file

The 27 were adopted by CONFIG-BLOCK adoption, not by a `terraform import`
command: 27 `import { to = sentry_alert.<n> }` blocks paired with 27
`removed { from = sentry_issue_alert.<n>  lifecycle { destroy = false } }`
blocks, landed on the branch and applied in ONE merge. That shape is not a
stylistic choice — `terraform import` REQUIRES an existing config block, and
`main` had zero `sentry_alert` blocks, so a pre-merge import could never have
run against `main`. `required_version` is `>= 1.9` for the same class of
reason: on an older CLI a `removed` block plans a DESTROY of the live rule
rather than a forget. **Do not lower it.**

Those `import{}`/`removed{}` blocks were REMOVED by #7826 (2026-09-06), once
the hard precondition held on `main`: `terraform state list` showing 27
`sentry_alert.` addresses in an exact 1:1 with the 27 resource labels, the three
surviving `sentry_issue_alert` addresses disjoint from all 27 `removed{}`
from-labels, and `scripts/sentry-alert-live-fidelity.sh` PASSing field-for-field.
Until then, removing an `import{}` whose address was never imported would have
turned it into a planned CREATE colliding with the live rule — and removing a
`removed{}` whose forget never committed would have planned a DESTROY of one.

The step-by-step import runbook that stood here was retired for two reasons,
both of which made it actively misleading rather than merely obsolete:

1. It was stale by 25 resources — it described importing "the 4 issue-alert
   rules" created by the legacy `configure-sentry-alerts.sh`.
2. It extracted rule ids from an `<!-- ids: ... -->` manifest that the audit
   script no longer emits. Sentry DEPRECATED the project-scoped rules API the
   manifest was built from, and its replacement (`organizations/{org}/workflows/`)
   uses a DISJOINT identifier space — so a manifest repointed at the new
   endpoint would have kept its name and shape while silently changing
   meaning.

If a future rule ever does need adopting, read its id from the Sentry API or
from the Terraform provider directly, not from an audit report:

```bash
doppler run --project soleur --config prd --command '
  curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
    "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/" \
  | jq -r ".[] | \"\(.id)\t\(.name)\""'
```

Note `SENTRY_IAC_AUTH_TOKEN`, not `SENTRY_AUTH_TOKEN`: Doppler `prd` holds
both, they are different credentials, and CI feeds the former into an env var
named after the latter.

## Cron monitors — adoption COMPLETE (#7590)

This section previously read "the 8 `sentry_cron_monitor` resources do not
exist in Sentry yet" and described the first apply creating them. True at
authoring, actively misleading now: the root declares **59** of them, all live
once `apply-sentry-infra.yml` runs for the latest additions,
and the audit's Class D machinery exists precisely *because* live monitors can
outrun the `.tf` that declares them — a monitor Terraform never declared is
spend no apply can reclaim.

Re-derive rather than trusting the number:

```bash
grep -c '^resource "sentry_cron_monitor"' apps/web-platform/infra/sentry/*.tf
```

- Adding a monitor is a five-ledger update, not one edit — the tf resource,
  the heartbeat (`monitor-slug:` or `SENTRY_MONITOR_SLUG`), the
  `NON_INNGEST_MONITORS`/`SENTRY_MONITOR_SLUG` registration in
  `function-registry-count.test.ts`, the count prose here and in
  `sentry-monitors-audit.sh`, and the `github -> sentry` edge counts in
  `knowledge-base/engineering/architecture/diagrams/model.c4` (parity-gated by
  `plugins/soleur/test/c4-count-parity.test.sh`). Miss a ledger and a
  different gate goes red post-merge (#8586).

## Audit

The audit answers "is the alert routing healthy?", and nothing in this
directory pointed at it:

```bash
# 1. Is the audit script itself sound? Hermetic — no credentials, no network.
bash apps/web-platform/scripts/sentry-monitors-audit.test.sh

# 2. Did the last CI run of the gate pass? No credentials needed.
gh run list --workflow="Sentry Audit Gate" --limit 5 --json conclusion,createdAt

# 3. What does the live org look like now? Needs prd credentials.
#    NOTE SENTRY_IAC_AUTH_TOKEN, not SENTRY_AUTH_TOKEN — Doppler holds a
#    DIFFERENT secret under that second name, and CI feeds the former into an
#    env var named after the latter (#7590 lost a session to this).
doppler run --project soleur --config prd --command '
  SENTRY_AUTH_TOKEN="$SENTRY_IAC_AUTH_TOKEN" \
  AUDIT_OUT_DIR=/tmp/sentry-audit \
    bash apps/web-platform/scripts/sentry-monitors-audit.sh'
```

(1) proves the script is not broken; only (2) and (3) say anything about the
org. Class D has teeth only when Terraform state is injected, which
`apply-sentry-infra.yml` does and a local run does not — so a local run reports
Class D candidates as *unresolved*, never as clean.

## Drift detection

Two different things drift here (alert-rule fields, and the root's state against its
config), and each has its own detector.

**Alert-rule fidelity** — `scripts/sentry-alert-live-fidelity.sh`: one
read-only GET against the non-deprecated workflows endpoint, diffed
field-by-field against a reference **projected from the Terraform plan** by
`tests/scripts/lib/sentry-alert-projection.jq` (#8050). It detects deletion,
`enabled:false`, name drift, changed `comparison.{value,interval}`, changed
`tagged_event`, a multi-trigger `logicType` flip, a `monitor_ids` unbind, and
a live in-scope rule the root does not declare — for every `sentry_alert`, not
the 4 that `assert-byok-rules-exist.sh` covers. This exists because a migrated
rule can go dark weeks later: still present, still planning clean, matching
nothing. It runs at two sites with two references:

- **Post-apply**, in `apply-sentry-infra.yml`: the plan step projects the plan
  it is about to apply into `${RUNNER_TEMP}/sentry-alert-reference.json` and
  the probe reads that. A divergence right after the apply is therefore live
  state Terraform does not own, or evidence the apply did not do what it
  reported — true by construction. **Do not "fix" the apply job to read the
  committed file below**: that coupling is what redded `main` after a complete
  apply (run 34491157462) — a rule cannot be captured before it is applied.
- **Daily**, in `scheduled-sentry-alert-drift.yml` (Inngest-dispatched per
  ADR-033): the probe reads the committed `alert-reference.json` in this
  directory, which exists ONLY because the daily job has no Terraform access.
  `scripts/sentry-alert-reference-gate.sh` in `plan_pr` holds it equal to the
  plan at PR time, so it cannot merge stale under the strict up-to-date policy
  (an admin bypass-merge is the one path to a stale copy; it surfaces as one
  daily drift issue naming the regeneration below, never as a red apply).
  **Without Doppler `prd_terraform` access**, the PR round-trip IS the
  regeneration route: push the `.tf` change, let `plan_pr` red, then
  `gh run download <run-id> -n sentry-alert-reference-expected-<run-id>` (7-day
  retention; `gh run rerun <run-id> --failed` regenerates it) and `cp` the file
  over `alert-reference.json` — byte-exact, no credentials.

**Adding or editing a rule = a resource block + a regenerated
`alert-reference.json`.** From this directory, after the Local invocation
triplet above:

```bash
terraform plan -input=false -out=/var/tmp/sentry.tfplan
terraform show -json /var/tmp/sentry.tfplan > /var/tmp/sentry-plan.json
jq -S --arg side tf -f ../../../../tests/scripts/lib/sentry-alert-projection.jq \
  /var/tmp/sentry-plan.json > alert-reference.json
```

If you forget, the gate reds the PR with the leaf-level diff; the workflow
sweeps the expected file for secret-shaped bytes and then prints it into the
step summary and uploads it as the artifact
`sentry-alert-reference-expected-<run-id>`. Two normalisations live in the
module and nowhere else: lifecycle triggers (`{}` in the provider,
`comparison: true` live) and trigger `logicType`, which the provider hard-codes
to `any-short` on every write while imported single-trigger rules still read
`all` — single-trigger rules project a constant on both sides. The Phase 2 and
Phase 3.4 captures under `knowledge-base/project/specs/fix-7650-sentry-alert-migration/`
are history (the adoption record and `sentry-adoption-plan-assert.sh`'s
self-skipping bijection input), not the probe's reference.

**The whole root, state against config** — the `apps/web-platform/infra/sentry`
leg of `scheduled-terraform-drift.yml` (#6612, ADR-031's 2026-09-24 amendment).
Twice daily it runs a full-root `terraform plan -detailed-exitcode` (no
`-target=`), so every resource type is compared, cron and uptime monitors
included. It authenticates exactly as the apply does: the `SENTRY_IAC_AUTH_TOKEN`
repository secret bound as the raw `SENTRY_AUTH_TOKEN`, with no `doppler run`,
and terraform sees only an `env -i` allowlist. Exit 2 files an `infra-drift`
issue; exit 1 (a vendor read failure, a missing token) sends the `[ERROR]` email
and files no issue. The issue's step 2 routes the fix by what the plan shows,
because a manual dispatch of the apply passes the same gates as a merge: a
dispatch reconciles in-place updates only; an object deleted in Sentry's web UI
(`+` with no recent merge) needs a PR, since the create gate refuses it; a
destroy needs a re-run of the failed push apply or a PR carrying
`[ack-destroy]`, since a dispatch never carries the ack. Never apply locally
(`use_lockfile = false`). The leg cannot see attributes under `ignore_changes`,
so field fidelity for those stays with the probe above.

ADR-031's exit criterion for this leg counts its plan failures over 30 days
from the job annotations (a job id is its check-run id):

```bash
gh run list -w scheduled-terraform-drift.yml -L 100 --created ">=$(date -u -d '30 days ago' +%F)" \
  --json databaseId --jq '.[].databaseId' \
| while read -r run; do
    gh api "repos/jikig-ai/soleur/actions/runs/$run/jobs" \
      --jq '.jobs[] | select(.name == "drift-check (apps/web-platform/infra/sentry)") | .id'
  done \
| while read -r job; do
    gh api "repos/jikig-ai/soleur/check-runs/$job/annotations" \
      --jq '[.[] | select(.message | test("Terraform plan failed in web-platform/sentry"))] | length'
  done | paste -sd+ - | bc
```
