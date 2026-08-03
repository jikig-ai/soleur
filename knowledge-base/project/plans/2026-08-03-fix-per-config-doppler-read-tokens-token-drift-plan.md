---
title: "fix(infra): per-config Doppler read tokens restore the token-drift scan to 13 of 13"
date: 2026-08-03
type: fix
issue: 7234
refs: [7159, 7175]
branch: feat-one-shot-7234-per-config-doppler-service-tokens
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
adr: ADR-166 (PROVISIONAL ordinal — re-derive before merge)
---

# fix(infra): per-config Doppler read tokens restore the token-drift scan to 13 of 13

Closes #7234. `Ref #7159`, `Ref #7175` — **never `Closes`/`Resolves` for those two**: both
close on a live scheduled run, not at merge (see AC-P1 and SE-3).

> **Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).** No
> `knowledge-base/project/specs/feat-one-shot-7234-per-config-doppler-service-tokens/spec.md`
> exists; `tasks.md` is derived from this plan.

> **Revision note.** This is v2. A 5-agent review panel (architecture-strategist,
> spec-flow-analyzer, kieran, dhh, code-simplicity) plus a CTO domain review and a scoped
> strong-model consult found **4 P0s and 12 P1s** against v1, including three claims v1 made
> about code that were false when read. All are applied below; the audit trail is
> §Review Findings Applied.

## Overview

`scripts/check-cloudflare-token-drift.sh` grades every Cloudflare API token and Access service
token it can find in Doppler, twice daily. PR #7162 pointed it at a project-scoped
`doppler_service_account`; the credential was minted, wired, published — and measured to see
**nothing** (`doppler configs -p soleur --json` → `null`; reading `prd` → `Could not find
requested config 'prd'`). PR #7236 restored the interim config-scoped `secrets.DOPPLER_TOKEN`,
so the scan runs at **1 of 13** today with an honest `degraded` verdict.

This change replaces that identity with **13 per-config `doppler_service_token` resources under
one `for_each`**, published as a single Actions secret carrying a JSON map keyed by config
name. The detector stops asking Doppler to enumerate the project — a capability no credential
in this repository has — and iterates the map it was handed.

Operator decision, 2026-08-03: option (c) of #7234, over option (b) (widening the service
account's `workplace_permissions`), because the only plausible listing permission is
`all_enclave_projects` — reach across **every** Doppler project in the workplace, strictly wider
than the single `soleur` project #7159 authorised — and because it is *unmeasured* whether any
workplace permission would work. **Do not re-litigate the shape.**

Three things decide whether this ships correctly:

1. **`configs` must not be inflatable.** `CONFIG_NAMES` — the array whose length becomes
   `configs` — is sorted but **not deduped** (`scripts/check-cloudflare-token-drift.sh:569` is
   plain `sort`; the `sort -u` at `:226` is the *inventory* parse). Under today's design that
   is harmless, because the loop iterates configs Doppler returned unique. **This change is the
   first thing that can ever put a duplicate in that array**, and the producible Terraform
   defect — `config = "prd"` written in place of `config = each.key` — yields 13 successful
   reads of one config and a confident `at-floor 13/13`.
2. **The three superseded resources must actually be destroyed**, which means their `-target=`
   legs survive into the apply that removes them, and `[ack-destroy]` reaches the **merge
   commit message** — which this repo builds from *branch commit messages*, not the PR body.
3. **The guard ladder must not be weakened to fit.** Every assertion that becomes false gets a
   same-or-stronger replacement; both anti-vacuity floors go up, never down.

## Premise Validation

| Premise | Probe | Result |
|---|---|---|
| #7234 / #7159 / #7175 open; #7162 merged | `gh issue view` | **HOLDS** (labels as stated) |
| interim restore is this branch's base parent | `git show a6b9720c2 --stat` | **HOLDS** — 4 files, repoints at `secrets.DOPPLER_TOKEN`, keeps floor 13 |
| the 13 config names | `doppler-config-inventory.txt` | **HOLDS** — 13 bare name lines, generated `2026-08-03T08:35:38Z` |
| pinned Doppler provider | `.terraform.lock.hcl` | **HOLDS** — `dopplerhq/doppler` `1.21.2`, `~> 1.21` |
| CI Terraform version | `scheduled-terraform-drift.yml` `TERRAFORM_VERSION` | **HOLDS** — `1.10.5`, identical to the local probe host |

**FINDING — the chosen mechanism is in ADR-164's rejected-alternatives table, and the rejection
is falsified.** ADR-164 rejects *"A `for_each` credential per config (13 `doppler_service_token`s)"*
as *"13 credentials, 13 Actions secrets, 13 `-target=` legs and a detector that loops
credentials, to obtain what one project membership obtains."* Measured: **one** Actions secret
(R2), **one** `-target=` leg (R1), and the membership obtains **nothing**. Three cost claims
wrong, the premise void. The operator re-decided with that measurement in hand; the new ADR
records the reversal rather than quietly re-adopting a rejected alternative.

## Research Reconciliation — brief vs. codebase

| Brief claim | Reality | Response |
|---|---|---|
| "`local.token_drift_configs` — the 13 configs" | No such local. The names live only in `doppler-config-inventory.txt`, whose header says *"THIS FILE REPORTS; IT GATES NOTHING."* | Derive it with `file()` (FR1). The header claim becomes false and is rewritten (FR12); so does the same claim inside **ADR-164 Decision 2**, which must be amended, not carried forward untouched (§ADR) |
| "iterate the map instead of calling `doppler configs` to enumerate" | One call site, `:479-480`, fatal on empty (`:481-485`) | Retained with a new meaning (FR5/FR6); never again used to enumerate a project the credential does not own |
| "one GitHub Actions secret" | `DOPPLER_TOKEN_DRIFT` exists but has **zero** consumers since the interim restore | Publish a **new** name, `DOPPLER_TOKEN_DRIFT_MAP`; Terraform destroys the old (SE-1) |
| detector has one consumer | **Five call sites.** `reusable-release.yml:539` (`--only REGISTRY_PUSH_ACCESS_TOKEN`, `DOPPLER_TOKEN_PRD`, **prd root**, no `DOPPLER_CONFIG`); `apply-web-platform-infra.yml:4721` and `cf-tunnel-ssh-bridge/action.yml:324` (`--only CI_SSH_ACCESS_TOKEN --json-file`, `DOPPLER_CONFIG: prd_terraform`, **branch**-scoped); plus two pre-existing remedy strings (`cf-tunnel-registry-bridge/action.yml:188`, `reusable-release.yml:1059`) that wrap the detector in a `doppler run` against `prd_terraform`, a fifth invocation form that also lands in single mode. **None of the five passes `--configs-floor`** — all rely on the default `1` at `:121` | Single-credential mode stays byte-for-byte today's behaviour (FR5b); tests use the **real** argv (AC-B4) |
| "the ladder must keep working" | 9 workflow guards + test families `C1-C3`, `F1-F4`, `T1-T22`, `P1-P17`, `S1-S4`, `W1-W10`, anti-vacuity floors `>= 57` and `>= 80` | No assertion deleted without a stronger replacement; both floors rise (FR14-FR16) |
| — | `rung2-rehearsal-orphan-sweep` prose asserts repointing it at the token-drift credential *"would satisfy the predicate"* | False under the new shape too — a map of config-scoped tokens cannot list ephemeral configs. Corrected in-PR (FR12); the gap tracked (FR18b) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a twice-daily drift run reporting Cloudflare
  and Access token drift as clean while a rotated credential sits undetected — the #7071 (CI
  registry bridge dead) and #7095 (`ci_ssh` Access token; production undeployable for 3 days on
  an unreplaceable host) failure class. The first signal would be a failed deploy, not a report.
- **If this leaks, the user's data and infrastructure are exposed via:** the
  `DOPPLER_TOKEN_DRIFT_MAP` repository Actions secret — 13 read credentials covering the whole
  `soleur` project, including `prd` (which holds `SUPABASE_SERVICE_ROLE_KEY`, the Terraform
  GitHub App private key, `GHCR_MINTER_DOPPLER_TOKEN`, `PROXY_TLS_KEY`, three git-transport SSH
  keys). This is the reach ADR-164 disclosed and the operator accepted; restated because
  *today's live reach is one config* and this change makes the accepted reach real.
  **Precisely what transits the runner:** values only for `CF_API_TOKEN*` (`:714`) and the
  `*_ACCESS_TOKEN_ID/_SECRET` pair (`:741-742`) — but `--only-names` (`:536`) pulls each
  config's full key-*name* listing, so the *name* `SUPABASE_SERVICE_ROLE_KEY` transits while its
  value does not. The bypass-RLS reach is a capability, not an exercised read.
- **Brand-survival threshold:** `single-user incident` — CPO sign-off at plan time,
  `user-impact-reviewer` at review time.

## Design

### D1 — Terraform

```hcl
# apps/web-platform/infra/token-drift-read-tokens.tf  (replaces token-drift-service-account.tf)

locals {
  # The ONLY config list. NO trimspace(): this filter must accept exactly what the detector's
  # `grep -E '^[a-z0-9_]+$'` accepts (measured identical on ASCII — R4). distinct() makes the
  # local itself the accepted set, so it is directly comparable to `grep … | sort -u`.
  token_drift_configs = distinct([
    for _l in split("\n", file("${path.module}/doppler-config-inventory.txt")) :
    _l if can(regex("^[a-z0-9_]+$", _l))
  ])
}

resource "doppler_service_token" "token_drift" {
  for_each = toset(local.token_drift_configs)

  project = "soleur"
  config  = each.key           # LOAD-BEARING: a literal here mints N tokens on ONE config.
  name    = "token-drift-ci-tf-${each.key}"
  access  = "read"
}

resource "github_actions_secret" "doppler_token_drift_map" {
  repository  = "soleur"
  secret_name = "DOPPLER_TOKEN_DRIFT_MAP"
  # `.key` — NOT `.api_key`, which belonged to the retired doppler_service_account_token.
  plaintext_value = jsonencode({
    for _cfg, _t in doppler_service_token.token_drift : _cfg => _t.key
  })
}
```

