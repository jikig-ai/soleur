# ADR-168 — Per-config read tokens for the token-drift scan; the committed inventory becomes the reach

- **Status:** Accepted
- **Date:** 2026-08-03
- **PR:** #7241
- **Issue:** #7234 (the project-scoped Doppler service account cannot enumerate configs — drift scan reads 0 of 13)
- **Supersedes (in part):** [ADR-164](./ADR-164-project-scoped-service-account-and-declared-coverage-floor.md)
  — Decision 1 only. Decision 2 stands, with one bullet amended in place.
- **Related:** [ADR-007](./ADR-007-doppler-secrets-management.md) (the Doppler posture),
  [ADR-149](./ADR-149-git-data-host-birth-route-and-readiness-interlock.md)
  (git-data birth declares `doppler_config.git_data_prd`, the first change that must raise the
  floor — and now also the first that needs a `depends_on`),
  `apps/web-platform/infra/token-drift-read-tokens.tf` (the credentials),
  `scripts/check-cloudflare-token-drift.sh` (the detector),
  `.github/workflows/scheduled-terraform-drift.yml` (the only consumer)

## Context

ADR-164 chose a project-scoped `doppler_service_account` with a `viewer` project membership to
give the twice-daily Cloudflare token-drift scan read access across all 13 configs of the Doppler
`soleur` project. That shape was applied. The credential was minted, the membership created, the
token published as `DOPPLER_TOKEN_DRIFT` — and the first real scan reported:

```
token-drift verdict: unavailable (detector exit 2, causes: -, configs: 0,
                                  floor: 13, coverage: degraded, ratio: 0/13)
ERROR: could not enumerate Doppler configs for project 'soleur'
```

Everything structural was correct. Verified live against the Doppler API: the service account
existed, the project membership existed with `role=viewer`, the token existed, the Actions secret
was published. What the credential could not do was **see the project at all**.

### The measurement

An ephemeral token was minted for the existing service account, probed, and revoked in the same
command:

```
DOPPLER_TOKEN=<sa-token> doppler configs -p soleur --json
  -> null                                              (0 configs visible)

DOPPLER_TOKEN=<sa-token> doppler secrets -p soleur -c prd --only-names --json
  -> {"error":"Could not find requested config 'prd'"}
```

Neither enumerate **nor** read. This is not a listing-only gap and not a CLI auth-form difference
— the CLI authenticates fine and resolves an empty project view. `workplace_permissions = []`,
chosen in ADR-164 as the least-privileged value satisfying the provider's `ExactlyOneOf`
constraint, yields `workplace_role: no_access`, and workplace-level visibility turns out to be a
**precondition** for project-scoped access rather than something a project membership can confer
on its own.

### Why ADR-164 got here

Every other premise in #7159 was falsified by measurement — the prd-root token reads 1 config, the
key sets are not a superset, the provider enforces `ExactlyOneOf`. The one premise that was
**inferred rather than probed** was the load-bearing one: that a service-account credential can
enumerate every config in the project. It was inferred from the pinned provider shipping the
`doppler_service_account` resource type at all.

That is the transferable lesson, and it is why this is a new ADR rather than an edit to ADR-164:
the record that a shape was chosen on measured evidence, shipped, and *failed* is the most
valuable thing #7162 produced. Overwriting it would lose exactly the part worth keeping.

## Decision

**Mint one config-scoped `doppler_service_token` per config, under a single `for_each` over the
committed inventory, and publish them as ONE Actions secret carrying a JSON map keyed by config
name.**

```hcl
locals {
  token_drift_configs = distinct([
    for _l in split("\n", file("${path.module}/doppler-config-inventory.txt")) :
    _l if can(regex("^[a-z0-9_]+$", _l))
  ])
}

resource "doppler_service_token" "token_drift" {
  for_each = toset(local.token_drift_configs)
  project  = "soleur"
  config   = each.key
  name     = "token-drift-ci-tf-${each.key}"
  access   = "read"
}
```

The detector stops asking Doppler to enumerate the project — a capability no credential in this
repository has — and iterates the map's keys.

The operator made this call on 2026-08-03 with the measurement in hand, choosing it over widening
the service account's `workplace_permissions`. The only plausible listing permission,
`all_enclave_projects`, reaches **every** project in the workplace — strictly wider than the single
`soleur` project #7159 authorised — and it was *unmeasured* whether any workplace permission would
have worked. Adopting it would have repeated #7162's exact error with a wider blast radius.

