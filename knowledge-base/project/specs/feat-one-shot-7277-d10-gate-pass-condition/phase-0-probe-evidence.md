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

## Not yet run (require a runner or a throwaway registry)

- **0.2** `GITHUB_TOKEN` + `packages: read` from a runner. A workstation probe does NOT establish
  runner capability — different principal, different token scopes.
- **0.3** signature mechanism (copy `sha256-<digest>.sig` vs re-sign keyless), and whether the
  repo's `cosign verify` checks `critical.identity.docker-reference`.
- **0.4** throwaway-zot feasibility for the full pin set — per-pass wall-clock and peak runner disk.
- **0.7** A4 wiring: `zot_mirror_verdict` makes zero network calls; the detector must run first or
  the predicate can never abort.
- **0.9** `crane validate --remote` over plain-HTTP loopback — if it does not work, A2 has no
  blob-completeness verifier and needs a recorded fallback before Phase 2.
