---
feature: feat-one-shot-7278-registry-restart-lever
issue: 7278
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-06-feat-registry-zot-inventory-lever-plan.md
supersedes_plan: knowledge-base/project/plans/2026-08-04-feat-registry-zot-restart-lever-plan.md
created: 2026-08-06
---

# Tasks — read-only zot disk-inventory lever (#7278)

> **RE-SCOPED 2026-08-06, then DEEPENED.** Derives from
> `2026-08-06-feat-registry-zot-inventory-lever-plan.md` **including its
> §Deepen-Plan Revisions**, which override the plan's own v1 text. The prior task list
> (restart lever, 7 checked / 59 open) is superseded with its plan: a **restart**-only lever
> cannot fix the live incident (15,640 restarts into a 100 %-full volume prove it), and its
> host-side delivery needs a host replace that is fatal while #6929 is open.
>
> **Already shipped, do NOT re-plan:** old Phase 0 / 0.5 (`user_data` under the Hetzner cap +
> its size guard) landed in **merged PR #7280**.
>
> **Scope: inventory-only.** `restart` / `push-config` / `reclaim` are documented and
> **BLOCKED ON A PROVISIONING EVENT** — not dropped, not delivered here.
>
> **Deepen changed the enumerator:** `crane` is **CUT** in favour of `curl` + `jq` (revision
> B1). Two arithmetic-correctness findings (A1 referrer tags, A2 the `fs_used_gb` error bar)
> are the highest-value items in Phase 0 and were caught by no v1 gate.

Ordering is dependency-directed. Do not reorder 1 → 4.

## Phase 0 — Preconditions (verify, never assume)

- [ ] 0.1 Re-derive the next-free ADR ordinal against freshly-fetched `origin/main`. Plan
      assumes **171** (170 max; **169 is TAKEN**) — PROVISIONAL.
