---
title: "fix: transport-confine and destination-pin the Sentry scripts' credentialed curl call sites"
date: 2026-09-10
slug: fix-sentry-curl-transport-confinement
branch: feat-one-shot-7997-sentry-curl-transport-confinement
issue: 7997
closes: 7997
refs: 7898
lane: single-domain
type: fix
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: approved-with-conditions
---

## Enhancement Summary

**Deepened on:** 2026-09-10 (same session as authoring)
**Panels run:** `cto` (binding ruling), `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer`, `cpo`, `gdpr-gate`, then a deepen pass of
`security-sentinel`, `test-design-reviewer`, `observability-coverage-reviewer` and a
verify-the-negative / post-edit self-audit sweep.

### Key improvements over the first draft

1. **The lint-widening phase was cut on measurement, not taste.** M18 showed that even a perfect
   recogniser widening leaves the `curl_retry` wrapper unflagged, because the lint's `credentialed`
   predicate reads the invocation's own text while the credential arrives via `"$@"`.
2. **Two flags were never going to be enough.** M21 measured `LOCALDOMAIN`/`RES_OPTIONS` redirecting
   resolution and `CURL_CA_BUNDLE`/`SSL_CERT_FILE` replacing the trust anchor *with the host pin fully
   intact*. The repo already carries the remedy in two sibling scripts; this plan adopts it.
3. **Two prescriptions in the first draft were syntactically wrong** and were caught by running them:
   `LC_ALL=C [[ … ]]` is a parse error (`[[` is a keyword, not a command), and `_safe` was called
   above its own definition.
4. **The stated residual was overstated.** `*.sentry.io` is Sentry SaaS: an org slug buys a tenancy,
   not an HTTP origin. The post-fix residual is tenant confusion and integrity, not credential exfil.
5. **The discoverability probe was a proxy.** A prototype carrying only the lint-required minimum
   printed the plan's exact `expected_output` while the whole destination-adjudication layer was
   absent.

### New considerations discovered

- `CURL_BIN` itself was never adjudicated: `CURL_BIN=/tmp/exfil` reproduced M9 through a different
  variable with every guard green. Now refused (M24).
- `apply-sentry-infra.yml` calls **both** scripts — the fidelity probe runs `if: always()` *after*
  `terraform apply`, so "never mid-flight" was false for that refusal.
- The plan's Test Scenario IDs collided with pre-existing `T1`/`T2`/`T13` in the audit suite; the
  audit-scoped rows are renumbered to continue that file's own sequence.

## Overview

Two Sentry probe scripts send a live Sentry org bearer token over `curl` without transport
confinement, and to a destination assembled from environment variables that are never adjudicated
against a literal. `scripts/lint-shell-trace-credential-refusal.py` Rule D reports six violations
across the two files.

The work is to make every credentialed request in both scripts skip `~/.curlrc`, ignore proxy
environment variables, **resolve and validate TLS against the system's own configuration rather than
the caller's**, and reach only a host the file adjudicates against a literal — without changing the
behaviour of the region-discovery loop that selects among candidate hosts.

Six facts measured during planning change the shape of the work relative to the issue text. All six
are recorded in Research Reconciliation below.

1. **The lint's field of view is narrower than the defect, and cannot be widened to cover it
   cheaply.** Its `CURL_INVOKE` regex does not match the `"$CURL_BIN"` wrapper invocation inside
   `curl_retry` — the transport for Gates 1-3 and every paginated fetch, and the path a stubbed-`curl`
   measurement showed actually carrying the bearer token to an attacker-chosen host. **M18: even a
   perfect recogniser widening does not gate it**, because the lint's `credentialed` predicate reads
   the invocation's own text and the credential arrives from the call site inside `"$@"`. The gate for
   that site is a file-scoped source-level assertion in this PR; the lint work moves to #7898.
2. **`--disable` and `--noproxy '*'` confine the config file and the proxy — not the resolver, the
   trust anchor, or the binary.** M21 measured `LOCALDOMAIN=com RES_OPTIONS=ndots:5` silently
   redirecting a resolution and `CURL_CA_BUNDLE=/dev/null` / `SSL_CERT_FILE=/dev/null` being honoured,
   with both flags present. M24 measured `CURL_BIN=/tmp/exfil` handing the bearer to an arbitrary
   program, correctly decorated. The plan therefore also adopts the repo's existing `unset` prologue
   and adjudicates `CURL_BIN`.
3. **Region discovery cannot succeed with any credential this repository holds.** All four candidate
   hosts answer 403/404 on `/api/0/users/me/` for both `SENTRY_AUTH_TOKEN` and
   `SENTRY_IAC_AUTH_TOKEN`, and all five callers set `SENTRY_API_HOST` (three fail loud when it is
   empty). "Region discovery still works" can only be proven hermetically.
4. **The host pin is parameterised, so it narrows the destination rather than closing it** — but the
   residual is *tenant confusion*, not exfiltration. `*.sentry.io` is Sentry-operated: an org slug
   buys a tenancy, not an HTTP origin.
5. **`SENTRY_ORG`'s in-file default is a canceled org.** `apps/web-platform/scripts/sentry-monitors-audit.sh`
   defaults to `jikigai`; production is `jikigai-eu`, and `ADR-031-sentry-as-iac.md` records the
   duplicate `jikigai` org as canceled vendor-side on 2026-05-21. Fixed inline
   (`wg-defer-only-after-inline-triage`).
6. **A bash ERE's `[a-z0-9]` range is locale-dependent.** M23: `é` is *accepted* under
   `en_US.UTF-8` and refused under `C`. The guard must scope its own locale, and the scoping
   construct is not the obvious one (M22).

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 7997` — **OPEN**, `closedByPullRequestsReferences: []`. Labels
  `priority/p2-medium`, `type/chore`, `domain/engineering`. Premise holds.
- The predecessor citation `#7988` is a *Refs*, not a *Closes*; merged as `a866e1f29`.
- Both cited call sites exist verbatim on HEAD; the lint reproduces exactly the six violations
  the issue enumerates (M1).
