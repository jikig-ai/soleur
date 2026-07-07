# Learning: the Hetzner cloud-init user_data cap is measured on the GZIPPED render, not the raw file

## Problem

Authoring the zot pull-fallback logic inline in `cloud-init.yml` (#6122) appeared blocked by a
comment in `soleur-host-bootstrap-observability.test.sh`: "the 32,768-byte cap has only ~0.4 KB
headroom". `cloud-init.yml` is 36,121 raw bytes — already OVER the cap — so a naive read said
"no room to add anything, route to a baked helper instead".

## Solution

The web host's user_data is `base64gzip(templatefile("cloud-init.yml", …))` (`server.tf` — the
`#6090` gzip-first change, mirroring `git-data.tf`). The cap applies to the **base64-of-gzip**
render, not the raw file. Measured it directly:

```bash
gzip -9 -c apps/web-platform/infra/cloud-init.yml | base64 -w0 | wc -c   # → 16984
```

16,984 / 32,768 → **~15 KB real headroom** (shell payload is highly compressible). The "~0.4 KB"
comment is stale — it predates the `#6090` gzip wrapper. With real headroom confirmed, the inline
fallback logic (a `/run/soleur-image-ref` resolver + threaded reads across 4 runcmd blocks) was
cap-safe, and no baked-helper detour was needed.

## Key Insight

When reasoning about the Hetzner 32,768-byte user_data cap for a cloud-init that Terraform wraps
in `base64gzip(templatefile(...))`, **measure `gzip -9 -c <file> | base64 -w0 | wc -c`, never `wc
-c <file>`**. The raw size can be comfortably OVER the cap while the compressed render sits at
~half. A stale in-tree "headroom" comment is a hypothesis to re-measure, not a fact — the same
"plan-quoted numbers are preconditions to verify" discipline applies to code comments about
budgets. Grep `server.tf` for `base64gzip`/`gzip` on the `user_data =` line to confirm the wrap
before trusting any raw-byte headroom claim.

## Tags
category: best-practices
module: infra, cloud-init, hetzner
