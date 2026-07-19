---
title: A correction to a false comment is itself a claim — and it carried a NEW false claim twice in one PR
date: 2026-07-19
category: best-practices
module: apps/web-platform/infra/{cloud-init-inngest.yml,cloud-init.yml,vector.toml,inngest-redis.service,variables.tf}
issue: 6617
pr: 6702
problem_type: best_practice
component: documentation
symptoms:
  - "a comment asserts a cosign-verify that no line of the file performs; the claim had already propagated into the plan and into an acceptance criterion"
  - "the CORRECTION to that comment claimed a digest pin 'authenticates' the pull, and named a second file as having real verification when it has zero cosign invocations"
  - "adding SyslogIdentifier= plus a Vector allowlist entry newly routed a unit whose argv carries the live prd Redis password to a third-party log sink"
  - "a Phase 0 read-only probe returned STOP: the boot gate is exact-set-equality sitting at 5/5, so the first new secret name FATALs the sole scheduler's boot"
  - "Closes #6500 survived the descope in 4 places; a squash-merge would auto-close an unfixed P1 that gates an irreversible PAT revoke"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: critical
tags: [comment-rot, false-claims, mechanical-gate, cosign, digest-pin, provenance-vs-integrity, vector, journald, pii-scrubbing, user-data-budget, measurement-gate, auto-close, acceptance-criteria]
synced_to: [security-sentinel, observability-coverage-reviewer]
---

# Learning: the cosign correction that wrote two new false claims (#6617 / PR #6702)