### ADR-164's rejection of this exact shape is void

ADR-164's Alternatives table rejected *"a `for_each` credential per config (13
`doppler_service_token`s)"* as *"13 credentials, 13 Actions secrets, 13 `-target=` legs and a
detector that loops credentials, to obtain what one project membership obtains."* Measured, all
four clauses are wrong:

| ADR-164 claim | Measured |
|---|---|
| 13 Actions secrets | **1.** `jsonencode` over a `for_each` map tracks the encoded string as sensitive and emits keys sorted, so one secret carries all 13 and does not churn on re-plan. ~800 bytes against a 48 KB limit. |
| 13 `-target=` legs | **1.** `-target=` on a `for_each` resource expands to every instance (measured on the CI pin, v1.10.5), and `terraform-target-parity.test.ts` matches the un-indexed base address on both sides. |
| "to obtain what one project membership obtains" | The membership obtains **nothing**. |
| a detector that loops credentials | True, and it is now the cheaper half — see the binding control below. |

## The mis-binding hazard, and the control set

`config = "prd"` written in place of `config = each.key` mints **13 distinct tokens with 13 correct
map keys, all bound to one config**. It passes every shape check there is, pairwise distinctness
included — which is why a distinctness gate was rejected as the primary control. Terraform cannot
produce a *shuffle* (key and value come from the same instance), so this is the whole producible
class.

Four controls, cost-ordered:

- **C-a — static, pre-merge, free.** A test asserts the `.tf` sets `config = each.key` and rejects
  a string literal, over comment-stripped HCL (the file documents the hazard in prose beside the
  attribute, so a bare grep would match the warning against the defect).
- **C-b — parse-time, zero network.** The map must parse as an object of non-empty string values
  with Doppler-shaped keys, before any call is made.
- **C-c — the read itself.** See below.
- **C-d — `sort -u` on the config-name array.** `configs` is that array's length, so a duplicate
  inflates coverage directly.

### C-c is the read, because a wrong `-c` errors

The plan for this change specified a per-credential self-identification probe, conditional on
measuring a Doppler-derived identifying field. The probe measured *admissible*
(`doppler configs -p soleur --json` returns exactly one entry whose name is derived from the
binding, on both root and branch configs; `doppler me --json` is **not** admissible — its `name` is
the value the caller supplied at create time, so a probe on it would be vacuous).

But the same probe measured something better:

```
token bound to prd (ROOT)
  -c prd            -> 129 keys
  -c dev / ci / cli / prd_terraform / prd_ghcr
                    -> rc=1  "This token does not have access to requested config 'X'"
token bound to prd_kb_drift_walker (BRANCH)
  -c prd_kb_drift_walker -> 130 keys
  -c prd                 -> rc=1   (a branch token cannot read its own root)
```

**A config-scoped token errors on a wrong `-c`. It does not silently serve its bound config.** So
pairing `CRED_FOR[$cfg]` with `-c "$cfg"` asserts the binding on every read: under the mis-binding
above, twelve reads fail closed, twelve configs count UNREAD, and the run grades `1/13 degraded`
naming them. The separate probe would have issued 13 extra API calls per run to re-derive a
property the very next call enforces, so it was dropped and its three distinct causes (binding
mismatch / unreachable / empty diagnostic) preserved from the read's own failure shape.

This **contradicts** `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`,
which records that `-c`/`DOPPLER_CONFIG` are ignored. That learning is correct for the
`configs list` verb — which does return a list silently scoped to the caller, as `kb-drift.tf`
records — and wrong for `secrets` in the pinned CLI v3.75.3. **The two verbs differ; do not
generalise either one.**

## Consequences

**The committed inventory now determines reach, not just the reported denominator.** It is the
`for_each` list. This is the one bullet of ADR-164 Decision 2 that is falsified — *"the committed
inventory reports, and gates NOTHING … changes no state"* — and it is amended in place there to
"gates no verdict *threshold*", which remains true: the floor is a literal declared independently.

That makes the ratchet a four-layer property, and the fourth layer is the only one that fires
*above* 13. The naive argument ("the floor is a literal, so a shrink is impossible") fails, because
F3 pins `floor == inventory count` — CI forces the floor down to match a shrunken inventory — and
`FLOOR_HEADROOM=3` admits a 14→13 round trip. What remains is the **destroy guard**: shrinking the
list destroys a token, so the apply HALTs without `[ack-destroy]` on its own line in the merge
commit message.

