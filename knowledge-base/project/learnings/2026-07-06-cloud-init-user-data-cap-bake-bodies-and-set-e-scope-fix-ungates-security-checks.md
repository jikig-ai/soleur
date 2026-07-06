---
title: "cloud-init observability at the 32KB user_data cap: bake emit bodies, keep comments terse, and a set -e scope-fix un-gates accidentally-protected checks"
date: 2026-07-06
category: integration-issues
module: apps/web-platform/infra
tags: [cloud-init, hetzner, user_data, byte-cap, set-e, errexit, observability, sentry, drift-guard, baked-scripts]
pr: "#6092"
tracker: "#6090"
related:
  - 2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md
  - 2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns.md
---

# cloud-init fresh-boot observability at the 32,768-byte cap (#6090 / PR #6092)

Adding Sentry breadcrumbs + readiness gates across web-2's silent fresh-boot sequence,
in the no-SSH off-host model. Three non-obvious, recurring lessons surfaced.

## 1. cloud-init COMMENTS count toward the 32,768-byte user_data cap — bake the bodies, keep cloud-init terse

The rendered `cloud-init.yml` (Terraform `templatefile()` output, NOT gzipped) **is** the
Hetzner user_data, comments included. On this repo the baseline renders to ~31.5 KB, leaving
**~0.4–1.3 KB headroom** (the `bootstrap.sh:153` "within ~1 KB" note is more current than the
stale `server.tf:56` "~29.6 KB"). Two byte-budget breaches this session, both from verbose
multi-line rationale comments — the first at **+2196 over**, the second (after review) at
+1331 over. Measure the *rendered delta* (`git show origin/main:…cloud-init.yml` vs current,
same dummy vars, `wc -c`) — it was +2196 → +892 after: **comments were ~2/3 of the bloat.**

**Pattern that fits under the cap:** an emitter/poller body cannot live inline (~20 lines ≈
0.7 KB each). Instead have the already-baked `soleur-host-bootstrap.sh` **author** the helper
scripts at boot via heredoc → 0 user_data:

```sh
# quoted heredoc keeps $1/$STAGE literal; sed bakes the value in (avoids per-$ escaping)
cat > /usr/local/bin/soleur-boot-emit <<'EMITEOF'
#!/bin/sh
( set +e; DSN='@@SOLEUR_SENTRY_DSN@@'; …POST… ) || true
EMITEOF
sed -i "s|@@SOLEUR_SENTRY_DSN@@|${SOLEUR_SENTRY_DSN:-}|" /usr/local/bin/soleur-boot-emit
```

cloud-init then carries only cheap call-sites (`soleur-boot-emit <stage> <level>`,
`soleur-wait-ready port 9000 webhook_bound || exit 1`). Bonus: baking inside the *existing*
baked script adds NO new Dockerfile / `server.tf host_script_files` / hash lockstep.
Keep every cloud-init comment a terse `# #6090: <5-8 words>` pointer — the rich rationale
belongs in the plan + the test-file header + the PR body (where reviewers/operators read it),
never in user_data. Backstop: Hetzner rejects `>32768` at **apply** time — an over-cap fails
the recreate *apply* loudly (no silent bad boot, never touches the live host).

## 2. cloud-init joins ALL runcmd items into ONE `/bin/sh` — a leaked `set -e` silently aborts, and scoping it un-gates whatever the leak was accidentally protecting

