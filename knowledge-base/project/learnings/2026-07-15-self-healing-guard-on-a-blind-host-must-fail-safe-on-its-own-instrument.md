---
date: 2026-07-15
category: infra
module: apps/web-platform/infra
issue: 6415
related: [6400, 6122, 6288, 6405, 6303, 6421]
related_adrs: [ADR-115, ADR-096, ADR-103]
tags: [observability, cloud-init, cron, self-healing, fail-safe, terraform, review]
---

# Learning: a self-healing guard on a blind host must fail safe on its OWN instrument

## Problem

The 2026-07-14 zot outage (#6400): the registry host booted holding only its public `eth0`, never
configured `10.0.1.30`, and the fleet's primary image-pull path was dead for **~14 days while every
health signal stayed green**. A NIC-less host keeps public egress (so the disk heartbeat kept
pinging), the boot readiness poll targets `localhost:5000` (so it passed), and the ADR-096 GHCR
fallback meant **deploys kept succeeding** — the deploy pipeline was an actively misleading proxy.

We shipped an on-host guard that converges the NIC and self-reports. **Multi-agent review found the
guard, as first written, would have been WORSE than no guard** — five merge-blocking P1s.

## Key Insight

> **A guard that acts on a fact it did not successfully read is worse than no guard.**

Every P1 was the same shape: the guard treated *"I could not measure"* as *"the measurement is
false."* On a deny-all no-SSH box with a reboot primitive, that inversion is an outage.

The sharpest instance: **`ip` and `reboot` live in `/usr/sbin`; cron's default PATH is
`/usr/bin:/bin`.** Under cron the probe resolved *nothing* — but `curl` lives in `/usr/bin`, so it
*did* resolve, IMDS *did* corroborate ("a network genuinely is attached"), and the reboot gate opened
**on a perfectly healthy host**. Budget burned, then the terminal alarm fired forever, telling the
operator to destroy a healthy production registry.

Three properties made it invisible:

1. **The boot invocation runs under cloud-init's richer PATH**, so the post-merge verification (AC15)
   would have passed **green** — and the box would page 10 minutes later, from cron.
2. **The test could not catch it**: the harness did `PATH="$BIN:$PATH"`, and the harness PATH already
   contains `/usr/sbin`. A stub prepended to a working PATH cannot model a *missing* binary.
3. **The sibling cron was no precedent**: `zot-disk-heartbeat.sh` uses no `/usr/sbin` binary, so "the
   existing cron shape is proven in prod" transferred *nothing*. This guard was the host's **first**
   cron consumer of one.

**Generalizable:** when adding the first consumer of a *new dependency class* to an existing pattern,
"the pattern is proven" is not evidence. Ask what the precedent never exercised.

## Solution

- **Declare `PATH` in the cron.d block**, and *additionally* resolve the probe explicitly
  (`IP_BIN=$(command -v ip)`) — an unresolvable probe emits `converged_by=probe-fault` and **cannot
  reach the reboot arm**. Zero evidence ≠ evidence of absence.
- **Corroborate on the expected ADDRESS, not a bare network count.** IMDS already returns the
  address; using the weaker "≥1 network attached" predicate is what made a drifted constant
  dangerous. Keying on the address makes drift *structurally unable* to trigger a reboot, instead of
  a convention two future edits can break. *(The `-?` in `^[[:space:]]*-?[[:space:]]*ip:` is
  load-bearing — IMDS returns a YAML **list**, so the address line is `- ip: <addr>`. My first regex
  missed it and the gate never opened; my own fixture caught it.)*
- **Verify the reboot budget is DURABLE before granting reboot authority.** An unchecked write on a
  read-only root fs (ext4 `errors=remount-ro`) never persists → the cap never binds → **unbounded
  power-cycle**. Atomic `.tmp` + `rename(2)` + read-back + dirent fsync; on failure emit
  `converged_by=counter-unwritable` and refuse.
- **Read verdict fields from the NEWEST row, not any-row.** An any-row `grep -q nic_ok=false` pages
  terminal on the guard's *most likely success path*: the boot emit says `false` at ~100s (uptime
  gate shut), the 5-min cron says `true`, **same `boot_id`**.
- **Every emitted field needs a reader.** `zot_store_mounted` shipped with none — the exact sin the
  plan criticised v1 for. An unmounted store 404s the whole fleet while `nic_ok=true` reads GREEN.
- **Absence needs a sibling cross-check.** "No rows ever" read TRANSIENT forever → no issue, and
  Sentry green (it keys only on the *zot* exit code). If the sibling producer on the same host, over
  the same token path, IS emitting, then silence is **proof the guard is broken** — not a fresh host.
  And "never emitted" is the *rollout* path: the replace births a fresh host.