**A new standing blind spot.** Denominator and reach now share one source, so a config added
*Doppler-side* and absent from the inventory has no token, is never read, and is not in
`configs_expected` either — nothing reports it. Detecting that needs the project-enumerating
capability this repository structurally lacks. Tracked with the related rung-2 gap on #7233.

**More rotation surface.** Thirteen tokens is thirteen rotation obligations. Per token:
`terraform apply -replace='doppler_service_token.token_drift["<config>"]' -target='doppler_service_token.token_drift["<config>"]' -target='github_actions_secret.doppler_token_drift_map'` (both `-target=`s are load-bearing: without the first the apply plans the whole root; without the second the map is pruned as a *dependent* and republishes the destroyed token); whole-set rotation is
one `-replace=` per config in a single apply, generated from the inventory. The map republishes in
the same apply either way. This is the accepted cost of the shape.

**A new detection capability.** One config's token being revoked now reads as
`12/13 degraded` naming that config. Under the project-scoped credential this was **invisible** —
one dead grant was indistinguishable from a healthy fleet.

**Blast radius is unchanged from ADR-164, and becomes real.** Thirteen read credentials covering
the whole project, including `prd`. That reach was disclosed and accepted at #7159; what changes is
that today's *live* reach is one config, and this makes the accepted reach actual. A leaked
`DOPPLER_TOKEN_DRIFT_MAP` or a leaked R2 state key yields all thirteen at once.

**Masking is now required, reversing an explicit in-file prohibition.** Actions masks the map as
one opaque string, so values extracted from it are unmasked — in a script that deliberately does
not suppress the Doppler CLI's stderr. Each credential is registered with `::add-mask::` before the
first CLI invocation.

**`terraform plan` still cannot tell you this works.** The Doppler provider ships no data source
that can enumerate service tokens, and a resource absent from state plans `to add` without calling
the API. #7162 had a clean plan, a successful apply, and a credential that saw nothing. The only
evidence is a scheduled run against live Doppler — which is why #7234 and #7159 close on that, not
on merge.

## Alternatives considered

| Alternative | Verdict |
|---|---|
| Widen the service account's `workplace_permissions` | **Rejected by the operator.** The only plausible value reaches every project in the workplace, wider than #7159 authorised, and it is unmeasured whether any workplace permission enables listing. |
| Keep the service account provisioned as a spare | **Rejected.** A live, project-wide, permanently useless credential is drift with a justification attached, plus a second revocation obligation for zero benefit. |
| `local.token_drift_configs` as an HCL literal list | **Rejected.** A fifth place `13` lives, pinned to the inventory by nothing. Deriving it gets set-equality for free. |
| 13 separate Actions secrets | **Rejected.** 13 env keys, 13 rotations, and the single-reference assertion becomes 13. |
| Reuse the `DOPPLER_TOKEN_DRIFT` name for the map | **Rejected.** A type change disguised as a value change — and the `_MAP` suffix is what lets the bare-token grep reach a clean 0, because `secrets\.DOPPLER_TOKEN[[:space:]]*\}\}` cannot match `secrets.DOPPLER_TOKEN_DRIFT_MAP }}`. Reusing the name makes that assertion unwritable. |
| Keep `doppler configs -p soleur` as the config list | **Rejected — it is the capability that does not exist.** A config-scoped credential returns a list scoped to itself with `success: true`, so the denominator narrows in lockstep with the numerator and `13/13` prints through every narrowing. |
| Trust the map's key count as `configs` | **Rejected.** 13 keys with 13 dead tokens would read `13/13`. |
| A pairwise-distinctness gate as the primary anti-mis-binding control | **Rejected.** It tests distinct *strings*; the invariant is distinct *bindings*, and the producible defect mints 13 distinct tokens. Retained only as part of C-b. |
| A per-credential self-identification probe | **Rejected after measurement.** Admissible, but redundant: the read already enforces the binding, so it would cost 13 extra API calls per run for a better error message. Its three causes are preserved from the read's failure shape. |

## Known limitations

- The blind spot above: Doppler-side config *additions* are undetectable.
- `configs` is not intersected with the inventory, so an out-of-inventory read could in principle
  pad the count. Under this shape that route is structurally closed (a token can only assert a
  config Terraform minted it against), and `configs_unread` remains the discriminator.
- The rung-2 orphan sweep's scratch-config probe stays unsatisfiable — see #7233.