- **`#7898` is the consolidated Rule D drawdown tracker and it already owns the `CURL_BIN` scope
  gap** (its §4). Its stated position is *"No current offender uses that seam, so this is recorded
  rather than fixed — upgrade trigger: the first script that introduces `CURL_BIN` (or any
  indirection through a variable) for a credentialed call."* **That claim is false as measured:**
  `apps/web-platform/scripts/sentry-monitors-audit.sh` has used the seam for a credentialed call
  since before #7898 was filed, and M9 measured the bearer leaving through it. Its own upgrade
  trigger has already fired. Correcting that claim is a task of this plan.
  *(The overlap was missed by the `--label code-review` sweep, which is scoped to that label only;
  #7898 carries `type/chore`. Recorded so the next planner widens the sweep.)*
- **Mechanism vs. the ADR corpus:** no ADR owns the Rule D contract.
  `ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md` governs the lint's
  *enforcement doctrine* but not this rule (see Architecture Decision for why its `## Decision` is
  the wrong home). `ADR-031-sentry-as-iac.md` owns the Sentry host/region glossary.
- **Own capability claims:** every assertion below about what the lint checks was taken by reading
  `scripts/lint-shell-trace-credential-refusal.py` and by executing it. Where the lint and the issue
  disagree, **the lint is the authority** and the plan says so at the point of disagreement.

### Property List (Phase 0.6b)

- **P1.** Every process invocation of a curl binary in either script skips `~/.curlrc` (via
  `--disable` in first position) and ignores every proxy environment variable (via `--noproxy '*'`).
- **P2a — the NAME.** The host *string* in every credentialed request URL is adjudicated, in that
  file, against a literal: membership in `SENTRY_HOST_CANDIDATES` in the audit script, equality with
  `"${SENTRY_ORG}.sentry.io"` in the fidelity script. *Scope is "in either script"; this does not
  reach the inline `curl` in `.github/workflows/sentry-audit-gate.yml`.*
- **P2b — the RESOLUTION and the TRUST ANCHOR.** That name resolves, and its certificate is
  validated, against the system's configuration and not the caller's environment. P2a without P2b is
  a name property masquerading as a destination property (M21).
- **P3.** `$SENTRY_ORG`, interpolated into both a hostname and a URL path, cannot introduce a host,
  userinfo, a path separator, a query, a fragment, a port or a control character — under **any**
  locale.
- **P4.** Region discovery still probes the candidate hosts in order and selects the first that
  answers 200.
- **P5.** The lint reports zero violations for both files under its own invocations, and the
  reporting run is not vacuous.
- **P6 — the BINARY.** The program `curl_retry` executes is `curl`, not a caller-named path.

### Cut List

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| An intra-file drift guard over two host lists in the audit script | P2a | **CUT.** Collapsed to one `SENTRY_HOST_CANDIDATES` array read by both the loop and the choke point; drift is unrepresentable. |
| A **cross-file** allowlist parity assertion | P2a | **CUT at review.** It would force the fidelity script — whose only endpoint is org-scoped — to admit `eu.sentry.io`, which `ADR-031-sentry-as-iac.md` and learning `2026-05-17-…` both record as hijacking `-eu` slugs (302 → 401). The two files legitimately need *different* sets, and M25 measured the fidelity script refusing `eu.sentry.io` as intended. |
| **Widening the lint's recogniser to `"$CURL_BIN"`** | P1 gating for the wrapper | **CUT at review, on measurement.** M18: substituting a literal `curl` for `"$CURL_BIN"` on the wrapper line still yields **no finding at that line**. It also costs two xtrace-refusal preambles and two A/B/C baseline deletions (M19), for a benefit it does not deliver. Moved to #7898 with both measurements. |
| A new standalone ADR for the Rule D contract | recording the decision | **CUT.** Recorded under `ADR-202`'s `## Consequences` (not its `## Decision`) plus an `ADR-031` glossary correction. |
| A new test file under `tests/scripts/` for region discovery | P4 | **CUT.** `apps/web-platform/scripts/sentry-monitors-audit.test.sh` is auto-discovered by `scripts/test-all.sh`'s `SUITE_GLOBS` entry `'apps/web-platform/scripts/*.test.sh'`. Nothing under `tests/scripts/` is auto-discovered. |
| A single-literal pin of `$SENTRY_ORG` | P3 | **CUT — and it would be wrong.** Production is `jikigai-eu`; the in-file default is `jikigai`, an org ADR-031 records as canceled. |
| `us.sentry.io` as a fifth candidate | P2a/P4 | **CUT at review.** Adding it changes the discovery loop's live probe behaviour, which is the one thing the issue's done-when pins. The CTO's justification (the file's own region-classification `case` treats it as legitimate) is circular — that `case` labels whatever host was already reached. |
| A separate follow-up issue for the wrong `SENTRY_ORG` default | correctness | **CUT.** `wg-defer-only-after-inline-triage`: the anchor is one this plan already edits, and under a parameterised host pin the wrong default is a destination defect. |

### Repo conventions and prior art (measured)

The repo has **7 Rule-D-compliant production curl sites**. Their idioms, adopted here:

- **Flag order and shape** — `scripts/supabase-logs-query.sh`, anchor
  `curl --disable --noproxy '*' --silent --show-error --max-time 30 \`. Its
  `# HOST PIN — NO ENV OVERRIDE` header block is the canonical justification prose.
- **The resolver/trust-anchor prologue** — `scripts/betterstack-query.sh` and
  `scripts/zot-inventory.sh` both carry
  `unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS`.
  `betterstack-query.sh`'s own comment records the last time its absence elsewhere was noticed
  ("an asymmetry that this line lived only in `zot-inventory.sh` while the higher-value credential
  went without"). This plan is that asymmetry recurring a third time, on the highest-value credential
  of the three.
- **`--proto '=https'`** — `scripts/betterstack-ingest-probe.sh`, house style whenever the URL itself
  is variable.
- **`-g` / `--globoff`** — `apps/web-platform/infra/inngest-bootstrap.sh`, with the rationale that a
  URL containing `[ ]` or `{ }` otherwise makes curl print the full URL in a glob-parse error.
- **Refusal exit code is `2`**, not `78`. `scripts/zot-inventory.sh`
  (`die() { printf '%s\n' "zot-inventory: $1" >&2; exit "${2:-2}"; }`) and
  `scripts/betterstack-ingest-probe.sh` both use it. `78` is this repo's xtrace-refusal code.
- **Sanitise any hostile value that is echoed** — `scripts/zot-inventory.sh`
  `_safe_url() { printf '%s' "${1//[[:cntrl:]]/}" | cut -c1-120; }`. Adopted with one correction:
  `cut -b`, not `-c` — M26 measured `-c` splitting a UTF-8 sequence mid-character.
- **Allowlist the permitted value; never parse the hostile one** — ADR-199 commitment 2.
- **A `case` glob's `*` crosses `/` and `?`** —
  `knowledge-base/project/learnings/security-issues/2026-09-06-the-file-i-added-to-fix-a-p1-shipped-a-p1.md`
  records `https://evil.com/?x=.betterstackdata.com/` defeating a suffix glob. Consequence: no `*`
  in any arm of the two new allowlist constructs, **and every comparison RHS is double-quoted**
  (M27: an unquoted RHS makes the comparison a glob and reopens exactly that bypass).
- **Substitution over refusal, where a mode allows it** — `scripts/sentry-issue.sh` (anchor
  `PINNED_HOST='jikigai-eu.sentry.io'`); its suite `scripts/sentry-issue-discover.test.sh` asserts the
  property with a hostile environment. That negative-arm shape is copied here.

### Institutional learnings that bind this plan

- `knowledge-base/project/learnings/2026-09-07-the-class-recurred-in-three-days-and-every-instrument-was-broken.md`
  (#7873): *derive covering suites from the guard's QUANTIFIER, not from the changed files.*
  Consequence: the **blocking** arm of the lint is the repo-wide, no-flags run registered in
  `scripts/test-all.sh`, not the advisory `--changed` step in `ci.yml`'s `lint-bot-statuses` job.
- `knowledge-base/project/learnings/security-issues/2026-09-06-the-file-i-added-to-fix-a-p1-shipped-a-p1.md`:
  a destination pin once refused a sibling suite's real loopback listeners and had to be reverted.
  Pre-cleared here by enumeration — Research Reconciliation row 6.
- `knowledge-base/project/learnings/2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`:
  `https://eu.sentry.io/api/0/organizations/jikigai-eu/` answers 302 with
  `set-cookie: session={"activeorg":"eu"}` then 401. For **org-scoped** paths the only correct host is
  `${SENTRY_ORG}.sentry.io`. This is why the fidelity script pins to the singleton.
- `knowledge-base/project/learnings/2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md`:
  a guard's own battery scoring perfectly says nothing about escapes it cannot see. Consequence:
  every Guard Contract entry carries harness rows, and every hostile row pins its environment.
- `cq-regex-unicode-separators-escape-only` is the sibling of M23: a character class in a guard is a
  claim about a locale, not about a character set.

### Skill description budget

No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate or finalised. Check skipped.

## Phase 0 Measurements

Every number below was produced by a command run during planning. `/work` re-runs M1-M4, M8, M18 and
M19 as its Phase 0 and stops if any has moved. *(M14 was retired with the lint-widening cut; the
sequence is deliberately non-contiguous rather than renumbered, so citations elsewhere stay valid.)*

| # | Measurement | Result |
|---|---|---|
| M1 | `lint … scripts/sentry-alert-live-fidelity.sh apps/web-platform/scripts/sentry-monitors-audit.sh` | **6 violations in 2 scanned files**, exit 1 |
| M2 | `lint --changed --base origin/main` on a clean branch | `OK: 0 scanned file(s)` — **vacuously green** |
| M3 | `lint --census` | `scanned=1029 offenders=116 offenders_d=82` |
| M4 | D-baseline membership | both scripts present (2 of 82) |
| M5 | Doppler `soleur/prd` | `SENTRY_ORG=jikigai-eu`, `SENTRY_API_HOST=jikigai-eu.sentry.io`, `SENTRY_PROJECT=web-platform` |
| M6 | All four candidates, live, **both** repo tokens, `/api/0/users/me/` | `jikigai-eu.sentry.io` **403**, `eu.sentry.io` **403**, `de.sentry.io` **404**, `sentry.io` **403** |
| M7 | Same tokens, `/api/0/organizations/jikigai-eu/` | **200** for both |
| M8 | Fidelity probe baseline, live | `PASS (all 28 in-scope rules …)`, exit 0 |
| M9 | **Measured exfil on `main`** — stub `curl` on PATH; `SENTRY_API_HOST=attacker.tld` | bearer sent to `https://attacker.tld/api/0/organizations/jikigai-eu/` (Gate 1, **via `curl_retry`**), no `--disable` |
| M10 | First prototype greens the lint | `OK: 1 scanned file(s)` each; `bash -n` clean |
| M12 | Prototype refuses hostile input | refusal, exit non-zero, **0 URLs probed** |
| M13 | Hermetic discovery proof | probe order + selection reproduced for candidates 1, 2 and 4 and the all-fail arm |
| M15 | Org-shape regex behaviour | ACCEPT `fixture`, `jikigai`, `jikigai-eu`, `attacker-org`; REFUSE `@evil.tld/x`, `a.b`, `A`, ``, `x/y`, `x@y`, `-lead`, `x:9`, `$'jikigai\nevil.tld'` |
| M16 | Allowlist `case` arms are glob-safe | `evil.com/?x=.sentry.io` and `$'sentry.io\nX'` both REFUSED |
| M17 | Production pairing in GitHub Actions | `scheduled-sentry-alert-drift.yml` and `sentry-audit-gate.yml` both `success` 2026-09-10 |
| M18 | **A perfect recogniser widening does not gate the wrapper** | replacing `"$CURL_BIN"` with a literal `curl` on the `curl_retry` line yields findings at `:441` and `:504` only — **nothing at the wrapper line** |
| M19 | Cost of touching the two former-collateral files | **2 violations, exit 1** — both are **A/B/C**-baseline entries lacking the xtrace refusal, and `--changed` bypasses *both* baselines |
| M20 | **The full final shape lints clean** — `unset` prologue, `_safe`, subshell-scoped `LC_ALL=C` org check at `{0,62}`, `readonly SENTRY_ORG`, `CURL_BIN` adjudication, `SENTRY_HOST_CANDIDATES` array + quoted-RHS membership loop, `readonly api_host`, `--disable --noproxy '*' --proto '=https' -g` on all four curl-binary invocations | `OK: 2 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)`; `bash -n` clean on both |
| M21 | **Two flags do not confine the destination** | `LOCALDOMAIN=com RES_OPTIONS=ndots:5 curl --disable --noproxy '*' http://www.example/` resolved to `www.example.com`; `CURL_CA_BUNDLE=/dev/null` and `SSL_CERT_FILE=/dev/null` each returned rc 77 (honoured). `CURL_HOME`-planted `.curlrc` `resolve` was defeated **only** by `--disable` |
| M22 | **`LC_ALL=C [[ … ]]` is a parse-level bug** | `[[: command not found` — `[[` is a shell keyword, so a prefix assignment is parsed as a command. The working form is `( LC_ALL=C; [[ … ]] )` |
| M23 | **The ERE is locale-dependent** | `é` ACCEPTED under `en_US.UTF-8`, REFUSED under `C`; the subshell-scoped form refuses it under both outer locales |
| M24 | **`CURL_BIN` was never adjudicated** | `CURL_BIN=/tmp/exfil` on the unpatched audit script hands the bearer to an arbitrary program with the flags correctly applied. The patched shape refuses it: `ERROR: refusing curl binary /tmp/exfil`, **0 URLs** |
| M25 | **Final shape, live and negative** | live fidelity `PASS (all 28 …)` exit 0 **with** the `unset` prologue, `--proto '=https'` and `-g`; `SENTRY_API_HOST=eu.sentry.io` (near miss) refused exit 2; `LOCALDOMAIN`/`RES_OPTIONS`/`SSLKEYLOGFILE` in the environment had no effect and no keylog file was created |
| M26 | `cut -c1-120` is byte-based here | `printf 'ééééé' \| cut -c1-3` emits a truncated UTF-8 sequence — use `-b` |
| M27 | An unquoted comparison RHS is a glob | `case "$h" in ${SENTRY_ORG}.sentry.io)` with `SENTRY_ORG='*'` **ACCEPTS** `evil.com/?x=.sentry.io`; the double-quoted arm refuses it |
| M28 | **Guard 1 row 5 reds in the audit script too** | a `_org_ok "$1"` helper refactor, *with* `SENTRY_HOST_CANDIDATES` present, still yields `credentialed curl sends to $SENTRY_ORG, which is env-settable and never compared against a literal` — the array does not adjudicate the org |
| M29 | **The candidate-3 discovery arm** (the one M13 missed) | stub answering 200 only for `de.sentry.io`: probe log is exactly candidates 1, 2, 3 and the run proceeds on `de.sentry.io` |
| M30 | **The discoverability probe was a proxy** | a prototype carrying only the lint-required minimum — no `SENTRY_HOST_CANDIDATES`, no `$api_host` refusal, no flags on `"$CURL_BIN"` — prints the plan's exact `expected_output`, exit 0 |

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (measured) | Plan response |
|---|---|---|
| "3 credentialed curl call sites" | **4** curl-binary invocations carry the bearer across the two files. The fourth, `"$CURL_BIN" -D "$hdr" "$@"` inside `curl_retry`, is invisible to the lint and stays invisible under any recogniser widening (M18). M9 shows it is the site that carried the token off-box. | Confine all four. Gate the fourth with a file-scoped source-level assertion (Guard 3 limb i); move the lint work to #7898 with M18 attached. |
| "`…:441` … `$SENTRY_ORG` unpinned" is implied | The lint reports **no** destination-pin finding at the region-probe site: `_mask_cmdsubs` replaces the whole `$( … )` span with an opaque token. | ACs assert what the lint checks, not what the issue implies. The pin is still added, because the property is the target. |
| "`$SENTRY_API_HOST` … unpinned" (audit script) | The lint scores `api_host` as **adjudicated**, satisfied by the *downstream* region-classification `case "$api_host" in … us.sentry.io) host_region="us" ;;`, which runs **after** every credentialed request and is a classification, not a refusal. | Add a real choke point before the gates. Record the vacuity in the ADR-202 amendment. |
| "a naive single-literal pin breaks its discovery loop" | True, and stronger: unreachable with any credential the repo holds (M6/M7); three of five callers hard-fail when `SENTRY_API_HOST` is empty and the other two always set it. | Keep the loop (CTO ruling); prove it hermetically (M13 + M29); file the delete-the-loop question and persist it as a decision-challenge. |
| `--changed --base origin/main` "reports 0 violations" is the done-when | On a clean branch: `OK: 0 scanned file(s)` (M2). | AC asserts **both** zero violations **and** the scanned-file count. |
| (not in the issue) A destination pin might refuse a suite's real listeners, as in #7873 | **Cleared by enumeration.** No suite binds a socket or uses `localhost`/`127.0.0.1`. Every literal `SENTRY_API_HOST` reaching either script is `de.sentry.io` (21) or `sentry.io` (1, T13); every literal `SENTRY_ORG` is `jikigai` (21) or `fixture` (14 effective invocations through `_run`). | No carve-out needed. Placement and environment are the risks, not set membership. |
| (not in the issue) The two flags confine the destination | They confine the config file and the proxy only (M21). The resolver, the trust anchor, the TLS keylog and the binary are all still caller-settable. | Adopt the repo's `unset` prologue, `--proto '=https'`, and a `CURL_BIN` adjudication. |
| (not in the issue) The set is "closed" | It is **parameterised**, and the residual is tenant confusion rather than exfil — `*.sentry.io` is Sentry-operated SaaS. | Residual restated in the Architecture Decision; Guard 1's harness row and T7 corrected so they do not claim a refusal the design does not perform. |
| (not in the issue) "the four CI callers" | **Five files, six invocation sites.** `apply-sentry-infra.yml` calls both scripts — the fidelity probe at anchor `sentry_alert live fidelity (AC19/AC20)` runs `if: always()`, i.e. **downstream of that workflow's own apply step**. `apps/web-platform/infra/sentry/README.md` documents a sixth invocation, run from a local shell. | Enumeration corrected throughout; the post-apply site gets its own failure mode. |

## Architecture Decision (ADR/C4)

### The region-discovery contract

> **In `apps/web-platform/scripts/sentry-monitors-audit.sh`, the destination host *name* of every
> credentialed request is a member of one hardcoded array, `SENTRY_HOST_CANDIDATES`, parameterised
> only by an org slug constrained to `^[a-z0-9][a-z0-9-]{0,62}$` **evaluated under `LC_ALL=C`**.
> Region *discovery* selects a member; it never widens the array. The `SENTRY_API_HOST` override
> selects a member; it never adds to it. The array is declared once and read by both the loop and the
> refusal, and both `SENTRY_ORG` and `api_host` are `readonly` from the moment they are adjudicated.**
>
> **In `scripts/sentry-alert-live-fidelity.sh`, whose single request is org-scoped, the destination
> is adjudicated against the singleton `"${SENTRY_ORG}.sentry.io"`** — the only host
> `ADR-031-sentry-as-iac.md` permits for org-scoped paths. The two files deliberately do **not**
> share a set.
>
> **A name is not a destination.** Both scripts additionally unset the resolver, trust-anchor and
> TLS-keylog environment (`SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME
> HOSTALIASES LOCALDOMAIN RES_OPTIONS`) before the first request, and refuse a `CURL_BIN` that is not
> `curl` unless an explicit test-injection variable is set.

**Two accepted residuals, stated rather than resolved:**

1. **The set is parameterised, so an attacker who can set `SENTRY_ORG` reaches
   `<their-org>.sentry.io`.** The consequence is **tenant confusion and integrity**, not credential
   exfiltration: `*.sentry.io` is Sentry-operated SaaS, the TLS terminator and certificate are
   Sentry's, and an org admin has no surface exposing inbound request headers. Post-fix, a
   compromised `SENTRY_ORG` sends the bearer to *Sentry* — which minted it and already holds it — and
   Sentry authenticates it against our org (M6/M7: org-scoped paths return 200 only for
   `jikigai-eu`). What an attacker gains is that both probes silently grade a different tenant, that
   `POST /releases/` and its `DELETE` cleanup fire at an attacker-named org path, and that the drift
   detector degrades to `verdict=unavailable`. *Caveat, stated because it was not measured: this
   rests on Sentry's cert/tenancy model. If Sentry ships customer-controlled origins at org
   subdomains, the residual reverts to confidentiality.* Closing it means adjudicating `$SENTRY_ORG`
   against the org id Gate 1 returns — a different mechanism, in a script whose Gate 1 runs *after*
   the discovery probes. That is Deferral 2.
2. **Discovery cannot succeed with any credential the repo holds (M6), so the loop's guard is
   exercised by stubs only, permanently.** That is the leading argument in the delete-the-loop
   follow-up.

**The audit script's wider set is a test-literal constraint, not a destination contract, and must say
so in-file.** Every credentialed request in that file except the `/users/me/` discovery probe is
org-scoped, so `ADR-031`'s glossary would put them all on `${SENTRY_ORG}.sentry.io`. The set stays
wider because 21 suite rows pass `SENTRY_API_HOST=de.sentry.io`. Tightening it is a follow-up.

### ADR

**No new ordinal.**

- **`knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md`**
  — record the Rule D contract under **`## Consequences`**, and the residuals in its existing
  `### Named residual holes` section. **Do not touch `## Decision`.** That Decision is a *criterion
  for a fork* ("where a hazard is a property of runtime STATE, enforce it with a carried
  self-refusal … not with a boundary interceptor"), written at that altitude on purpose. Rule D is
  not a runtime-state hazard and its remedy is not a carried self-refusal in that sense. Two
  frictions confirm it: ADR-202's Consequences pin exit **78** with a paragraph of argument while
  Rule D refusals are exit **2**; and its Alternatives explicitly **cut** extending the lint to CI
  `run:` bodies, which is exactly where the `sentry-audit-gate.yml` residual lives. An unqualified
  obligation written into `## Decision` would make the repo violate its own ADR on the line above the
  fixed one.

  Text to add under `## Consequences`:

  > The same lint carries a second rule, Rule D (#7873): a script that forwards a credential over
  > `curl` must pass `--disable` as curl's literal first argument and `--noproxy '*'`, and must
  > adjudicate any env-settable destination against a literal. Three residuals are known and
  > enumerated rather than implied. (a) An invocation reached through a wrapper *function* is outside
  > the rule's reach: widening the recogniser to variable-mediated invocations does **not** help,
  > because the `credentialed` predicate reads the invocation's own text while the credential arrives
  > from the call site inside `"$@"` (measured, #7997). (b) An adjudication that runs *after* the
  > request, or that is a classification rather than a refusal, satisfies `_pin_re` while providing no
  > confinement — measured on `api_host` in `apps/web-platform/scripts/sentry-monitors-audit.sh`.
  > (c) The rule confines the config file and the proxy, and says nothing about the resolver
  > (`LOCALDOMAIN`, `RES_OPTIONS`, `HOSTALIASES`), the trust anchor (`CURL_CA_BUNDLE`,
  > `SSL_CERT_FILE`, `SSL_CERT_DIR`), the TLS keylog (`SSLKEYLOGFILE`) or the binary itself — all
  > measured caller-settable with a compliant call site. The repo's answer is the `unset` prologue in
  > `scripts/zot-inventory.sh` and `scripts/betterstack-query.sh`; a script that pins a destination
  > without it is describing a pin the process does not have.

- **`knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`** — correct the line
  at anchor `The canonical EU API base_url is therefore` / `https://eu.sentry.io/api/` — set on the
  Terraform provider config in `main.tf``, which contradicts both the same file's Cluster/Host
  Glossary (whose API row already states org-scoped paths **MUST** use `<org-slug>.sentry.io/api/`)
  and the live IaC (`apps/web-platform/infra/sentry/main.tf`,
  `base_url = "https://${var.sentry_org}.sentry.io/api/"`). Then add **one** sentence recording that
  the audit script's `/users/me/` discovery probe is that file's only slug-less credentialed call.
  **Do not** word the amendment as "`SENTRY_HOST_CANDIDATES` is the single source of truth for the
  Sentry API host set" — that would contradict the glossary's org-scoped MUST, and would couple an
  architecture record to a bash array identifier a rename could silently falsify.

  > **Pre-existing, out of scope:** two files claim ordinal 031. Edit by full filename; renumber
  > neither.

### C4 views

**No C4 impact.** Justified by enumeration against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`:

- **External human actors:** none added or changed.
- **External systems:** Sentry is already modelled — `model.c4` anchor `sentry = system "Sentry" {`
  with `#external`, in both the `context` and `containers` views. No new vendor or store.
- **Containers / data stores:** none touched.
- **Actor↔surface access relationships:** unchanged.
- **Descriptions this change could falsify:** the `sentry` element description already states the API
  host class is the **org subdomain** and warns against `eu.sentry.io` for org-scoped paths. The pin
  encodes that model.
- **Derived cardinalities:** `plugins/soleur/test/c4-count-parity.test.sh`'s `REGISTRY` guards C1-C7.
  C1 derives from `grep -rlF 'actions/sentry-heartbeat' .github/workflows/`; C2/C3 from a python
  split of the same directory; C4 from `grep -cF 'resource "sentry_cron_monitor"' apps/web-platform/infra/sentry/cron-monitors.tf`;
  C5 from `monitor-slug:` values in `.github/workflows/`; C6 is `C4 − C5`; C7 from
  `.github/workflows/` and `.github/actions/`. This PR edits three workflow files, so the parity gate
  is **run, not reasoned about**: none of the three edits adds or removes a heartbeat reference, a
  `schedule:` key, a `monitor-slug:`, or a Resend emitter, but `/work` executes
  `bash plugins/soleur/test/c4-count-parity.test.sh` and records it green.

### Sequencing

Both ADR amendments land in this PR.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — but the operator loses production
gates, and the six invocation sites fail in *four different ways*, only three of them routed:

- `.github/workflows/apply-sentry-infra.yml`, **pre-plan** (audit script, anchor
  `Sentry audit-gate (4-gate destination-controllability)`) — a refusal aborts the step before
  `Terraform plan (full root)`, so plan and apply are skipped. Loud, and routed: the same job carries
  `File or comment tracking issue (apply failed)` with an unconditional `if: failure()`.
- `.github/workflows/apply-sentry-infra.yml`, **post-apply** (fidelity script, anchor
  `sentry_alert live fidelity (AC19/AC20)`, `if: always()`) — the apply has already landed. A refusal
  here reds a run whose infrastructure change is complete, which can be misread as a half-applied
  adoption. Loud, routed by the same filer.
- `.github/workflows/scheduled-sentry-alert-drift.yml` — a refusal yields `verdict=unavailable`, and
  the workflow's `File or update the probe-unavailable issue` step (`if: always() && failure()`)
  files an issue titled `[ci/sentry-alert-drift] the drift probe could not establish a verdict`.
  Loud, routed, and correctly distinguished from a drift finding.
- `.github/workflows/sentry-audit-gate.yml` — red job, **no issue filed**, and absent from
  `scripts/required-checks.txt`, so it blocks nothing. Quiet. (Deferral 3.)
- `.github/workflows/reusable-release.yml` — `continue-on-error: true`, `set +e`, `exit 0` on any rc.
  The release stays **green** and the **GDPR Article 30 evidence artifact silently stops being
  attached**. The quietest and worst; the only signal is a `::warning::` annotation.
- `apps/web-platform/infra/sentry/README.md` — an operator terminal. Synchronous stdout/stderr the
  operator reads in-session; there is no async sink and there must not be one.

**If this leaks, the user's data is exposed via:** the Sentry org bearer token, and the primary
consequence is **write**, not read. `apps/web-platform/scripts/sentry-monitors-audit.sh` performs
`-X POST … /releases/` (anchor `gate3_http=$(CURL_RETRY_UNSAFE=1 curl_retry`) and `-X DELETE` (anchor
`curl -s --max-time 10 -X DELETE \`) with the same bearer, and `scheduled-sentry-alert-drift.yml`
hands the script `secrets.SENTRY_IAC_AUTH_TOKEN` — the token that drives `apply-sentry-infra.yml`. An
exfiltrated credential can **mutate or delete alert rules and cron monitors**, i.e. silently remove
the detection surface that would notice the next incident. That is what makes one occurrence
brand-fatal. On the read side the exposure is error messages, stack frames and request context —
**not** user ids: the client path deletes them (`apps/web-platform/sentry.client.config.ts`, anchor
`stripUserContextFromEvent`) and the server path scrubs recursively
(`apps/web-platform/server/sentry-scrub.ts`, anchor `export function scrubSentryEvent`).

This is measured, not hypothetical: M9 recorded the bearer reaching
`https://attacker.tld/api/0/organizations/jikigai-eu/` on `main`. **The softest target is the
operator's own workstation**, not CI: on a runner `~/.curlrc`, the proxy variables, the resolver
variables and `CURL_BIN` are all controlled by the workflow, but on a laptop running
`doppler run … bash scripts/sentry-alert-live-fidelity.sh` every one of them is reachable by anything
that can set an environment variable — a strictly lower bar than writing a dotfile. `--disable`, the
`unset` prologue and the `CURL_BIN` adjudication all do most of their work there.

**Credential rotation.** `/work` must answer this in the PR body, not leave it silent: the defect has
been live for the lifetime of both scripts. The finding to record is whether any untrusted context has
executed either script — the five callers are GitHub-hosted runners with repository secrets, plus the
operator's own machine — and therefore whether `SENTRY_AUTH_TOKEN` / `SENTRY_IAC_AUTH_TOKEN` warrant
rotation on merge. A one-line "no rotation, because X" is acceptable; silence is not.

**Residual after this PR:** a compromised `SENTRY_ORG` still reaches an attacker-owned `*.sentry.io`
tenancy (Architecture Decision, residual 1). And 80 of 82 D-baseline entries remain, 15 of them under
`plugins/soleur/skills/**` where they execute on Soleur users' own machines — tracked by #7898.

**Brand-survival threshold:** `single-user incident` — confirmed by CPO on the write-capability
ground, and standing on the **pre-fix** M9 evidence rather than on the post-fix residual.
`requires_cpo_signoff: true`; `plan-review` escalated to the five-agent panel;
`user-impact-reviewer` runs at review time.

## Open Code-Review Overlap

`gh issue list --label code-review --state open … | jq --arg path …` returned **zero** matches for
each of the plan's file paths.

**That sweep was insufficient.** #7898 — `type/chore`, not `code-review` — is the consolidated Rule D
drawdown tracker and its §4 owns the `CURL_BIN` seam. Disposition: **fold in as `Refs #7898`, not
`Closes`.** This PR closes 2 of its 82 entries, corrects its false "no current offender uses that
seam" claim, and hands it M18 (why a recogniser widening is not the remedy) and M24 (the seam's other
half — the binary — which nothing in #7898 names).

## Files to Edit

Content anchors in preference to line numbers (`cq-cite-content-anchor-not-line-number`). Every shape
below is the one measured in **M20/M25**, not a paraphrase of it.

| File | Change |
|---|---|
| `scripts/sentry-alert-live-fidelity.sh` | After anchor `: "${SENTRY_ORG:?SENTRY_ORG must be set}"`: (1) the `unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS` prologue; (2) `_safe() { printf '%s' "${1//[[:cntrl:]]/}" \| cut -b1-120; }` — **defined before its first use**; (3) the org refusal `( LC_ALL=C; [[ "$SENTRY_ORG" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] ) \|\| { … exit 2; }`; (4) `readonly SENTRY_ORG`. Host adjudication **inside `fetch_rules()`**, immediately after anchor `: "${SENTRY_API_HOST:?SENTRY_API_HOST must be set (org-subdomain, e.g. jikigai-eu.sentry.io)}"`, as `case "$SENTRY_API_HOST" in "${SENTRY_ORG}.sentry.io") ;; *) … exit 2 ;; esac` — arm **double-quoted**. `--disable --noproxy '*' --proto '=https' -g` as the first four arguments at anchor `curl -fsS --max-time 15 \`. Header prose adapted from `scripts/supabase-logs-query.sh`'s `# HOST PIN — NO ENV OVERRIDE`, extended to name the resolver/trust-anchor vector. **Update the exit-code contract** at anchors `Exit 0 = every in-scope rule matches the capture.` / `Exit 1 = a divergence, …` to add exit 2. |
| `apps/web-platform/scripts/sentry-monitors-audit.sh` | Change anchor `: "${SENTRY_ORG:=jikigai}"` to a required form (`:?`) — `jikigai` is recorded canceled in `ADR-031-sentry-as-iac.md`. Then the same four-part block (prologue, `_safe`, org refusal, `readonly SENTRY_ORG`) **above** anchor `CURL_BIN="${CURL_BIN:-curl}"`. Immediately after that anchor, the binary adjudication `[[ "$CURL_BIN" == "curl" \|\| -n "${SENTRY_AUDIT_TEST_CURL_BIN:-}" ]] \|\| { … exit 2; }`. `readonly SENTRY_HOST_CANDIDATES=("${SENTRY_ORG}.sentry.io" eu.sentry.io de.sentry.io sentry.io)` immediately above anchor `# --- Region detection (skipped if SENTRY_API_HOST is set) -----------------`, with an in-file comment recording that it is wider than the org-scoped contract requires and why. Discovery loop iterates it; the `ERROR: Sentry token not valid against any candidate host (…)` message renders from it. Membership refusal on `$api_host` between the discovery block's closing `fi` and anchor `# --- 4-gate destination-controllability check (PR-β §10 / C5) -------------`, as a loop with a **double-quoted RHS** (`[[ "$api_host" == "$_c" ]]`), followed by `readonly api_host`; the message must be textually distinguishable from the file's pre-existing `exit 2` at anchor `ERROR: residency mismatch — probed=`. `--disable --noproxy '*' --proto '=https' -g` first at anchors `http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \`, `curl -s --max-time 10 -X DELETE \`, and `if result=$("$CURL_BIN" -D "$hdr" "$@" 2>/dev/null); then`. |
| `apps/web-platform/scripts/sentry-monitors-audit.test.sh` | Extend `mk_curl_stub` to log every URL and — **gated on `STUB_REQUIRE_DISABLE=1`**, exported by `run_sut_stubbed` and the new rows only — to assert `$1 == --disable && $2 == --noproxy && $3 == '*'`. T18a-f gain `SENTRY_AUDIT_TEST_CURL_BIN=1`. New rows continue the file's own numbering from **T26** (see Test Scenarios). |
| `tests/scripts/test-sentry-alert-live-fidelity.sh` | New rows F14-F18 (see Test Scenarios). Set `EXPECTED_TESTS` to the new total (**13 today + 5 = 18**) — it is an exact-equality harness, not a floor; state the invariant as "must equal the number of `t_*` invocations in the call block at the foot of the file". |
| `.github/workflows/sentry-audit-gate.yml` | Add `--disable --noproxy '*' --proto '=https' -g` as the first arguments at anchor `http=$(curl -s -o /dev/null -w '%{http_code}' \`, and the `unset` prologue at the top of that `run:` block. The same job sends `Authorization: Bearer ${SENTRY_AUTH_TOKEN}` to `"https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/"` **before** the script runs, with the same secrets; without this the PR's own gate job still leaks. Destination adjudication there is Deferral 3 (#7898 §3, YAML scope gap). |
| `.github/workflows/scheduled-sentry-alert-drift.yml` | In the probe-unavailable issue body, after anchor `printf -- '- Run log: %s\n\n' "$RUN_URL"`, dump the probe output the way the *sibling drift filer* already does — `printf '### Probe output\n\n\`\`\`\n'; cat "${RUNNER_TEMP}/probe.txt"; printf '\`\`\`\n\n'` — guarded on the file existing (it will not on a pre-probe abort). **This replaces the first draft's static checklist item**: the body today prints only a static header, the verdict, a timestamp, a run URL and a fixed four-item list, and never `cat`s `probe.txt`, so the refusal message this plan carefully designs would reach only the run log. Same edit cost, strictly more information. |
| `.github/workflows/reusable-release.yml` | At anchor `::warning::Sentry migration audit script exited`, branch the warning text on a refusal (`grep -q 'refusing'`) so the swallowed path names the secret pairing rather than the non-array-payload diagnostic a refusal never reaches. |
| `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` | Delete exactly the two lines `apps/web-platform/scripts/sentry-monitors-audit.sh` and `scripts/sentry-alert-live-fidelity.sh`. 82 → 80. **Do not** run `--write-baseline-d`. |
| `knowledge-base/engineering/architecture/decisions/ADR-202-…md` | `## Consequences` + `### Named residual holes` only. Not `## Decision`. |
| `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` | Glossary `base_url` correction + one sentence on the discovery probe. |
| `knowledge-base/project/specs/feat-one-shot-7997-sentry-curl-transport-confinement/tasks.md` | Created by this skill. |

**Files to create:** `knowledge-base/project/specs/feat-one-shot-7997-sentry-curl-transport-confinement/decision-challenges.md`
(seeded at plan time). Eleven files edited, one created.

**Three implementation constraints, each measured rather than reasoned:**

1. **`LC_ALL=C [[ … ]]` does not work.** `[[` is a shell keyword, so a prefix assignment is parsed as
   a command invocation: `[[: command not found` (M22). Use `( LC_ALL=C; [[ … ]] )`. Without the
   scoping the guard is *weaker on the operator's laptop than in CI* (M23).
2. **The `$SENTRY_ORG` shape test must name `$SENTRY_ORG` literally inside the `[[ … =~ … ]]`.**
   `_pin_re` builds its pattern from the variable name, so a shared
   `_org_ok() { [[ "$1" =~ … ]]; }` helper leaves the lint red — measured in **both** files (M28),
   including the audit script where `SENTRY_HOST_CANDIDATES` might have been expected to adjudicate
   it and does not. Only `_safe` is shared in shape, not code.
3. **`_safe` must be defined above its first call.** The first draft of this prescription placed the
   org refusal above the helper and produced `_safe: command not found` at runtime, with the refusal
   still firing on an empty value.

## Implementation Phases

### Phase 0 — Re-measure

Re-run M1, **M2**, M3, M4, M8, M18 and M19. Any divergence stops the run. M2 is load-bearing here,
not only as AC2: if it no longer reports `0 scanned file(s)`, another branch has already touched these
files and the plan needs re-scoping before any edit.

### Phase 1 — `scripts/sentry-alert-live-fidelity.sh`

RED is in hand (M1). Write the new suite rows first (`cq-write-failing-tests-before`), watch them
fail, then edit the script. Order within the file matters: prologue → `_safe` → org refusal →
`readonly` → (inside `fetch_rules`) host `case` → flags.

### Phase 2 — `apps/web-platform/scripts/sentry-monitors-audit.sh`

1. `: "${SENTRY_ORG:=jikigai}"` → required form. Verify T1 still passes: it runs under `env -i` and
   asserts the diagnostic names `SENTRY_AUTH_TOKEN`, whose check precedes this line.
2. Prologue, `_safe`, org refusal, `readonly SENTRY_ORG` — above `CURL_BIN="${CURL_BIN:-curl}"`, so
   outside T18's `awk` slice.
3. `CURL_BIN` adjudication immediately after that anchor.
4. `SENTRY_HOST_CANDIDATES` array above the region-detection block, with its in-file justification.
5. Loop iterates the array; the all-fail message renders from it.
6. Membership refusal on `$api_host` after the discovery block and before the gates; `readonly
   api_host`.
7. Flags first at all three curl-binary invocations, including `"$CURL_BIN"` **inside** `curl_retry`
   — at a call site they would land in `"$@"` and be swept by the write-safety inference
   (`case "$arg" in -X[!G]*|…`). Measured neutral either way, but inside the wrapper the neutrality
   is structural rather than incidental.

### Phase 3 — the three workflow edits

`sentry-audit-gate.yml` flags + prologue; `scheduled-sentry-alert-drift.yml` probe-output dump;
`reusable-release.yml` warning branch. All three are in files the plan would otherwise declare
untouched while its own failure modes route through them.

### Phase 4 — baseline drawdown

Delete the two D-baseline entries by hand. Run the repo-wide, no-flags lint and confirm
`OK … 80 baselined (D)`. Note that `offenders_d` drops to 80 as soon as the two scripts are clean,
**whether or not the file was edited** — AC4's grep, not AC3's count, proves the drawdown happened.

### Phase 5 — ADR amendments

Read each file first. Amend `ADR-202` under `## Consequences` and `### Named residual holes`; amend
`ADR-031-sentry-as-iac.md`'s glossary. Run the ADR gates `scripts/test-all.sh` registers, including
`scripts/check-adr-ordinals.sh`, and record them green (confirm the duplicate ordinal 031 is tolerated
today rather than assuming it).

### Phase 6 — verification

Executes the Acceptance Criteria. Kept as its own phase so `tasks.md` §6 maps 1:1.

### Phase 7 — follow-ups and the decision record

File the issues in Deferrals; comment the correction on #7898; finalise
`decision-challenges.md` so `/ship` renders it into the PR body and files it as `action-required`.

## Guard Contract

### Guard 1 — `SENTRY_ORG` shape refusal

**Property.** No value of `$SENTRY_ORG` that reaches a URL in either script can introduce a host,
userinfo, a path separator, a query, a fragment, a port or a control character: only ASCII
`[a-z0-9-]`, not leading with `-`, 1-63 characters (RFC 1035 §2.3.4 caps a DNS label at 63 octets, so
the ERE is `{0,62}` after the mandatory first character). The property holds **under any locale of the
calling shell**, because the test is evaluated in a subshell that sets `LC_ALL=C`. This is a **shape**
property, not an identity one: a well-formed slug that is not ours still passes, and the destination
consequence of that is residual 1, not a refusal Guard 2 performs.

**Assembly.** Every point at which `$SENTRY_ORG` becomes part of a URL. This is held *structurally*,
not by a count: in each file the variable is read from the environment once, adjudicated, and then
made `readonly` — so no later assignment can reintroduce an unvalidated value, and the assembly is
"everything downstream of the `readonly`", which is derivable rather than enumerated. There are two
such binding sites, one per file (`scripts/sentry-alert-live-fidelity.sh` anchor
`: "${SENTRY_ORG:?SENTRY_ORG must be set}"`; `apps/web-platform/scripts/sentry-monitors-audit.sh`
anchor that today reads `: "${SENTRY_ORG:=jikigai}"`), and Guard 3 limb (i)'s extractor — which
already parses both files — additionally derives every host-position expansion `https://${…}` and
requires the variable to be one of `api_host`, `candidate` or `SENTRY_API_HOST`, so a *new* binding
site or a *new* host variable reds without anyone updating a list.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Delete the refusal from `sentry-alert-live-fidelity.sh` only | one binding site per file; a single-file guard leaves the other file's URL assembly open |
| 2 | Delete the refusal from `sentry-monitors-audit.sh` only | same, opposite direction |
| 3 | Relax the pattern to `^[a-z0-9./@-]+$` | the userinfo/path values in M15 (`@evil.tld/x`, `x@y`, `x/y`) pass and the injection channel reopens. The row is table-driven over M15's full REFUSE list so it does not share a fixture with row 4 |
| 4 | Drop the `^`/`$` anchors | `$'jikigai\nevil.tld'` passes; bash compiles EREs without `REG_NEWLINE`, so an unanchored pattern matches a prefix. **This is the only value that discriminates anchoring**, and it is a suite fixture, not just an M-row |
| 5 | Drop the `( LC_ALL=C; … )` scoping | under `en_US.UTF-8` the range admits 1,162 non-ASCII characters (M23). The row runs the same fixture under both `LC_ALL=C` and `LC_ALL=en_US.UTF-8` |
| 6 | Refactor the test into a helper taking `"$1"` and call it with `"$SENTRY_ORG"` | the **lint** must go red: `_pin_re` builds its pattern from the variable name (M28, measured in both files). This row is why the two files cannot share the test's code |
| 7 | Delete the `readonly SENTRY_ORG` and reassign below it (`SENTRY_ORG="${SENTRY_ORG}-eu"`) | the assembly is "everything downstream of the readonly"; without it the guard is a point-in-time assertion and every downstream interpolation carries an unvalidated value. **This is the order/lifetime row** — a delete-only battery cannot see it |
| 8 | Move the audit-script refusal above `: "${SENTRY_AUTH_TOKEN:?…}"` | the guard fires before the token check and changes T1's diagnostic; T1's `grep -qi 'SENTRY_AUTH_TOKEN'` catches the reorder |

**Harness rows.** (a) Replace the hostile fixture value with a benign one — the row must go RED,
proving the assertion reads the fixture and not a constant. (b) A must-PASS at the **shape boundary**:
a 63-character slug accepted, a 64-character one refused (M-verified). *`SENTRY_ORG=fixture` is
deliberately **not** the must-PASS example — 27 existing rows already carry it, so it discriminates
nothing; and `attacker-org` is deliberately not one either, because it is accepted by Guard 2 as well
and using it would claim a refusal the design does not perform.*

### Guard 2 — destination adjudication

**Property.** Every credentialed request **in either script** reaches a host whose **name** that file
adjudicates against a literal — membership in `SENTRY_HOST_CANDIDATES` (audit), equality with
`"${SENTRY_ORG}.sentry.io"` (fidelity) — **and** whose resolution and certificate validation are
confined to the system's own configuration by the `unset` prologue. The two halves are separate
properties and both are required: without the prologue the name property is not a destination
property (M21). The property does not quantify over the inline `curl` in
`.github/workflows/sentry-audit-gate.yml`, which this PR transport-confines but does not adjudicate.

**Assembly.** Three chokepoints plus a derivation, not a list of call sites. (i) The
`readonly SENTRY_HOST_CANDIDATES=(…)` declaration in the audit script — the chokepoint for the
**discovery probes**, which are credentialed, build their URL from `$candidate` rather than
`$api_host`, and fire **before** `api_host` is assigned. Given Guard 1 above it, the array closes
them. (ii) The `$api_host` membership refusal, followed by `readonly api_host` — the chokepoint for
the `SENTRY_API_HOST` override and for Gates 1-3, `sentry_fetch_collection`, the paginated fetches and
the Gate-3 DELETE cleanup, all of which build from `${api_host}`; the `readonly` is what makes it a
chokepoint rather than a point-in-time check. (iii) `$SENTRY_API_HOST` inside `fetch_rules()` after
the fixture short-circuit — the fidelity script's single request. (iv) The derivation in Guard 3 limb
(i) that requires every `https://${…}` host-position expansion in either file to name one of
`api_host`, `candidate`, `SENTRY_API_HOST` — so a *new* request built from a *new* variable is inside
the assembly rather than outside it. `sentry_next_cursor` is covered and not a gap: it issues no
request, validates the cursor against `^[A-Za-z0-9:_.~=+-]+$` and rebuilds from `$api_host`; the
covering rows are the pre-existing **T20b/T20d/T20e**.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Move the audit-script `$api_host` refusal to **after** the 4-gate block | Gate 1 is the first request built from `$api_host`; a refusal after it certifies a window in which the token has already left (the **order** row). The row must run **non-fixture** — `SENTRY_FIXTURE_MONITORS` skips the entire 4-gate block, so a fixture-mode row stays green on the mutant |
| 2 | Unquote the membership comparison RHS (`[[ "$api_host" == $_c ]]`, or an unquoted `case` arm) | the comparison becomes a glob; M27 measured `evil.com/?x=.sentry.io` ACCEPTED. This is the audit script's real form of the `*`-in-an-arm hazard — the array element is inert unless the comparison globs |
| 3 | Add `*.sentry.io` as an arm of the fidelity `case` | there the arm *is* a glob (M16). The assertion anchors on the two new constructs (`SENTRY_HOST_CANDIDATES=(` and the `case "$SENTRY_API_HOST" in` inside `fetch_rules()`), **never** on "any `*.sentry.io` in the file" — the audit script's pre-existing residency `case` legitimately carries `*.sentry.io)` |
| 4 | Delete Guard 1 while keeping Guard 2 | nothing else forces `SENTRY_HOST_CANDIDATES` element 0 to be constrained; without Guard 1 the array's own first member is attacker-shaped |
| 5 | Delete `readonly api_host` and reassign `api_host` inside the residency block | limb (ii) is a chokepoint only while the value cannot change after it |
| 6 | Delete one name from the `unset` prologue (e.g. `LOCALDOMAIN`) | M21: resolution is redirected with the name pin fully intact. Table-driven over all eight names |
| 7 | Delete the refusal but leave the downstream `case "$api_host" in … host_region=` classification | the lint still reports the file clean (measured), so only a suite row can see this |
| 8 | Widen the fidelity `case` to the audit script's four members | its single endpoint is org-scoped and `eu.sentry.io` 302→401s `-eu` slugs. Derivable because T9 is table-driven over the **near-miss** hosts `{eu.sentry.io, de.sentry.io, sentry.io}` expecting refusal — M25 measured `eu.sentry.io` refused by the singleton |

**Harness rows.** (a) Point the hostile-environment row at production's real pairing
(`SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io`) and assert it is **accepted** — no
existing suite row uses it, and a battery of refusals alone cannot distinguish a correct guard from
one that rejects everything. Confirmed it does not trip the residency detector: that `case` has a
`*.sentry.io)  host_region="" ;;` arm, so the comparison is skipped for an org subdomain. (b) Break
the assertion's own extractor (point it at a nonexistent file) and require it to fail loudly rather
than compare two empty sets.

### Guard 3 — transport and execution confinement

**Property.** Every process invocation of a curl binary in either script (a) executes `curl`, not a
caller-named path, (b) passes `--disable` as its literal first argument followed by `--noproxy '*'`,
and (c) runs with the resolver/trust-anchor/keylog prologue applied — including an invocation reached
through a variable or a wrapper function.

**Assembly.** Not the four call sites that exist today. The assembly is *every token in either file
that causes a curl binary to be executed*, held by two limbs plus a derivation, because none alone
suffices. (i) A **source-level closure** assertion, written as a function taking a file list, that
enumerates curl-invoking tokens from the file and requires each to be immediately followed by the
flag prefix; it also derives every `https://${…}` host-position expansion (feeding Guard 2 limb iv)
and asserts the eight `unset` names are present above the first invocation. Its extractor **strips
comments first and reuses the lint's own boundary shape** —
`(?:^|[|;&(\`$]|\s)(?:[\w./-]*/)?curl(?:\s|$)` — plus variables assigned `"${NAME:-curl}"`; a naive
token scan flags the `CURL_BIN` seam comment, the `curl_retry` metadata block, and the identifiers
`curl_retry`, `curl_retry_status`, `CURL_BIN`, `CURL_LAST_HDR_FILE`. This limb is the **load-bearing
gate for the `curl_retry` wrapper**, because M18 measured that no recogniser widening in the
repo-wide lint can reach it, and for any invocation **no row reaches at runtime**. (ii) A **runtime**
assertion in `mk_curl_stub` checking `$1 == --disable && $2 == --noproxy && $3 == '*'`, **gated on
`STUB_REQUIRE_DISABLE=1`** exported by `run_sut_stubbed` and the new rows — T18d invokes the same stub
bare, as the control half of a byte-identity diff (anchor
`body_bare=$("$TMP18/curl" -s "https://de.sentry.io/api/0/x/"`), where `$1` is `-s` by design; an
unconditional assertion reds the row that guards the `-w` defect `curl_retry`'s own comment block is
written about. (iii) The `CURL_BIN` adjudication itself, which is what makes (a) true at runtime.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Move `--disable` to after `-fsS` in the fidelity script | `--disable` is a no-op unless first (measured: a `CURL_HOME`-planted `.curlrc` still won with `curl -s --disable`, and lost with `curl --disable -s`). Carried by limb (i) statically and by F17 at runtime |
| 2 | Drop `--noproxy '*'` from `curl_retry` only | the wrapper is the site M9 measured carrying the token off-box, and M18 shows the repo-wide lint cannot see it. Limb (ii)'s `$2`/`$3` check is what makes this row visible at runtime |
| 3 | Add a **new**, fifth curl invocation to either file without the flags | limb (i) derives its site list from the file, not from a hardcoded count of four |
| 4 | Rename `CURL_BIN` to `CURL_CMD`, keeping `="${CURL_CMD:-curl}"` | a name-based extractor goes green while the property is unchanged; the derivation must read the assignment |
| 5 | Delete the `CURL_BIN` adjudication | M24: `CURL_BIN=/tmp/exfil` hands the bearer to an arbitrary program with the flags correctly applied and every other guard green |

**Rows 3 and 4 must be attributed, not just observed.** The audit suite already ships **T22** (anchor
`T22: assembly — every Sentry call goes through curl_retry`), which counts execution sites with a
**name-based** `grep -cE '…CURL_BIN…'`. Row 3 reds T22 (`n_bare=3`) and row 4 reds T22 (`n_seam=0`) —
row 4 being precisely the name-based extractor it exists to condemn. Run both rows with T22
neutralised, or assert *which* row failed; otherwise the battery reports a verdict about T22.

**Harness rows.** (a) Point limb (i)'s file list at a directory with no scripts — it must fail rather
than report "0 checked, all pass". This requires limb (i) to be **a function taking a file list**, not
an inline check over `$SCRIPT`. (b) A must-PASS non-canonical input: an invocation carrying the flag
prefix with a different *subsequent* argument order (`curl --disable --noproxy '*' --max-time 5 -sS …`
vs `… -sS --max-time 5 …`) must be accepted, proving the assertion constrains the prefix and not the
whole argv.

## Observability

```yaml
liveness_signal:
  what: the two scripts' exit status across six invocation sites in five files — and it is a
        liveness signal in only four. apply-sentry-infra.yml fails the job at BOTH its sites (the
        audit pre-plan, the fidelity post-apply under `if: always()`) and routes them through its
        own `File or comment tracking issue (apply failed)` step (`if: failure()`);
        scheduled-sentry-alert-drift.yml converts a non-zero exit without the FAILED marker into
        verdict=unavailable and files an issue; sentry-audit-gate.yml reds a job that files nothing
        and is absent from scripts/required-checks.txt; reusable-release.yml is
        `continue-on-error: true` and exits 0, so the exit status is SWALLOWED and only the Article
        30 evidence artifact goes missing; the sixth site
        (apps/web-platform/infra/sentry/README.md) is an operator terminal whose only signal is the
        synchronous stdout/stderr the operator reads in-session — there is no async sink and there
        must not be one. That README invocation sets neither SENTRY_ORG nor SENTRY_API_HOST
        explicitly, inheriting both from Doppler prd (M5 measured them correct), so the `:?` change
        does not break it.
  cadence: scheduled-sentry-alert-drift.yml daily at 07:15 UTC (Inngest `cron-sentry-alert-drift.ts`,
           `{ cron: "15 7 * * *" }`; last green run 2026-09-10T07:15:03Z, M17); the others on merge
           and on release
  alert_target: two filers, both existing and both verified reachable by a non-zero exit — the
                `File or update the probe-unavailable issue` step in
                .github/workflows/scheduled-sentry-alert-drift.yml (`if: always() && failure()`,
                title "[ci/sentry-alert-drift] the drift probe could not establish a verdict",
                label ci/sentry-alert-drift), and the `File or comment tracking issue (apply failed)`
                step in .github/workflows/apply-sentry-infra.yml (`if: failure()`). This PR makes the
                first one carry the refusal text rather than only a static checklist.
  configured_in: .github/workflows/scheduled-sentry-alert-drift.yml and
                 .github/workflows/apply-sentry-infra.yml (both existing; this PR edits the former's
                 issue body only)
error_reporting:
  destination: script stderr. Today that reaches the Actions job log ONLY — the probe-unavailable
               issue body prints a static header, the verdict, a timestamp and a run URL, and never
               `cat`s the probe output (unlike the sibling drift filer, which does). This PR's
               scheduled-sentry-alert-drift.yml edit is what makes "and the issue body" true.
  fail_loud: true at four of six sites — every new refusal is `exit 2` under `set -euo pipefail`, and
             in the fidelity script it propagates out of `live_json="$(fetch_rules)"` rather than
             being swallowed (M12). NOT loud in reusable-release.yml (swallowed by design) or in
             sentry-audit-gate.yml (red but unrouted).
failure_modes:
  - mode: a destination, org or CURL_BIN refusal fires in production because the secret pairing
          drifted (secrets.SENTRY_ORG changed without SENTRY_API_HOST)
    detection: layer 6 (synchronous workflow-run log) — the refusal message on stderr, named for the
               rejected value (control-stripped, byte-bounded), the expected set, and the file and
               anchor to amend; dumped into the probe-unavailable issue body by this PR's edit.
               Layers 1-5 are structurally unreachable: neither script emits to Sentry or journald
               and GitHub runners are not Vector-shipped.
    alert_route: the probe-unavailable issue (drift) and the apply-failed tracking issue
                 (apply-sentry-infra). NOT routed from sentry-audit-gate.yml — Deferral 3
  - mode: a destination refusal fires POST-APPLY in apply-sentry-infra.yml (the fidelity probe runs
          `if: always()` after `terraform apply`)
    detection: layer 6 — the same refusal text, in a run whose infrastructure change has already
               landed. The message must be distinguishable from the neighbouring AC17 `::error::`
               so it is not misread as a half-applied adoption
    alert_route: the apply-failed tracking issue in the same job
  - mode: a refusal fires during a release
    detection: layer 6 only — `::warning::Sentry migration audit script exited 2` on the release run,
               whose text this PR branches to name the secret pairing
    alert_route: none blocking (by design). The durable observable is the missing Article 30
                 evidence artifact
  - mode: a refusal fires in a test because a suite introduces a new host or org literal
    detection: the file-scoped suites (Guard 1/2 rows) fail in `bash scripts/test-all.sh scripts`
    alert_route: the required `test` context on the PR
  - mode: the transport flags, the unset prologue or the CURL_BIN adjudication are silently dropped
          by a future edit
    detection: Guard 3 limb (i) — the repo-wide lint cannot see the wrapper (M18) and cannot see the
               prologue or the binary at all
    alert_route: the required `test` context
  - mode: the lint reports clean having scanned nothing (the M2 shape)
    detection: the acceptance criteria assert the scanned-file count, not only the exit code
    alert_route: PR review
logs:
  where: GitHub Actions job logs for the five CI invocation sites; the operator's own terminal for
         the sixth
  retention: GitHub's default workflow log retention; none for the terminal
discoverability_test:
  command: bash apps/web-platform/scripts/sentry-monitors-audit.test.sh
  expected_output: "the suite's own PASS line, with the T26-T32 rows present in the run"
```

**Why the probe is the suite and not the lint.** The first draft used
`python3 scripts/lint-shell-trace-credential-refusal.py <two paths>` expecting
`OK: 2 scanned file(s)…`. M30 measured a prototype carrying only the lint-required minimum — no
`SENTRY_HOST_CANDIDATES`, no `$api_host` refusal, no flags on `"$CURL_BIN"`, no `unset` prologue, no
`CURL_BIN` adjudication — printing that exact string, exit 0. The lint is a correct **acceptance
criterion** (AC1) and a wrong **discoverability probe**: it cannot see the wrapper (M18), scores
`api_host` adjudicated by a downstream classification, and knows nothing about the prologue or the
binary. The suite is what quantifies over the property. No credential is required: the suite is
stub-driven and touches no network, so `credentials_required` is deliberately absent.

### Soak follow-through

Not applicable. No acceptance criterion is time-gated.

## Encryption Posture

Skipped: no persistent store, no new cross-component connection. This hardens the transport of
connections that already exist, and the Files-to-Edit match none of the gate's detection globs. The
in-transit posture of those existing connections is nonetheless *strengthened* here — `--proto
'=https'` pins the scheme and the `unset` prologue removes the caller's ability to substitute a trust
anchor (M21) — which is recorded in the ADR-202 amendment rather than as a new posture ledger entry.

## Infrastructure (IaC)

Skipped: no server, service, cron, vendor account, DNS record, certificate, secret or firewall rule
is introduced.

**One honest qualification.** `failure_modes[0]`'s remedy is "a repository secret drifted; re-set
`SENTRY_API_HOST` / `SENTRY_ORG`" — a secret change. That is a *recovery* path for a state this PR
does not create (M17 measured the pairing correct today), not a provisioning step, so the gate does
not fire. There is no runbook for it under `knowledge-base/engineering/operations/runbooks/`; the
probe-output dump added to the probe-unavailable issue body is the routing, and a runbook is named in
the Deferrals.

## Acceptance Criteria

### Pre-merge (PR)

1. `python3 scripts/lint-shell-trace-credential-refusal.py scripts/sentry-alert-live-fidelity.sh apps/web-platform/scripts/sentry-monitors-audit.sh` prints `OK: 2 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)` and exits 0. *Necessary, not sufficient — M30.*
2. `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0 **and** names a scanned-file count of at least 2. A bare exit 0 does not satisfy this (M2). No file this branch touches may be an A/B/C-baseline entry lacking the xtrace refusal — `--changed` bypasses that baseline too (M19).
3. `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide, no flags — the **blocking** arm registered in `scripts/test-all.sh`) exits 0 and reports `80 baselined (D)`.
4. `grep -c 'sentry-alert-live-fidelity\|sentry-monitors-audit' scripts/lint-shell-trace-credential-refusal-d.baseline.txt` returns `0` and `grep -vc '^#' …` returns `80`. **This, not AC3, proves the drawdown happened.**
5. `bash -n` clean on both scripts and both suites; `actionlint` clean on the three edited workflows, with any embedded `run:` snippet checked via `bash -c` rather than `bash -n` on the YAML.
6. Region discovery, hermetic: with a `curl` PATH shim answering 200 for exactly one candidate, the recorded probe sequence is a prefix of `SENTRY_HOST_CANDIDATES` ending at that candidate, and every subsequent request targets it. Asserted for **all four** candidates plus the all-fail arm. Assert on the recorded URL log, **not** the exit code (the `sentry.io` and `eu.sentry.io` arms trip the residency detector, which sits after the gates, so Gates 1-4 still produce URLs to assert on). M13 covered candidates 1, 2, 4 and all-fail; M29 covered candidate 3.
7. Hostile environment, audit script: `SENTRY_API_HOST=attacker.tld`, `SENTRY_ORG='@evil.tld/x'` and `CURL_BIN=/tmp/exfil` each cause a refusal with exit 2, **zero** URLs recorded, **and a stderr line matching that refusal's own message anchor** — not merely `rc == 2`, which the file's pre-existing residency `exit 2` also produces for `attacker.tld`. Rows run **non-fixture** via `run_sut_stubbed`. The PR body records the `main` baseline for contrast (M9, M24).
8. Hostile environment, fidelity script: `SENTRY_API_HOST` set to each of `attacker.tld`, `eu.sentry.io`, `de.sentry.io`, `sentry.io`, and `SENTRY_ORG='@evil.tld/x'` — each a refusal with exit 2. Injected **inside** the `doppler run` child (`doppler run … -- env SENTRY_API_HOST=… bash …`); injecting outside does not satisfy this (Sharp Edge 5). Rows use a PATH-shimmed `curl` with `SENTRY_FIXTURE_RULES` **unset** — the fixture short-circuit precedes the host adjudication, so a fixture-mode row asserts nothing about it.
9. Live, fidelity: `doppler run -p soleur -c prd -- bash scripts/sentry-alert-live-fidelity.sh` prints `PASS (all 28 in-scope rules match the committed capture field-for-field)` and exits 0 — **with** the `unset` prologue, `--proto '=https'` and `-g` in place (M25).
10. Environment-confinement, live: the same command with `LOCALDOMAIN=com RES_OPTIONS=ndots:5 SSLKEYLOGFILE=<path>` injected inside the `doppler run` child still passes, and `<path>` is not created (M25).
11. **Production pairing, audit script.** No existing suite row uses `jikigai-eu` / `jikigai-eu.sentry.io`. Two assertions: (a) hermetic must-PASS rows in both suites pinning that pairing; (b) `doppler run -p soleur -c prd -- env SENTRY_FIXTURE_MONITORS=<empty-array fixture> bash apps/web-platform/scripts/sentry-monitors-audit.sh` reaches past all three guards. Fixture mode is required for (b): the 4-gate block contains a live `POST /releases/`.
12. Locale-independence: the org guard refuses a non-ASCII fixture under **both** `LC_ALL=C` and `LC_ALL=en_US.UTF-8`, and accepts a 63-character slug while refusing a 64-character one.
13. `bash scripts/test-all.sh scripts` green, including `tests/scripts/sentry-alert-live-fidelity`, `tests/scripts/sentry-alert-drift-workflow`, `tests/scripts/sentry-monitors-audit-class-d`, the auto-discovered `apps/web-platform/scripts/sentry-monitors-audit.test.sh` (T1, T13, T18a-f, T20b/d/e and T22 in particular), `scripts/lint-shell-trace-credential-refusal` and `scripts/lint-shell-trace-credential-refusal-repo`.
14. `python3 scripts/lint-guard-contract.py` passes on this plan.
15. `bash plugins/soleur/test/c4-count-parity.test.sh` green (this PR edits three workflow files).
16. `ADR-202`'s `## Consequences` carries the Rule D contract and its three residuals, and its `## Decision` is **unchanged**; `ADR-031-sentry-as-iac.md`'s `base_url` glossary line is corrected. `scripts/check-adr-ordinals.sh` green.
17. The PR body carries: the credential-rotation finding (rotate, or why not); `Closes #7997` and `Refs #7898`; the three follow-up issue links; and the M9/M24-vs-AC7 before/after contrast.
18. `#7898` has a comment correcting its §4 "no current offender uses that seam" claim and carrying M18 and M24.

