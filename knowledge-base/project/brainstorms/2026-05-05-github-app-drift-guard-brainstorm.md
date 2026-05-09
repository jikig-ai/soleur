---
date: 2026-05-05
topic: github-app-drift-guard
related_issues: [3187, 3181, 3183, 1784, 2887]
related_prs: [3181]
status: brainstorm-complete
brand_survival: single-user-incident
---

# GitHub App Drift-Guard via JWT-signed `gh api /app` Snapshot

## What We're Building

A scheduled GitHub Actions workflow (`scheduled-github-app-drift-guard.yml`,
hourly cron) that:

1. Loads a base64-encoded GitHub App private key (`GITHUB_APP_PRIVATE_KEY_B64`)
   from a workflow secret sourced from Doppler `prd`.
2. Decodes the PEM into `$RUNNER_TEMP` with `umask 077`, masks it via
   `::add-mask::`, never echoes it.
3. Mints an RS256 App JWT (10-min expiry) with inline `openssl dgst -sha256 -sign`
   (no third-party action — same supply-chain class this guard exists to detect).
4. Calls `gh api /app` with the JWT as bearer.
5. Asserts the response's `client_id` matches `OAUTH_PROBE_GITHUB_CLIENT_ID`
   AND `id` matches `GITHUB_APP_DATABASE_ID` (both immutable). Presence checks
   on both expected and actual sides BEFORE comparison.
6. On drift: file/update issue with label `ci/auth-broken` (App swap detected).
7. On guard malfunction (secret missing, JWT mint fail, HTTP 401/5xx, jq
   parse fail): file/update issue with label `ci/guard-broken`.
8. Post-step leak tripwire: greps the rendered run log for `BEGIN .* PRIVATE KEY`
   and JWT prefix `eyJ`. Fails the run if either is present (the GDPR Art 33
   72h clock survival mechanism).
9. `shred -u` the PEM file at end-of-run.

## User-Brand Impact

- **Artifact:** GitHub App private key (PEM) and minted RS256 JWTs.
- **Vector A — Credential leak:** PEM bytes or JWT in workflow logs / artifacts /
  forked PR contexts → attacker mints installation tokens against every repo
  our App is installed on → controller-side unauthorized access to user repo
  content/metadata. Reportable Article 33 breach (GDPR Policy §11, 72h CNIL).
- **Vector B — Trust breach (silent miss):** Drift-guard exists but its own
  failure modes pass when they shouldn't (empty-string vs empty-string compare,
  silent skip on missing secret, `gh api /app` HTTP error treated as no-drift)
  → swapped App goes undetected → users sign in to attacker-controlled OAuth
  flow → user credential exfil.
- **Threshold:** `single-user incident`. One PEM leak or one undetected swap
  during founder cohort recruitment is brand-ending. CPO + user-impact-reviewer
  sign-off required at PR time.

## Why This Approach

### Inline openssl + bash for JWT mint

The guard's purpose is to detect tampering of identity primitives. It must
not depend on a community Action that can be hijacked (precedent:
`tj-actions/changed-files` March 2025). `actions/create-github-app-token@v1`
mints an installation token (different identity primitive — proves
installation, not App-level control over `/app`). Inline openssl is ~15 lines
of pre-installed bash, fully auditable in one screen, zero supply-chain
surface.

### Base64-encoded PEM in Doppler

Multi-line secrets through `gh secret set` from Doppler routinely lose `\n` or
get base64-wrapped silently. Storing as `GITHUB_APP_PRIVATE_KEY_B64` makes the
encoding contract explicit. Decode-step calls `openssl rsa -in $KEY -check
-noout` and fails loud on shape mismatch — silent shape failure is the #1
self-silent mode.

### Hourly cadence (not daily as issue specified)

MTTD target is "before attacker drains creds from active sessions." Daily =
up to 24h dwell. Hourly cuts dwell 24x at $0 cost (public repo → free Actions
minutes; 1 JWT mint/hr is 0.02% of the App JWT rate-limit budget). 15-min
coupling to `scheduled-oauth-probe.yml` is over-indexed — JWT mint is more
surface than body-grep, and the failure classes are different.

### Assert `client_id` AND `id` (not just `client_id`)

Both are immutable App identity primitives. `slug`/`name`/`owner.login` are
mutable via legitimate admin UI edits and would produce flake. Two immutable
fields is stricter than one, with no false-positive surface on legitimate
rebrands.

### Three-way label split

- `ci/auth-broken` — drift detected (App swapped or identity mismatch)
- `ci/guard-broken` — guard malfunction (secret missing, JWT mint failed,
  HTTP error, parse error)
- Shared label routing for triage, but separate dedup keys so triagers
  don't conflate "drift detected" with "guard is broken."

### Leak tripwire as blocking post-step

`::add-mask::` redacts but does not alert. If a future edit accidentally
introduces `set -x`, an `echo "$JWT"`, or pipes the PEM through a shell that
fails masking, the leak is silent and unbounded. The post-step grep for
`BEGIN .* PRIVATE KEY` and `eyJ` is what bridges leak → operator awareness
within minutes, which is what makes the GDPR Article 33 72-hour notification
clock survivable. Pair with mint logic from day one — adding it later is a
window of unbounded silent leak exposure.

### Schedule-only trigger + CODEOWNERS lock

`on: schedule:` only — explicitly NO `pull_request_target`, `workflow_run`,
or `workflow_dispatch`. Add a CODEOWNERS entry on the workflow file path
requiring engineering+legal review for any future trigger change. This is
the load-bearing control against forked-PR / `workflow_run` reachability of
the secret block.

### Doppler row in `compliance-posture.md` is blocking, not follow-up

