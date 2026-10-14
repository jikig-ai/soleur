# Phase 0 — probe results (#6982)

Measured on this worktree at base `81d141b27`, 2026-07-27. Every number below is a
**measurement**, not a plan restatement — the plan's own figures are treated as
preconditions to re-derive (`hr-when-a-plan-specifies-relative-paths-e-g` class).

---

## 0.1 W0 — the `doppler run` config-scope probe **[P0 CONFIRMED — a live boot-breaker]**

**Method.** Created a throwaway branch config `soleur/prd_w0probe6982` under the `prd`
environment, seeded `GIT_DATA_LUKS_KEY` into it, minted a **`read`** service token scoped to
that single config — i.e. scoped exactly the way `doppler_service_token.git_data`
(`git-data-luks.tf:100-104`, `project = soleur`, `config = prd_git_data`, `access = read`)
is — then ran the invocation `cloud-init-git-data.yml` actually uses. Config and token were
deleted immediately (trap-on-EXIT).

Exit status was **not** the criterion (R36): a CLI that silently resolved to an empty `prd`
view would exit 0 with the key absent, which is the dark boot. The criterion is whether
`GIT_DATA_LUKS_KEY` is present in the resulting environment.

| Arm | Invocation | Exit | `GIT_DATA_LUKS_KEY` in env |
|---|---|---|---|
| **A** — what `cloud-init-git-data.yml` does **today** | `doppler run --project soleur --config prd -- env` | **1** | **absent (count=0)** |
| **B** — the fix candidate | `doppler run --project soleur --config prd_git_data -- env` | 0 | **present (count=1)** |
| **C** — no flags (token scope implied) | `doppler run -- env` | 0 | present (count=1) |

Arm A stderr, verbatim:

```
Unable to fetch secrets from the Doppler API
Doppler Error: This token does not have access to requested config 'prd'
Reading secrets from fallback file
Doppler Error: The fallback file does not exist
```

**Verdict: the CLI ERRORS on the mismatch. It does not defer to the token's own scope.**

**Consequence — this is not a latent risk, it is a present defect on `main`.** Both
boot-critical blocks in `cloud-init-git-data.yml` (the `LUKSEOF` heredoc at :165 and the
bootstrap invocation at :191) run `doppler run --project soleur --config prd`. On a real
birth today:

- `doppler run` exits 1 **before exec'ing** the heredoc, so `set -euo pipefail` — line 1 of
  that heredoc — runs **zero times**. `cryptsetup luksOpen` never runs; at-rest encryption
  is absent while every artifact claims it present.