Conventions mirror the nine sibling `doppler_service_token`s (`kb-drift.tf:102`,
`doppler-write-token.tf:40`, `web-arm-write-token.tf:29`, `workspaces-luks.tf:128`,
`web-probe-read-token.tf:33`, …): `.key` for the value, a literal `project` because that
project is not Terraform-managed, a repository-level secret because the Terraform GitHub App
403s on environment secrets, and **no `lifecycle.ignore_changes` on `plaintext_value`** — with
one, a `-replace=` rotation would mint a value that never reached the secret and the scan would
present a revoked credential while the apply read green. Templating a service-token name has
precedent at `rung2-rehearsal/rehearsal.tf:88`.

### D2 — The map contract

A single-line JSON object, `{"<config>": "<token>", …}`, keys sorted by `jsonencode`. Measured
(R2): Terraform tracks the encoded string as sensitive, and key order is deterministic, so the
secret churns only when a token value or the key set changes. ~800 bytes against GitHub's 48 KB
limit. The workflow passes it under a shape-neutral env name:

```yaml
env:
  DOPPLER_TOKEN_MAP: ${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }}
  DOPPLER_PROJECT: soleur
  DOPPLER_CONFIGS_FLOOR: 13
```

No `DOPPLER_TOKEN`, no `DOPPLER_CONFIG`.

### D3 — One code path, two modes

A `CRED_FOR[<config>]` associative array replaces the single `DOPPLER_CRED` snapshot
(`:425-449`). Both modes normalise into it:

| Mode | Trigger | Construction |
|---|---|---|
| **Map** (the token-drift step) | `DOPPLER_TOKEN_MAP` **non-empty** (`[[ -n … ]]`, not `${x+set}` — pinned, see below) | parse the JSON; fail closed on non-object, zero keys, or a non-string value |
| **Single** (the 5 legacy call sites, unedited) | `DOPPLER_TOKEN` non-empty | today's `doppler configs -p soleur --json` restricted to exactly-one-result → `{<that config>: <token>}`. **Byte-for-byte the current behaviour** |
| Both non-empty | ambiguous | `exit 2`, named error, no read attempted |
| Neither | — | the existing empty-credential path (`:440-449`), unchanged |

**The definedness axis is pinned deliberately.** `DOPPLER_TOKEN_MAP: ${{ secrets.X }}` with the
secret absent yields a *defined but empty* variable. `-n` puts the merge→apply window into the
"neither" arm → today's `degraded 0/13`, which is what the follow-through's surviving `0/*`
TRANSIENT arm expects and what the `degraded` issue body (rewritten by FR10) correctly
diagnoses. Choosing `${x+set}` would route it to `unknown`, whose issue body says *"this is a
DETECTOR fault, not a credential fault — do not touch the Doppler identity"* — the wrong remedy
in the one window it is guaranteed to fire.

Downstream (`--only-names`, both `secrets get` loops, `CONFIG_NAMES`, `FAILED_CONFIGS`,
`compute_coverage`, `emit_json`) keeps its shape and reads `${CRED_FOR[$cfg]}`. **`configs`
still counts configs whose read SUCCEEDED** — ADR-164 §2's semantic, carried forward.

### D4 — Three controls against a credential/config mis-binding, in cost order

A Doppler service token is config-scoped by construction; `kb-drift.tf:94-95` records the
measurement that under such a token `doppler configs list` *"returns a list silently scoped to
the caller (one entry, `success: true`, no error)"* — and that resource is scoped to
`prd_kb_drift_walker`, a **branch** config, so the branch case is already measured, not open.
Whether the `-c` **flag** errors or is silently ignored is separate and *unmeasured* (P0.3 q2).

The failure to prevent: a map whose entries do not read the configs they claim, yielding a
confident `13/13` over one config. Terraform cannot produce a *shuffle* — `jsonencode({for
_cfg, _t in … : _cfg => _t.key})` takes key and value from the same instance, so a key/value
skew would be an HCL bug, not a code defect. What Terraform **can** produce is
`config = "prd"` in place of `config = each.key`: 13 distinct tokens, correct map keys, all
bound to one config. Three controls, cheapest first:

- **C-a — static, pre-merge, free.** A test asserts the `.tf` sets `config = each.key` (never a
  string literal) and that the map's key and value come from the same iteration variable. This
  catches the entire producible class **before merge**, at zero runtime cost, and it is the
  control that holds regardless of what P0.3 measures.
- **C-b — parse-time, zero network.** The map must parse as an object with ≥1 key and all-string
  values (shape validation). Cheap, unconditional.
- **C-c — runtime self-identification, CONDITIONAL on P0.3.** Each credential is asked which
  config it is bound to; a mismatch counts that config **UNREAD** and emits
  `::error::token_drift_config_binding_mismatch`. Counting it unread is what gives it a channel:
  it depresses `configs` below the floor, so the coverage issue files and the close arm's
  `configs_unread == '-'` conjunct blocks. **Adopted only if P0.3 measures a Doppler-*derived*
  identifying field on both a root- and a branch-scoped credential.** If P0.3 disqualifies every
  candidate, C-c is dropped and the plan ships on C-a + C-b, recording the residual gap —
  because building the primary safety property on an unmeasured credential capability is the
  exact #7162 mistake this change exists to correct.
- **C-d — `sort -u`, one word, mandatory.** `:569` is plain `sort`. Without `-u`, 13 assertions
  of `prd` still length-13 the array and print `13/13`. This is a *precondition* of C-c meaning
  anything, and it is independently required because C-c is conditional.

On an identify failure the entry pushed to `FAILED_CONFIGS` is the map **handle**, not a
measured name — a credential that could not self-identify has no assertion to key on. So the
unread list names the handle's claim, not a measurement; the issue body must not imply
otherwise.

### D5 — What each shape detects

| Regression | Old (service account) | New (per-config map) |
|---|---|---|
| credential absent / empty | `degraded 0/13` | `degraded 0/13` — unchanged, and the merge→apply window lands here by design (D3) |
| map present but malformed (non-object / zero keys / non-string values) | n/a | `unknown` (fail-closed) |
| whole credential revoked | `degraded 0/13` | `degraded 0/13` |
| **one** config's token revoked | *invisible* | `degraded 12/13`, naming that config — **new capability** |
| reach narrowed to a subset | `degraded 7/13` | `degraded 7/13`, naming the six |
| step repointed at a bare token via `DOPPLER_TOKEN_MAP=<token>` | n/a | `unknown` (parse fails) |
| step repointed at a bare token via `DOPPLER_TOKEN=` (what #7236 did) | `degraded 1/13` | `degraded 1/13` — single mode. This is why FR16 deletes the `1/*` TRANSIENT arm: a collapse-to-one must grade FAIL |
| `config = "prd"` instead of `each.key` | n/a | **caught pre-merge by C-a**; at runtime `1/13 degraded` iff C-c ships |
| a config in Doppler but not in the inventory | invisible (report-only); the denominator was regenerated independently, so `configs_unread` could in principle expose a narrower reach | **a NEW standing blind spot**: denominator and reach now share a source, so `configs_unread` is empty except when an individual token breaks, and no credential can enumerate the project. Tracked as FR18b |
| a config in the inventory that is not in Doppler | invisible | `terraform apply` fails — **post-merge**, on the apply that also carries the destroy. `infra-validation.yml`'s PR-time plan is `continue-on-error: true` (`:1178`) and its other job runs `-backend=false` `validate`, so **nothing gates the merge**. P0.4 is the only pre-merge control |

### D6 — Rotation

`terraform apply -replace='doppler_service_token.token_drift["<cfg>"]'` per token; whole-set
rotation passes one `-replace=` per config in a single apply, generated from the inventory. The
map republishes in the same apply. Emergency revocation of the set is deleting the resource; the
next scan reports `degraded 0/13` within 12 hours. More rotation surface than one token — the
accepted cost of option (c), disclosed in the ADR.

## Architecture Decision (ADR/C4)

### ADR

**Create `ADR-166-per-config-read-tokens-for-the-token-drift-scan.md`**, header
`**Supersedes (in part):** ADR-164` — established corpus vocabulary (`ADR-091:6`, `ADR-053:6`,
`ADR-149:8`), with the reciprocal marker convention of `ADR-027:10`.

It must record what nothing else will: (a) that a project-scoped `doppler_service_account` with
`workplace_permissions = []` / `workplace_role: no_access` can **neither enumerate nor read** a
project it holds a `viewer` membership on — the measurement #7162 cost; (b) that this shape sits
in ADR-164's rejected-alternatives table and why the rejection is void; (c) the measured cost
corrections (1 secret, 1 `-target=` leg); (d) the mis-binding hazard and the C-a/C-b/C-c/C-d
control set, including that C-c is conditional on measurement; (e) rotation cost; (f) the new
standing blind spot in D5's last-but-one row.

**Amend vs. supersede — decided: supersede in part, AND amend one bullet of Decision 2.**
ADR-164 Decision 1 is not superseded by a better idea, it was *falsified* — a new ADR keeps that
record where a reader will find it, rather than overwriting it. But the boundary is one bullet
narrower than v1 of this plan claimed: Decision 2's bullet **"The committed inventory reports,
and gates NOTHING … changes no state"** is falsified by FR1, because a short inventory now
changes the *minted token set*. That bullet is amended in place to "gates no verdict
*threshold*", with a pointer to ADR-166. The rest of Decision 2 — declared floor, `configs`
counts successful reads, `unknown → degraded → at-floor` — stands and is carried by reference.
ADR-164's status becomes `Accepted — Decision 1 superseded by ADR-166 (2026-08-03); Decision 2
amended in one bullet, otherwise in force`.

> **Ordinal PROVISIONAL.** `ADR-165` is the highest on freshly-fetched `origin/main`;
> `adr-ordinals` is not a required check and ADR-164 moved **five times** in one pipeline.
> Re-derive before merge and after every sync; sweep this branch's own artifacts only
> (`git diff --name-only origin/main...HEAD`), never a repo-wide replace.

### C4 views

All three model files read in full (622/62/54 lines). Enumeration: no new external human actor;
no new external system (`doppler` `model.c4:238`, `github`, `cloudflare` all already `#external`
and already in the `context` and `containers` includes at `views.c4:16,40`); no new container or
data store. **One access relationship is missing**: the model carries five `doppler -> *`
injection edges and one `inngest -> doppler` write edge, but **no `github -> doppler` edge at
all** — CI's read of Doppler is unmodelled, and this change is precisely about the shape of that
credential.

**Task:** add one **single-line** relationship (all 147 existing `->` descriptions are
single-line) beside the other `github -> *` edges, with **no hardcoded counts** —
`plugins/soleur/test/c4-count-parity.test.sh` exists because prose counts in `model.c4` went
unchecked, and a "13" here would be a sixth unpinned copy:

```
github -> doppler "scheduled-terraform-drift's token-drift scan reads token-shaped keys across the soleur project's configs using per-config read-only service tokens delivered as ONE Actions secret; the config list comes from the committed inventory, never from a live listing (ADR-166)" { technology "doppler CLI (config-scoped read service tokens)" }
```

Rationale, hazards and control set live in ADR-166, not the diagram — a label that documents a
control would rot the first time the control changes.

Both endpoints are already view-included, so **no `views.c4` edit**. `spec.c4` untouched.
**`model.likec4.json` MUST be regenerated and committed** — `plugins/soleur/test/c4-model-freshness.test.sh`
byte-diffs it against a fresh render and runs in the required `test-scripts` shard; the
pre-commit hook that would catch it is `--no-verify`-bypassable. Run
`bash scripts/regenerate-c4-model.sh`, then `apps/web-platform/test/c4-code-syntax.test.ts` and
`c4-render.test.ts`.

### Sequencing

True at apply. Nothing soak-gated; the ADR ships `Status: Accepted`.

## Observability

```yaml
liveness_signal:
  what:          "Sentry cron monitor check-in from scheduled-terraform-drift (./.github/actions/sentry-heartbeat), plus the token_drift step's published `coverage` output"
  cadence:       "twice daily — the workflow's ONLY trigger is `workflow_dispatch:` (verified), fired by Inngest per ADR-033"
  alert_target:  "operator email (DETECTOR-UNAVAILABLE / DEAD arms) and GitHub issue #7175 (the token-drift-coverage channel)"
  configured_in: ".github/workflows/scheduled-terraform-drift.yml — steps id:token_drift, id:coverage_issue, id:coverage_close"

error_reporting:
  destination:   "GitHub Actions ::error:: annotations on the token_drift step + the create-or-update body of issue #7175 (label token-drift-coverage); channel failure escalates to the operator backstop email at scheduled-terraform-drift.yml:896-917"
  fail_loud:     "the step log line `token-drift verdict: <v> (detector exit N, causes: …, configs: N, floor: 13, coverage: <c>, ratio: N/13)` — any coverage other than at-floor at 13/13 files or rewrites #7175 within 12 hours"

failure_modes:
  - mode:        "DOPPLER_TOKEN_DRIFT_MAP absent or empty (includes the merge->apply window)"
    detection:   "neither-mode -> the existing empty-credential path -> degraded 0/13"
    alert_route: "GitHub issue #7175 degraded body (layer: the token-drift-coverage issue channel); the follow-through probe's 0/* arm grades it TRANSIENT rather than FAIL"
  - mode:        "map present but malformed (non-object, zero keys, non-string values)"
    detection:   "fail-closed to coverage=unknown, exit 2, verdict published before exiting"
    alert_route: "GitHub issue #7175 unknown body + DETECTOR-UNAVAILABLE operator email (layer: GitHub Actions annotations, then the issue channel)"
  - mode:        "one config's service token revoked or expired Doppler-side"
    detection:   "that config's --only-names read fails; counted UNREAD, named in configs_unread; configs drops to 12 < floor 13 -> degraded"
    alert_route: "GitHub issue #7175 degraded body naming the config (layer: the token-drift-coverage issue channel)"
  - mode:        "credential/config mis-binding (config = a literal instead of each.key)"
    detection:   "PRE-MERGE by control C-a, a static test over the .tf; at runtime by C-c if P0.3 admits it, which counts the config UNREAD so it reaches the same issue channel"
    alert_route: "CI on the PR (layer: required test shard), then GitHub issue #7175 post-merge"
  - mode:        "the for_each list is shortened (fewer tokens than the declared floor)"
    detection:   "configs < DOPPLER_CONFIGS_FLOOR -> degraded, configs_unread naming every inventory config that produced no read; pre-merge the F-family also fails because floor and inventory count must stay equal"
    alert_route: "CI pre-merge (plugins/soleur/test/token-drift-workflow-causes.test.sh), then GitHub issue #7175"
  - mode:        "an inventory config does not exist in Doppler"
    detection:   "the merge-triggered terraform apply fails on that key's create. NOT gated pre-merge: infra-validation.yml's plan job is continue-on-error and its validate job runs -backend=false"
    alert_route: "the apply run's job annotation, readable with `gh run view` (layer: GitHub Actions run logs)"
  - mode:        "the 3 superseded resources are deleted from config but never destroyed"
    detection:   "the drift job reports a persistent 3-resource delete on apps/web-platform/infra; `terraform state list | grep -c doppler_service_account` is non-zero"
    alert_route: "the existing infra-drift issue channel of scheduled-terraform-drift.yml"
  - mode:        "verdict at-floor + configs_unread '-' + verdict unavailable — files nothing, closes nothing"
    detection:   "reachable via the non-vacuity gate (all 13 name-listings succeed, zero values probed). The follow-through probe returns TRANSIENT forever and #7175 keeps a stale body"
    alert_route: "the DETECTOR-UNAVAILABLE operator email still fires on verdict=unavailable (layer: operator email). FR11 widens the filer's gate to cover it so the issue body stops being stale"

logs:
  where:         "GitHub Actions run logs for scheduled-terraform-drift, readable with `gh run view`; the verdict JSON is written to $RUNNER_TEMP/token-drift.json and parsed in-step, not uploaded"
  retention:     "90 days (Actions default); derived state persists on issue #7175, rewritten every run"

discoverability_test:
  command:       "gh run list --workflow=scheduled-terraform-drift.yml --status success -L 1 --json databaseId --jq '.[0].databaseId' | xargs -I{} gh run view {} --log | grep 'token-drift verdict:' | tail -1"
  expected_output: "a line containing `coverage: at-floor, ratio: 13/13` (gh prefixes each log line with job/step columns, so match as a substring; --status success avoids `gh run view --log` refusing an in-progress run, and `tail -1` avoids SIGPIPE-ing gh the way `grep -m1` would)"
```

**Soak follow-through:** none new. `scripts/followthroughs/token-drift-coverage-7159.sh` exists,
is directive-wired on #7159, and is swept by `scheduled-followthrough-sweeper.yml`. FR16 edits
it; no new `secrets=` clause.

## Encryption Posture

```yaml
at_rest:
  - store:            "(none introduced)"
    mechanism:        "n/a — no persistent store is created. Both new resource types are already classified in the `non_store_types` array of scripts/encryption-posture-ledger.json."
    evidence:         "scripts/encryption-posture-ledger.json — `non_store_types` contains the literals \"doppler_service_token\" and \"github_actions_secret\" (content anchor, not a line number)"
    defends_against:  "n/a"
    does_not_defend:  "n/a — no new store. The 13 token values DO land in the pre-existing terraform.tfstate on the R2 backend (non_iac_stores entry `r2.terraform_state_backend`), as five sibling token keys already do; this adds sensitive values to a declared store rather than creating one. It does NOT defend against a leaked R2 access key or a leaked Actions secret — either yields all 13 read credentials at once."
    disclosed_as:     "not-publicly-claimed"
    live_verification: "available — `terraform state list` enumerates the resources without revealing values"
in_transit:
  - connection:        "GitHub Actions runner -> Doppler API (per-config secret reads)"
    enforced_at:       "scripts/check-cloudflare-token-drift.sh — the doppler CLI is HTTPS-only against api.doppler.com; the credential is delivered as an env prefix, never on argv (rationale at :471-474, asserted by tests P9/P11)"
    tls:               "TLS 1.2+ (doppler CLI default; no plaintext transport option)"
    cert_verification: "on"
    does_not_defend:   "a leaked DOPPLER_TOKEN_DRIFT_MAP; a compromised runner, which sees all 13 plaintext tokens in its environment for the duration of the step"
    disclosed_as:      "not-publicly-claimed"
```

No `exception` block: no `plaintext-exception`, no `cert_verification: off`.

## Functional Requirements

**Terraform**

- **FR1** — `apps/web-platform/infra/token-drift-read-tokens.tf` per §D1: `local.token_drift_configs`
  derived from the inventory via `file()` + `can(regex("^[a-z0-9_]+$", _l))` over raw
  `split("\n")` lines, wrapped in `distinct()`. **No `trimspace()`/`trim()`/`chomp()`** — the
  filter must accept exactly what the detector's `grep -E '^[a-z0-9_]+$'` accepts (measured
  identical on ASCII input, R4; the one divergence is `[a-z]` under a glibc `en_US.UTF-8`
  locale, so the two grep sites are pinned `LC_ALL=C` rather than the claim being softened).
- **FR2** — `doppler_service_token.token_drift` with `for_each = toset(local.token_drift_configs)`,
  `project = "soleur"`, **`config = each.key`** (never a literal — the C-a class),
  `name = "token-drift-ci-tf-${each.key}"`, `access = "read"`. No `lifecycle`, no `expires_at`.
- **FR3** — `github_actions_secret.doppler_token_drift_map` publishes `DOPPLER_TOKEN_DRIFT_MAP`
  as `jsonencode({for _cfg, _t in doppler_service_token.token_drift : _cfg => _t.key})`.
  Attribute is **`.key`**, not `.api_key`.
- **FR4** — delete `token-drift-service-account.tf` and its four resources.

**Detector** (`scripts/check-cloudflare-token-drift.sh`)

- **FR5** — a `CRED_FOR[<config>]` map replaces the `DOPPLER_CRED` snapshot (`:425-449`), per
  §D3's four-row table. Mode selection is on **non-emptiness** (`[[ -n … ]]`), pinned. Map-shape
  validation (control C-b) runs before any network call. `DOPPLER_TOKEN_MAP` is **unset after
  the parse**, mirroring the existing discipline the block it replaces states verbatim
  (*"Unsetting makes that failure loud BY CONSTRUCTION"*).
- **FR5b** — single-credential mode is byte-for-byte today's behaviour: its 1-entry map comes
  from the existing `doppler configs -p soleur --json` at `:479-480` restricted to
  exactly-one-result, and its existing error path is unchanged. It must **not** depend on the
  new self-identification surface — two of the five legacy call sites are branch-scoped and one
  (`apply-web-platform-infra.yml:4721`) runs immediately after an irreversible destroy, where in
  that workflow's own words a false `unavailable` *"impugns a repair that in fact worked"*.
