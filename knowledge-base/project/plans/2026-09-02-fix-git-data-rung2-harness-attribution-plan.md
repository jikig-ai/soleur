---
title: "fix(git-data): make the rung-2 rehearsal harness attribute its own verdict"
type: fix
date: 2026-09-02
slug: fix-git-data-rung2-harness-attribution
branch: feat-one-shot-7570-7534-7544-7481-7460-rung2-harness
issue: 7570
closes: [7570, 7534, 7544, 7481, 7460]
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(git-data): make the rung-2 rehearsal harness attribute its own verdict

## Overview

The git-data rung-2 rehearsal boots the git-data cloud-init on a throwaway host so the first
real boot of that template is not the production host that will hold every connected user's
source code. Five open defects mean a dispatch today cannot be trusted to report *why* it
failed — or that it passed at all.

The last real dispatch (GitHub Actions run `30649892865`, 2026-07-31) ended
`RUNG2_CAPTURE_VERDICT=1`, fatal at `stage:luks_open`, `rc=32`. That root cause — an ext4
quota `RO_COMPAT` feature the stock Ubuntu 24.04 image cannot mount — was fixed on `main`
in the merge landed 2026-08-03 (`mkfs.ext4 -q -O project`, ADR-163). It is **not** in scope
here. It is the reason the next rehearsal is expected to get further, and therefore the
reason the harness must report accurately when it does.

This plan repairs the harness. It does **not** dispatch the rehearsal.

Five defects, all verified live on `main` during this planning session:

| # | Defect | Effect on a dispatch |
|---|---|---|
| 7570 | D1 reads `$CAPTURE` before `run_case` defines it; under `set -u` the failing direction aborts | a real emitter regression prints `CAPTURE: unbound variable`, not D1's message |
| 7534 | the evidence-hash extractor cannot see four legitimate Terraform binding forms | a payload can be rewritten arbitrarily without moving the digest the evidence attests |
| 7544 | 6 `docker run` sites use the floating `ubuntu:24.04` tag | an upstream `e2fsprogs` bump moves R1's fingerprint with no repo change — unattributable CI red |
| 7481 | no Sentry second channel; the five parent-shell stages reach Sentry only | a host that already reported a fatal returns `TRANSIENT`, burning one of two sanctioned paid dispatches |
| 7460 | the Better Stack ingest token is not baked into `user_data` | stages 1–5 are invisible to the reader that polls Better Stack |

## Research Insights

### Premise Validation (Phase 0.6)

All five issues confirmed `OPEN`, none closed by a merged PR
(`gh issue view <N> --json state,closedByPullRequestsReferences` → `closedBy: []` for each).
All five defects confirmed present on disk in this worktree. Four premises carried in the
brief were checked and **three did not survive**:

| Premise as stated | Measured reality | Plan response |
|---|---|---|
| `HOST_SQL` may still omit the `detail` field | **Already closed.** `git-data-rung2-evidence-capture.sh` selects `JSONExtractString(raw,'detail') AS detail` — landed in `dfcf7bd26` (#7507, 2026-08-13 21:41 UTC) | No work. Removed from scope. |
| #7460 carries a merge-blocking Doppler write (`TF_VAR_betterstack_logs_token` must resolve in `prd_terraform`) | **Already satisfied.** `variable "betterstack_logs_token"` exists no-default at `apps/web-platform/infra/variables.tf` (anchor: `"Write-only Better Stack Logs ingest token (source 2457081"`); `BETTERSTACK_LOGS_TOKEN` is present in `prd_terraform` (verified via `doppler secrets -p soleur -c prd_terraform --only-names`); every Terraform invocation runs under `--name-transformer tf-var`, which maps it | The variable is added to the **module**, not the root. No Doppler write is needed. #7460 is **not blocked**. |
| #7460's residency precondition: `BETTERSTACK_LOGS_TOKEN` must reside in the `prd_git_data` Doppler config | **Satisfied in code, absent live.** `apps/web-platform/infra/git-data-luks.tf` declares `doppler_config.git_data_prd` (`name = "prd_git_data"`) *and* a `doppler_secret` named `BETTERSTACK_LOGS_TOKEN` in it. The live config does not exist — `doppler configs -p soleur` returns no `prd_git_data` — because git-data has never been born. | Residency is asserted against the **Terraform declaration**, which is what a later scope-narrowing would edit. A live-config assertion would fail-closed forever pre-birth and is the wrong instrument. |
| #7460 needs ADR-180 | **Ordinal taken.** `ADR-180-guard-contract-as-plan-time-deliverable.md` exists on `main`; the highest ordinal across **all 65 `origin/*` refs** is `ADR-197`. | New ADR is **ADR-198**, provisional. Re-derive across all refs immediately before merge (`/ship` ADR-Ordinal Collision Gate). |

Also measured, unprompted by the brief:

- **The four PRs from the collision probe (7567, 7507, 7458, 7540) close none of the five.** Confirmed.
- **`apps/web-platform/infra/git-data-rung2-boot-evidence.env` does not exist.** The birth gate
  therefore refuses every dispatch today, and **nothing is invalidated by editing
  `cloud-init-git-data.yml` in this PR.** See Risks §R1 — this is the argument for doing #7460
  *now* rather than after a rehearsal.
- **`user_data` headroom is 20,180 B** of the 32,768 B Hetzner cap
  (`bash apps/web-platform/infra/git-data-userdata-budget.sh` →
  `stored=12588 B / cap=32768 B (headroom 20180 B, raw 67479 B, stripped 36805 B)`).
  A baked token costs ~40–80 stored bytes. Budget is not a constraint.
- **`.github/dependabot.yml` does not exist.** #7544's claim confirmed. See §Design Call 2.

### Live Sentry measurements (constraint 3 — pulled in-session, not requested from anyone)

`SENTRY_ISSUE_RO_TOKEN` resolves under `soleur/prd_terraform`. Every row below is a live
probe run during planning against `https://sentry.io/api/0/organizations/jikigai-eu/issues/`.
**Four of them correct or sharpen #7481's own defect statements.**

| Probe | Result | What it settles |
|---|---|---|
| `?query=&statsPeriod=90d&project=-1` | HTTP 200, non-empty | the token reads the org; an anchor query is viable |
| org `jikigai` (the value `sync-health-residual-5689.sh` defaults to) | **HTTP 403** | #7481 defect 2 says org drift yields "200 + `[]` → queried cleanly". It does **not** — it yields 403. The fix (validate + anchor) is still right; the *mechanism* in the issue body is wrong and the arm must be written against 403. |
| `&project=999999999` | **HTTP 403** | project drift is likewise a 403, not a silent empty |
| `?query=nosuchtag:x` | **HTTP 200 `[]`** | **this** is the real silent-clean-bill mechanism: an unknown tag key is indistinguishable from a genuine miss. This is a materially better justification for the liveness anchor than the issue's own. |
| `?query=host_name:soleur-git-data-rehearsal-30649892865` | 200, **5 rows** — 2 `fatal`, 1 `warning`, **2 `info`** | #7481 defect 1 confirmed live: an unfiltered `host_name` query matches the unconditional `level:info` `bootcmd` beacon (`WEB-PLATFORM-63`, `git-data boot stage`), so the `boot_complete`-missing path returns FAIL on the first poll of a healthy boot |
| `…+level%3Afatal` | 200, **2 rows**, both `fatal` (`WEB-PLATFORM-6B` *git-data LUKS stage FAILED*, `WEB-PLATFORM-65` *git-data cloud-init FAILED*) | the filter works, and it is space-separated AND — Sentry search has no `OR` (`…/learnings/integration-issues/sentry-api-boolean-search-not-supported-20260406.md`) |
| `…+stage%3Aluks_open` | 200, 1 row | `stage:` tag queries work; the 2026-07-31 fatal is queryable and is the real production artifact the fixtures must model |
| `&start=…&end=…` (ISO pair) | HTTP 200 | run-pinned windows are supported |
| `&start=…` **alone** | **HTTP 400 `{"detail": "start and end are both required"}`** | #7481 defect 5 prescribes *"Pin the query to the run (ISO `start=` from the apply timestamp)"*. Implemented literally, **every call 400s**. `end=` is mandatory. |
| no `Authorization` header | HTTP 401 | the "four causes distinguished" requirement has a real 401 arm to assert against |
| `/organizations/jikigai-eu/projects/` | one project: id `4511404943671376`, slug `web-platform` | defect 6's project scoping has a concrete value |
| `/organizations/jikigai-eu/tags/host_name/values/` | `soleur-git-data-rehearsal-<run_id>` ×3, `soleur-web-2`, `soleur-web-g2probe` | the host-name shape is `soleur-git-data-rehearsal-<run_id>`, matching the workflow's own summary text |

One residual the probes could **not** decide, recorded honestly: Sentry issue search returns
*issue groups*, and a group can aggregate events from several hosts. `host_name:H level:fatal`
returning a row proves the group contains ≥1 event from `H` **and** that the group's level is
`fatal`; it does not by itself prove the *same event* had both. The mitigation is structural
rather than empirical: ADR-147 freezes the emit `message` literals, and the emitter uses a
*different* message per severity (`git-data boot stage` at info, `git-data cloud-init FAILED`
at fatal), so groups are level-homogeneous by construction. The plan states this bound rather
than asserting a stronger claim than the probes support.

### Live Docker measurement (#7544)

The two obvious commands return **different digests**, and only one is correct:

```
docker manifest inspect --verbose ubuntu:24.04
  → sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316
    mediaType application/vnd.oci.image.manifest.v1+json   ← PLATFORM-SPECIFIC (linux/amd64). WRONG.

docker buildx imagetools inspect ubuntu:24.04
  Digest: sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517
    MediaType application/vnd.oci.image.index.v1+json      ← MANIFEST LIST. This is the pin.
```

`knowledge-base/project/learnings/2026-03-19-docker-base-image-digest-pinning.md` requires the
manifest-list digest. The plan pins `sha256:33ceb719…` and names
`docker buildx imagetools inspect ubuntu:24.04` as the producing command, so a later refresh
cannot silently reach for the platform-specific one.

### Structural map of the surface

- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — verdict sentinel is a
  `trap 'printf "RUNG2_CAPTURE_VERDICT=%s\n" "$?"' EXIT`, so **every** exit path prints it.
  `ANCHOR_SQL` (anchor: `__ANCHOR__`) asks *"is this log source answering at all"* by selecting
  rows from any host **other** than the rehearsal host — deliberately excluding its own. Two
  Better Stack credential preflights `exit 2` before any query: a missing
  `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` and a missing query script. Evidence keys:
  `RUNG2_BOOT_REHEARSAL`, `RUNG2_EVIDENCE_URL`, `RUNG2_TEMPLATE_SHA256`, `RUNG2_VAR_DIVERGENCE`.
  **No Sentry query exists today** — the previous arm was fully reverted; only stale prose remains.
- `tests/scripts/test-git-data-rung2-evidence-capture.sh` — 12 arms, **anti-vacuity floor of 34
  assertions**. Stubs dispatch on the `__ANCHOR__` / `__HOSTROWS__` SQL comment markers rather
  than call ordinal, so a new query can be stubbed without reordering breakage. Wired into
  `scripts/test-all.sh` (anchor: `run_suite "tests/scripts/git-data-rung2-evidence-capture"`).
- `.github/workflows/git-data-rung2-rehearsal.yml` — capture step runs under
  `doppler run -p soleur -c prd_terraform`; bounded poll of 20 attempts / 16 min / 30 s sleep.
  Redaction tuple is a 3-name Python tuple (`BETTERSTACK_QUERY_HOST`, `…_USERNAME`,
  `…_PASSWORD`) applied to `capture.log` before a 7-day artifact upload **on a public repo**.
  The two-dispatch cap ("cap two per fix attempt") is prose discipline with no code enforcement.
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — arms `T1`–`T5`, `D1`, `R1`–`R4`,
  `S1`. Terminal line today is
  `git-data-runcmd-rehearsal: 44 passed, 0 failed, Skipped: 2 (46 assertions)`. Skip ceiling is 2.
  Run via `apps/web-platform/infra/run-registered-suites.sh` and `infra-validation.yml`, **not**
  directly from `scripts/test-all.sh`.
- `tests/scripts/test-git-data-birth-readiness-gate.sh` — arms `A1`–`A11`; `A4`/`A5`/`A7`/`A8`
  use dangling symlinks to force unreadable payloads (`chmod 000` is bypassed by root).
- `apps/web-platform/infra/modules/git-data-userdata/main.tf` — **exactly one** `templatefile(`
  and **nine** `file(` calls, all `"${path.module}/../../…"` single-line literals. The module is
  already in the canonical shape §Design Call 1 proposes to pin.

### Institutional learnings that constrain this plan

| Learning | Constraint imposed |
|---|---|
| `knowledge-base/project/learnings/2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md` | **Constraint 2's citation.** Every narrowed or new assertion in this plan carries a mutation row that must drive it RED. Fixtures model the production artifact, never a convenient synthetic one. |
| `…/2026-03-19-docker-base-image-digest-pinning.md` | manifest-list digest only; tag and digest move together; a drifted tag with a stale digest silently re-uses the old image |
| `…/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` | `${VAR:-}` is the fix shape for #7570; `set -u` aborts read as "the script failed", not "the guard failed" |
| `…/test-failures/2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns.md` | assert the arm registry is non-empty **before** looping; wrap deliberately-nonzero commands in `|| true` inside `$( )` |
| `…/2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md` | **#7481 defect 3.** Validate JSON *shape* before trusting any count — `jq -e` on `null \| length` yields 0 and exits 0 |
| `…/integration-issues/sentry-api-boolean-search-not-supported-20260406.md` | no `OR` in Sentry search; split into separate queries. The plan's queries are space-separated ANDs only. |
| `…/2026-05-04-sentry-org-token-region-probe-and-dashboards-scope-guard.md` | use org-scoped endpoints; token type determines which endpoints answer |
| `…/2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md` | do not verify "the guard is now written correctly"; verify "the guard reddens on the unpatched behaviour" |
| `…/2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md` | the ADR-147 addendum ships in **this** PR, not a follow-up |
| ADR-147 | emit `message` literals are frozen — never rename, only add tags. Load-bearing for the level-homogeneity argument above. |
| ADR-152 | the two rationale-strip expressions are deliberately different and must not be merged; the templatefile map must stay brace-free and one-entry-per-line |
| **ADR-149 + ADR-152 (NOT ADR-115)** | `user_data` is ForceNew with no `ignore_changes` — post-birth edits cost a destructive host replace. **Citation corrected at review:** `grep -c ForceNew` returns **0** in ADR-115, 1 in ADR-149 and 2 in ADR-152. The brief carried the ADR-115 attribution and the first draft propagated it to four places without checking — the `2026-08-06` wrong-measurement-propagated class, caught here. |
| ADR-149 | the birth route is held by a mechanical interlock; a defect in this harness is a defect in that interlock |
| ADR-163 | the 2026-07-31 root cause, already fixed — out of scope, and the reason a clean re-rehearsal is expected to progress further |

### Property List and Cut List (Phase 0.6b)

**Properties** — what a fixed harness must observably do:

- P1. When a rehearsal host fails, the capture script names **which stage** failed, not merely that something did.
- P2. When a rehearsal host is healthy, the capture script does **not** report FAIL.
- P3. When the capture script cannot consult a channel, it says **which** channel and **why**, and returns TRANSIENT — never a verdict.
- P4. Every test arm in the rehearsal suites prints **its own** failure message when the thing it guards regresses.
- P5. The evidence digest moves whenever any byte that renders into `user_data` changes — or the gate refuses to produce a digest.
- P6. An upstream base-image change that moves R1's fingerprint is reported **as a base-image change**, not as a template regression.
- P7. No secret reaches the 7-day public-repo artifact.

**Cut List** — mechanisms named by the issues that this plan does **not** build:

| Mechanism proposed | Property it would buy | Why cut |
|---|---|---|
| Full HCL parsing (`hcl2json` / `terraform console`) for #7534 | P5 | A canonical-shape assertion buys P5 with zero new dependencies and zero new "tool absent" arms. See §Design Call 1. Recorded in Alternatives Considered, not silently dropped. |
| A committed `Dockerfile` + `.github/dependabot.yml` for #7544's refresh | base-image freshness | The Dockerfile shape is #7535's deliverable, and #7535 is OPEN and out of scope. Building a Dockerfile here would collide with it — the issue explicitly says *"Either order works; do not do both at once."* Replaced by a follow-through freshness probe, which the repo's sweeper already dispatches. See §Design Call 2. |
| Re-selecting `detail` in `HOST_SQL` | P1 | **Already on `main`** since `dfcf7bd26`. Verified on disk. |
| A live-Doppler assertion that `prd_git_data` holds `BETTERSTACK_LOGS_TOKEN` | #7460 residency | The config does not exist pre-birth, so a live assertion fails-closed forever and measures nothing. The Terraform declaration is the authority a later scope-narrowing would edit; that is what gets asserted. |
| A new Doppler write of `TF_VAR_betterstack_logs_token` | #7460 merge gate | `--name-transformer tf-var` already derives it from the existing `BETTERSTACK_LOGS_TOKEN`. Measured. |

### Value-Proposition Measurement (Phase 0.6c)

The saving this plan claims is **paid rehearsal dispatches**, not compute. The route is capped
at two dispatches per fix attempt on a paid `cpx22`. Today, defect #7481 alone means a host
that already reported a fatal returns `TRANSIENT`, consuming one of the two without producing
a verdict — and defect #7570 means a genuine emitter regression in the *pre*-dispatch suite
aborts without naming itself. The measured baseline is run `30649892865`: one dispatch spent,
verdict `1`, and the cause (`stage:luks_open`, `rc=32`) was recoverable only because a human
went and looked at Sentry — which is the `hr-no-dashboard-eyeball-pull-data-yourself` violation
this plan removes. The saving is *"a dispatch produces an attributed verdict"*, and it is
measured by the acceptance criteria, not asserted.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality on disk | Plan response |
|---|---|---|
| "That specific gap [`HOST_SQL` detail] may already be closed on main — CONFIRM on disk" | **Closed.** `detail` is selected. | Scoped out with evidence. Zero work. |
| "#7460 … carries a merge-blocking Doppler write" | The variable exists no-default in the root and resolves via `--name-transformer tf-var` from an existing `prd_terraform` secret | **#7460 is not blocked.** The plan adds a *module* variable, not a root one. |
| "#7534's HCL-parsing fork [is a] likely candidate [for being blocked]" | The module is already in the canonical shape (one `templatefile(`, nine `path.module` literals) | **Not a genuine fork.** §Design Call 1 picks the canonical-shape assertion and says why, per constraint 5. |
| "9 floating `ubuntu:24.04` references" | 9 textual occurrences, of which **6 are live `docker run` spins** (anchors: the six `ubuntu:24.04 bash` lines) and 3 are prose | Pin the 6 spins. The 3 prose references get the digest only where they name a runnable command. |
| "#7570 … `:909` … `:910`" | Confirmed at those exact lines, with a `PRE-EXISTING HAZARD, TRACKED IN #7570` comment above it | Two-token fix as the issue prefers. |
| "#7544 issue table: sites at `:544`, `:611`, `:647`, `:708`, `:891`, `:1133`" | Line numbers have **drifted** — live spins are now at `:861`, `:1088`, `:1261`, `:1385`, `:1775`, `:2421` | Cite content anchors, never the issue's line numbers (`cq-cite-content-anchor-not-line-number`). |
| "#7481: `SENTRY_ORG` … HTTP 200 + `[]` → queried cleanly for the wrong org" | A wrong org returns **403** | The org-drift arm asserts 403, not empty-200. The anchor still earns its place — for the *unknown-tag-key* case, which genuinely returns 200 `[]`. |
| "#7481: pin the query with ISO `start=`" | `start=` without `end=` returns **HTTP 400** | The window is an ISO `start=`/`end=` **pair**. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the git-data host — the shared store holding
  every connected user's source code — is born from a template whose boot rehearsal reported a
  verdict it did not measure. The concrete artifact is
  `apps/web-platform/infra/git-data-rung2-boot-evidence.env` carrying
  `RUNG2_BOOT_REHEARSAL=PASS` for a boot that was never observed, which then unlocks the birth
  route (ADR-149's interlock) on false evidence. A dark git-data host is indistinguishable from
  a healthy one from the apply, and every user's push path depends on it.
- **If this leaks, the user's source code is exposed via** three vectors, enumerated by who is
  exposed rather than by surface:

  | Who | Vector | Bound |
  |---|---|---|
  | the alpha tester onboarded 2026-08-06, and every later user | **#6588** — user source code is unencrypted at rest while the privacy policy *already claims* LUKS encryption-at-rest. git-data's birth is what makes the published claim true, and this harness gates that birth. | present-tense, live today |
  | any local account on the git-data host — **including `git`**, which serves every connected user's push and transport | Phase 5.2 as first drafted bakes the ingest token into a **`0755` world-readable** `git-data-emit`, while `doppler_token` lives in a **`0600` root** env file. See §5.0d. | new exposure class, fixed in-plan |
  | any anonymous reader of the public repo | the 7-day `capture.log` artifact. Its redaction is a **name-based allowlist of three values** over an environment `doppler run -c prd_terraform` populates with the whole config — including `AWS_SECRET_ACCESS_KEY`, which this plan's own Encryption Posture names as granting full Terraform state read. The step pipes `2>&1`, and Phase 4.3 is the first change to route unbounded third-party content (curl stderr) into that stream. | fail-open **shape**, not an active leak: no `set -x`, no env dump today |

  The Better Stack ingest token is write-only against a shared source, so a leak buys forged rows
  and quota burn — **but the remediation is cross-host**: that one value fans out to the Inngest
  host's bake, the zot registry, git-data, and the web host's Vector sink, so rotating it darkens
  three other shippers and costs two host replaces (§5.0d(ii)).

  Converting fail-opens to fail-closeds is this plan's whole thesis, and the redaction allowlist is
  the one place the first draft did not apply it to its own artifact. Phase 4.6 adds the token and
  files the inversion as its own issue; the mechanism is a security-review call, not something to
  improvise inside a harness PR.
- **Brand-survival threshold:** `single-user incident` — and the strongest justification is
  **#6588** (P0-critical, `type/security`, Phase 4), not the harness-false-PASS chain the first
  draft led with. The false-PASS argument is real but multi-step and contingent; #6588 is a
  standing misrepresentation, live now, with a user already onboarded. This PR is on its critical
  path.

CPO sign-off is required at plan time before `/work` begins; `user-impact-reviewer` is invoked
at review time.

## Design Calls

### Design Call 1 — #7534: canonical-shape assertion, not HCL parsing. Not a genuine fork.

The issue frames this as *"parsing HCL (or asserting `main.tf` contains exactly one
`templatefile(` and no non-`path.module` `file*(` literal, which is a cheaper partial). That is
a design question, not an edit."* Its recorded re-eval trigger — *"when the git-data birth route
is ready to dispatch"* — has fired, so the call must be made now.

**Recommendation: the canonical-shape assertion. This is a decision, not a coin-flip, and the
reason is that the two options do not buy the same property.**

Full HCL parsing tries to *widen coverage* so every expressible binding form gets hashed. It
cannot actually reach that: `file(local.p)` requires evaluating the module, not parsing it, and
a computed local is not statically resolvable at all. So the "complete" option is itself partial,
while costing a new binary dependency (`hcl2json`, or `terraform` on the `$PATH` of a bash
library that runs in CI shards and locally) and a new fail-mode — *"the parser is absent, now
what?"* — inside a gate whose entire contract is fail-closed.

The canonical-shape assertion instead **narrows the admissible module shape** so the existing
extractor is provably complete over it:

1. after comment-stripping, `main.tf` contains **exactly one** `templatefile(` occurrence, and
   its argument is the known `"${path.module}/../../cloud-init-git-data.yml"` literal; and
2. the count of `file`-family occurrences equals the count the extractor resolved — i.e.
   **every** such occurrence matched the strict single-line `"${path.module}/…"` literal form.

   **The occurrence count MUST carry the extractor's own `(^|[^A-Za-z])` word boundary.** Without
   it the rule counts `templatefile(` as a `file(` and aborts on the shipped module. Measured
   against the comment-stripped `main.tf`: naive `file`-family occurrences = **10**, boundary-aware
   = **9**, extractor-resolved = **9**. A literal reading of the first draft's prose gives
   `10 != 9` -> permanent ABORT, and Guard 1's two must-PASS rows go RED on day one. The extractor's
   own comment states the rule (*"every `file("${path.module}/…")` on a NON-COMMENT line, excluding
   `templatefile(`"*); the prose dropped the boundary that implements it.

   Two companions in the same rule: the resolved side is **post-`sort -u`**, so two bindings
   referencing the same payload would false-ABORT — Guard 1 row 6 must therefore add a *new* file,
   not merely a tenth binding to an existing one. And the exactly-one `templatefile(` check needs
   `grep -o … | wc -l`, not `grep -c`: two occurrences on one physical line count as one line.

Any deviation **ABORTs**, in the same voice as the existing per-payload abort. That converts an
unbounded fail-*open* (an unknown form silently unhashed, evidence attesting a byte set that is
not what shipped) into a bounded fail-*closed* (an unknown form refuses to produce a digest at
all). For an evidence gate, refusing is correct; hashing an incomplete set is not.

**The residual bound, stated honestly:** this does not make every binding form hashable. It makes
every non-canonical form *inadmissible*. If a future change legitimately needs `file(local.p)`,
the gate reddens and a human must either restore the canonical form or extend the gate
deliberately. That is the intended trade and it is the reason the abort message must name the
offending occurrence rather than only reporting that two integers disagreed — the same lesson
the existing per-payload abort already encodes.

All four forms the issue enumerates are caught: multi-line `file(\n "…"\n)` (occurrence counted,
not resolved → mismatch); `file(local.p)` (same); a second `templatefile(` (fails the
exactly-one check); a non-`path.module` literal (same mismatch). The three withdrawn items from
the issue body (`.tf` in a subdirectory, `sha256sum` symlink-following, `_r2_hash` equivalence)
are **not** re-raised.

**The gate's grammar is stated up front, in two classes, because Phase 5 adds a map entry.**
The `templatefile` map holds two kinds of entry and the gate must be written against that
distinction rather than against today's snapshot — otherwise Phase 5's new
`betterstack_logs_token` entry either trips the gate this PR just built, or forces an ad-hoc
loosening under pressure, which is how a fail-open quietly reopens:

| Class | Example | Gate's rule | Bound by |
|---|---|---|---|
| **file-form** — a `file`-family call | `git_data_bootstrap = replace(file("${path.module}/../../git-data-bootstrap.sh"), …)` | MUST be a strict single-line `"${path.module}/…"` literal, else ABORT | the evidence digest (the bytes are hashed) |
| **value-form** — anything else | `host_name = var.host_name`, `sentry_dsn = var.sentry_dsn`, and Phase 5's `betterstack_logs_token = var.betterstack_logs_token` | not a `file*(` occurrence, so the gate does not quantify over it — it must **not** trip | `RUNG2_VAR_DIVERGENCE` (declaration) and the render-arg parity assertion in Phase 5.6 |

So Phase 5's addition is a value-form entry and is unaffected by Guard 1 **by construction, not
by exemption**. Guard 1's matrix carries a must-PASS row proving exactly that (row 8), and the
Phase 5 map change is validated against the Phase 2 gate in the same battery rather than
discovered to interact at `/work` time.

### Design Call 2 — #7544: pin now, refresh by follow-through probe, do not build the Dockerfile

The pin itself is unambiguous and lands here. The **refresh mechanism** is the design question,
and the issue's own preferred answer (Dependabot, which needs a committed Dockerfile) collides
with #7535: *"If #7535's inline-image change lands first, the pin belongs in that Dockerfile's
`FROM`. … Either order works; do not do both at once."* #7535 is OPEN and out of scope. There is
no `.github/dependabot.yml` today, so adopting Dependabot means introducing a whole ecosystem
configuration to manage one literal — and then re-doing it when #7535 lands the Dockerfile.

**Recommendation (REVISED at plan review — the first draft's mechanism was inert):** add an
`ubuntu:24.04` case to the **existing** `Detect zot pin staleness` step in
`.github/workflows/rule-audit.yml`.

The first draft proposed a new follow-through probe
(`scripts/followthroughs/ubuntu-base-digest-freshness-7544.sh`) exiting 0 when pinned == live.
**Three reviewers independently found this self-destructs.** The follow-through substrate is a
one-shot *close-criteria* tracker, not a monitor: `followthrough-convention.md` states
*"Exit 0 = PASS (close-criteria met → sweeper closes the issue)"*. On the first sweep after merge
the pin equals live by construction, so the sweeper would **close #7544**, and the probe would stay
reopen-eligible only inside `CLOSED_LOOKBACK_DAYS=14` before leaving the query window forever.
`ubuntu:24.04` does not move on a 14-day schedule. The mechanism would have terminated precisely
because drift was absent. The convention file even warns about this class — probes that *"PASS
vacuously and auto-close the tracker blind"* — and the first draft cited that file while walking
into the paragraph.

`rule-audit.yml` already does the right thing, on cron, unbounded: it polls upstream, compares to a
committed pin, and files **one idempotent `action-required` issue** on drift (anchors:
`Detect zot pin staleness`, `gh issue create --label zot-pin-drift --label action-required`). One
new case there buys the durable property with **zero** new files, no `run_suite` registration, and
nothing for #7535 to delete beyond one block.

The first draft also justified the probe as *"the shape #7535 can delete in one line"*. That
rationale does not survive either: #7535's own re-eval trigger is an **event-grep** on an
`R3/R4 fixture-starvation failure` that may never occur — and Phase 3's digest pin makes upstream
`apt` drift *less* likely, so this plan measurably reduces the probability of its own deferral
target firing. Treat the `rule-audit.yml` case as permanent, not as a bridge.

## Implementation Phases

Ordering is by **dependency direction**, not by file. Phase 5 is last because it is the single
`cloud-init-git-data.yml` edit (constraint 1), and it must be shaped after Phase 4 has settled
what the Sentry channel covers.

### Phase 0 — Preconditions (measure, do not assume)

0.1 Record the runcmd suite's terminal line **from a run, not from a fixture**. Measured this
session: `git-data-runcmd-rehearsal: 69 passed, 0 failed, Skipped: 0 (69 assertions)`.

**The first draft quoted `44 passed, 0 failed, Skipped: 2 (46 assertions)` and "skip ceiling is
2". Both were wrong**, and the review caught the plan contradicting its own measurement. The
44/46/2 triple is verbatim the *fixture* literal in
`scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` — which Phase 0.5 itself correctly
identifies as a fixture rather than a live expectation, and which the first draft then quoted as the
live baseline. On disk the suite **hard-exits 1 below 69 assertions** (anchor:
`if [ "$total" -lt 69 ]`), so a 46-assertion run is impossible; and `_SKIP_CEILING=7`, itemised in
its own stanza. The "skip ceiling at 2" line the first draft echoed is a stale comment inside D1's
block — one of the comments Phase 1.1 replaces.

Consequence: **this suite has a floor too, and the first draft's floor discipline never named it.**
Phase 1.2 (`D1-MUT`) and Phase 3.4 (`R1-PIN`) both add arms here, so the `-lt 69` literal must rise
with them, following the file's own raise-itemisation convention (`# RAISED 58 -> 68 (#7613),
ITEMISED`). Same for `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` (floor 71), which
Phase 5.5 touches. **Four floors, not two.**

0.2 Record the anti-vacuity floors. **Measured at plan time, both suites sit exactly AT their
floor**, so the floor is self-enforcing: adding an arm without raising the literal turns the
floor check RED in the same run.

| Suite | Measured | Floor |
|---|---|---|
| `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` | `34 passed, 0 failed` — `anti-vacuity floor: 34 assertions ran (floor 34)` | 34 |
| `bash tests/scripts/test-git-data-birth-readiness-gate.sh` | `69 passed, 0 failed` — `anti-vacuity floor: 69 assertions ran (floor 69)` | 69 |

Every arm this plan adds raises the corresponding floor by its own assertion count, in the same
commit. Do not defer the floor bump: a floor that trails the arm count silently tolerates a
deleted arm.

0.3 Re-derive the free ADR ordinal across **all** `origin/*` refs, not `origin/main`:
`for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree --name-only "$r" knowledge-base/engineering/architecture/decisions/; done | grep -oE 'ADR-[0-9]{3}' | sort -u | tail -3`.
Measured at plan time: highest is `ADR-197`, so **ADR-198** is provisional.

0.4 Re-resolve the `ubuntu:24.04` manifest-list digest immediately before writing the literal
(`docker buildx imagetools inspect ubuntu:24.04 | grep '^Digest:'`) and use **that** value, not
the plan's — the tag moves.

0.5 Confirm `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` still passes after
each suite-count change. Its `TERMINAL_LINE` is a **fixture** literal, not an assertion against
the live suite (the probe itself matches the bare prefix `git-data-runcmd-rehearsal:`), so a
count change does not break it — but a drifted fixture weakens the probe's fidelity and should
be updated with the count.

### Phase 1 — #7570: D1 attributes its own failure (highest priority)

The narrowest fix, and the one the operator named. `run_case` first assigns `CAPTURE` at the
`CASE_RC="$rc"; CAPTURE="$TMP/out/capture.log"` line, whose first call is `T5` — **below** D1.
So under this file's `set -u`, D1's `[ -s "$CAPTURE" ]` expands an unset variable, and because
`[` short-circuits on `||` it is reachable **only** when `_d_rc == 2`: precisely D1's failing
direction.

1.1 Change the D1 read to `[ -s "${CAPTURE:-}" ]`. **The `:-` is what does the work** under this
file's `set -uo pipefail`; the issue's preferred `CAPTURE=""` initialisation is optional belt-and-
braces, and the first draft's "two tokens, and the initialisation is what makes the arm
attributable" framing had it backwards. Delete the `PRE-EXISTING HAZARD, TRACKED IN #7570` comment
block and replace it with a note naming the real mechanism.

**Decide the `||` disjunct explicitly — do not leave it dead.** `CAPTURE` is first assigned inside
`run_case` (`CASE_RC="$rc"; CAPTURE="$TMP/out/capture.log"`), whose first call is `T5`, *below* D1.
So at D1 the variable is unset today and — if it is initialised to `""` — permanently empty. The
predicate `[ "$_d_rc" -ne 2 ] || [ -s "${CAPTURE:-}" ]` then has a right operand that is
**permanently false**, whatever the emitter writes. The first draft asserted the opposite
(*"the must-PASS boundary the `||` encodes"*) and Guard 4 row 3 was therefore unsatisfiable.

Two honest options, and the plan must pick one rather than paper over it:
- **(a)** point `CAPTURE` at the real capture path *before* D1, so the disjunct means what it reads
  as — an emitter that exited 2 but still emitted is not a D1 failure; or
- **(b)** delete the disjunct, making D1 a bare `[ "$_d_rc" -ne 2 ]`, and state in the comment that
  the emitter's output is not observable at this point in the file.

**(a) is preferred** — it preserves the arm's stated semantics and keeps Guard 4 row 3 meaningful.
(b) is acceptable only with the comment, because a silently-dead disjunct is the same class of
defect as the unattributed abort this issue exists to fix.

1.2 **Prove the arm reddens on the real defect, not on the fix** (per
`2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`). Add a mutation arm
`D1-MUT` that copies the emitter to a scratch path, rewrites its argument handling so a 3-arg
call dies at the `shift` (`_d_rc == 2`) while producing no capture output, runs D1's predicate
against it, and asserts the message printed is D1's own text — **not** a shell abort. The arm
must fail if the predicate ever again reaches an unset `CAPTURE`.

### Phase 2 — #7534: the canonical-shape assertion (Guard 1)

2.1 In `tests/scripts/lib/git-data-birth-readiness-gate.sh`, immediately **before** the existing
`while IFS= read -r _f` payload loop, add the two checks from §Design Call 1 against the same
comment-stripped `$module_tf` text the extractor reads. Both abort with `return 1` and a message
naming the offending occurrence. Reuse the existing `sed 's/^[[:space:]]*#.*$//'` strip so the
assertion and the extractor cannot disagree about what a comment is — a divergence there would
reintroduce exactly the class this closes.

2.2 Update the `THE HONEST BOUND on this predicate is a SINGLE-LINE LITERAL form` comment block:
the bound is no longer "these forms are invisible" but "these forms are inadmissible". Add the
**fourth**, undocumented form the issue records (a single-line literal whose prefix is not
`${path.module}/` — `file("${path.root}/x")`, `file("../x")`, `file(abspath(…))`), which the
issue says should be documented regardless of when it closes.

2.3 Add arms `A12`–`A15` to `tests/scripts/test-git-data-birth-readiness-gate.sh`, one per
binding form, each building a synthesized module tree (per `cq-test-fixtures-synthesized-only`)
and asserting the gate ABORTs with `rc=1` and a message naming the occurrence. Follow the
`A4`/`A5`/`A7`/`A8` fixture idiom.

2.4 Add arm `A16`: a **must-PASS** case that is not the canonical tree — the same nine payloads
with an extra `path.module` binding added (ten payloads) — asserting the gate still produces a
digest and that the digest **moves** when that tenth payload's content changes. This is the
harness row constraint 2 requires: a matrix of only-RED rows cannot detect a guard that rejects
everything.

### Phase 3 — #7544: digest-pin the base image (Guard 2)

3.1 Introduce a single shell literal near the top of
`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`:
`UBUNTU_BASE='ubuntu:24.04@sha256:<manifest-list digest from Phase 0.4>'`, with a comment
recording (a) that the digest is the **manifest-list** one, (b) the exact command that produced
it, and (c) that tag and digest move together per the 2026-03-19 learning.

3.2 Replace all **six** live `docker run` spin sites with `"$UBUNTU_BASE"`. Anchors: the six
`ubuntu:24.04 bash` lines (inside `run_case`; the two standalone spins; inside `_s1_run`; R1's;
R4's). Leave the two prose references intact except where they name a runnable command
(`docker run --rm ubuntu:24.04 dpkg -s e2fsprogs` → the pinned form), so a reader copying the
line reproduces what CI ran.

3.3 **Assert R1's fingerprint against the pinned version rather than refreshing the fixture.**
R1's `unclassified=` / `moduledep=` verdicts are the classification; the surrounding comment
already warns *"Do NOT 'refresh' the fixture wholesale — the point is the classification, not
the diff."* Add to R1's failure detail the pinned digest and the `mke2fs` version measured
inside it, so a drift message reads *"the pinned image's mke2fs is X, the allowlist was built
against Y"* rather than blaming the template. Update the parenthetical that currently reads
`(mke2fs measured 1.47.0 in ubuntu:24.04 / 1.47.2 on the authoring host.)` to name the digest.

3.4 Add arm `R1-PIN`: asserts every `docker run` invocation in this file carries an
`@sha256:` digest — a grep over the file's own text with a **floor** (`≥ 6` spins found), so the
arm cannot pass by finding zero. This is the anti-vacuity row.

3.5 Add an `ubuntu:24.04` case to the existing `Detect zot pin staleness` step in
`.github/workflows/rule-audit.yml` (see §Design Call 2). It reads the pin from
`git-data-runcmd-rehearsal.test.sh`'s `UBUNTU_BASE` literal — so the monitor and the pin cannot
drift — resolves the live manifest-list digest, and on divergence adds to the step's existing
idempotent `action-required` issue naming both digests. **No new files, no follow-through
enrollment.** This is also the component that legitimately has network, so the manifest-list-vs-
platform-digest media-type check lives here rather than in the offline suite (see Guard 2 row 4).

### Phase 4 — #7481: the Sentry second channel — REUSE, do not rebuild (Guard 3)

The largest phase, and the one plan review changed most. All six defects, addressed against the
**measured** API semantics above — and against a proven in-repo reader this plan originally failed
to look for.

#### 4.0 — the correction that reshapes this phase

The first draft asserted *"no Sentry query exists today"*. That was true of the **capture script**
and false of the **repo**, and the difference is the whole architecture of this phase. This was a
`hr-verify-repo-capability-claim-before-assert` failure in the plan's own research: the claim was
verified against the consuming file rather than against the authority.

`apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` (26 KB, in production) already
implements four of the five mechanisms Phase 4 was about to write from scratch:

| Mechanism | Already in `fresh-host-boot-trail.sh` |
|---|---|
| shape validation before counting | `if [[ "$HTTP" != "200" ]] \|\| ! echo "$RESP" \| jq -e 'type == "array"'` — Phase 4.4, verbatim |
| a failure message that is not a verdict | `"Sentry read FAILED (HTTP ${HTTP}) — the auto-read did NOT run; this is NOT a 'host emitted nothing' result."` |
| host-scoped, event-level `level == "fatal"` filtering | `select(hostok($eh))` + `select(.key=="level") \| .value == "fatal"` |
| a run anchor | `sincok($since)` — the same "attempt 2 must not read attempt 1's fatal" problem |

**And it uses a strictly better endpoint.** It reads
`https://de.sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/events/` — **individual
events, each with its own tags** — where the first draft chose `/organizations/{org}/issues/`,
which returns *issue groups*. That difference **dissolves the residual this plan documented and
honestly admitted it could not close**: with the issues endpoint, `host_name:H level:fatal`
matching proves the group contains an event from `H` and that the group's level is `fatal`, not
that the same event had both, and the plan had to lean on ADR-147's message-literal freeze to argue
level-homogeneity. With the events endpoint the question does not arise. A weaker instrument plus a
paragraph defending the weakness is strictly worse than the stronger instrument already in the tree.

Note also the **regional host**: the existing reader uses `de.sentry.io`. The plan's own probes used
`sentry.io` and returned 200, so both resolve, but the repo's convention is the regional host and
this phase follows it.

`scripts/sentry-issue.sh` additionally already carries the 401 and 403 diagnostic wording Phase 4.3
was going to invent, and the `SENTRY_ISSUE_RO_TOKEN` resolution ladder.

**Therefore: extract, do not re-implement.** The capture script's consult calls a shared helper
factored out of `fresh-host-boot-trail.sh` (or, if extraction proves to entangle that script's
poll loop, the capture script calls the existing script). Either way the plan must not create a
**third** Sentry reader. If extraction turns out to be infeasible at `/work` time, record in the PR
body **why** — per that script's own header: *"EXTRACTED, NOT REWRITTEN … Duplicating the block
would have given the two copies one test between them."*

#### 4.1 — the query

One helper builds a single space-separated AND query — no `OR`, per the 2026-04-06 learning —
scoped to the events endpoint, filtering `host_name == <HOST_NAME>` and `level == "fatal"` at the
**event** level. `SENTRY_ORG` is **pinned to a literal, never read from the environment**: the
`doppler run -c prd_terraform` wrapper exports every secret in that config, and an env-sourced org
is the defect. `SENTRY_PROJECT` is likewise pinned, with an inline comment naming
`/organizations/jikigai-eu/projects/` as the source of the id `4511404943671376` and the date it
was measured (2026-09-02) — a bare magic number in the implementation is how the next reader
inherits an unexplained literal.

The run window is derived from the apply timestamp. **State the `end` semantics explicitly**: `end`
must track *now*, not be frozen at capture start, or fatals emitted later in the 16-minute poll
fall outside the window on every subsequent attempt. Closes defects 1, 5, 6.

**The window shape was validated end-to-end at plan time on the issues endpoint**
(`verified: 2026-09-02`) — the ISO `start=`/`end=` **pair** is mandatory there (`start=` alone
returns HTTP 400 `{"detail": "start and end are both required"}`), which is what falsifies the
issue body's literal prescription. Re-validate the equivalent parameter on the events endpoint at
Phase 0, since the two endpoints need not share it.

#### 4.2 — the liveness anchor, with a window that is not the verdict window

The anchor answers *"is this source answering at all"*. Two ways to get it wrong, both found at
review, both already paid for by the Better Stack anchor's own header (*"An anchor that is a strict
prerequisite of the thing it is anchoring is not an anchor; it would have returned zero rows on a
perfect rehearsal, forever"*):

- **Do not include the rehearsal host.** Its own unconditional `level:info` `bootcmd` beacon would
  satisfy the anchor, making it vacuous — satisfied by the very host it exists to be independent of.
  Mirror `ANCHOR_SQL`, which excludes its own host by design.
- **Do not reuse the run-pinned window.** In a one-project org over a minutes-long window the
  rehearsal host may be the only emitter, so an own-host-excluding anchor returns zero rows on a
  *perfect* run → false TRANSIENT → 20 attempts and a paid host burned, which is the exact cost
  this plan exists to save. The Better Stack anchor deliberately uses a wide `30 DAY` window rather
  than the run window; this one uses the equivalent (`statsPeriod=90d` is the shape measured
  non-empty at plan time). **The window width is the load-bearing parameter and it is specified
  here, not left to `/work`.**

**Constrain the projection.** The capture script's own header records why: *"this route projects
matched rows into a PUBLIC Actions log on a PUBLIC repo, so an unconstrained reader is one flag
away from exporting production boot telemetry."* The Better Stack anchor answers liveness with a
minimal projection (`dt, host` only — never `raw`/`detail`). The Sentry anchor must do the same:
emit a **count or ids only**, never `title` or `culprit`. Only the host-scoped verdict query may
print titles, and only after Phase 4.6 widens the redaction tuple.

**Honest scoping of what the anchor buys.** The tag keys are frozen literals (ADR-147) and Guard 3
row 9 already asserts the query string in CI, so a typo'd tag key reddens before any dispatch. What
the anchor uniquely catches at runtime is *Sentry ingest being down*. That is its justification —
not the unknown-tag-key case, which CI covers.

#### 4.3 — distinguish causes, and separate DETERMINISTIC from TRANSIENT

Capture the HTTP status with `-o <file> -w '%{http_code}'` — into a **separate stream**, never
interleaved with the body a parser will read (measured at plan time: appending `--write-out` text
to the response makes the whole payload unparseable). Keep `curl` stderr.

**The split matters more than the enumeration.** The first draft returned `exit 2` (TRANSIENT) for
all four causes, and the workflow retries `rc=2` for 20 attempts / 16 minutes against a paid
`cpx22`. A 401 (token absent or rejected) and a 403 (org or project not accessible) are
repo/credential-side and **identical on every attempt** — retrying them spends the whole poll budget
to report the least actionable verdict. The workflow already has a fast-fail for exactly this class
(`a bad credential is not transient`), and the script's own DERIVATION FAULT comment records the
same lesson.

| Cause | Class | Handling |
|---|---|---|
| 401 | deterministic | terminal, distinct rc — do not retry |
| 403 | deterministic | terminal, distinct rc — do not retry (reuse `sentry-issue.sh`'s wording) |
| everything else | transient | one catch-all: `HTTP <code>: $(jq -r '.detail // empty')` |

The catch-all replaces the first draft's dedicated `429` arm. **429 was never measured; the 400 the
plan actually hit was not enumerated.** An arm invented for an unobserved status alongside a missing
arm for an observed one is the wrong trade — the catch-all covers 400, 429, and every code nobody
thought of, which is what `fresh-host-boot-trail.sh` already does in one line.

Add a **token-presence preflight** mirroring the Better Stack one, so an absent
`SENTRY_ISSUE_RO_TOKEN` is a cheap deterministic refusal rather than a 401 discovered mid-poll. Add
a `command -v jq` structural check for the same reason the emitter checks `command -v curl`: an
absent `jq` yields rc 127, which reads most naturally as "not an array" and would produce a
permanent TRANSIENT.

**Every new cause carries a `**Next:**` clause.** The existing verdict blocks are written in an
action-first voice (`**Next:** check the DOPPLER_TOKEN secret … Then re-dispatch.`); a distinct
message is a *diagnosis*, and a diagnosis is not an action. Each cause must state explicitly
whether a re-dispatch is warranted — for all of these it is not.

#### 4.4 — shape validation before counting

Per the 2026-07-23 learning and the existing reader's idiom: assert
`jq -e 'type == "array"'` **before** any length is taken. A 200 whose body is HTML or an object
yields TRANSIENT, never clean. `jq -e` on `null | length` returns 0 and exits 0 — the count must
never be the first thing trusted.

#### 4.5 — placement: DERIVE the site set, do not enumerate it

The first draft named four call sites. **There are six**, and the two it missed are the two the
plan itself cites as the previous regression. Measured — seven `exit 2` sites in
`scripts/followthroughs/git-data-rung2-evidence-capture.sh`:

| Anchor | Class |
|---|---|
| `for v in BETTERSTACK_QUERY_HOST` (creds unset) | needs consult |
| `TRANSIENT: ${QUERY} not found` | needs consult |
| `the Better Stack query transport exited ${anchor_rc}` | **needs consult — missed by the first draft** |
| `returned ZERO rows from ANY other host` | needs consult |
| `the host-rows query exited ${host_rc}` | **needs consult — missed by the first draft** |
| `has not reported` (`boot_complete` missing) | needs consult |
| `DERIVATION FAULT (deterministic, NOT transient)` | excluded **by name** — deterministic, not a channel failure |

The first draft wrote *"the two Better Stack credential preflight sites"* where Guard 3's own
Assembly said *"both **transport-failure** sites"*. Those are different pairs. The plan named the
sites where the previous regression happened as its justification and then wrote a list excluding
them.

**The fix is structural, not a longer list.** Route every TRANSIENT exit through a single
`transient()` helper that consults the second channel once and upgrades to a named FAIL when a fatal
is found. Then:

- one consult implementation instead of six placements;
- the mutation *"revert one site to a bare `exit 2`"* is caught by **one** arm grepping for a bare
  `exit 2` outside the helper, with the derivation-fault site excluded by name and a **floor** on
  the count;
- a seventh TRANSIENT path added next year is covered automatically.

This is the same design Guard 2 states for `docker run` (*"greps the file's own text … rather than
enumerating the six. Members drift"*). Enumerated member sets rot, and this plan is the proof.

#### 4.5b — the verdicts the flow did not define

Three states the first draft left undefined, all found by flow analysis:

- **A Sentry-derived FAIL has no stated exit code.** It must be `exit 1` — the terminal FAIL — since
  "a host that already reported a fatal returns TRANSIENT" is the entire defect #7481 names. The
  workflow's FAIL summary is Better-Stack-flavoured (`read which assertion went false`) and must
  gain a Sentry-derived variant.
- **Silent-both.** Better Stack unreadable *and* Sentry returns 200 with no fatal → **TRANSIENT,
  never PASS**. This holds by construction today (PASS requires `boot_complete` from Better Stack,
  and the consult never writes evidence) but nothing states it and no arm asserts it. Add a
  must-PASS row: both channels silent → rc 2.
- **Better Stack PASS + Sentry FATAL.** The PASS path never consults Sentry, so a host that emitted
  a pre-`doppler run` fatal and later reached `boot_complete` writes
  `RUNG2_BOOT_REHEARSAL=PASS` — **the exact artifact `## User-Brand Impact` names as the failure.**
  Either the PASS path gains a Sentry cross-check, or the plan states the precedence and why it is
  acceptable. Given the threshold, it gains the cross-check.

#### 4.6 — redaction

Add `SENTRY_ISSUE_RO_TOKEN` to the workflow's redaction tuple (anchor: the
`for var in ("BETTERSTACK_QUERY_HOST",` line), and an arm asserting the tuple contains it.

**The wider finding, recorded rather than fixed here.** That tuple is a **name-based allowlist of
three values over an environment `doppler run -c prd_terraform` populates with the whole config** —
including `AWS_SECRET_ACCESS_KEY`, which this plan's own Encryption Posture names as granting full
Terraform state read — feeding a 7-day artifact on a **public** repo. The capture step pipes `2>&1`,
and Phase 4.3 is the first change to route *unbounded third-party content* (curl stderr) into that
stream. There is no `set -x` and no env dump today, so this is a fail-open **shape**, not an active
leak — but converting fail-opens to fail-closeds is this plan's whole thesis. **Name it in
`## User-Brand Impact`, add the token, and file the inversion (iterate the config's own name list,
or a value-denylist) as its own issue** — the mechanism choice is a security-review call, not
something to improvise inside a harness PR.

#### 4.7 — remove the eyeball instructions WITHOUT deleting the guidance around them

There are **three** sites, not two. The first draft named two and its AC asserted only absence,
which as specified permits landing Phase 4.7 as a pure deletion.

1. `.github/workflows/git-data-rung2-rehearsal.yml` — the TRANSIENT summary. The `Confirm against
   Sentry first` clause is **one of five** things that paragraph carries. The other four must
   survive verbatim or be restated:
   - `**Next:** download the git-data-rung2-capture-log artifact …` (the read path)
   - `**DO NOT simply re-dispatch.**`
   - `Each dispatch spends a paid cpx22 — cap two per fix attempt` — **the only statement of the
     two-dispatch cap anywhere in the repo**, and the plan's entire value proposition
   - `**#7025 stays open and the DO-NOT-DISPATCH banner stays up.**`

   The same paragraph also asserts *"#7116 mis-reports TRANSIENT for exactly the early-boot fatals
   it could read from Sentry directly"* — **#7116 is CLOSED** (verified). That sentence is stale and
   must be rewritten, not merely trimmed.
2. `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` — the `check
   **Sentry** before concluding anything` passage. Its `## Reading the outcome` table must also gain
   the new TRANSIENT sub-causes, or the plan's `fail_loud` claim is true in `capture.log` and false
   in the read path.
3. **`scripts/followthroughs/git-data-rung2-evidence-capture.sh` itself** — the `boot_complete`
   branch ends `Check Sentry for this host_name before concluding anything.` The first draft missed
   this one entirely. Its stated rationale (*"everything before `doppler run` reaches SENTRY ONLY"*)
   is **falsified by Phase 5.2**, as is the header's *"on a SUCCESSFUL boot the only row this source
   ever receives … is boot_complete itself"*.

#### 4.7b — the stale prohibition in the file Phase 4 edits

`scripts/followthroughs/git-data-rung2-evidence-capture.sh`'s header contains
`#7116 owns that work; do not do it here.` **#7116 is closed** (verified: *"rung-2 capture reports
TRANSIENT for early-boot fatals it could read from Sentry directly"* — the same defect #7481
re-specifies after the arm was reverted). An agent executing Phase 4 opens this file and reads a
prohibition on precisely the work it was assigned, citing a closed issue. Update the header's
`WHAT THIS DOES NOT CLAIM` block in the same commit, and note in the PR body why #7116 closed with
the work reverted — a reviewer seeing #7481 re-do closed work will ask.

#### 4.8 — fixtures model the production artifact

At least one arm feeds the **real** `level:info` beacon (`git-data boot stage`,
`stage:bootcmd_start`, `WEB-PLATFORM-63`) so an arm can actually observe the row that breaks an
unfiltered query, and at least one the real fatal (`git-data LUKS stage FAILED`,
`stage:luks_open`). Synthesized to the measured schema per `cq-test-fixtures-synthesized-only`; no
live token in a fixture.

#### 4.9 — anti-vacuity

Assert the `RUNG2_CAPTURE_VERDICT=` sentinel on every new arm, raise the suite's floor (see Phase
0.2 — the floor helper migration makes this one literal, not three), and anchor the config
assertion on the **Sentry paragraph** — the old `grep -qF 'prd_terraform' "$SUT"` was satisfied by a
pre-existing Better Stack error string, so deleting the whole Sentry block left it green.

#### 4.10 — the window derivation must be exercised

An arm drives the window helper with two different apply timestamps and asserts the emitted bounds
differ; replacing the helper's body with `printf ''` must redden. The previous suite stayed 43/0
green under exactly that stub. A second arm asserts a `start=`-without-`end=` form is never emitted
(the first draft promised this in an AC and built it in no phase).

4.1 **The query.** One helper builds a single space-separated AND query — no `OR`, per the
2026-04-06 learning:
`host_name:<HOST_NAME> level:fatal`, with `project=4511404943671376` and an ISO
`start=`/`end=` **pair** derived from the apply timestamp (defect 5; `start=` alone is HTTP 400,
measured). `SENTRY_ORG` is **pinned to a literal `jikigai-eu`, not read from the environment**
— the `doppler run -c prd_terraform` wrapper exports every secret in that config, and an
env-sourced org is the defect. Closes defects 1, 5, 6.

**The complete shape was executed end-to-end at plan time, not merely composed on paper**
(`verified: 2026-09-02`). Against the real 2026-07-31 rehearsal host it returns HTTP 200 and
exactly the two fatals, with the two `info` rows and the `warning` row correctly excluded:

```
GET https://sentry.io/api/0/organizations/jikigai-eu/issues/
      ?query=host_name%3Asoleur-git-data-rehearsal-30649892865+level%3Afatal
      &start=2026-07-31T00:00:00&end=2026-08-01T00:00:00
      &project=4511404943671376&limit=5
  -> HTTP 200, 2 rows:
     WEB-PLATFORM-6B  fatal  "git-data LUKS stage FAILED"
     WEB-PLATFORM-65  fatal  "git-data cloud-init FAILED"
```

One incidental confirmation of Phase 4.4 from composing that probe: appending `curl`'s
`--write-out` text to the response body makes the whole payload unparseable
(`json.decoder.JSONDecodeError: Extra data`). The status **must** be captured with
`-o <file> -w '%{http_code}'` into a separate stream, never interleaved with the body a parser
will read — which is the concrete form of "validate shape before counting".

4.2 **The liveness anchor** (defect 2), mirroring `ANCHOR_SQL`'s existing role and its
exclude-own-host design: a second query with **no** `host_name` term over the same window,
asserting the source answers with ≥1 row. Its justification is the measured
*unknown-tag-key → 200 `[]`* case, which is the only shape that silently reads clean; org and
project drift both return 403 and are handled by 4.3.

4.3 **Four distinguished causes** (defect 4). Capture the HTTP status with `--write-out` and
keep `curl` stderr. Distinct messages, each returning TRANSIENT with `exit 2`:
`401` (credential absent or rejected — measured), `403` (org or project not accessible, i.e. the
drift case — measured), `429` (rate limited), and a transport/timeout rc with the stderr tail.
None of these is a verdict.

4.4 **Shape validation before counting** (defect 3), per the 2026-07-23 learning: parse with
`jq -e 'if type=="array" then . else error("not-an-array") end'` **before** any length is taken.
A 200 whose body is HTML or an object yields TRANSIENT, never clean. `jq -e` on `null | length`
returns 0 and exits 0 — the count must never be the first thing trusted.

4.5 **Placement at every call site** (test requirement). The Sentry consult is invoked from
**all** paths that today return TRANSIENT without a second opinion: both Better Stack credential
preflight `exit 2` sites, the anchor-zero-row path, and the `boot_complete`-missing path.
Reverting any single one of these to a bare `exit 2` must redden the suite — this is the
mutation row the previous attempt lacked, and it is why placement is asserted per site rather
than once.

4.6 **Redaction** — add `SENTRY_ISSUE_RO_TOKEN` to the workflow's redaction tuple (anchor: the
`for var in ("BETTERSTACK_QUERY_HOST",` line). The arm prints Sentry `title` and `culprit` into
a 7-day artifact on a public repo. Add an arm asserting the tuple contains the token name, so a
future arm that reads a new secret without widening the tuple reddens.

4.7 **Remove the stale eyeball instructions.** `.github/workflows/git-data-rung2-rehearsal.yml`
(anchor: `Confirm against Sentry first`) and
`knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` (anchor:
`If the poll expires without a terminal answer, check **Sentry** before concluding anything`)
both direct a human to a dashboard. Once the script consults Sentry itself these are false, and
they are `hr-no-dashboard-eyeball-pull-data-yourself` violations relocated one layer up. Replace
with a statement of what the script now consults and what its verdicts mean.

4.8 **Fixtures model the production artifact** (test requirement, and constraint 2's citation).
At least one arm feeds the **real** `level:info` beacon body — `WEB-PLATFORM-63`,
`git-data boot stage`, `stage:bootcmd_start` — so an arm can actually observe the row that
breaks an unfiltered query. At least one feeds the real fatal shape (`git-data LUKS stage
FAILED`, `stage:luks_open`). Synthesized to the measured schema per
`cq-test-fixtures-synthesized-only`; no live token in a fixture.

4.9 **Anti-vacuity.** Assert the `RUNG2_CAPTURE_VERDICT=` sentinel on **every** new arm (the
repo's own learning records sentinel deletion as a surviving mutation), raise the suite's
34-assertion floor by the number of assertions added, and add a config assertion that anchors on
the **Sentry paragraph** — the old `grep -qF 'prd_terraform' "$SUT"` was satisfied by a
pre-existing Better Stack error string, so deleting the whole Sentry block left it green.

4.10 **The window derivation must be exercised.** Add an arm that drives the helper with two
different apply timestamps and asserts the emitted `start=`/`end=` differ accordingly — replacing
the helper's body with `printf ''` must redden. The previous suite stayed 43/0 green under
exactly that stub.

### Phase 5 — #7460: bake the Better Stack ingest token (the single cloud-init edit)

Sequenced last so `cloud-init-git-data.yml` is touched **once** (constraint 1).

#### 5.0 — CRITICAL: Phase 5 breaks `HOST_SQL`'s row window, and the failure mode is PASS over an unread fatal

**This is a regression the plan introduces, found at review, and it must be fixed in the same
phase that causes it.**

`scripts/followthroughs/git-data-rung2-evidence-capture.sh`'s `HOST_SQL` ends
`ORDER BY dt DESC LIMIT 50`. That bound is safe **today only because of the channel split** —
ADR-149 states it outright: *"On a successful boot the only Better Stack row a git-data host
produces is `boot_complete` itself."* Phase 5 makes all the post-`write_files` stages emit, and the
emitter is invoked far more often than once per stage (sshd warn, mount, gc-timer, the LUKS trap,
per-stage `on_err`).

`LIMIT 50` keeps the **newest** 50 rows. An early `stage:luks_open` fatal, followed by enough later
rows, **drops out of the window**. The FAIL arm `grep -q '"level":"fatal"'` then finds nothing,
control falls through to the `boot_complete` check, and the script writes
`RUNG2_BOOT_REHEARSAL=PASS` — *the exact artifact `## User-Brand Impact` names as the failure this
whole plan exists to prevent.*

Three things follow, all in scope:

1. **The fatal query must not be row-window-bounded.** Add a separate, unlimited
   `level='fatal'` query for the host, or scope the limit per stage. A verdict that depends on how
   chatty a healthy boot happens to be is not a verdict.
2. **Phase 4's placement set must be re-derived AFTER Phase 5's coverage change, not before it.**
   This is the real contract-ordering violation in the first draft: Phase 4 consumes a row model
   that Phase 5 changes. Phase 4.5's `transient()` derivation is unaffected (it quantifies over
   `exit 2` sites), but the **PASS path** becomes a site that needs a second opinion — which is
   also what 4.5b's "Better Stack PASS + Sentry FATAL" case demands. The two findings converge on
   the same fix: the PASS path gains a Sentry cross-check.
3. **An arm must model a chatty boot.** A fixture with >50 rows where the fatal is the oldest,
   asserting FAIL. Without it this regression is invisible: every existing fixture is small.

#### 5.0b — the prior rejection is recorded in CODE, not only in the ADR

The first draft searched ADR-147's alternatives table, correctly found no "bake the ingest token"
row, and concluded this is not a previously-rejected mechanism. **True of the ADR, false of the
repo.** The rejection is written at three code sites:

- `apps/web-platform/infra/git-data-luks.tf` — *"It is NEVER baked into user_data — user_data is
  retrievable from the Hetzner metadata"*, with the reasoning that it is *"the same rationale that
  keeps the LUKS passphrase out"*.
- `apps/web-platform/infra/modules/git-data-userdata/main.tf` — *"the LUKS passphrase and the Better
  Stack INGEST token are deliberately NOT baked"*. **`main.tf` is a digest input**, so shipping this
  now-false comment puts a falsehood *inside the attested byte set*.
- `apps/web-platform/infra/cloud-init-git-data.yml` — *"an absent token skips this block, which IS
  the channel split"*.

All three must be updated in this PR. A reversal that leaves the old reasoning in place is how the
next reader concludes the reversal was an accident.

#### 5.0c — this is the SECOND instance of the pattern, and the precedent carries the review this PR owes

`apps/web-platform/infra/inngest-host.tf` **already bakes this exact variable**
(`betterstack_logs_token = var.betterstack_logs_token`) with the identical rationale — a pre-Doppler
fallback so the earliest `runcmd` can phone home — and ADR-096 records it, including the cost this
plan re-derived from scratch (rotation requires a host replace).

The comment on the line above it reads: **`(weigh before widening use)`**.

That is a forward trigger, and **this PR is the widening it anticipated**. So ADR-198 is not a
first-of-kind decision; it is the second instance of an established pattern, and its job is to
*discharge* that clause rather than re-decide the question. Cite ADR-096.

#### 5.0d — THE gap in the security argument: a `0600` secret becomes a `0755` one

**The sharpest finding of the review, and it invalidates the load-bearing claim as stated.**

The first draft's whole security argument was: *"`user_data` already bakes `doppler_token`, so
anyone who can read `user_data` can already derive the Better Stack token — the marginal access
cost is near zero."* That is true of **metadata and tfstate readers**. It is false of **on-host
readers**, and the plan never considered them. Measured:

| Secret | Where it lands on the host | Mode |
|---|---|---|
| `doppler_token` (today) | `/etc/default/git-data-doppler` | **`0600` root** — the file is `chmod 600`'d immediately, with the comment *"NOT written to world-readable /etc/environment"* |
| Better Stack ingest token (as Phase 5.2 would place it) | baked into `/usr/local/bin/git-data-emit` | **`0755` root:root — world-readable** |

The host carries a `git` account (`users: - name: git`) whose forced-command wrappers serve every
connected user's push and transport. That account **cannot** read `doppler_token`. Under Phase 5.2
as first drafted it **could** read the ingest token. That is a new exposure class, not a marginal
one, and "the marginal access cost is near zero" is simply false for it.

Three consequences, all in scope:

1. **Re-price the rejected alternative.** §Alternatives Considered dismissed *"read the ingest token
   from a baked file rather than the templatefile map"* on ~40–80 bytes of `user_data` and a
   read-ordering concern. That alternative is the one that preserves `0600` parity with
   `doppler_token`. With 20,180 B of headroom, byte cost is not the deciding axis — **mode is**.
   Prefer a `0600` root-owned env file that the emitter sources, mirroring the Doppler token's own
   treatment, unless a measured read-ordering obstacle rules it out.
2. **The `## Encryption Posture` ledger is incomplete.** It lists `user_data` and
   `terraform.tfstate` only. The on-host copy is a third store with its own mode and its own
   `does_not_defend`, and AC 33's `0 unledgered` baseline is being asserted against a store list
   that omits it.
3. **This is the substance ADR-198 must carry**, alongside 5.0c's `(weigh before widening use)`
   discharge — a bake whose on-host mode is *looser* than the credential it claims equivalence with
   is not the same decision the Inngest host made.

#### 5.0d(ii) — two further gaps in the security argument, both of which change ADR-198

- **The token is one shared value across four hosts.** `variables.tf`'s
  `betterstack_logs_token` fans out to the Inngest host's bake and its Doppler project, the zot
  registry's Doppler secret, git-data's Doppler secret, and the web host's Vector sink. The first
  draft priced the **capability** of a leak (forged rows, quota burn) and never priced the
  **remediation**: rotating after a git-data metadata leak darkens the web host's shipper and the
  registry's, and requires *both* an Inngest host replace and a git-data host replace. That
  cross-host blast radius belongs in `## User-Brand Impact`, `## Encryption Posture` and ADR-198.
- **The equivalence argument proves too much.** *"Marginal access cost ≈ 0 because `doppler_token`
  is already baked and the ingest token is derivable from it"* applies **verbatim** to
  `GIT_DATA_LUKS_KEY`, which lives in the same `prd_git_data` config — and which the repo
  deliberately keeps out (`cloud-init-git-data.yml`: *"The LUKS key is NEVER baked into this
  user_data"*). Applied consistently, the first draft's argument licenses baking the passphrase.
  ADR-198 must state the distinguishing principle as a **rule** — *derivable through a revocable
  indirection is not equivalent to directly readable and durable* — and say explicitly that it does
  **not** extend to `GIT_DATA_LUKS_KEY`. Otherwise ADR-198 becomes the precedent for the next bake.

#### 5.0e — the eight-stage correction

#7460's title says *"all nine boot stages"*. Measured: the `bootcmd` beacon is an **inline bare
`curl` to Sentry**, emitted before `write_files`, so the shared `git-data-emit` script does not
exist yet when it fires and `stage:bootcmd_start` **cannot** reach Better Stack regardless of a
baked token. Coverage widens to **eight**. Correct this in ADR-198, in `## Observability`, and
surface the issue-title correction (recorded in `decision-challenges.md` as UC-3).

5.1 Add `variable "betterstack_logs_token"` (sensitive, no default) to
`apps/web-platform/infra/modules/git-data-userdata/variables.tf`; thread it into the single
`templatefile(` map in `main.tf` as one new **brace-free, single-physical-line** entry (ADR-152's
two parser invariants); pass it from both callers — `apps/web-platform/infra/git-data.tf` (from
the existing root `var.betterstack_logs_token`) and
`apps/web-platform/infra/rung2-rehearsal/rehearsal.tf` (from its existing
`var.betterstack_logs_token`). No new root variable and no Doppler write: both roots already
have the value, measured.

5.2 In `cloud-init-git-data.yml`, at the emitter's Better Stack block (anchor:
`if [ -n "$${BETTERSTACK_LOGS_TOKEN:-}" ]; then`), fall back to the baked token when the
environment variable is absent. The env token continues to win when present, so a post-rotation
`doppler run` stage uses the fresh value.

5.3 **The new failure mode, mirrored to Sentry** (`cq-silent-fallback-must-mirror-to-sentry`).
After a Better Stack rotation, stages 1–5 ship on the stale baked token while stages 6–9 use the
fresh env token — silently darkening exactly the stages T-4 exists to cover, because the ingest
`curl` ends in `|| true`. Replace that swallow with: on ingest failure **while using the baked
token**, emit a Sentry event at `level:warning`, `stage:betterstack_ingest`, carrying which token
source was used. **Do not rename any emit `message` literal** — ADR-147 freezes them; add tags only.

Two properties this mirror must have, or it is dark in exactly the window it exists to cover:

- **The DSN must be available pre-Doppler.** Verified on disk: `sentry_dsn` is a baked
  `templatefile` argument read as `DSN='${sentry_dsn}'` at both the `bootcmd` beacon and the
  shared emitter, so the mirror reaches Sentry from the earliest boot stage with no dependency on
  Doppler or on the sink that just failed. This is ADR-147's unconditional channel, and it is the
  whole reason the mirror is worth adding.
- **The ingest path stays non-fatal.** Replacing `|| true` must not make a Better Stack ingest
  failure abort a boot stage. The emitter's exit contract is `0 delivered · 1 transient ·
  2 STRUCTURAL (no curl / no DSN)`, and **only 2 refuses a boot** — the mirror warns, it does not
  promote a second-sink failure into a boot failure. An arm asserts the emitter's rc is unchanged
  when the Better Stack POST fails.

5.4 Mirror the templatefile-map change into `apps/web-platform/infra/git-data-userdata-budget.sh`
(the deliberate hand-copy), and re-run it to record the new headroom. `git-data-render-strip-parity.test.sh`
is what keeps the two equal and must stay green.

5.5 **Residency assertion.** Add an arm to `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`
asserting `apps/web-platform/infra/git-data-luks.tf` declares a `doppler_secret` named
`BETTERSTACK_LOGS_TOKEN` in the `prd_git_data` config. This is the *"commit an assertion so a
later scope narrowing trips red"* the issue asks for, targeted at the Terraform declaration
rather than at a live config that does not exist pre-birth.

5.6 **`RUNG2_VAR_DIVERGENCE` — decided, and the decision is "do not add it".** The evidence hash
binds the template and the nine payload files; it does **not** bind `templatefile` *arguments*,
which is why `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` exists in
`tests/scripts/lib/git-data-birth-readiness-gate.sh` (anchor:
`GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST="host_name git_data_volume_id …"`). That allowlist holds
exactly the eight **identity-shaped** vars that legitimately differ between the rehearsal and
production. `betterstack_logs_token` is **not** one of them: prod and rehearsal deliberately
carry the *same* ingest token (anchor in `rung2-rehearsal/rehearsal.tf`:
`The same INGEST token prod's config holds`), exactly as the existing `sentry_dsn` and
`betterstack_ingest_url` arguments already do — and neither of those is in the allowlist either.

So the new argument must **never** appear in a `RUNG2_VAR_DIVERGENCE` declaration, and adding it
to the allowlist would be the defect: it would permit a rehearsal that shipped its stage markers
to a different sink than production while producing hash-valid evidence. Add an arm asserting the
allowlist literal is **unchanged** by this PR, so a later edit that quietly widens it reddens.

**"Not on the allowlist" is weaker than "asserted equal", and the plan says so rather than
implying otherwise.** The gate refuses *declared* divergences; nothing today asserts that the two
roots actually pass the same *value*. A value-equality assertion is not implementable in the test
suite — the value is a secret resolved at apply time, and the suite must never read it. What **is**
checkable, and what this plan adds, is **structural parity of the source expression**: an arm
asserting that `git-data.tf` and `rung2-rehearsal/rehearsal.tf` each pass their own root
`var.betterstack_logs_token` into the module, and that both root variables are declared with **no
default** (so neither can silently fall back to a different value). That is the same binding
`sentry_dsn` and `betterstack_ingest_url` already have.

The general gap — that `templatefile` *argument values* are bound by declaration rather than by
the evidence itself — is **pre-existing, not introduced here**, and it is the reason the
divergence allowlist exists at all. Closing it properly means binding render-arg values (or an
HMAC over them) into the evidence, which is a redesign of what the evidence attests and is out of
scope for a harness-repair PR. **File a deferral issue** (per `wg-when-deferring-a-capability-create-a`)
recording the gap, the two candidate mechanisms, and a re-evaluation trigger of *"before the
git-data host is born"* — the same trigger shape #7534 itself carried.

5.7 **ADR-198** (provisional ordinal): the decision, both directions of the security argument on
the time axis, and the new failure mode. It must state that `user_data` already bakes
`doppler_token` (read-only, scoped to `prd_git_data`), so anyone who can read `user_data` can
already derive the Better Stack token — **and** that this equivalence is point-in-time: revoking
`doppler_token` today closes the derivation path for every historical `terraform.tfstate`
version, whereas a baked token is directly readable and durable until Better-Stack-side
rotation, which (ForceNew, no `ignore_changes` — ADR-149 and ADR-152, **not** ADR-115) then requires host replacement. Least
privilege is confirmed: `BETTERSTACK_LOGS_TOKEN` is ingest-only; management is
`BETTERSTACK_API_TOKEN` and reads use `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}` — blast radius
of a leak is forged rows and quota burn, not log read. Coverage widens from ~1 row per successful
boot to nine; Better Stack's processor DPA is recorded PENDING at
`knowledge-base/legal/compliance-posture.md` — **link, do not duplicate**. Chapter V is not
engaged; both sinks are EU-resident.

5.8 **ADR-147 addendum** marking §"Channel split without a flag" **superseded in part**. The
invariant ADR-147 actually protects — *"a fatal never depends on Doppler to be reported"* — is
preserved and strengthened: Sentry remains unconditional from the baked DSN, and Better Stack
gains coverage it did not have. The channel split was a consequence of the constraint, not a
goal. ADR-147's alternatives table has **no** "bake the ingest token" row (A4 is the different
journald→Vector path), so this is not a previously-rejected mechanism.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/modules/git-data-userdata/variables.tf` — new `betterstack_logs_token`
  (string, `sensitive = true`, **no default**, per `hr-tf-variable-no-operator-mint-default`).
- `apps/web-platform/infra/modules/git-data-userdata/main.tf` — one new entry in the single
  `templatefile(` map, brace-free and on one physical line.
- `apps/web-platform/infra/git-data.tf` — pass `var.betterstack_logs_token` (root variable
  already exists, anchor: `"Write-only Better Stack Logs ingest token (source 2457081"`).
- `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf` — pass its existing
  `var.betterstack_logs_token`.

No new root variable. No new provider. No new Doppler secret.

### Apply path

Cloud-init only — the git-data host **has never been provisioned** (no `soleur-git-data` server
and no git-data volume of either kind exist in Hetzner; measured). There is no host to replace
and no live store to endanger. Blast radius today is zero; the change takes effect at the host's
first birth. `hcloud_server.git_data` remains outside the auto-applied `-target=` set of
`apply-web-platform-infra.yml`, so a merge does not provision it.

### Distinctness / drift safeguards

`user_data` is ForceNew with **no** `ignore_changes` (**ADR-149 and ADR-152** — ADR-115 does not say this; see Research Insights). Post-birth, any edit to this
template costs a destructive host replace — which is precisely why the edit lands **now**, before
birth, and why it is batched into one change. `RUNG2_VAR_DIVERGENCE` (Phase 5.6) is the
mechanism that keeps the rehearsal's render vars from diverging from production's.

### Vendor-tier reality check

Better Stack Logs ingest against shared source `2457081` — an existing source, already in use by
the rehearsal's scratch config. No tier gate is engaged: `betterstack_paid_tier` guards
`betteruptime_policy`/`monitor` resources, none of which this plan touches. Coverage widens from
~1 row per successful boot to nine, which is a quota consideration recorded in ADR-198, not a
tier gate.

## Observability

The harness's operator-visible surface is **layer 6** of the seven —
*"Synchronous webhook-response body / workflow-run log"* — realised here as the
`git-data-rung2-rehearsal.yml` run log, its `$GITHUB_STEP_SUMMARY`, and the **redacted**
`capture.log` artifact. Every failure path this plan adds is readable there with no SSH.

The rehearsal *host's* boot-stage failures are produced by the cloud-init emitter's direct
Sentry POST plus its Better Stack ingest. That emitter is a git-data-specific producer and is
**not** one of the seven enumerated layers — stating that plainly rather than mis-citing layer 3
(which is Vector's journald shipper on the web host, a different mechanism). Its
operator-visible read path is Sentry, and after Phase 4 the capture script reads it directly
rather than directing anyone to a dashboard.

```yaml
liveness_signal:
  what: "git-data-rung2-rehearsal.yml capture step — RUNG2_CAPTURE_VERDICT sentinel printed on every exit path by an EXIT trap, plus the Sentry liveness anchor query added in Phase 4.2"
  cadence: "per rehearsal dispatch (workflow_dispatch; capped at two per fix attempt)"
  alert_target: "GitHub Actions run conclusion + $GITHUB_STEP_SUMMARY; the Sentry fatal channel pages independently via the git-data boot emitter"
  configured_in: ".github/workflows/git-data-rung2-rehearsal.yml (capture step, anchor: RUNG2_CAPTURE_VERDICT) and scripts/followthroughs/git-data-rung2-evidence-capture.sh (anchor: trap 'printf \"RUNG2_CAPTURE_VERDICT=%s\\n\" \"$?\"' EXIT)"

error_reporting:
  destination: "Sentry org jikigai-eu, project web-platform (id 4511404943671376), via the baked DSN in cloud-init-git-data.yml; Better Stack Logs source 2457081 for the post-Doppler stages and, after Phase 5, all nine"
  fail_loud: "a non-zero RUNG2_CAPTURE_VERDICT in the run log; a FAIL line naming the stage; and — new in Phase 4.3 — a distinct TRANSIENT message per HTTP cause (401 / 403 / 429 / transport) so 'could not consult' names which channel and why"

failure_modes:
  - mode: "a rehearsal host fails before `doppler run`, so no Better Stack row exists"
    detection: "Phase 4 Sentry query host_name:<H> level:fatal, project-scoped, run-pinned start=/end= pair — read by the capture script itself, layer 6"
    alert_route: "capture step prints FAIL naming the stage; workflow conclusion fails; step summary carries the stage and rc"
  - mode: "the Sentry channel is consulted against the wrong org or project"
    detection: "measured HTTP 403 (not an empty 200) → distinct TRANSIENT message; org is a pinned literal, never read from the doppler-exported environment"
    alert_route: "capture step, layer 6"
  - mode: "a query returns HTTP 200 with a non-array body (CDN or captive-portal interstitial)"
    detection: "jq -e type-assertion before any length is taken (Phase 4.4) → TRANSIENT, never a clean bill"
    alert_route: "capture step, layer 6"
  - mode: "a query silently matches nothing because a tag key is wrong (measured: 200 + [])"
    detection: "the liveness anchor query (Phase 4.2) — zero anchor rows means dead source, not silent host"
    alert_route: "capture step, layer 6"
  - mode: "after a Better Stack rotation, stages 1-5 ship on the stale baked token and go dark"
    detection: "Phase 5.3 — the ingest failure is mirrored to Sentry at level:warning, stage:betterstack_ingest, tagged with which token source was used; Sentry does not depend on the failing sink"
    alert_route: "Sentry web-platform, the same channel the boot fatals use"
  - mode: "an upstream e2fsprogs bump moves R1's mount-class fingerprint"
    detection: "the image is digest-pinned, so CI cannot move under the suite; the follow-through freshness probe (Phase 3.5) reports the divergence with both digests named"
    alert_route: "scheduled follow-through sweeper output"
  - mode: "a test arm regresses and aborts on an unbound variable instead of printing its message"
    detection: "the D1-MUT mutation arm (Phase 1.2) fails if the predicate reaches an unset CAPTURE"
    alert_route: "infra-validation.yml / run-registered-suites.sh run log, layer 6"
  - mode: "a payload is bound in a form the evidence hash cannot see"
    detection: "the canonical-shape assertion (Phase 2.1) ABORTs the digest rather than emitting one over an incomplete set"
    alert_route: "the birth readiness gate's own abort message, printed in the dispatching workflow log, layer 6"

logs:
  where: "GitHub Actions run log for git-data-rung2-rehearsal.yml; the redacted capture.log artifact; Sentry issues in project web-platform; Better Stack Logs source 2457081"
  retention: "GitHub artifact 7 days; GitHub run logs 90 days; Sentry per plan retention; Better Stack per plan retention"

discoverability_test:
  command: "bash tests/scripts/test-git-data-rung2-evidence-capture.sh && bash tests/scripts/test-git-data-birth-readiness-gate.sh"
  expected_output: "both suites print a terminal summary line with 0 failed and an assertion count at or above their anti-vacuity floor"
```

The `discoverability_test` reads the harness's own guards with no network and no credentials —
the two suites that decide whether a dispatch can be trusted. It deliberately excludes the live
Sentry probe: that needs `SENTRY_ISSUE_RO_TOKEN`, and there is an unauthenticated substitute for
the property being verified (the stubbed arms), so no `credentials_required` declaration is
claimed.

## Encryption Posture

Detection fires: the plan edits `cloud-init-git-data.yml` and `*.tf`.

```yaml
at_rest:
  - store: "hcloud_server.git_data user_data (Hetzner-stored cloud-init payload)"
    mechanism: "plaintext-exception"
    evidence: "apps/web-platform/infra/git-data.tf — user_data is rendered by module git-data-userdata and stored by Hetzner in cleartext; it already carries doppler_token (read-only, scoped to prd_git_data) and sentry_dsn"
    defends_against: "nothing at this layer — Hetzner-side access controls and Terraform state access controls are the boundary"
    does_not_defend: "anyone with Hetzner console/API read on the server resource, or read access to any historical terraform.tfstate version in the R2 backend, reads the baked token directly"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: the git-data host has never been provisioned; no server or volume exists"
  - store: "terraform.tfstate (R2 backend) — the new templatefile argument lands in state"
    mechanism: "provider-managed:Cloudflare R2 server-side encryption"
    evidence: "the shared infra backend block in apps/web-platform/infra/; retrieved_on 2026-09-02"
    defends_against: "a raw object-store disk seizure"
    does_not_defend: "a leaked R2 access key; the AWS_ACCESS_KEY_ID/SECRET pair read from Doppler prd_terraform grants full state read"
    disclosed_as: "not-publicly-claimed"
    live_verification: "available"
in_transit:
  - connection: "git-data host -> Better Stack Logs ingest (source 2457081)"
    enforced_at: "apps/web-platform/infra/cloud-init-git-data.yml — the emitter's curl to '${betterstack_ingest_url}', an https:// endpoint"
    tls: "https, TLS 1.2+ (curl default, no --insecure)"
    cert_verification: "on"
    does_not_defend: "a leaked ingest token — forged log rows and quota burn against a shared source"
    disclosed_as: "not-publicly-claimed"
  - connection: "capture script -> Sentry issues API"
    enforced_at: "scripts/followthroughs/git-data-rung2-evidence-capture.sh — the Phase 4 curl to https://sentry.io/api/0/organizations/jikigai-eu/issues/"
    tls: "https, TLS 1.2+ (curl default)"
    cert_verification: "on"
    does_not_defend: "a leaked SENTRY_ISSUE_RO_TOKEN — event:read and org:read across the org; this is why Phase 4.6 widens the artifact redaction tuple"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "user_data is stored in cleartext by Hetzner by construction; the marginal access cost of the baked ingest token is near zero because user_data already carries doppler_token, from which the same value is derivable — but the equivalence is point-in-time, and ADR-198 records both directions"
  tracking_issue: "#7460"
  reevaluate_when: "a Better Stack ingest-token rotation is required, or the git-data host is born and user_data becomes ForceNew-expensive to change (ADR-149, ADR-152)"
  expires_on: "2026-11-30"
```

## Guard Contract

### Guard 1 — canonical module-shape assertion (#7534)

**Property.** The evidence digest is produced only when every byte that renders into git-data's
`user_data` is in the hash-input set; any binding form the extractor cannot resolve makes the
gate refuse to emit a digest rather than emit one over an incomplete set.

**Assembly.** The chokepoint is `git_data_rung2_user_data_sha256()` in
`tests/scripts/lib/git-data-birth-readiness-gate.sh`, and specifically the comment-stripped text
of `$module_tf` — the **single** text both the new assertion and `_payload_refs()` read. There is
exactly one such chokepoint because the module is the sole render of git-data's `user_data`,
called by both roots; the module's own header records why a second copy is structurally excluded.
The assertion must run **before** the payload loop, so a non-canonical form aborts before any
input is accumulated. The `sed 's/^[[:space:]]*#.*$//'` strip is shared, not duplicated: two
strips could disagree about what a comment is, which would reopen the class.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | rewrite one `file("${path.module}/../../git-data-bootstrap.sh")` as a multi-line `file(\n "…"\n)` | RED (abort naming the occurrence) |
| 2 | delete the assertion's own dispatch (make it a no-op returning 0) while leaving a non-canonical form in the fixture | RED — the arm must fail when the check does not run, not merely when it runs and passes |
| 3 | add a **second** `templatefile(` after a compliant first | RED (the exactly-one check must not stop at the first occurrence) |
| 4 | rebind one payload as `file(local.p)` | RED |
| 5 | rebind one payload as `file("${path.root}/../../git-data-gc.sh")` (the fourth, undocumented form) | RED |
| 6 | **must-PASS, non-canonical-but-permitted:** add a tenth `path.module` payload binding | GREEN, and the digest must **move** when that payload's bytes change |
| 7 | **harness row:** delete arm `A13` from the suite's arm registry | RED via the assertion-count floor — a suite that silently runs fewer arms must not report green |
| 8 | **must-PASS, value-form:** add a **value-form** map entry (`foo = var.foo`) — the exact shape Phase 5.1 adds | GREEN — the gate quantifies over `file*(` occurrences and `templatefile(` count, not over map arity. This row is what stops Phase 5 from tripping Phase 2, and what stops a future maintainer from "fixing" it by loosening the file-form rule. |

### Guard 2 — base-image digest pin (#7544)

**Property.** Every container the rehearsal suite spins is the same immutable image across runs,
so a fingerprint change is attributable to the repo and never to an upstream tag move.

**Assembly.** The chokepoint is the single `UBUNTU_BASE` literal in
`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`, and the assembly is **every**
`docker run` invocation in that file — six live spin sites today (inside `run_case`; two
standalone; inside `_s1_run`; R1's; R4's), which is why the guard derives them rather than
enumerating them. Members drift; the invocation verb does not.
**The derivation must be the file's own** — `grep -cE '^[[:space:]]*docker run --rm'` (= 6), which
that file already publishes alongside a written history of this count being wrong three ways. A
bare `grep -c 'docker run'` matches 13 (prose included) and a `docker run.*@sha256:` form matches 0
(the image sits on a continuation line, and after Phase 3.2 it is a variable). The guard therefore
asserts the **site count** from the anchored form and, separately, that no bare `ubuntu:24.04`
survives outside the `UBUNTU_BASE` literal and comments.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | revert any one `"$UBUNTU_BASE"` back to a bare `ubuntu:24.04` | RED |
| 2 | make the guard's own grep match nothing (rename the sought token) so it reports zero spins checked | RED via the `≥ 6` floor — a guard reporting "0 checked" and exiting 0 is vacuous |
| 3 | add a **seventh** `docker run` using a bare tag, after six compliant ones | RED (the check must not stop at the first spin) |
| 4 | pin using the **platform-specific** digest (`sha256:1e0a86e5…`) instead of the manifest list | RED — but **offline**, a digest literal is opaque: the suite cannot tell an index digest from a platform one without a registry call. The offline arm therefore asserts (a) the known-wrong `sha256:1e0a86e5…` is absent and (b) the `UBUNTU_BASE` comment records `image.index` as the observed media type. The *live* index-vs-platform check lives in the freshness probe (Phase 3.5), which is the component that legitimately has network. Stating this bound is the point — an arm that claimed to verify the media type offline would be asserting something it cannot see. |
| 5 | **must-PASS, not the canonical value:** bump `UBUNTU_BASE` to a different valid tag+manifest-list-digest pair | GREEN — the guard binds the *shape*, not one literal |

### Guard 3 — Sentry second-channel verdict arms (#7481)

**Property.** The capture script returns FAIL only when the rehearsal host actually reported a
fatal, returns TRANSIENT with a named cause whenever it could not read a channel, and never
reports a clean bill from a query it could not verify was answered.

**Assembly.** The chokepoint is the Sentry consult helper in
`scripts/followthroughs/git-data-rung2-evidence-capture.sh`, but the property quantifies over
**every call site that today returns TRANSIENT without a second opinion** — and there are four,
not one: the two Better Stack credential preflight `exit 2` sites, the anchor-zero-row path, and
the `boot_complete`-missing path. Scoping the guard to the helper alone is exactly the defect the
previous attempt shipped: reverting the arm to `exit 2` at both transport-failure sites left the
suite 43/0 green. Placement is therefore asserted **per site**.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove `level:fatal` from the query so the `level:info` bootcmd beacon matches | RED — this is the false-FAIL that would burn a paid dispatch on every healthy boot |
| 2 | replace `_sentry_stats_period` (the window helper) body with `printf ''` | RED — the previous suite stayed 43/0 green under exactly this stub |
| 3 | revert the consult at **one** of the four call sites to a bare `exit 2`, leaving three compliant | RED (per-site placement; the check must not stop at the first) |
| 4 | delete the `RUNG2_CAPTURE_VERDICT=` sentinel assertion from one arm | RED via the assertion-count floor — sentinel deletion is a recorded surviving mutation |
| 5 | return HTTP 200 with an HTML body from a stub | RED unless the arm reports TRANSIENT (never clean) |
| 6 | source `SENTRY_ORG` from the environment instead of the pinned literal, and set it to `jikigai` in the stub env | RED — measured to produce 403, which must be a named TRANSIENT cause, not a verdict |
| 7 | delete the whole Sentry block from the script | RED — the config assertion must anchor on the **Sentry paragraph**, not on a `prd_terraform` substring a pre-existing Better Stack error string already satisfies |
| 8 | **must-PASS, not the canonical fixture:** a host with fatals whose issue titles differ from the 2026-07-31 ones | GREEN with FAIL — the arm binds `level` and `stage` tags, not title text |
| 9 | **harness row:** stub the query helper to return the fixture regardless of the query string | RED — at least one arm must assert the *query* it built, not only the response it got |

### Guard 4 — D1 attribution (#7570)

**Property.** When the emitter regresses such that a 3-arg call dies at the `shift`, arm D1
prints D1's own failure message.

**Assembly.** The single call site at the `D1: a 3-arg call died at the shift` message, plus the
`CAPTURE` initialisation among the harness's top-level state. The two are one property: the
predicate is reachable only in the failing direction, so the initialisation is what makes the
message reachable at all.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | restore the unguarded `[ -s "$CAPTURE" ]` and remove the `CAPTURE=""` initialisation, then run the mutated emitter | RED — and the failure text must be D1's own, not `CAPTURE: unbound variable` |
| 2 | delete the `D1-MUT` arm's dispatch so it never invokes the mutated emitter | RED via the assertion-count floor |
| 3 | make the mutated emitter exit 2 **and** write a non-empty capture file (so the `||` right operand is true) | GREEN — **only under Phase 1.1 option (a)**. Under option (b) this row does not exist and must be struck: with `CAPTURE` empty at D1 the right operand is permanently false and the row is unsatisfiable. The first draft carried this row while proposing the fix that kills it. |

## Acceptance Criteria

### Pre-merge (PR)

**#7570**

1. `grep -c 'CAPTURE=""' apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` ≥ 1, and the
   D1 predicate reads `${CAPTURE:-}`.
2. `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` terminates with `0 failed`
   and an assertion count **greater** than the Phase 0.1 baseline (the new `D1-MUT` arm).
3. Guard 4 mutation row 1 executed and recorded: with the fix reverted, the suite's output
   contains `unbound variable`; with the fix applied, it contains D1's own message. Both
   outputs pasted into the PR body.

**#7534**

4. `bash tests/scripts/test-git-data-birth-readiness-gate.sh` → `0 failed`, arm count ≥ 16,
   and the `anti-vacuity floor:` line reports a floor **above** the measured baseline of 69.
5. Guard 1 mutation rows 1, 3, 4, 5 each executed against a synthesized tree and each observed
   RED; row 6 observed GREEN **with a moved digest**. Results tabulated in the PR body.
6. Guard 1 mutation row 2 (own-dispatch) executed and observed RED.
7. The extractor's `THE HONEST BOUND` comment names all **four** forms, including the
   non-`path.module` literal.

**#7544**

8. Every spin is pinned, asserted with **the file's own published derivation**, not a new count:
   `grep -cE '^[[:space:]]*docker run --rm' apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`
   = **6** (the site count the file already documents), and `grep -c 'ubuntu:24\.04'` outside the
   `UBUNTU_BASE` literal's own line and outside comments = **0**.
   **The first draft's form was arithmetically unsatisfiable** and was caught by four reviewers:
   every spin is written `docker run --rm \` with the image on a *continuation* line, so
   `grep -c 'docker run.*@sha256:'` returns 0 by construction; and after Phase 3.2 the image is
   `"$UBUNTU_BASE"`, a variable, so no digest is textually present at any spin site. The bare
   `grep -c 'docker run'` returns **13** (6 spins + 7 prose/comment lines). The file already carries
   a comment recording that this exact count has been wrong three separate ways — *"the drift here
   was never a miscount, it was two measures sharing one number"* — and publishes the anchored form
   used above. This AC was very nearly the fourth instance.
9. The `UBUNTU_BASE` comment records the media type observed when the digest was resolved
   (`application/vnd.oci.image.index.v1+json` — an OCI **index**, i.e. the manifest list) and the
   exact producing command; and the platform-specific digest `sha256:1e0a86e5…` does **not**
   appear anywhere in the file. Both halves are greps over committed text, deterministic and
   offline — the live `docker buildx imagetools inspect` is a **Phase 0.4 measurement**, not an
   acceptance criterion, because Docker Hub availability is ambient state this diff does not
   control (`cq-ac-must-not-depend-on-concurrent-sessions`).
10. R1's failure detail names the pinned digest and the `mke2fs` version measured inside it.
11. `.github/workflows/rule-audit.yml` contains an `ubuntu:24.04` staleness case that sources the
    pin from `UBUNTU_BASE` (asserted by grep), and `actionlint` passes on the workflow. The live
    comparison's own outcome is **not** an AC — an upstream tag move between authoring and CI would
    flip it without a line of the diff changing, which measures Docker Hub rather than this change
    (`cq-ac-must-not-depend-on-concurrent-sessions`).
12. **No** `scripts/followthroughs/ubuntu-base-digest-freshness-7544.*` file exists, and #7544
    carries no `soleur:followthrough` directive — the first draft's mechanism was cut at review
    because the sweeper would have closed the tracker on its first clean run.

**#7481**

13. `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` → `0 failed`; assertion floor
    raised from 34 by exactly the number of assertions added, and the floor literal updated in
    the same commit.
14. Every Guard 3 mutation row 1–7 and 9 executed and observed RED; row 8 observed GREEN.
    Tabulated in the PR body with the command run for each.
15. The org is a pinned literal, never environment-sourced. Assert it as **presence of the
    guardrail plus absence of the expansion**, not as absence of the bare token:
    `grep -c 'jikigai-eu' scripts/followthroughs/git-data-rung2-evidence-capture.sh` ≥ 1, and
    `grep -cE '\$\{?SENTRY_ORG' …` = 0.
    **A bare `grep -c 'SENTRY_ORG' … = 0` is the wrong instrument** — the script's own comment
    must explain *why* `SENTRY_ORG` is deliberately not read (that explanation is the thing a
    future maintainer needs), and a comment naming the variable would false-fail the bare grep.
    Anchoring on the `$`-expansion distinguishes "the script explains the hazard" from "the
    script has the hazard" (the #6039 self-reference class).
16. The Sentry query carries `project=4511404943671376`, a `level:fatal` term, and an ISO
    `start=`/`end=` **pair**; an arm asserts a `start=`-only form is never emitted.
17. `grep -c 'SENTRY_ISSUE_RO_TOKEN' .github/workflows/git-data-rung2-rehearsal.yml` ≥ 1 inside
    the redaction tuple, and an arm asserts the tuple contains it.
18. Neither `.github/workflows/git-data-rung2-rehearsal.yml` nor
    `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` contains
    `Confirm against Sentry first`; the runbook passage at the `check **Sentry** before
    concluding anything` anchor is replaced with a statement of what the script now consults.
19. At least one arm's fixture body reproduces the measured production beacon
    (`git-data boot stage`, `level:info`, `stage:bootcmd_start`) and at least one the measured
    fatal (`git-data LUKS stage FAILED`, `stage:luks_open`).
20. `python3 scripts/lint-guard-contract.py` (or the repo's current invocation) passes over this
    plan's `## Guard Contract`.

**#7460**

21. `bash apps/web-platform/infra/git-data-userdata-budget.sh` reports `stored` below the 32,768 B
    cap with headroom recorded in the PR body (baseline 20,180 B).
22. `bash apps/web-platform/infra/git-data-render-strip-parity.test.sh` → `0 failed` (the
    hand-mirrored map in the budget script matches the module).
23. `cd apps/web-platform/infra && terraform validate` passes for the root, and
    `cd apps/web-platform/infra/rung2-rehearsal && terraform validate` passes.
24. `git rev-list --count origin/main..HEAD -- apps/web-platform/infra/cloud-init-git-data.yml`
    returns exactly `1` — the template was touched in **one** commit, not five. This is
    constraint 1's batching requirement.
    **Note the command shape is load-bearing:** `git diff --stat origin/main...HEAD -- <path>`
    is a *union* diff and carries no per-commit information at all (measured: it returns empty
    on an unchanged file and a single stat line on a changed one, regardless of how many commits
    touched it), so it cannot distinguish one commit from five and would pass a batching
    violation silently. Same class as the `git log -- A B` union trap already in the plan skill's
    Sharp Edges.
25. `grep -c 'BETTERSTACK_LOGS_TOKEN' apps/web-platform/infra/git-data-luks.tf` ≥ 1 **and** the
    new residency arm in `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` passes;
    deleting that `doppler_secret` block turns the arm RED (recorded).
26. The ingest-failure Sentry mirror exists at the emitter's Better Stack block and no emit
    `message` literal changed (`git diff origin/main...HEAD -- apps/web-platform/infra/cloud-init-git-data.yml`
    contains no change to any of ADR-147's four frozen literals).
26a. `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` in `tests/scripts/lib/git-data-birth-readiness-gate.sh`
    is **byte-identical** to `origin/main` — `betterstack_logs_token` was not added — and the new
    arm asserting that turns RED when the token name is appended to it.
26b. The render-arg parity arm passes: both roots pass their own `var.betterstack_logs_token`
    into the module and both root variables are declared with **no default**. Removing either
    call site, or adding a default to either variable, turns it RED.
26c. An arm asserts the emitter's exit code is **unchanged** when the Better Stack POST fails —
    the mirror warns, it never promotes a second-sink failure to a boot failure (`only 2 refuses
    a boot`).
26d. A deferral issue exists for the render-arg value-binding gap (§Phase 5.6), carrying the two
    candidate mechanisms and the re-evaluation trigger *"before the git-data host is born"*, and
    is linked from this PR body.
27. `knowledge-base/engineering/architecture/decisions/ADR-198-*.md` exists, carries both
    directions of the time-axis security argument, links (does not duplicate) the PENDING
    Better Stack DPA entry in `knowledge-base/legal/compliance-posture.md`, and its ordinal was
    re-derived across all `origin/*` refs after the final rebase.
28. ADR-147 carries an addendum marking §"Channel split without a flag" superseded in part, with
    the preserved invariant restated.

**Cross-cutting**

29. `bash scripts/test-all.sh` (or the shards the diff touches, with the full battery at
    `/ship` Phase 4 per ADR-183) → `0 failed`.
30. `bash apps/web-platform/infra/run-registered-suites.sh` → `0 failed`.
31. `bash scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` → `0 failed`, with its
    `TERMINAL_LINE` fixture updated to the new count.
32. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` → OK (run the
    gate's **own** invocation, not a hand-enumerated path list — `2026-07-28` learning).
33. `python3 scripts/lint-encryption-posture.py --repo-sweep` → `PASS` with `0 unledgered`
    and `0 failing checks` — the gate's **own** CI invocation (`ci.yml`, anchor:
    `run: python3 scripts/lint-encryption-posture.py --repo-sweep`), not a hand-passed path
    list. Measured at plan time on `main`: `17 stores, 5 connections, 0 unledgered,
    0 failing checks -> PASS`, so any new unledgered store introduced by Phase 5 shows as a
    delta against that baseline.
34. Every `knowledge-base/` path cited in this plan resolves:
    `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN {}'`
    prints nothing.
35. The PR body carries `Closes #7570`, `Closes #7534`, `Closes #7544`, `Closes #7481`,
    `Closes #7460`.

### Post-merge

36. **No rehearsal dispatch in this run.** The next dispatch is a separate, operator-chosen
    action; this PR only makes its verdict trustworthy. `apps/web-platform/infra/git-data-rung2-boot-evidence.env`
    remains absent, so the birth gate continues to refuse — which is the correct state until a
    rehearsal produces evidence against the **post-#7460** template.

## Risks & Mitigations

**R1 — editing the hash-bound template invalidates evidence.** It does not, today: no evidence
file exists, and the git-data host has never been born. The stronger point is the inverse — if
#7460 is deferred, the next rehearsal attests template A, #7460 then edits to template B, and a
**second** paid dispatch is required to re-attest. Doing it now costs zero dispatches; deferring
it costs one. This is the argument for including #7460 rather than sequencing it out.

**R2 — five issues in one PR is a large blast radius.** Mitigated by dependency-ordered phases
that are independently revertible: Phases 1–4 touch no Terraform and no cloud-init; Phase 5 is a
single template edit. If Phase 5 must be dropped at review, Phases 1–4 still close four issues
and the plan says so rather than failing as a unit.

**R3 — #7481 and #7460 look redundant.** They are defense-in-depth and the load-bearing
sub-value of each must be named (per `2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate`).
#7460 widens the **primary** channel but its coverage depends on the baked token being valid and
on ingest succeeding from a pre-Doppler network state. #7481 adds an **independent** channel that
covers the two Better-Stack-unavailable preflight paths — which #7460 cannot reach — and reads
the channel ADR-147 makes structurally unconditional. Ordering matters: #7481 is built and tested
against the world it was specified for (stages 1–5 Sentry-only) *before* #7460 widens it, so the
arm is not designed against a fallback that has already stopped being the common path.

**R4 — the Sentry issue-group aggregation residual.** `host_name:H level:fatal` returns issue
groups, and the probes could not prove the AND is event-scoped. The structural argument (ADR-147
freezes per-severity message literals, so groups are level-homogeneous) is stated in the plan and
must be restated in the script's comment, not assumed. If a future emit adds a severity to an
existing message literal, this bound breaks — which is one more reason ADR-147's freeze is
load-bearing rather than stylistic.

**R5 — assertion-count floors going loose.** Every phase raises a floor literal. A phase that
adds arms without raising its floor leaves the suite tolerating a silently-deleted arm. AC 4, 13
and 31 pin this, and Guard 1 row 7 / Guard 3 row 4 / Guard 4 row 2 each mutate the harness rather
than the system under test — because a matrix that mutates only the SUT cannot see a vacuous
harness (`2026-08-13` learning).

**R6 — the plan's own ADR ordinal is provisional.** ADR-198 was free across all 65 `origin/*`
refs at plan time (**corrected at review**: the first draft said "6,518", which was
`git ls-remote --refs | wc -l` — a count dominated by ~2,981 tags. `git for-each-ref
refs/remotes/origin | wc -l` = 65. The conclusion held; the evidence base was off by two orders of
magnitude, in a plan whose whole rhetorical mode is "measured". Recorded rather than quietly
patched); siblings claim ordinals mid-pipeline (ADR-197 was claimed on a ref but not on
`main`). Re-derive before merge, and if it moves, sweep this plan, `tasks.md`, and AC 27 for the
old ordinal in the same edit.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **#7534 via HCL parsing** (`hcl2json` or `terraform console`) | Adds a binary dependency and a "parser absent" fail-mode to a fail-closed bash gate, and still cannot resolve `file(local.p)` without *evaluating* the module. The canonical-shape assertion buys the same property — a digest is emitted only over a complete set — with zero new dependencies. See §Design Call 1. |
| **#7534: leave the extractor as-is and only document the fourth form** | The issue's re-eval trigger has fired; the digest now gates a real birth. Documenting a fail-open is not closing it. |
| **#7544 via Dockerfile + Dependabot** | The Dockerfile is #7535's deliverable and #7535 is OPEN; the issue explicitly says not to do both at once. A follow-through freshness probe buys the same property without pre-empting #7535. See §Design Call 2. |
| **#7544: refresh the R1 fixture wholesale when the pin bumps** | The suite's own comment forbids it — *"the point is the classification, not the diff."* The pin makes drift attributable; classification stays manual and deliberate. |
| **#7481: read Sentry only on the `boot_complete`-missing path** | This is what the reverted attempt effectively did, and it left the suite 43/0 green with the arm removed from both transport-failure sites. Placement at all four sites is the property. |
| **#7481: keep the `statsPeriod` rolling window** | `host_name` embeds the run id, which is stable across GitHub re-run **attempts**, so attempt 2 of a fixed host would see attempt 1's fatal. Run-pinned `start=`/`end=` is required — and must be a pair, measured. |
| **#7460: defer until after a clean rehearsal** | Costs an extra paid dispatch (see R1) and leaves stages 1–5 dark for the rehearsal that is supposed to prove the template. |
| **#7460: read the ingest token from a baked file rather than the templatefile map** | Another `write_files` entry costs more `user_data` bytes than one map argument and adds a read-ordering dependency in the emitter, which runs from `bootcmd` before `write_files` on the earliest stage. |

## Plan Review Revisions (R1–R24)

A seven-agent panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO, CPO)
plus a scoped strong-model advisor reviewed the first draft. **Every finding below was verified
against the tree before being applied** — none is taken on the reviewer's word. The first draft's
research was strong; its *instruments* were not, and three of them could not have fired.

### Applied

| # | Finding | Corrected in |
|---|---|---|
| R1 | **Guard 3's site set was 4; there are 6** — and the two missed (`the Better Stack query transport exited …`, `the host-rows query exited …`) are the two the plan itself cited as the previous regression. The enumeration and its own justification named different pairs. | §4.5 — now **derives** the set over every `exit 2` with a floor, excluding the derivation fault by name |
| R2 | **AC 8 / `R1-PIN` could not pass.** Spins are `docker run --rm \` continuations, so `docker run.*@sha256:` matches 0; bare `docker run` matches 13 including prose. The file already publishes the correct anchored derivation *and* a history of this count being wrong three ways. | AC 8, Guard 2 §Assembly |
| R3 | **The #7544 freshness probe would have closed its own tracker.** The sweeper closes on exit 0. | §Design Call 2, §3.5, AC 11/12 — replaced by a case in `rule-audit.yml` |
| R4 | **Phase 4 rebuilt a reader the repo already has.** `fresh-host-boot-trail.sh` implements 4 of 5 mechanisms in production and uses the **events** endpoint, dissolving the issue-group residual the first draft documented and could not close. | §4.0 — reuse, do not re-implement |
| R5 | **Phase 5 breaks `HOST_SQL`'s `LIMIT 50`** → an early fatal can drop out of the window → **PASS written over an unread fatal**, the exact artifact §User-Brand Impact names. | §5.0 |
| R6 | **A `0600` secret becomes a `0755` one.** `doppler_token` is `chmod 600`; `git-data-emit` is `0755`, readable by the `git` account that serves users' pushes. The equivalence argument covered metadata readers, not on-host ones. | §5.0d |
| R7 | **ADR-115 does not say what it was cited for.** `grep -c ForceNew` = 0 in ADR-115, 1 in ADR-149, 2 in ADR-152. Propagated to four places from the brief without checking. | 4 citations corrected |
| R8 | **The prior rejection is in CODE, not the ADR** — three sites, one of them (`main.tf`) a digest input, so the stale comment would ship *inside the attested byte set*. | §5.0b |
| R9 | **This is the SECOND instance, not the first.** `inngest-host.tf` already bakes this variable, ADR-096 records it, and its comment reads `(weigh before widening use)` — a forward trigger this PR is the widening of. | §5.0c |
| R10 | **The token is one shared value across four hosts**; the first draft priced the leak's capability, never its cross-host remediation. | §5.0d(ii), §User-Brand Impact |
| R11 | **The equivalence argument proves too much** — it licenses baking `GIT_DATA_LUKS_KEY`, which the repo deliberately excludes. | §5.0d(ii); ADR-198 must state the distinguishing rule |
| R12 | **Design Call 1's counting rule aborted the shipped tree.** Naive `file`-family count = 10 (counts `templatefile(`), boundary-aware = 9, resolved = 9. The prose dropped the extractor's `(^\|[^A-Za-z])` boundary. | §Design Call 1 clause 2 |
| R13 | **Guard 4 row 3 was unsatisfiable** — with `CAPTURE=""` the `\|\|` right operand is permanently false; and `${CAPTURE:-}` alone does the work, not the init. | §1.1, Guard 4 row 3 |
| R14 | **Phase 0.1's baseline was a stale fixture.** Quoted `44/0/2 (46)`; the suite hard-exits below **69** and `_SKIP_CEILING=7`. Measured this session: `69 passed, 0 failed, Skipped: 0`. | §0.1 |
| R15 | **Four floors, not two** — the runcmd suite (69) and the rung-2 rehearsal suite (71) also gain arms and were never named. | §0.1 |
| R16 | **"6,518 origin refs"** was `ls-remote \| wc -l`, dominated by ~2,981 tags. Real count: **65**. Conclusion (ADR-198 free) held; the evidence base did not. | §Premise Validation, R6 |
| R17 | **Phase 4.7 would have deleted the two-dispatch cap** — line 405 carries the cap, `DO NOT simply re-dispatch`, the artifact pointer and the #7025 banner, and the only statement of the cap in the repo. It also asserts #7116 mis-reports, and **#7116 is CLOSED**. | §4.7 |
| R18 | **A third eyeball instruction survives**, inside the capture script itself, and its rationale is falsified by Phase 5.2. | §4.7 |
| R19 | **A stale prohibition sits in the file Phase 4 edits**: `#7116 owns that work; do not do it here` — on a closed issue, telling an agent not to do its assignment. | §4.7b |
| R20 | **401/403 are deterministic but were returned as retryable**, burning the 16-minute poll on a paid host; and the enumeration invented a `429` arm for an unmeasured status while omitting the **400** the plan measured itself producing. | §4.3 |
| R21 | **The anchor would false-TRANSIENT or self-satisfy** — a run-pinned minutes-long window in a one-project org, and no projection constraint on a public artifact. | §4.2 |
| R22 | **Three verdicts were undefined**: a Sentry-derived FAIL's exit code, silent-both, and Better-Stack-PASS + Sentry-FATAL (which writes PASS today). | §4.5b |
| R23 | **Coverage is eight stages, not nine** — the `bootcmd` beacon predates `write_files`, so it cannot reach Better Stack with any token. | §5.0e, UC-3 |
| R24 | **#6588 is the strongest threshold justification** and was absent; the exposure list was by surface, not by role. | §User-Brand Impact |

### Carried into `/deepen-plan` and `/work`, not yet folded

These are recorded so they are not lost. They need per-section work rather than a paragraph:

- **AC de-duplication.** The same ~25 mutations appear three times (Guard Contract, ACs 3/5/6/14, §Test Scenarios). Three representations, three places to drift. The Guard Contract matrices are the right home; the ACs should reference them. DHH additionally identified ACs 3/5/6/14/29/36 and parts of 13/21/26 as encoding no checkable post-condition — AC 36 in particular is a scope statement and belongs in Non-Goals.
- **Guard Contract row consolidation.** Guard 1 rows 1/4/5 are one predicate stated three times; rows 7 / G3-4 / G4-2 are three copies of "the floor works"; G2 rows 1 and 3 are one predicate from two directions. ~14 rows carries the same coverage as 25.
- **AC 26 / Test Scenario 23 are paper.** ADR-147's four frozen literals are the **web host's** and appear nowhere in `cloud-init-git-data.yml`, so the check is vacuously true; and `git-data cloud-init FAILED` exists nowhere in the repo (it is a historical Sentry group), so it cannot carry the level-homogeneity argument. The real freeze is the R3(3b)(iv) set-equality in the runcmd suite — retarget or drop both.
- **Phase 5.3's mirror shape is undefined.** The Better Stack block is *inside* `git-data-emit`, so the mirror cannot call it (recursion on its own failing sink) and must be a second inline `curl` duplicating `KEY`/`SHOST`/`PROJ`/`BODY` — materially more than the 40–80 bytes the headroom argument budgets, and it must satisfy the runcmd suite's emit-site analyzer (guarded detail source, pairwise-distinct arg-4 names, no `cloud-init-output.log`). The sibling `cloud-init-inngest.yml` solved the stale-token mode differently — a boot-time Doppler **re-fetch** — and that alternative is absent from §Alternatives Considered.
- **`git-data-rung2-rehearsal.test.sh` pins the module's complete input surface** with `==` over an 11-name list. Phase 5.1 turns it RED until spliced to 12.
- **`git-data-template-strip.test.sh` constrains Phase 5.2's edit shape** — `${betterstack_logs_token}` must not start a line.
- **`ignore_changes = [value]` on the prod Doppler secret** permits prod stages 1–5 and 6–9 to use *different tokens by construction*, not merely after a rotation race. The stale-token failure mode's stated cause understates the mechanism.
- **The defense-in-depth learning wants an inline comment at each call site**, not a §Risks paragraph — and R3's *ordering* argument should be deleted: same-PR sequencing buys the ordering but not the independent verification.
- **Collapse Phase 5.5 / 5.6 / AC 26b into existing arms.** The residency fact is already asserted in three places; the allowlist guard is one token added to the existing `_pin` loop (and the first draft's byte-identical-to-`origin/main` form is the tautology this repo already deleted once — *"THE TAUTOLOGY IS GONE"*); arm 7c already covers expression parity, leaving only the no-default check.
- **Mechanize or explicitly defer the two-dispatch cap.** After R17 it survives only as prose. The existing `Validate dispatch inputs` step is the natural home, `gh run list` is an established gate pattern in six workflows, and the plan's entire value proposition is the dispatch budget.
- **Migrate the hand-rolled floors to `tests/scripts/lib/gate-suite-harness.sh`** (`gate_assert_ran <observed> <floor>`, already used by 14 suites) before raising them — 3 literals per floor becomes 1.
- **Every new TRANSIENT cause needs a `**Next:**` action clause**, matching the voice of the four existing verdict blocks. A distinct message is a diagnosis; the operator needs an action, and for all of these it is "do not re-dispatch".
- **The `plaintext-exception` block has no mechanical enforcer** — `hcloud_server` is in the ledger's `non_store_types`, so its `expires_on` will never fire.

## Open Code-Review Overlap

One open `code-review` issue names a file this plan edits:

- **#7098** — *ci: audit the 56 `run:` bodies whose `set` omits `-e` against GitHub's inherited
  `bash -e`, then shape the lint* — names
  `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`.
  **Disposition: acknowledge.** #7098 is a repo-wide audit of workflow `run:` bodies and their
  `set -e` inheritance; this plan touches that file only to add a Terraform-declaration residency
  arm (Phase 5.5). The concerns do not intersect, the file is not rewritten, and folding a 56-site
  audit into a five-issue harness PR would make both unreviewable. #7098 stays open.

No other open `code-review` issue names any planned edit path. **Re-run at review** against the
full 17-path manifest (the first draft scanned 11, five short of its own Files-to-Edit table —
found by DHH), over 63 open `code-review` issues. #7098 is the only hit, on the same file.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure and test-harness change on a pre-birth surface. The single
architectural decision (baking an ingest token into a ForceNew `user_data` template, reversing
part of ADR-147's channel split) is captured as a plan deliverable in §Architecture Decision
below, not deferred. No product, legal, finance, marketing, sales, support or operations surface
is engaged: there is no UI, no user-facing copy, no pricing or contractual change, and the
regulated-data question is confined to the log-volume widening already recorded against Better
Stack's PENDING processor DPA, which ADR-198 links rather than duplicates.

No UI surface appears in `## Files to Edit` or `## Files to Create`, so the mechanical
UI-surface override does not fire and the Product/UX Gate is `NONE`.

No `spec.md` exists for this branch, so it carries no `lane:` — defaulted to `cross-domain`
(TR2 fail-closed). This widens the review fan-out rather than narrowing it, which at
`single-user incident` threshold is the correct direction to fail.

## Architecture Decision (ADR/C4)

### ADR

- **ADR-198 (new, provisional ordinal — re-derive before merge).** *Baking the Better Stack
  ingest token into git-data's `user_data`.* Records the decision, both directions of the
  security argument on the time axis (marginal access cost near zero today because
  `doppler_token` already yields the same value; durability and rotation cost are not
  equivalent), the new stale-token failure mode and its Sentry mirror, the least-privilege
  confirmation, and the quota/DPA note. Delivered in this PR (Phase 5.7).
- **ADR-147 addendum.** §"Channel split without a flag" marked **superseded in part**. The
  invariant it protects — *a fatal never depends on Doppler to be reported* — is preserved and
  strengthened; the split was a consequence of the constraint, not a goal. ADR-147's alternatives
  table has no "bake the ingest token" row, so this is not a previously-rejected mechanism.
  Delivered in this PR (Phase 5.8).

### C4 views

**No C4 impact**, and here is what was checked against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` rather than a
keyword grep:

- **External human actors** — none added or changed. The rehearsal is dispatched by the same
  operator role already modelled; no new correspondent, reviewer or recipient enters the system.
- **External systems / vendors** — Sentry and Better Stack are both **already** external systems
  in the model (they are existing sinks for the platform's telemetry). This plan adds no new
  vendor: the Sentry read uses an existing token against an existing org, and the Better Stack
  ingest uses the existing shared source `2457081`. The direction of the Sentry edge for the
  git-data host is a *read* the capture script performs — but the capture script is a CI-side
  consumer, and the model does not decompose CI job internals.
- **Containers / data stores** — none added. `hcloud_server.git_data` and its two volumes are
  already modelled as the git-data store; this plan provisions nothing new and the host remains
  unborn.
- **Actor↔surface access relationships** — unchanged. No ownership, tenancy or sharing boundary
  moves; the git-data store's access model (transport / provision / remove forced-command keys)
  is untouched.

The only element description this change could falsify would be one asserting that git-data's
early boot stages reach Sentry *only* — no such description exists in the three model files.

### Sequencing

Both ADRs are authored in this PR at `status: accepted`. Neither is soak-gated: the decision is
true the moment the template renders with the baked token, which is at merge, not at a later
host birth.

## Files to Edit

| Path | Issue | Change |
|---|---|---|
| `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` | 7570, 7544 | `CAPTURE=""` init + `${CAPTURE:-}` read + `D1-MUT` arm; `UBUNTU_BASE` literal + 6 spin sites + `R1-PIN` arm + R1 detail |
| `tests/scripts/lib/git-data-birth-readiness-gate.sh` | 7534 | canonical-shape assertion before the payload loop; comment block updated with the fourth form |
| `tests/scripts/test-git-data-birth-readiness-gate.sh` | 7534 | arms `A12`–`A16`; assertion floor raised |
| `scripts/followthroughs/git-data-rung2-evidence-capture.sh` | 7481 | Sentry consult helper; per-site placement at four call sites; shape validation; four distinguished causes |
| `tests/scripts/test-git-data-rung2-evidence-capture.sh` | 7481 | new arms + production-artifact fixtures; anti-vacuity floor raised from 34 |
| `.github/workflows/git-data-rung2-rehearsal.yml` | 7481 | redaction tuple + remove the "Confirm against Sentry first" instruction |
| `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` | 7481 | replace the dashboard-eyeball passage with what the script consults |
| `apps/web-platform/infra/cloud-init-git-data.yml` | 7460 | **ONE edit**: baked-token fallback + ingest-failure Sentry mirror |
| `apps/web-platform/infra/modules/git-data-userdata/variables.tf` | 7460 | new `betterstack_logs_token` variable |
| `apps/web-platform/infra/modules/git-data-userdata/main.tf` | 7460 | one new templatefile map entry |
| `apps/web-platform/infra/git-data.tf` | 7460 | pass the existing root variable |
| `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf` | 7460 | pass its existing variable |
| `apps/web-platform/infra/git-data-userdata-budget.sh` | 7460 | mirror the map change |
| `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` | 7460 | residency arm + `RUNG2_VAR_DIVERGENCE` disposition |
| `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh` | cross | `TERMINAL_LINE` fixture updated to the new count |
| `knowledge-base/engineering/architecture/decisions/ADR-147-boot-stage-diagnostics-live-in-baked-host-scripts.md` | 7460 | addendum, scoped narrowly — see §Architecture Decision |
| `apps/web-platform/infra/git-data-emit.test.sh` | 7460 | **found at review.** Asserts the exact contract Phase 5 reverses: *"no token => Sentry only (1); token => Sentry + Better Stack (2)"*. Goes RED, or goes vacuous if the mirror renders an empty token — both unacceptable silently. Also carries an endpoint-rewrite anchor Phase 5.2 changes, an emit-site analyzer Phase 5.3's new site must satisfy, and its own floor. |
| `apps/web-platform/infra/git-data-luks.tf` | 7460 | **found at review.** Carries *"It is NEVER baked into user_data"* — the prior rejection, in code (§5.0b). |
| `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md` | 7460 | **found at review.** States the one-Better-Stack-row-per-successful-boot premise that `HOST_SQL`'s `LIMIT 50` rests on, falsified by Phase 5 (§5.0). Its `stage:bootcmd_start` reaches-Sentry-only claim **survives** (§5.0e) — amend precisely, do not blanket-supersede. |
| `apps/web-platform/infra/git-data-gc.service` | 7460 | **found at review.** One of the **nine hashed payloads**; its comment's stated reason for running under `doppler run` is falsified. Editing it moves the digest — free pre-birth, and part of why this lands now. |
| `knowledge-base/engineering/operations/runbooks/git-data-birth.md` | 7460 | **found at review.** Carries a **directive** that inverts: *"Do not anchor a Better Stack query on anything earlier; it will return zero rows on a perfect rehearsal."* |
| `.github/workflows/rule-audit.yml` | 7544 | the `ubuntu:24.04` case in the existing `Detect zot pin staleness` step (§Design Call 2) |
| `plugins/soleur/test/cloud-init-user-data-size.test.ts` | 7460 | **found at review.** Models per-name value lengths (`SECRET_LENGTHS` / `DEFAULT_REF_LEN = 80`). Will not break, but without an entry the budget model carries an 80-byte guess for the new name. |

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-198-<slug>.md` | the baked-ingest-token decision (ordinal provisional) |

*(The first draft's `ubuntu-base-digest-freshness-7544.sh` + `.test.sh` were **cut at review** — the
follow-through sweeper closes a tracker on exit 0, so the probe would have terminated on its first
clean run. Replaced by a case in the existing `rule-audit.yml` staleness step. See §Design Call 2.)*

## Test Scenarios

Every scenario below is of the shape **mutation → guard reddens**, not **command → output**, per
Phase 2.12's own finding that a plan whose deliverable is guards must test the guards.

| # | Mutation applied | Suite that must go RED |
|---|---|---|
| 1 | revert `${CAPTURE:-}` to `$CAPTURE` and delete the init, then run the mutated emitter | `git-data-runcmd-rehearsal.test.sh` `D1-MUT` |
| 2 | mutated emitter exits 2 **and** writes capture output | `D1-MUT` must **PASS** (must-PASS boundary) |
| 3 | rebind a payload multi-line | `test-git-data-birth-readiness-gate.sh` `A12` |
| 4 | rebind a payload as `file(local.p)` | `A13` |
| 5 | add a second `templatefile(` | `A14` |
| 6 | rebind a payload as `file("${path.root}/…")` | `A15` |
| 7 | add a tenth `path.module` payload | `A16` must **PASS**, and digest must move on its content change |
| 8 | no-op the canonical-shape assertion | assertion-count floor |
| 9 | unpin one `docker run` | `R1-PIN` |
| 10 | pin with the platform-specific digest | `R1-PIN` media-type check |
| 11 | rename the token `R1-PIN` greps for | `R1-PIN` `≥ 6` floor |
| 12 | bump to a different valid tag+list-digest pair | `R1-PIN` must **PASS** |
| 13 | drop `level:fatal` from the Sentry query | evidence-capture suite (false-FAIL arm, real beacon fixture) |
| 14 | `_sentry_stats_period` body → `printf ''` | window-derivation arm |
| 15 | revert the consult at one of four call sites | per-site placement arm |
| 16 | Sentry stub returns HTTP 200 + HTML | shape-validation arm (must report TRANSIENT) |
| 17 | env-source `SENTRY_ORG` and set it to `jikigai` | org-pinning arm (403 must be a named TRANSIENT) |
| 18 | delete the whole Sentry block | Sentry-paragraph-anchored config arm |
| 19 | delete a `RUNG2_CAPTURE_VERDICT=` assertion | assertion-count floor |
| 20 | stub the query helper to ignore its query string | query-assertion arm |
| 21 | fixtures with different issue titles but same tags | must **PASS** with FAIL verdict |
| 22 | delete the `doppler_secret BETTERSTACK_LOGS_TOKEN` block from `git-data-luks.tf` | `git-data-rung2-rehearsal.test.sh` residency arm |
| 23 | change an ADR-147 frozen emit `message` literal | ADR-147 literal-freeze assertion |
| 24 | break the budget-script map mirror | `git-data-render-strip-parity.test.sh` |
