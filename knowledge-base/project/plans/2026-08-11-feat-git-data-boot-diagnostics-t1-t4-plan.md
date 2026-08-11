---
title: "feat: git-data boot-diagnostics — template strip, slice non-vacuity, Sentry second channel"
date: 2026-08-11
slug: feat-git-data-boot-diagnostics-t1-t4
branch: feat-one-shot-7264-git-data-boot-diagnostics-t1-t4
issue: 7264
closes: [7116]
lane: cross-domain
type: feat
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: git-data boot-diagnostics — T-2, T-3, T-1 (T-4 deferred to a follow-up PR)

> **Revision 3.** Six reviewers (DHH, Kieran, code-simplicity, architecture-strategist,
> spec-flow-analyzer, CTO) materially changed this plan, and the operator ruled on the three
> User-Challenges they raised
> ([`decision-challenges.md`](../specs/feat-one-shot-7264-git-data-boot-diagnostics-t1-t4/decision-challenges.md)
> — all RESOLVED).
>
> **This PR is T-2 + T-3 + T-1. T-4 (baking the Better Stack ingest token) is deferred to its
> own PR** per the operator's ruling on UC-C. Consequently this PR carries **no new ADR
> ordinal** — only an ADR-152 addendum.

## Overview

Three changes to the git-data boot-diagnostics surface.

**T-2** ports an already-proven render-time comment strip to git-data's cloud-init template,
recovering ~17.8 kB of the Hetzner 32,768 B `user_data` cap. **T-3** closes a narrow
vacuity hole in the rehearsal's runcmd slice. **T-1** gives the rung-2 evidence-capture script
a Sentry query arm so parent-shell boot fatals report `FAIL` instead of `TRANSIENT` — closing
#7116.

UC-1 is a recorded process decision, not a build item, and is out of scope by construction.

### Scope ruling and its consequence for T-1

The operator split T-4 into a follow-up PR. That **changes T-1's role for the better**: with
T-4 absent, the five parent-shell stages (`gitdata_runcmd_early`, `sshd_config`,
`volume_mount`, `gitdata_doppler_dl`, `gc_timer`) still reach **Sentry only**, because the
emitter's Better Stack block is gated on `BETTERSTACK_LOGS_TOKEN`, present only under
`doppler run`. So in this PR T-1 is the **primary** fix for #7116, not a redundant second
implementation. Once T-4 lands, T-1 becomes the second channel for the case T-4 cannot cover
(Better Stack itself unreachable). Both placements are required, and both are specified below.

## Research Reconciliation — Spec vs. Codebase