- **A successful self-heal needs its own branch.** It emits `nic_ok=true`, so the terminal branch
  structurally cannot see it — without an advisory, the race self-heals silently forever (a *lost
  ceiling*: today it at least eventually surfaces as an outage). Keyed on `reboot_count>0`, not
  `converged_by=reboot`, which lives on the **previous** boot_id.
- **The advisory must be create-only.** `reboot_count` persists on the root disk, so a healed host
  emits it forever → ~48 comments/day → the operator mutes the label that *also* carries the terminal
  FIRE. The open issue **is** the standing signal.

## Prevention

- **Shared-log-source markers need an anchored membership check.** `betterstack-query.sh --grep` is an
  unanchored `raw LIKE '%MARKER%'` over a source **every host multiplexes into**, and
  `SOLEUR_ZOT_DISK`'s `zot_last_err` carries `docker logs` output — so a pull of
  `/v2/SOLEUR_PRIVATE_NIC/manifests/x` injects your marker into another stream's row, which survives
  the trusted-region strip, carries no fields, and falls through to a **fabricated GREEN that
  auto-closes a live issue**. Anchor on the marker starting the `raw` field.
- **Negative-space suites need a positive control.** ~40 of the guard's assertions are "NO reboot" /
  "NO mount". They are only non-vacuous because every negative sits beside a positive emit assert
  from the same run, and T4 proves the reboot arm fires. Pair every negative with a positive from the
  same fixture.
- **Mutation-test every safety gate.** 13 mutations, each verified RED. Three assertions were provably
  **weaker than their English descriptions** and would have shipped as decoration:
  `[a-z_]+` missed digit-bearing TF vars; `zot_last_err=[^"]*$` could **never fail** (`[^"]*` eats any
  appended field); `grep -qwF?` made `-F` optional. **Litmus: for every `grep -qE` assert, write the
  mutant it should catch and confirm it does.**
- **Stubbing `sleep` turns a lost wait-bound into an infinite spin**, not a slow test — bound the run
  with `timeout` (resolved ABSOLUTE; `PATH=x timeout …` looks `timeout` up through the stripped PATH).
