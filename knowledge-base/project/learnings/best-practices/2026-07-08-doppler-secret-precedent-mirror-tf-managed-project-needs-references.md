# Learning: mirroring a `doppler_secret` — literals vs references depend on whether the target project is TF-managed

## Problem

While wiring `BETTERSTACK_LOGS_TOKEN` into the isolated `soleur-inngest/prd` Doppler
project (#6197), I authored the new `doppler_secret` by mirroring the closest precedent
I found — `ghcr-read-credential.tf`, which pins its target with **string literals**:

```hcl
resource "doppler_secret" "ghcr_read_token" {
  project = "soleur"     # literal
  config  = "prd"        # literal
  ...
}
```

Copied verbatim into `inngest-betterstack-token.tf`:

```hcl
resource "doppler_secret" "inngest_betterstack_logs_token" {
  project = "soleur-inngest"   # literal — WRONG here
  config  = "prd"              # literal — WRONG here
  ...
}
```

`terraform validate` + `fmt` passed green. The terraform-architect review agent caught it
as a real correctness/ordering bug.

## Root cause

The two precedents look identical but differ on one load-bearing axis: **is the target
Doppler project/config a TF-managed resource in the same config?**

- `soleur/prd` is a **pre-existing, non-TF-managed** project — there is no
  `doppler_project.soleur` resource to reference, so `ghcr-read-credential.tf` MUST use
  literals. Correct there.
- `soleur-inngest/prd` **is** TF-managed — `inngest-host.tf` declares
  `doppler_project.inngest` + `doppler_environment.inngest_prd`, and every sibling
  dedicated secret wires them by reference:
  ```hcl
  project = doppler_project.inngest.name
  config  = doppler_environment.inngest_prd.slug
  ```

Using literals against a TF-managed project creates **no dependency graph edge**, so:

1. On a cold/full untargeted apply, Terraform can schedule the `doppler_secret` before the
   project + environment exist → `Could not find requested config 'prd'` (non-deterministic
   parallelism luck).
2. A `-target=doppler_secret.inngest_betterstack_logs_token` dispatch will NOT pull in
   `doppler_project.inngest` / `doppler_environment.inngest_prd` — no edge to follow.

## Solution

Reference the TF-managed parents (mirror the *sibling in the same file*, not the
literal-using precedent in a different project):

```hcl
project    = doppler_project.inngest.name
config     = doppler_environment.inngest_prd.slug
visibility = "masked"   # also matches the in-project convention (siblings all set it)
```

## Key Insight

**A precedent is only a valid template if its *environment* matches, not just its *shape*.**
When mirroring any resource that references a parent (`doppler_secret`→project/config,
`hcloud_volume_attachment`→server, a policy→role), check whether the parent is TF-managed
**in the same config**: use references (build the edge) if it is; literals only if the
parent is genuinely out-of-band. The cheapest gate: before copying a precedent, grep the
target file for a *sibling* of the same resource type and prefer its wiring over a
same-type precedent in a different project. This is the `doppler_secret` instance of the
general rule "mirror the closest-environment precedent, verify env parity first."

## Session Errors

- **doppler_secret literal-vs-reference precedent mismatch** — Recovery: switched to
  `doppler_project.inngest.name`/`doppler_environment.inngest_prd.slug` + `visibility="masked"`.
  Prevention: the Key Insight above, routed to the terraform-architect agent.
- **Test-8 drift-guard assertion string wrong** (`vector-${vec_triple}.tar.gz` vs the URL's
  actual `vector-${VECTOR_CLI_VERSION}-${vec_triple}.tar.gz`) — Recovery: relaxed the grep to
  `${vec_triple}.tar.gz`. Prevention: derive drift-guard grep literals from the as-written
  file, not from a mental reconstruction of the interpolation (run the test immediately).
- **`terraform fmt -check` on a `.sh` file → rc=2** — Recovery: scoped fmt to `.tf` only.
  Prevention: one-off; `terraform fmt` only accepts `.tf`/`.tfvars`.
- **Narrow grep for `hcloud_server_network.inngest` in `inngest-host.tf` alone** returned
  nothing (it lives in `network.tf`), briefly suggesting the resource was absent — Recovery:
  widened the grep across all `*.tf`. Prevention: for "does resource X exist" questions on a
  multi-file infra dir, grep the whole directory, not the topically-named file.

## Tags
category: best-practices
module: apps/web-platform/infra
