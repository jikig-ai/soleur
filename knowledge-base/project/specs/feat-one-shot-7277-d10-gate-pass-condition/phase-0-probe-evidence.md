# Phase 0 probe evidence (#7277)

Measured 2026-08-05. Every row is a command + its real output — no inferred values.
These pin the abort/degrade boundary A5 rests on, so a later edit that changes a
classification string must change this file too.

## 0.8 — next-free ADR ordinal

```
$ git ls-tree -r --name-only origin/main -- knowledge-base/engineering/architecture/decisions/ \
    | grep -oE 'ADR-[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -3
165 166 168
```

Highest is **168** (167 absent), so next free is **ADR-169** — the plan's provisional value holds.
Still provisional until re-derived immediately before merge (task 5.3): ordinals have collided
three times recently, and a branch-picked one is only valid against the SHA it was measured on.

## 0.5 — `/health` field names

```
$ curl -sf -H 'Cache-Control: no-cache' https://app.soleur.ai/health
fields: build_sha, memory, sentry, status, supabase, uptime, version
version = 0.249.4   build_sha = f838839ef11119ac46f4d38ccf926472dee393a8
```

Both `version` AND `build_sha` are present, so A0 can assert on the pair as planned.

Note what the values say: prod is serving the 2026-08-04 11:09 build. A0 must therefore NOT
treat "`/health` is 200" as proof the running build is restorable — the endpoint is healthy on a
build that is 9 releases stale. That is precisely the fail-open A0's cross-check exists to close.

## 0.1 / 0.6 — crane classification strings (crane 0.20.2, the pinned version)

`CRANE_VERSION=v0.20.2` / `CRANE_SHA256=c14340087103ba9dadf61d45acd20675490fd0ccbd56ac7901fc1b502137f44b`
(`reusable-release.yml:1254-1259`).

| case | rc | last stderr line (the discriminator) |
|---|---|---|
| tag absent | 1 | `Error: GET …/manifests/v0.0.0-does-not-exist: MANIFEST_UNKNOWN: manifest unknown` |
| **repo absent** | 1 | `Error: GET …/manifests/latest: MANIFEST_UNKNOWN: manifest unknown` |
| DNS failure | 1 | `Error: Get "https://…/v2/": dial tcp: lookup … no such host` |
| success | 0 | `sha256:b04096d3…` on **stdout** |

### Two findings that change the implementation

**1. `NAME_UNKNOWN` does not exist as a distinct signal on GHCR — task 0.1's premise is refuted.**
A missing *repository* and a missing *tag* both return `MANIFEST_UNKNOWN: manifest unknown`. Any
classifier written to branch on `NAME_UNKNOWN` has a dead arm. This is fine for the gate's
purposes — both are correctness failures and both must ABORT — but the classifier must not claim
to distinguish them, and no test may assert a `NAME_UNKNOWN` string that GHCR never emits.

**2. The exit code is a bucket, not a diagnosis, and neither is line 1.**
All three failure classes exit `1`, and all three emit the SAME first line
(`HEAD request failed, falling back on GET: …`). Classifying on `rc`, or on the first line,
cannot separate a correctness failure from an availability failure — which is exactly the
distinction A5's abort/degrade boundary is made of. Classify on the **last** line, and treat any
stderr that matches neither known shape as `UNKNOWN` → abort (a "could not measure" outcome is
its own aborting class, evaluated before the comparison).

### Independent corroboration of the chosen PASS condition

```
$ crane digest ghcr.io/jikig-ai/soleur-web-platform:latest
sha256:b04096d3bfb639c60be267da11bfd831cb332d295363f7a0d8224eb303be75e5
```

That digest is byte-identical to the one in the failing release run's own error text
(`cosign sign --yes 127.0.0.1:5000/jikig-ai/soleur-***@sha256:b04096d3…`). The GHCR **read** half
is demonstrably working while the zot **push** half resets — which is the evidence the plan used
to reject the three candidates that depend on the failing component.

---

# Work-phase probes (2026-08-05, second session)