- `git-data-bootstrap.sh` never runs: no bare-repo root, no `core.hooksPath`, no fence.
- That runcmd item carries **no `set -e`** (this PR's issue item 3), so cloud-init logs the
  failure and **continues**. sshd is already up, so `web-git-data-probe.sh` reports the host
  **reachable** and any :22-based beat would go green.
- Nothing is emitted off-box.

That is precisely the "green apply, dark host" state the birth-readiness interlock exists to
prevent — sitting inside the very file the interlock inspects. `git-data-luks.test.sh` A6
asserts only that the *string* `doppler run` survives; nothing asserted the scope agreed.

**Design decision this gates (W0's purpose): remedy (b) then (a).**

1. Correct both invocations to `--config prd_git_data` (Arm B). Explicit over Arm C's
   flagless form: it is self-documenting, matches the sibling hosts' explicit style, and is
   greppable by a drift guard.
2. Because the token *can* read `prd_git_data` (Arm B), the Better Stack ingest secret may
   live there — so `doppler_secret.git_data_betterstack_logs_token` returns (plan 2.0 / D1)
   and the birth `-target` set goes **18 → 20**, not 18 → 19.

---

## 0.2 Readiness gate HOLDs — the RED half

```
source tests/scripts/lib/git-data-birth-readiness-gate.sh \
  && git_data_birth_readiness_gate apps/web-platform/infra/cloud-init-git-data.yml
```

→ **exit 1**, prints `HOLD — the git-data birth route is INTERLOCKED and will not apply.`
The gate can refuse before it is trusted to release.

## 0.3 `user_data` budget baseline — **the plan's figure was optimistic (R38 confirmed)**

Rendered via `terraform console` on the real `templatefile(...)` with the full var map, then
measured through Terraform's **own** `base64gzip` (default compression level), never
`gzip -9`.

| | Plan (measured with `gzip -9`) | **Measured (Terraform `base64gzip`)** |
|---|---|---|
| Raw render | ~41.7 KB | **43,711 B** |
| Stored (what Hetzner caps) | ~21.9 KB | **23,716 B** |
| Cap | 32,768 B | 32,768 B |
| **Headroom** | ~10.8 KB | **9,052 B** (72.4 % used) |

`-9` overstated headroom by ~1.8 KB on what the plan itself calls a hard gate. **9,052 bytes
is the real budget** for everything this PR adds (emitter, `bootcmd` beacon, gc units, sshd
directives, trap/`STAGE` machinery). Shell text gzips ~2.7:1 here, so that is roughly 24 KB
of raw additions — workable, but it must be re-measured after each phase, not assumed.

`cloud-init schema -c <rendered>` on the baseline: **Valid schema** (exit 0). The two
`datasource not detected` lines are expected off-host.

`grep -cP '(?<!%)%\{'` on the template: **0** (AC4's form, which correctly tolerates the
doubled `%%{…}` that `curl -w` needs).

## 0.4 `runcmd` must-abort / must-tolerate classification

Adopted from the plan's nine-item table, **extended to the items this PR adds** (R16). Applied
in Phase 3.3; item #1 is the real hazard because W6 edits the sshd drop-in in this same PR.

| # | Item | Under `set -e` |
|---|---|---|
| 1 | `systemctl restart sshd` | **hazard** — gate on `sshd -t` first (Phase 3.2) |
| 2 | `mkdir -p /mnt/git-data` | safe |
| 3 | `mount … \|\| true` | already-declared must-tolerate; keep the `\|\| true` |
| 4 | `echo … >> /etc/fstab` | safe |
| 5 | `curl -fsSL` / `sha256sum -c -` / `tar xzf` / `chmod +x` / `rm` | **must-abort by design** — this is issue item 3 |
| 6–7 | `printf … > /etc/default/…`, `chmod 600` | safe |
| 8–9 | `. /etc/default/git-data-doppler`, `doppler run …` | must-abort by design |
| **new** | `sshd -t` | must-abort (that is its whole purpose) |
| **new** | `systemctl enable --now git-data-gc.timer` | must-tolerate — a maintenance timer must never brick a boot |

## 0.5 `HOME=/root` reaches the runcmd shell before any `doppler` call

**Confirmed.** `cloud-init-git-data.yml:149` writes `HOME=/root` into
`/etc/default/git-data-doppler`, and both `doppler run` sites (:163, :189) `set -a` +
source that file immediately before invoking. Three prior dark boots came from this class;
it is already correct here and must stay correct after the Phase-3 edits.

## 0.6 ADR-149 item 6 — firewall entailment **already discharged on `main`**

Evidence, not assumption: `tests/scripts/lib/git-data-host-birth-gate.sh:397-399` carries
`hcloud_firewall_attachment.git_data is DELIBERATELY NOT IN THIS LOOP`, and :472-477 asserts
the **outcome** (`server_ids` ends at length 1) rather than a create verb, with the
hcloud-provider-source rationale inline. **No code change required.**

## 0.7 Better Stack query form + sweeper credentials

- `scripts/betterstack-query.sh` exports `BS_TABLE` (default
  `t520508_soleur_inngest_vector_prd_3_logs`) and `BS_TABLE_S3`, and **Mode 1 raw SQL**
  substitutes both tokens (`:104-113`), with `$BS_TABLE_S3` substituted *before* `$BS_TABLE`
  because the latter is a prefix of the former. Mode 1 does **not** auto-add the archive arm,
  so the `UNION ALL s3Cluster(...)` must be written explicitly — `remote()` alone covers only
  the ~40-minute hot window, which a once-per-boot marker falls out of immediately.
- The default table **is** the correct one for git-data: `local.betterstack_logs_ingest_url`
  (`zot-registry.tf:103`) is `https://s2457081.eu-fsn-3.betterstackdata.com/`, i.e. source
  **2457081** = `soleur-inngest-vector-prd`. Pinned explicitly anyway (R38).
- **Sweeper credentials confirmed present** (R4): `scheduled-followthrough-sweeper.yml:72-74`
  passes `BETTERSTACK_QUERY_HOST`, `BETTERSTACK_QUERY_USERNAME`, `BETTERSTACK_QUERY_PASSWORD`
  — the three names `betterstack-query.sh` actually requires. `BETTERSTACK_LOGS_QUERY_TOKEN`
  (v1's name) exists nowhere in the repo. No workflow edit is needed; the follow-through
  probe's `secrets=` directive must name these three.

---

## Net effect on the plan

| Plan assumption | Probe result |
|---|---|
| W0 "may" be a scope mismatch | **Is** one, and it breaks boot today. Fix is mandatory, not conditional. |
| Better Stack secret shape decided by W0 | Remedy **(b) then (a)**: correct the invocation, then place the secret in `prd_git_data`. Target set **18 → 20**. |
| ~10.8 KB `user_data` headroom | **9,052 B**. Budget every addition against this. |
| ADR-149 item 6 may need correcting | Already discharged; no change. |
| Sweeper may need `secrets=` wiring | Already wired; name the three existing secrets. |