> **Disposition note, up front.** This repo *already* documents this class:
> [2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes.md](./2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes.md).
> That learning's own rule is that **"the disposition for a recurring documented class is a
> mechanical gate, not another learning."** This file exists to record the *recurrence* and the
> *shape of the gate it argues for* — not to add more prose about being careful. See
> [§A.4](#a4-the-disposition-a-mechanical-gate-not-a-third-learning).

---

## A (PRIMARY) — a correction is a claim, and inherits every failure mode of the thing it corrects

`cloud-init-inngest.yml:236` asserted that the cold-boot OCI pull was **cosign-verified**. No line
of that file performs a cosign verification; `grep -n cosign` returned exactly one hit — the
sentence itself. Worse, the false claim had already **propagated**: the plan for this very change
inherited it instead of grepping the path, and restated it as an **acceptance criterion**. An AC
derived from a false premise certifies a control that does not exist.

While correcting it, I wrote **two new false claims**, each caught by a *different* reviewer.

### A.1 — "the digest pin **authenticates** the pull" (INTEGRITY ≠ PROVENANCE)

A content-addressed digest gives **integrity**: the bytes hash to what was recorded, so a swapped
or spoofed payload fails the pull regardless of transport or which registry served it. It gives
**no provenance**: it proves you got the bytes *someone* recorded, never *who built them*. Only a
signature does that — and this image is unsigned **by design**. `build-inngest-bootstrap-image.yml`
says so plainly:

> NOT cosign-signed (no id-token perm) — no sign step

So there is no signature for a verify to check, and adding a verify step would gate the sole
scheduler's boot on an artifact that has never been produced. Provenance on this path still rests
entirely on GHCR's TLS + authn. The corrected comment now states integrity-vs-provenance
explicitly, because overstating the pin repeats the original error one layer down.

### A.2 — "real verification exists only in ci-deploy.sh **and cloud-init-registry.yml**"

`cloud-init-registry.yml` has **zero** cosign invocations. All **6** occurrences are comments, and
they are about something else entirely — zot's `sha256-*` tag **retention** policy
(`mostRecentlyPushedCount`, `deleteUntagged`, `deleteReferrers=false`), i.e. the tags a verify
*elsewhere* depends on being retained. Verified:

```console
$ grep -c cosign apps/web-platform/infra/cloud-init-registry.yml
6
$ grep -nE '^[[:space:]]*cosign ' apps/web-platform/infra/cloud-init-registry.yml
(no output)
```

"Retains the artifacts a verify depends on" had collapsed into "performs the verify" — a one-word
slip in a security claim. The corrected text names the retention role precisely.

### A.3 — why the guard shipped alongside could not catch it

`inngest-host.test.sh` item 11 is the guard added in this same PR:

```sh
if grep -qE 'cosign[- ]verif' "$CLOUD_INIT" && ! grep -qE '^[[:space:]]*cosign verify[[:space:]]' "$CLOUD_INIT"; then
```

It is scoped to `$CLOUD_INIT` — a **single file** (`cloud-init-inngest.yml`, set at `:20`). A false
claim *about a third file* is **structurally outside what that assertion can see**. The guard is
correct and worth keeping; it simply cannot cover the failure that actually occurred. This is the
generalizable point: **a single-file assertion cannot police a cross-file citation**, and a
verification claim is almost always a cross-file citation.

### A.4 — the disposition: a mechanical gate, not a third learning

Two PRs, four days apart, same class. Per the 2026-07-15 learning's own disposition rule, prose is
no longer the right response.

> **Gate shape.** For every **file name cited inside a verification/security claim**, grep that file
> for the **mechanism the claim attributes to it**. If the file is named as performing X, `X` must
> appear in it as an *invocation*, not only as prose.
>
> Concretely, for a comment/doc line matching `/verif|cosign|signed|authenticat|attest/i` that also
> contains a path-like token (`\S+\.(ya?ml|sh|tf|ts)`), assert that the cited file contains a
> non-comment occurrence of the mechanism. Both of this PR's false claims trip that rule:
> A.1 attributes *authentication* to a digest pin (no signature verification exists anywhere on the
> path), A.2 attributes *verification* to a file with 6 comment-only hits and 0 invocations.
>
> Deliberately **not** a single-file guard — the scoping bug in A.3 is exactly what makes item 11
> blind. The gate must resolve the cited path and read *that* file.

---

## B — a `SyslogIdentifier=` + Vector-allowlist pair is a SINK-CONNECTION act, not a tagging act

Before this PR, `inngest-redis.service` set **no** `SyslogIdentifier`, so journald derived the tag
from the `ExecStart` basename → **`doppler`**, which matches **zero** `vector.toml` sources. That
unit's stderr never left the host. Vector's Source 4 matches `SYSLOG_IDENTIFIER` by **exact value**,
never by prefix — so the tag and the allowlist entry are **only meaningful as a pair**, and adding
the pair **newly routes that stderr to Better Stack**, a third party.

What was on the wire on the other side of that switch:

- `inngest-redis.service:31` —
  `ExecStart=/usr/bin/doppler run --config prd -- /usr/bin/bash -c '/usr/bin/redis-server … --requirepass "$INNGEST_REDIS_PASSWORD"'`
  The literal (not the value) is what appears in `ps`, but **redis-server echoes an offending
  directive VERBATIM on any config parse failure** — `>>> 'requirepass "<value>"'`.
- `pii_scrub_string` on `origin/main` redacted exactly **5** shapes: `userid=`/`user_id=`, OAuth
  params (`code|state|access_token|id_token|refresh_token`), email, `Bearer`, `Basic`. Plus a
  control-char strip. **No `requirepass` rule. No DSN rule.**

So a malformed `redis.conf` after a host replace would have shipped **the live prd Redis password**
off-box every 5s under `Restart=on-failure`. Fixed in `871fe6a94` by adding two rules
(`vector.toml:391`, `:398`) before the pair went live.

> **Rule.** When a diff makes a **previously-dark** unit's output shippable, audit **every emitter on
> that unit** for credential *shape* — not just the code you added. Include the process's own error
> paths, which are the ones that echo config verbatim.
>
> Match on the credential **shape** `user:pass@host`, **not** a bare `://` — scripts legitimately
> print credential-less internal URLs, and a bare-scheme rule would redact those into noise while
> still missing the embedded-password case.

This is the **sink-side sibling** of `hr-write-boundary-sentinel-sweep-all-write-sites`: that rule
sweeps every *write* site; this one sweeps every *emitter* whose output a diff newly connects to a
sink.

---

## C — a measurement gate that returns STOP is a **successful** gate

Plan Phase 0 was six read-only probes. Two of them killed the headline arm:

**Probe 0.5** measured the boot-credential isolation gate at `cloud-init-inngest.yml:320-323`:

```sh
n_total="$(printf '%s\n' "$names" | grep -c . || true)"
n_inngest="$(printf '%s\n' "$names" | grep -Ec '^(INNGEST_(SIGNING_KEY|EVENT_KEY|REDIS_PASSWORD|POSTGRES_URI|HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)$' || true)"
if [ "$n_total" -ne "$n_inngest" ] || [ "$n_inngest" -lt 5 ]; then
  echo "[inngest] FATAL: boot credential not isolated …"; exit 1
```

This is **exact set equality**, and it measured live at **5/5** — exactly at its floor. Adding the
first `ZOT_*` secret name makes `n_total=6 ≠ n_inngest=5`, **FATALs the boot**, and the singleton
scheduler never starts. The zot arm was not "a one-line pin swap"; it had a **boot-brick
precondition**.

**Probe 0.3** found **zero** zot access-log rows from `10.0.1.40` in 72h — the inngest host had
never been enrolled as a zot client in any plane.

The gate withdrew the zot arm and reframed #6500 from *"a one-line pin swap"* into *"an enrollment
task with a boot-brick precondition."* PR-A became PR-A′.

> **Rule.** A Phase-0 probe that returns STOP has **done its job**. The finding — *the arm cannot
> land without an enrollment half* — is worth more than a merged, unreachable arm would have been.
> Do not treat a gate's STOP as a phase failure to be worked around.

---

## D — the gate decision must propagate into the ACs **and into COMMIT BODIES**

After the STOP/SPLIT, `Closes #6500` still sat in **4** places: `tasks.md:30`, `tasks.md:100`,
plan `:431`, and plan **AC16**. A PR body written to satisfy its own AC would have **auto-closed an
unfixed P1 on merge** — and #6500 is the gate that authorizes the irreversible **ADR-096 §5.3 PAT
revoke**. That is one careless `stateReason=COMPLETED` away from an unrecoverable action.

The non-obvious half: **a squash-merge concatenates the branch's commit bodies into the merge
commit message**, so GitHub's auto-close keywords fire from commit bodies too. The check must cover:

```bash
git log origin/main..HEAD --format=%B | grep -n 'Closes #6500'
```

not just the PR body. A fix agent's own commit message tripped exactly this and forced a local
history rewrite. All sites now read `Ref #6500` (`tasks.md:102` states the rule inline: *"`Ref`,
never `Closes`, because the Phase 0 gate withdrew the zot arm"*).

> **Rule.** A descope is not applied until the auto-close keywords are swept from **plan, tasks, ACs,
> PR body, and `git log origin/main..HEAD --format=%B`**. Grep all five.

---

## E — `cloud-init.yml`'s base64gzip user_data has ~78 B of headroom, and a digest pin needs ~84

`server.tf` wraps the web render in `base64gzip()`; Hetzner stores the result as `user_data` under a
hard 32,768 B cap with a sub-cap ratchet (`WEB_GZIP_BUDGET = 22_450` in
`plugins/soleur/test/cloud-init-user-data-size.test.ts`). The security review asked for a digest pin
on `cloud-init.yml`'s inngest arm; the budget refused it.

**Re-measured 2026-07-19 at branch HEAD** using the test's own model (gzip -9 + base64 of the
rendered template; the test file states it is **NOT byte-exact** vs terraform's Go zlib — #5887's
`terraform plan` is the byte-exact truth):

| tree | modeled size | vs 22,450 budget |
|---|---:|---|
| `origin/main`, as-is | 22,372 B | **78 B under** |
| main + 2 `@sha256` pins, no added comment | **22,456 B** | **6 B OVER — fails** |
| main + 2 pins using a *low-entropy placeholder* digest | 22,404 B | 46 B under — **passes** |

Three things follow, and the third is the one that matters:

1. **The revert (`761243954`) was correct.** The pin genuinely does not fit.
2. **Its numbers were not.** That commit recorded baseline `22,439` (≈11 B headroom) and the pinned
   tree at `22,464` (14 B over). Actual: `22,372` (78 B) and `22,456` (6 B over) — the baseline is
   off by 67 B and no longer reproduces. **The `variables.tf` SOLEUR-DEBT comment shipped that wrong
   baseline into this PR** and has been corrected to cite the re-measurement. *A learning about
   miscounted claims, which found a miscounted claim in its own PR while being written.*
3. **Entropy is the dominant term, and it will fool a budget experiment.** The same two pins measure
   **22,404 B (passes)** with a patterned placeholder digest and **22,456 B (fails)** with a real
   random one — a **52 B swing from digest randomness alone**. A sha256 is 64 chars of
   incompressible hex; gzip cannot recover it.

> **Rule.** Any `cloud-init.yml` size experiment MUST use a **real-entropy** sha256, or it will
> falsely conclude the pin fits. And cite the budget as a **re-measurement at your own HEAD**, never
> as an absolute inherited from an older commit — the render's inputs drift, so an absolute goes
> stale silently while reading as precise.

The residual risk is recorded as a `SOLEUR-DEBT` block on `variables.tf`'s `web_colocate_inngest`,
whose trigger is *flipping the flag to true*: the unpinned arm is **dormant** (default `false`
post-ADR-100), so it is a non-exposure today, and spending scarce hard-capped bytes to pin dead code
is the wrong side of the trade — **but only while it stays dead**.

---

## Two agent REFUTATIONS worth preserving (both reviewers were right to push back)

**1. `/health` is not unverified.** I claimed the probe's route appeared nowhere else. It does:
`ci-deploy.sh:1843/1955/2679` gate on `curl -sf .../health` — and `-f` fails on a 404, so a wrong
route would have **wedged deploys**, not merely gone quiet. `inngest-inventory.sh:127` and
`inngest-wiped-volume-verify.sh:48` also default to it. Switching to `/` would have desynced this
probe from #6407's watchdog. The real gap was narrower than I stated: nothing **pinned** the route.
Fixed by pinning it to the fleet contract (`3b790a2d0`).

> **Rule.** A *"this appears nowhere else"* claim is a **grep result**, and a narrow grep is not an
> absence proof. State the grep you ran, or state the gap you can actually prove.

**2. `Persistent=true` was correctly declined.** The A4 probe is a **monotonic** timer
(`OnBootSec=90s` / `OnUnitActiveSec=1h`, `inngest-bootstrap.sh:548`), and systemd honours
`Persistent=` **only for `OnCalendar=` timers**. Asserting it would have forced a directive systemd
ignores into the unit — a green AC certifying nothing. Reboot survival for a monotonic timer is
`OnBootSec=`, which is already there; `inngest.test.sh:547-554` now records the reasoning next to
the assertion.

---

## Session Errors

1. **The NIC-wait as briefed would have bricked a fresh web-1.** `cloud-init.yml`'s `runcmd` is ONE
   `/bin/sh`, so a fail-closed `|| exit 1` before `cloudflared service install` terminates the
   *entire* remaining runcmd — cloudflared, the webhook, the readiness gate, every monitor, the
   egress firewall — **permanently**, since `runcmd` is once-per-instance. It would have replaced a
   partial, in-band-fixable degradation with total loss of `deploy.` and `ssh.` on the sole web host.
   **Recovery:** redesigned to **defer, not abort** (a systemd precondition); added a regression AC
   forbidding `exit 1` in `runcmd`. Caught at deepen (CF-5/UC-4).
   **Prevention:** before prescribing a fail-closed guard, identify the **blast radius of the
   abort** — in a single-shell, once-per-instance context, `|| exit 1` is not a guard, it is a
   detonator.

2. **"Mirror the web ZIREF pattern" was an unsafe premise.** That block is gated by
   `web_colocate_inngest`, `default = false` — the reference implementation has **never executed**,
   and its only cosign mention is a comment.
   **Prevention:** before adopting a pattern as battle-tested, check whether its gate has ever been
   true in production. "Exists in the repo" is not "has run."

3. **The NIC gate was attributed to #6466; ADR-114 §I1 tracks it under #6441.** Closing #6466 would
   have closed an issue whose actual scope (host-addressability) is untouched.
   **Prevention:** read the issue **body**, not its title, before attributing work — and follow the
   ADR's own "tracked in #N" pointer.

4. **The brief specified 4 Vector tags; 3 of 4 could never match.** Source 4 is exact-value
   `SYSLOG_IDENTIFIER` equality: `inngest-redis.service` was tagged `doppler`, the nftables unit
   `inngest-nftables.sh` (with extension), and `inngest-boot-phone-home` has **no journald channel
   at all** (pure `curl` to the Better Stack HTTP ingest).
   **Prevention:** for an allowlist keyed on exact equality, verify **both sides of the pair** — the
   emitted value and the allowlist entry. A one-sided change yields a green AC certifying a fix that
   does not exist.

5. **An SC2034 "vacuous test" hypothesis was WRONG.** All 8 vars are consumed inside `assert`'s
   `eval`, in escaped `\"\$VAR\"` form — invisible to shellcheck. Refuted by a sandbox
   section-rename that flipped 4 legs to FAIL.
   **Prevention:** shellcheck cannot see through `eval`; **verify by mutation** before treating
   SC2034 as a dead-assertion signal.

6. **The CF-2 correction claimed the digest pin "authenticates" the pull.** (§A.1)
   **Recovery:** comment rewritten to state integrity-vs-provenance explicitly.
   **Prevention:** §A.4's gate — a claim of *authentication* requires a **signature**, and the
   signature must exist.

7. **That same correction claimed `cloud-init-registry.yml` has real verification.** It has 6
   comment-only cosign hits and **0** invocations. (§A.2)
   **Recovery:** `918fc19d0`.
   **Prevention:** §A.4's gate — grep every **cited file** for the **mechanism attributed to it**.

8. **The web-path digest pin blew the user_data budget**; required a measured revert. (§E)
   **Prevention:** grep for a size budget over any file rendered into a capped payload *before*
   editing it, and measure with real entropy.

9. **The `SyslogIdentifier` + allowlist pair newly routed the prd Redis password off-box.** (§B)
   **Recovery:** `871fe6a94` added `requirepass` + DSN scrub rules before the pair went live.
   **Prevention:** audit every emitter on a unit whose output a diff newly connects to a sink.

10. **Gate 4.55 halted deepen-plan** (missing `## Downtime & Cutover`).
    **Recovery:** section added — which surfaced that web-2 was retired 2026-07-17, leaving web-1
    with no blue-green partner (#6459).
    **Prevention:** the halt was correct and productive; run the gate predicates before invoking
    deepen, not after.

11. **Two false-positive hook blocks** (`hr-all-infrastructure-provisioning-servers`) on *descriptive*
    prose — an AC asserting a write count is zero, and a quoted `systemctl` token.
    **Recovery:** `iac-routing-ack` + rephrasing.
    **Prevention:** the hook matches quoted/negative prose, not only prescriptions; expect it when
    writing ACs *about* infra commands and reach for the ack rather than re-litigating.

12. **`Closes #6500` survived the descope in 4 places.** (§D)
    **Prevention:** sweep plan, tasks, ACs, PR body, **and commit bodies**.

13. **The plan declared a 60s probe cadence; the timer ships hourly** (`OnBootSec=90s` /
    `OnUnitActiveSec=1h`). AC27's `--since 1h >= 1 row` was therefore a **coin flip on a HEALTHY
    host**, while the plan's own text calls zero rows a positive down-signal — the AC and the prose
    disagreed about what zero means.
    **Recovery:** `2e3803e30` matched the Observability block to the timer that actually ships.
    **Prevention:** derive an AC's window from the **shipped timer literal**, not from the plan's
    prose; and reconcile the AC against the plan's own interpretation of a zero result.

14. **A fix agent's commit message tripped the #6500 auto-close gate** → local history rewrite.
    **Recovery:** rewritten; tree verified byte-identical, nothing pushed.
    **Prevention:** brief fix agents on the `Ref`-not-`Closes` constraint **as a commit-message
    constraint**, not only a PR-body one.

15. **`git stash list` hit the guardrail** (`hr-never-git-stash-in-worktrees`) — even the read-only
    form is denied.
    **Prevention:** the rule is on the `git stash` verb, not on mutation; use `git status` /
    `git diff` to inspect worktree state.

16. **This learning's own PR shipped a wrong measurement.** `variables.tf`'s SOLEUR-DEBT block cited
    `761243954`'s baseline (`~11 B` headroom, pinned tree `14 B` over). Re-measured at HEAD: `78 B`
    headroom, pinned tree `6 B` over — the baseline is off by 67 B and no longer reproduces.
    **Recovery:** corrected inline during compound-capture, with the model named and the entropy
    caveat recorded.
    **Prevention:** a measurement inherited from an older commit is a **stale citation wearing the
    costume of a fact**. Re-measure at your own HEAD before quoting an absolute, or quote the
    verdict and not the number. *(Direct instance of §A: a correction is a claim.)*

---

## Key Insight

The 2026-07-15 learning established that a comment-fix PR is **primed** to write a new false comment.
This PR shows the next layer: **the correction itself is a claim with the same failure modes**, and a
security correction fails in a specific, predictable direction — it **overstates the control it
substitutes**. "Digest pin" became "authenticates"; "retains the artifacts a verify depends on"
became "performs the verify." Both were the *reassuring* reading of the mechanism.

Two occurrences four days apart, plus a third found inside this very file's PR while writing it, is
not a discipline problem. It is a **missing gate**: every file name cited inside a
verification/security claim should be grepped for the mechanism attributed to it. That check is
mechanizable, and prose has now failed at it three times.

---

## Related

- **Recurrence of:**
  [2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes.md](./2026-07-15-comment-fix-pr-wrote-a-new-false-comment-and-vacuous-ac-classes.md)
  — that file's Learning A (count the M / re-derive the prescription) and its disposition rule
  (*"a recurring documented class gets a mechanical gate, not another learning"*), which §A.4 acts on.
- **§E extends** that learning's **I** ("comment-only is not free in a size-capped payload") with the
  **entropy** term and the **stale-absolute** failure: the budget number itself rots.
- **§B is the sink-side sibling** of `hr-write-boundary-sentinel-sweep-all-write-sites`.
- Guards shipped with this PR: `inngest-host.test.sh` item 11 (single-file cosign-claim guard — see
  §A.3 for what it structurally cannot cover), `journald-config.test.sh:323` (`requirepass` scrub
  rule present) and `:354` (leak fixture), `inngest.test.sh:535-554` (timer type + monotonic
  reboot-survival reasoning).
- Open blocking dependencies recorded, not absorbed: **#6497** (zot has served zero pulls in 90
  days), **ADR-096 §5.3** (deletes the GHCR fallback entirely, leaving the singleton one registry and
  no break-glass), **#6459** (web-1 is the sole web host, no blue-green partner since web-2's
  2026-07-17 retirement).