### Post-merge (operator)

None. Every criterion is executable in-session or by CI.

## Test Scenarios

**Numbering.** Measured, `apps/web-platform/scripts/sentry-monitors-audit.test.sh` already assigns
`T00`, `T1`-`T5`, `T8`, `T9`, `T11`-`T25` (highest is **T25**), so the new audit rows continue that
file's own sequence from **T26**. The fidelity suite names its tests by function (`t_*`), not by
number, so the **F** labels below are plan-side identifiers for the new rows rather than in-file ids.
`/work` re-derives the highest existing `T` id before writing — this list is a snapshot, and a
sibling branch can move it.

| # | Scenario | Where | Environment | Asserts |
|---|---|---|---|---|
| T26 | Discovery selects candidate *n* | audit suite | stubbed PATH `curl`, `SENTRY_API_HOST` unset, `SENTRY_AUDIT_TEST_CURL_BIN=1` | probe log is `candidates[0..n]`, then every later URL uses `candidates[n]` — one row per candidate (4 rows) |
| T27 | Discovery exhausts the set | same | same | all four probed in order, then the `not valid against any candidate host` message |
| T28 | Transport prefix at runtime | `mk_curl_stub`, `STUB_REQUIRE_DISABLE=1` | `run_sut_stubbed` | `$1 == --disable && $2 == --noproxy && $3 == '*'` on every stubbed invocation of rows that set the flag |
| T29 | Source-level closure | audit suite | none (static) | every curl-invoking token in both scripts carries the flag prefix; every `https://${…}` host expansion names `api_host`/`candidate`/`SENTRY_API_HOST`; the eight `unset` names precede the first invocation. Site list derived from the file, comments stripped, extractor reuses the lint's boundary shape |
| T30 | Hostile `SENTRY_API_HOST` (audit) | audit suite | **non-fixture** `run_sut_stubbed` | exit 2, zero URLs, **and** the refusal's own message anchor on stderr |
| T31 | Hostile `SENTRY_ORG` (audit) | same | same | table-driven over M15's REFUSE list incl. `$'jikigai\nevil.tld'`; exit 2, zero URLs, message anchor |
| T32 | Hostile `CURL_BIN` (audit) | same | same, without `SENTRY_AUDIT_TEST_CURL_BIN` | `CURL_BIN=/tmp/exfil` → exit 2, zero URLs, message anchor |
| T33 | Production pairing accepted (audit) | same | same | `SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io` reaches past all three guards |
| T34 | Shape boundary | same | none | 63-char slug accepted, 64-char refused; non-ASCII refused under `LC_ALL=C` **and** `en_US.UTF-8` |
| F14 | Hostile + near-miss `SENTRY_API_HOST` (fidelity) | fidelity suite | PATH-shimmed `curl`, `SENTRY_FIXTURE_RULES` **unset** | table-driven over `{attacker.tld, eu.sentry.io, de.sentry.io, sentry.io}` → exit 2, message anchor |
| F15 | Hostile `SENTRY_ORG` (fidelity) | same | same | exit 2, message anchor |
| F16 | Production pairing accepted (fidelity) | same | same | must-PASS |
| F17 | Flags reach the live-fetch path | same | same | `--disable` first, then `--noproxy '*'`, on the `curl -fsS` invocation — which today no test executes |
| F18 | Fixture mode still short-circuits before the host check | fidelity suite | `SENTRY_FIXTURE_RULES` set, `SENTRY_API_HOST` unset | all 13 pre-existing rows still pass |
| T18d | Control arm survives | audit suite | bare stub invocation | `$1 == -s`; the `--disable` assertion is opt-in and must not fire here |

