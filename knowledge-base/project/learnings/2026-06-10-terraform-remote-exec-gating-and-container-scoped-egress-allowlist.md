# Learning: terraform remote-exec assertions are non-gating without `set -e`; a container-scoped firewall fronts the WHOLE app

**Source:** #5046 PR-2 (PR #5089) — DOCKER-USER container egress firewall + cron containment-hook relax-minimal + 2-cron restore. 11-agent review fixed 38 findings inline (4 P1).

## Problem

Four independent failure classes converged on one PR:

1. **Terraform `remote-exec` `inline` assertions were decorative.** Terraform joins the `inline` list into ONE shell script with NO implicit errexit; the provisioner fails only on the LAST command's exit. The new provisioner's "merge-precondition" probes (`nft list | grep -q`, a live positive+negative container probe) all preceded an unconditional `echo` — an inert ruleset would have applied GREEN, the exact silent-green failure the probes existed to prevent. Five review agents independently flagged it; the 7 sibling provisioners on main share the latent class (`fail2ban_tuning` works only because its `test` asserts happen to be last; `docker_seccomp_config`/`apparmor_bwrap_profile` end in always-true `echo`s).
2. **The plan's allowlist was cron-scoped, but a DOCKER-USER firewall is CONTAINER-scoped.** The plan enumerated ~12 cron-needed hosts; grep-enumeration of ALL runtime egress found 10 more — Resend (email), Buttondown (waitlist), Cloudflare/Stripe/Hetzner (BYOK validators), the 3 browser push services, and the first-party canary targets (soleur.ai/app/api — live plain-fetch crons dial them THROUGH the firewall). Without them, default-drop breaks user-facing flows: the single-user incident the plan's own threshold names.
3. **Doppler-wrapped systemd units need three things the bare `ExecStart=/usr/bin/doppler run ...` shape lacks:** `EnvironmentFile=/etc/default/inngest-server` (DOPPLER_TOKEN source), a HOME (the CLI calls `os.UserHomeDir()`; root system services get none — the documented 2026-05-20 heartbeat-unit failure), and path resolution (cloud-init installs `/usr/local/bin/doppler`; `/usr/bin` is a latent discrepancy `inngest-bootstrap.sh:206-209` explicitly works around). As written, the firewall would never have installed and BOTH OnFailure alarm channels were dead.
4. **DNS-pin reconciliation interacts with Docker's resolv.conf substitution.** Containers on the default bridge get `8.8.8.8/8.8.4.4` substituted whenever the host's resolv.conf is loopback-only. A prune tick while the container is down (deploy window) derives the pin set from the HOST upstreams and deletes the substitution pair → every container DNS query drops on restart (total egress blackout, misclassified as "dns exfil"). Similarly, an expected-but-ABSENT dynamic env var (Doppler rename) silently removed Supabase from the desired set with `FAILED_HOSTS=0` → live IPs pruned → app-wide outage.

## Solution

1. `"set -e"` as the FIRST `inline` element; enforcement probes as explicit `if cmd; then echo FAILED; exit 1; fi` (note: `!`-prefixed pipelines are errexit-EXEMPT under POSIX — `! docker exec … && echo ok` does not reliably gate); fresh-host container-absent case skips probes LOUDLY (the next apply proves enforcement). Drift guard asserts the probe strings; only `set -e` makes them load-bearing.
2. Sweep-class allowlist discipline: `git grep -hoE 'https://[a-z0-9.-]+' <runtime dirs>` enumerates the authoritative host list; the drift guard pins an EXACT host count so any new host forces a deliberate test edit carrying its evidence.
3. Mirror the inngest unit precedent verbatim: `EnvironmentFile=-/etc/default/inngest-server` + `Environment=HOME=/root` + `ExecStart=/bin/sh -c 'D="$(command -v doppler||true)"; if [ -n "$D" ] && [ -n "$DOPPLER_TOKEN" ]; then exec "$D" run ... -- <script>; else exec <script>; fi'` (graceful doppler-less degradation keeps the firewall installable on a fresh host).
4. Unconditionally seed the Docker substitution pair into the DNS pin set; union the container's OWN `getent` view (one `docker exec` per tick) into the allow set (CDN answers diverge per resolver); count an absent expected env var as a FAILED host → additive-only tick (prune never fires on env drift).

## Key Insight

**A guard that cannot fail is worse than no guard — it converts "unverified" into "verified-looking".** Terraform `remote-exec`'s no-errexit join is the infrastructure twin of the vacuous-RED test class: the assertion text exists, runs, and is structurally incapable of failing the operation it claims to gate. Apply the same non-vacuity discipline as RED-verification: before trusting any multi-command assertion block, identify which command's exit status the harness actually consumes.

**Scope the enumeration to the BOUNDARY, not the feature.** The firewall's boundary is the container; the feature was crons. Every deny-by-default boundary inherits the egress needs of EVERYTHING inside it — enumerate from the boundary inward (grep all runtime code), never from the feature outward.

## Session Errors

1. **CWD drift across Bash calls** (vitest exit 127, sed exit 2, terraform -chdir failures, bun-test filter no-match) — Recovery: re-run with `cd <worktree-abs-path> && cmd` chained in one call. **Prevention:** existing work-skill bullet covers this; the recurrence count (~4) suggests defaulting EVERY test/build invocation to the chained form rather than relying on persisted CWD.
2. **Authored non-gating provisioner assertions** — Recovery: `set -e` first + if/exit-1 probes (review caught it). **Prevention:** routed to work SKILL.md Infrastructure Validation as a bullet; sibling-provisioner sweep file-tracked (see issue).
3. **Authored doppler units without reading the inngest precedent** — Recovery: rewrote all 4 units per `inngest-bootstrap.sh:150-232`. **Prevention:** before authoring ANY systemd unit that wraps a credentialed CLI, grep the infra dir for an existing unit wrapping the same CLI and diff your draft against it (the precedent encodes 3 non-obvious requirements).
4. **Drift-guard authoring bugs at RED** (stray `--` arg, missing `-E`, comment-prose forbidden-pattern match, `$'` escaping) — Recovery: caught by running the guard before relying on it. **Prevention:** always run a new guard in its RED state and read EVERY failure line — a guard's own bugs surface as nonsense failures.
5. **Three test files broke after SUT extensions** (hook self-test mock arity, webpush arity, monitor registry) — Recovery: mock-chain sweep same cycle. **Prevention:** covered by existing wrapper-extension-mock-sweep learning; worked as designed.
6. **signature-verify test timeouts under full-suite load** — Recovery: passed in isolation; pre-existing flake. **Prevention:** none needed (env-only; per wg-when-tests-fail-and-are-confirmed-pre).
7. **Edit-tool staleness rejection on cron-monitors.tf** — Recovery: re-read, re-applied. **Prevention:** one-off.

## Tags

category: integration-issues
module: infra, cron-containment