- **FR6** — the enumeration call at `:479-480` is **retained with a new meaning** (per-credential
  self-identification in map mode; one-result semantics in single mode) and is never again used
  to enumerate a project the credential does not own. The fatal guard at `:481-485` becomes a
  per-credential failure that counts the config UNREAD.
- **FR6b — `sort -u` at `:569`** (control C-d). The line is currently plain `sort`; the `sort -u`
  at `:226` is the *inventory* parse. Without `-u`, N assertions of one config still length-N the
  array. Mutation-tested: removing `-u` must red the suite.
- **FR6c — control C-c, conditional.** Per-credential self-identification, adopted **only if**
  P0.3 measures a Doppler-derived identifying field on both a root- and a branch-scoped
  credential. A mismatch counts the config **UNREAD** (giving it a channel) and emits
  `::error::token_drift_config_binding_mismatch`. Probe **exit status is captured, not
  discarded**: a non-zero exit emits `token_drift_identify_unreachable` and an empty answer
  `token_drift_identify_empty`, distinct from a mismatch — collapsing "the API 5xx'd" into "this
  credential is mis-bound" is the defect `:476-478` condemns in its own comment. If P0.3
  disqualifies every candidate, C-c is **dropped**, §D4's residual gap is recorded in the ADR,
  and C-a carries the class.
- **FR7** — the four read sites (`:536`, `:714`, `:741`, `:742`) use `${CRED_FOR[$cfg]}`. Whether
  `-p`/`-c` stay on argv is decided by **P0.3 q2**, not assumed: if a config-scoped token
  silently serves its bound config for a wrong `-c`, the script's comment that *"the config is
  named EXPLICITLY on every read"* has inverted into a false guarantee and must be rewritten (or
  the flags dropped), and test P3 moves with it.
- **FR7b** — `compute_coverage` (`:260-296`) changes in exactly one way: a **map-shape** failure
  (control C-b) becomes a second `unknown` trigger, evaluated first. Today `unknown` is reachable
  only via `FLOOR_OK == 0`; an absent/empty credential publishes `degraded` (`:445` says so
  verbatim) and **keeps doing so** (D3). Rationale: a malformed credential *source* is no
  measurement, and `unknown` is ADR-164's fail-closed default for "either side unparseable".
  Nothing else changes: `configs` counts successful reads, the `>=` gate is untouched.
- **FR7c** — `coverage_ratio` on any fail-closed path is `<successful reads>/<inventory count>`,
  i.e. `0/13` — never `-/-`. Verified reachable: `publish_verdict()` calls `emit_json()` which
  calls `compute_coverage()` unconditionally, and the workflow already passes `--inventory`
  (`scheduled-terraform-drift.yml:233`), so `CONFIGS_EXPECTED` is populated. `-/-` remains
  correct only when the verdict file itself is missing or corrupt.

**Workflow** (`.github/workflows/scheduled-terraform-drift.yml`)

- **FR8** — the `token_drift` step's `env:` (`:153-198`) drops `DOPPLER_TOKEN`, adds
  `DOPPLER_TOKEN_MAP: ${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }}`; `DOPPLER_PROJECT` and
  `DOPPLER_CONFIGS_FLOOR: 13` unchanged, `DOPPLER_CONFIG` still absent. The comment block
  (`:154-197`) is rewritten from the interim narration to the map shape, keeping the
  "three places move together" floor note in substance.
- **FR9 — the stale-prose sweep, and the enumeration IS the checklist.** Every site below is
  rewritten or deleted in this PR. `git grep -n 'doppler_service_account' .github/workflows/scheduled-terraform-drift.yml`
  returns 6 lines and **v1 of this plan missed the highest-traffic one**:
  - **`:422`** — the `degraded`-path `::warning::` in the token_drift step's own `run:` body,
    which fires on **every degraded run** and says the credential *"is a `doppler_service_account`
    holding a viewer membership on the whole soleur project, so there is nothing left to widen"*.
    Both clauses become false. This is outside every anchor v1 listed and outside any
    Remedy-scoped assertion.
  - **`:660-667`** — the **`unknown`** branch of the coverage-issue body: *"This is a DETECTOR
    fault, not a credential fault… Do not touch the Doppler identity… check for a truncated
    write in `emit_json`."* FR7b routes malformed-map faults here, which **are** credential
    faults. Rewritten. (v1 rewrote only the `else` branch and would have shipped this.)
  - **`:668-692`** — the `CONFIGS == 1` interim branch: **deleted**. It exists only to explain
    the interim 1/13 and would otherwise suppress the correct diagnosis of a real collapse.
  - **`:693-748`** — the `else` branch. `N1`/`N2`/`N3` are replaced by §D5's rows. The
    service-account paragraph (`:694-702`), the `environments` paragraph (`:724-726`), the
    `doppler_service_token`-repoint-as-fault paragraph (`:727-731`) and the
    `-replace=doppler_service_account_token.token_drift` recipe (`:739`) all become false and go.
    The `>=`-growth paragraph (`:743-748`) survives. **Constraint, verified against the step's
    `env:` (`:548-560`):** it receives only `COVERAGE`, `CONFIGS`, `CONFIGS_FLOOR`,
    `CONFIGS_EXPECTED`, `CONFIGS_UNREAD`, `COVERAGE_RATIO`, `INVENTORY_AGE_DAYS`, `VERDICT` —
    **no cause channel** — so the body must enumerate the possible causes and point at the run's
    annotations, never claim to have diagnosed one.
  - **`:156`**, **`:681-699`**, **`:710`**, **`:727-739`**, **`:1552`**, **`:1790-1795`** — the
    remaining resource/file references.
  - **`:1551-1555`** and **`:1790-1801`** — the rung-2 prose asserting that repointing that job
    at the token-drift credential *"would satisfy the predicate"*. False under the new shape too;
    the reason becomes structural, not elective. `RUNG2_CONFIGS_FLOOR: 13` (`:1500`) unchanged.
  - **`:802-829`** — the close arm's comment justifying the `configs_unread` conjunct via
    ephemeral configs padding the count. That route is structurally closed (a token can only
    assert a config Terraform minted it against) while the conjunct becomes load-bearing for a
    different reason (C-d).
