# Learning: an enforcement probe that treats "any failure = safe" is fail-open — discriminate exit codes

## Problem

`cron-egress-enforce-probe.sh` (#5933 item 3) proves a fresh host's container-egress
firewall is *enforcing* by curling a NON-allowlisted host (`example.com`) from inside the
container and requiring the connection to be **dropped**. The first implementation was:

```bash
if docker exec "$CONTAINER" curl -s -o /dev/null --max-time 8 https://example.com; then
  PROBE_RESULT=negative_fail; emit_fail; exit 1   # only curl EXIT 0 = "inert"
fi
echo egress-probe-negative-ok                      # ANY non-zero curl exit → "enforcing" pass
```

security-sentinel caught this as a **fail-open (P2)**: the check treats *every* non-zero curl
exit as "the firewall dropped it." But curl exits non-zero for reasons unrelated to the
firewall — DNS blip (exit 6), a transient stall, or a response slower than `--max-time`
(exit 28 from a genuinely slow-but-open path). So an **inert ruleset** (the exact bug the
probe exists to catch) coincident with any `example.com` transient failure → non-zero exit →
`egress-probe-negative-ok` → `PROBE_RESULT=ok` → `exit 0` → cloud-init skips `poweroff -f` →
the host stays up serving with an **open exfil path**. The fail-closed guarantee is silently
defeated in exactly the case it was built to prevent.

## Solution

Discriminate the curl exit code — do not collapse "reachable" and "unreachable-for-any-reason"
into one boolean. The firewall's default rule is nftables `drop` (silent discard), so an
enforcing ruleset makes the connect hang until `--max-time` → **curl exit 28 (timeout)**. Only
exit 28 proves a DROP; everything else is inconclusive → fail-closed:

```bash
neg_rc=0
docker exec "$CONTAINER" curl -s -o /dev/null --max-time 8 https://example.com || neg_rc=$?
if [ "$neg_rc" -eq 0 ]; then
  PROBE_RESULT=negative_fail;          emit_fail; exit 1   # reachable → INERT → poweroff
elif [ "$neg_rc" -ne 28 ]; then
  PROBE_RESULT=negative_inconclusive;  emit_fail; exit 1   # DNS/refused/infra → can't prove DROP → fail-closed
fi
echo egress-probe-negative-ok                              # exit 28 (timeout) = DROP = enforcing
```

Capture the exit under `set -e` with `|| neg_rc=$?` (the `||` keeps errexit from aborting
before the discrimination). The **positive** probe (allowlisted host must be reachable) is the
opposite polarity — a failure there errs toward `poweroff` (safe), so it gets `--retry 3` to
avoid a *destructive* false poweroff on a transient hiccup; the **negative** probe stays
single-shot (a retry there could mask a real open path).

## Key Insight

**A safety probe's failure mode must match its polarity.** When a probe asserts a *negative*
("X must NOT be reachable"), a naive "the operation failed → the negative holds" is fail-OPEN:
the operation fails for many reasons, only one of which is the property under test. Enumerate
the *specific* signal that proves the property (here: nftables `drop` → connect timeout → curl
exit 28) and treat every other outcome as **inconclusive → fail-closed**. The reflex "curl
failed, so the host was blocked" is the exact shape of the bug. This generalizes to any
allow/deny gate proven by a side-effecting probe (HTTP reachability, port scan, DNS
resolution, permission check): assert the *discriminating* exit/status, never "not success."

## Secondary: adding a baked host-script is a 6-leg lockstep

Adding one file to the fresh-host baked set (`local.host_script_files`) requires updating
**six** coupled sites, enforced across two suites:

1. `apps/web-platform/infra/server.tf` — `local.host_script_files` array (folds into `host_scripts_content_hash`).
2. `apps/web-platform/Dockerfile` — `COPY --from=builder /app/infra/<f> … /opt/soleur/host-scripts/`.
3. `apps/web-platform/.dockerignore` — `!infra/<f>` re-include (else the builder `COPY . .` excludes it → release build breaks, #5922 class).
4. `soleur-host-bootstrap.sh` — the 0755 install loop AND the `test -x` assert loop.
5. `plugins/soleur/test/cloud-init-user-data-size.test.ts` — bump the exact baked-set count (`.toBe(N)`).
6. `.github/workflows/infra-validation.yml` — register any new `.test.sh` (glob-less; unregistered = never gates).

Also: **inline cloud-init.yml comments count against the 32,768-byte Hetzner user_data cap**
(the baked scripts do NOT — they're extracted at boot). A verbose comment in the terminal
`runcmd` block tipped `cloud-init-user-data-size.test.ts` over budget; keep cloud-init
comments terse and put the rationale in the baked script's own header.

## Session Errors

1. **Planning subagent stalled on a nested background research agent** — the one-shot planning
   subagent (general-purpose) spawned a nested `repo-research` agent and stopped, emitting "I'll
   continue waiting…" instead of the required Session Summary; it produced zero plan/spec
   artifacts. **Recovery:** ran `/soleur:plan` + deepen inline in the parent with direct file
   reads (no nested agents). **Prevention:** in a one-shot planning subagent, do research with
   read-only tools (Grep/Read/Explore) inline; if a nested agent is spawned, the parent must
   actually await + reconcile it, never terminate on a "waiting" message. One-shot's fallback
   ("run plan inline") already recovers this — the parent should detect the missing Session
   Summary + zero on-disk artifacts and go inline, which it did.
2. **Self-introduced fail-open probe** (the primary learning above) — caught by security-sentinel.
   **Prevention:** for any negative-assertion safety probe, discriminate the exit code; treat
   "not success" as inconclusive→fail-closed, never as the negative holding.
3. **Lockstep test failed on first run (expected coupling)** — adding the baked script needed the
   count bump + `.dockerignore` re-include, and the verbose cloud-init comment blew the user_data
   budget. **Recovery:** fixed all three. **Prevention:** the 6-leg checklist above + keep
   cloud-init inline comments terse.
4. **Ran vitest for `cloud-init-user-data-size.test.ts` in `apps/web-platform`** but it lives in
   `plugins/soleur/test/` and runs under `bun test`. One-off. **Prevention:** `git ls-files | grep <basename>`
   before assuming a test's runner/location.

## Tags
category: best-practices
module: apps/web-platform/infra
