# Learning: docker run's implicit pull misattributes a fetch failure to the next gate

## Problem

The dedicated inngest host (deny-all-public egress) emitted
`SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature` on every refresh tick. The verify path runs
`docker run --network none gcr.io/projectsigstore/cosign@sha256:…` — the daemon-side
*implicit pull* of that ref could never resolve on this host, and its failure was emitted as
`reason=signature`: a fetch problem wearing a provenance diagnosis. Two further traps
surfaced while designing the fix: `docker tag` cannot mint a `name@sha256:` reference
(digest refs only exist after a pull/push-derived RepoDigest), and `REFRESH_*` env seams
are inert in production (the `--fixture-seams` gate unsets them).

## Solution

- Producer: `zot_mirror` gained a second leg — `crane copy` of the digest-pinned cosign
  image to `127.0.0.1:5000/jikig-ai/cosign:v3.1.1` (after the bundle copy, before
  `mirror_status=ok`), plus `crane digest` equality-check against the pin.
- Consumer: `COSIGN_IMAGE` resolves to `${ZOT_EP}/jikig-ai/cosign@sha256:…` after `ZOT_EP`
  (re-derived from the seam var so a `COSIGN_IMAGE=` line in the sourced env file can't
  redirect it), and an explicit bounded `docker pull` stages it before `docker run` —
  a fetch miss now emits `reason=pull member=cosign-image`.
- Budgets re-derived: `TimeoutStartSec` 420→620 (second pull leg added 180 s to the
  worst-case tick) and `timeout-minutes` 20→30 (second retried copy leg).

## Key Insight

**A `docker run` of an unpulled image on a restricted-egress host fails closed at the
NEXT gate's error label — never at pull.** When the gate label is `signature`, operators
hunt a signing defect that doesn't exist. Any `docker run` on a no-public-egress host
needs an explicit `docker pull` (with its own failure reason/member) upstream, or the
implicit-pull failure will be misattributed. And adding a bounded operation inside any
enclosing budget (`TimeoutStartSec`, `timeout-minutes`, worst-case derivations) requires
re-deriving the bound in the same diff — two seats independently caught the stale bound.

## Tags
category: infra
module: inngest-config-refresh

## Session Errors

1. **Brief prescribed two unimplementable mechanisms** (`docker tag` for a digest ref;
   `REFRESH_COSIGN_IMAGE` env injection which the seam gate unsets in prod).
   **Prevention:** deepen-plan's sharp-edge preflight must test seam-gate reachability and
   Docker reference semantics before a mechanism reaches the plan; both were caught there.
2. **New bounded op added without re-deriving the enclosing budgets** (`TimeoutStartSec`,
   `timeout-minutes`, S2c relational pin) — found by review, not by the implementation pass.
   **Prevention:** when a diff adds any `timeout`/`retry` call, grep the same file for
   enclosing budget literals (`TimeoutStartSec`, `timeout-minutes`, worst-case comments)
   and re-derive them in the same edit; keep the arithmetic pins relational (2*_pto) so
   they can't false-green.
3. **`degraded()` warning named the bundle dst on cosign-leg failures** — a second leg in
   one step reuses shared emit helpers whose object names silently go stale.
   **Prevention:** any helper that interpolates an object name needs a per-leg object
   switch when a second leg lands (or the object moves into `detail=`).
4. **Generated artifact drift** — `model.c4` edited without regenerating
   `model.likec4.json`; the freshness gate was the catch.
   **Prevention:** for every generated pair, run the freshness gate, not just the syntax
   tests; the affected-tests mapper already routes the diagram dir to it.
