# egress gateway image — pin provenance

Analysis of record for the `EGRESS_GW_IMAGE` pin in `egress-gateway-bootstrap.sh`
(#9534 / feat-open-web-egress). Read by `egress-gw-image-staleness.test.sh` (CI
gate) and by the upstream-poll step in `.github/workflows/rule-audit.yml`
(detection). Mirrors `zot-image.provenance.md`.

**The gateway is the sole policy plane for open-web egress.** A wrong or
retagged pin does not degrade the boundary — it can break CONNECT entirely
(the synthetic probe pages) or silently swap Squid versions. Treat every row
below as load-bearing.

| Field | Value |
|---|---|
| Pinned reference | `ubuntu/squid@sha256:6a097f68bae708cedbabd6188d68c7e2e7a38cedd05a176e1cc0ba29e3bbe029` |
| Tag polled | `ubuntu/squid:latest` (Canonical's maintained Squid image; multi-arch index) |
| Capture date (UTC) | **2026-10-05** |
| Superseded | none (initial pin) |

## Re-pin procedure

```bash
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ubuntu/squid:pull" | jq -r .token)
curl -sI "https://registry-1.docker.io/v2/ubuntu/squid/manifests/latest" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  | grep -i docker-content-digest
```

1. Update `EGRESS_GW_IMAGE` default in `egress-gateway-bootstrap.sh`.
2. Update the Pinned reference + Capture date rows above.
3. The digest MUST be the index (manifest-list) digest — web hosts are amd64
   but a platform-specific manifest pin breaks the next arch change and the
   poll step compares against the index digest specifically.
4. Bump lands via the normal PR → `terraform_data.egress_gateway` redelivery
   (config_hash includes the bootstrap file).
