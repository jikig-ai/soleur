---
title: "Tenant DPA register (SYNTHESIZED TEST FIXTURE — not the live register)"
type: tenant-dpa-register-fixture
status: fixture
---

# Tenant DPA register — synthesized fixture

**This file is a test fixture.** Every value is synthesized (`cq-test-fixtures-synthesized-only`);
no row describes a real tenant, a real legal entity, or a real founder. It exists because the DPA
gate in `provision-hetzner.sh` runs BEFORE the `--dry-run` branch and reads
`knowledge-base/legal/tenant-dpa-register.md` relative to the working directory — so a
characterization suite running outside the repository exits 3 without a register to read.

`Status` is the 7th visible column, which is `awk -F'|'` field `$8` (field `$1` is the empty
string left of the leading pipe).

## Rows

| Tenant slug | Legal entity | Founder UUID | DPA signed date | DPA counter-signed date | Sub-processors (Schedule 2) | Status | Notes |
|---|---|---|---|---|---|---|---|
| fixture-tenant | Fixture Entity SARL | 00000000-0000-4000-8000-000000000000 | 2026-01-01 | 2026-01-02 | hetzner, cloudflare | dpa-signed | synthesized fixture row |
| fixture-inflight | Fixture Inflight SARL | 00000000-0000-4000-8000-000000000001 | 2026-01-03 | | hetzner | provisioning-in-progress | synthesized fixture row |
| fixture-revoked | Fixture Revoked SARL | 00000000-0000-4000-8000-000000000002 | 2026-01-04 | 2026-01-05 | hetzner | terminated | synthesized: must NOT pass the gate |
| fixture-offboarded | Fixture Offboarded SARL | 00000000-0000-4000-8000-000000000003 | 2026-01-06 | 2026-01-07 | hetzner | dpa-signed | synthesized: historical row of an offboarded tenant (register is append-only) |
| fixture-offboarded | Fixture Offboarded SARL | 00000000-0000-4000-8000-000000000003 | 2026-01-06 | 2026-01-07 | hetzner | terminated | synthesized: the LATER row wins; must NOT pass the gate |