- **FR10** — outside this workflow: `apps/web-platform/infra/kb-drift.tf:100-101` (the "one
  `doppler_service_account`" count and the file cross-reference);
  `scripts/check-cloudflare-token-drift.test.sh:1268` (the N3 comment);
  `scripts/encryption-posture-ledger.json` (the three now-dead `non_store_types` entries —
  verified harmless to leave, removed for hygiene). `plugins/soleur/skills/plan/SKILL.md:902`
  records the `ExactlyOneOf` lesson and is **kept**.
- **FR11** — widen the coverage-issue filer's gate so the `at-floor` + `configs_unread == '-'` +
  `verdict == 'unavailable'` state files (or refreshes) #7175 instead of falling between the
  filer and the closer. That state is reachable via the non-vacuity gate (`:278-281`,
  `:718-723`) and today leaves #7175 open with a stale body while the follow-through returns
  TRANSIENT forever — pinning AC-P3 permanently.
- **FR12** — `doppler-config-inventory.txt`: the *"THIS FILE REPORTS; IT GATES NOTHING"* claim is
  rewritten. New contract: it **also** determines which per-config tokens Terraform mints (the
  credential's reach), and it still gates **no verdict threshold** — the floor is declared
  independently. The "THREE `13`s MOVE TOGETHER" block gains the destroy-guard layer (SE-2) and
  the `prd_git_data` `depends_on` trap (SE-4), which is the block a future floor-raiser reads.

**Guards and tests**

- **FR13** — **C1** (`token-drift-workflow-causes.test.sh:1163`) re-points from
  `${{ secrets.DOPPLER_TOKEN }}` to `env.DOPPLER_TOKEN_MAP == '${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }}'`
  and asserts `env.DOPPLER_TOKEN` absent. Its fail message demands *"first re-run the enumeration
  probe against the real credential"* — satisfied by P0.3, which the new message names.
  **C2** (`:1188`) is strengthened, not relaxed: `env.DOPPLER_CONFIG` absent (unchanged), the
  bare-token grep goes from **== 1 to == 0**, and a new positive pin requires exactly one
  `secrets.DOPPLER_TOKEN_DRIFT_MAP` reference over the whole step YAML. Both counts use
  `grep -Eo … | wc -l` (occurrences), not `grep -Ec` (matching lines).
- **FR14 — new tests**, each mutation-tested (delete the guard → suite reds):
  - **C-a static test:** the `.tf` sets `config = each.key`, contains no `config = "` literal in
    the `token_drift` block, and the map's key and value derive from the same iteration
    variable. Anchored on the call form, not a bare token (`cq-assert-anchor-not-bare-token`).
  - **F5:** `local.token_drift_configs` is **set-equal** to the inventory's name lines. This is a
    stronger pin than "the `.tf` calls `file()`" and it is the reason no separate three-parser
    harness is built: it compares *contents*. Paired with two source greps — the `.tf` contains
    the literal `^[a-z0-9_]+$`, and contains no `trimspace(`/`trim(`/`chomp(`.
  - **`n5'`** — the producible mis-binding: 13 **distinct** tokens all bound to one config
    (passes shape validation, which is the point). With C-c: `1/13 degraded` + the mismatch
    annotation. Without C-c: the case is caught by C-a pre-merge and the runtime test asserts the
    honest fallback. **Mutation proof: remove `-u` from `:569` and this case reports `13/13`.**
  - **`n4'`** — one revoked token → `configs: 12`, `degraded`, `configs_unread` naming exactly it.
  - a malformed-map case → `unknown`, `0/13`, verdict published before exit 2, **zero doppler
    calls** (assert the stub's argv log is empty).
  - a masking-order case → a rejected-credential run prints no credential to the deliberately
    unsuppressed stderr; mutation-proven by moving the mask after the first `doppler` call.
  - a single-mode regression case driving the **real** argv of all five legacy call sites —
    including that **none passes `--configs-floor`**.
  - the stub (`check-cloudflare-token-drift.test.sh:72-154`) learns a token→config binding
    fixture so P3's per-config argv assertions gain teeth.
- **FR15** — **`FLOOR_MINIMUM=13` (`:1050`), the run-time `(( 10#$cfg_floor < 13 ))` (`:391`) and
  `RUNG2_CONFIGS_FLOOR: 13` (`:1500`) are NOT edited by this plan.** F5 and the C-a test are
  **additive**. F3 is an *equality* pin (`floor == inventory count`), so it cannot be the ratchet;
  the ratchet is those three literals plus the destroy guard (SE-2).
- **FR16** — `token-drift-coverage-7159.sh`: delete the hardcoded `1/*` TRANSIENT arm (`:96-106`)
  — it was the interim's and would grade a real collapse-to-one as transient forever. Keep the
  `0/*` arm (`:92-95`), which FR7c/D3 pin as the merge→apply shape. Add an arm treating an
  **unparseable ratio** (`-/-`, `-`, empty) as TRANSIENT, not FAIL: a run that published no
  parseable ratio measured nothing. Rewrite the FAIL remedy at `:107` (*"check the service-account
  membership role and its environments scope"* — a resource that will not exist) and the header
  at `:8-9` plus `:93`, both of which assert a `web-platform-infra-apply` **required-reviewer
  gate that no longer exists** (removed by PR #4220, `apply-web-platform-infra.yml:341`), so the
  `0/*` message currently tells the operator to wait for an approval that will never come.
- **FR17** — anti-vacuity floors rise: `>= 57` (`token-drift-workflow-causes.test.sh:1396`) and
  `>= 80` (`check-cloudflare-token-drift.test.sh:1806`) move up by the net-new case count. Never
  down.

**Apply path and closure**

- **FR18 — the destroy lands, or nothing does.** Add
  `-target=doppler_service_token.token_drift` (one leg covers all 13 instances, R1) and
  `-target=github_actions_secret.doppler_token_drift_map` to the default per-merge allow-list
  (`apply-web-platform-infra.yml:461-577`). **Keep** the four existing legs (`:523-526`) so the
  merge apply destroys the superseded resources — the parity test is explicitly one-directional
  (`terraform-target-parity.test.ts:34-36`), so stale legs red nothing. **`[ack-destroy]` must be
  on its own line in a BRANCH COMMIT MESSAGE BODY, not the PR body:** this repo is
  `squash_merge_commit_message: COMMIT_MESSAGES` (measured), so the squash body is the
  concatenated branch commit messages, and `apply-web-platform-infra.yml:666` matches only
  `HEAD_MSG`. Getting this wrong HALTs the apply on 4 planned deletes: no tokens created, no map
  published, and the already-repointed step reads an absent secret twice daily.
- **FR18b — two follow-ups filed in this PR** (`wg-when-deferring-a-capability-create-a`):
  (a) the `rung2-rehearsal-orphan-sweep` scratch probe is `unsatisfiable` by construction — no
  credential here can enumerate the project — so its gate needs re-shaping or retiring, together
  with D5's new standing blind spot (a Doppler-side config addition is now undetectable);
  (b) prune the four dead `-target=` legs, **gated on `terraform state list | grep -c doppler_service_account`
  returning 0**, not on a green apply — a *partial* destroy would otherwise leave a live orphaned
  identity the pruned legs can no longer address. (Verified 2026-08-03: no open issue tracks (a).)
  A third defect found in-session by the Phase-2.7 gate is **fixed inline, not filed**
  (`rf-review-finding-default-fix-inline`): `gdpr-gate`'s `notice-frontmatter.sh` staleness probe
  hard-codes `scheduled-content-vendor-drift.yml`, which no longer exists — verified; the job
  moved to `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`. One line.

## Non-Functional Requirements

- **NFR1 — per-credential masking, and it REVERSES an explicit in-file prohibition.** The block
  above `mask_value` (`:454-456`) states: *"The credential itself is deliberately NOT masked
  here: `::add-mask::<value>` writes the value to stdout, and the credential must reach no sink
  at all."* That reasoning was written for a whole-secret credential GitHub masks automatically.
  A JSON **map** is masked only as one whole string, so the 13 extracted values are unmasked —
  and the CLI's stderr is deliberately unsuppressed (`:476-478`), so a rejected-token error can
  print a live credential into a workflow log. So: **mask each credential the instant it is
  parsed out of the map and BEFORE the first `doppler` invocation of any kind**, and **rewrite
  that comment in the same PR** to record why the prohibition is overturned. Ordering is the
  requirement, not presence.
- **NFR2** — `access = "read"` on every token; no `read/write` credential minted; no credential
  on a child argv (tests P9/P11).
- **NFR3** — no new recurring vendor expense; no operator step at any point. Terraform mints,
  publishes and rotates in-band.

## Implementation Phases

Dependency-directed, not file-grouped: the credential contract lands before its consumers.

**Phase 0 — preconditions (probes, no edits).**
- **P0.1** `access = "read"` and `.key` — nine siblings already do it; read one.
- **P0.2** `terraform validate` with the new file present. Provider `ExactlyOneOf`-class
  validation does not appear in `terraform providers schema -json` (ADR-164); validate is the
  authority. It will **not** catch an API-side token-name rejection — `token-drift-ci-tf-prd_workspaces_luks`
  is 37 chars against siblings of 13-19; that only surfaces at apply, so note it.
- **P0.3 — the conditional-adoption probe.** Using an existing config-scoped credential:
  (1) does a config-scoped token self-identify, and **via which field**? Try `doppler me --json`
  (present in the pinned CLI v3.75.3, alias `whoami`) then `doppler configs -p soleur --json`.
  **Hard constraint: the field must be one Doppler DERIVES from the config binding, never one
  echoing the Terraform-supplied `name`** — a probe asserting a string Terraform put there is
  vacuous. (2) Does `doppler secrets -c <WRONG-config>` **error, or silently serve** the bound
  config? This decides whether `-p`/`-c` stay on argv and whether the script's "named EXPLICITLY
  on every read" comment has inverted. (3) Confirm on a **branch**-scoped credential — the parse
  is already recorded at `kb-drift.tf:94-96` (one entry, `success: true`, for a
  `prd_kb_drift_walker`-scoped token), so this is confirmation, not discovery. (4) Non-empty for
  the configs ADR-164's census called vacuous (`cli`, `cli_ops`). **If (1) or (3) fails, control
  C-c is dropped** — do not improvise a substitute mid-build.
- **P0.4 — the only pre-merge control on the new apply coupling.** Re-measure the inventory
  against live Doppler (`doppler configs -p soleur --json | jq -r '.[].name' | sort`). A stale
  inventory now breaks the merge apply, and `infra-validation.yml`'s plan job is
  `continue-on-error: true`.

**Phase 1 — Terraform (RED → GREEN).** FR1-FR4, FR18's legs. Write the C-a static test and the
parity assertion first; then the `.tf`; then the legs. Delete the old file and fix
`kb-drift.tf:100-101` in the same commit.

**Phase 2 — detector (RED → GREEN).** FR5-FR7c, FR6b, NFR1. Tests first: the binding fixture and
`n5'` must fail against the current script before it changes.

**Phase 3 — workflow.** FR8 lands **before** FR9's prose rewrites, so no intermediate commit has
new prose describing a step still on the old credential.

**Phase 4 — guards, sweep, probe.** FR10-FR17, FR18b. Mutation-test every new assertion.

**Phase 5 — ADR, C4, closure.** ADR-166 + the ADR-164 partial-supersede and Decision-2 bullet
amendment + the `github -> doppler` edge + `bash scripts/regenerate-c4-model.sh` and the
committed `model.likec4.json`. Re-derive the ordinal against freshly-fetched `origin/main`.

**Phase 6 — verify.** Full suite; `shellcheck`; `lint-workflows`; `terraform fmt -check` and
`validate`; `bun test plugins/soleur/test/`; `bash scripts/check-cloudflare-token-drift.test.sh`;
`bash plugins/soleur/test/token-drift-workflow-causes.test.sh`;
`bash plugins/soleur/test/c4-model-freshness.test.sh`;
`python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (CI's exact form,
**no explicit path list** — a hand-enumerated subset verifies a different set than CI does); and
`python3 scripts/lint-encryption-posture.py --repo-sweep` (CI's exact form, `ci.yml:263`).

## Acceptance Criteria

Every command below is written so a no-match `grep` cannot read as a failure under `pipefail`.

### Pre-merge

- [ ] **AC-A1** No superseded resource survives:
      `! git grep -qE 'resource[[:space:]]+"(doppler_service_account|doppler_project_member_service_account|doppler_service_account_token)"' -- 'apps/web-platform/infra'`
      (exits 0). `apps/web-platform/infra/token-drift-service-account.tf` does not exist.
      *(`grep -c` over `*.tf` would print one `path:0` line per file and miss `infra/modules/**` —
      do not use it.)*
- [ ] **AC-A2** The C-a static test passes and is mutation-proven: the `token_drift` resource
      block sets `config = each.key`, contains no `config = "` literal, and the map's key and
      value come from the same iteration variable.
- [ ] **AC-A3** F5 passes: `local.token_drift_configs` is set-equal to the inventory's name
      lines; the `.tf` contains the literal `^[a-z0-9_]+$` and contains no
      `trimspace(`/`trim(`/`chomp(`.
- [ ] **AC-A4** The `infra-validation` PR plan comment shows exactly 13
      `doppler_service_token.token_drift[...]` creates, 1
      `github_actions_secret.doppler_token_drift_map` create, 4 destroys, and no other create or
      destroy. *(Anchored on that job — `infra-validation.yml:1136-1200` already runs the
      unscoped plan with real credentials on every infra PR. An "unscoped local plan" would be an
      undeferred operator credential step. Sensitive values render as `(sensitive value)`.)*
- [ ] **AC-A5** `apply-web-platform-infra.yml` contains both new `-target=` legs **and still**
      all four legs at the old addresses.
- [ ] **AC-B1** The token-drift step's `env:` has no `DOPPLER_TOKEN` and no `DOPPLER_CONFIG`;
      over the extracted step YAML, occurrences of `secrets\.DOPPLER_TOKEN[[:space:]]*\}\}` are
      **0** and of `secrets\.DOPPLER_TOKEN_DRIFT_MAP[[:space:]]*\}\}` are **1** — counted with
      `grep -Eo … | wc -l`, since `grep -Ec` counts *lines* and would read 1 for two references
      sharing a line.
- [ ] **AC-B2** `n5'` (13 distinct tokens, all bound to one config) does **not** report `13/13`,
      and **removing `-u` from `:569` makes it report `13/13`** — the mutation proof for FR6b.
- [ ] **AC-B3** `n4'`: one revoked token → `configs: 12`, `degraded`, `configs_unread` naming
      exactly that config.
- [ ] **AC-B4** Single-credential mode is byte-for-byte unchanged, driven on the **real** argv of
      all five legacy call sites — `--only REGISTRY_PUSH_ACCESS_TOKEN` with a `prd`-root
      credential and no `DOPPLER_CONFIG`; `--only CI_SSH_ACCESS_TOKEN --json-file` with
      `DOPPLER_CONFIG: prd_terraform`; and the `doppler run -p soleur -c prd_terraform --` form —
      **none of which passes `--configs-floor`**.
- [ ] **AC-B5** A malformed map (non-object / zero keys / non-string values) publishes
      `coverage: unknown` with `coverage_ratio: 0/13` **before** exiting 2, and makes **zero**
      doppler calls (the stub's argv log is empty). An **absent or empty** map publishes
      `degraded 0/13` — the merge→apply shape the follow-through's `0/*` arm expects.
- [ ] **AC-B6** A rejected-credential run prints no credential to stderr; mutation-proven by
      moving the `::add-mask::` after the first `doppler` call. The `:454-456` comment forbidding
      credential masking is rewritten in the same diff.
- [ ] **AC-C1** The three ratchet literals are **byte-identical to `origin/main`**:
      `git diff origin/main...HEAD -- plugins/soleur/test/token-drift-workflow-causes.test.sh .github/workflows/scheduled-terraform-drift.yml | grep -E '^-.*(FLOOR_MINIMUM=13|cfg_floor.*< 13|RUNG2_CONFIGS_FLOOR:[[:space:]]*13)' ; test $? -eq 1`
      (`grep` exits 1 on no match, which is the pass).
- [ ] **AC-C2** Both anti-vacuity floors are strictly higher than on `origin/main`.
- [ ] **AC-C3** The stale-prose sweep is complete, asserted over the **source region this plan
      edits**, with an explicit terminator and a non-vacuity check:
      `awk '/^ *echo "### Remedy"/{f=1;next} /^ *- name: /{f=0} f' .github/workflows/scheduled-terraform-drift.yml`
      must emit a **non-empty** stream, and that stream plus the `token_drift` step's own `run:`
      body must contain zero occurrences of `doppler_service_account`,
      `doppler_project_member_service_account`, `workplace_permissions`, or
      `There is nothing here to widen`. *(A `/^### Remedy/` anchor extracts **zero** lines — the
      headings are 12-space-indented `echo` arguments — and would pass vacuously. The step-body
      clause is what reaches `:422`, which no Remedy-scoped assertion can see.)*
- [ ] **AC-C4** `git grep -n 'token-drift-service-account.tf' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/engineering/architecture/decisions' ':!knowledge-base/project/learnings' ':!**/archive/**'`
      returns no hits. *(The ADR and any `/compound` learning legitimately name the retired file
      — they are the record.)*
- [ ] **AC-C5** `token-drift-coverage-7159.sh` has no `1/*` arm, still has the `0/*` arm, has the
      unparseable-ratio arm, names no service-account resource, and asserts no
      `web-platform-infra-apply` reviewer gate. `bash -n` and `shellcheck` clean.
- [ ] **AC-C6** Every assertion removed from the guard ladder has a named replacement in the same
      suite, listed in the PR body as a removed→replacement table.
- [ ] **AC-D1** `ADR-166` (or its final ordinal) exists with `**Supersedes (in part):** ADR-164`;
      ADR-164 carries the reciprocal marker **and** its Decision-2 "gates NOTHING … changes no
      state" bullet is amended to "gates no verdict threshold".
- [ ] **AC-D2** `model.c4` contains a **single-line** `github -> doppler` relationship carrying
      **no numeric count**, and the regenerated `model.likec4.json` is committed:
      `bash plugins/soleur/test/c4-model-freshness.test.sh` passes.
- [ ] **AC-D3** `git log origin/main..HEAD --format=%B | grep -Fxq '[ack-destroy]'` succeeds — the
      ack is in a **branch commit message body**, because
      `squash_merge_commit_message: COMMIT_MESSAGES` (measured) means the merge commit is built
      from those, not from the PR body. The PR body additionally **names the four expected
      destroy addresses** so a reviewer can diff them against the apply's "will be destroyed"
      list; the guard counts deletes, it does not identify them.
- [ ] **AC-D4** The PR body uses `Closes #7234` and **`Ref #7159` / `Ref #7175`** — never
      `Closes`/`Resolves` for the latter two (SE-3).
- [ ] **AC-D5** Both FR18b follow-ups exist and are linked from the PR body; the
      `notice-frontmatter.sh` workflow-name fix is in the diff, not an issue.

### Post-merge (automated — no operator step)

- [ ] **AC-P1** The merge-triggered `apply-web-platform-infra` run applies cleanly: 13 token
      creates, 1 secret create, 4 destroys (`gh run view <id> --log`).
- [ ] **AC-P2** The next scheduled drift run logs `coverage: at-floor`, `ratio: 13/13`, and
      publishes `configs_unread=-`. Read via `gh run view <id> --json`/`--log`, **not** via the
      verdict log line alone — that line carries `causes/configs/floor/coverage/ratio` and
      **not** `configs_unread`, which is a step output.
- [ ] **AC-P3** #7175 auto-closes on that run, and
      `bash scripts/followthroughs/token-drift-coverage-7159.sh` returns **PASS**.
- [ ] **AC-P4** #7234 and #7159 are closed **only after AC-P1-AC-P3 hold against a real
      scheduled run.** A green CI run is not sufficient: #7162 was green on CI while reading zero
      configs (SE-3).

## Open Code-Review Overlap

**#7098** — *"ci: audit the 56 `run:` bodies whose `set` omits `-e`…"* — matches
`.github/workflows/apply-web-platform-infra.yml`. **Disposition: acknowledge.** A 56-body audit
of an orthogonal concern would multiply this PR's scope. Constraint accepted so this PR does not
grow that backlog: any `run:` body this plan *adds* opens with an explicit `set` line. The
`token_drift` step's existing `set -uo pipefail` (`:200`) deliberately omits `-e` — the step must
publish outputs before failing — and is left as-is.

No open review issue names any other file in this plan's edit set.

## Files to Create

- `apps/web-platform/infra/token-drift-read-tokens.tf`
- `knowledge-base/engineering/architecture/decisions/ADR-166-per-config-read-tokens-for-the-token-drift-scan.md` *(ordinal provisional)*
- `knowledge-base/project/specs/feat-one-shot-7234-per-config-doppler-service-tokens/tasks.md`

## Files to Edit

| File | Anchor | Change |
|---|---|---|
| `apps/web-platform/infra/token-drift-service-account.tf` | whole file | **delete** (FR4) |
| `apps/web-platform/infra/doppler-config-inventory.txt` | the "REPORTS; GATES NOTHING" and "THREE `13`s" blocks | rewrite for the dual role; add the destroy-guard layer and the `prd_git_data` `depends_on` trap (FR12, SE-2, SE-4) |
| `apps/web-platform/infra/kb-drift.tf` | `:100-101` | drop the `doppler_service_account` count and the file cross-reference (FR10) |
| `.github/workflows/apply-web-platform-infra.yml` | `:523-526` (keep) + insert beside | add 2 legs, keep 4 (FR18) |
| `.github/workflows/scheduled-terraform-drift.yml` | `:153-198`, **`:422`**, `:660-667`, `:668-692`, `:693-748`, `:802-829`, `:156`, `:681-699`, `:710`, `:727-739`, `:1551-1555`, `:1552`, `:1790-1801`; filer gate | FR8, FR9, FR11 |
| `scripts/check-cloudflare-token-drift.sh` | `:37-48` header, `:425-449`, **`:454-456`** (the mask prohibition), `:479-485`, `:536`, **`:569`**, `:714`, `:741-742` | FR5-FR7c, FR6b, NFR1 |
| `scripts/check-cloudflare-token-drift.test.sh` | `:72-154` stub, `:333-390` `run_sut`, `:1195-1214`, `:1235-1269`, `:1268`, `:1370`, `:1583`, `:1806` | FR14, FR17 |
| `plugins/soleur/test/token-drift-workflow-causes.test.sh` | `:1163` C1, `:1188` C2, `:1396` floor, new C-a + F5. **`:1050` `FLOOR_MINIMUM=13` NOT edited** | FR13-FR15, FR17 |
| `scripts/followthroughs/token-drift-coverage-7159.sh` | `:8-9`, `:92-95`, `:96-106`, `:93`, `:107` | FR16 |
| `scripts/encryption-posture-ledger.json` | the three retired `non_store_types` entries | remove (FR10) |
| `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh` | the hard-coded `scheduled-content-vendor-drift.yml` | point at the Inngest job (FR18b) |
| `knowledge-base/engineering/architecture/decisions/ADR-164-….md` | status header; the `for_each` Alternatives row; Decision 2's "gates NOTHING" bullet | partial-supersede marker + bullet amendment |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | relationships block, beside the `github -> *` edges | add `github -> doppler` (single line, no counts) |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | regenerated | `bash scripts/regenerate-c4-model.sh` |

## Risks & Mitigations

Only risks no FR already encodes.

| Risk | Mitigation |
|---|---|
| **P0.3 disqualifies self-identification**, and the plan has bet its safety property on an unmeasured credential capability — the #7162 mistake | Control C-c is explicitly **conditional**; C-a (static, pre-merge, free) carries the producible class regardless, and C-d (`sort -u`) is mandatory independently. The plan ships without C-c rather than improvising a substitute |
| **The ratchet does not hold ABOVE 13.** `FLOOR_MINIMUM=13` is a static lower bound and `FLOOR_HEADROOM=3` admits 14-16, so PR1 (git-data birth: inventory 14, floor 14) then PR2 ("that config was retired": inventory 13, floor 13) passes F2, F2b, F3 and the runtime check — and under the new shape PR2 **destroys a token**, cutting reach with no gate objecting | SE-2 names the destroy guard (`destroy-guard-filter-web-platform.jq` → `[ack-destroy]`) as the only above-13 layer. Noted, not fixed here: FR18 makes `[ack-destroy]` a routine line in *this* PR, which is how a reader learns to add it reflexively. Making F2 a monotonic ratchet against `origin/main`'s floor is the real fix and belongs to whoever raises the floor |
| `file()` makes the inventory a hard dependency of **every** plan in the infra root — deleting or renaming it breaks all applies | Stated so it is a known coupling. Three independent consumers (detector, CI check, Terraform) red before it can vanish unnoticed |
| An out-of-inventory assertion still pads `configs` — `compute_coverage` does not intersect `n` with `INVENTORY_NAMES`, so a Doppler-side rename could print `at-floor 13/13` while an inventory config is unread | Only `configs_unread` discriminates, and only the close arm consults it. Documented rather than changed: intersecting `n` is a Decision-2 change this plan is not authorised to make |
| A **partial** destroy leaves a live orphaned identity whose `-target=` leg has been pruned | FR18b(b) gates the prune on `terraform state list \| grep -c doppler_service_account == 0` |
| 13 tokens is 13 rotation obligations | Accepted cost of option (c), disclosed in the ADR; the whole-set `-replace=` form is generated from the inventory |

## Sharp Edges

- **SE-1 — the secret is renamed on purpose, and R3 is the hard argument.** `DOPPLER_TOKEN_DRIFT`
  (a bare token) → `DOPPLER_TOKEN_DRIFT_MAP` (a JSON object). The soft argument is that a bare
  name holding a map fails confusingly. The load-bearing one: with the rename,
  `grep -Eo 'secrets\.DOPPLER_TOKEN[[:space:]]*\}\}'` cleanly returns **0** because the
  `_DRIFT_MAP` suffix defeats the `\}\}` tail (measured, R3). Reuse the name and C2's `== 0`
  assertion becomes impossible to write. The rename is what makes AC-B1's clean 0/1 pair exist.
  Marginal cost is ~4 string edits — FR13 and FR16 change regardless, because the *env var* name
  changes either way.
- **SE-2 — the inventory's contract changes; the invariant survives on FOUR layers.** It now
  determines the credential's **reach** as well as the reported denominator. The naive defence
  ("the floor is a literal") is insufficient alone, because F3 pins `floor == inventory count`,
  so shrinking the inventory alone is impossible — CI forces the floor down to match. What
  preserves it: (1) `DOPPLER_CONFIGS_FLOOR: 13`; (2) the run-time `(( 10#$cfg_floor < 13 ))`,
  external to the declaration; (3) `FLOOR_MINIMUM=13`; **(4) the destroy guard** — shrinking the
  list now destroys a token, so `destroy-guard-filter-web-platform.jq` demands `[ack-destroy]`,
  which is the only layer that fires *above* 13. Strongest single evidence the coupling is
  fail-closed: a name failing `^[a-z0-9_]+$` is dropped by *both* the Terraform filter and
  `configs_expected`, producing `12/12` — which against the **literal** floor of 13 renders
  `degraded`, not `at-floor`. Do not derive the floor from the inventory, and do not delete any
  of the four layers.
- **SE-3 — `terraform plan` cannot tell you the credential works, and neither can CI.** The
  Doppler provider ships no data source that can enumerate service accounts or tokens (ADR-164),
  and a resource absent from state plans `to add` without calling the API. #7162 had a clean
  plan, a successful apply, and a credential that saw nothing. The only evidence this shape works
  is a **scheduled run against live Doppler** — which is why AC-P4 refuses to close on CI green
  and why the PR body says `Ref #7159`, never `Closes`.
- **SE-4 — `config = each.key` is a STRING, so it builds no dependency edge, and one future
  config is Terraform-managed.** Every name in today's inventory belongs to a config that
  pre-exists outside Terraform, so a literal `project` is correct. But `git-data-luks.tf` declares
  `doppler_config.git_data_prd`, and ADR-149 says `prd_git_data` appears at git-data birth. The
  PR that adds it to the inventory must ALSO add
  `depends_on = [doppler_config.git_data_prd]` to `doppler_service_token.token_drift`, or the
  token create can be ordered before the config exists and the apply fails on a race that reads
  as flake. **This lives in the inventory header's floor-raising block (FR12), not only here** —
  the floor-raiser reads that block, not this plan.

## Research Insights

**R1 — `-target=` on a `for_each` resource expands to every instance (measured).** Terraform
v1.10.5 (= the CI pin), throwaway root with `random_id.multi` over 3 keys plus an untargeted
sibling: `terraform plan -target=random_id.multi` → all three instances created, sibling
untouched. `terraform-target-parity.test.ts` matches the un-indexed base address on both sides
(`:347` resources, `:369` targets — the capture stops before `[`), so **one leg** satisfies the
parity guard. Voids ADR-164's "13 `-target=` legs".

**R2 — `jsonencode` over a `for_each` map of sensitive attributes (measured).** v1.10.5,
`random_password` over 3 keys: the encoded string is tracked **sensitive** (an `output` required
`sensitive = true`) and keys are emitted **sorted**, so the secret does not churn on re-plan.
`github_actions_secret.plaintext_value` already accepts sensitive values (five siblings do).
Voids ADR-164's "13 Actions secrets". `jsonencode` HTML-escapes `<`; Doppler tokens are
`dp.st.<name>.<url-safe>` so nothing escapes, but parse with `jq`, never a regex.

**R3 — C2's two greps, measured.** Against `DOPPLER_TOKEN_MAP: ${{ secrets.DOPPLER_TOKEN_DRIFT_MAP }}`:
the bare-token pattern → **0**, the map pattern → **1**. Adding a bare
`${{ secrets.DOPPLER_TOKEN }}` line returns the first to 1 — the mutation proof that `== 0` pins
something. Use `grep -Eo … | wc -l`, not `grep -Ec`.

**R4 — the HCL filter and the detector's grep agree, measured on the real inventory.** v1.10.5,
`can(regex("^[a-z0-9_]+$", _l))` over raw `split("\n")` lines against the committed file with
three adversarial lines appended: both accept the same 14 and reject the trailing-space line and
`UPPER`. Terraform's `regex` anchors per string, matching grep's per-line semantics, so **no
`trimspace()` is needed and adding one breaks the agreement**. The one measured divergence:
under a glibc `en_US.UTF-8` locale, `grep`'s `[a-z]` matches accented lowercase (`prdé`) while
RE2 does not — so FR1 pins `LC_ALL=C` on the grep sites rather than claiming unconditional
byte-identity. Dedup: HCL does not dedupe, which is why FR1 wraps the local in `distinct()` so
it is directly comparable to `grep … | sort -u`.

**R5 — the branch-config parse is already measured.** `kb-drift.tf:94-96` records that under
`doppler_service_token.kb_drift` — scoped to `prd_kb_drift_walker`, a **branch** config —
`doppler configs list` *"returns a list silently scoped to the caller (one entry, `success:
true`, no error)"*. P0.3 q3 confirms rather than discovers. `doppler me --json` exists in the
pinned CLI v3.75.3 (alias `whoami`) but appears **nowhere** in this repository, which is exactly
why C-c is conditional on measurement.

**R6 — `[ack-destroy]` is read from the merge commit, and this repo builds that from BRANCH
COMMIT MESSAGES.** Measured: `squash_merge_commit_message: COMMIT_MESSAGES`,
`squash_merge_commit_title: COMMIT_OR_PR_TITLE`. `/ship` and `merge-pr` both run bare
`gh pr merge --squash --auto` with no `--body`, so the repo setting governs, and
`apply-web-platform-infra.yml:666` matches only `HEAD_MSG`. A squash prefixes each commit
*subject* with `* ` but leaves body lines verbatim, so an ack on its own line in a commit body
survives. **A PR-body-only ack does not reach the gate.**

**R7 — consumer sweep** (`hr-write-boundary-sentinel-sweep-all-write-sites`,
`hr-type-widening-cross-consumer-grep` in spirit). The three resources are declared in exactly
one file. **No test anywhere asserts on their addresses**, so deletion breaks no suite directly —
the breakage is via the interim pin (`token-drift-workflow-causes.test.sh:1164-1186`) and the
parity guard. The slug `0519109d-…` appears **nowhere** in the repo. The sweep's first pass
undercounted twice and both corrections are folded into FR9/FR10: `scheduled-terraform-drift.yml:422`
(the degraded `::warning::`, the highest-traffic site) and the fifth detector invocation form
(`doppler run … -- check-cloudflare-token-drift.sh` in two operator-facing remedy strings).
`git grep -n 'doppler_service_account' .github/workflows/scheduled-terraform-drift.yml` returns
**6** lines — use that, not a memory of "~14 prose sites".

**R8 — learnings that bear directly** (paths verified):
`learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md` (a service token is scoped
at creation; `-c`/`DOPPLER_CONFIG` are ignored — the source of the D4 hazard);
`learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md` (branch
configs resolve the root's set — bounds what 13 read tokens reach);
`learnings/integration-issues/2026-05-29-targeted-apply-workflow-needs-new-resource-in-target-list.md`
(a resource absent from `-target=` is planned but never applied — drives FR18);
`learnings/best-practices/2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited.md` (the
enumeration is the checklist — drives R7 and AC-C3/AC-C4);
`learnings/best-practices/2026-07-07-followthrough-and-shape-gate-silent-falseness.md`
(verification code is the highest-leverage place for a silent false-green — drives every mutation
proof); `learnings/best-practices/2026-04-22-verification-claims-in-plans-decay-silently.md`
(drives P0.4); `learnings/best-practices/2026-05-20-tf-operator-mint-variables-are-design-smell.md`
(provider-side mint outranks operator mint — NFR3);
`learnings/workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md`
(the ADR-ordinal sweep must be branch-scoped).

**R9 — tooling verified locally** (2026-08-03): `terraform` v1.10.5, `doppler` v3.75.3, `jq`
1.8.1, `shellcheck` 0.10.0. Next free ADR ordinal on freshly-fetched `origin/main` is **166**.
`python3 scripts/lint-infra-no-human-steps.py` returns `OK` against this plan.

## Alternatives Considered

Full rationale belongs in ADR-166; this is the index.

| Alternative | Verdict |
|---|---|
| **(b) widen the service account's `workplace_permissions`** | **Rejected by the operator, 2026-08-03.** The only plausible candidate, `all_enclave_projects`, reaches every project in the workplace — wider than #7159 authorised — and it is *unmeasured* whether any workplace permission enables listing. Adopting it repeats #7162's exact error with a wider blast radius |
| **keep the service account provisioned as a spare** | **Rejected.** A live, project-wide, permanently useless credential is drift with a justification attached, plus a second revocation obligation for zero benefit |
| **`local.token_drift_configs` as an HCL literal list** | **Rejected.** A fifth place `13` lives, with no mechanism pinning it to the inventory — so one would have to be built. F5's set-equality obtains that for free, and the safety argument is unchanged because the *floor*, not the list, decides the verdict (SE-2) |
| **13 separate Actions secrets** | **Rejected.** 13 env keys, 13 rotations, and C2's single-reference assertion becomes 13 |
| **reuse `DOPPLER_TOKEN_DRIFT` for the map** | **Rejected.** A type change disguised as a value change, and it makes C2's `== 0` unwritable (SE-1) |
| **keep `doppler configs -p soleur` as the config list** | **Rejected — it is the capability that does not exist.** A config-scoped credential returns a list silently scoped to itself with `success: true`, so the denominator narrows in lockstep with the numerator and `13/13` prints through every narrowing |
| **trust the map's key count as `configs`** | **Rejected.** 13 keys with 13 dead tokens would read `13/13` |
| **a pairwise-distinctness gate as the anti-mis-binding control** | **Rejected as the primary.** It tests distinct *strings*, but the invariant is distinct *bindings* — the producible defect (`config = "prd"`) mints 13 distinct tokens and sails through. Retained only as part of C-b's shape validation |
| **provenance-derived counting (`CONFIG_NAMES` from the assertion, mismatch does not withhold the read)** | **Rejected.** It was designed against a *shuffled* map, which `jsonencode` over one instance cannot produce — and it left `binding_mismatch` with no channel, so a mismatched run would still satisfy the close arm and close #7175 |
| **add a `binding_mismatches` list to the JSON verdict schema** | **Rejected as churn.** `emit_json`'s argv contract is 11 positional scalars behind 3 list sentinels; counting a mismatch UNREAD reuses `configs_unread` and gives the same channel |
| **fix the rung-2 unsatisfiable gate here** | **Deferred — FR18b(a).** It needs a project-enumerating credential this repo structurally lacks; its replacement is its own decision. The false prose is still corrected here |

## Review Findings Applied

The 5-agent panel + CTO + advisor found 4 P0s and 12 P1s against v1. Audit trail:

| Finding | Source | Landed |
|---|---|---|
| **P0** `sort -u` at `:569` **does not exist** (plain `sort`), so v1's central "misassembly cannot forge the count" claim was false against shipped code | spec-flow | FR6b, AC-B2's mutation proof, §Overview item 1 |
| **P0** `[ack-destroy]` in the PR body never reaches the merge commit — `squash_merge_commit_message: COMMIT_MESSAGES` | kieran | FR18, AC-D3, R6 |
| **P0** v1's AC11/TS2/AC13/TS10 asserted three different outcomes for one input, and the mutation proof could not be constructed | spec-flow + architecture | the distinctness gate demoted to shape validation; `n5'` re-authored against the **producible** case (13 distinct tokens, one config) |
| **P0** the `unknown` issue branch says *"a DETECTOR fault, not a credential fault"* — and v1 routed credential faults there while rewriting only the `else` branch | spec-flow | D3 pins mode selection on `-n` so the merge window stays `degraded`; FR9 rewrites `:660-667` |
| **P1** `:422`'s degraded `::warning::` names the service account and was outside every v1 anchor | spec-flow + kieran | FR9 first bullet; AC-C3's step-body clause |
| **P1** NFR2 reversed an explicit in-file prohibition (`:454-456`) without naming it | architecture + spec-flow | NFR1 names and rewrites it |
| **P1** `Closes #7159` would close it at merge, defeating AC-P4 and the follow-through's own stated premise | architecture | AC-D4, SE-3, the title block |
| **P1** the ratchet does not hold above 13; `FLOOR_HEADROOM=3` admits a 14→13 round trip | architecture | SE-2's fourth layer + a Risks row |
| **P1** ADR-164 Decision 2's "gates NOTHING … changes no state" bullet **is** falsified by FR1 | architecture | §ADR amends that one bullet |
| **P1** `model.likec4.json` must be regenerated (`c4-model-freshness.test.sh`, required shard) | architecture | Files to Edit, Phase 5, AC-D2 |
| **P1** D1 and FR2 prescribed different token names; D1 is the block an implementer copies | code-simplicity + kieran | D1 made byte-identical to FR2 |
| **P1** "merge-blocking" was false — `infra-validation.yml`'s plan job is `continue-on-error` and its validate job is `-backend=false` | kieran | D5's last row, Observability, P0.4 named as the only pre-merge control |
| **P1** AC5's unscoped **local** plan is an undeferred operator credential step | kieran | AC-A4 anchored on the existing PR plan job |
| **P1** the `at-floor` + `unread=='-'` + `unavailable` dead zone strands #7175 and pins the probe TRANSIENT forever | spec-flow | FR11, Observability's last failure mode |
| **P1** `binding_mismatch` had no channel; the close arm would fire on a run with a live defect | spec-flow | C-c counts the config UNREAD |
| **P1** the legacy-consumer contract was mis-stated — **none** passes `--configs-floor`, and there is a fifth invocation form | CTO + architecture | Research Reconciliation, FR5b, AC-B4, R7 |
| **P1** a third inventory parser with divergent whitespace semantics | CTO | FR1 forbids `trimspace()`; R4 measures the agreement; F5 pins contents |
| **P1** the probe discarded exit status, collapsing "the API 5xx'd" into "mis-bound" | CTO | FR6c's three distinct causes |
| **P1** an untemplated token name makes a name-echoing identify field vacuous | CTO | FR2 templates it; P0.3's hard constraint |
| **P2** AC14's `awk '/^### Remedy/…'` extracts **zero** lines and passes vacuously | kieran | AC-C3's anchored form + non-vacuity clause |
| **P2** AC2's `grep -c` over `*.tf` prints per-file counts and misses `infra/modules/**` | kieran | AC-A1's `git grep -q` form |
| **P2** the C4 label hardcoded three `13`s into the one file with a count-parity gate, as a multi-line string | architecture + DHH | single line, no counts, rationale moved to the ADR |
| **P2** `discoverability_test` errors on an in-progress run; `grep -m1` SIGPIPEs `gh` | kieran | `--status success` + `tail -1` |
| **P2** the follow-through asserts a reviewer gate removed by PR #4220 | spec-flow | FR16 |
| **P2** `DOPPLER_TOKEN_MAP` should be unset after the parse, per the discipline of the block it replaces | architecture | FR5 |
| **taste** the plan was ~1,300 lines of scaffolding around a loop; the `Test Scenarios` table duplicated the ACs 1:1; CI-green ACs, six restating-NFRs, and four self-referential Sharp Edges were ceremony | DHH + code-simplicity | table deleted, ACs consolidated 35→22, FRs merged, Risks cut to the 6 no FR encodes, Alternatives reduced to an index pointing at the ADR |

Two panel recommendations were **declined**, with reasons, per `rf-when-a-reviewer-or-user-says-to-keep-a`:

- **DHH: cut the runtime binding control entirely** ("a shuffle requires Terraform to lie").
  Correct about the shuffle, which is why provenance-counting was dropped — but architecture and
  spec-flow independently identified a *producible* defect the argument does not cover
  (`config = "prd"` instead of `each.key`: 13 distinct tokens, one config). That is why the
  control set is now C-a (static, free, pre-merge) with C-c **conditional on measurement**,
  rather than either "13 probes always" or "nothing".
- **DHH: amend ADR-164 in place rather than a second ADR.** Declined for Decision 1 — the record
  that a shape was chosen on measured evidence, shipped, and failed is the most valuable thing
  #7162 produced, and overwriting it loses that. Accepted in part: Decision 2's falsified bullet
  **is** amended in place rather than left standing behind a pointer.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/compliance (`gdpr-gate`). Product, Marketing,
Sales, Finance, Operations, Support: not relevant — CI/infra tooling, no user-facing surface, no
pricing or positioning implication, no new recurring vendor expense.

### Engineering (CTO) — reviewed

Shape sound, complexity medium (days). Seven P1s, all applied (see §Review Findings Applied).
Confirmed against the real guards: `terraform-target-parity.test.ts:34-36` declines the
reverse-direction check, so the four legs pointing at config-deleted resources red nothing (AC-A5
is safe); that file's `-target=` regex reduces a `for_each` target to its base address,
corroborating R1 against the real matcher; `destroy-guard-filter-web-platform.jq` counts deletes
generically, so FR18's ack is required. No capability gaps.

### Legal / compliance (`gdpr-gate`, Phase 2.7 trigger (b)) — reviewed

*Advisory only — not legal review.* The canonical regulated-surface regex matched **zero** files
across the plan and all entries of its Files lists. All five mandatory v1 checks returned no
finding: no new column (Art. 6), no new PII table (Art. 5(1)(e)), no FK to `users` and no
migration (Art. 17), no Art. 9 special-category column, no Chapter V trigger (Doppler Inc,
GitHub Inc and Cloudflare Inc are all already rows in `compliance-posture.md`'s Vendor DPA
table; no new processor is engaged and the data flow is inbound). **Zero Critical, zero
Important.** No Art. 30 amendment trigger — the scan processes machine credentials, not personal
data. Nothing written, no issue filed. One advisory Art. 32(1)(b) Suggestion was accepted and
folded into §User-Brand Impact: `--only-names` pulls each config's full key-*name* listing even
though only token-shaped *values* are fetched. The gate also surfaced an unrelated repo-hygiene
defect, fixed inline as FR18b rather than filed.

### Product/UX Gate

**Tier: none.** The mechanical UI-surface override did not fire — no path in Files to
Create/Edit matches a UI-surface term or glob. No `.pen` is owed under
`wg-ui-feature-requires-pen-wireframe`.

### CPO sign-off

`single-user incident` sets `requires_cpo_signoff: true`. Per the sign-off lifecycle staging the
plan-phase obligation is the single product-owner ack on the technical approach; the approach was
chosen by the operator this session with the falsifying measurement in hand.
`user-impact-reviewer` runs at review time against the diff.

### Scoped advisor consult (Phase 4.5) — reviewed

Two changes adopted: make the new inventory test **additive** to the ratchet literals rather than
a replacement (identified as "the single most likely wrong-architecture commit in the plan" —
FR15, SE-2, AC-C1); and the observation that a JSON map is masked only as one whole string while
the CLI's stderr is deliberately unsuppressed, now NFR1 with an ordering requirement and a
mutation-proven test. Its third proposal — provenance-derived counting — was adopted in v1 and
then **withdrawn** on the panel's evidence that it defends an impossible case and leaves the
mismatch signal without a channel.