## Risks & Mitigations / Sharp Edges

1. **The done-when command is vacuously green.** `--changed --base origin/main` on a clean branch
   reports `OK: 0 scanned file(s)` and exits 0 (M2). AC2 asserts the scanned count too.
2. **Placement, fidelity script.** `SENTRY_API_HOST` is required *inside* `fetch_rules()`, after the
   `SENTRY_FIXTURE_RULES` short-circuit. A top-level host guard reds all 13 rows of
   `tests/scripts/test-sentry-alert-live-fidelity.sh` and the `W7` row of
   `tests/scripts/test-sentry-alert-drift-workflow.sh` — neither sets it. The same fact makes any
   fixture-mode assertion about that guard vacuous (AC8, F14-F17).
3. **Placement, audit script (T1).** T1 runs under `env -i` and asserts the diagnostic names
   `SENTRY_AUTH_TOKEN`. Its check precedes the `SENTRY_ORG` line, so both the `:?` change and the
   guards below it are safe — verify, don't assume.
4. **Placement, audit script (T18).** T18 slices `curl_retry` out with
   `awk '/^CURL_BIN=/{on=1} on{print} on && /^curl_retry\(\)/{inr=1} inr && /^}/{exit}'` and `source`s
   it under `set -euo pipefail` with no Sentry environment. The slice **already** contains top-level
   statements that run at source time (`AUDIT_SCRATCH="$(mktemp -d)"`, the `trap`, the `CURL_LAST_*`
   assignments), so the constraint is not "no top-level statement" — it is that an added statement
   **must not fail** in that environment. The `CURL_BIN` adjudication *is* inside the slice and *does*
   fail there unless T18 sets `SENTRY_AUDIT_TEST_CURL_BIN=1`; that is a required edit, not an option.
   The org guard above `CURL_BIN=` and the host choke point far below the closing brace are outside
   the slice.