- **The `set -u` expansion-order variant (#6497).** Same class, one layer earlier: this guard *acted
  on a fact it did not read*; #6497's htpasswd probe **never reached the read**. A bare
  `"$ZOT_PULL_TOKEN"` inside `zot-disk-heartbeat.sh`'s `set -u` raises `unbound variable` and exits
  **before `$LINE` is built** — taking the whole `SOLEUR_ZOT_DISK` heartbeat dark and bypassing the
  trailing `exit 0` that exists so the cron can never wedge. Since this heartbeat's **absence** is
  itself an alarm, the probe would page *"host down"* when only the probe broke. Two traps worth
  carrying: **`|| VAR=false` does not rescue it** (an expansion error is not a command failure, so
  the `||` never runs — a reviewer scanning for a fallback finds one), and the `unknown` guards
  written for exactly that case sat **8 lines too late**, i.e. dead code that reads as coverage.
  **Rule: under `set -u`, default at the expansion site (`"$${VAR:-}"`) — a guard against a failure
  mode must be a PRECONDITION, never a post-hoc correction.** The mirror of this file's
  "short-circuit guard must sit after the recovery it gates".
  → [2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md](./2026-07-15-false-comment-shipped-the-bug-then-plan-guard-adr-and-tests-each-restated-it.md) §1

## Session Errors

1. **Plan asserted a repo capability that does not exist** (forwarded) — v1 claimed
   `apply-web-platform-infra.yml` "already names the web-host-driven private-net probe"; the file says
   the cron is *"unbuilt"*, and `ZOT_HEARTBEAT_URL` has zero consumers. That fabrication was the sole
   basis for elevating L3 to required-for-close. **Recovery:** `spec-flow-analyzer` caught it; verified
   against the file; L3 deferred. **Prevention:** already `hr-verify-repo-capability-claim-before-assert`
   — the recurring gap is that plan-review agents *concur with* a fabricated citation unless one agent
   opens the file. Two of four "keep" verdicts rested on it.
2. **The IaC-routing hook blocked the plan write twice** (forwarded) — the `iac-routing-ack` comment
   itself contained the trigger token. **Recovery:** removed the literal, kept the ack.
   **Prevention:** when acking a token-triggered gate, describe the verb; never quote it.
3. **Two bad tool calls** (forwarded) — a wait-condition that proved nothing; a glob spanning every
   plan file. **Recovery:** none needed. **Prevention:** one-off.
4. **ADR-113 ordinal collided mid-flight.** A sibling claimed 113 on `main` after this branch's base
   (#6303); #6421 already held 114 → renumbered to **115** + swept 10 files. The plan also claimed
   `adr-ordinals` "is not a required check" — **false**, it is required
   (`scripts/required-checks.txt:76`). **Recovery:** re-derived the free ordinal across `origin/main`
   AND every remote branch (not just main), swept only our files, left the sibling's references
   intact. **Prevention:** `git log --all --grep='renumber ADR'` returns **18** commits — the check
   catches it at CI, *after* the write+sweep cost. Already tracked by #5744 / #5951; no new issue.
   Concrete tip captured here: re-derive against **in-flight branches**, not just `origin/main` —
   `origin/main` said 113 was free while two branches already held 113 and 114.
5. **`git checkout -- <file>` wiped every uncommitted review fix in that file.** Used as a
   mutation-restore on a file that also carried in-flight edits. **Recovery:** rebuilt the whole suite
   from scratch and committed immediately. **Prevention:** the sharp edge is already documented in
   `review/SKILL.md` — *check `git status --short <file>` first; undo via a targeted inverse edit* — and
   I violated it while running that very skill. Prose is losing here; the durable fix is a PreToolUse
   hook denying `git checkout -- <path>` / `git restore <path>` when `git status --porcelain <path>` is
   non-empty. **Cheap habit until then: `cp <file> /tmp/<file>.bak` before any mutation loop.**
6. **Pipe-masking false-green, twice.** `actionlint … | head -20; echo "exit=$?"` reports `head`'s 0.
   I reported "exit 0" for actionlint and shellcheck when **both exit 1**. **Recovery:** re-ran with
   `cmd > log 2>&1; rc=$?` and compared against the `origin/main` baseline (both pre-existing, neither
   CI-gated). **Prevention:** AGENTS.md already carries this rule and I broke it twice in one session
   — the tell is *any* `| head`/`| tail` in the same command as an exit-code read. Never read `$?`
   after a pipe.
7. **My IMDS corroboration regex missed YAML's list form.** `^[[:space:]]*ip:` does not match
   `- ip: 10.0.1.30`, so the reboot gate never opened. **Recovery:** my own T4 fixture failed and
   pinpointed it. **Prevention:** one-off — and the system working: a realistic fixture caught a real
   bug in a fix written the same hour.
8. **A mutation test used `perl s///` without `/g`.** It mutated the FIRST occurrence (the disk
   heartbeat's `post()`), not the guard's, so I falsely reported the render assert "VACUOUS" and spent
   a cycle debugging a working assert. **Recovery:** re-ran with `/g`. **Prevention:** when a file has
   sibling occurrences of a pattern, a mutation must target the one under test — verify the mutation
   landed where you think (`grep -c` the mutant) before trusting a vacuity verdict.
9. **`PATH="$run_path" timeout 10 bash …` resolved `timeout` through the stripped PATH**, so the
   missing-`ip` fixture silently never ran the guard. **Recovery:** resolved `TIMEOUT_BIN` absolutely
   before any fixture strips PATH. **Prevention:** `VAR=x cmd` looks `cmd` up using the NEW PATH —
   pin helper binaries absolutely whenever a fixture manipulates PATH.
10. **The plan shipped two false ACs and one wrong ordering.** AC6 ("`10.0.1.30` appears exactly once
    across `infra/*.tf`") was **unpassable** — the literal also lives in comments and in a live
    `docker info | grep` probe; it was the plan's own grep-matches-its-own-comments trap. AC1 measured
    the raw template with `gzip -9` as a proxy for rendered `user_data` at `base64gzip`'s ~`-6`. And
    the step ordering put the store-heal *after* the healthy-path early exit, which would have left R4
    (the bug it exists for) uncovered — R4 fires precisely when `nic_ok=true`. **Recovery:** corrected
    all three at /work with the reasoning recorded in the plan. **Prevention:** already covered by
    "plan-quoted numbers are preconditions to verify" — extend the instinct to ACs: an AC is a claim
    about a gate, and a gate that cannot fail (or cannot pass) is not a gate.

## Related

- ADR-115 — the decision + the normative LUKS blocker that keeps this registry-only.
- `2026-07-07-immutable-redeploy.md` Sharp edge 2 — the same race on the same host (#6122). Its manual
  *"always verify private-net reachability after a `-replace`"* was an **operator-memory dependency**,
  and #6400 is what that dependency failing looks like. Now automated for the registry.
- #6438 — deferred follow-ups (off-host probe, git-data/inngest, web hosts).
- #6448 — discovered pre-existing: `docker-daemon.json` hardcodes `10.0.1.30:5000`; `server.tf`'s probe
  greps the file it just delivered (self-referential), so drift fails **silent**.