PEM is brand-survival material. Doppler is the only vendor in the trust chain
not currently in our DPA table. Adding the row + filing follow-up issues for
DPA verification + RBAC review is a one-edit gate that prevents shipping a
brand-survival credential through an unaudited vendor relationship.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| JWT mint | Inline `openssl` + bash | Zero supply-chain hops; the guard cannot depend on the same trust class it exists to detect |
| PEM storage | Doppler `GITHUB_APP_PRIVATE_KEY_B64` (base64-encoded) | Multi-line secret newline corruption mitigation; explicit encoding contract |
| Cadence | Hourly | 24x MTTD vs daily at $0 cost; well below rate limits |
| Assertion fields | `client_id` AND `id` | Both immutable; two-field check eliminates flake from legitimate `slug`/`name` edits |
| Trigger surface | `schedule:` only + CODEOWNERS lock | Eliminates fork-context secret reachability |
| Permissions | `contents: read` only | No `id-token`, no `actions: write`, no `actions/upload-artifact` |
| PEM file location | `$RUNNER_TEMP` with `umask 077` + `shred -u` | Bounded lifetime, restricted permissions |
| Mask discipline | `::add-mask::` PEM and JWT immediately on materialization | Defense-in-depth for redaction |
| Leak tripwire | Post-step grep `BEGIN .* PRIVATE KEY` + `eyJ` → fail run | GDPR Art 33 72h clock survivability |
| Failure labels | `ci/auth-broken` (drift) + `ci/guard-broken` (malfunction) | Separates triage paths |
| Issue dedup | New dedup key `github-app-drift`, separate from `oauth-probe` | Different failure classes |
| User-probe coupling | None (do NOT auto-escalate `scheduled-oauth-probe.yml`) | Identity-only drift may be legitimate rotation; human triage decides escalation |
| Compliance posture | Add Doppler row to `compliance-posture.md` IN THIS PR | Brand-survival credential through previously unaudited vendor |

## Non-Goals

- **Auto-escalation of the user-facing OAuth probe.** Drift-guard fires →
  human triage → human decides whether to red the user probe. Auto-coupling
  would lock founders out during legitimate App rotation.
- **Real-time alerting (Sentry breadcrumb).** Deferred to follow-up. Pino
  logs + issue-filing + email notification is sufficient for v1.
- **Pre-written user-comm template for confirmed compromise.** Deferred to
  follow-up issue (`legal-document-generator` owns).
- **Doppler RBAC review** (confirm `GITHUB_APP_PRIVATE_KEY_B64` is readable
  only by CI service token + named admins). Deferred to follow-up; document
  current state in compliance-posture entry.
- **Installation-level guard** (does an attacker have an unexpected
  installation of our App?). Out of scope for this guard, which is App-identity
  only. File as separate concern if priority increases.
- **Workflow file SHA pinning audit** for the new workflow's actions
  (`actions/checkout`, etc.). Use the same pins as `scheduled-oauth-probe.yml`
  (already SHA-pinned).

## Open Questions

1. **Do we have the GitHub App's database ID (`id`) on file?** If not, capture
   it during the first manual run (`gh api /app | jq .id`) and add as
   `GITHUB_APP_DATABASE_ID` workflow secret. Not blocking — plan can include
   the bootstrap step.
2. **CODEOWNERS file format for workflow trigger lockdown.** Confirm during
   plan whether the existing CODEOWNERS supports per-file glob with multi-team
   approval, or if we need to extend it.
3. **`SOLEUR_SKIP_GITHUB_CLIENT_ID_SHAPE` override pattern from PR #3181.**
   Apply the same override pattern for `GITHUB_APP_DATABASE_ID` shape check?
   Defer to plan.

## Domain Assessments

**Assessed:** Engineering, Legal, Product

(Marketing, Operations, Sales, Finance, Support not relevant — internal CI
infra with no user-facing surface change, no vendor cost change beyond
existing Doppler, no marketing surface, no sales/finance/support impact.)

### Engineering (CTO)

**Summary:** Build now. Inline openssl JWT mint (no third-party Action),
base64-PEM in Doppler, assert `client_id` + `id`, hourly cadence, three-way
label split. Top architectural risk is PEM newline corruption mitigated by
base64 encoding + post-decode shape check. Self-silent-failure surface
extensively enumerated and addressed via explicit presence checks on both
sides of every comparison.

### Legal (CLO)

**Summary:** GO with conditions. The drift-guard is itself a GDPR Policy §299
compliance control (the document explicitly names "compromise of the GitHub
organization" as in-scope). PEM-in-CI-logs IS a reportable Article 33 breach
under §11 (72h CNIL clock), so leak-tripwire + trigger-lockdown + permissions
minimization are non-negotiable in this PR. Doppler is missing from the
vendor DPA table in `compliance-posture.md` — adding the row is blocking.
Pre-written user-comm template for confirmed compromise deferred to
follow-up.

### Product (CPO)

**Summary:** BUILD, bump P3 → P2, attach to Phase 4 (Validate + Scale),
sequence BEFORE Stripe live activation. Post-#2887 (dev/prd Doppler collapse
incident, 2026-05-03), the org's threshold for credential-handling defenses
has moved from "defer absent triggering incident" to "build by default."
Founder cohort recruitment in Phase 4 hits GitHub OAuth on first signin; a
swap incident during recruitment kills the cohort and the willingness-to-pay
signal. Do NOT auto-escalate the user-facing probe on identity-only drift —
that would create false-positive lockouts during legitimate App rotation.

## Capability Gaps

None. Engineering covers JWT mint + workflow + secret handling. Legal covers
compliance-posture entry + (deferred) incident-template. Product covers
priority + roadmap sequencing. Existing review pipeline (`user-impact-reviewer`,
`security-sentinel`, `silent-failure-hunter`) covers PR-time gates.