5. **`doppler run` overwrites the inherited environment.** A negative arm written as
   `SENTRY_API_HOST=attacker.tld doppler run … -- bash script` silently passes *because the guard
   never sees the hostile value*. Measured: the first attempt at this reported three green refusals
   that had not fired. Correct form: `doppler run … -- env SENTRY_API_HOST=attacker.tld bash script`.
6. **`exit 2` is already taken in the audit script**, at anchor `ERROR: residency mismatch — probed=`,
   and `attacker.tld` reaches it. So `rc == 2` is **non-discriminating for exactly the mutant Guard 2
   targets**: deleting the membership refusal still yields rc=2 for that input. Every refusal row
   must grep the new message's own anchor (`cq-assert-anchor-not-bare-token`), and
   `reusable-release.yml` renders only `script_rc`, so the message is the only discriminator there
   too.
7. **Refusal messages echo attacker-controlled bytes into a parsed log stream.** Strip control
   characters and bound the length, and **never let the sanitised value be the first token on its own
   line** — pin the shape as a literal prefix then `%s` (`printf 'ERROR: refusing … %s\n' "$(_safe …)"`),
   so one refactor cannot turn a rejected value into `::stop-commands::<token>`. Under `LC_ALL=C`,
   `${1//[[:cntrl:]]/}` does **not** strip U+2028/U+2029/U+0085; that is safe for the Actions parser
   (which splits on `\n`/`\r` only) precisely because of the prefix rule. Use `cut -b`, not `-c`
   (M26).
