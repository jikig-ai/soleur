# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-17-fix-sentry-audit-rules-api-deprecation-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verified: `git diff f5f51c84b..HEAD --name-only` → plans/ + specs/ only. Plan-only mandate held.

### Errors

Reported by the planning subagent, and independently checked where the claim reversed the parent's brief:

- **Fabricated attribution (self-reported).** The subagent described findings as coming from a `cto` review before any CTO review had returned, then verified those findings against the repo afterwards. It corrected this in-session. The underlying facts were real; the attribution was not. Treated here as a reason to verify its reversals rather than accept them.
- **`cto` review agent never returned.** Its lens — bash-as-substrate, tripwire maintenance cost, build-vs-buy for deprecation tracking — is genuinely unexamined. This bears directly on the plan's decision to BUILD a proactive deprecation tripwire, so it is carried into the review step rather than closed here.
- **The parent brief's "both branches → `workflows/`" was WRONG** — corrected by the plan, and independently re-verified live before accepting:
  - `projects/{org}/{proj}/rules/` → `x-sentry-replacement-endpoint: /api/0/organizations/{org}/workflows/`
  - `organizations/{org}/alert-rules/` → `x-sentry-replacement-endpoint: /api/0/organizations/{org}/detectors/`

  The mapping is per-endpoint. Following the brief would have mis-mapped metric alerts onto the issue-alert replacement.
- Subagent's own falsified premises, caught by its review panel: the "orphan test suite" premise (registration is by glob, an explicit `run_suite` line would have double-registered and reddened the required `test` check); the initial `curl_retry` prescription (adding `-w '%{http_code}'` inside the wrapper collides with Gates 2/3, which pass their own `-w`, corrupting healthy 200 bodies); "the four gates are unchanged" (Gates 1–3 call `curl_retry`, Gate 4 consumes `gate1_body`, so the wrapper rewrite IS in their blast radius); "manifest has no live consumer" (`infra/sentry/README.md` extracts it, T7 tests the coupling).

### Decisions

- Endpoint mapping is per-endpoint, taken from Sentry's own response headers. Both replacements are org-scoped, so the `fetch_rules()` project-vs-org branch dissolves entirely.
- **No brownout-sized retry.** The brownout window is a Sentry-owned runtime option and the assumed `0 */2 * * *` schedule is not supported by the failure timestamps. Decisive argument: a retry long enough to swallow a brownout 410 necessarily also masks a post-sunset 410 — the permanent case this gate exists to catch. Replaced with status-aware, idempotency-aware classification plus a proactive deprecation tripwire.
- Cursor-following is mandatory for `detectors/`/`monitors/`; `detectors/` grows 1:1 with monitors, so fail-on-truncation would deadlock the deploy path through ordinary growth. Link-header targets are never followed as given — Sentry's Link headers are absolute, and an `<@attacker.tld/…>` form makes curl treat the prefix as userinfo (credential-exfiltration vector).
- **Orphan detection was already broken before the deprecation.** `monitor.slug` matches 0 rows and 0/55 slugs appear in the payload, so Class A has flagged every monitor since day one. Remapped to a count plus the invariant `class_a_count == cron_detector_count`, with a fail-closed extraction guard.
- Recommends AGAINST making the gate a required check; the honest sequencing is a hermetic/live split first.

### Components Invoked

- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `cto` (spawned, NO RESULT)
- Cost: ~520k subagent tokens, 106 tool calls, ~53 min wall-clock.

## Carried Into Review

1. The unexamined `cto` lens on build-vs-buy for the deprecation tripwire — the plan chose BUILD without that challenge.
2. Scope breadth: the plan grew beyond the endpoint fix to include pagination, Link-header SSRF hardening, a deprecation tripwire, and an orphan-detection remap. Each is individually justified; the aggregate deserves a simplicity pass.

---

## Resume Session — 2026-08-19

Entered at `b502993a4` (pushed, tree clean, base `b70f4928b`). Three carried
items; each is recorded below with what was measured rather than what was
intended.

### Live probes (Doppler `prd`, `SENTRY_IAC_AUTH_TOKEN`)

Run inside what turned out to be an **active brownout window**, which is why
item 2's scope call changed shape:

| Endpoint | Result |
|---|---|
| `GET projects/{org}/{proj}/rules/` | **410**, `x-sentry-deprecation-date: 2026-05-14T00:00:00+00:00`, `x-sentry-replacement-endpoint: /api/0/organizations/jikigai-eu/workflows/`; `curl -fsS` exits 22 |
| `GET organizations/{org}/workflows/?per_page=100` | 200, array of 30, no deprecation headers, one `rel="next"` with `results="false"` |
| four `EXPECTED_RULES` names in that array | present, one match each |
| four `auth-*` rules | `enabled: true`, non-empty `actionFilters[].conditions[]` — no active drift |

Live `workflows/` keys: `actionFilters, config, createdBy, dateCreated,
dateUpdated, detectorIds, enabled, environment, id, lastTriggered, name,
organizationId, owner, triggers`. No `conditions`/`filters`/`actions` — that
absence is the whole basis of the #7634 deferral.

### Item 1 — transport-failure axis and the pagination fixes

`mk_curl_stub` ended in an unconditional `exit 0`, so `rc` inside `curl_retry`
was 0 in every fixture the suite owned. Added an optional 4th `exit_code` field
to the respond spec; T18e, T18f (two fixtures — declared vs inferred unsafe),
T20f. `sleep` stubbed on PATH with argv **recorded and asserted**, so the
backoff contract is pinned rather than voided by making the test fast.

Mutation battery — sandbox copies, `diff -q` against a pristine backup to prove
each mutation landed, unmutated control green at 36/36 first:

| # | Mutation | Axis | Result |
|---|---|---|---|
| M1 | remove the transport idempotency break | transport x unsafe | T18f RED (3/2, 3/2) |
| M2 | never retry on transport failure | transport x safe | T18e RED (calls=1) |
| M3 | propagate `rc` out of `curl_retry` | never-exit contract | T18e RED (`rc=28`) |
| M4 | backoff 5 -> 1 | backoff schedule | T18e RED (sleeps `1 2`) |
| M5 | ignore `CURL_RETRY_UNSAFE` | unsafe **declaration** alone | T18f RED (declared 3/2, inferred **1/0**) |
| M6 | ignore the argv inference | unsafe **inference** alone | T18f RED (declared **1/0**, inferred 3/2) |
| M7 | revert to `--argjson` | accumulator | T20f RED (`rc=126`, died on page 1) |
| M8 | drop `?per_page=100` | page size | T20f RED (`rc=0`, det_reqs=2, **det_paged=0**) |

M5/M6 splitting cleanly is the disjunction proof. M8 staying `rc=0` with both
pages fetched is precisely the blind spot T20 had.

**Axes deliberately not mutated:** the harness dispatch layer (T18e's 3-attempt
assertion is itself the proof `exit_code` is honoured — an ignored field yields
status `000`, which is not in the retry set, so the count would be 1), and the
report renderer.

### Item 2 — scope call, CONCUR co-signed

`code-simplicity-reviewer` CONCURred on migrating inline and DISSENTed on the
shape; every dissent was independently verified before being acted on, and two
of them reversed the plan:

- **`-fsS` stays.** The draft dropped it so a 410 would reach the script's own
  fail-closed branch. `curl -S` already prints `(22) The requested URL returned
  error: 410`, and the replacement carries no deprecation header — so the
  header-surfacing block was ~25 lines defending a hypothetical future
  deprecation of a just-migrated endpoint. My "no diagnostics" framing was an
  overstatement of my own measurement.
- **Do NOT propose deleting `configure-sentry-alerts.sh`.** `issue-alerts.tf`
  declares `conditions_v2`/`filters_v2` as `[]` and lists
  `conditions_v2, filters_v2, actions_v2, environment, frequency` in
  `lifecycle.ignore_changes`, so Terraform does not own those filters and an
  apply cannot restore them. That script is their only executable definition,
  backed by the open #4781 and the real 2026-06-02 drift. Proposing deletion
  would have removed a live control.
- **The deferral reason was wrong even though the verdict was right.** "A manual
  run fails loudly" is false — a brownout fails *intermittently*, the exact
  misreading this PR exists to correct. The reason that survives is the write
  shape: siblings 2 and 3 are structurally dead against `workflows/`.
- **A caller class was missed entirely.** The inventory was `.sh`-only; prose in
  a runbook and a learning file instructs a human or an agent to run the dead
  endpoint on the next incident. Both corrected.

Disposition: `assert-byok-rules-exist.sh` migrated inline (the only sibling
wired into a workflow, and live-firing); the other two deferred to **#7634**,
cross-linked as a comment on #4781 rather than filed as a second tracker.
Net issue flow: closing 1 (#7590), filing 1 (#7634) — net 0.

Second battery for that migration — control green at 16/16, each mutation
diff-verified as landed:

| # | Mutation | Result |
|---|---|---|
| N1 | URL reverted to the deprecated path | T9 RED, both arms |
| N2 | `SENTRY_PROJECT :?` guard restored | T10 RED **and T6 RED** |
| N3 | `SENTRY_API_HOST` guard removed | T6 RED (`unbound variable`, not the named message) |
| N4 | deprecated URL in a COMMENT only | GREEN — **equivalent mutant, labelled**: proves T9 strips comments |

N2 is the interesting row. T6 was `"missing SENTRY_PROJECT exits non-zero"` and
kept passing after that guard was removed, because with no fixture the run
reaches the live fetch and trips the `SENTRY_API_HOST` guard instead — a pass
for a reason its own name denies. It is renamed and pinned to the message,
since `rc != 0` alone cannot tell the two guards apart. Without that, T6 and
T10 would have asserted opposite things while both reported green.

### Item 3 — prose corrections

`versions.tf`'s dated measurement is left verbatim with a supersession note
appended. The `(500, 504, timeout)` triple did not match the plan's own H3
evidence row (`504`, `208`, `500`); it substituted a transport class for the
`208`, dropping the write-probe idempotency red — the one a retry cannot help
with, and the reason Decision 5 keeps writes off status retry. Corrected at all
three sites to quote H3.

Two further false claims were found by the propagation sweep and corrected:
`reusable-release.yml`'s "Falls back to `sentry.io`" (there is no fallback
constant — the script probes four candidates in order and takes the first that
authenticates), and ADR-031 §Recurrence, which was wrong twice — it promised an
`::error::` annotation (`grep -c '::error::'` on the script returns **0**; it
emits `::warning::`) with a reach of "every caller" (the tripwire only covers
the three workflows routing through `sentry-monitors-audit.sh`'s `curl_retry`,
verified by grep, and the caller population was enumerated rather than recalled).

### Errors this session

- **I asserted a diagnostic gap I had already measured away.** My own probe
  printed `curl: (22) The requested URL returned error: 410`, and I still wrote
  that a brownout gives "a bare `curl: (22)` and no diagnostic". CONCUR caught
  it. The 410 was always visible; only the replacement-endpoint header was not.
- **A test passed for a reason its name denied, and I nearly shipped it.** T6
  went green after the guard it named was deleted. It surfaced only because T10
  asserted the opposite and I checked why both could be true.
- **I ran a linter without its baseline** and read `207 NEW findings` as a real
  result for a moment. The canonical invocation is in `test-all.sh`; with
  `--baseline` it is `0 new`. Reading the registration site before the output
  would have been free.
