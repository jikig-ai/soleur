---
date: 2026-05-29
topic: org-targetable runtime flag provisioning + per-org scoping
issue: 4581
branch: feat-flag-org-scoping
pr: 4582
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
status: complete
---

# Brainstorm: Org-Targetable Runtime Flag Provisioning + Per-Org Scoping (#4581)

## What We're Building

A sanctioned path to **provision and per-org-scope** an org-targetable runtime flag,
so an operator can enable a legally-sensitive flag (`byok-delegations`) for **one** org
(jikigai) without a deploy, with the WORM audit row written, and **without** collaterally
enabling it for unrelated orgs. Fixes five verified gaps in `flag-create` / `flag-set-role`
that today make enabling `byok-delegations` for jikigai impossible via approved tooling
(blocks #4232).

Delivered as **two PRs, portability first**:

- **PR-1 (low-risk portability):** remove the hard `psql` dependency for the WORM audit
  append (gap 5) and make the audit-actor precondition resilient (gap 4). Makes the
  sanctioned path runnable on any operator machine. Independently testable; prerequisite
  for the audit appends in PR-2 to work psql-lessly.
- **PR-2 (ADR-043-gated model change):** per-feature-segment scoping model (gaps 1 + 2 + 3),
  with a state-migration dry-run and a single-org re-verify read. Delivers the
  `byok-delegations`@jikigai unblock.

## Why This Approach

**Segment model = Option A (per-feature segment).** One Flagsmith segment per
org-targetable flag (`<flag>-orgs`), whose membership is the orgs that get *that* flag;
the feature carries one ON-override on its own segment (created once at provision). Per-org
scoping is then a pure **membership edit** — the exact mechanic the existing
`flip.sh --org` branch already implements, just pointed at the flag's own segment instead
of the shared `org-targeted` segment.

- **Bounds segment count on the small axis (features ~2-5), not the unbounded customer axis.**
  This is the option neither ADR-043 nor the 2026-05-25 audit-env-flags brainstorm
  considered — both framed the choice as "per-org segments (N, rejected for explosion)"
  vs "single shared segment (chosen)". Per-feature segments dodge ADR-043's stated
  rejection reason *and* give per-(feature,org) granularity.
- **Blast radius = one feature.** Editing a flag's segment cannot affect another flag.
- **Fallback-fidelity preserved (CTO):** the Doppler `FLAG_*` mirror reflects prd-segment
  (role) state, not per-org overrides — so a per-org-scoped flag falls back to
  `default_enabled=false` (OFF) during a Flagsmith outage, the **safe** direction for a
  legally-sensitive feature. This must be stated in the amending ADR.

Option B (per-org segment) was rejected: it relocates ADR-043's segment-explosion to the
customer axis and turns every flip into an override-edit.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Option A: per-feature segment** (`<flag>-orgs`) | Bounds segments by features; reuses `--org` membership-edit path; smaller tier-cap & migration risk than B |
| 2 | **Two PRs, portability first** | Isolate low-risk psql→RPC refactor from high-risk live-prd segment migration |
| 3 | **Gap 5 → PostgREST RPC** `POST /rpc/audit_flag_flip` via `service_role` key (curl-only) | Preserves SECURITY DEFINER grant model; NOT a raw insert, NOT Bun.sql (bypasses grant). Keep mandatory: non-2xx → exit 4 |
| 4 | **Gap 4 → seed `OPERATOR_EMAIL`** in Doppler `cli_ops` (in-session) | Controlled provisioned actor for 7-yr WORM trail; do NOT derive from `git config` (spoofable). `gh api user` only as authenticated last-resort + Sentry mirror |
| 5 | **Single-org re-verify read (count==1)** before success | Prove scoping, don't assert it (CLO). Extends the existing `--org` re-verify pattern to feature-state + membership |
| 6 | **`create.sh --flagsmith-only` mode** | Provision the Flagsmith side of an already-code-wired flag (current `exit 1` at create.sh:43 is the blocker) |
| 7 | **PR-2 state-migration dry-run** enumerating every existing (feature, segment-override) pair | Cutover must not drop `team-workspace-invite` for either org nor leak `byok-delegations` to the second org |
| 8 | **Amend ADR-043** via `/soleur:architecture` before PR-2 | The per-org-segment rejection is the decision being reversed; record blast-radius + fallback-fidelity rationale |
| 9 | **Gate PR on `user-impact-reviewer`** | Brand-critical, single-user-incident threshold, tamper-evidence change |

## User-Brand Impact

- **Artifact:** org-targetable runtime flags (esp. `byok-delegations` — owner-funded BYOK,
  per-grantee opt-in) + the `flag_flip_audit` WORM trail (migration 071, 7-yr retention).
- **Vectors:** (a) wrong-org feature exposure via the shared `org-targeted` segment's
  all-or-nothing blast radius; (b) silent audit-trail loss when the `psql`/`OPERATOR_EMAIL`
  preconditions fail; (c) BYOK credential/spend-delegation surface exposed by an incorrect
  flip. Operator confirmed **all three** apply.
- **Threshold:** `single-user incident`. A single non-opted-in org gaining access to another
  org's spend/key-delegation surface is the failure this design must make *impossible to do
  silently* and *detectable* if it ever occurs (CLO: GDPR Art. 33 72h clock only triggers if
  a non-opted-in org actually accesses personal data; otherwise internal/contractual).

## Open Questions

1. **Live Flagsmith tier segment cap** — confirm via API before PR-2 commits (non-issue under
   A's bounded count, but record the live ceiling in the ADR).
2. **Roadmap promotion (CPO):** `byok-delegations` is `Post-MVP / Later`, not a numbered
   phase, yet gates the most sensitive surface and is accreting GDPR/DSAR substrate. Confirm
   whether to promote it before more infra builds around a "Later" item. *(Advisory — not a
   blocker for this feature.)*
3. **PR-1 secret prerequisites** — `SUPABASE_URL` + service-role key must be seeded in
   `soleur/cli_ops` for the RPC; the scripts currently resolve only `DATABASE_URL_POOLER`.

## Domain Assessments

**Assessed:** Engineering, Product, Legal (mandatory triad — user-brand-critical). Marketing,
Operations, Sales, Finance, Support not relevant (internal operator tooling).

### Engineering (CTO)

**Summary:** Confirmed gap-3 is an ADR-043 reversal, not a script fix; recommended per-org
segments (Option B) but flagged Flagsmith tier segment-cap and a HIGH state-migration risk
(cutover must not drop `team-workspace-invite` or leak `byok-delegations`). Audit append must
route through the SECURITY DEFINER RPC via `service_role` (not raw insert / not Bun.sql);
seed `OPERATOR_EMAIL` rather than derive it. Two-PR sequencing, portability first. Operator
chose Option A over B (bounds segments on features, not orgs).

### Product (CPO)

**Summary:** Per-(feature,org) granularity is needed *now* (two tenant-boundary flags already
share one segment = live cross-tenant exposure) but cap ambition at n-features, no targeting
matrix UI. Recommended Option A (per-feature segment — matches operator mental model, bounds
proliferation to the bounded axis, preserves dual-control). Extend `flag-set-role`'s `--org`
into one idempotent provision+override+scope verb; do not add a second segment-mutation skill
(breaks the ADR-038 fallback-fidelity contract).

### Legal (CLO)

**Summary:** WORM integrity must survive the transport swap — route through the
SECURITY DEFINER RPC, keep `exit 4` hard-block (a flip with no audit row is the prohibited
state). Actor provenance: Doppler `OPERATOR_EMAIL` → authenticated `gh api user` floor →
hard fail; never silent `git config`. Cross-org scoping must be *proven* via a post-write
re-verify read (count==1). Internal/contractual if caught pre-exposure; GDPR Art. 33 72h
clock only if a non-opted-in org actually accesses personal data — design for detectability.
Gate the PR on `user-impact-reviewer`: **yes**.