8. **No `*` in an allowlist arm — and no unquoted comparison RHS.** A shell glob's `*` crosses `/` and
   `?`; M27 measured an unquoted `case` arm accepting `evil.com/?x=.sentry.io`. The extractor anchors
   on `SENTRY_HOST_CANDIDATES=(` and the `case "$SENTRY_API_HOST" in` inside `fetch_rules()`; a
   file-wide sweep would false-fail on the pre-existing residency arm `*.sentry.io)`.
9. **`mk_curl_stub`'s prefix assertion must be opt-in.** T18d invokes the same stub bare as the
   control half of a byte-identity diff, where `$1` is `-s` by design. An unconditional abort empties
   both control values and reds the row that guards the `-w` defect.
10. **`EXPECTED_TESTS` is an exact-equality harness, not a floor.** It reads 13 today and five rows
    are being added; leaving it at 13 reds the suite even when all 18 rows pass.
11. **The lint does not require `$`-free literals in a `case` arm.** `_pin_re`'s `case` branch needs
    only one literal character before the first `)`, so `"${SENTRY_ORG}.sentry.io"` is a valid
    adjudication (M20). Do not "fix" the fidelity arm into a `$`-free literal — that would red
    production.
12. **`LC_ALL=C [[ … ]]` is a parse error.** `[[` is a shell keyword; a prefix assignment makes bash
    look for a command named `[[` (M22). Use `( LC_ALL=C; [[ … ]] )`. Without it the guard admits
    1,162 non-ASCII characters under `en_US.UTF-8` (M23) — weaker on the operator's laptop than in CI,
    which is the wrong direction.
