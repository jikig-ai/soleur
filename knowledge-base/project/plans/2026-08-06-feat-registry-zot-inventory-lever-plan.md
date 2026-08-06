---
title: "feat: a read-only zot disk-inventory lever — measure what is actually consuming the 59 GB"
issue: 7278
branch: feat-one-shot-7278-registry-restart-lever
lane: cross-domain
type: feature
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
adr: ADR-171 (CONFIRMED 2026-08-06 — max on origin/main is ADR-170; 169 is taken)
supersedes: knowledge-base/project/plans/2026-08-04-feat-registry-zot-restart-lever-plan.md
created: 2026-08-06
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: a read-only zot disk-inventory lever (#7278)

Closes #7278.

Spec lacks valid `lane:` (the spec dir carries only `tasks.md` + `session-state.md`, no
`spec.md`) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary (deepen-plan, 2026-08-06)

**Agents:** architecture-strategist, spec-flow-analyzer, security-sentinel,
observability-coverage-reviewer, code-simplicity-reviewer, test-design-reviewer,
terraform-architect, plus a mechanical verify-the-negative sweep.
**Gates run:** 4.45, 4.5, 4.55, 4.6, 4.7, 4.8, 4.9, 4.10.

The verify-the-negative sweep checked **21 factual premises** against the worktree:
**21 CONFIRM, 0 CONTRADICT.** Every measured claim in this plan holds. The defects below are
all in the *mechanism*, not the *premises* — and four of them would have let the plan
manufacture its own conclusion.

### V1 (BLOCKING) — the round-trip gate as v1 specified it **could never pass**

`scripts/betterstack-query.sh`'s own header, lines 4-9:

> **OUTPUT SHAPE: each row's `raw` column is DOUBLE-ENCODED JSON** (a JSON string containing a
> JSON document). **A grep for a field name or a message substring against the raw line
> silently returns nothing** — the quotes are backslash-escaped. Decode first:
> `… | jq -r '.raw | fromjson | "\(.SYSLOG_IDENTIFIER) \(.message)"'`

v1's §D5 said "poll `betterstack-query.sh --grep SOLEUR_ZOT_INVENTORY` for a line carrying this
run's `run_id`" and specified **no decode**. That gate returns zero rows *always* — a probe that
can never PASS, failing loudly and wrongly into `marker_not_observable`, which AC18 then reads
as evidence that runner egress failed. `scripts/followthroughs/cert-reissue-markers-6698.sh:42-48`
carries a ‼️-flagged comment on exactly this defect class. **Fixed in §D5.**

### V2 (BLOCKING) — a **2xx empty catalog** was a fully GREEN run reporting the maximum delta

H5 says the pull user's `_catalog` access is UNKNOWN. But every v1 mechanization bound the
verdict to a **non-2xx** response. A `/v2/_catalog` returning `200 {"repositories":[]}` — the
plausible shape of a policy-filtered catalog — yielded `repos=0`, `manifest_errors=0`,
**`enumeration_complete=true`**, `manifest_referenced_gb=0.0`, `delta_gb=59.0`. Every gate
passes, the marker is observed, the follow-through PASSes, ADR-171 flips, and the recorded
finding is AC17's large-delta branch **verbatim** — *"the consumer is not policy-kept blobs"* —
produced by a permissions failure. This is the exact hazard §Sharp Edges names and the gate did
not cover. **Fixed in §D2 (repo/tag floors, `catalog_empty`) and §D4.**

### V3 (BLOCKING) — completeness covered **one of three** enumeration legs

`enumeration_complete` derived solely from `manifest_errors`. A `crane ls` failure on one of two
repos — the *expected* condition at 4.8 restarts/min — dropped that repo's entire blob set with
`manifest_errors=0` and `enumeration_complete=true`. Same for a truncated catalog page.
**Fixed:** `catalog_errors`, `tag_list_errors`, `repos_enumerated` are first-class fields and all
fold into `enumeration_complete`.

### V4 (BLOCKING) — the completeness gate could not see a **sweep straddling a zot restart**

300-500 requests against a host restarting ~4.8/min will very likely straddle a restart; the
sweep can complete with **zero errors** while the store changed under it. **Fixed:** the marker
carries `boot_id`, `zot_restarts_at_start`, `zot_restarts_at_end` — all three already exist in
`SOLEUR_ZOT_DISK`, so this is a second self-pull, not new instrumentation.

### V5 (BLOCKING) — nothing dispatched the lever, and nothing recorded its number

v1's AC17 required *"that figure is recorded on #7278 and #7247"* with **no phase, no file, and
no permission** to do it (`permissions: contents: read` cannot comment), and #7278 is **closed by
this PR** before the first dispatch can happen (R10). Separately, **no step anywhere fired the
lever**, so the follow-through could never legitimately pass. The repo already has the pattern:
`.github/workflows/inngest-watchdog-restart-dispatch.yml` triggers on `issues: [labeled]`, guards
on **both** the controlled label **and** `issue.user.type == 'Bot'` (a label-only gate would let
any triager fire it), then `gh workflow run` + `gh issue comment`. **Fixed in §D9.**

### V6 (BLOCKING) — the follow-through probe would **self-contaminate and auto-close**

`followthrough-convention.md:110` (#6475): the Logs source is shared, inngest ships
**GitHub-webhook logs that embed issue/PR bodies**, so *"any marker a human types into GitHub
appears in another producer's rows."* The literal `enumeration_complete=true` appears in this
plan's own AC8, AC17 and §D6 — text that lands in the PR body, the ADR and the tracker. A
presence-probe grepping for it matches the PR body's own text → **exit 0 → tracker closes →
ADR-171 flips to `accepted` with zero dispatches and zero measurements.** The convention's
mandated defense (`SYSLOG_IDENTIFIER` field isolation) is **structurally unavailable** here: the
marker is a direct CI `curl` POST, so it never passes through journald/Vector and **has no
`SYSLOG_IDENTIFIER` at all.** v1 never noticed. **Fixed in §D5/§Follow-Through.**

### V7 (BLOCKING) — the read path had no positive control, so an unanswered query read as absence

`scripts/betterstack-assert-absence.sh` already solved this and v1 neither used nor cited it. Its
header: *"betterstack-query.sh exits 3 when credentials are not injected and errors the whole
query if its archive arm fails; in both cases **stdout is empty**, which a row-count parse reads
as 'absence satisfied'."* The presence-mirror is identical — empty stdout reads as "the marker
never landed". Its four-outcome table (`unknown` 3 / `unshipping` 2 / `present` 1 / `clean` 0,
*"`clean` is the ONLY exit 0, and it is unreachable without a positive control read back through
the sink"*) is adopted. The control is **free**: `SOLEUR_ZOT_DISK` lands on the same source every
5 min. **Fixed in §D5.**

### V8 (correction) — H6's cause was attached to the bucket H6 cannot reach

`zot-registry.tf:115-118` records that a wrong-cluster POST returns **401**, and `curl -fsS`
exits non-zero on 401 — so a region-pin refusal surfaces as `ingest_post_failed`, **not**
`marker_not_observable`. v1 attached H6 to the latter. **Fixed in §D6.**

### V9 (correction) — "fifth crane site" is wrong; it is the **sixth**

Measured: `CRANE_VERSION=` appears at **5 sites across 4 workflow files** (`reusable-release.yml`,
`build-inngest-config-bundle.yml`, `build-inngest-bootstrap-image.yml`, and
`apply-web-platform-infra.yml` ×2). The new one is the **sixth crane site**. "Fifth **bridge
caller**" *is* correct — the two counts were conflated. Phase 0.4's parity question was posed
against the wrong premise.

### V10 (BLOCKING) — Phase 2.3's composite assertion was **false on arrival**

v1 asserted *"none of the four existing callers passes `skip-docker-login`"*. This PR's own
workflow is a **fifth caller that does pass it**, so a repo-wide grep is RED on the same commit
that introduces the test. It is also a migration-time fact frozen as a permanent invariant.
**Fixed in §D1/Phase 2.3** with a durable invariant pinned in the **fail-closed direction**:
the login step's condition must be exactly `inputs.skip-docker-login != 'true'`. Asserting
`== 'false'` inverts it and lets a typo'd or empty value silently strip credentials from every
push caller.

### V11 (BLOCKING) — four ACs asserted non-vacuity in prose and never executed it

AC3 (*"deleting the guard must make it fail"*), AC8 (*"verified by reading every exit path"*),
and tests 1.1.5/1.1.6 (source-greps that pass on an empty or non-existent file) all claimed a
test *would* fail against a defect without ever running that defect. The repo has solved this
twice — `git-data-emit.test.sh`'s `mutate_del`/`mutate_sub` battery (which **exits non-zero when
the mutation marker is absent**, so a mutation that does not land is not a null result wearing a
pass's clothes) and `private-nic-guard.test.sh`'s T4 positive control. v1 cited neither.
**Fixed in Phase 1.1 / 2.3 / 4.1 and the ACs.**

### V12 (BLOCKING) — the pass condition lived in workflow YAML, where no test can reach it

The round-trip assert is the gate for the entire deliverable and v1 put it in a `run:` block.
**Fixed:** extracted to `scripts/zot-inventory-assert-marker.sh` with four tested cases — the
primary being **a line present with a *different* `run_id` must NOT pass**, which is precisely
the failure documented in the learning §The positive-control requirement already cites.

### V13 (correction) — `disk_sample_stale` was a GREEN run with a knowingly-wrong `delta_gb`

It was the only failure mode absent from `fail_loud`, and it emitted `outcome=partial` with a
**zero** exit — directly contradicting test 1.1.3, which asserts `outcome=partial` ⟹ non-zero
exit. **Fixed:** `outcome` is now three-valued and the exit contract is uniform.

### V14 (correction) — `delta_gb` is an **upper bound**, not a measurement

`manifest_referenced_bytes` sums OCI blob `size` fields. zot's on-disk footprint also includes
`blobs/uploads/` staging and the boltdb/meta cache. A 5 GB staging leftover and 5 GB of genuinely
unreferenced blobs are the same number to this instrument and have completely different remedies
— the exact "wrong target" harm §User-Brand Impact names. **Fixed in AC17.**

### V15 (correction) — `fs_used_gb` had no defined formula

`SOLEUR_ZOT_DISK` reports `pcent` and `fs_size_gb`, not `fs_used`. `df`'s `pcent` is
`used/(used+avail)`, **not** `used/size` — ext4's ~5 % reserved blocks are in `size` but not the
denominator. On 59 GB that is ~3 GB of ambiguity on an integer percent, material for a
measurement whose reading branches on small-vs-large. **Fixed in §D4.**

### V16 (correction) — the follow-through had no valid host issue and no exit contract

Measured: **#7278** is closed by this PR (the sweeper lists `--state open`; a correct probe
returns exit 2, and the reopen path fires only on exit **1** → permanent silent no-op).
**#7247** carries the `follow-through` label and is a live P1 incident that will close when the
incident does. **Fixed:** a dedicated tracker, plus the three-way exit contract spelled out
(`0` observed-and-complete, `2` not-yet **or** any auth/query failure, `1` never) and the
`: "${VAR:?msg}"` form banned — it exits **1** = FAIL, and
`scripts/lint-followthrough-varq-ban.sh` reddens CI on it.

### V17 (accepted) — window asymmetry between the two reads