Run against a real throwaway zot started from the **Terraform-declared digest read through the
`local.zot_image` arch ternary** (`zot-registry.tf:84`), not `zot_image_amd64` directly:
`ghcr.io/project-zot/zot-linux-amd64@sha256:073f30d9…`. Config mirrored from
`cloud-init-registry.yml`: `htpasswd -Bbn` auth (generated via `httpd:2.4-alpine`, same form) and
`accessControl.repositories."**".defaultPolicy: []`.

## 0.9 — `crane validate --remote` over plain-HTTP loopback — **RESOLVED, works**

The hard Phase-2 dependency. A2 has a blob-completeness verifier; **no fallback is needed.**

```
$ crane append -f layer.tar -t 127.0.0.1:5555/probe/img:v1 --insecure --oci-empty-base
127.0.0.1:5555/probe/img@sha256:2fd181f0…
$ crane validate --remote 127.0.0.1:5555/probe/img:v1 --insecure
PASS: 127.0.0.1:5555/probe/img:v1                                              # rc=0
```

### The negative control — this is the row that matters

A verifier that cannot fail is the defect this plan exists to remove, so the pass above is not
evidence on its own. The layer blob was evicted from the store on disk (via a helper container —
zot runs as uid 0 and the tree is root-owned), simulating the gc-evicted-layer case
`build-inngest-bootstrap-image.yml` warns about. Re-measured against the **same** image:

| verifier | rc | last line |
|---|---|---|
| `crane digest` | **0** | `sha256:2fd181f0…` — **PASS on an unusable image** |
| `crane validate --remote --fast` | 1 | `BLOB_UNKNOWN: blob unknown to registry` |
| `crane validate --remote` (full) | 1 | `BLOB_UNKNOWN: blob unknown to registry` |

So the plan's premise is **measured, not argued**: a digest-only round-trip goes green on a
restore that a host would fail to pull. A2 must use `crane validate --remote`.

> **Read-back discipline for this row.** The first attempt at this control silently failed — the
> blob path was guessed wrong AND the `mv` hit `Permission denied`, so all three verifiers were
> re-run against an *intact* image and all three printed PASS. Those three PASSes proved nothing
> and were discarded. The eviction is only trustworthy because `test -f` was asserted to print
> `EVICTED` **before** the verifiers ran.

### What this settles for the dark-launch, scoped honestly

`build-inngest-bootstrap-image.yml`'s dark-launch warning names two disjuncts. This refutes the
second one — *"crane validate does not speak plain-HTTP to the loopback bridge the way copy/digest
do"* — for **direct** plain-HTTP loopback with no `cloudflared` in the path. It does **not** promote
the dark-launch, whose own criterion is `blob_validate=ok` on a real run against prod zot.

## 0.7 — A4 wiring — **CONFIRMED by source**

`scripts/zot-mirror-diagnosis.sh:39` — `zot_mirror_verdict()` takes `$1 = the detector's exit code,
$2 = path to its --json-file output`, and `scripts/check-cloudflare-token-drift.sh:175` implements
`--json-file`. The grader is pure arithmetic over a file the detector must write first. Sourcing
only the grader yields `unmeasured` → DEGRADE, i.e. a predicate that can never abort. **A4 must
invoke the detector, then grade** — pinned by a suite row plus a structural check.

## 0.3 — signature source material — **present**

```
$ crane ls ghcr.io/jikig-ai/soleur-web-platform | grep '^sha256-b04096d3'
sha256-b04096d3bfb639c60be267da11bfd831cb332d295363f7a0d8224eb303be75e5
```

The cosign signature tag exists at GHCR, so the copy mechanism has source material.

## Required pins resolve at GHCR — **verified, not assumed**

The plan names the pins by derivation, so both were re-derived and then resolved:

```
$ grep -n 'soleur-inngest-bootstrap:v' apps/web-platform/infra/cloud-init.yml
740:    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.24

$ crane digest ghcr.io/jikig-ai/soleur-web-platform:v0.249.4       # prod /health version
rc=0  sha256:6a8ef65387121aead538bdd656ed5f60a601eb3f55291aae446dd287e0d5002e
$ crane digest ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.24   # the cloud-init pin
rc=0  sha256:6cdaa63d1496642e681898a831234b712f75d3b09bd0844bcabec3de74b0a0f8
```

Note `soleur-inngest-bootstrap:latest` does **not** exist (`MANIFEST_UNKNOWN`) — only the pinned
`v1.1.24` does. A gate that reached for `latest` on this repo would abort forever. `FLOOR = 2`
holds.

## The A1 classifier table — corrected and properly controlled

### Correction to this file's own earlier finding #1

The earlier entry says *"`NAME_UNKNOWN` does not exist on GHCR."* That conclusion is right for the
implementation and its stated reason is wrong: `NAME_UNKNOWN` **does** exist, on the **tags** API.
It is API-dependent, not absent.

```
$ crane ls     ghcr.io/jikig-ai/soleur-inngest-config    # tags API
NAME_UNKNOWN: repository name not known to registry
$ crane digest ghcr.io/jikig-ai/soleur-inngest-config:latest   # manifest API
MANIFEST_UNKNOWN: manifest unknown
```

A1 resolves digests with `crane digest`, so `NAME_UNKNOWN` is unreachable **there** and a
`NAME_UNKNOWN` arm would be dead code. Left as-is, the original wording would mislead the next
person who adds a `crane ls` call. If one is ever added, `NAME_UNKNOWN` falls to the `UNKNOWN`
default arm and aborts — fail-closed, so the omission is safe by construction.

### The finding that changes an operator-facing message

A repo that **exists but is not visible to the credential** is masked by GHCR as
`MANIFEST_UNKNOWN` — identical to genuinely-absent. The first attempt at this control
(`ghcr.io/torvalds/definitely-private-xyz`) was **confounded**: that repo probably does not exist
at all, so its `MANIFEST_UNKNOWN` measured absence, not denial. The clean control queries a repo
*proven* to exist, with credentials removed:

| case | rc | last stderr line (the discriminator) |
|---|---|---|
| success | 0 | digest on **stdout** |
| absent tag, repo visible | 1 | `MANIFEST_UNKNOWN: manifest unknown` |
| absent repo | 1 | `MANIFEST_UNKNOWN: manifest unknown` |
| **no credentials at all** | 1 | `UNAUTHORIZED: authentication required` (on `ghcr.io/token`) |
| DNS failure | 1 | `dial tcp: lookup … no such host` |

**Consequence for A1's message, and it is load-bearing:** a `NOTFOUND` verdict may **not** say the
image is gone. `MANIFEST_UNKNOWN` is produced by *absent tag*, *absent repo*, **and** *present but
not visible to this credential*. Claiming "absent" would name a cause the gate did not measure — on
the one gate protecting an irreversible destroy. The message must read *absent **or not visible to
this credential***. Both classes abort, so the verdict is unchanged; only the honesty of the text is.

## 0.2 — runner `packages: read` — **NOT established locally, and safe by construction**

A workstation probe cannot establish runner capability (different principal, different scopes), so
this stays open. What the finding above settles is the **consequence of it failing**: an
insufficiently-scoped runner token yields `MANIFEST_UNKNOWN` → `NOTFOUND` → **ABORT**. A 0.2 failure
is therefore a safe abort, never an unsafe pass — it costs a dispatch, not a store. This is why the
`NOTFOUND` wording above is not cosmetic: it is the difference between an operator reading "the
image is gone from GHCR" and "check the job's `packages: read` permission".

## 0.4 — full-pin-set wall-clock and peak disk — **NOT measured**

Deliberately not measured here. The workstation's transfer profile (560 GB free, residential
uplink) does not predict a GitHub-hosted `ubuntu-24.04` runner's, so a local number would be a
false precision on the two figures that feed the job budget. Carried as a named residual; the
restore job gets its own `timeout-minutes` budget and is resumable, which is what makes an
unmeasured duration survivable.