13. **`_safe` must be defined above its first call.** The first draft of this prescription produced
    `_safe: command not found` with the refusal still firing on an empty value.
14. **`{0,62}`, not `{0,63}`.** RFC 1035 §2.3.4 caps a DNS label at **63 octets**; `{0,63}` after a
    mandatory first character is 64, and a 64-character label fails to resolve. Fail-closed, but the
    number and the citation must both be right in a security comment.
15. **T22 confounds two Guard 3 rows.** `T22: assembly — every Sentry call goes through curl_retry`
    counts execution sites with a name-based `CURL_BIN` grep, so it reds on both "add a fifth
    invocation" and "rename `CURL_BIN`". Run those rows with T22 neutralised, or assert which row
    failed.
16. **Fixture mode disables both new guards.** `SENTRY_FIXTURE_MONITORS` skips the entire 4-gate block
    in the audit script and `SENTRY_FIXTURE_RULES` short-circuits before the host adjudication in the
    fidelity script. Every hostile and must-PASS row that asserts about a guard must declare its
    environment; a fixture-mode row is green whether the guard accepts everything, refuses everything,
    or does not exist.
17. **`SENTRY_PROJECT` is deliberately not guarded, and the reason is narrower than it looks.** It
    reaches a URL path (`projects/${SENTRY_ORG}/${SENTRY_PROJECT}/`) and an unescaped JSON body. It
    cannot move the *destination* once the host is adjudicated — measured, curl's brace/range globs
    expand only within the path — but it **can multiply the request**: `SENTRY_PROJECT='[1-100]'`
    fans one Gate-2 call into 100 bearer-carrying requests. `-g` closes that, which is why the flag is
    in the prefix. Full adjudication is Deferral 2.
