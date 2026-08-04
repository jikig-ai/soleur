# ADR-164 — A project-scoped Doppler service account reads the fleet; the coverage floor is declared, not derived

- **Status:** Accepted — **Decision 1 superseded by [ADR-168](./ADR-168-per-config-read-tokens-for-the-token-drift-scan.md) (2026-08-03); Decision 2 amended in one bullet, otherwise in force**
- **Date:** 2026-08-03
- **PR:** #7162
- **Issue:** #7159 (the token-drift scan reads one Doppler config and calls the result healthy)
- **Related:** [ADR-154](./ADR-154-repair-the-credential-channel-not-the-host.md) (the
  `CI_SSH_ACCESS_TOKEN` pair behind the 63-hour outage — the credential a literal token swap would
  have dropped out of scan range), [ADR-007](./ADR-007-doppler-secrets-management.md) (the Doppler
  posture this widens), [ADR-149](./ADR-149-git-data-host-birth-route-and-readiness-interlock.md)
  (git-data birth declares `doppler_config.git_data_prd`, the first change that must raise the
  floor), `scripts/check-cloudflare-token-drift.sh` (the detector),
  `.github/workflows/scheduled-terraform-drift.yml` (the only consumer of the credential)

> **Ordinal — provisional until merge, and this is the FIFTH time it has moved.** Authored as
> **ADR-155**; 155, 156 and 157 were all claimed on `origin/main` by sibling PRs mid-pipeline, so
> it was renumbered to **158**. While this branch was still in flight, **158** was itself claimed
> by `ADR-158-kb-file-tree-host-is-a-derived-value.md` (merged via #7189) — renumbered to **159**.
> A rebase onto `origin/main` then pulled in `ADR-159-delivery-is-not-activation.md` → **160**.
> A BEHIND auto-sync at merge time then pulled in `ADR-160-enforcement-tag-grammar-conforms-to-the-corpus.md`
> **plus** 161 and 162 → **163**. A second BEHIND sync then pulled in
> `ADR-163-birth-filesystem-features-must-be-mountable-by-the-target-image.md`, so it is
> renumbered a fifth time to **164**.
>
> Five moves on one branch is the datum, not the anecdote: an ordinal is claimed at *merge*, and
> this pipeline's plan→ship span is long enough that the claim reliably goes stale. Every one of
> the four was surfaced by a `fetch`, a `rebase`, or a BEHIND sync — **never by a gate on this
> branch**, because `adr-ordinals` is not a required check. Re-run `scripts/check-adr-ordinals.sh`
> after ANY sync whose merge output lists the decisions directory, and read its exit code
> directly: `bash …/check-adr-ordinals.sh | tail -3` reports `tail`'s status, not the script's.
>
> An ordinal picked on a branch is a *claim*, not a reservation: nothing in the repo reserves one,
> and the collision is invisible from a branch that is behind `origin/main` — each of the three
> was surfaced only by a fetch or a rebase, never by a gate. Re-check against a freshly fetched
> `origin/main` immediately before merge, and sweep every citation — the `.tf` files, the plan,
> the spec, the tasks file and `decision-challenges.md` — in the same PR.
>
> **Sweep the OWN-ordinal only.** A blanket `ADR-<n>` → `ADR-<n+1>` replace is the wrong tool and
> has now mis-fired twice on this branch: once rewriting a reference *inside this very note* (so
> it read "158 was claimed by ADR-158", a sentence that is false and reads as true), and once
> rewriting bare `ADR-159` citations in ten files belonging to *other* work — `ci-deploy.sh`,
> `model.c4`, the #7103 spec — that legitimately cite the sibling ADR-159. Restrict the sweep to
> files in this branch's own diff (`git diff --name-only origin/main...HEAD`), and remember the
> prose form: a replace keyed on `ADR-159` silently misses a bold bare **159** in a sentence.

## Context

`scripts/check-cloudflare-token-drift.sh` grades every Cloudflare API token and Access service
token it can find in Doppler, twice daily. It ran under a single config-scoped
`doppler_service_token` and reported a `coverage` enum whose healthy state — `multi-config`,
"more than one config" — had **no denominator at all**, so it could not distinguish *2 of 13* from
*13 of 13*.

Everything below was measured: a per-config census on **2026-08-02** and probes A–G on
**2026-08-03**, each against live Doppler with an ephemeral read credential revoked in the same
command.

**What a config-scoped credential can see.** A `prd`-ROOT Doppler service token enumerates
**exactly one** config. `doppler configs -p soleur --token <root>` returns `['prd']`; raw
`GET /v3/configs?project=soleur` returns 1 with `success: true` — a list silently scoped to the
caller, not an error — and `GET /v3/environments?project=soleur` returns `[]`. This is not a quirk:
service tokens are config-scoped by construction, and this repository already states it verbatim —
"BLAST RADIUS: a Doppler service token is CONFIG-scoped"
(`apps/web-platform/infra/web-probe-read-token.tf:20`). The detector, meanwhile, loops over
**configs** (the `doppler configs -p "$PROJECT" --json` enumeration), not over credentials. Value
inheritance from a root config to its branches therefore gives the scan no visibility whatsoever —
and a branch config can **override** an inherited value, which is precisely the fan-out drift class
the detector exists to catch.

**The shape of the live project.** 13 configs across 4 environments: `dev` (3), `ci` (1), `prd`
(7), `cli` (2). The `prd` environment's **7** is the detector header's own motivating case, which
cites a credential "stale in 5 of 7 configs".

**Why the checklist's swap was not a fix.** #7159 asked for a literal repoint of the token-drift
step's `DOPPLER_TOKEN` from the `prd_terraform` credential to a `prd`-root one. The two configs'
key sets are **not in a superset relation in either direction**: `prd_terraform` alone holds
`CI_SSH_ACCESS_TOKEN_ID` / `_SECRET` — the ADR-154 outage credential — plus 8 `CF_API_TOKEN*` keys
that `prd` root does **not** carry (10 `CF_API_TOKEN*` in `prd_terraform` in total — the plan and the
spec quote the total, this line quotes the exclusive subset, and "alone holds" did not disambiguate
them);
`prd` root alone holds `REGISTRY_PUSH_ACCESS_TOKEN_ID` / `_SECRET`. Swapping one config-scoped token
for another was therefore a **coverage regression**, and it still left `configs` at 1, which makes
the checklist's own `multi-config` Done-when **unreachable by the change that was supposed to
satisfy it**.

**Provenance, stated so it cannot be mistaken.** The evidence above is the 2026-08-02 census and
the 2026-08-03 probes. It is deliberately **not** Doppler's config-inheritance metadata
(`inheriting` / `inherits`, which is off everywhere): that metadata describes Doppler's *explicit
cross-config inheritance feature*, not the built-in environment-root-to-branch behaviour. The
inheritance framing is exactly what made the original #7159 decision read as sound, and no
conclusion here leans on it.

## Decision

Two decisions, one change.

### 1. The scan runs as a project-scoped service account

> **SUPERSEDED 2026-08-03 by [ADR-168](./ADR-168-per-config-read-tokens-for-the-token-drift-scan.md).
> DO NOT BUILD ON THIS DECISION — ITS CENTRAL PREMISE WAS NEVER MEASURED AND IS FALSE.**
> Everything below rests on the inference that a project-scoped `doppler_service_account`
> with a `viewer` project membership can enumerate and read every config. #7234 measured
> that credential against live Doppler: it could do **neither**. `doppler configs -p soleur
> --json` returned `null`, and reading `prd` returned *"Could not find requested config
> 'prd'"*. The scan therefore read **nothing**, not thirteen configs.
>
> ADR-168 replaces this credential with 13 config-scoped `doppler_service_token`s under one
> `for_each` over the committed inventory, published as a single Actions secret
> `DOPPLER_TOKEN_DRIFT_MAP`. The blast-radius analysis, the `viewer` role probe and the
> `workplace_permissions = []` reasoning below are retained as the record of what was
> decided and why — they are **not** a description of what runs today, and the whole
> `doppler_service_account` / `doppler_service_account_token` /
> `doppler_project_member_service_account` triple has been retired from the infra root.
>
> Marked inline, alongside Decision 2's amendment, because the status line at the top of a
> 270-line ADR is not where a reader lands when they arrive from a code comment or a search
> hit — and this section reads as current, load-bearing design.

**The #7159 premise is falsified.** The issue's three-row option table rested on the assertion that
*"there is no project-scoped read token to mint."* That is **true of `doppler_service_token`**,
which is config-scoped by construction and is the reason the config-scoped shapes were all dead
ends. It is **false of `doppler_service_account`**: the pinned `DopplerHQ/doppler v1.21.2` — read
from the binary already in `.terraform`, not from vendor docs — ships `doppler_service_account`
alongside `doppler_service_account_token` and `doppler_project_member_service_account`. That is a
provider-minted, project-scoped identity requiring no credential-entry step, and it was absent from
the option table entirely. The operator was shown the measurements and chose this shape on
2026-08-03.

The credential is one `project-scoped service account`:
`doppler_service_account.token_drift`, a `doppler_project_member_service_account.token_drift` at
`project = "soleur"` / `role = "viewer"` with `environments` **unset**, and a
`doppler_service_account_token.token_drift` published as the Actions secret `DOPPLER_TOKEN_DRIFT`
with exactly one consumer. `DOPPLER_TOKEN` in the token-drift step then becomes the literal swap
#7159 asked for — safe this time, because the new credential's reach is a superset of the old one's
rather than a sideways move.

**The role.** `viewer` is the least-privileged project role that can read secret *values*: per
`GET /v3/projects/roles` it carries `enclave_project_config_secrets_read` and does **not** carry
`enclave_project_config_secrets_write`; the only lower role, `no_access`, has zero permissions and
cannot run the scan. `viewer` is not purely read-only, and that is disclosed rather than elided — it
also carries `enclave_project_config_dynamic_secrets_leases_write` (a **write** verb: it can create
dynamic-secret leases), `enclave_project_config_dynamic_secrets_read`,
`enclave_project_config_rotated_secrets_read` and `enclave_config_logs`.

**`workplace_permissions = []`, and why "leave both unset" is not available.** The pinned provider
enforces `ExactlyOneOf` on `workplace_permissions` / `workplace_role`, so exactly one of the two
must be present — an account with neither fails validation. `workplace_permissions = []` is the
least-privileged value that satisfies the constraint, and it leaves the project membership as the
identity's **only** grant, so the identity can reach no other Doppler project. This is *provider-side
validation*: it does **not** appear in `terraform providers schema -json`, so the schema probe alone
would not have surfaced it.

**Blast radius — accepted, disclosed, and wider than what it replaces.** This credential reads the
**whole `soleur` project**: all four environments, all 13 configs. That is broader than the "whole
`prd` tree" #7159 was prepared to accept, and it is **wider than the pre-existing
`DOPPLER_TOKEN_PRD`**, which is `prd`-root-scoped. Concretely, its reach includes
`GHCR_MINTER_DOPPLER_TOKEN` — itself a Doppler token declared `access = "read/write"` — and the
Terraform GitHub App private key, whose installation holds `secrets:write` and can therefore rewrite
every repository Actions secret including `DOPPLER_TOKEN_DRIFT` itself. The earlier revision's
mitigation, "this adds no new capability — only a second copy", is **withdrawn as false**, not
softened. The operator chose this shape after being shown these measurements; it is an accepted,
disclosed trade-off and is recorded here rather than buried.

What genuinely bounds it, each verified rather than assumed: the project membership is the only
grant (above); the role cannot write secret values (roles probe); the credential is
Terraform-managed and rotatable by `-replace=` in a single apply, which `DOPPLER_TOKEN_PRD` is not;
and the detector reads only *token-shaped* key families, bounding what transits the runner to the
50 scannable key occurrences the 2026-08-03 census counted rather than every secret in the project.
An incident response must revoke **both** this credential and `DOPPLER_TOKEN_PRD`; only this one is
Terraform-managed.

### 2. The coverage gate and the coverage report are different numbers: a declared floor, reported ratio

A project-scoped credential makes any denominator taken from the scan's own listing hold **by
construction** — the ratio would print `13/13` forever and `degraded` would have no producer. So the
gate and the report are split:

- **`configs_floor` is declared, and gates.** It is a literal in the token-drift step's own `env:` —
  `DOPPLER_CONFIGS_FLOOR: 13` — read from nowhere else. It states not a fact about Doppler but a
  demand the step makes of its own credential: *the identity I was handed must reach at least this
  many configs.* A step cannot be wrong about a number it declares.
- **The gate is one-sided:** `configs < floor → degraded`, `configs >= floor → at-floor`. `>=`, not
  `==`, because the project is expected to grow (git-data birth, ephemeral rehearsal configs) and
  growth must not red a cron twice daily. Growth pushes the printed ratio above 1 and changes no
  state.
- **`configs` counts configs whose read SUCCEEDED**, not configs enumerated. A role that can list
  but not read values would otherwise list 13, scan none, and satisfy the floor while measuring
  nothing.
- **The committed inventory reports, and gates no verdict THRESHOLD.**
  `apps/web-platform/infra/doppler-config-inventory.txt` supplies `coverage_ratio`,
  `configs_unread` and `inventory_age_days`. A short, long or stale inventory changes the printed
  ratio and the unread list and moves **no verdict state**: no arm starts or stops firing on
  account of it, no issue opens or closes. A denominator that gates is a denominator that can
  derive the healthy state and close the channel.
  > **AMENDED 2026-08-03 by [ADR-168](./ADR-168-per-config-read-tokens-for-the-token-drift-scan.md).**
  > This bullet originally read *"gates NOTHING … changes no state"*, and that is now **false**.
  > ADR-168 derives the per-config read tokens' `for_each` from this file, so the name lines
  > determine the credential's REACH — a shortened inventory mints fewer tokens and destroys the
  > ones it drops. What survives is the narrower claim above: it gates no verdict *threshold*,
  > because the floor is a literal declared independently in the workflow. The rest of this
  > Decision 2 stands. Amended in place rather than left standing behind a pointer, because a
  > reader deleting a line from that file would have trusted this sentence.
- **A CI assertion pins the floor equal to the inventory's name count**, in
  `plugins/soleur/test/token-drift-workflow-causes.test.sh`, alongside a run-time re-assertion of
  `configs_floor >= 13` that is *external* to the declaration — a number cannot catch its own
  reduction. This is what stops a floor being quietly lowered in the same change that narrows the
  grant. It reads no credential and makes no network call, so it cannot be defeated by narrowing
  the credential, and it cannot red a merge because live Doppler grew.

The ladder becomes `unknown` (either side unparseable — the fail-closed default) → `degraded`
(`configs < floor`) → `at-floor` (`configs >= floor`), evaluated in that order. `multi-config`,
`single-config` and `full` are retired: `single-config` collapses into `degraded` at a floor of 13,
and `full` would have been a state with no reachable producer whose only consumer was the issue
close arm. `at-floor` keeps its name rather than becoming `full` even though the steady state is
`13/13`, because the state is defined against the declared floor and not against the project — a
name asserting completeness would invite a future reader to gate on the inventory again.

**What `degraded` concretely detects**, and it is the whole point: an absent or empty credential,
and a revoked one. Every one is a real, producible regression with a performable remedy — the
property `multi-config` never had.

> **AMENDED 2026-08-03 by [ADR-168](./ADR-168-per-config-read-tokens-for-the-token-drift-scan.md)
> — THREE OF THE FIVE LISTED PRODUCERS NO LONGER EXIST.** This paragraph used to open with *"a role
> downgrade (`0/13`), a membership scoped to a subset of environments (`7/13`, with
> `configs_unread` naming the six dropped configs), a repoint back to a config-scoped token
> (`1/13`)"*. All three describe ways to narrow a **project-scoped service account**, and there is
> no longer one: there is no role and no environment-scoped membership to downgrade, and "a repoint
> back to a config-scoped token" is the shape that now ships. A list of producers that cannot occur
> reads as coverage the ladder does not have, which is the failure mode the paragraph's own last
> sentence complains about in `multi-config`.
>
> The producers under the map shape, each real: the `DOPPLER_TOKEN_DRIFT_MAP` secret absent or
> empty (`0/13` — this is also the shape of the merge→apply window before it is first published);
> a map with fewer entries than the floor, which is what a shortened inventory or a destroyed token
> instance produces; individual tokens revoked or expired, which fail their own reads and are named
> in `configs_unread` while the rest still count; and the `config = <literal>` mis-binding, which
> mints 13 distinct tokens all bound to one config and surfaces as `1/13` with 12 access-denied
> reads. That last one is now caught pre-merge by C-a in
> `plugins/soleur/test/token-drift-workflow-causes.test.sh` rather than by a scheduled run up to
> 12 hours later.

## Consequences

- The scan goes from 1 config to 13, and from 11 token-shaped values graded to the fleet set. The
  first case the detector's own header cites as motivating it — `REGISTRY_PUSH_ACCESS_TOKEN` — was
  not scanned at all before this change.
- The standing `token-drift-coverage` issue can now close on `at-floor` at `13/13` rather than on a
  partial ratio, so the coverage channel goes back to signalling regression.
- One more credential must be revoked during incident response, and it is the widest read
  credential in the Doppler project.
- More secret material transits the CI runner — 50 scannable key occurrences against 18 under the
  two-config union — which is why every distinct scanned value is registered with `::add-mask::`
  before the first probe, in the same change that deliberately stops swallowing the enumeration's
  stderr.

## Known limitations

- **A deleted config produces a false `degraded`** until the floor and inventory are lowered. Left
  as-is deliberately: a mechanism that let a shrinking live count lower its own alarm threshold is
  the narrowing class this design exists to catch, with extra steps. Noisy in the safe direction.
- **The inventory is expected to drift.** `git-data-luks.tf` already declares a `prd_git_data`
  config that will exist after git-data birth; rehearsal dispatches create ephemeral ones. The
  change that alters the project's config set owns both edits — floor and inventory — in the same
  PR.

- **The `13` ratchet decays silently unless the pinned literals are raised together.** The
  minimum is asserted in independent places that are not derived from each other:

  | Site | Literal |
  |---|---|
  | `plugins/soleur/test/token-drift-workflow-causes.test.sh` — `FLOOR_MINIMUM=13` (F2/F3) | pre-merge, repo-internal |
  | `.github/workflows/scheduled-terraform-drift.yml` — the token_drift step's `(( 10#$cfg_floor < 13 ))` run-time re-assertion | per-run, external to the declaration |

  A third literal, `RUNG2_CONFIGS_FLOOR: 13` in the same workflow's `rung2-rehearsal-orphan-sweep`
  job, declares the same demand for the scratch-config sweep and moves with them.

  **When the floor legitimately rises** — git-data birth adding `prd_git_data` is the known one —
  raise `DOPPLER_CONFIGS_FLOOR`, regenerate `doppler-config-inventory.txt`, **and raise all three
  `13`s in the same PR.** The failure this prevents is specific and quiet: with the floor at 14 and
  `FLOOR_MINIMUM` left at 13, a later PR can narrow the grant back to 13 configs, lower
  `DOPPLER_CONFIGS_FLOOR` to 13 to match, and pass F1, F2, F3 and the run-time assertion with **no
  test edited** — the ratchet has silently returned to its old notch. F3's inventory-equality pin
  does not catch it either, because that PR would regenerate the inventory too. The `13`s are the
  only thing that makes a *reduction in the COUNT* visible in a diff, which is why raising them is
  a deliberate edit and never an automated one.

  > **AMENDED 2026-08-03 by [ADR-168](./ADR-168-per-config-read-tokens-for-the-token-drift-scan.md)
  > — THIS BLOCK IS THE PRE-#7234 THREE-LITERAL VERSION, AND THE INVENTORY'S OWN HEADER CITES IT.**
  > Two corrections. First, all three literals above bound a **COUNT**, and since ADR-168 the
  > inventory's name lines are the `for_each` key set, so what matters is a **SET**: a RENAME moves
  > no count at all, so every pin above holds while one config goes permanently unread and a token
  > is minted for a config that does not exist. Second, the 14→13 round trip this block describes as
  > uncaught **is now caught** — by a fourth site, `INVENTORY_REMOVALS_ACK` (assertion **F4b**) in
  > the same test file, which asserts the inventory's name set is a SUPERSET of the same file's at
  > the merge base. Retiring a config for real means naming it there, which is the same
  > deliberate-edit discipline as `FLOOR_MINIMUM`.
  >
  > The earlier revision also leaned on the apply's destroy guard as "the only layer that fires
  > above 13". That is withdrawn rather than softened:
  > `destroy-guard-filter-web-platform.jq` counts planned deletes **inside** the
  > `[ack-destroy]`-bypassable `destroy_count` sum — the same file's comments record why
  > `host_creates` and `reboot_updates` were deliberately placed *outside* it — so a PR carrying
  > that ack for an unrelated reason waves the token deletes through with it. ADR-168's own merge
  > commit is exactly such a PR. The guard also has no `for_each` instance-delete case among its 40
  > tfplan fixtures. It is defence in depth behind F4b, never the gate.
- **An orphaned state write on the create is invisible to `terraform plan`.** The provider ships no
  data source that can enumerate service accounts or their tokens, so a lost state write leaves a
  live credential with no Terraform record; the remedy is `-replace=`.
  > **CORRECTED 2026-08-03 by [ADR-168](./ADR-168-per-config-read-tokens-for-the-token-drift-scan.md).**
  > This bullet named "the count-asserting `terraform state list` check" as the detector for that
  > orphan. **No such check exists in this Terraform root.** `grep -rn 'terraform state list'` over
  > `apps/web-platform/infra/` and `.github/workflows/` returns a comment in `seo-config-rules.tf`,
  > a line in `sentry/README.md`, and two live uses in `apply-github-infra.yml` — a *different*
  > root. The web-platform apply has none, so this risk currently has **no detector at all**, which
  > is a materially different disclosure from "detected by a check". Tracked with the dead
  > `-target=` legs in issue #7254, which is gated on the same state read.
  >
  > The severity claim is also inverted by ADR-168: the sentence said the risk was *"strictly
  > larger at this shape than at a config-scoped one, because an orphan now reads the whole
  > project."* The shape that shipped **is** config-scoped — 13 tokens each reaching exactly one
  > config — so an orphan leaks one config's read access rather than the project's, while there
  > are now 13 instances that can individually orphan instead of one.
- **The governing control on a repository-level secret is who can merge under `.github/workflows/`.**
  `CODEOWNERS` pins that path to the operator, but no ruleset in IaC enforces CODEOWNERS review.
  Pre-existing and unchanged by this ADR — named so "repository-scoped like every sibling" is not
  misread as a control.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **A union of two config-scoped `doppler_service_token`s** — keep the `prd_terraform` credential, add a `prd`-root one | **Rejected.** It reads 2 of 13 while carrying `prd`-root blast radius. At N=2 the union *is* `for_each` with the loop unrolled, so it takes that option's cost without its generality, and it forces a credential-iteration surface through the detector that the chosen shape does not need at all. Decisively, #7159's own "Known follow-up" warns that a 2-config scan "would go quiet while still missing the fan-out class" — which is exactly what a union's `at-floor` close arm would have done. |
| **A `for_each` credential per config** (13 `doppler_service_token`s) | **Rejected here; ADOPTED by [ADR-168](./ADR-168-per-config-read-tokens-for-the-token-drift-scan.md) after this rejection was falsified by measurement.** The rejection read: "13 credentials, 13 Actions secrets, 13 `-target=` legs and a detector that loops credentials, to obtain what one project membership obtains — and every credential is an independent rotation and revocation obligation." Measured 2026-08-03: **one** Actions secret (`jsonencode` over the `for_each` map is tracked sensitive and key-sorted), **one** `-target=` leg (targeting a `for_each` resource expands to every instance), and the project membership obtains **nothing** — it could neither enumerate nor read. Three of the four cost claims were wrong and the premise they were weighed against was void. Only the rotation-obligation clause survives, and ADR-168 accepts it. |
| **Reuse `DOPPLER_TOKEN_TF`** | **Rejected.** It is a workplace-scope personal token; reusing it would make the scheduled scan a consumer of the widest credential in the repo, and it is not scoped, rotatable or revocable independently of everything else that uses it. |
| **Reuse the existing `DOPPLER_TOKEN_PRD` repo secret** | **Rejected.** Not Terraform-managed, shared by six consumers, not rotatable by `-replace=`, and config-scoped to `prd` root — so it reads 1 of 13. |
| **A denominator that gates the state** | **Rejected.** A short inventory would derive the healthy state, fire the close arm and silence the channel — fail-open in the exact direction the design claims to guard. |
| **A denominator taken from the scan's own credential** (`GET /v3/configs`, `GET /v3/environments`) | **Rejected on structure.** Both endpoints return a list silently scoped to the caller, so the denominator narrows in lockstep with the numerator and `13/13` prints forever through every narrowing. More seductive at this shape, not less, because the number it prints is correct today. |
| **A cross-workflow step verifying the inventory against live Doppler** | **Rejected.** It needs a listing credential — and the only one that can list the whole project is this credential — so it has the same two-place defeat condition as the repo-internal pin while adding a network dependency, a second live-credential consumer, and a merge blocker that reds on legitimate growth. |
| **Assert the credential's identity class** ("is this a service-account token?") | **Rejected.** It detects a repoint to a config-scoped token and nothing else: a service-account token narrowed by `environments`, or sitting at a reduced role, asserts as the same class while reading a fraction of the project. A check that is green through two of three failure modes reads as coverage and is worse than none. |
| **Scope the membership with `environments = ["prd"]`** | **Rejected.** The 2026-08-03 per-config census puts 7 scannable keys in `dev*` and `ci`, which this would forfeit, while removing **none** of the escalation hops — they all live in `prd` root. Narrower on paper, no narrower in consequence. Only `cli` and `cli_ops` are vacuous. |