| Claim as given | Measured reality (2026-08-11) | Plan response |
|---|---|---|
| T-2 hazard survey "came back clean — one `#!` at the emitter shebang" | **The survey was wrong, and the repo already knew.** `cloud-init-git-data.yml:1` is `#cloud-config`, which the payload expression deletes — proven (`substr(naive,0,14)` → `"package_update"`). ADR-152 §"The expression is deliberately not shared" names this hazard verbatim, including the dark-host failure mode. | Treat T-2 as **porting a proven pattern**, not inventing a guard. |
| Recovery ~14,124 B; raw 37,363 B; comments 24,340 B | Raw **46,894 B**; strip-matching lines **30,710 B** / 372 lines. Stored **30,376 → 12,588 B** = **17,788 B** recovered; headroom 2,392 → **20,180 B**. | Measured figures throughout. |
| Byte budget stored=30376 / cap=32768 / headroom 2392 | **Confirmed exactly.** | — |
| T-2 needs a tightened *shared* expression | **Wrong — it reverses ADR-152**, which rules the expression "deliberately not shared, and must not be… Do not port an expression between these two cases," with a two-row table (injected scripts preserve `#!` only; a cloud-init template preserves `#!` **and** any `#`-directive). `zot-registry.tf:405` already defines `registry_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/"`, and `:520`/`:563` already wrap `templatefile()` in `replace(...)`. | Add a **second, separate** local. Leave `git_data_rationale_strip` byte-unchanged. |
| T-3 replaces "the THIRD re-implementation… source it from both suites" | **Not buildable as specified.** `git-data-runcmd-rehearsal.test.sh:105-123` is inside a `python3 <<PY … PY` heredoc (terminator `:124`); those sites are Python comprehensions over in-memory `d["runcmd"]`. Only `_luks_slice` (4 lines) is bash. | **UC-A resolved:** narrow to the real defect — the missing non-vacuity assert. No library. |
| T-1 blocker is "tooling shape" | Search works: `SENTRY_ISSUE_RO_TOKEN` `[event:read, org:read]` → **200** on `issues/?query=`, `host_name:`, `stage:` (live-verified). `/rules/` → 404. Already recorded at `git-data-rung2-evidence-capture.sh:45-52` (#7204), which says "#7116 owns that work". | Build on tag-scoped issue search — **but the token is in the wrong config; see below.** |
| T-1 is straightforward once the API is known | **Dead read as specified.** The workflow invokes the capture script under `doppler run -p soleur -c prd_terraform` (`git-data-rung2-rehearsal.yml:317`), but `SENTRY_ISSUE_RO_TOKEN` lives in `soleur/prd` (`scripts/sentry-issue.sh:11`). The variable would be **unset at runtime**. | Phase 0 verifies and provisions; AC covers it. |
| ADR ordinal = max(existing)+1 | `origin/main` maxes at 176; across all 36 origin refs **177 and 178 are already claimed** by pushed branches. | Moot for this PR — no new ordinal. Applies to the T-4 follow-up. |

Facts that constrain the build:

- **`main.tf` is inside the rung-2 evidence hash** (`git-data-birth-readiness-gate.sh` hashes
  the module's `.tf` files "because it holds the strip expression"). T-2 invalidates prior
  attestations — free today, because the evidence file is absent and the gate HOLDs
  fail-closed. `_payload_refs` excludes `templatefile(` by its `[^A-Za-z]` prefix guard, so
  wrapping the render does not perturb extraction. Residual: an **ordering prerequisite for
  #6977** — the first birth must dispatch the rung-2 rehearsal *after* this merge.
- **B1 does not strip comments.** `git-data-runcmd-rehearsal.test.sh:212` is a bare `re.search`
  over raw `main.tf` taking the **first** match, so a documenting comment naming an old
  expression is extracted instead of the live one — and its probe passes either way (wrong
  stripper, green suite). The parity extractor *does* strip comments
  (`git-data-render-strip-parity.test.sh:64`). **Write no `# was: …` comment naming an
  expression**, and harden B1 in this PR.
- **`user_data` is ForceNew with no `ignore_changes`** (`git-data.tf:376-394`) — the intended
  reprovision path. Inert today (#6977).
- **`validate-infra-templates.sh` will validate the wrong document.** It renders
  `jsonencode(templatefile(…))` (`:558`) — the bare templatefile — and runs
  `cloud-init schema -c` on it (`:301`). After T-2 the strip wraps the render, so the only
  schema-validating gate would validate an un-stripped document that will never boot a host.

## User-Brand Impact

**If this lands broken, the user experiences:** a git-data host that boots dark — cloud-init
declines a payload whose `#cloud-config` header was stripped, so no LUKS volume opens and
every connected user's repository is unreachable, with no error on any channel.

**If this leaks, the user's source code is exposed via:** unchanged by this PR. `user_data`
already carries a Doppler service token and a semi-public Sentry DSN; T-2 removes bytes and
adds no credential. (T-4's added credential moves to the follow-up PR with its own posture.)

**Brand-survival threshold:** single-user incident

## Research Insights

### The mechanism vs. the ADR corpus

ADR-152 anticipated this work. Its §"The generalizable rule, for the next host":

| What is being stripped | Safe expression | Why |
|---|---|---|
| Injected scripts, cloud-init NOT stripped (git-data) | preserve `#!` only | scripts have no `#`-directive but a shebang |
| The cloud-init template itself (registry) | preserve `#!` **and** any `#`-directive without a separator | `#cloud-config` is load-bearing and is a comment by syntax |

T-2 moves git-data from row 1 to **both** rows: payloads keep the `#!`-only expression; the
template gets the directive-preserving one. That is ADR-152's documented plan for "the next
host", executed — not a new decision, which is why this is an addendum and not a new ADR.
ADR-152 also prescribes the verification triad: **assert the first line survives, assert every
shebang survives, and assert the strip is not a no-op** (a strip matching nothing satisfies
both preservation checks while doing nothing).

### Measured strip behaviour

Measured with terraform's own `base64gzip` in a scratch dir replicating
`git-data-userdata-budget.sh` (reproduces the committed 30,376 B baseline exactly).

| variant | rendered | stored | headroom |
|---|---|---|---|
| baseline | 67,286 | 30,376 | 2,392 |
| payload expr applied to the render | 36,748 | 12,580 | **deletes `#cloud-config`** |
| directive-preserving expr | 36,762 | **12,588** | **20,180** |

Structural check: the stripped render parses via `yaml.safe_load` with identical top-level
keys, identical counts (`runcmd` 14=14, `bootcmd` 1=1, `write_files` 12=12), identical `STAGE=`
coverage (8 markers; `boot_complete` carries no `STAGE=` literal — 9 stages total), and begins
with `#cloud-config`.

**That structural check is a proxy, not the invariant** (architecture-strategist P0-2, Kieran
P1-4): key sets and counts are invariant under corruption *inside* a `write_files` content
string or the `LUKSEOF` heredoc body (`cloud-init-git-data.yml:536`). The invariant to assert
is per-entry: stripped and unstripped differ **only** by lines matching the strip regex.

Regex edge cases, confirmed by execution: bare `#\n` and `#   \n` strip; `#`-at-EOF unchanged;
`#!` survives; `#cloud-config` and any `#nospace` line survive. Only `#\r\n` under-strips (safe
direction; zero CRLF in the template or the nine payloads). Corpus: **zero** `#nospace` lines
across all nine payloads, exactly **one** in the template (line 1).

### Interpolation-site safety (architecture-strategist P0-1)

Post-T-2 the strip runs over rendered output containing apply-time secret values
(`doppler_token`, `sentry_dsn`, `betterstack_ingest_url`), all `sensitive`, so a mangled render
is invisible in plan output. Today every `${…}` site is mid-line, so the `^[ \t]*` anchor
cannot reach them — a property of the current template text, not an invariant. It must become
a committed assertion.

### Institutional learnings

- `2026-08-09-my-suites-were-hermetic-…-dead-read` — cited by this plan and then **reproduced
  twice**: the schema gate validating the un-stripped document, and the Sentry token in the
  wrong Doppler config. Both fixed below.
- `2026-07-26-cloud-init-comment-is-a-live-host-input…` — the whole byte content is ForceNew.
- `2026-07-14-cloud-init-templatefile-escaping…` — three stacked parsers; verify via
  `terraform console`.
- `cq-assert-anchor-not-bare-token` — the Sentry arm anchors on field shape (`"id":"…"`).
- `2026-05-16-adr-amendment-required-when-reversing…` — amend the ADR you correct, in the PR.

## Open Code-Review Overlap

None. No open `code-review`-labelled issue names any file in this plan's edit set.

## Architecture Decision (ADR/C4)

### ADR

**One addendum, no new ordinal.**

- **ADR-152 addendum** — records that git-data's template now *is* stripped, using the
  registry's directive-preserving expression, per ADR-152's own "next host" rule. Corrects
  ADR-152's standing statement that git-data's cloud-init is not stripped, and carries the
  measured bytes. This is execution of a documented decision, not a new one.

ADR-180 (baked-credential channel split) and the ADR-147 addendum move to the **T-4 follow-up
PR**, where the decision they record actually happens.

### C4 views

Checked `model.c4`, `views.c4`, `spec.c4` for external actors, external systems, containers and
access relationships. Better Stack and Sentry are already modelled as the two sinks; this PR
changes neither topology nor credential provenance (T-4 does, in the follow-up). No new human
actor, no new store, no owner/tenancy boundary move. **No C4 edit required.**

## Infrastructure (IaC)

### Terraform changes

- `modules/git-data-userdata/main.tf` — add `git_data_template_rationale_strip` (a **second**
  local, mirroring `zot-registry.tf:405`); wrap the render in `replace(...)` mirroring
  `zot-registry.tf:520`/`:563`; correct the stale "cloud-init-git-data.yml itself is NOT
  stripped" comment. **Leave `git_data_rationale_strip` byte-unchanged.**
- `git-data-userdata-budget.sh` — mirror the new local; emit `stripped_bytes` (the registry has
  this at `registry-userdata-budget.test.sh:78`; git-data lacks it) so the not-a-no-op arm has
  an input; emit both stripped and unstripped renders.
- `git-data-render-strip-parity.test.sh` — extend to compare the **second** expression too.
- `.github/scripts/validate-infra-templates.sh` — apply the template strip when the discovered
  call site wraps the render, so the schema gate validates the document that will actually boot.

No new Terraform **variable** in this PR, so no `TF_VAR_*` provisioning is required and the
merge cannot wedge the infra root on an unresolved variable. (That risk belongs to the T-4
follow-up.)

### Apply path

Cloud-init only; git-data has no bake path (ADR-147). `user_data` is ForceNew, so the change
takes effect at the next birth. No host is replaced by this PR — no birth route exists (#6977).

### Distinctness / drift safeguards

`dev != prd` unaffected. Both roots call the one shared module, so the two cannot diverge.

### Vendor-tier reality check

No new vendor resource.

## Encryption Posture

### at_rest

- **`user_data` / `terraform.tfstate`** — mechanism: provider-side encryption on the R2 state
  backend. **Defends against:** at-rest disclosure of the state object. **Does not defend
  against:** a reader of instance metadata or state, who obtains the pre-existing Doppler
  service token. **Unchanged by this PR** — T-2 removes bytes and adds no credential.
  Live verification: the `discoverability_test` below.

### in_transit

- **host → Better Stack ingest** — tls yes (`https://`), cert_verification on. Unchanged.
- **host → Sentry** — tls yes, cert_verification on. Unchanged.
- **capture script → Sentry API** — tls yes, cert_verification on; read-only token.

### exception

None.

## Observability

```yaml
liveness_signal:
  what: boot-stage markers on Better Stack source 2457081, tagged host_name + stage
  cadence: per boot, nine stages
  alert_target: rung-2 evidence capture
  configured_in: apps/web-platform/infra/cloud-init-git-data.yml (emitter)
error_reporting:
  destination: Sentry (baked DSN, all stages) + Better Stack (post-doppler stages only)
  fail_loud: yes — runcmd trap emits level=fatal with an rc guard at all three arming sites
failure_modes:
  - mode: strip deletes a cloud-init directive, host boots dark
    detection: first-line assertion + per-entry byte diff + cloud-init schema on the STRIPPED render
    alert_route: infra-validation CI
  - mode: strip silently becomes a no-op (matches nothing)
    detection: budget script emits stripped_bytes; assert > 0
    alert_route: infra-validation CI
  - mode: template strip expression drifts from its budget-script mirror
    detection: git-data-render-strip-parity.test.sh, extended to the second expression
    alert_route: infra-validation CI
  - mode: runcmd slice silently empty, four rehearsal arms pass vacuously
    detection: non-vacuity assert on runcmd-all.code.sh (mirrors luks-stage.code.sh)
    alert_route: infra-validation CI
  - mode: Sentry query arm fails (401/429/network) and reads as "no fatal"
    detection: explicit rc + HTTP-status check; non-200 => TRANSIENT with a no-verdict line
    alert_route: capture-script verdict
discoverability_test:
  command: bash apps/web-platform/infra/git-data-userdata-budget.sh
  expected_output: "git-data user_data: stored=<N> B / cap=32768 B" with N < 32768 and exit 0
```

## Implementation Phases

### Phase 0 — Trapdoor check (before any code)

Verify `SENTRY_ISSUE_RO_TOKEN` resolves under the config the rung-2 workflow actually uses:
`doppler run -p soleur -c prd_terraform` (`git-data-rung2-rehearsal.yml:317`). It currently
lives in `soleur/prd`. If absent, **T-1 is a dead read** — provision it into `prd_terraform`
before writing the arm.

### Phase 1 — T-2: strip the cloud-init template (ported, not invented)

1. RED: assert the rendered output starts with `#cloud-config`; assert every shebang survives;
   assert `stripped_bytes > 0`. Confirm each fails against the payload expression.
2. Add `git_data_template_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/"` as a **second**
   local, mirroring `zot-registry.tf:405`. **Leave `git_data_rationale_strip` untouched.**
3. Wrap the render: `replace(templatefile(…), local.git_data_template_rationale_strip, "")`,
   mirroring `zot-registry.tf:520`/`:563`. Both invariants hold: no brace in the literal, and
   every map entry stays on one physical line.
4. Mirror the new local in `git-data-userdata-budget.sh`; extend the parity test to it; emit
   `stripped_bytes`; emit both stripped and unstripped renders.
5. Harden B1's extractor (`rehearsal:212`) to skip comment lines. Write **no** `# was: …`
   comment naming an expression until that lands.
6. Fix `validate-infra-templates.sh` so the schema gate validates the **stripped** render.
7. Add the per-entry byte-diff assertion and the interpolation-site assertion (every `${…}` is
   preceded on its line by a non-newline character).
8. Keep at least one rehearsal arm reading the **unstripped** render so R1 (`:757`,`:762`),
   B2 (`:442`) and S1 (`:669`) do not degenerate into tautologies once the render is
   comment-free.
9. Update the stale `main.tf` comment and write the ADR-152 addendum.
10. Green: budget, parity, `validate-infra-templates.sh`, luks (≥133), runcmd rehearsal (≥44,
    **detached, poll an rc file**).

### Phase 2 — T-3: close the vacuity hole

Add the mirrored non-vacuity assert to `runcmd-all.code.sh` (`rehearsal:122-123`), matching
`luks-stage.code.sh`'s `assert "mkfs.ext4" in _code`, so its four arms (R3(3b), R3(3c), R3(3d),
R3(2d)) cannot pass on an empty slice. Pick a sentinel that is present in the concatenated
runcmd and is not comment-only text. **No shared library** (UC-A, operator-resolved).

### Phase 3 — T-1: Sentry arm on the evidence-capture script

1. RED: extend `tests/scripts/test-git-data-rung2-evidence-capture.sh` (≥33) with three arms —
   fatal present ⇒ `FAIL`; fatal absent with a live source ⇒ prior verdict; query non-200 /
   rc≠0 / unparseable ⇒ `TRANSIENT`.
2. Place the arm at **both** sites:
   - the `boot_complete`-missing branch (`:306`) — this is the #7116 fix, where Better Stack is
     live but silent because parent-shell stages reach Sentry only;
   - the two TRANSIENT exit paths, transport rc≠0 (`:252`) and zero-row anchor (`:271`), which
     exit **before** `host_out` is queried and are where Sentry is the only surviving channel.
3. Query `GET /api/0/organizations/jikigai-eu/issues/?query=…` with `host_name:` and `stage:`
   scoping, **bounded by the same `WINDOW`** the Better Stack SQL uses — Sentry issues
   aggregate across occurrences, so an unbounded query lets an earlier boot of a reused
   `host_name` flip a genuine PASS to FAIL.
4. **Fail closed:** non-200, rc≠0 or unparseable body ⇒ `TRANSIENT` with an explicit no-verdict
   line, mirroring `:253`/`:282`. Anchor on field shape (`"id":"…"`), never a bare token. Use
   herestrings, never `producer | grep -q` (#7005).
5. State the precedence rule in the script: **FAIL from either sink wins; TRANSIENT only when
   both are silent-and-live.**
6. Update the now-false operator message at `:307-312` and the header note at `:45-52` that says
   "#7116 owns that work; do not do it here" — this phase is that work.
7. Add a runbook line for the "Sentry FAIL, Better Stack silent" combination.
8. Green: `test-git-data-rung2-evidence-capture.sh` (≥33).

### Phase 4 — Reconciliation and follow-up

Re-sync measured byte figures across the ADR-152 addendum and the acceptance record. File the
T-4 follow-up issue (below) and the #6977 ordering prerequisite.

## Acceptance Criteria

### Pre-merge (PR)

1. The rendered `user_data` begins with the exact bytes `#cloud-config`, asserted by a committed
   test that fails against the payload expression.
2. Every shebang present in the unstripped render is present in the stripped render.
3. `stripped_bytes > 0` — the strip is not a no-op (ADR-152's third verification arm).
4. For each `write_files` entry and each `runcmd` element, stripped and unstripped differ
   **only** by lines matching the strip regex.
5. Every `${…}` interpolation site in `cloud-init-git-data.yml` is preceded on its line by a
   non-newline character, asserted by a committed test.
6. `cloud-init schema -c` runs against the **stripped** render in `validate-infra-templates.sh`.
7. `git_data_rationale_strip` is **byte-unchanged** from `origin/main`; the template expression
   is separately declared and separately mirrored, and the parity test compares both.
8. B1's extractor skips comment lines, proven by a fixture in which a comment naming a different
   expression precedes the live one.
9. `bash git-data-userdata-budget.sh` exits 0, reports stored < 32768, and the figures in the
   ADR-152 addendum and the acceptance record match its output.
10. `runcmd-all.code.sh` carries a non-vacuity assert; an empty slice fails the suite.
11. At least one rehearsal arm reads the unstripped render.
12. `SENTRY_ISSUE_RO_TOKEN` resolves under `prd_terraform` (the config the rung-2 workflow
    invokes), asserted rather than assumed.
13. The capture script issues at least one Sentry HTTP query; the two `echo`-only mentions are
    no longer its only Sentry code lines.
14. The capture script returns `FAIL` for a parent-shell stage whose fatal is present in Sentry,
    and `TRANSIENT` (never PASS) on non-200 / rc≠0 / unparseable body — both pinned by tests.
15. The Sentry query is bounded by the same `WINDOW` as the Better Stack query.
16. No `main.tf`, ADR-152 or capture-script text still asserts that the template is unstripped,
    or that early stages reach Sentry only with no reader.
17. Verification floors, re-run: luks ≥133; runcmd rehearsal ≥44 (detached, rc file); rung-2
    rehearsal ≥71; evidence-capture ≥33; `lint-encryption-posture.py --repo-sweep` PASS;
    `validate-infra-templates.sh` rc=0; `check-adr-ordinals.sh` rc=0.

### Post-merge (operator)

None. **But note:** no AC above exercises a live boot. `user_data` is ForceNew, no birth route
exists (#6977), and dispatching the rung-2 rehearsal is a Non-Goal — so every criterion is a
source-level or hermetic assertion. End-to-end verification is filed against #6977, including
the ordering prerequisite that the first birth dispatches the rehearsal *after* this merge.

## Test Scenarios

1. **Header preservation** — stripped render starts with `#cloud-config`; mutate to the payload
   expression and assert RED.
2. **Per-entry non-destructiveness** — byte diff per `write_files`/`runcmd` entry.
3. **Not-a-no-op** — `stripped_bytes > 0`.
4. **Payload expression untouched** — byte-identical to `origin/main`.
5. **B1 extractor** — a preceding comment naming another expression does not fool it.
6. **Slice vacuity** — an empty `runcmd-all.code.sh` fails, rather than passing four arms.
7. **Sentry arm, three directions** — fatal ⇒ FAIL; absent with live source ⇒ prior verdict;
   non-200 / rc≠0 ⇒ TRANSIENT.
8. **Better Stack down + Sentry silent** ⇒ TRANSIENT, not PASS.

## Non-Goals

- **T-4 (baking the Better Stack ingest token)** — deferred to its own PR by operator ruling.
- Dispatching `git-data-rung2-rehearsal.yml` (paid cpx22; operator step, cap 2).
- Triggering a git-data birth (#6977).
- Creating or regenerating `git-data-rung2-boot-evidence.env`.
- Project-quota enforcement.
- Sweeping the 43 remaining `grep -q` fail-open sites (#7005).
- Any live end-to-end verdict — unreachable until #6977 lands.

## Deferred — T-4, tracked as #7460

**What:** bake the Better Stack ingest token into `user_data` so the emitter reaches both sinks
without `doppler run`, giving all nine stages Better Stack coverage.

**Why deferred:** it carries the only security surface, the only ADR reversal (ADR-147
§"Channel split without a flag"), a merge-blocking Doppler write, and a stop-and-re-scope
trapdoor. Splitting keeps a boot-critical render change reviewable on its own.

**Re-evaluation criteria / what its plan must carry:**
- Verify `BETTERSTACK_LOGS_TOKEN` resides in `prd_git_data` — the "no new capability" argument
  is false without it — **and** commit an assertion so a later scope narrowing trips red.
- ADR-180 must state the trade on the **time axis**: today, revoking `doppler_token` closes the
  derivation path for every historical `tfstate` version; a baked token is directly readable and
  durable until Better-Stack-side rotation, and rotation then requires host replacement
  (ForceNew, no `ignore_changes`).
- New failure mode: after a BS token rotation, stages 1-5 ship on the stale baked token
  (currently swallowed by `|| true`) while 6-9 use the fresh env token — mirror that failure to
  Sentry (`cq-silent-fallback-must-mirror-to-sentry`).
- Gate merge on a CI check that resolves `TF_VAR_betterstack_logs_token` in `prd_terraform`;
  an unprovisioned no-default variable fails the whole root apply (`git-data.tf:373-374`).
- Note the Better Stack quota widening (~1 row/boot → 9) and the **pending processor DPA**
  (`compliance-posture.md:95`) — acknowledge, do not duplicate.

## Alternative Approaches Considered

| # | Alternative | Verdict |
|---|---|---|
| A1 | Re-prepend `#cloud-config` after stripping | **Rejected.** Encodes the hazard instead of removing it. |
| A2 | One shared tightened expression for payloads and template | **Rejected — this was revision 1's own error.** ADR-152 rules the expression "deliberately not shared, and must not be". Two separate locals, per the registry precedent. |
| A3 | `templatestring()` to strip pre-interpolation | **Open — evaluate in the ADR-152 addendum.** TF 1.9's `templatestring()` allows `templatestring(replace(file(path), strip, ""), vars)`, keeping the corpus closed and dissolving the interpolation-site and per-entry concerns. Root pins `>= 1.7` (`infra/main.tf:64`). If rejected, reject on **cost** — revision 1 recorded it as impossible, which is false. |
| A4 | Build the shared bash slicer as directed | **Rejected (UC-A, operator-resolved).** Two of three call sites are Python inside a heredoc; migrating them means disk round-trips, strictly worse than the one-liner. |
| A5 | Ship T-4 in this PR | **Rejected (UC-C, operator-resolved).** T-4 to its own PR. |

## Risks & Mitigations

- **The strip corrupts something inside a heredoc or block scalar.** Shape checks cannot see
  this; mitigated by the per-entry byte diff (AC4) and schema validation of the stripped
  document (AC6).
- **A secret value acquires a leading-`#` line.** Mitigated by AC5.
- **B1 extracts the wrong expression.** Mitigated by AC8; until then, no documenting comment.
- **The rehearsal loses discriminating power** once the render is comment-free. Mitigated by
  AC11 (one arm reads the unstripped render) and AC10 (non-vacuity).
- **T-1 fails open on a broken Sentry query.** Mitigated by AC14's TRANSIENT arm.
- **Nothing here is verified against a live boot.** Stated in Post-merge; filed against #6977.

## Sharp Edges

- Assert the render *starts with* `#cloud-config`. A `grep -c` passes even when the header has
  moved off line 1, where cloud-init ignores it.
- Never run `git-data-runcmd-rehearsal.test.sh` in the foreground (~13 min > 600 s ceiling).
- `templatefile()` takes a path, so under the current version pin the strip must wrap the
  render. `templatestring()` (TF 1.9+) is the alternative — see A3.
- The parity extractor strips comments; **B1 does not**. Do not document an old expression in a
  comment near the live one until B1 is hardened.
- Do not port a strip expression between the payload and template cases (ADR-152).
- The Sentry arm must sit on the TRANSIENT exit paths too — `:252` and `:271` return before
  `host_out` is ever queried.