18. **`--write-baseline-d` is the wrong tool for the drawdown.** It rewrites the whole file from a
    full-tree scan and would absorb any offender that appeared since M3. Delete the two lines by hand.
19. **`ADR-031` is a duplicated ordinal.** Edit `ADR-031-sentry-as-iac.md` by full filename.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Pin `SENTRY_API_HOST` to a single literal in the audit script** | Breaks the discovery loop the done-when protects, and 21 suite rows pass `de.sentry.io`. Tightening to the org-scoped singleton is a follow-up. |
| **Pin `SENTRY_ORG` to a single literal** | Wrong value available: the in-file default is `jikigai`, an org ADR-031 records as canceled; production is `jikigai-eu`. |
| **Delete the region-discovery loop entirely** | Measured dead in production (M6/M7); three of five callers hard-fail without `SENTRY_API_HOST`; the code-simplicity review showed most of the plan's remaining machinery exists to keep it safe. Rejected on the CTO ruling — it reverses the issue's stated done-when inside a security fix. Persisted as an ADR-084 decision-challenge and filed with M6 attached. |
| **Include `us.sentry.io` as a fifth candidate (CTO ruling point 3)** | **Departed from.** Adding it changes the discovery loop's live probe behaviour, and that behaviour is the single thing the done-when pins. The ruling's justification is circular: the region-classification `case` labels whatever host was already reached. `us.sentry.io` remains in ADR-031's API-host row, so a follow-up may add it deliberately. |
| **Widen the lint's recogniser to `"$CURL_BIN"`** | **Measured not to work** (M18) — the `credentialed` predicate reads the invocation's own text while the credential arrives via `"$@"`. It would also cost two xtrace preambles and two A/B/C baseline deletions (M19). Moved to #7898 with both measurements. |
| **A cross-file allowlist parity assertion** | Would force the fidelity script — single, org-scoped endpoint — to admit `eu.sentry.io`, which ADR-031 and the 2026-05-17 learning both record as hijacking `-eu` slugs. M25 measured the singleton refusing it, which is the intended behaviour. |
| **Merge Guard 1 into Guard 2 (code-simplicity recommendation)** | **Departed from.** Their assemblies are genuinely different — a variable's *lifetime* after a `readonly` versus a set of *destination* chokepoints — and Guard 2's mutation row 4 ("delete Guard 1 while keeping Guard 2") only exists because they are separable. |
| **A standalone ADR for the Rule D contract** | Cut: recorded under ADR-202's `## Consequences` and an ADR-031 glossary correction. Avoids an ordinal claim (216 was free across all 80 `origin/*` refs at plan time, but ordinals have collided twice in one session in this repo). |
| **Putting the Rule D contract in ADR-202's `## Decision`** | Would distort it: that Decision is a fork criterion about runtime-STATE hazards, it pins exit 78 while Rule D uses 2, and its Alternatives explicitly cut CI `run:` bodies — where the `sentry-audit-gate.yml` residual lives. |
| **A `_org_ok "$1"` helper shared by both scripts** | Measured to leave the lint red in **both** files (M28). |
| **Keeping the lint as the `discoverability_test`** | M30: a prototype with the whole destination-adjudication layer absent prints its exact expected output. |

## Deferrals — tracking issues to file in `/work` Phase 7

1. **Delete or gate the Sentry region-discovery loop.** Body carries M6/M7, the six invocation sites
   (three fail loud without `SENTRY_API_HOST`), and the accepted cost that the loop's guard is
   stub-exercised only, permanently. Re-evaluation trigger: a personal Sentry token enters the repo's
   credential set, or Sentry changes `/users/me/` scoping. Also carries: whether to add `us.sentry.io`
   deliberately, and whether to tighten the audit script's org-scoped chokepoint to the singleton (a
   `sed` over 21 test literals). Labels: `type/chore`, `domain/engineering`, `priority/p3-low`.
2. **Adjudicate `SENTRY_ORG` against the org id Gate 1 returns**, closing the parameterised-set
   residual, and adjudicate `SENTRY_PROJECT` (URL path plus an unescaped JSON body plus the `-g`
   fan-out `-g` currently mitigates). Labels: `type/security`, `domain/engineering`, `priority/p3-low`.
3. **Route a `sentry-audit-gate.yml` failure to a human, and adjudicate its inline `curl`
   destination.** That workflow files no issue and is absent from `scripts/required-checks.txt`. This
   PR confines its transport only; the destination pin needs the YAML scope gap (#7898 §3). Also:
   write the secret-pairing recovery runbook. Labels: `type/chore`, `domain/engineering`,
   `priority/p3-low`.

**Comment, not a new issue, on `#7898`:** correct its §4 claim that no current offender uses the
`CURL_BIN` seam; attach M9, M18 and M24. Note that #7898's census says 67 files while the D baseline
holds 82 — a one-line check for whoever picks it up, not an assertion of drift.

**Not filed here, pre-existing, surfaced by the compliance gate:** Sentry (Functional Software GmbH)
has an Art. 30 Vendor Mapping row but **no row** in
`knowledge-base/legal/compliance-posture.md` §Vendor DPA Status — the table the published privacy
policy points at as canonical. Same class as the Better Stack (#7529) and Proton (#7845) gaps.

**Milestone note for `/ship`:** #7997 sits on milestone "Post-MVP / Later" while this plan declares
`single-user incident`. Re-milestone it or re-label `type/security`.

## Domain Review

**Domains relevant:** Engineering, Product (threshold sign-off only), Legal (compliance gate)

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Ruled on the region-discovery fork with the full record, including the facts
disqualifying the proposing option. (1) keep the loop and pin the set, filing deletion separately —
**adopted**; (2) no drift guard, collapse the two host lists into one array — **adopted**; (3) include
`us.sentry.io` — **departed from**, see Alternatives; (4) fix the property rather than the lint's
field of view — **adopted in the fallback form the ruling itself provided**, on M18; (5) no new ADR,
amend ADR-202 and ADR-031 — **adopted with a correction from architecture review**: under ADR-202's
`## Consequences`, not its `## Decision`.

### Product (CPO)

**Status:** reviewed — **APPROVED WITH CONDITIONS**

**Assessment:** Threshold `single-user incident` confirmed on the write-capability ground.
**C1/C2** (a refusal must reach the operator; the alert route is false) — **checked and partly
refuted**: the drift workflow already has a filer a non-zero exit reaches, so no new arm is needed;
but the observability reviewer then found the issue *body* never dumps the probe output, so the
routing carries no cause. This PR fixes that instead of adding a static checklist item. **C3**
(rewrite User-Brand Impact) — **adopted**. **C4** (credential rotation) — **adopted** as AC17.
**C5** (#7898 overlap) — **adopted**: `Refs #7898` plus a correction comment. **C6** (the refusal
message is its own route out) — **adopted** into Sharp Edge 7. Milestone contradiction recorded.

### Legal / compliance (gdpr-gate)

**Status:** reviewed — **PASS (advisory), zero Critical findings**

**Assessment:** 12 candidate paths adjudicated against the canonical path globs, 0 matched; the gate
fired on the threshold declaration alone. All five mandatory v1 checks not triggered (no schema
artifact). One Important-grade Chapter-V observation: two members of the *original* five-member set
(`us.sentry.io`, `sentry.io`) are US endpoints the Art. 30 PA-8 DE-region record does not contemplate
— mitigated by measurement (no repo credential can reach them) and, since review, by dropping
`us.sentry.io`. No edit to `article-30-register.md` or `compliance-posture.md` is required to ship;
the optional PA-8 §(g) note is at `/work`'s discretion. The gate's own corpus-freshness
`POSTURE_FAIL` (123 days) does not gate this PR; note that the issue `compliance-posture.md` cites
for it, **#7710, is CLOSED** while the banner still fires — worth one line to whoever owns the corpus
attestation, not a task here.

> **This is not legal review. Findings are heuristic. Consult `clo` +
> `legal-compliance-auditor` before merging.**

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire: no path in Files to Edit or Files to
Create matches any UI-surface term or glob.

### Other domains

Finance, Marketing, Sales, Support and Operations assessed not relevant.

### Panels run

**Plan review (escalated set for `single-user incident`):** `kieran-rails-reviewer`,
`code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, plus `cto`, `cpo` and
the compliance gate. **`dhh-rails-reviewer` was not spawned**, recorded rather than silent: its lens
(over-engineering, "is this bigger than the defect?") was given verbatim to
`code-simplicity-reviewer` as its scoping question, and that review returned the largest set of cuts
— the lint-widening cut, the cross-file parity cut, and the inline fix of the `SENTRY_ORG` default all
originate there.

**Deepen pass:** `security-sentinel` (found the resolver/trust-anchor gap M21, the locale dependence
M23, the unquoted-RHS glob M27, the `{0,63}` off-by-one, and corrected the residual's blast radius),
`test-design-reviewer` (found the `CURL_BIN` gap M24, the `rc == 2` collision, the fixture-mode
vacuity class, and the T22 confound; scored the first draft 7.4/10), `observability-coverage-reviewer`
(found M30, the un-dumped issue body, the missing layer citations, and the post-apply fidelity call
site), plus a verify-the-negative / post-edit self-audit sweep (11 negative claims confirmed against
the code; found the T-number collision, the missing M2 in `tasks.md` Phase 0, and the Files-to-Edit
count).

**Step 4.5 scoped advisor consult:** satisfied by the `cto` consult, spawned at the plan's single
highest-leverage decision point with a curated payload that included the facts disqualifying the
proposing option.
