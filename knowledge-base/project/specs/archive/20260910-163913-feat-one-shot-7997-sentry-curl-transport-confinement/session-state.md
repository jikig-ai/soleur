# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-10-fix-sentry-curl-transport-confinement-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Collision gate re-run against the plan's own `closes: 7997` — same target as invoked, no divergence.
  `refs: 7898` is a reference, not a close, so it is not a collision surface for this pipeline.

### Errors
None that blocked planning. Four self-inflicted errors were caught by measurement during the pass
and recorded in the plan as Sharp Edges rather than shipped:

1. A negative-arm verification reported three green refusals that had never fired — `doppler run`
   overwrites the inherited environment, so `env` must go INSIDE the child. (Sharp Edge 5.)
2. `LC_ALL=C [[ … ]]` is a parse error (`[[` is a keyword, not a command, so it takes no env
   prefix). Working form is `( LC_ALL=C; [[ … ]] )`. (Sharp Edge 12.)
3. `_safe` was called above its own definition. (Sharp Edge 13.)
4. `discoverability_test` was a proxy — a compliant-looking prototype printed the exact expected
   output with the whole destination layer absent; and `T25` collided with an existing id. Both
   corrected.

Tooling: Playwright MCP unavailable (no browser verification planned). `plugin:github` MCP also
failed to connect; `gh` CLI used throughout.

### Decisions
- **Region-discovery contract (the architecture decision this issue turns on):** keep the probe
  loop, but make the destination HOST NAME a member of one hardcoded `SENTRY_HOST_CANDIDATES`
  array read by BOTH the loop and a new refusal, parameterised only by an org slug that is
  shape-constrained under `LC_ALL=C`. `sentry-alert-live-fidelity.sh` pins to the singleton
  `${SENTRY_ORG}.sentry.io` instead — its only endpoint is org-scoped, and ADR-031 records
  `eu.sentry.io` as hijacking `-eu` slugs. The delete-the-loop alternative was filed and persisted
  as an ADR-084 decision-challenge; CTO ruled the fork with the disqualifying facts in hand.
- **The lint is the authority, and it disagrees with the issue in three places.** It reports no
  destination finding at the region probe (`_mask_cmdsubs` blinds it); it scores `api_host`
  "adjudicated" via a downstream classification that runs after every request; and it cannot see
  the `curl_retry` wrapper at all, because the credential arrives via `"$@"`. Measured: even a
  perfect recogniser widening leaves that line unflagged. The planned lint widening was therefore
  CUT and moved to #7898 — whose §4 claim that "no current offender uses that seam" is false as
  measured.
- **Two flags were not enough.** `--disable`/`--noproxy` confine the config file and the proxy
  only. `LOCALDOMAIN`/`RES_OPTIONS` still redirect resolution, `CURL_CA_BUNDLE`/`SSL_CERT_FILE`
  still replace the trust anchor, and `CURL_BIN` still names the program. Adopts the repo's
  existing `unset` prologue, `--proto '=https' -g`, and a `CURL_BIN` adjudication.
- **The stated residual was corrected DOWNWARD, not up.** `*.sentry.io` is Sentry SaaS: an org
  slug buys a tenancy, not an origin, so the post-fix residual is tenant confusion and integrity,
  not exfiltration. The `single-user incident` threshold stands on PRE-fix evidence — a stubbed
  `curl` recorded the bearer reaching `https://attacker.tld/api/0/organizations/jikigai-eu/` on
  `main` today.
- **The prescription is measured, not asserted.** The exact final shape lints clean, passes
  `bash -n`, keeps the live probe green at 28/28 against production Sentry, reproduces discovery
  selection for all four candidates plus the all-fail arm, and refuses every hostile input
  including the resolver/keylog environment.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`, `soleur:gdpr-gate` (via agent)
- Agents: `soleur:engineering:cto`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
  `architecture-strategist`, `spec-flow-analyzer`, `soleur:product:cpo`, `security-sentinel`,
  `test-design-reviewer`, `observability-coverage-reviewer`, 2x `Explore`, 1x `general-purpose`
  (verify-the-negative + self-audit sweep). `dhh-rails-reviewer` deliberately not spawned; its lens
  was given verbatim to `code-simplicity-reviewer` and the substitution is recorded in the plan's
  Domain Review.
- Commands: `lint-shell-trace-credential-refusal.py` (explicit-path, `--changed`, `--census`),
  `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, `gh issue/pr/run/label`,
  `doppler secrets`/`doppler run` against `soleur/prd`, live `curl` probes against Sentry, and
  scratch-copy prototypes of both scripts plus a stubbed `curl` harness.