`cc_runcmd` shellifies the whole `runcmd:` list into one `#!/bin/sh` script, so `set -e`,
vars, and traps **leak across list items** (the file's own line-349/559 comments assert this).
The #5921 extraction block did `set -e` and disarmed its `on_err` trap but never restored
`set +e` → errexit leaked into the bare downstream `apt-get`/cloudflared region with **no
trap** → a transient non-zero silently aborted the whole runcmd = the exact "cloudflared never
comes up, :9000 never binds" symptom. **Likely the real root cause**, found by code-read.

Fix = `set +e` right after the extraction block (restores the "runcmd is NOT under a top-level
set -e" invariant the terminal fail-closed gate already assumes). **But the scope-fix has a
sharp edge review caught:** the leaked errexit had been *accidentally* fail-closing the webhook
binary's `sha256sum -c -` (a mismatch aborted the boot). Restoring `set +e` un-gates it → an
unverified binary would install. Any check that was only errexit-protected must be made
**explicitly** fail-closed when you scope the leak: `sha256sum -c - || { emit …; exit 1; }`.
Ask, for every security/integrity command in the newly-`set +e` region: "was this only
aborting because of the leak?"

## 3. Async systemd-service death needs an active readiness poll — a command-level trap cannot see it

`systemctl enable --now webhook` / `cloudflared service install` return 0 the instant the unit
*launches*, not when it binds `:9000` / connects the tunnel. The primary symptom (8/8 probes
hit web-1) is an **async** bind failure no runcmd trap can observe. The only detector is a
bounded-timeout active poll of the real invariant (`ss -ltn | grep :9000`, `systemctl
is-active`) → named fatal + `exit 1`. Note `is-active` proves process liveness, NOT tunnel
connectivity — end-to-end tunnel health stays the workflow fan-out's / Better Stack's job.

## 4. A byte-identical cross-file parity drift-guard makes indentation load-bearing

`cron-egress-enforce-probe.test.sh` asserts the Sentry transport lines are **byte-identical**
(incl. 6/8-space indent) between the probe and `soleur-host-bootstrap.sh`'s emit. Refactoring
`emit_fail`'s inline block into a shared `_sentry_emit` helper de-indented those lines 6→4
spaces and broke the guard (`grep -qF` is substring-with-leading-whitespace). Restoring the
`if [ -n "$DSN" ]; then` nesting put them back at 6/8-space. **When a drift-guard asserts
byte-identity, any refactor of the guarded lines must preserve exact indentation** — and when
you *add* an Nth copy (here a baked emitter), extend the guard to cover it indentation-agnostic
(`grep -cF … >= 2`), or the new copy silently drifts with every guard still green.

## Session Errors

1. **New `.test.sh` aborted early under `set -e`.** `line_of()` command-substitution greps hit
   errexit on a no-match (accumulate-then-exit foot-gun; recurred despite
   [[2026-06-29-bash-accumulate-then-exit-gate-test-three-footguns]]). Recovery: wrap each
   deliberately-nonzero `$(grep …)` in `|| true`. **Prevention:** author `pass/fail`-accumulator
   `.test.sh` files by guarding EVERY `$(grep …)` / `$(… | head …)` with `|| true` from the start.
2. **AC4 sentinel grep matched a header comment** (`/run/soleur-hostscripts.ok` appears at line
   17 AND the line-199 write). Recovery: anchor on the write construct `: > /run/…`.
   **Prevention:** anchor line-order assertions on the syntactic construct (the write/call), never
   a bare path/token the file also names in prose.
3. **AC3 DSN-preference grep over-counted** (matched `_sentry_emit` AND the `sed …${VAR:-}` bake).
   Recovery: anchor on the `DSN="${VAR:-}"` assignment form. **Prevention:** count occurrences of
   the specific syntactic form, not a substring the value-bake also contains.
4. **Byte budget blown twice** (+2196, then +1331 over the 32,768 cap) — cloud-init comments count
   toward user_data. Recovery: bake bodies (§1) + terse comments + drop low-value breadcrumbs.
   **Prevention:** measure the rendered delta after every cloud-init edit; keep comments to a
   one-line pointer; bake any >5-line body.
5. **Composite trap broke the existing inngest test** (`grep -qE 'trap cleanup EXIT'`). Recovery:
   relax the sibling assertion to `trap .*cleanup.* EXIT` in the same PR. **Prevention:** when you
   change a trap/literal a sibling drift-guard pins, update that guard in lockstep.
6. **`_sentry_emit` refactor de-indented the parity-guarded transport** (§4). Recovery: restore the
   `if` nesting. **Prevention:** grep for a byte-identity guard before refactoring shared lines.
7. **Full infra `*.test.sh` suite timed out** (2m; slow docker/terraform tests). Recovery: scope to
   `grep -l <changed-file> *.test.sh` with a per-test timeout. **Prevention:** never run the whole
   infra suite inline; scope to tests referencing the changed files.
8. **Review caught a real MEDIUM bug I introduced:** the inngest composite trap was never disarmed
   (`trap - EXIT`), so it lingered into the trap-less terminal block and mislabeled a
   `doppler_download` failure as `stage=inngest_bootstrap`. Recovery: disarm at block end (mirror
   `plugin_seed`). **Prevention:** an EXIT trap that emits a *named* stage MUST be disarmed at its
   block's end, or it misattributes any later exit in the same shell.