The round-trip poll needs `--no-archive --since 15m` (hot window is ~40 min; *"if the archive arm
errors, the whole query errors"*, so the s3 arm can only contribute failure to a seconds-old
row). The follow-through needs the **archive arm** and `--since 7d` (it must find a dispatch days
old; inheriting the script's `SINCE="1h"` default means it can never observe one). Both are
stated with the reason, so the next editor does not unify them and break one.

### V18 (accepted) — the blocked actions had no unblock-detection path

#6929 is OPEN, `priority/p3-low`, **no `follow-through` label, no directive**. Nothing watches
it, so §Blocked actions was prose that rots. **Fixed:** enrolled as a `Dependency`
follow-through per the convention's own table.

---

## Deepen-Plan Revisions — these OVERRIDE the v1 text below

Where a revision here conflicts with a section further down, **this section wins**. The two
findings that most affect whether the number is *correct* (A1, A2) were caught by no gate in v1
and are the most important output of this pass.

### A. Arithmetic correctness — the number itself

**A1 (BLOCKING, dominant failure mode) — cosign referrer tags may be invisible to `tags/list`.**
The keep-set is `sha256-.*` × **50** per repo against `latest` + `v.*`×5 + `[0-9a-f]{7,64}`×5 —
so roughly **50 of ~61 tags per repo are signature/attestation referrers**. If zot's referrers
API is enabled and referrer tags are hidden from `/v2/<repo>/tags/list`, **~80 % of tags go
uncounted**, `enumeration_complete` stays `true`, and the delta is large and spurious — the exact
shape §Sharp Edges warns about. v1 had no probe, no test and no mention.
**Fix:** Phase 0 probes `/v2/<repo>/tags/list` against the live registry and counts
`sha256-*` entries. If they are hidden, enumerate via `/v2/<repo>/referrers/<digest>` and make
referrer coverage a first-class input to `enumeration_complete`. **This probe is the single
highest-value item in Phase 0.**

**A2 (BLOCKING) — `fs_used_gb` carries a ~3 GB systematic error, unstated.**
`SOLEUR_ZOT_DISK` emits `pcent` from `df --output=pcent` — which is `used/(used+avail)`,
**excluding root-reserved blocks** — and `fs_size_gb` from `df --output=size` (**total**). So
`fs_size_gb × pcent/100` overstates used bytes by the reserved fraction: ext4's 5 % default on a
59 GB filesystem is **~2.95 GB baked straight into the headline `delta_gb`**. `df --output=used`
is not in the marker, and §D8 forbids the cloud-init change that would add it.
**Fix:** state the derivation and its error bar explicitly in §D4 and in AC17. **A `delta_gb`
under ~3 GB is not distinguishable from zero** and must not be read as one.

**A3 — a large `delta_gb` must name its candidates, or it has no next action.**
v1's AC17 said only *"the remedy is somewhere the current telemetry does not look."*
`cloud-init-registry.yml` sets `"dedupe": true`, implying a zot cache DB at `rootDirectory`; and
with zot restarting ~4.8/min while releases retry, **orphaned `.uploads/` staging sessions are a
highly plausible large consumer**. **Fix:** AC17 names both, and states that `delta_gb` is an
**upper bound on unreferenced blob bytes**, not a measurement of them — a 5 GB staging leftover
and 5 GB of genuinely unreferenced blobs are the same number to this instrument and have
completely different remedies.

**A4 — catalog/tag-list truncation is not a fetch error and was invisible.**
`enumeration_complete` must additionally require: **no unfollowed `Link` header** on `_catalog`
or any `tags/list`, and `repos` matching the expected floor (2). A mismatch is a named verdict,
never a proceed.

### B. Transport and enumerator

**B1 — replace `crane` with `curl` + `jq`.** v1 chose crane for pagination and index recursion.
**Index recursion is hand-rolled either way** (§D2 step 3 recurses `manifests[].digest`), so
crane bought only pagination — a `Link`-header loop over ~2 repos and ~120 tags that at zot's
default page size will not paginate at all. Four costs of keeping it, all avoided by cutting it:
(i) **it breaks the error taxonomy** — crane exits 1 for *every* failure, so `catalog_unreadable`
would have to be recovered from stderr prose instead of the `curl -w '%{http_code}'` status that
is free; (ii) **it falsifies AC2** — egress would live in a separate binary, so a PATH-shimmed
stub asserts only what arguments the script passed, never what crane did; (iii) it adds a
**mandatory sixth** `CRANE_SHA256` pin site; (iv) Phase 0.5 existed only to decide whether to use
the simpler thing. **Cutting crane removes Phases 0.4 and 0.5, the crane install spine, and the
`inngest-bootstrap-mirror-only.test.sh` edit, and makes AC2 truthful.** What is lost: crane's
`Accept` negotiation (one header listing the four OCI/Docker manifest + index media types) and
Link-header pagination (~8 lines — and hand-rolling it is what lets A4 detect an unfollowed Link,
which crane silently cannot report).
*Consequently V9's "sixth crane site" and P1-8's parity-test edit both fall away.*

**B2 (BLOCKING) — skipping `docker login` deletes the only origin-dial probe.**
The composite's readiness check is a **local-listener** probe, and its own header says it cannot
do the job: *"cloudflared binds 127.0.0.1:5000 as soon as it starts, before and regardless of
whether the tunnelled stream reaches zot, so it cannot distinguish a working bridge from a dead
one."* The `docker login` step is what actually dials the origin today. With
`skip-docker-login: true` the composite returns **success with zero origin proof**, and a
crash-looping origin — the live condition — surfaces as a failed catalog read, which v1 mapped to
`reason=catalog_unreadable`: **an application-layer verdict for a transport-layer failure.** That
is the `lint-diagnosis-claims.sh` BLOCKING class and the plan's own thesis inverted.
**Fix:** `scripts/zot-inventory.sh` opens with an explicit `GET /v2/` origin-reachability
verdict (200/401 = origin answered; connection reset / empty = origin dial failed, emit the
`zot-mirror-diagnosis.sh` measured verdict). **`catalog_unreadable` is only claimable after the
origin has been proven to answer.**

**B3 — the *right* rationale for `skip-docker-login` is fail-closed avoidance, not privilege
purity.** `scripts/registry-pull-path-health.sh`'s header records that the bridge *"exits 1 on a
failed listener bind **and on a failed docker login**."* Given `zot_restarts` climbing ~4.8/min,
the most likely outcome of the first dispatch *without* the skip is that **the composite aborts
and the inventory never runs** — the lever defeated by an unrelated gate during exactly the
condition it exists to measure. Record this in §D1 and in ADR-171 as the primary reason; the
privilege reduction (§D7, as corrected) is the secondary one.

**B4 — `skip-docker-login` must fail CLOSED.** The composite gate must be exactly
`inputs.skip-docker-login != 'true'` (a typo'd or empty value leaves login *running*, i.e. every
existing caller's behaviour). Additionally the composite must **normalize and reject**:
`case "${SKIP:-false}" in true|false) ;; *) exit 1 ;; esac`. Rationale: GitHub Actions does not
fail on an **undeclared** input key, so `skip_docker_login: true` (underscore) silently yields a
push-credentialed job with no error. The runtime `ZOT_PUSH_*`-must-be-unset assertion in
§D7 catches this independently of the YAML.

### C. Security

**C1 (BLOCKING) — mask every Doppler-read secret. The repo is PUBLIC, so job logs are
world-readable.** v1's Phase 1.3 masked only `ZOT_PULL_TOKEN`. Values read via
`doppler secrets get --plain` inside a `run:` body are **not** auto-masked — only `${{ secrets.* }}`
values are. `BETTERSTACK_LOGS_TOKEN` is used on every run as `Authorization: Bearer $TOKEN`; any
`curl -v`, retry diagnostic, or future `set -x` publishes a live write credential.
**Fix:** `::add-mask::` **every** secret value the script reads, immediately after the read and
before any use — `ZOT_PULL_TOKEN` **and** `BETTERSTACK_LOGS_TOKEN`. AC7 gains: *a test asserts
the script emits an `::add-mask::` for each secret-valued variable it reads.* The in-repo
discipline is unambiguous — the composite masks both its token halves and `ZOT_PUSH_TOKEN`.

**C2 — the marker is built from a registry-controlled string and hand-interpolated into JSON.**
v1 copied the cloud-init idiom "verbatim", but that idiom is safe *at its original site* because
every field is host-derived and the one free-text field is deliberately **last**. v1's
`largest_repo=<name>` comes **from the registry** and sat second-to-last. A repo name containing
`"`/`\` breaks the JSON; a space corrupts `key=value` parsing of every later field; `\n`,
` `, ` ` forge a log line (a C0-only strip does not close this —
`cq-regex-unicode-separators-escape-only`).
**Fix — and the simplest fix is a cut:** **drop `largest_repo` and `largest_repo_gb` entirely.**
With exactly two repos "largest" is a coin flip between two names already known, it serves no
branch of AC17, and — decisively — **per-repo attribution of a deduplicated blob is undefined**
(`"dedupe": true` means a shared base layer is one blob on disk; v1 never said which repo it
counts toward). They were the only fields that could be wrong without anyone noticing.
Independently: build the payload with `jq -Rn --arg m "$LINE" '{message:$m}'`, never string
interpolation, and assert the emitted line is **single-line** in AC7.

**C3 — credential handling for the HTTP client.** Never put a token on argv (visible in
`/proc/*/cmdline`, echoed by `set -x`) — the composite's own note is *"(never argv)"*. With B1's
`curl -u`, pass credentials via `--config -` on stdin or a `netrc` in a private scratch dir, and
never reuse the ambient docker config.

**C4 — do not exit 1 on token verdict `unverifiable`.** AP-021: a verdict *"must never collapse
'could not check' into 'bad'"*, and `reusable-release.yml`'s own `unverifiable` arm prints
*"This is NOT a claim that it is stale, and it is not a reason to rotate."* For a lever whose
purpose is to obtain a number during a live incident, aborting before the bridge on an ungraded
credential is the wrong trade. **Gate exit-1 on `stale` only**; carry `unverifiable`/`unmeasured`
forward and let B2's origin probe be the gate.

### D. Workflow mechanics

**D-1 — install the Doppler CLI before the token-drift preflight.** v1's Phase 3.2 ordered
preflight → crane → bridge, but the Doppler CLI is installed by the **composite's first step**,
i.e. at bridge-up. `check-cloudflare-token-drift.sh` shells out to `doppler`, so the preflight
would exit 2 and print a false cause on every run — `reusable-release.yml` carries a dedicated
step and a comment for exactly this. Add `DopplerHQ/cli-action` as step 0.

**D-2 — forward the three measured-verdict inputs.** The composite declares `token-verdict`,
`token-checked-at`, `token-cause` precisely *"so this action's failure messages can branch on
something the CALLING JOB measured, instead of naming a cause nobody checked."* v1 passed only
`skip-docker-login` and `doppler-token` — so the lever would run a preflight and then report
`unmeasured`, committing the ADR-166 defect it exists to avoid. Forward all three.

**D-3 — rename the Phase 0.6 probe marker.** `--grep` is a substring `LIKE`, so
`SOLEUR_ZOT_INVENTORY_PROBE` is matched by a grep for `SOLEUR_ZOT_INVENTORY` — contaminating both
the round-trip poll and the follow-through. Use a **non-prefix** token, e.g.
`SOLEUR_INVENTORY_HALFPROBE`.

**D-4 — add `lint-workflow-errexit-capture.py` (AP-022 / ADR-170) to the exit gate and the ACs.**
It scans all of `.github/workflows` and is CI-required; this design guarantees rc-capture sites
(the preflight, the bounded retries, the poll). v1 named only `lint-diagnosis-claims.sh`.

**D-5 — the guard test must iterate ALL jobs, not pin one.** The precedent hard-codes a single
job key, so a future second job added without the guard passes green and fires on every
registration push — the #6425 class re-entering through the door the guard does not watch.
Assert `set(jobs) == {"inventory"}` **and** the guard string on every job. Worth back-porting to
`restart-inngest-workflow-guard.test.sh` in the same PR (two lines, same hole, fleet-wide).

**D-6 — AC6's pathspec is insufficient.** Measured misses: `apps/web-platform/infra/cloud-init.yml`
(**no hyphen** — the 51 KB web-fleet user_data template; editing it ForceNew-replaces the web
hosts while AC6 stays green), `doppler-config-inventory.txt` (read by `file()` and driving a
`for_each` on `doppler_service_token`), `vector.toml` and ~55 other `${path.module}` sources baked
into `user_data` or `triggers_replace = sha256(file(...))`, and all three `.terraform.lock.hcl`.
**Replacement:**
`git diff --name-only origin/main...HEAD -- '*.tf' '*.terraform.lock.hcl' 'apps/web-platform/infra/**' 'infra/**' 'apps/cla-evidence/infra/**' 'tests/scripts/lib/*gate*.sh'`
must return **empty** — with the guard-test file under `apps/web-platform/infra/` as the sole
explicit carve-out (verified consumed by no `templatefile()`/`file()` in any `.tf`). Without the
carve-out written in, the tightened command false-FAILs. *(Not a hole: `*.tf` is a git pathspec
glob and does span `/`; and zero `.tfvars`/`.tf.json` files are tracked anywhere.)*

**D-7 — name the fourth composite caller correctly.** It is the **`registry_store_restore` job**
in `apply-web-platform-infra.yml` — the post-recut GHCR restore path (#7277), *"the step that ends
the empty-store window"* — not "the release pipeline". §Risks and AC5 both under-described the
exposure. Also: the composite's own header says **"THREE CALLERS"** and there are four; correct
it in the same edit, since a stale caller count is what makes the next `unmeasured`-arm reasoning
wrong.

**D-8 — resolve the `APP_DOMAIN_BASE` contradiction in Phase 0.** The composite says it is *not*
in `soleur/prd` and falls back to a hardcoded default with `2>/dev/null`; `apply-web-platform-infra.yml`
reads it from `soleur/prd` and **fails closed** if empty, with a comment explicitly rejecting the
silent default. The repo contradicts itself and v1 picked a side without measuring. Resolve by
name-only listing. (The `2>/dev/null` also swallows exactly the auth errors the same file forbids
swallowing 18 lines above — pre-existing, three lines from this PR's own edit, worth fixing here.)

**D-9 — `BETTERSTACK_LOGS_TOKEN` in `soleur/prd` is NOT Terraform-managed.** Every `doppler_secret`
for that name mirrors it into an *isolated* project; its presence in the `prd` root is
out-of-band, corroborated only by prose. Zero-Terraform survives, but this is a trap: if Phase 0
finds it absent or rotated, the reflexive fix — adding a `doppler_secret` to `soleur/prd` — **is a
`.tf` change and breaches AC6**. Phase 0 must record which config it read and name
"do not mint a TF secret for this" as the fallback constraint. One clause in ADR-171.

### E. Observability read path

**E1 (BLOCKING) — decode before matching.** See V1. The gate must
`jq -R -r 'fromjson? | .raw // empty' | jq -r 'fromjson | .message'` and then match
`run_id=`, and a test must assert the gate **fails** when fed an undecoded fixture.

**E2 — window asymmetry, stated with reasons so it is not "tidied" away.** Round-trip poll:
`--no-archive --since 15m` (hot window ~40 min; *"if the archive arm errors, the whole query
errors"*, so the S3 arm can only contribute failure to a seconds-old row). Follow-through:
archive arm ON, `--since 7d` (it must find a dispatch days old; the script's `SINCE="1h"` default
means it never would).

**E3 — four-outcome vocabulary, adopted from `scripts/betterstack-assert-absence.sh`.**
`unknown` (3, query did not answer) / `unshipping` (2, positive control returned 0 rows — the
channel is dark) / `present` (1) / `clean` (0). **Only a measured absence with a live control may
be cited as evidence for H6.** The positive control is free: `SOLEUR_ZOT_DISK` lands on the same
source every 5 min, so a 15-minute window holds ~3 rows; zero control rows ⇒ `channel_dark`,
never `marker_absent`. Note that helper enforces a **1 h `--since` floor** because *its* canary is
rate-limited to 1800 s — our control's 5-min cadence is why a separate script with its own
documented floor is correct rather than reusing it.

**E4 — extract the round-trip out of workflow YAML.** `scripts/zot-inventory-assert-marker.sh`,
unit-tested on four cases, the primary being **a line present with a *different* `run_id` must NOT
pass** — precisely the failure documented in the learning §The positive-control requirement
already cites. v1 put the deliverable's pass condition where no test can reach it.

**E5 — H6 is attached to the wrong bucket.** A wrong-cluster POST returns **401** and `curl -fsS`
exits non-zero, so a region-pin refusal surfaces as `ingest_post_failed`, not
`marker_not_observable`. Capture `curl -w '%{http_code}'` and emit
`reason=ingest_rejected_http_<code>` (a computed verdict, so `lint-diagnosis-claims.sh` is
satisfied); re-attach H6 there.

**E6 — measure the ingest→queryable lag in Phase 0 and derive the poll budget from it.** No lag
constant exists anywhere in the repo, and **five in-repo consumers classify "not present yet" as
TRANSIENT rather than a verdict**. v1 named no interval and no budget. Phase 0.6 already
round-trips a synthetic line — record *how long it took*, and set the budget to a stated multiple.
Below that floor, non-observation is `unknown`, not a verdict.

**E7 — the marker's provenance must be in the durable record.** Add `commit_sha=`,
`marker_schema=1`. `run_id` alone resolves only *through* the GH Actions run log — 90-day default
retention — which is the artifact the plan argues is not durable.

**E8 — restart-straddle detection.** Add `boot_id`, `zot_restarts_at_start`,
`zot_restarts_at_end`, `sweep_started_at`, `sweep_duration_s`. All three zot fields already exist
in `SOLEUR_ZOT_DISK`, so this is a second self-pull, not new instrumentation.
`zot_restarts_at_end != zot_restarts_at_start` ⇒ `outcome=partial reason=restart_during_sweep`.

**E9 — `outcome` cardinality must match exit semantics.** v1 overloaded `outcome=partial` across
an exit-1 arm (incomplete enumeration) and an exit-0 arm (stale disk sample), which also
contradicted test 1.1.3. Give the disk-staleness arm `outcome=degraded`, or fold it into
`fail_loud`. And pin the `reason` **value set** as a closed enum in the test, not just the field
name — otherwise a typo'd reason passes the allow-list, and any interpolated error string becomes
an unscrubbed egress path.

**E10 — the follow-through probe's discriminator.** The convention's mandated `SYSLOG_IDENTIFIER`
field isolation is **structurally unavailable** (a direct CI POST never passes through
journald/Vector, so it has no such field). Substitute: require the decoded `.message` to **start
with** `SOLEUR_ZOT_INVENTORY run_id=` and the `run_id` to be numeric — a GitHub-webhook echo of
prose cannot satisfy a prefix-anchored match plus a numeric run id. State in the tracker that no
GitHub-authored text may quote the exact PASS token.

### F. Test design

**F1 — mechanize non-vacuity.** Copy `mutate_del`/`mutate_sub` from `git-data-emit.test.sh`,
**including its exit-non-zero-when-the-mutation-marker-is-absent behaviour** (*a mutation that
does not land is a null result wearing a pass's clothes*). One mutation arm per load-bearing
property: naive-sum mutant, exfil-URL mutant, write-verb mutant, masking-rule-deleted mutant.

**F2 — pin the 1.1.1 fixture to a shape that discriminates all five defects.** Three refs, seven
unique blobs:
`R_a:t1 → m1(501), c0(13), aaaa(1000), bbbb(1000)` · `R_a:t2 → m2(502), c0(13), aaaa(1000)` ·
`R_b:t1 → m3(503), c0(13), aaaa(1000), cccc(7)`. Load-bearing: `aaaa` spans two tags **and** two
repos (kills per-tag and per-repo scoping); **`bbbb` is a distinct digest with a size identical to
`aaaa`** (the discriminator v1 omitted — without it, dedup-by-size is indistinguishable from
dedup-by-digest); `c0` shared across all three; distinct manifest sizes. Assert **hand-computed
literals** `unique_blobs=7`, `manifest_referenced_bytes=3526`. Observable pairs — correct 7/3526;
naive sum 11/5552; dedup-by-size 6/2526; per-repo 9/4539; manifest-self omitted 4/2020; config
omitted 6/3513 — **no two collide.** On mismatch the failure must dump the accumulated
`digest:size` set, not just the total.

**F3 — a real recording origin, not only stubs.** Bind a Python `http.server` on
`127.0.0.1:5000` that logs `"%s %s" % (command, path)`, serves canned `/v2/` responses, and 405s
anything else. Assert every recorded line matches `^(GET|HEAD) `. This proves verb confinement
**at the wire**, doubles as the dedup/index fixture, and — with B1's curl — validates the
plain-HTTP auth form directly. Complement with a source-level deny-list (`wget|nc|ncat|socat|/dev/tcp`,
write-shaped verbs) **explicitly labelled a supplement**, since it covers untested branches a
recording origin cannot reach. Record process-boundary egress allow-listing (netns) as
considered-and-rejected, so the next reader knows the test is a test and not an enforcement.

**F4 — harness discipline, all from in-repo precedent.** `PATH="$BIN"` **alone**, never
`"$BIN:$PATH"` (prepending is exactly what made a prior defect invisible — a real binary leaks in
and masks the fault). Resolve `timeout` absolutely before stripping PATH, and bound the retry arm
with it. **Never `producer | grep -q`** — under `pipefail` an early match SIGPIPEs the producer
and the pipeline reports non-zero *even though grep matched*, which fails **open** on every
negative assertion; grep the recorded file directly. Minimum-cardinality floor before any negative
assertion (zero recorded calls otherwise satisfies "no call targeted a forbidden host", and zero
is what an early `set -e` exit produces). `export TMPDIR="${TMPDIR:-/var/tmp}"`; a skip is not a
pass.

**F5 — Phase 2.3's assertion was false on arrival and must become a durable invariant.**
v1 asserted *"none of the four existing callers passes `skip-docker-login`"* — but **this PR's own
workflow is a fifth caller that does pass it**, so a repo-wide grep is RED on the same commit that
introduces the test. Replace with: (i) the **permanent** invariant — input exists, `default: 'false'`,
login condition is exactly `!= 'true'` (which guarantees "unchanged for any caller that does not
pass the input" for **all future** callers); (ii) a discovered-set scan asserting the caller set is
non-empty and each `with:` either omits the key or sets a literal `'true'`/`'false'`, never a
`${{ }}` expression; (iii) the one-shot migration check (`git diff` shows no `with:` change on the
four pre-existing callers) demoted to **AC5 evidence**, not a permanent test.
Additionally assert the **forward** direction from parsed YAML: the new workflow passes
`skip-docker-login: 'true'` under the exact declared key (a grep matches a comment).

**F6 — AC7's credential test must plant sentinels in the *actually consumed* variables**
(`ZOT_PULL_TOKEN`, `BETTERSTACK_LOGS_TOKEN`), with the masking-rule-deleted mutation arm proving
the check is not vacuous. Derive the field allow-list from the marker's **construction site**
rather than hand-copying §D4 — a hand-copied key set has gone green while the producer dropped two
keys.

**F7 — AC4 must use parsed YAML, not grep.** A grep for the guard-test registration passes on a
commented-out step. Assert against `jobs['deploy-script-tests'].steps[].run` and
`on.pull_request.paths` — the same discipline the plan demands of itself in AC3.

### G. Follow-through and journey

**G1 — a dedicated tracker issue.** Not #7278 (closed by this PR; the sweeper lists `--state open`
and its reopen path fires only on exit **1**, so a correct exit-2 probe is a permanent silent
no-op) and not #7247 (a live P1 incident that will close when the incident does, taking the
tracker with it). File a dedicated issue, label it `follow-through`, put the **sole** directive
there — the convention honours only the first directive in a body.

**G2 — the three-way exit contract, spelled out.** `0` observed-and-complete; `2` not-yet-observed
**or any auth/query failure**; `1` **never** (there is no regression shape here). The
`: "${VAR:?msg}"` guard form is **banned** — it exits 1 = FAIL, not TRANSIENT, and
`scripts/lint-followthrough-varq-ban.sh` reddens CI on it.

**G3 — assign the dispatch and the recording.** v1 had neither. Mirror
`.github/workflows/inngest-watchdog-restart-dispatch.yml`: trigger on `issues: [labeled]`, guard
on **both** the controlled label **and** `issue.user.type == 'Bot'` (the label alone is not an
authority boundary — applying one needs only Triage), then `gh workflow run` + `gh issue comment`.
For the recording itself, the inventory workflow needs `issues: write` (v1's `contents: read`
cannot comment) and posts the marker line plus its interpretation onto **#7247**, which is open
and `action-required`. Note #7278 is closed by this PR and is not a valid target.

**G4 — every failure arm must carry a next action**, and the arms that are **unremediable under
the #6929 deadlock** must say so plainly rather than dead-ending. Naming a remedy is not naming an
unmeasured cause, so this is compatible with `lint-diagnosis-claims.sh`.

**G5 — enrol #6929 as a `Dependency` follow-through** so §Blocked actions stops being prose that
rots: `[[ "$(gh issue view 6929 --json state --jq .state)" == CLOSED ]] && exit 0 || exit 2`,
`secrets=GH_TOKEN`.

### H. Recorded as considered-and-rejected

The simplicity review proposed four further cuts. Each is **rejected**, with the reason, so the
next reader does not re-litigate them:

| Proposed cut | Rejected because |
|---|---|
| Drop the Better Stack round-trip; print the number and comment it on an issue | The operator brief requires the lever be *"observable FROM TELEMETRY, not just an exit code"* and *"assert against observed state rather than the lever's self-report."* The critique is nonetheless partly absorbed: `--no-archive`, a measured budget (E6), the four-outcome vocabulary (E3), and an issue comment as an **additional** durable home (G3) — not a replacement. |
| Drop the pyyaml guard test and its two CI wirings | The brief mandates it verbatim, including parsed-YAML assertion and both `on:` key spellings. It is also the cheapest defence against the #6425 class, and D-5 strengthens it. |
| Drop Phase 6 (runbook + triage pointers) | The brief lists them as **issue acceptance**. AC10/AC11 are not damage control for optional edits — they are how a required edit is made provably safe around a banner the plan itself calls *"what stops a fatal destroy."* |
| Defer encryption-ledger entry 2 as a pre-existing gap | Fair, but it is ~12 lines and **this PR adds the fifth caller** to that leg. Folding it in is cheaper than the issue that would track it. |

Two further simplicity findings **are** adopted and appear above: **B1** (cut crane) and **C2**
(cut `largest_repo`/`largest_repo_gb`).

### I. Housekeeping

- **I1 — convert line-number citations to content anchors** (`cq-cite-content-anchor-not-line-number`).
  Several in v1 have already drifted (`zot-registry.tf:115` vs `:125`; `cloud-init-registry.yml:408`
  vs the `LINE=` assignment at `:406`).
- **I2 — AC7 asserts the emitted marker is a SINGLE line.** v1 asserted no whitespace *inside a
  value* but never that the line is unbroken; an embedded newline breaks both `key=value` parsing
  and the `LIKE`-based `--grep`.
- **I3 — ADR-171 should note ADR-169's *"THERE IS DELIBERATELY NO PREDICATE THAT OBSERVES
  PRODUCTION ZOT"*** (`registry-pull-path-health.sh`) and why it does not apply: that objection is
  to undecidable classification **inside an authorization gate**; this is a measurement, and a
  measurement is not a gate. A plan that supersedes a predecessor and carries ten refutations
  should not leave the eleventh unaddressed.
- **I4 — C4 edit 4 needs a config note.** `model.c4` says the source-2457081 ingest token is *"in
  `soleur-registry/prd`"*; CI reads the `soleur/prd` copy. Without naming that, a reader concludes
  CI needs the isolated project's credential.
- **I5 — Phase 2.2 must also update the composite's `description:`** (it says *"+ docker login"*)
  and the caller-teardown contract's unconditional `docker logout`; both become mode-dependent.
  Confirm the teardown's guard covers the never-logged-in case so it cannot redden a green run.
- **I6 — Phase 0.3 is already answered:** the `ZOT_PUSH_*` decode is **inline inside** the login
  step, so one `if:` covers both, and `REGISTRY_BRIDGE_PID` is exported in the *preceding* step.
  No ordering hazard. Verify, do not re-derive.

> ## ⚠ SUPERSEDES the 2026-08-04 plan
>
> `knowledge-base/project/plans/2026-08-04-feat-registry-zot-restart-lever-plan.md` is
> **SUPERSEDED** and is reference-only. Its scope was a **restart** lever. That scope
> **cannot fix the live incident**: restarting zot into a 100 %-full volume restarts it into
> the same wall, which is exactly what `--restart unless-stopped` has already demonstrated
> **15,640** times. Its host-side delivery (a `webhook` listener baked into
> `cloud-init-registry.yml`) additionally requires a host **replace**, which today is fatal
> (§The deadlock). Its Phase 0 and Phase 0.5 **did ship**, in merged PR #7280, and are not
> re-planned here.
>
> Its `adr: ADR-169 (PROVISIONAL)` is **DEAD**: ADR-169 is now taken by
> `ADR-169-what-authorizes-destroying-the-sole-pull-path.md`. See §Architecture Decision.

---

## Overview

The registry host has no in-place lever of any kind. Every remediation for the live
disk-exhaustion incident (#7247) needs to execute something on a host that cannot be
reached, and the one delivery vehicle that exists — a host replace — is presently fatal.

This plan does the **one useful thing that needs no host execution at all**: it measures,
read-only, over the already-live and already-CF-Access-gated `registry.${var.app_domain_base}`
ingress, **how many of the 59 GB are actually referenced by a manifest**.

That number is the open question. Nothing in the repo answers it today.
`SOLEUR_ZOT_DISK` reports `pcent` and `fs_size_gb` but **no per-path or per-object
breakdown**, and the prior session recorded the gap in exactly those terms:

> **Honest gap: I cannot confirm the 59 GB is all policy-KEPT blobs.** Rough arithmetic
> from the recorded ~1.5–2 GB/image puts the keep-set nearer ~25 GB than 59 GB.

**The deliverable of this plan is that measurement, not a diagnosis.** The plan asserts no
cause. It ships the instrument that makes a cause assertable, and it ships it in the only
shape available today: zero host change, zero Terraform, existing credentials, existing
transport.

### What this is NOT

- It is **not** a restart lever. Restart is blocked (§Blocked actions) and is independently
  useless against a full volume.
- It is **not** a fix for #7247. It is the measurement #7247 needs before a fix can be chosen.
- It does **not** touch `var.registry_server_type`. That is #7309 / PR #7325's scope.
- It does **not** fire, stage, or prepare any registry recreate, `registry-host-replace`, or
  `registry-luks-recut`. The recut is separately vetoed while #7278 is open (#7287).

---

## Measured findings this plan builds on (do not re-derive)

Recorded in `knowledge-base/project/specs/feat-one-shot-7278-registry-restart-lever/session-state.md`.

| Fact | Measurement | Source |
|---|---|---|
| The store is full, continuously | `pcent = 100` on 72/72 samples over 6 h | `SOLEUR_ZOT_DISK`, self-pulled 2026-08-06 |
| The filesystem is already grown to the device | `fs_size_gb=59` / `block_size_gb=60`, `resize_ok=true` | same |
| It is **not** OOM | `oom_kills=0`, `zot_anon_mb=36` against a `3072` MB cap | same |
| The loop is live | `zot_restarts` 15,640, climbing ~4.8/min | same |
| **No on-demand GC endpoint exists** | `/v2/_zot/gc`, `/v2/_catalog/gc`, `/_zot/gc`, `/v2/_zot/ext/gc` all 404; the pinned build's `BinaryType` excludes mgmt/scrub/search | probed 2026-08-05 |
| **No zot user holds `delete`** | `accessControl`: pull → `["read"]`; push → `["read","create","update"]` | `cloud-init-registry.yml` on `main` |

The last row is why **reclaim over the existing ingress is not available** and must not be
planned around as though it might be. Under deny-by-default `accessControl` the DELETE is
refused regardless of what the build implements, so the build-capability question is moot
and is **not asserted either way** (`hr-verify-repo-capability-claim-before-assert`).

### Correction to the superseded plan's hypothesis table

The 2026-08-04 plan carried `H2 — store exhaustion causes the loop — **UNKNOWN, direction
unresolved**`. The direction is now decided in one direction only: **the disk is the binding
constraint** (`pcent=100` continuously on a fully-grown fs, `resize_ok=true`, zero OOM kills).
What remains **UNKNOWN** is *what is occupying the 59 GB*, and that is precisely this plan's
deliverable. Do not read the first resolution as resolving the second.

---

## Research Reconciliation — claims vs. codebase reality

| Claim | Reality (measured this session) | Plan response |
|---|---|---|
| **R1.** "Reach zot's OCI API by `curl https://registry.<base>/v2/…` with CF-Access headers — no bridge needed." | **Refuted, and already recorded in-repo.** `tunnel.tf`'s registry `ingress_rule` is `service = "tcp://${local.registry_endpoint}"` — a raw-TCP service. `model.c4` on the `tunnel -> zotRegistry` edge states it outright: *"a plain HTTPS GET here returns an empty 200 BY DESIGN (tcp:// ingress is not a WS upgrade) and is not a health probe."* | Use the **only** proven CI→registry transport: `.github/actions/cf-tunnel-registry-bridge` (`cloudflared access tcp` → `127.0.0.1:5000`), then plain HTTP to the local listener. §Decision D1. |
| **R2.** "`scripts/betterstack-query.sh` can also emit." | **False.** It POSTs **ClickHouse SQL** to `https://${BETTERSTACK_QUERY_HOST}` using `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`. Its own header says the `BETTERSTACK_LOGS_TOKEN` is **INGEST-ONLY (write)** and is a different credential. | Query and ingest are two different credentials on two different endpoints. §Decision D4/D5. |
| **R3.** "A CI job can already emit a `SOLEUR_*` marker to Better Stack." | **No CI-side emitter exists.** Every `SOLEUR_*` in `.github/workflows/` is either `echo`'d to the job log or passed as a `--grep` argument. `grep -rln 'betterstackdata\|in.logs.betterstack' .github/` returns one file, and only as a comment + a `sed` assertion in `validate-vector-config.yml`. | The **capability** exists (token + endpoint + a canonical idiom); the **CI precedent** does not. This PR is the first. Stated plainly, and it is why an ADR + C4 edit are deliverables. §Decision D4. |
| **R4.** "`secrets.DOPPLER_TOKEN` can read the registry credentials." | **False and load-bearing.** `secrets.DOPPLER_TOKEN` is scoped to the `prd_terraform` **branch** config; `REGISTRY_PUSH_ACCESS_TOKEN_*` and `ZOT_*` live in the `prd` **root**, and `reusable-release.yml:580` states *"branch configs do NOT inherit from the 'prd' root."* | Use `secrets.DOPPLER_TOKEN_PRD` (prd root), which is what all four existing bridge callers pass. Getting this wrong ships a credential-less workflow. §Decision D3. |
| **R5.** "The registry Access token is named `registry_push`, so using it grants push." | **Conflates two gates.** `tunnel.tf` states it: *"is BOTH gates: this CF Access service token (network/edge) + the zot-push htpasswd (registry)."* CF Access gates the **hostname**; zot's htpasswd + `accessControl` gate the **action**. | Present the existing Access service token at the edge; authenticate to **zot** as the read-only pull user (`ZOT_PULL_USER`/`ZOT_PULL_TOKEN`). No write capability is conferred. §Decision D1. |
| **R6.** "A naive sum of manifest layer sizes gives the bytes on disk." | **Would fabricate a number.** OCI blobs are content-addressed and shared across tags *and* repos; the keep-set is `latest` + `v.*`×5 + `[0-9a-f]{7,64}`×5 + `sha256-.*`×50 per repo, ×2 repos. A naive sum double-counts every shared base layer. | **Deduplicate by digest.** §Decision D2. This is the single arithmetic property the whole deliverable rests on. |
| **R7.** "The enumeration will complete." | **Expected to fail intermittently.** zot is restarting ~4.8/min *right now*, and the composite's own header records the 2026-08-03 case where *"a tens-of-seconds docker login + three-tag crane copy is near-certain to straddle"* a restart. | A **partial** sweep under-reports and manufactures a large delta that *looks like the answer*. Completeness is a first-class emitted field and the primary AC is conditioned on it. §Decision D2, AC1. |
| **R8.** "The prior plan's ADR-169 ordinal is still free." | **Taken.** `ADR-169-what-authorizes-destroying-the-sole-pull-path.md` exists on disk; max ordinal is **ADR-170**. | Next-free is **ADR-171**, PROVISIONAL. §Architecture Decision. |
| **R9.** "`crane` is available on the runner." | **Not preinstalled.** There is an established pinned-install spine at `apply-web-platform-infra.yml:2039` and `:2849` — `CRANE_VERSION="v0.20.2"`, `CRANE_SHA256="c14340087103ba9dadf61d45acd20675490fd0ccbd56ac7901fc1b502137f44b"` — whose parity across sites is enforced by `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` **anchored on the assignment**. | Reuse the spine verbatim; Phase 0 confirms whether adding a site requires extending the parity test. §Decision D2. |
| **R10.** "A new workflow can be dispatched from the feature branch to verify it pre-merge." | **False.** `workflow_dispatch` requires the file on the **default branch**; `gh workflow run … --ref <feature-branch>` returns `HTTP 404: workflow not found on the default branch`. | The runner-egress question cannot be settled pre-merge. Handled honestly rather than papered over. §Decision D6. |

---

## Hypotheses

`hr-ssh-diagnosis-verify-firewall` / the network-outage checklist fires on this plan
(`handshake`, `timeout`, `5xx` appear in its reachability surface). The reachability
question here is **CI runner → CF edge → tunnel → zot** and **CI runner → Better Stack
ingest**, so the L3→L7 layers are answered against those paths. Unverified layers are
listed **first**, and every "verified" carries an artifact, never "obvious".

| # | Layer | Hypothesis | Status | Discriminator / artifact |
|---|---|---|---|---|
| **H1** | **L3 — firewall** | The registry host's Hetzner firewall blocks the runner. | **VERIFIED NOT-APPLICABLE (artifact).** The host firewall is deny-all-public **by design**; the runner never dials it directly. The path is runner → CF edge → a web-host `cloudflared` connector inside `10.0.1.0/24` → `tcp://10.0.1.30:5000`. Four existing workflows traverse it in production today. | `tunnel.tf` registry `ingress_rule`; `model.c4 tunnel -> zotRegistry`; the four callers of `cf-tunnel-registry-bridge`. |
| **H2** | **L3 — DNS/routing** | `registry.<base>` does not resolve, or resolves off-tunnel. | **VERIFIED (artifact).** `cloudflare_record.registry` is a CNAME to the tunnel and is exercised by every release. Independently re-probed each release by `scripts/registry-pull-path-health.sh`. | The record in `dns.tf` + a green release traversal. |
| **H3** | **L7 — edge admission** | CF Access refuses the runner's service token (the #7071 class: Terraform replaced the token and the stale value was still served). | **UNKNOWN — has a live detector.** Presents as an indistinguishable 403 / `websocket: bad handshake`. | `scripts/check-cloudflare-token-drift.sh --only REGISTRY_PUSH_ACCESS_TOKEN`, already wired into `scheduled-terraform-drift.yml` and the release preflight. The lever **runs it as a preflight** and branches on its four-valued verdict (`live\|stale\|unverifiable\|unmeasured`) — mirroring `reusable-release.yml:514-560`. |
| **H4** | **L7 — origin availability** | The origin dial fails because **zot is restarting**, not because of anything at the edge. | **KNOWN-LIVE and expected.** Measured 2026-08-03 (#7242): the route was present *and* Access admitted the request; the origin was crash-looping. `zot_restarts` is climbing right now. | Do **not** name a cause. Branch on `scripts/zot-mirror-diagnosis.sh`'s measured verdict (ADR-166), which is the in-repo remedy for exactly this misattribution. **`bad handshake` is a symptom, never a cause.** |
| **H5** | **L7 — application** | The pull user cannot read `/v2/_catalog`, so the enumeration silently under-reports. | **UNKNOWN — measured by the run.** `accessControl` grants the pull user `read`, but whether `_catalog` itself is readable under that policy is not asserted. | The run emits `repos=<N>` and a distinct `reason=catalog_unreadable` verdict. An empty catalog is reported as a **named failure**, never as "0 GB referenced". |
| **H6** | **L7 — telemetry egress** | A GitHub runner cannot reach Better Stack Logs ingest, or the region/cluster pin refuses it. | **UNKNOWN, and NOT settleable pre-merge** (R10). `zot-registry.tf:115` records source 2457081 as region/cluster-pinned to `eu-fsn-3`; runner egress geography is untested against that pin. | Phase 0 proves token + endpoint + readback **from this workstation** (an explicit partial). The runner half is measured by the lever's own round-trip gate at first dispatch, which **fails loud**. Fallback is the already-proven CI→Sentry egress. §Decision D6. |
| **H7** | **the domain question** | The 59 GB is all policy-kept blobs. | **UNKNOWN. This is the hypothesis the plan exists to test, and it must not be upgraded before the run produces `enumeration_complete=true`.** | `delta_gb = fs_used_gb − manifest_referenced_gb` (dedup). |

**No verdict above may be upgraded without its discriminator.** In particular, a small
`delta_gb` does **not** by itself confirm H7 unless `enumeration_complete=true` — a partial
sweep can produce any delta at all.

---

## Decisions

### D1 — Transport: the existing `cf-tunnel-registry-bridge` composite, with a new `skip-docker-login` input

The registry ingress is `tcp://`, so there is no HTTP path to the origin (R1). The proven
transport is `cloudflared access tcp --hostname registry.${APP_DOMAIN_BASE} --url 127.0.0.1:5000`,
already packaged in `.github/actions/cf-tunnel-registry-bridge/action.yml` and used by four
production workflows.

**The composite's final step is `docker login 127.0.0.1:5000` with `ZOT_PUSH_USER`/`ZOT_PUSH_TOKEN`.**
A read-only inventory lever must not materialise **write** credentials for the sole pull path
into its runner — that would violate this plan's own allow-list (§D7) on the very surface it
is instrumenting.

**Chosen:** add an input `skip-docker-login` (default `false`) that gates **both** the
`ZOT_PUSH_*` pull/decode **and** the `docker login` step. Default-false is a zero-behaviour
change for all four existing callers, and the bridge itself (and `REGISTRY_BRIDGE_PID`) is
unaffected because the login is the composite's last step.

| Alternative | Verdict | Reason |
|---|---|---|
| Inline the `cloudflared access tcp` bridge in the new workflow | Rejected | Duplicates the SHA-pinned cloudflared install (`2026.5.0` / `0095e46f…`) into a fifth site. The composite header's own SHA-RECOMPUTE DISCIPLINE section exists because that pin drifts. |
| Use the composite as-is and accept the push-cred `docker login` | Rejected | Grants the read-only lever write capability on the sole pull path. A reviewer would flag it, correctly. |
| Mint a **new** `registry_inventory` CF Access service token | Rejected — **but v1's stated reason was mechanically false; the corrected reason is below** | **v1 claimed** the new token would enter `hcloud_server.registry`'s `depends_on` and, because `-target` is transitive, plan as `+ create` inside the three registry gates and brick the recut. **That is wrong: `-target` closes over *dependencies* (upstream), not *dependents*.** A CI-only Access token is not a dependency of any of the six allowed addresses, so it never enters those graphs and `out_of_scope` stays 0. The in-repo counterexample is decisive — the closest precedent, `cloudflare_zero_trust_access_service_token.registry_push` and its two `doppler_secret`s, is **not** in `hcloud_server.registry`'s `depends_on`, which is exactly four entries (`registry_betterstack_logs_token`, `zot_pull_token_registry`, `zot_push_token_registry`, `registry_luks_key`). **The real hazard, which is stronger and generalizes:** a new CF Access token + its Doppler secrets have **no scoped apply path**. None of the registry dispatch targets would create them, so landing them requires an **untargeted** apply — and an untargeted plan today carries the pending `-/+ hcloud_server.registry` into the #6929 fatal. That reasoning applies to *any* new `.tf` resource, so it strengthens §D8 rather than being a special case. |

**Caller-side teardown is mandatory** — the composite cannot register a post-job hook. Copy
its documented `if: always()` teardown verbatim (`docker logout` guarded, `kill $REGISTRY_BRIDGE_PID`,
`tail /tmp/cloudflared-registry.log`).

### D2 — Enumerator: pinned `crane`, deduplicated by digest, with completeness as a first-class field

`crane` v0.20.2 (the existing pinned spine, R9) already handles OCI tag pagination and
image-index recursion, and is already used against **this exact registry over this exact
bridge** by the #7277 restore path. Reuse it rather than hand-rolling `/v2/` pagination.

The algorithm:

1. `crane catalog` → repositories.
2. Per repo: `crane ls` → tags (includes the `sha256-*` cosign referrer tags).
3. Per tag: `crane manifest` → if it is an image **index**/manifest-list, recurse into each
   `manifests[].digest`; otherwise it is an image manifest.
4. Accumulate into a digest-keyed set: `config.digest → config.size`, each
   `layers[].digest → layers[].size`, **and** each manifest's own digest → its size
   (manifests are stored as blobs too).
5. `manifest_referenced_bytes = Σ(size)` over the **unique digest set**.

**Deduplication by digest is non-negotiable** (R6). A naive sum over tags would multiply
every shared base layer by the number of tags referencing it and produce a number with no
relationship to the disk.

**Completeness is emitted, not assumed** (R7). The script emits `repos`, `tags`,
`manifests_fetched`, `manifest_errors`, and `enumeration_complete`. Any per-request failure
after its bounded retry sets `enumeration_complete=false` and `outcome=partial`. **The
primary acceptance criterion is conditioned on `enumeration_complete=true`** — because a
partial sweep produces a large delta that is indistinguishable from the finding.

Recorded alternative: raw `curl -u` + `jq` driving `/v2/` by hand. Rejected as primary —
it re-implements pagination and index recursion that `crane` already gets right, and it is
the shape most likely to silently under-enumerate.

### D3 — Credentials: all existing, all in one Doppler config, zero new secrets

Verified this session by listing **names only** (never values):

| Need | Doppler secret name | Config | Reached in CI via |
|---|---|---|---|
| CF Access edge admission for `registry.<base>` | `REGISTRY_PUSH_ACCESS_TOKEN_ID` / `_SECRET` | `soleur` / `prd` | the composite, given `doppler-token` |
| zot **read-only** auth | `ZOT_PULL_USER` / `ZOT_PULL_TOKEN` | `soleur` / `prd` | `secrets.DOPPLER_TOKEN_PRD` |
| Registry endpoint / domain | `ZOT_REGISTRY_URL`, `APP_DOMAIN_BASE` | `soleur` / `prd` | same |
| Better Stack **ingest** | `BETTERSTACK_LOGS_TOKEN` | `soleur` / `prd` | same |
| Better Stack **query** (readback) | `BETTERSTACK_QUERY_HOST` / `_USERNAME` / `_PASSWORD` | — already GitHub Actions repo secrets | `secrets.BETTERSTACK_QUERY_*` (precedent: `scheduled-zot-restart-loop.yml:71-73`) |

One Doppler token (`secrets.DOPPLER_TOKEN_PRD`, the prd **root**) plus three existing GH
secrets. **No new Doppler secret, no new GitHub secret, no new Terraform resource.**
Always pass `-p soleur -c prd` explicitly — the explicit binding is what makes a mis-scoped
token fail loudly instead of silently (R4).

Note on the superseded plan's R8 (*"registry-ctl credentials must not land in `soleur/prd`
root — the release token reads it"*): **it does not apply here.** This plan **writes nothing**;
it reads secrets that are already there, and the strongest capability it holds is the
**read-only** pull user, which the release token already holds.

### D4 — The marker and its emission path (the design question, resolved)

**Endpoint:** `https://s2457081.eu-fsn-3.betterstackdata.com/` — a hardcoded, non-secret
`local.betterstack_logs_ingest_url` at `apps/web-platform/infra/zot-registry.tf:125`.
**Auth:** `Authorization: Bearer $BETTERSTACK_LOGS_TOKEN`.
**Idiom:** the canonical one at `cloud-init-registry.yml:408-416` — `curl -fsS -m 10`,
JSON `{"message":"<LINE>"}`, retried **once**, then a breadcrumb.

**MEASURED: no GitHub Actions workflow has ever POSTed to Better Stack** (R3). The ingest
capability is reachable from CI with zero new secrets; the CI-side precedent is not. This PR
creates it, which is why the C4 edges that currently assert *"CI polls read-only"* become
false and must be corrected (§Architecture Decision).

The marker line — all fields space-free so `key=value` parsing cannot be corrupted:

```
SOLEUR_ZOT_INVENTORY run_id=<gh-run-id> outcome=<ok|partial|failed> reason=<enumerated|->
  repos=<N> tags=<N> manifests_fetched=<N> manifest_errors=<N> enumeration_complete=<true|false>
  unique_blobs=<N> manifest_referenced_bytes=<N> manifest_referenced_gb=<N.N>
  fs_size_gb=<N> pcent=<N> fs_used_gb=<N.N> delta_gb=<N.N> disk_sample_age_s=<N>
  largest_repo=<name> largest_repo_gb=<N.N>
```

`fs_size_gb` / `pcent` are **self-pulled** from the existing `SOLEUR_ZOT_DISK` marker
(`hr-no-dashboard-eyeball-pull-data-yourself`); `disk_sample_age_s` is carried so a stale
disk sample cannot silently stale the delta.

**PII: none by construction.** The line carries byte counts, object counts, our own OCI repo
names and digests. A CI POST bypasses Vector's VRL scrub (`cloud-init-inngest.yml:112-113`
pre-redacts for this reason), so a test asserts the emitted line matches a **strict allowed-field
allow-list** and contains no credential-shaped token.

**No stub.** The emitter either POSTs or the run fails with a named reason. A "wire it in
later" emitter is a silent telemetry-loss vector.

### D5 — Verification is a telemetry round-trip, never the lever's self-report

After the POST, the workflow polls
`scripts/betterstack-query.sh --since 15m --grep SOLEUR_ZOT_INVENTORY` (bounded budget) and
requires the line carrying **this run's `run_id`**. Only then is the run green.

This is the property `hr-observability-as-plan-quality-gate` asks for: the emitter's exit
code cannot fake a row in the warehouse. On failure the run emits
`outcome=failed reason=marker_not_observable`, **exits 1**, and *also* prints the computed
line to the job log — the log exists so the operator does not lose the figure, and is
**never** the pass condition.

### D6 — The runner-egress unknown, handled honestly

The region/cluster pin (H6) cannot be tested from a runner pre-merge (R10). Three honest moves,
no invented endpoint:

1. **Phase 0 measures the half that is measurable**: from this workstation, POST a synthetic
   `SOLEUR_ZOT_INVENTORY_PROBE` and round-trip it. This proves token validity, endpoint,
   readback, and marker greppability. **It does not prove runner egress** — stated as an
   explicit bound in the plan and in the Phase-0 record.
2. **The lever's own round-trip gate is the runner-side measurement**, at first dispatch.
   That is why it must fail loud (§D5) rather than warn.
3. **If falsified**, mirror through `.github/actions/sentry-heartbeat` — the *already-proven*
   CI-side observability egress (used by `scheduled-zot-restart-loop.yml` with
   `secrets.SENTRY_INGEST_DOMAIN` / `_PROJECT_ID` / `_PUBLIC_KEY`). Choose only on evidence;
   do not pre-build it.

Closure is **automated, not remembered**: `scripts/followthroughs/zot-inventory-marker-7278.sh`
passes only once a real `SOLEUR_ZOT_INVENTORY` line is observed (§Follow-Through Enrollment).

### D7 — Action allow-list

- **Exactly one action: `inventory`.** No command grammar, no forwarded parameters, no shell
  interpolation of any dispatch input into a URL or a command.
- **HTTP verbs against the registry: GET/HEAD only.** No POST/PUT/PATCH/DELETE. Asserted from
  the script source by a test.
- **`scripts/zot-inventory.sh` owns all registry and telemetry egress**, and reaches exactly
  two destinations: `http://127.0.0.1:5000` (the bridge) and
  `https://s2457081.eu-fsn-3.betterstackdata.com/` (the marker POST, not a registry call).
  **This is a property of the script, not of the job** — v1 stated it as the latter and was
  wrong. The *job* additionally reaches, all pre-existing and all required:
  `api.cloudflare.com` (token-drift preflight), `api.doppler.com` (every secret read),
  `github.com` (checkout + the pinned cloudflared and crane release assets), the Cloudflare
  edge (`registry.<base>`, WSS), and `$BETTERSTACK_QUERY_HOST` (the ClickHouse readback — a
  *different* host from the ingest URL). The enumeration is the useful artifact; the absolute
  was false. AC2 is scoped to the script accordingly.
- **The zot-layer credential is the `read`-only pull user.** With `skip-docker-login: true`
  the job **does not materialize `ZOT_PUSH_*` into its environment and does not leave a docker
  session authenticated** to the registry.
  **Stated precisely, because v1 overclaimed:** the job still holds `secrets.DOPPLER_TOKEN_PRD`,
  which is scoped to the whole `soleur/prd` **root config** and can therefore read
  `ZOT_PUSH_TOKEN` in one command — `apply-web-platform-infra.yml`'s `registry_store_restore`
  job does exactly that with the same token. Doppler service tokens are **config-scoped, not
  secret-scoped**, so there is no variant that reads `ZOT_PULL_TOKEN` without also being able to
  read `ZOT_PUSH_TOKEN`. Narrowing further would need a new isolated Doppler config — **not
  done here**, because a new `doppler_project`/`doppler_secret` is a Terraform change with no
  scoped apply path (§D8), which is the same reason §D1 rejects a new CF Access token.
  The mechanism this plan buys is **non-materialization, not non-possession.** v1's verb was
  wrong and it was headed into ADR-171.
- **The narrow claim is made self-enforcing:** `scripts/zot-inventory.sh` asserts at entry that
  `ZOT_PUSH_USER` and `ZOT_PUSH_TOKEN` are unset/empty in its environment and exits non-zero if
  either is populated. That is the "measure something the failure state cannot produce"
  discipline applied to the plan's own privilege claim — and it catches a mis-keyed
  `skip-docker-login` regardless of what the workflow YAML says.

### D8 — Zero Terraform, and why that is load-bearing

**This plan edits no `.tf` file.** That is an acceptance criterion, not an incidental property:

- `hcloud_server.registry` deliberately carries **no** `lifecycle.ignore_changes = [user_data]`,
  and `user_data` is ForceNew. It **already has a pending REPLACE in state.**
- A replace today opens `/dev/mapper/registry` against a still-plaintext ext4 volume (#6929,
  OPEN) → the `refusing-non-luks-device` arm → **permanently dark registry**.
- Therefore **any untargeted `terraform plan` showing a registry replace is a STOP, not a
  proceed**, and this plan must contribute nothing to that graph.

Nothing in this design needs a Terraform change. If /work discovers otherwise, that
dependency must be surfaced **explicitly and loudly** and the plan re-scoped — never quietly
armed.

---

## Blocked actions (named, not dropped)

The issue asks for a lever. Three of the four plausible actions are **BLOCKED ON A
PROVISIONING EVENT** and are recorded here so they are not silently lost or rediscovered
under pressure.

| Action | Status | Why |
|---|---|---|
| `inventory` | **DELIVERED BY THIS PLAN** | The pull user holds `read`; the transport, the credentials and the telemetry all already exist. |
| `restart` | **BLOCKED ON A PROVISIONING EVENT** | Needs host execution. There is no in-place execution path (ADR-096: the registry host is cloud-init-only). *Independently*, it would not help: `--restart unless-stopped` has restarted zot **15,640** times into the same full volume. |
| `push-config` (e.g. tighten the keep-set, grant `delete`, add per-path telemetry) | **BLOCKED ON A PROVISIONING EVENT** | `/etc/zot/config.json` and the monitor scripts are written by cloud-init. |
| `reclaim` | **BLOCKED ON A PROVISIONING EVENT**, *and* independently blocked today | **No zot user holds `delete`** (measured), so manifest DELETE over the existing ingress is refused. Granting `delete` means editing the cloud-init-written config — i.e. back into the same blocker. And no on-demand GC endpoint exists (measured). |

### The deadlock, stated

Every WRITE-shaped remediation needs a config change on the host → needs cloud-init to
re-run → needs a host **replace** → and a replace today opens `/dev/mapper/registry` against
a still-plaintext ext4 volume (#6929, OPEN) → registry permanently dark.

That is why this plan is scoped to the read-only half: it is the entire set of useful work
that is on the near side of that deadlock.

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — the lever is dispatch-only
and read-only, so a broken lever is a lever that does not run. The *indirect* harm is the one
that matters: a lever that returns a **confident-looking but partial** number would send the
next remediation at the wrong target while releases stay blocked (#7247 is live). That is why
`enumeration_complete` gates the primary AC.

**If this leaks, the user's workflow is exposed via:** the CF Access service token plus the
zot **pull** credential together permit reading our own OCI image bytes — the same capability
every web host already has over the private network, and the same the release pipeline already
holds. No user or customer data is reachable from this surface at any point. With
`skip-docker-login: true` the job holds **no** write capability on the registry.

- **Brand-survival threshold:** `aggregate pattern`

Rationale for not selecting `single-user incident`: no user or customer data traverses this
surface, so no single user's breach is possible through it. The harm is fleet-wide release
availability, felt in aggregate. The threshold is set on the evidence, not to select a review
tier.

---

## Architecture Decision (ADR/C4)

This changes a documented data-flow boundary: **CI gains a WRITE (ingest) direction to Better
Stack Logs**, which two C4 anchors currently state is read-only. Per
`wg-architecture-decision-is-a-plan-deliverable` the ADR and the C4 edits are deliverables of
**this** plan, not follow-ups.

### ADR

**Create `ADR-171-ci-side-observability-emission-and-read-only-registry-inventory.md`.**

Ordinal is **PROVISIONAL**: max on disk is **ADR-170** (ADR-169 is taken by
`what-authorizes-destroying-the-sole-pull-path`), so 171 is next-free — but a sibling PR can
claim it during the pipeline and `adr-ordinals` is not a required check. **Re-derive against
freshly-fetched `origin/main` at ship**, and if it moves, sweep in the same edit:
`grep -rn 'ADR-171' knowledge-base/project/{plans,specs}/feat-one-shot-7278-registry-restart-lever/`.

Decisions to record:

- **GitHub Actions may emit `SOLEUR_*` markers to Better Stack Logs ingest**, not only query
  it — with the constraint that a CI POST bypasses Vector's VRL scrub, so a CI-emitted marker
  must be PII-free by construction and asserted so by a test.
- **A CI-emitted marker is only trusted once it is read back out of the warehouse.** The
  emitter's exit code is not evidence.
- **The registry's read-only surface is reachable today and its write surface is not** — with
  the `accessControl` measurement and the #6929 deadlock as the recorded reasons, so the
  restart/push-config/reclaim scope is not re-proposed as though it were available.
- **Alternatives Considered:** a new `registry_inventory` CF Access token (rejected — it
  bricks the recut gates, §D1); an inlined cloudflared bridge (rejected — pin drift); a
  restart-only lever (rejected — refuted by 15,640 restarts against a full volume);
  reclaim via manifest DELETE (rejected — no user holds `delete`).
- **Amend ADR-096** with the consequence this measurement exposes: making the registry host
  cloud-init-only means every host-side capability waits for a provisioning event, and while
  #6929 is open there is no safe provisioning event — so the *read-only* surface is the only
  instrumentable one.

### C4 views

All three of `model.c4`, `views.c4` and `spec.c4` were read. Enumeration behind the
"no new element" conclusion:

- **(a) External human actors:** the operator (`founder`) — already modeled. The lever is
  fired from GitHub Actions. **No new actor.**
- **(b) External systems / vendors:** GitHub (`github`), Cloudflare tunnel/Access (`tunnel`,
  `cloudflare`), Better Stack (`betterstack`), Doppler (`doppler`), Sentry (`sentry`) —
  **all already modeled. No new vendor.**
- **(c) Containers / data stores touched:** `zotRegistry` — already modeled. **No new store.**
- **(d) Access relationships that change:** **YES — two, and this is the whole C4 delta.**

Edits required in `model.c4` (no new `view … include` line is needed — every element already
appears in the views that list it):

1. **`github -> betterstack`** currently reads *"Polls the `SOLEUR_ZOT_DISK` + `SOLEUR_PRIVATE_NIC`
   Logs sources … ALSO reads the heartbeats API **read-only**"*. Add the **ingest (write)
   direction**: CI emits `SOLEUR_ZOT_INVENTORY` to source 2457081 via the Logs ingest endpoint
   with `BETTERSTACK_LOGS_TOKEN` from `soleur/prd`, and verifies by reading it back through the
   same ClickHouse query path.
2. **`betterstack` element description** contains *"a Logs warehouse (source 2457081,
   ClickHouse-SQL-queryable) that **CI polls read-only**"*. That clause becomes **false** —
   correct it. (The C4 completeness mandate requires fixing descriptions the change falsifies.)
3. **`github -> zotRegistry`** currently describes only the #7277 **RESTORE** path
   (`crane copy` + `crane validate --remote`). Add the **read-only INVENTORY** traversal:
   `crane catalog`/`ls`/`manifest` as the **pull** user over the same `cloudflared access tcp`
   bridge, enumerating manifest-referenced bytes deduplicated by digest.
4. **`zotRegistry -> betterstack`** — add a one-clause note that `SOLEUR_ZOT_INVENTORY` is
   emitted by **GitHub**, not by the host, so a reader does not go looking for a host-side
   emitter that does not exist.

Then run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing

The ADR ships with status `adopting` and flips to `accepted` once a real dispatch produces an
observed `SOLEUR_ZOT_INVENTORY` line (the follow-through probe is the flip condition).

---

## Infrastructure (IaC)

### Terraform changes

**None.** This is the deliberate, load-bearing property of the design (§D8). Every credential,
every endpoint, every ingress rule and every Access policy this plan uses **already exists and
is already applied**.

### Apply path

**Not applicable — no infrastructure is provisioned.** The change is confined to
`.github/workflows/`, `.github/actions/`, `scripts/`, `knowledge-base/` and the C4 model. No
host config changes, so `hr-prod-host-config-change-immutable-redeploy` is not engaged.

### Distinctness / drift safeguards

- `hcloud_server.registry` keeps **no** `lifecycle.ignore_changes = [user_data]` — preserved
  exactly, because nothing here touches it.
- The **pending REPLACE already in state** is not disturbed and is not acted on. An untargeted
  plan showing it is a STOP.
- `var.registry_server_type` is untouched (#7309 / PR #7325 owns it).
- The CF Access service token's expiry/rotation drift is already covered by
  `scripts/check-cloudflare-token-drift.sh` + `cloudflare_notification_policy.service_token_expiry`;
  no new token means no new registration is required.

### Vendor-tier reality check — recurring cost

**EUR 0.00 / month.** Stated explicitly so `wg-record-recurring-vendor-expense-before-ready`
is *satisfied*, not skipped:

- No new vendor, no new paid-tier resource, no new host, no new volume.
- No new Cloudflare Access application, service token, tunnel ingress rule or DNS record.
- No new Doppler secret and no new Doppler project or config.
- Better Stack: **one additional log line per manual dispatch**, against a source already
  ingesting ~288 `SOLEUR_ZOT_DISK` lines/day plus Vector journald streams from every host.
  This is not a measurable tier movement.
- GitHub Actions: one manually-dispatched job, minutes-billed on an already-paid plan.

No operator cost acceptance is required because the delta is zero. If /work discovers any
non-zero recurring delta, that is a **STOP** and must be surfaced for explicit acceptance
before the PR is marked ready.

---

## Observability

Layer citation per `hr-observability-layer-citation`: this component runs **in GitHub Actions**,
not on the registry host. It therefore has **two** observability layers and they must not be
conflated:

- **The job itself** → the GitHub Actions run log + `::error::` annotations, and (on the
  fallback path only) the Sentry check-in via `.github/actions/sentry-heartbeat`.
- **The measurement it produces** → Better Stack Logs source **2457081**, written via the
  ingest endpoint and read via `scripts/betterstack-query.sh`. This is the layer that matters,
  because a run log is not queryable six hours later and the whole point is a durable figure.

The registry host runs **no Vector** (`grep -n vector apps/web-platform/infra/cloud-init-registry.yml`
→ no matches) and has no shell, which is why ADR-096 rejected a journald interim — but that
constraint governs the *host*, not this CI job, and is cited here only so the two are not confused.

```yaml
liveness_signal:
  what: "A SOLEUR_ZOT_INVENTORY line in Better Stack Logs source 2457081 carrying this run's run_id, outcome, enumeration_complete and delta_gb. Absence of the line is the failure signal — the run does not go green without observing it."
  cadence: "on demand, per workflow_dispatch (this is a lever, not a monitor); the existing 5-min SOLEUR_ZOT_DISK beat continues to supply fs_size_gb/pcent independently"
  alert_target: "Better Stack Logs source 2457081; absence surfaced by scripts/followthroughs/zot-inventory-marker-7278.sh via the scheduled-followthrough-sweeper, not a native Better Stack alert (ADR-096)"
  configured_in: ".github/workflows/registry-zot-inventory.yml (emit + round-trip assert); scripts/zot-inventory.sh (the marker line)"

error_reporting:
  destination: "SOLEUR_ZOT_INVENTORY outcome=failed|partial reason=<enumerated> to Better Stack Logs source 2457081, AND ::error:: + non-zero exit in the workflow run"
  fail_loud: "yes — the run exits 1 on: token-drift verdict stale/unverifiable; bridge-up failure; catalog unreadable; enumeration_complete=false; ingest POST failure; and round-trip non-observation. There is NO exit path that reports success without an observed marker carrying enumeration_complete=true."

failure_modes:
  - mode: "CF Access refuses the runner's service token (#7071 class) — indistinguishable 403 / bad handshake"
    detection: "scripts/check-cloudflare-token-drift.sh --only REGISTRY_PUSH_ACCESS_TOKEN preflight returns stale|unverifiable (the reusable-release.yml:514-560 four-valued verdict)"
    alert_route: "::error:: reason=access_token_stale + exit 1; already covered fleet-wide by scheduled-terraform-drift.yml"
  - mode: "the bridge comes up but the origin dial fails because zot is RESTARTING (#7242 class, live right now)"
    detection: "branch on scripts/zot-mirror-diagnosis.sh's MEASURED verdict (ADR-166) — never name bad handshake as a cause"
    alert_route: "::error:: reason=<the measured verdict> + exit 1; SOLEUR_ZOT_INVENTORY outcome=failed"
  - mode: "the pull user cannot read /v2/_catalog, so the sweep silently reports zero"
    detection: "repos=0 with a non-2xx catalog response is a DISTINCT named verdict, never 0 GB referenced"
    alert_route: "::error:: reason=catalog_unreadable + exit 1"
  - mode: "PARTIAL enumeration — a manifest fetch fails mid-sweep and the delta looks like the finding"
    detection: "manifest_errors > 0 after bounded retry sets enumeration_complete=false; the primary AC is conditioned on enumeration_complete=true"
    alert_route: "::error:: reason=enumeration_incomplete + exit 1; the marker IS still emitted with outcome=partial so the partial counts are recoverable"
  - mode: "the ingest POST fails (bad token, rate limit, egress blocked)"
    detection: "curl -fsS non-zero after one retry, mirroring the cloud-init idiom"
    alert_route: "::error:: reason=ingest_post_failed + exit 1; the computed line is printed to the job log for recovery, but the run FAILS"
  - mode: "the POST succeeds but the line never lands in the warehouse (region/cluster pin refuses runner egress — H6, UNMEASURED)"
    detection: "the bounded betterstack-query.sh poll never returns a line carrying this run's run_id"
    alert_route: "::error:: reason=marker_not_observable + exit 1 — explicitly NOT reported as an inventory failure, because the measurement succeeded and only its durability did not"
  - mode: "the SOLEUR_ZOT_DISK sample used for fs_size_gb/pcent is stale, staling delta_gb"
    detection: "disk_sample_age_s is carried in the marker; a sample older than a bounded threshold sets outcome=partial reason=disk_sample_stale"
    alert_route: "::warning:: + the field is emitted so a reader can judge; the delta is never presented without its sample age"

logs:
  where: "Better Stack Logs source 2457081 (SOLEUR_ZOT_INVENTORY); GitHub Actions run log"
  retention: "per the existing Better Stack Logs source retention — unchanged by this plan"

discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_ZOT_INVENTORY --limit 20"
  expected_output: "one SOLEUR_ZOT_INVENTORY line per dispatch carrying run_id=, outcome=, enumeration_complete=, repos=, tags=, unique_blobs=, manifest_referenced_gb=, fs_size_gb=, pcent=, delta_gb=, disk_sample_age_s= — and zero lines when the lever has never been dispatched. No SSH anywhere on this path."
```

### The positive-control requirement

Per `knowledge-base/project/learnings/2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md`,
the verification must measure something the failure state **cannot produce**. Here that is
concrete: `enumeration_complete=true` plus a `run_id` matching **this** run, read back out of
the warehouse. A crash-looping zot cannot produce a complete enumeration, and a dead ingest
path cannot produce a warehouse row.

### `lint-diagnosis-claims.sh` compliance (BLOCKING)

This lint's scope is `.github/workflows/`, `.github/actions/`, `scripts/` and
`apps/web-platform/infra/` — **three of which this PR touches** — it ships with a
`.highwater` ratchet and it is **BLOCKING** (registered in `scripts/test-all.sh`, whose
`scripts` shard feeds the required `test` job).

Every operator-facing `::error::` / `::warning::` this PR adds must therefore either
reference a **verdict/outcome variable the run computed**, or carry an explicit
`# MEASURED-BY: <what measured it>` marker. This is not incidental compliance — it *is* this
plan's thesis (`bad handshake` is a symptom, never a cause) applied to the plan's own output.

---

## Follow-Through Enrollment

The ADR's `adopting → accepted` flip and the H6 runner-egress answer are both gated on a real
dispatch, which cannot happen before merge (R10). That is a soak-shaped closure condition, so
it is **enrolled**, not remembered:

- **Script:** `scripts/followthroughs/zot-inventory-marker-7278.sh` — exit 0 only when a
  `SOLEUR_ZOT_INVENTORY` line with `enumeration_complete=true` is observed in Better Stack.
  Dispatch-gated, **not** date-gated (`earliest` is a floor, never the condition).
- **Directive:** `<!-- soleur:followthrough script=scripts/followthroughs/zot-inventory-marker-7278.sh earliest=<merge-date> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` on the tracker, plus the `follow-through` label.
- **Sweeper:** the three `BETTERSTACK_QUERY_*` secrets are **already** wired into
  `.github/workflows/scheduled-followthrough-sweeper.yml` (it uses them today) — confirm, do
  not re-add.

---

## Encryption Posture

Detection fires on the **new cross-component connection** limb (no `.tf`, `.sql`,
`cloud-init` or `docker-compose` file is touched — §D8).

**Schema note (verified against `scripts/encryption-posture-ledger.schema.json`, not paraphrased).**
The ledger's `connection` object is `additionalProperties: false` and requires exactly
`connection`, `enforced_at`, `in_transit`. `in_transit.cert_verification` is an **enum of
`on | off`** — free-text such as `"on for both TLS legs; n/a for the private leg"` **fails
validation**, and `off` **requires** an `exception` block carrying all four of `justification`,
`tracking_issue` (`^#[0-9]+$`), `reevaluate_when`, `expires_on` (`YYYY-MM-DD`, Layer-A-enforced
to ≤ 90 days). The two entries below are written in that exact shape; do not add annotation
keys (a `status:` field would fail `additionalProperties: false`).

```yaml
# Entry 1 — NEW, created by this plan.
- connection: "GitHub Actions runner -> Better Stack Logs INGEST (s2457081.eu-fsn-3.betterstackdata.com)"
  enforced_at: "scripts/zot-inventory.sh (the SOLEUR_ZOT_INVENTORY POST); URL pinned at apps/web-platform/infra/zot-registry.tf local.betterstack_logs_ingest_url"
  in_transit:
    tls: "https / TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "a leaked BETTERSTACK_LOGS_TOKEN (ingest-only: it can write log lines, it cannot read them); TLS protects the channel, not the credential. Also does not defend against a CI POST bypassing Vector's VRL PII scrub — mitigated by construction (the marker carries only counts, sizes, our own OCI repo names and digests) and asserted by a field allow-list test."
    disclosed_as: "not-publicly-claimed"

# Entry 2 — PRE-EXISTING GAP, folded in because this plan adds the fifth caller.
- connection: "GitHub Actions runner -> zot registry over the CF Tunnel (registry.<base> -> tcp://10.0.1.30:5000)"
  enforced_at: ".github/actions/cf-tunnel-registry-bridge/action.yml (cloudflared access tcp); tunnel.tf registry ingress_rule"
  in_transit:
    tls: "runner<->CF edge and CF edge<->origin connector: TLS 1.2+ (raw TCP over WebSocket). origin connector<->10.0.1.30:5000: PLAIN HTTP on the Hetzner private network, by design."
    cert_verification: "off"
    does_not_defend: "a passive on-net attacker on 10.0.1.0/24 could read image bytes on the final leg; integrity comes from cosign digest-pinning, not TLS. Also does not defend a leaked CF Access service token or a leaked zot pull credential."
    disclosed_as: "not-publicly-claimed"
    exception:
      justification: "the same private-network-only exception already recorded for 'web hosts -> zot registry' — the final leg is plain HTTP inside the Hetzner private network; image bytes are our own OCI layers and integrity is cosign-digest-pinned"
      tracking_issue: "#6897"
      reevaluate_when: "the registry link gains TLS, or the store is exposed beyond the private network"
      expires_on: "2026-10-22"
```

`cert_verification: off` on entry 2 is the **honest** value: the enum has no way to say
"TLS on two legs, plaintext on the third", and the plaintext leg is the one that matters —
which is exactly why the existing `web hosts -> zot registry` entry also reads `off` with the
same `#6897` exception. Reusing that exception keeps one tracked decision rather than forking
a second.

**`at_rest`: not applicable.** The ledger's `at_rest` field belongs to `stores`, not
`connections`, and this plan introduces **no persistent store** — it reads an existing store
and writes one line to an existing sink. No `stores` entry is added.

Both entries go into `scripts/encryption-posture-ledger.json` `connections`, and
`python3 scripts/lint-encryption-posture.py` must exit 0. Entry 2 is a **pre-existing** gap
(four workflows already traverse that path; only `web hosts -> zot registry` is in the ledger)
— folded in rather than deferred, because this plan adds the fifth caller.

**Check `expires_on` at /work time.** `2026-10-22` is inherited from the existing `#6897`
exception. Layer A enforces ≤ 90 days *and* fails a lapsed exception — if that date has passed
or is out of window when the PR lands, the exception must be re-dated with #6897 re-evaluated,
not silently extended.

---

## Domain Review

**Domains relevant:** engineering, operations

### Engineering

**Status:** reviewed
**Assessment:** The change is confined to CI orchestration and read-only measurement. The two
architectural risks are (a) creating a **new egress direction** (CI → Better Stack ingest),
addressed by the ADR + C4 edits and a PII-free field allow-list, and (b) editing a **composite
action four production workflows depend on**, addressed by a default-`false` input plus a
guard test asserting the default and that no existing caller passes it. The dominant
correctness risk is not security but **arithmetic**: dedup-by-digest and completeness gating
(§D2), because a wrong number here would misdirect the remediation for a live incident.

### Operations

**Status:** reviewed
**Assessment:** EUR 0/mo, no new vendor surface, no new host, no change to the paging
topology. The lever is manual-dispatch and read-only, so it adds no scheduled load and cannot
degrade the sole pull path — the heaviest thing it does is ~300–500 GET requests through the
existing tunnel, comparable to a single release's mirror step. It **does** run against a
registry that is currently crash-looping, so it must be resilient to intermittent 5xx and must
never report a partial sweep as a result.

### Product/UX Gate

**Not applicable.** No file in `## Files to Create` or `## Files to Edit` matches any
UI-surface term or glob (no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`,
no route or template). The mechanical UI-surface override does not fire; Product is `NONE`.

### GDPR / Compliance Gate

**Skipped, with reason.** No regulated-data surface is touched: no schema, no migration, no
auth flow, no API route, no `.sql`. None of the four expansion triggers fire either — no
LLM/external-API processing of operator-session data; brand-survival threshold is
`aggregate pattern`, not `single-user incident`; nothing reads `knowledge-base/project/learnings/`
or `specs/`; no new artifact distribution surface. The one new data flow (CI → Better Stack)
carries byte counts, object counts, our own OCI repo names and digests — **no personal data**,
asserted by a field allow-list test.

---

## Open Code-Review Overlap

**None.** Queried all 64 open `code-review` issues against every path in
`## Files to Create` / `## Files to Edit`; zero bodies reference any of them.

---

## Implementation Phases

> Every step below runs from CI or from a repo script. There is no host execution and no
> interactive step anywhere in this plan.

### Phase 0 — Preconditions (verify, never assume)

- **0.1** Re-derive the next-free ADR ordinal against freshly-fetched `origin/main`. Plan
  assumes **171** (170 is max; 169 is taken) — PROVISIONAL.
- **0.2** Re-pull `SOLEUR_ZOT_DISK` and record `pcent`, `fs_size_gb`, `zot_restarts`,
  `oom_kills`. This is both a freshness refresh and the source of the marker's disk fields.
- **0.3** Confirm the `cf-tunnel-registry-bridge` composite's current step order and that the
  `ZOT_PUSH_*` decode and the `docker login` are the **only** steps to gate behind
  `skip-docker-login`. Confirm `REGISTRY_BRIDGE_PID` is exported **before** them.
- **0.4** Confirm the crane pin spine and whether adding a **fifth** site requires extending
  `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` (it anchors on the
  `CRANE_SHA256` assignment).
- **0.5** Confirm `crane`'s auth form against a plain-HTTP `127.0.0.1:5000` endpoint with the
  read-only pull user (which of `--insecure` / `crane auth login` / registry-config is
  required). If crane cannot be made to authenticate read-only against the local bridge, fall
  back to the recorded `curl -u` + `jq` alternative and record the reason.
- **0.6** **Ingest half-probe (explicit partial).** From this workstation, POST a synthetic
  `SOLEUR_ZOT_INVENTORY_PROBE` line to the ingest endpoint and round-trip it back via
  `betterstack-query.sh`. Record: token valid, endpoint correct, readback works, marker
  greppable. **Record the bound explicitly: this does NOT prove GitHub-runner egress against
  the `eu-fsn-3` region/cluster pin (H6).**
- **0.7** Confirm the three `BETTERSTACK_QUERY_*` secrets are already wired into
  `scheduled-followthrough-sweeper.yml` (do not re-add).
- **0.8** Confirm `scripts/lint-diagnosis-claims.sh`'s current `.highwater` baseline so the
  new messages can be authored under it from the start.

### Phase 1 — The enumerator (RED first)

- **1.1** Write failing tests before implementation (`cq-write-failing-tests-before`), in
  `tests/scripts/test-zot-inventory.sh`, driving `scripts/zot-inventory.sh` with a
  **PATH-shimmed `crane` and `curl`** (the established shell-mock pattern — the stub records
  `$*` to a file and the test greps it):
  - **1.1.1 Dedup arithmetic.** Two repos sharing a base layer digest → the shared layer is
    counted **once**. A naive-sum implementation must fail this test.
  - **1.1.2 Index recursion.** An image index whose children carry distinct layers → all
    children's blobs are counted.
  - **1.1.3 Partial sweep.** One manifest fetch fails after retry → `enumeration_complete=false`,
    `outcome=partial`, `manifest_errors=1`, and the script **exits non-zero**.
  - **1.1.4 Catalog unreadable.** Non-2xx `/v2/_catalog` → `reason=catalog_unreadable`, and
    **never** `repos=0` presented as a result.
  - **1.1.5 Egress confinement.** The recorded stub invocations target **only**
    `127.0.0.1:5000` and the pinned Better Stack ingest URL — no other host.
  - **1.1.6 Verb confinement.** No POST/PUT/PATCH/DELETE is issued against the registry.
  - **1.1.7 Marker hygiene.** The emitted line matches a strict allowed-field allow-list, has
    no whitespace inside any value, and contains no credential-shaped token. Feed it a
    synthetic token in the environment and assert it does not appear in the output.
  - **1.1.8 No-stub emitter.** With the ingest token unset, the script fails loudly — it does
    not silently skip the POST.
- **1.2** Implement `scripts/zot-inventory.sh`: `crane catalog` → `crane ls` → `crane manifest`,
  index recursion, digest-keyed accumulation, bounded per-request retry, marker construction,
  and the ingest POST using the `cloud-init-registry.yml:408-416` idiom verbatim (retry once,
  then breadcrumb). All egress lives in this one file so the confinement test has a single
  surface to assert over.
- **1.3** Mask `ZOT_PULL_TOKEN` under `GITHUB_ACTIONS` exactly as
  `scripts/registry-pull-path-health.sh` does.
- **1.4** Author every operator-facing message to satisfy `lint-diagnosis-claims.sh`: name only
  the verdict the run computed, or carry `# MEASURED-BY:`.

### Phase 2 — The composite input

- **2.1** Add input `skip-docker-login` (default `'false'`) to
  `.github/actions/cf-tunnel-registry-bridge/action.yml`, gating **both** the `ZOT_PUSH_*`
  decode **and** the `docker login` step, so a read-only caller never materialises push
  credentials into the runner environment at all.
- **2.2** Update the composite's header (the PREREQUISITES and OUTPUTS blocks) to state that
  `ZOT_PUSH_*` are required only when `skip-docker-login` is false.
- **2.3** Guard test asserting: the input exists, its default is `'false'`, the login step is
  gated on it, and **none of the four existing callers passes it** (so their behaviour is
  provably unchanged).

### Phase 3 — The workflow

- **3.1** `.github/workflows/registry-zot-inventory.yml`, mirroring
  `restart-inngest-server.yml`'s shape exactly:
  - `on: workflow_dispatch: {}` plus `push: {branches: [main], paths: ['.github/workflows/registry-zot-inventory.yml']}` — the push trigger exists **only** to register the workflow in the Actions UI.
  - Top-level `permissions: contents: read`.
  - **Job-level** `if: github.event_name == 'workflow_dispatch'` — without it, editing the
    file on `main` fires the op in production (#6425).
  - `concurrency: {group: registry-zot-inventory, cancel-in-progress: false}`.
  - `timeout-minutes` comfortably above the enumeration + round-trip budget.
  - `actions/checkout` SHA-pinned.
  - The dispatch input, if present, is a `choice` with the single value `inventory`; it is
    never interpolated into a URL or a command.
- **3.2** Steps: token-drift preflight → crane install (pinned spine) → bridge up
  (`skip-docker-login: true`, `doppler-token: ${{ secrets.DOPPLER_TOKEN_PRD }}`) → self-pull
  `SOLEUR_ZOT_DISK` → run `scripts/zot-inventory.sh` → round-trip assert → **`if: always()`
  teardown** (copy the composite's documented teardown verbatim).
- **3.3** The round-trip assert polls `betterstack-query.sh --since 15m --grep SOLEUR_ZOT_INVENTORY`
  on a bounded budget for a line carrying **this run's `run_id`**; failure is
  `reason=marker_not_observable`, `::error::`, exit 1 — with the computed line printed to the
  job log for recovery but never as the pass condition.

### Phase 4 — Guard test + CI wiring

- **4.1** `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh`, mirroring
  `restart-inngest-workflow-guard.test.sh`:
  - Parse with **python3 + pyyaml `yaml.safe_load`** and assert against the **parsed** YAML —
    never a grep.
  - Probe **both** key spellings for the YAML-1.1 truthy `on:` key:
    `on = wf.get("on", wf.get(True)) or {}`. pyyaml keys `on` as boolean `True`, so probing
    only `"on"` reads as "no triggers" and the test **passes vacuously**.
  - Run every comparison **inside python**, printing bare `yes`/`no` — the guard `if` string
    contains spaces and single quotes that round-tripping through shell `eval` mangles and
    silently false-FAILs.
  - Pin the job key deliberately (the precedent hard-codes `"restart"`; a guard on a
    differently-named job would not be seen).
  - Assert: workflow parses; the registration `push` trigger is present; `workflow_dispatch` is
    present; the job carries `github.event_name == 'workflow_dispatch'`; `permissions` is
    `contents: read`; the dispatch input (if any) is a `choice` whose options are exactly
    `['inventory']`.
- **4.2** **Both** CI wirings, or the test gates nothing:
  - a `run: bash apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh` step in
    `infra-validation.yml`'s `deploy-script-tests` job (that job has no `needs:` and no `if:`,
    and the workflow hand-enumerates every `.test.sh` with no glob runner);
  - `.github/workflows/registry-zot-inventory.yml` added to `infra-validation.yml`'s
    `pull_request.paths`.
- **4.3** Register `tests/scripts/test-zot-inventory.sh` in `scripts/test-all.sh`.

### Phase 5 — ADR + C4

- **5.1** Write `ADR-171-…` (ordinal from 0.1), status `adopting`, with all four rejected
  alternatives and the ADR-096 amendment (§Architecture Decision).
- **5.2** `model.c4` — the four edits in §Architecture Decision → C4 views.
- **5.3** Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- **5.4** If the ordinal moved in 0.1, sweep plan + tasks + every AC naming it in the same edit.

### Phase 6 — Runbook + triage pointers

- **6.1** `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`: add a
  "**try the inventory lever FIRST**" pointer ahead of any destructive path, plus a `## Related`
  entry. **The existing blocked-state banner is untouched** — the top "Corrected 2026-08-04"
  block and the "🚧 The remaining blocker" section must remain byte-identical. Verify with a
  diff restricted to those regions.
- **6.2** `scripts/zot-restart-loop-alarm.sh`: name the lever in the **crash-loop arm only**.
  **Leave every `NIC_CAUSE` arm untouched** — those are a different failure class a disk
  inventory cannot inform.
- **6.3** `.github/workflows/scheduled-zot-restart-loop.yml`: name the lever in the FIRE issue
  body — that is the surface a responder actually reads first.
- **6.4** `knowledge-base/project/specs/feat-one-shot-7247-zot-crash-loop-recovery/`: add the
  pointer to #7247's triage notes so the next session on that issue starts from the measurement
  rather than re-deriving the gap.
- **6.5** Verify no runbook text added anywhere in this PR contains an SSH step or any
  human-executed step.

### Phase 7 — Ledger + follow-through

- **7.1** Add the two `connections` entries to `scripts/encryption-posture-ledger.json` and run
  `python3 scripts/lint-encryption-posture.py`.
- **7.2** `scripts/followthroughs/zot-inventory-marker-7278.sh` + the tracker directive + the
  `follow-through` label (§Follow-Through Enrollment).

### Phase 8 — Exit gate

- **8.1** Full `tests/scripts/` suite plus `scripts/test-all.sh`.
- **8.2** `python3 scripts/lint-diagnosis-claims.sh` (or its `test-all.sh` entry) green against
  the ratchet.
- **8.3** Walk every Pre-merge AC and record evidence per AC.
- **8.4** Confirm the `iac-routing-ack` comment survived plan edits.

---

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 — the instrument is correct.** `tests/scripts/test-zot-inventory.sh` passes, including
  the dedup test (1.1.1), the index-recursion test (1.1.2), and the partial-sweep test (1.1.3).
  A naive-sum or completeness-blind implementation must **fail** these.
- **AC2 — allow-list.** Tests assert: exactly one action (`inventory`); no
  POST/PUT/PATCH/DELETE against the registry; egress confined to `127.0.0.1:5000` and the
  pinned Better Stack ingest URL; no dispatch input interpolated into a URL or command.
- **AC3 — guard.** The parsed-YAML guard test passes and probes **both** `"on"` and the
  YAML-1.1 truthy `True` key spellings. Deleting the job-level
  `if: github.event_name == 'workflow_dispatch'` must make it **fail**.
- **AC4 — the guard is wired.** The guard test is invoked from `infra-validation.yml`'s
  `deploy-script-tests` job **and** the new workflow's path is in that workflow's
  `pull_request.paths`. Both, verified by grep.
- **AC5 — no existing caller changes.** `skip-docker-login` defaults to `'false'` and none of
  the four existing `cf-tunnel-registry-bridge` callers passes it. Asserted by test.
- **AC6 — ZERO Terraform** *(pathspec CORRECTED per revision D-6 — v1's glob had measured holes:
  it missed `apps/web-platform/infra/cloud-init.yml` (**no hyphen** — the 51 KB web-fleet
  user_data template, whose edit ForceNew-replaces the web hosts while AC6 stayed green),
  `doppler-config-inventory.txt` (read by `file()` and driving a `for_each` on
  `doppler_service_token`), `vector.toml` plus ~55 other `${path.module}` sources baked into
  `user_data` or `triggers_replace = sha256(file(...))`, and all three `.terraform.lock.hcl`)*:

  ```
  git diff --name-only origin/main...HEAD \
    -- '*.tf' '*.terraform.lock.hcl' 'apps/web-platform/infra/**' 'infra/**' \
       'apps/cla-evidence/infra/**' 'tests/scripts/lib/*gate*.sh'
  ```

  returns **empty**, with `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh`
  as the **sole explicit carve-out** (verified consumed by no `templatefile()`/`file()` in any
  `.tf`). **Without the carve-out written in, the tightened command false-FAILs.**
  `var.registry_server_type` is untouched; `hcloud_server.registry` has no
  `lifecycle.ignore_changes = [user_data]` added or removed. No registry recreate,
  `registry-host-replace`, or `registry-luks-recut` is fired or staged anywhere in the diff.
  *(Not a hole: `*.tf` is a git pathspec glob and does span `/`; zero `.tfvars`/`.tf.json` files
  are tracked anywhere in the repo.)*
- **AC7 — marker hygiene.** The emitted line matches the field allow-list, carries no
  whitespace inside a value, and does not reproduce any credential present in the environment.
- **AC8 — fail-loud.** No code path in the workflow reports success without an observed marker
  carrying `enumeration_complete=true`. Verified by reading every exit path.
- **AC9 — diagnosis-claims lint.** `lint-diagnosis-claims.sh` is green at or below its current
  `.highwater`; every new `::error::`/`::warning::` references a computed verdict or carries
  `# MEASURED-BY:`.
- **AC10 — runbook banner intact.** The recut runbook gains the lever pointer, and a diff of
  the "Corrected 2026-08-04" block and the "🚧 The remaining blocker" section against
  `origin/main` is **empty**.
- **AC11 — NIC arms intact.** `scripts/zot-restart-loop-alarm.sh`'s diff touches only the
  crash-loop arm; every `NIC_CAUSE` arm is byte-identical to `origin/main`.
- **AC12 — ADR + C4.** `ADR-171-*.md` (ordinal re-derived at ship) exists with status
  `adopting`; the four `model.c4` edits are present, including correcting the now-false
  *"CI polls read-only"* clause; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC13 — encryption ledger.** Both `connections` entries are present and
  `python3 scripts/lint-encryption-posture.py` exits 0 reporting **5 connections** (baseline
  measured 2026-08-06: `16 stores, 3 connections, 0 unledgered, 0 failing checks -> PASS`).
  The count is asserted, not just the exit code — a silently-dropped entry would still exit 0.
- **AC14 — cost.** The PR body states **EUR 0.00/mo recurring delta** with the reasoning from
  §Vendor-tier reality check. No operator acceptance is required at zero; a non-zero delta
  discovered during /work is a STOP.
- **AC15 — follow-through enrolled.** `scripts/followthroughs/zot-inventory-marker-7278.sh`
  exists, the tracker carries the directive + `follow-through` label, and the three
  `BETTERSTACK_QUERY_*` secrets are confirmed already wired into the sweeper.
- **AC16 — no human-executed step.** No file added or edited in this PR prescribes an SSH step,
  a dashboard action, or any operator-executed provisioning step.

### Post-merge (automated, no operator step)

- **AC17 — PRIMARY: the unmeasured question is answered.** A dispatch of
  `registry-zot-inventory.yml` produces a `SOLEUR_ZOT_INVENTORY` line **observed in Better
  Stack** carrying `enumeration_complete=true` and a numeric `delta_gb`, and that figure is
  recorded on #7278 and #7247.
  **The deliverable is the number. The plan asserts no cause.** Neither branch below may be
  stated before the number exists:
  - `delta_gb` small (manifest-referenced ≈ `fs_used_gb`) ⟹ the keep-set **is** the consumer,
    and the remedy is keep-set tightening — which is **blocked on a provisioning event**.
  - `delta_gb` large ⟹ the consumer is **not** policy-kept blobs, and #7247's remedy is
    somewhere the current telemetry does not look.
  - `enumeration_complete=false` ⟹ **no conclusion is licensed at all**; re-dispatch.

  **Three bounds on the reading, all added at deepen (A2/A3), all load-bearing:**
  1. **`delta_gb` under ~3 GB is not distinguishable from zero.** `fs_used_gb` is derived as
     `fs_size_gb × pcent/100`, but `pcent` is `used/(used+avail)` — it **excludes** ext4's ~5 %
     root-reserved blocks while `fs_size_gb` includes them, so the derivation carries ~2.95 GB of
     systematic error on a 59 GB volume. `df --output=used` is not in the marker and §D8 forbids
     the cloud-init change that would add it.
  2. **`delta_gb` is an UPPER BOUND on unreferenced blob bytes, not a measurement of them.**
     `manifest_referenced_bytes` sums OCI blob `size` fields; zot's on-disk footprint also holds
     the dedupe cache DB (`"dedupe": true`) and `.uploads/` staging. The two named candidates —
     **orphaned upload sessions** (highly plausible: zot is restarting ~4.8/min while releases
     retry) and **the cache DB** — are the same number to this instrument and have completely
     different remedies. A large delta that does not name them has no next action.
  3. **The reading is void unless Phase 0.3 resolved the referrer-tag question** (A1). ~50 of
     ~61 tags per repo are cosign `sha256-*` referrers; if they are hidden from `tags/list`, ~80 %
     of tags go uncounted, `enumeration_complete` still reads `true`, and the delta is large and
     **spurious** — the precise shape §Sharp Edges warns about.
- **AC18 — H6 answered.** The first dispatch either observes the marker (runner egress works
  against the `eu-fsn-3` pin) or fails with `reason=marker_not_observable`, at which point the
  Sentry-mirror fallback (§D6.3) is chosen **on that evidence**. The follow-through script
  closes the loop automatically either way.
- **AC19 — ADR flip.** `ADR-171` moves `adopting → accepted` once AC17 is satisfied.

---

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/zot-inventory.sh` | The enumerator + marker emitter. **All network egress lives here** so the confinement test has one surface. |
| `tests/scripts/test-zot-inventory.sh` | Unit test with PATH-shimmed `crane`/`curl` stubs (1.1.1–1.1.8). |
| `.github/workflows/registry-zot-inventory.yml` | The dispatch-only lever. |
| `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh` | Parsed-YAML guard, mirroring the inngest precedent. |
| `scripts/followthroughs/zot-inventory-marker-7278.sh` | Dispatch-gated follow-through probe. |
| `knowledge-base/engineering/architecture/decisions/ADR-171-….md` | The decision record (ordinal PROVISIONAL). |

## Files to Edit

| Path | Change |
|---|---|
| `.github/actions/cf-tunnel-registry-bridge/action.yml` | Add `skip-docker-login` input (default `'false'`), gate the `ZOT_PUSH_*` decode + `docker login`, update the header. |
| `.github/workflows/infra-validation.yml` | Register the guard test in `deploy-script-tests`; add the new workflow to `pull_request.paths`. |
| `scripts/test-all.sh` | Register `tests/scripts/test-zot-inventory.sh`. |
| `scripts/zot-restart-loop-alarm.sh` | Name the lever in the **crash-loop arm only**. |
| `.github/workflows/scheduled-zot-restart-loop.yml` | Name the lever in the FIRE issue body. |
| `scripts/encryption-posture-ledger.json` | Two `connections` entries (§Encryption Posture). |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Four edits (§Architecture Decision → C4 views). |
| `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` | Lever pointer + `## Related`. **Banner untouched.** |
| `knowledge-base/project/specs/feat-one-shot-7247-zot-crash-loop-recovery/` | Point #7247's triage notes at the lever. |
| `apps/web-platform/infra/restart-inngest-workflow-guard.test.sh` | **(D-5)** Back-port the iterate-all-jobs fix — two lines, same hole, fleet-wide. |
| ~~`apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`~~ | **DROPPED by revision B1** — crane is cut in favour of `curl` + `jq`, so no new `CRANE_SHA256` pin site is created and the parity test needs no edit. |

### Files to Create — additions from deepen

| Path | Purpose |
|---|---|
| `scripts/zot-inventory-assert-marker.sh` | **(E4)** The round-trip gate, extracted out of workflow YAML so it is testable. Decodes the double-encoded `raw`, matches `run_id` **and** `enumeration_complete=true`, `--no-archive --since 15m`, four-outcome vocabulary with the free `SOLEUR_ZOT_DISK` positive control. |
| `tests/scripts/test-zot-inventory-assert-marker.sh` | Four cases; primary = **a different `run_id` must NOT pass**; plus an undecoded-fixture case that must FAIL. |
| `.github/workflows/registry-zot-inventory-dispatch.yml` | **(G3)** Label-triggered dispatcher mirroring `inngest-watchdog-restart-dispatch.yml` — guards on the controlled label **and** `issue.user.type == 'Bot'`. Without it nothing ever fires the lever and the follow-through can never legitimately pass. |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A partial sweep produces a delta that looks like the finding.** This is the highest-consequence failure and it is the *expected* condition, because zot is restarting ~4.8/min right now. | `enumeration_complete` is emitted, the primary AC is conditioned on it, and 1.1.3 tests the arm. `outcome=partial` still emits so the partial counts are recoverable. |
| **Naive summation inflates the referenced total**, hiding a real delta. | Dedup by digest, tested by 1.1.1 against a shared-base-layer fixture that a naive implementation fails. |
| **Editing the composite breaks the release pipeline.** | Default `'false'`; the login is the composite's last step so the bridge is unaffected; AC5 asserts the default and that no existing caller passes the input. |
| **The runner cannot reach Better Stack ingest** (H6, unmeasured). | The round-trip gate fails loud with a distinct reason; the fallback is the already-proven CI→Sentry egress; the follow-through automates closure. No endpoint is invented. |
| **Reading the lever's failure as a diagnosis** (`bad handshake` as a cause). | Branch on `zot-mirror-diagnosis.sh`'s measured verdict (ADR-166); `lint-diagnosis-claims.sh` blocks any message naming an unmeasured cause. |
| **The crane pin drifts across its now-five sites.** | Reuse the existing spine verbatim; 0.4 checks whether the parity test needs extending. |
| **~300–500 requests hit a registry that is already failing releases.** | GET/HEAD only; bounded per-request retry; dispatch-only (never scheduled); `concurrency` group prevents overlap; comparable load to one release's mirror step. |
| **The `SOLEUR_ZOT_DISK` sample is stale, staling `delta_gb`.** | `disk_sample_age_s` is carried in the marker; a stale sample sets `outcome=partial reason=disk_sample_stale`. The delta is never presented without its sample age. |

---

## Sharp Edges

- **A partial enumeration is indistinguishable from a finding.** Under-counting
  manifest-referenced bytes produces a *large* delta — which is exactly the shape that would
  "prove" the interesting hypothesis. `enumeration_complete` is not decoration; it is the gate
  that stops this plan from manufacturing its own conclusion.
- **A plan whose `## User-Brand Impact` section is empty, contains `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** It is filled above.
- **`workflow_dispatch` cannot be fired from a feature branch.** GitHub requires the file on
  the default branch (`HTTP 404: workflow not found on the default branch`). Do not plan a
  pre-merge dispatch verification, and do not add a throwaway `workflow_dispatch` workflow
  intending to delete it — step two is impossible.
- **pyyaml keys `on:` as boolean `True`.** A guard test that probes only the string `"on"`
  reads the workflow as having no triggers and **passes vacuously** over a broken guard.
- **`secrets.DOPPLER_TOKEN` and `secrets.DOPPLER_TOKEN_PRD` are not interchangeable.** The
  former is `prd_terraform`-scoped and cannot read `REGISTRY_PUSH_ACCESS_TOKEN_*` or `ZOT_*`;
  branch configs do not inherit from the `prd` root. Using the wrong one ships a
  credential-less workflow that fails at the edge and looks like a token-drift incident.
- **`bad handshake` is a symptom with at least three causes** (ingress misconfiguration, edge
  refusal, origin restarting) and the third one is live right now. Never name a cause the run
  did not measure — `lint-diagnosis-claims.sh` is BLOCKING on exactly this.
- **The recut runbook's blocked-state banner is load-bearing.** It is the first thing a reader
  sees and it is what stops a fatal destroy. Add the lever pointer *around* it; do not reflow,
  reword, or relocate it.
- **`hcloud_server.registry` already has a pending REPLACE in state.** An untargeted
  `terraform plan` showing a registry replace is a STOP, not a proceed — and this plan touches
  no `.tf` precisely so it contributes nothing to that graph.