- [ ] 0.2 Re-pull `SOLEUR_ZOT_DISK` (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 6h --grep SOLEUR_ZOT_DISK`).
      Record `pcent`, `fs_size_gb`, `zot_restarts`, `oom_kills`, `boot_id`. Self-pull only.
- [ ] 0.3 **(A1 — HIGHEST VALUE)** Probe `/v2/<repo>/tags/list` against the live registry and
      **count `sha256-*` referrer entries**. The keep-set is `sha256-.*`×50 per repo, so ~50 of
      ~61 tags per repo are referrers. If they are hidden from `tags/list`, ~80 % of tags go
      uncounted, `enumeration_complete` stays `true`, and the delta is large and **spurious**.
      If hidden → enumerate via `/v2/<repo>/referrers/<digest>` and make referrer coverage a
      first-class input to `enumeration_complete`.
- [ ] 0.4 **(A2)** Confirm the `fs_used_gb` derivation and its error bar. `pcent` is
      `used/(used+avail)` (**excludes** root-reserved blocks); `fs_size_gb` is **total**. So
      `fs_size_gb × pcent/100` overstates used bytes by ext4's ~5 % reserve ≈ **2.95 GB on
      59 GB**. `df --output=used` is not in the marker and §D8 forbids adding it. Record the
      formula and the error bar; **a `delta_gb` under ~3 GB is not distinguishable from zero.**
- [ ] 0.5 Read `.github/actions/cf-tunnel-registry-bridge/action.yml`. **(I6 — verify, do not
      re-derive)** the `ZOT_PUSH_*` decode is inline **inside** the login step (one `if:` covers
      both) and `REGISTRY_BRIDGE_PID` exports in the **preceding** step — no ordering hazard.
- [ ] 0.6 **(D-8)** Resolve the `APP_DOMAIN_BASE` contradiction by **name-only** Doppler listing:
      the composite says it is *not* in `soleur/prd` (falls back to a hardcoded default with
      `2>/dev/null`); `apply-web-platform-infra.yml` reads it from `soleur/prd` and fails closed.
      The repo contradicts itself — measure, do not pick a side.
- [ ] 0.7 **(D-9)** Record which Doppler config `BETTERSTACK_LOGS_TOKEN` was read from. It is
      **not** Terraform-managed in `soleur/prd` (every `doppler_secret` mirrors it into an
      *isolated* project). **Constraint: if it is absent or rotated, do NOT mint a
      `doppler_secret` — that is a `.tf` change and breaches AC6.**
- [ ] 0.8 **(D-3, E6)** Ingest half-probe from this workstation: POST a synthetic
      **`SOLEUR_INVENTORY_HALFPROBE`** line (a **non-prefix** token — `--grep` is a substring
      `LIKE`, so `SOLEUR_ZOT_INVENTORY_PROBE` would be matched by a grep for the real marker and
      contaminate both the poll and the follow-through) and round-trip it.
      **Record the measured POST→queryable latency** — it is the one number the poll budget needs,
      and no such constant exists anywhere in the repo. Record the bound explicitly: **this does
      NOT prove GitHub-runner egress against the `eu-fsn-3` pin (H6).**
- [ ] 0.9 Confirm `BETTERSTACK_QUERY_HOST|_USERNAME|_PASSWORD` are already wired into
      `scheduled-followthrough-sweeper.yml` (do **not** re-add).
- [ ] 0.10 Record the `scripts/lint-diagnosis-claims.highwater` baseline (currently **1**) and
      confirm `scripts/lint-workflow-errexit-capture.py` (AP-022 / ADR-170) scope covers the new
      workflow.

## Phase 1 — The enumerator (RED first)

- [ ] 1.1 Write failing tests before implementation (`cq-write-failing-tests-before`) in
      `tests/scripts/test-zot-inventory.sh`.
  - [ ] 1.1.0 **(F3)** Harness: a Python `http.server` bound to `127.0.0.1:5000` that logs
        `"%s %s" % (command, path)`, serves canned `/v2/` responses, and **405s anything else**.
        This proves verb confinement **at the wire** and doubles as the arithmetic fixture.
  - [ ] 1.1.1 **(F2) Dedup by digest.** Fixture: `R_a:t1 → m1(501), c0(13), aaaa(1000), bbbb(1000)`;
        `R_a:t2 → m2(502), c0(13), aaaa(1000)`; `R_b:t1 → m3(503), c0(13), aaaa(1000), cccc(7)`.
        `aaaa` spans two tags **and** two repos; **`bbbb` is a distinct digest with a size
        identical to `aaaa`** (without it, dedup-by-size is indistinguishable from
        dedup-by-digest); `c0` shared across all three. Assert hand-computed literals
        `unique_blobs=7`, `manifest_referenced_bytes=3526`. Observable pairs — correct 7/3526,
        naive-sum 11/5552, by-size 6/2526, per-repo 9/4539, manifest-self-omitted 4/2020,
        config-omitted 6/3513 — **no two collide**. On mismatch, dump the accumulated
        `digest:size` set, not just the total.
  - [ ] 1.1.2 **Index recursion**, plus a child referenced by **two** indexes (a non-memoizing
        recursion double-counts it) and a child digest that also appears as a top-level tag.
  - [ ] 1.1.3 **Partial sweep.** Manifest fetch fails after retry ⇒ `enumeration_complete=false`,
        `outcome=partial`, `manifest_errors=1`, **non-zero exit**.
  - [ ] 1.1.4 **Catalog unreadable (non-2xx)** ⇒ `reason=catalog_unreadable`.
  - [ ] 1.1.4b **(V2) Catalog 2xx-EMPTY** ⇒ `reason=catalog_empty`, **never** `repos=0` presented
        as a result. A `200 {"repositories":[]}` must NOT yield `enumeration_complete=true` with
        `delta_gb=59.0` — that is the plan manufacturing its own conclusion from a permissions
        failure. Assert `repos >= 2` (the known floor) or emit `reason=catalog_undercount`.
  - [ ] 1.1.4c **(A4) Unfollowed `Link` header** on `_catalog` or any `tags/list` ⇒
        `enumeration_complete=false`.
  - [ ] 1.1.5 **(V3) Tag-list failure.** One repo's `tags/list` fails after retry ⇒
        `tag_list_errors=1`, `repos_enumerated != repos`, `enumeration_complete=false`.
  - [ ] 1.1.6 **Retry positive control.** A transient failure that succeeds on retry ⇒
        `enumeration_complete=true` (else the lever can never produce AC17).
  - [ ] 1.1.7 **(F3) Verb confinement.** Every request the recording origin logged matches
        `^(GET|HEAD) `. Complement with a source-level deny-list
        (`wget|nc|ncat|socat|/dev/tcp`, write-shaped verbs) **labelled a supplement**.
  - [ ] 1.1.8 **Egress confinement.** Recorded destinations are exactly `127.0.0.1:5000` and the
        pinned ingest URL, with a **minimum-cardinality floor asserted first** (zero calls
        otherwise satisfies the negative, and zero is what an early `set -e` exit produces).
  - [ ] 1.1.9 **(C1/F6) Masking.** Plant sentinels in the **actually consumed** vars
        (`ZOT_PULL_TOKEN`, `BETTERSTACK_LOGS_TOKEN`); assert an `::add-mask::` is emitted for each
        and neither sentinel reaches the marker or the recorded output.
  - [ ] 1.1.10 **(I2/E9) Marker hygiene.** Emitted line is **single-line**, matches a strict field
        allow-list **derived from the construction site** (not hand-copied), and `outcome`/`reason`
        are asserted against a **closed enum**.
  - [ ] 1.1.11 **No-stub emitter.** Ingest token unset ⇒ fails loudly, never a silent skip.
  - [ ] 1.1.12 **(D7 self-enforcement)** `ZOT_PUSH_USER`/`ZOT_PUSH_TOKEN` populated in the
        environment ⇒ the script exits non-zero at entry.
  - [ ] 1.1.13 **(F1) Mutation arms**, copying `mutate_del`/`mutate_sub` from
        `git-data-emit.test.sh` **including its exit-non-zero-when-the-marker-is-absent
        behaviour**: naive-sum mutant ⇒ 11/5552; exfil-URL mutant ⇒ 1.1.8 RED; write-verb mutant
        ⇒ 1.1.7 RED; masking-rule-deleted mutant ⇒ sentinel leaks.
- [ ] 1.2 **(B1)** Implement `scripts/zot-inventory.sh` with **`curl` + `jq`, not crane**:
      `GET /v2/_catalog` → `GET /v2/<repo>/tags/list` → `GET /v2/<repo>/manifests/<ref>` with an
      `Accept` header listing the four OCI/Docker manifest + index media types; hand-rolled
      `Link`-header pagination (which is what lets 1.1.4c detect an unfollowed Link — crane
      silently cannot report it); index recursion; digest-keyed accumulation of config + layers +
      each manifest's own blob; bounded per-request retry with `curl -w '%{http_code}'` so the
      verdict taxonomy keys on **status codes**, not stderr prose.
- [ ] 1.2a **(B2 — BLOCKING)** The script **opens with an explicit `GET /v2/` origin-reachability
      verdict** (200/401 = origin answered; connection reset / empty = origin dial failed → emit
      the `zot-mirror-diagnosis.sh` measured verdict). Skipping `docker login` removes the only
      thing that dialled the origin — the composite's readiness check is a **local-listener**
      probe that its own header says *"cannot distinguish a working bridge from a dead one"*.
      **`catalog_unreadable` is claimable only AFTER the origin is proven to answer**, or the
      script reports an application-layer verdict for a transport-layer failure
      (`lint-diagnosis-claims.sh` BLOCKING class).
- [ ] 1.3 **(C1)** `::add-mask::` **every** secret read from Doppler — `ZOT_PULL_TOKEN` **and**
      `BETTERSTACK_LOGS_TOKEN` — immediately after the read, before any use. The repo is
      **PUBLIC**; `doppler secrets get --plain` values are **not** auto-masked.
- [ ] 1.3a **(C3)** Never put a credential on argv (`/proc/*/cmdline`, `set -x`). Pass via
      `curl --config -` on stdin or a `netrc` in a private scratch dir with a `trap … EXIT`.
- [ ] 1.4 **(C2)** Build the ingest payload with `jq -Rn --arg m "$LINE" '{message:$m}'`, never
      string interpolation. **Drop `largest_repo` / `largest_repo_gb` entirely** — per-repo
      attribution of a deduplicated blob is **undefined** (`"dedupe": true`), they serve no AC17
      branch, and they were the only registry-controlled strings in the line.
- [ ] 1.5 **(E7/E8)** Marker fields: `run_id`, `commit_sha`, `marker_schema=1`, `outcome`,
      `reason`, `repos`, `repos_enumerated`, `tags`, `manifests_fetched`, `catalog_errors`,
      `tag_list_errors`, `manifest_errors`, `enumeration_complete`, `unique_blobs`,
      `manifest_referenced_bytes`, `manifest_referenced_gb`, `fs_size_gb`, `pcent`, `fs_used_gb`,
      `delta_gb`, `disk_sample_age_s`, `boot_id`, `zot_restarts_at_start`, `zot_restarts_at_end`,
      `sweep_started_at`, `sweep_duration_s`. All values space-free.
      `zot_restarts_at_end != zot_restarts_at_start` ⇒ `outcome=partial reason=restart_during_sweep`.
- [ ] 1.6 **(E9)** `outcome` ∈ `{ok, degraded, partial, failed}` with uniform exit semantics —
      `partial` is exit-1; the stale-disk arm is `degraded` (v1 overloaded `partial` across an
      exit-1 and an exit-0 arm, contradicting 1.1.3).
- [ ] 1.7 **(D-4)** Every operator-facing message satisfies `lint-diagnosis-claims.sh` (name a
      computed verdict, or carry `# MEASURED-BY:`) **and** `lint-workflow-errexit-capture.py`
      (AP-022) at every `rc=$?` site.

## Phase 2 — The composite input

- [ ] 2.1 Add `skip-docker-login` (default `'false'`) to
      `.github/actions/cf-tunnel-registry-bridge/action.yml`, gating the login step (the
      `ZOT_PUSH_*` decode is inline within it — one `if:` covers both).
- [ ] 2.1a **(B4 — fail CLOSED)** The gate condition is **exactly** `inputs.skip-docker-login != 'true'`.
      Asserting `== 'false'` inverts it and lets a typo'd or empty value silently strip
      credentials from every push caller. Additionally **normalize and reject**:
      `case "${SKIP:-false}" in true|false) ;; *) exit 1 ;; esac` — GitHub Actions does not fail
      on an **undeclared** input key, so `skip_docker_login: true` (underscore) would otherwise
      yield a push-credentialed job with no error.
- [ ] 2.2 **(I5/D-7)** Update the header: PREREQUISITES + OUTPUTS, the `description:` (says
      *"+ docker login"*), the caller-teardown contract's unconditional `docker logout` (confirm
      its guard covers never-logged-in so teardown cannot redden a green run), and **correct
      "THREE CALLERS" → four**.
- [ ] 2.3 **(F5)** Guard test — durable invariants only:
      (i) input exists, `default: 'false'`, login condition is exactly `!= 'true'`;
      (ii) discovered-set scan: caller set non-empty, each `with:` omits the key or sets a literal
      `'true'`/`'false'` (never a `${{ }}` expression);
      (iii) parsed-YAML assertion that the **new** workflow passes `skip-docker-login: 'true'`
      under the exact declared key (a grep matches a comment).
      **Do NOT assert "none of the four existing callers passes it"** — this PR's own workflow is
      a fifth caller that does, so that assertion is RED on arrival. Demote the one-shot migration
      check (`git diff` shows no `with:` change on the four pre-existing callers) to AC5 evidence.

## Phase 3 — The workflow

- [ ] 3.1 `.github/workflows/registry-zot-inventory.yml`, mirroring `restart-inngest-server.yml`:
      `on: workflow_dispatch: {}` + `push: {branches: [main], paths: ['<self>']}` (registration
      only); **job-level** `if: github.event_name == 'workflow_dispatch'` (#6425);
      `concurrency: {group: registry-zot-inventory, cancel-in-progress: false}`; `timeout-minutes`
      above the enumeration + poll budget; `actions/checkout` SHA-pinned. Any dispatch input is a
      `choice` with the single value `inventory`, never interpolated into a URL or command.
- [ ] 3.1a **(G3)** `permissions: contents: read` **+ `issues: write`** — v1's `contents: read`
      **cannot comment**, so AC17's recording requirement was unimplementable.
- [ ] 3.2 Steps, in this order:
      **(D-1)** `DopplerHQ/cli-action` **FIRST** — the CLI is not preinstalled and the composite
      installs its own only at bridge-up, so a preflight placed before it exits 2 and prints a
      false cause on every run →
      `check-cloudflare-token-drift.sh --only REGISTRY_PUSH_ACCESS_TOKEN` preflight →
      **(C4)** exit-1 on `stale` **only**; carry `unverifiable`/`unmeasured` forward (AP-021:
      never collapse "could not check" into "bad") →
      bridge up with `skip-docker-login: true`, `doppler-token: ${{ secrets.DOPPLER_TOKEN_PRD }}`
      (**not** `secrets.DOPPLER_TOKEN` — branch configs do not inherit from the `prd` root) and
      **(D-2)** `token-verdict` / `token-checked-at` / `token-cause` **forwarded** (they exist so
      the composite's failure messages branch on what the job measured; omitting them commits the
      ADR-166 defect the fix is for) →
      self-pull `SOLEUR_ZOT_DISK` (start) → `scripts/zot-inventory.sh` → self-pull again (end) →
      `scripts/zot-inventory-assert-marker.sh` → **`if: always()` teardown** copied from the
      composite's documented contract.
- [ ] 3.3 **(G3)** Post the marker line + its interpretation as a comment on **#7247** (open,
      `action-required`). **#7278 is closed by this PR** and is not a valid target.
- [ ] 3.4 **(G3)** `.github/workflows/registry-zot-inventory-dispatch.yml`, mirroring
      `inngest-watchdog-restart-dispatch.yml`: `on: issues: [labeled]`, `permissions: actions: write`,
      guard on **both** the controlled label **and** `github.event.issue.user.type == 'Bot'` (a
      label alone is not an authority boundary — applying one needs only Triage), then
      `gh workflow run` + `gh issue comment`.

## Phase 4 — The round-trip assert (extracted + tested)

- [ ] 4.1 **(E4)** `scripts/zot-inventory-assert-marker.sh` — the pass condition must **not** live
      in workflow YAML where no test can reach it.
- [ ] 4.2 **(E1 — BLOCKING)** **Decode before matching.** `betterstack-query.sh`'s `raw` column is
      **double-encoded JSON**; a bare grep *"silently returns nothing"* — a probe that can never
      PASS. Use `jq -R -r 'fromjson? | .raw // empty' | jq -r 'fromjson | .message'`, then match
      `run_id=<this>` **and** `enumeration_complete=true` (v1's Phase 3.3 required only the
      `run_id`, contradicting AC8).
- [ ] 4.3 **(E2)** `--no-archive --since 15m` — hot window is ~40 min, and *"if the archive arm
      errors, the whole query errors"*, so the S3 arm can only contribute failure to a
      seconds-old row.
- [ ] 4.4 **(E3)** Four-outcome vocabulary from `scripts/betterstack-assert-absence.sh`:
      `unknown` (3) / `unshipping` (2) / `present` (1) / `clean` (0). Positive control is **free**:
      `SOLEUR_ZOT_DISK` lands on the same source every 5 min, so a 15-min window holds ~3 rows.
      **Zero control rows ⇒ `channel_dark`, never `marker_absent`.** Only a measured absence with
      a live control may be cited as evidence for H6.
- [ ] 4.5 **(E6)** Poll budget derived from 0.8's measured latency, stated as a multiple. Below
      that floor, non-observation is `unknown`, not a verdict.
- [ ] 4.6 **(E5)** Capture `curl -w '%{http_code}'` on the ingest POST and emit
      `reason=ingest_rejected_http_<code>`. **H6 attaches HERE**, not to `marker_not_observable` —
      a wrong-cluster POST returns 401 and `curl -fsS` exits non-zero.
- [ ] 4.7 `tests/scripts/test-zot-inventory-assert-marker.sh` — four cases, the primary being
      **a line present with a DIFFERENT `run_id` must NOT pass**; plus a test asserting the gate
      **fails** when fed an undecoded fixture.

## Phase 5 — Guard test + CI wiring

- [ ] 5.1 `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh`: python3 +
      pyyaml `yaml.safe_load`, asserting the **parsed** YAML; probe **both** key spellings via
      `on = wf.get("on", wf.get(True)) or {}` (pyyaml keys `on` as boolean `True` — probing only
      `"on"` reads as "no triggers" and **passes vacuously**); comparisons **inside python**
      printing bare `yes`/`no` (the guard `if` has spaces + single quotes that shell `eval`
      mangles into a silent false-FAIL); `wf … or {}` on the top-level load.
- [ ] 5.1a **(D-5)** **Iterate ALL jobs**, do not pin one: `assert set(jobs) == {"inventory"}` and
      require the guard string on **every** job. Pinning one key lets a future second job ship
      unguarded and fire on every registration push — the #6425 class re-entering through the door
      the guard does not watch. Back-port the same two-line fix to
      `restart-inngest-workflow-guard.test.sh`.
- [ ] 5.1b Exercise **both** `on:` spellings with a synthetic two-file fixture (one bare `on:`,
      one quoted `"on":`) — otherwise one arm of `wf.get("on", wf.get(True))` is dead code.
- [ ] 5.1c **Mutation arm:** copy the workflow to `$TMP`, delete the job-level `if:` via python,
      re-probe, assert `no`. Converts AC3 from a human claim into a machine check.
- [ ] 5.2 **BOTH** CI wirings or the test gates nothing: a `run: bash …` step in
      `infra-validation.yml`'s `deploy-script-tests` job **and** the new workflow paths added to
      that workflow's `pull_request.paths`.
- [ ] 5.2a **(F7)** Assert the wiring from **parsed YAML** (`jobs['deploy-script-tests'].steps[].run`
      and `on.pull_request.paths`), not a grep — a grep passes on a commented-out step.
- [ ] 5.3 Register both new test suites in `scripts/test-all.sh`.

## Phase 6 — ADR + C4

- [ ] 6.1 Write `ADR-171-…` (ordinal from 0.1), status `adopting`: CI may emit `SOLEUR_*` to
      Better Stack ingest; a CI-emitted marker is trusted only after readback; the registry's read
      surface is reachable and its write surface is not; **the corrected privilege statement**
      (non-materialization, not non-possession — the job holds a `soleur/prd`-root Doppler token);
      **(B3)** the fail-closed rationale for `skip-docker-login`; **(D-9)** the note that
      `BETTERSTACK_LOGS_TOKEN` in `soleur/prd` is not TF-declared; **(I3)** why ADR-169's
      *"no predicate that observes production zot"* does not apply (that objection is to
      undecidable classification **inside an authorization gate**; this is a measurement).
      Alternatives Considered — using the **corrected** rationale for the new-Access-token
      rejection (no scoped apply path ⇒ untargeted apply ⇒ the pending registry replace),
      **not** the false `-target`-transitivity claim.
- [ ] 6.2 `model.c4` — four edits: `github -> betterstack` gains the **ingest/write** direction;
      the `betterstack` element's *"CI polls read-only"* clause is **now false** — correct it;
      `github -> zotRegistry` gains the read-only INVENTORY traversal alongside the #7277 RESTORE
      path; `zotRegistry -> betterstack` notes `SOLEUR_ZOT_INVENTORY` is emitted by **GitHub**,
      not the host. **(I4)** name the `soleur/prd` config on the ingest edge — `model.c4` currently
      says the token is *"in soleur-registry/prd"*, so a reader would conclude CI needs the
      isolated project's credential.
- [ ] 6.3 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 6.4 If the ordinal moved in 0.1, sweep plan + tasks + every AC naming it in the same edit.

## Phase 7 — Runbook + triage pointers

- [ ] 7.1 `registry-luks-recut-6929.md`: "**try the inventory lever FIRST**" pointer ahead of any
      destructive path + a `## Related` entry. **Banner untouched** — the "Corrected 2026-08-04"
      block (≈ lines 8-15) and the "🚧 The remaining blocker" section (line 35 → 118) stay
      byte-identical; verify with a **region-scoped** diff against `origin/main`.
- [ ] 7.2 `scripts/zot-restart-loop-alarm.sh`: crash-loop arm **only**; every `NIC_CAUSE` arm
      byte-identical (different failure class).
- [ ] 7.3 `scheduled-zot-restart-loop.yml`: name the lever in the FIRE issue body.
- [ ] 7.4 `knowledge-base/project/specs/feat-one-shot-7247-zot-crash-loop-recovery/`: point #7247's
      triage notes at the lever.
- [ ] 7.5 Verify no runbook text added contains an SSH step or any human-executed step.

## Phase 8 — Ledger + follow-through

- [ ] 8.1 Add the two `connections` entries to `scripts/encryption-posture-ledger.json` in the
      **schema-exact** shape (`additionalProperties: false`; required `connection`/`enforced_at`/
      `in_transit`; `cert_verification` is an **enum `on|off`** — free text fails validation; `off`
      requires an `exception` with all four of `justification`/`tracking_issue`/`reevaluate_when`/
      `expires_on`). Run `python3 scripts/lint-encryption-posture.py` and require **5 connections,
      PASS** (baseline: 16 stores, 3 connections). Re-check `expires_on` is within the
      Layer-A ≤ 90-day window at ship.
- [ ] 8.2 **(G1/G2)** File a **dedicated tracker issue** — not #7278 (closed by this PR; the
      sweeper lists `--state open` and its reopen path fires only on exit **1**, so a correct
      exit-2 probe is a permanent silent no-op) and not #7247 (a live P1 incident that will close
      and take the tracker with it). Label `follow-through`; the **sole** directive goes there
      (only the first directive in a body is honoured).
- [ ] 8.3 `scripts/followthroughs/zot-inventory-marker-7278.sh` — exit **0** observed-and-complete,
      **2** not-yet-observed **or any auth/query failure**, **1** never.
      **(E2)** archive arm ON, `--since 7d` (the script's `SINCE="1h"` default could never observe
      a days-old dispatch). **(E10)** discriminator: the convention's mandated `SYSLOG_IDENTIFIER`
      isolation is **structurally unavailable** (a direct CI POST never passes through
      journald/Vector), so require the decoded `.message` to **start with**
      `SOLEUR_ZOT_INVENTORY run_id=` and the `run_id` to be **numeric** — a GitHub-webhook echo of
      this plan's own prose cannot satisfy a prefix-anchored match plus a numeric run id.
      **Ban `: "${VAR:?msg}"`** (it exits 1 = FAIL, not TRANSIENT;
      `scripts/lint-followthrough-varq-ban.sh` reddens CI).
- [ ] 8.4 **(G5)** Enrol **#6929** as a `Dependency` follow-through so §Blocked actions stops being
      prose that rots: `[[ "$(gh issue view 6929 --json state --jq .state)" == CLOSED ]] && exit 0 || exit 2`,
      `secrets=GH_TOKEN`.

## Phase 9 — Exit gate

- [ ] 9.1 Full `tests/scripts/` suite + `scripts/test-all.sh`.
- [ ] 9.2 `lint-diagnosis-claims.sh` green at or below `.highwater` (**1**); AP-022
      `lint-workflow-errexit-capture.py` green; `lint-followthrough-varq-ban.sh` green.
- [ ] 9.3 **(D-6)** Assert ZERO Terraform with the **corrected** pathspec — v1's glob missed
      `cloud-init.yml` (**no hyphen**; the 51 KB web-fleet template), `doppler-config-inventory.txt`
      (a live `file()`-driven `for_each` input), `vector.toml` + ~55 other user_data/
      `triggers_replace` sources, and all three `.terraform.lock.hcl`:
      `git diff --name-only origin/main...HEAD -- '*.tf' '*.terraform.lock.hcl' 'apps/web-platform/infra/**' 'infra/**' 'apps/cla-evidence/infra/**' 'tests/scripts/lib/*gate*.sh'`
      returns **empty**, with `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh`
      as the sole explicit carve-out (verified consumed by no `templatefile()`/`file()`). Without
      the carve-out written in, the tightened command false-FAILs. No registry recreate /
      `registry-host-replace` / `registry-luks-recut` fired or staged; `var.registry_server_type`
      untouched.
- [ ] 9.4 Walk every Pre-merge AC and record evidence per AC.
- [ ] 9.5 State the **EUR 0.00/mo** recurring delta in the PR body with its reasoning
      (`wg-record-recurring-vendor-expense-before-ready` satisfied, not skipped). A non-zero delta
      discovered during /work is a **STOP**.
- [ ] 9.6 **(I1)** Convert line-number citations to content anchors
      (`cq-cite-content-anchor-not-line-number`) across the plan, ADR and scripts.
- [ ] 9.7 Confirm the `iac-routing-ack` comment survived plan edits.

## Post-merge (automated — no operator step)

- [ ] 10.1 **PRIMARY.** Dispatch the lever; require an **observed** `SOLEUR_ZOT_INVENTORY` line
      with `enumeration_complete=true` and a numeric `delta_gb`; the workflow comments it onto
      #7247. **The deliverable is the number — assert no cause.**
      **(A2)** A `delta_gb` under ~3 GB is **not distinguishable from zero** (the ext4-reserve
      error bar). **(A3)** `delta_gb` is an **upper bound on unreferenced blob bytes**, not a
      measurement of them — the two named candidates are zot's dedupe cache DB and orphaned
      `.uploads/` staging, which have different remedies.
      `enumeration_complete=false` licenses **no** conclusion; re-dispatch.
- [ ] 10.2 **(E5)** H6 answered: the marker is observed, or `ingest_rejected_http_<code>` fires
      (region-pin refusal) — at which point the Sentry-mirror fallback is chosen **on that
      evidence**.
- [ ] 10.3 Flip `ADR-171` `adopting → accepted` once 10.1 is satisfied.
