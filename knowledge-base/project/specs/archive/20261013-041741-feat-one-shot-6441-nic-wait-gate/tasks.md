---
feature: feat-one-shot-6441-nic-wait-gate
plan: knowledge-base/project/plans/2026-07-19-fix-nic-wait-gate-tunnel-connector-plan.md
issue: 6441
lane: cross-domain
brand_survival_threshold: single-user incident
status: pending
---

# Tasks — NIC-wait gate before cloudflared connector registration (#6441)

Derived from the finalized (post-plan-review) plan. Phase order is **load-bearing**:
Phase 0's verifications gate design decisions in Phases 2-3.

> **Three constraints bound every task below. Re-read before writing code.**
> - **C1** `runcmd` is ONE `/bin/sh`; an `exit 1` kills all downstream and never re-runs.
> - **C2** No reboot on the web host (ADR-115 is registry-scoped).
> - **C3** A wait placed after `cloudflared service install` consumes the pre-existing
>   `cloudflared_ready` 60 s fail-closed budget and detonates its `|| exit 1`.

## Phase 0 — Preconditions (all verifications BEFORE any code)

- [ ] 0.1 Re-run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`; record
      the measured bytes. Planning baseline: **22,372 B / 22,450 B budget → 78 B**.
- [ ] 0.2 Confirm bootstrap invocation (`cloud-init.yml:566`) precedes the cloudflared
      block (`:598`). *(Verified at plan time.)*
- [ ] 0.3 Confirm `soleur-boot-emit` accepts `warning`. *(Verified: `<stage> [info|warning|fatal]`.)*
- [ ] 0.4 Confirm `private_ip` is absent from the `templatefile` map **and** present on the
      `web_hosts` object type (`variables.tf:98`). Two distinct checks.
- [x] 0.5 **Per-connection origin-resolution claim — RESOLVED at deepen-plan: CONFIRMED.**
      cloudflared dials origins lazily per request (`proxy/proxy.go` `RoundTrip` /
      `proxyStream`; `ingress/origin_service.go` `start()` opens no connection); Cloudflare
      docs state connections are *"created on demand… new connections are created as
      traffic resumes"*; the 2026.5.2 connectivity pre-checks validate only the **edge**
      path, never origin reachability. Carry the citations into the ADR amendment.
- [ ] 0.6 **Decide the P0 bake/apply coherence mitigation.** Confirmed at plan time that
      `web2-recreate-preflight.sh` has exactly one call site
      (`apply-web-platform-infra.yml:1338`) and does **not** cover the routine apply or a
      fresh `web-1` create. Choose: reuse the preflight, or assert bake-before-apply
      sequencing.
- [ ] 0.7 Confirm the fleet is single-host (`variables.tf:109-111`, only `web-1`).

## Phase 1 — Plumb the expected IP

- [ ] 1.1 Add `private_ip = each.value.private_ip` to the cloud-init `templatefile` vars
      map in `apps/web-platform/infra/server.tf`. Single-sourced from `var.web_hosts`.
      Must enter the map **unconditionally** — `templatefile` pre-checks variables across
      both branches of an `%{ if }` directive.
- [ ] 1.2 Put all rationale prose in `server.tf` (not byte-budgeted), never in
      `cloud-init.yml`.

## Phase 2 — Bake `soleur-wait-nic`

- [ ] 2.1 Add a **new, separate** `soleur-wait-nic` heredoc to
      `apps/web-platform/infra/soleur-host-bootstrap.sh`. **Always exits 0.** Emits
      **exactly one** event from three mutually-exclusive arms:
      `private_nic_ready` (info) / `private_nic_timeout` (warning) /
      `private_nic_probe_fault` (warning).
- [ ] 2.2 **Conform to house precedent** (verified at deepen-plan):
      - Loop: `for i in $(seq 1 30); do sleep 2; …; done` — **30 × 2 s**, the shape used
        6+ times verbatim. Do **not** use the `while :; n=$((n+1))` form — that is the
        *fail-closed* variant used only by `soleur-wait-ready`.
      - Probe: `IP_BIN=$(command -v ip 2>/dev/null || true)` then
        `PROBE_OK=true; [ -n "$IP_BIN" ] && [ -x "$IP_BIN" ] || PROBE_OK=false`. Never
        inline `command -v ip` in the predicate.
      - Match: `"$IP_BIN" -4 -o addr show 2>/dev/null | grep -qwF -- "$EXPECTED"` —
        `-w`/`-F`/`--` are all load-bearing.
      - Probe once **before** the loop, then sleep-first inside it (the NIC-guard form).
- [ ] 2.3 **Probe-fault short-circuits BEFORE the loop** — both precedents skip the wait
      entirely when `PROBE_OK=false`. Never spend 60 s on a missing binary, and never read
      "could not measure" as "the address is absent" (#6415).
- [ ] 2.3b Precede the heredoc with its own `STAGE=…; FAILED_FILE=soleur-wait-nic` pair, so
      a *write* miss emits a named stage under the top-level `emit_fail` trap (the form
      used at `soleur-host-bootstrap.sh:278`, `:349`, `:460`). Note `soleur-wait-ready:307`
      lacks one — that is an existing gap, not a pattern to copy.
- [ ] 2.3c Baked form is a **standalone script**, not a shell function: use `exit 0`, never
      `return 0` (`return` outside a function is an error in dash). All three arms exit 0 —
      that is the property making the bare, no-`||` call site safe.
- [ ] 2.3d Put the fail-open-vs-fail-closed **divergence rationale** in a comment inside
      `soleur-host-bootstrap.sh` (baked, 0 user_data) — `soleur-wait-nic` is fail-open five
      lines from the fail-closed `soleur-wait-ready` that gates the same cloudflared step,
      and that asymmetry will read as a bug without the explanation.
- [ ] 2.4 **Leave `soleur-wait-ready` (`:307-319`) byte-identical.** Do not add a verb, do
      not thread a soft/hard flag, do not touch its header comment.
- [ ] 2.5 Pin the NIC bound **below** `cloudflared_ready`'s 60 s budget.
- [ ] 2.6 Add no `exit 1` to the bootstrap script **body** (heredoc interior is fine).

## Phase 3 — Wire the call site + measure

- [ ] 3.1 Insert `- soleur-wait-nic ${private_ip}` immediately **before**
      `cloudflared service install`, inside the existing `%{ if web_tunnel_connector ~}`
      block. **No `||` clause. No `exit 1`.**
- [ ] 3.2 **Zero new comment lines in `cloud-init.yml`** (a 3-line block costs 40-70 B
      gzipped and would consume the whole headroom). At most one pointer line.
- [ ] 3.3 Re-run the size test; record before/after in the PR body.
- [ ] 3.4 If over budget, re-baseline `WEB_GZIP_BUDGET` with the #6604-style rationale.
      Measure directly — do **not** inherit the review's +2 B figure (it measured a
      different insertion) or reason by analogy from the sha256-entropy experiment.

## Phase 4 — Tests, ADR, C4

- [ ] 4.1 Add a **render step** (e.g. `terraform console` `templatefile(...)` under the
      canonical Doppler `tf-var` invocation) so the `%{ if }` block is actually evaluated.
      Without it, "inside the block" is unassertable.
- [ ] 4.2 Add a **stub-`ip` extraction harness**: extract the `soleur-wait-nic` body and
      execute it against a stub `ip` earlier on `PATH`.
- [ ] 4.3 Behavioural tests for all three arms + the substring guard + exactly-one-event +
      all-arms-exit-0.
- [ ] 4.4 Negative tests: no `||`/`exit 1` at the call site; CF-5 guard across **both**
      files (heredoc-interior vs script-body aware); no reboot primitive in
      `apps/web-platform/infra/`.
- [ ] 4.5 No-diff assertion on `soleur-host-bootstrap.sh:307-319`; confirm the existing
      assertions at `soleur-host-bootstrap-observability.test.sh:145-158` pass unchanged.
- [ ] 4.6 Implement the Phase 0.6 P0 mitigation (coherence preflight or asserted
      sequencing).
- [ ] 4.7 **ADR-114 consolidating amendment.** Reconcile the three I1 status statements;
      record what ships (first-boot gate) and what was rejected (the runtime arm) with
      grounds; correct the stale blast-radius claim (post-#6594 it is total ingress loss).
      **Do NOT edit** the preserved *"Not shipped in #6416"* sentence — amendments append.
- [ ] 4.8 `.c4` edits: `model.c4:178` and `:408` only — add the first-boot gate and
      correct the stale two-connector claim (adjudicated against `variables.tf:109-111`,
      which shows a single-host fleet). **Do not** edit `:406`. No new elements,
      relationships, or `view … include` lines.
- [ ] 4.9 Run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

## Phase 5 — Ship hygiene

- [ ] 5.1 PR body uses **`Ref #6441`** — never `Closes`/`Fixes`. #6441 also holds the I2
      residual and the `WEB_HOST_PRIVATE_IPS` item, both still open.
- [ ] 5.2 Add **no** rule to `AGENTS.md` (over its 22k CRITICAL threshold).
- [ ] 5.3 File the three tracking issues: the pre-existing `cloudflared_ready || exit 1`
      hazard; `boot_id` on the shared emitter; the structural coherence-preflight gap.
- [ ] 5.4 Record the measured byte delta in the PR body.
- [ ] 5.5 CPO sign-off (threshold `single-user incident`) against the **reconciled**
      severity framing, not the maximal one.

## Verification idiom (applies to every check above)

Use `if grep -qE …; then ok; else no; fi` — the suite's established form
(`soleur-host-bootstrap-observability.test.sh:152-157`). **Never `grep -c … == 0`:**
`grep -c` exits 1 on a zero count, so it fails on the *passing* case under
`set -euo pipefail`. Scope every diff-based check to `apps/web-platform/infra/` and
exclude `knowledge-base/` — the plan's own prose would otherwise match.
