# Review findings — PR #7444 (#7440), 11-agent panel @ `e406a3ba1`

**Verdict: NOT SHIPPABLE.** The panel found ~60 findings, ~13 of them genuine P1s. Two are fixed
here; the rest are an owed fix round. This file is the durable record so nothing is lost.

Ten of eleven agents returned. `pattern-recognition-specialist` **stalled** (stream watchdog, 600s)
and never reported — its lens (Terraform escaping sweep, negative-assertion vacuity, `grep -q`
SIGPIPE, single-literal gates) is **uncovered** and should be re-run.

`semgrep-sast` was substituted by `shellcheck` per the documented bash carve-out (semgrep's
tree-sitter bash parser matches ~0 rules, so a clean result on a bash-dominant diff is vacuous).

---

## FIXED IN THIS PASS

### F-1 (P1, architecture-strategist) — the shipper would never have run
`ExecStart` named `/usr/bin/doppler`. This template installs the CLI to `/usr/local/bin`
(`tar xzf … -C /usr/local/bin doppler`) and creates **no symlink**; the sibling inngest template
carries an explicit `ln -sf /usr/local/bin/doppler /usr/bin/doppler` precisely because that path is
not otherwise real. Every other doppler call site in this file is bare and PATH-resolved — the unit
was the only absolute one and it picked the path a *different* host had to fabricate.

Consequence: `status=203/EXEC`; and because `Restart=always` + `StartLimitIntervalSec=0`
deliberately disable the latch, a permanent 5s restart loop shipping nothing, whose only fix is
another destructive replace of the fleet's sole image-pull path.

**Why my gate missed it:** T12 runs `systemd-analyze verify`, which *does* reject a missing
`ExecStart` binary — but resolves against the **runner's** filesystem. This box has
`/usr/bin/doppler` and lacks `/usr/local/bin/doppler`: the exact inverse of production. The gate
validated the developer's host. Fixed, plus a template-relative assertion that every absolute
`ExecStart` path is installed by this same template.

### F-2 (P1, code-quality-analyst) — the ADR ordinal was wrong and collided on `origin`
ADR-179 is taken by `ADR-179-bare-plugin-root-anchor-for-customer-facing-executables` on
`origin/feat-one-shot-7442-sync-plugin-root-anchoring` (**open PR #7443**). 176–181 are all claimed.
Renumbered to **182**, references swept (8 files).

Worse than the collision: my "2,986 refs" derivation reached a **wrong conclusion**, and the lesson
I drew from it pointed away from the real defect. I wrote that the danger was *local-only branches
invisible to origin*; the actual collision was **on origin**, inside the narrow scope I dismissed as
too narrow. Sibling branches renumbered between my probe and the review. AC18's "re-derive
immediately before merge" is the operative discipline, not a wider one-shot sweep.

---

## OWED — P1

### F-3 — the cursor can mean READ instead of DELIVERED, and a transient outage discards silently
Found twice, independently, by different methods (`test-design-reviewer` by mutation,
`data-integrity-guardian` by execution).

- Moving `persist_cursor` out of the `if ship … then` success branch leaves the suite **108/108**.
  Demonstrated: sink down → 0 rows delivered, cursor at `i=3`; sink recovers → **0 rows delivered**.
  A transient Better Stack outage permanently discards every row in it.
- Independently: a **failed** POST already loses the line permanently today. `ship` failure only does
  `POST_FAIL++` — it does not bump `WIN_DROPPED`, emits no drop row, and the *next* successful line
  advances the cursor past the hole. Executed: offered 3, shipped 2, `dropped_cum=0`, cursor `i=3`.
  This violates the suite's own T9 invariant (`dropped n + shipped == offered`) and no test covers it.
  It manufactures the exact "stalled gc" false signal the cap exemption exists to prevent.

**Fix:** on `ship` failure either bump `WIN_DROPPED` + emit `reason=post_fail`, or `break` and exit
non-zero so `Restart=always` replays from the last *delivered* cursor. Add to T11:
`assert "a FAILED POST did NOT advance the cursor" "[[ ! -s "$LAST_STATE/cursor" ]]"` plus a resume
leg proving the undelivered row is still reachable. Also add backoff — the two `post_body` attempts
fire back-to-back, so a briefly-500ing ingest fails both.

### F-4 — no assertion floor anywhere; `assert()` → `return 0` is CI-green
Neutering `assert()` yields `=== 0 passed, 0 failed ===`, **rc=0**, in both suites. Deleting
everything from T5 onward yields `28 passed, 0 failed`, rc=0. Neither runner has a floor either
(`run_suite` branches solely on `if ! "$@"`; the workflow step is pure rc).

**Fix:** an **absolute literal** `MIN_ASSERTIONS` (108 / 55) that increments `FAIL` rather than
exiting, immediately before the gate. Never derive it from the input it guards — a derived floor is
reduced by the same truncation it exists to detect.

### F-5 — cap-exempt classes are unbounded; the 5,000/day budget is not enforced
Converged across **five** agents. `is_cap_exempt` returns 0 before `WIN_COUNT` is consulted and
exempt lines face no ceiling. `PatchBlobUpload` fires per blob-upload chunk, so exempt volume is
proportional to push traffic. `performance-oracle` measured the crash-loop case: 6,912 restarts/day
× ~10 repos × ~2 gc lines ≈ **138,000 rows/day = 28× the budget** — in the exact scenario the
exemption was sized against. Shared-source consequence: source 2457081 also carries the web hosts'
and Inngest node's Vector rows *and* this host's own `SOLEUR_ZOT_DISK` disk/OOM alarms, so the
observer can starve the observed.

Also: the predicate matches the **whole line**, so `User-Agent: executing gc` from any private-net
client makes every one of its request lines exempt.

**Fix:** a separate generous ceiling (`CAP_EXEMPT_PER_INTERVAL`) with `reason=exempt_cap`, and match
on a **parsed field** rather than a whole-line substring.

### F-6 — the probe's PASS arm publishes raw production rows to a PUBLIC issue
`printf '%s\n' "$envelope_hits" | tail -3 | cut -c1-200` is the last thing before `exit 0`;
`sweep-followthroughs.sh` captures `2>&1` and posts it as a comment; the repo is PUBLIC. This
contradicts the FAIL arm's own counts-only discipline **108 lines earlier in the same file**.

Certain content: internal `10.0.1.x` topology, service usernames, OCI repo names, digests, paths,
User-Agent. Demonstrated against the **unmutated** probe: a row carrying a credential shape outside
the three scanned patterns exits 0 and the value appears in stdout.

**Fix:** drop the excerpt or reduce it to counts / field names.

### F-7 — `boot_id` drift ≠ a provisioning event, and this host self-reboots
Converged (`observability-coverage`, `agent-native`). The NIC guard calls `reboot` as a convergence
primitive, and `runcmd` is per-instance so no boot marker fires. A plain reboot of the current
**un-replaced** host flips `delivered=1` → `reason=delivered_but_silent` → "ACT, NOT WAIT" → starts
the 90-day escalation clock on a host that was never replaced. Reproduced.

**Fix:** gate `delivered` on the **presence of the `log_shipper_post_fail=` key** — that key exists
only in the new cloud-init, so key-absent ⇒ old host ⇒ not delivered, regardless of `boot_id`. Treat
`=unknown` as its own sub-state (the probe's `[0-9]+` regex currently discards it and then reports
"no POST failures", an absence it never measured).

### F-8 — drop accounting rides the failing path
`emit_drops` calls `ship()`. The plan's `error_reporting.fail_loud` forbids exactly this for
`post_fail` and then does it for both drop reasons. `cursor_invalidated`'s *stated cause* is a sink
outage — so its only signal is structurally undeliverable in its own causal story. `dropped_cum` and
`drop_seq` are already in the state file and the reporter reads neither.

**Fix:** add them to the reporter's `case` and `LINE` (~4 tokens; the data is already there).

### F-9 — cursor invalidation replays from the HEAD, not the tail
On invalidation `CURSOR=""`, and `JARGS` still carries `--no-tail`, so recovery reads the **entire
retained journal** — now 512 MB by this same diff. The block's own comment says "restarts from the
tail." The code does the opposite. This is the runaway-volume mode the design cites as its reason
for rejecting `--cursor-file`, re-introduced by a different door.

**Fix:** on invalidation drop `--no-tail` (or add `-n 0` / `--since=-5m`); assert the resumed
invocation's args, not just the drop row.

### F-10 — `redact()` is header-NAME-anchored while three artifacts claim header-object anchoring
Converged (security, user-impact, observability). Both sed rules key on the literal
`[Aa]uthorization`; ADR §3 and the cloud-init comment both say "anchored on the header-object shape
rather than trusting one header name's known masking." Measured survivors: `Cookie`, `X-Api-Key`
ship verbatim (silent); `Proxy-Authorization` ships and *then* trips the probe. T6 **locks the gap
in** by asserting an unrelated header value is preserved.

Also (`security-sentinel`): a `]` inside the Authorization value defeats both the redaction and the
detector — `[^]]*\]` stops at the first `]`, so the row literally contains `Authorization:[REDACTED`
while the credential tail sits three characters right, and the subtraction exonerates the line.

**Fix:** redact the whole `"headers":{…}` object with a name allowlist; invert T6 to assert an
arbitrary unknown header IS redacted.

### F-11 — `jq` absent ⇒ 100% silent loss, unit green, zero accounting
`jq` is a hard per-line dependency. It is in `packages:`, whose own comment says that stage is
NON-FATAL — and only `e2fsprogs` gets a runcmd `dpkg -s` re-ensure guard. Executed with `jq` off
PATH: **0 of 2 rows delivered, rc=0, no stderr, state all zeros, no drop rows**, unit `active`
forever. The reporter then emits `post_fail=unknown`, which the probe's `[0-9]+` cannot match, so it
reports the inverted root cause.

**Fix:** add the `dpkg -s jq || apt-get install -y jq` guard; fail loudly at startup on missing `jq`.

---

## OWED — P2 (abbreviated; see the panel reports for full reasoning)

| # | Finding | Source |
|---|---|---|
| F-12 | `EnvironmentFile=` vs `Environment=` precedence — architecture cites `systemd.exec(5)` ("settings from these files override `Environment=`") against my empirical real-unit-file test which showed the opposite. **Unresolved contradiction — must be re-measured decisively.** Two of my T12 assertions certify a model that may be inverted, and a wrong model will be copied. | architecture |
| F-13 | Doppler fallback cache: `DOPPLER_CONFIG_DIR` under `StateDirectory` makes this the estate's first *persistent* doppler config root; `doppler run` writes an encrypted cache of the whole `soleur-registry/prd` secret set there, co-located with its passphrase source on the same unencrypted root fs. Add `--no-fallback`. | security |
| F-14 | The unit holds the **whole** `prd` secret set (incl. `REGISTRY_LUKS_KEY`) in a permanently-resident process env with no `LimitCORE=0`. Use `--only-secrets BETTERSTACK_LOGS_TOKEN`. | security |
| F-15 | Resource-cap magnitudes unasserted: `MemoryMax` 128M→3000M, `CPUQuota` 20%→400%, `SystemMaxUse` 512M→4G, `RuntimeMaxUse` 64M→2G, `RestartSec` 5→86400, `RuntimeMaxSec`→1yr **all survive**. Shape regexes with no bound. | test-design |
| F-16 | `RuntimeMaxUse=64M` **raises** the volatile ceiling above journald's ~38 MB default — the opposite of the stated RAM-relief intent. | user-impact, performance |
| F-17 | The 1024 MB host reserve is mis-derived (host reports 3,814 MB, cap derived from nominal 4,096 → true remainder **742 MB**) and this change spends ~180 MB against it without repaying `registry_host_reserve_mb`. | performance, code-quality, user-impact |
| F-18 | `IOWeight=20` is a **verified no-op** (no BFQ; `io.cost.model`/`qos` empty) and is on the wrong cgroup for the stated goal — journald's fsync is in journald's cgroup. | performance |
| F-19 | `journald_storage=persistent` in the boot marker is a hardcoded literal behind a `|| true` restart, not a readback. Its sibling `shipper_unit=` *is* a readback, making the asymmetry look deliberate. | user-impact, performance |
| F-20 | `shipper_unit=$(systemctl is-active …)` is structurally always `active` — `Type=simple` marks active on fork, sampled in the next runcmd entry. The discrimination it exists for cannot fail closed. | user-impact, agent-native |
| F-21 | The failed-ship breadcrumb writes an ~800B copy of each line back into the same journal, so under egress outage retention collapses (~3.4 days, not 12) and eviction is oldest-first — deleting incident onset. Sizing also used 300 B/entry vs **666 B measured**, and `SystemMaxUse` is host-wide, not zot's. | user-impact, performance |
| F-22 | No restart backoff: a persistent start failure = 12 attempts/min forever = ~17,280 `doppler run` invocations/day. systemd ≥254 has `RestartSteps=` + `RestartMaxDelaySec=`. | performance |
| F-23 | `control_missing` and `envelope_without_zot_content` exit 2 on states where the channel is **working**, so a stopped disk cron or a zot module-path bump blocks the ADR flip indefinitely. Demote to PASS warnings. | code-simplicity |
| F-24 | Probe `--limit 400` can truncate under flood, making `n_envelope` a lower bound — the original defect one layer up, with no marker. Assert `LIMIT > cap × windows` or report on exactly-LIMIT. | code-simplicity |
| F-25 | `fromjson?` → `fromjson` survives, and is a **live fail-open**: without `?`, jq aborts at a noise row and every row after it drops from `$envelope_hits`, hiding a leak behind it. | test-design |
| F-26 | Harness seams: the `hostname` stub returns the real production hostname so hardcoding it survives; `STUB_SKIP_UNTIL` does the work `--after-cursor` is credited with (first-cursor-only mutation survives); the `curl` stub records `url=` and nothing reads it, so dropping the Bearer header or pointing at a wrong endpoint both survive. | test-design |
| F-27 | T3/T7's `journalctl…CONTAINER_NAME=zot` greps resolve against the **cursor-probe** line, not the streaming `JARGS` array — anti-correlated with what they name. T10b's `--follow` assertion is anchored on `notail=1`. T8's `flock -n` grep reads `$CI` (3 other matches) not `$UNITBLK`. C12's `--no-archive` is satisfied by the probe's own header prose. | test-design |
| F-28 | Stale-claim sweep gaps: `ADR-096:575` still says "the **isolated** Better Stack Logs source 2457081"; `ADR-172:76` and `model.c4:301` still assert "**every** host-side emitter reaches this source through a Vector agent that redacts" — which this PR falsifies, and `model.c4:301` is where the PII-safety inference lives. One block got a supersede note while its peer did not. | code-quality, architecture |
| F-29 | Replicated literals with no parity gate across the emit/readback seam: the envelope prefix has 6 copies, the four evidence classes 4–5 each, `zotregistry.dev/zot/v2/pkg/api` 6 (with **no** producer-side pin — it appears only in a comment). Editing the prefix silently yields `delivered_but_silent`, indistinguishable from a dead shipper. | code-quality |
| F-30 | Prose volume: 66% of +3392 is comments/docs, with 5 rationales each restated in 4–9 artifacts. ADR-184 should own them; the rest point at it. ~590 LOC reducible. | code-simplicity |

## OWED — P3 (see reports)
Unvalidated `post_fail` interpolated **before** the free-text `zot_last_err` (breaking that field's
stated last-position invariant); state-file counters read into `$(( ))` with no digit guard (one
value wedges `emit_drops` **permanently**, drop accounting silently dead, probe PASSes); no `fsync`
before rename; reporter claims `post_fail=0` on mere file readability; `shipped_cum` / state
`boot_id` / `seq` / `cum` have no reader; `-1` age is a second encoding of `last_ok_epoch=0` and a
backward clock step can emit a colliding `-1`; probe floor unguarded upward (any window <12 min can
never PASS); `WINDOW`/`WINDOW_MIN` independently overridable with nothing keeping them consistent;
`redact()` rule 2 targets a shape zot does not emit; `shape_leaks` scans for classes the diff argues
cannot reach this channel; layer citation may be **3** not 5; runbook's "same `pii_scrub_*` as every
other source" is now false; `data-protection-disclosure.md` §2.3(m) describes Vector as the
mechanism for source 2457081; journald restart ordered *after* the zot launch, losing startup lines;
reason taxonomy documented in a GitHub issue rather than the repo, with 6 of 11 undocumented and an
11th (`query_tool_missing`) in no prose list; `disk-monitoring.md` has no cross-link.

## Open design question (`code-simplicity`, rated P1-as-a-question)
Fold the shipper into the **existing 5-minute cron** instead of a daemon. That deletes the unit, §4,
§5, the cursor protocol, the cross-process state channel, window bookkeeping, and ~45 assertions
(~230 LOC), because a cron one-shot is precisely the sequential-invocation pattern `--cursor-file`
is documented for — as the ADR's own alternatives row concedes. Cost: ≤5 min latency. If the daemon
is kept, ADR-184's timer row must state the real trade (seconds-latency vs the host's first
always-on unit on the host that darks every deploy), which it currently does not.

## Verified sound (on the record, so a future pass does not re-litigate)
The Vector payload-destruction mechanism (`vector.toml:298` confirmed); all three legs of the pepper
retraction; the `redact()`-before-`sanitize()` ordering; the measured-not-inferred log shape; the
positive host-isolated discriminator and the rejection of the fail-open negation; C9/C9b's
false-green refusal against today's real production state; the FAIL arm's counts-only discipline; the
zero-Terraform reasoning (verified against the dispatch allow-set); the C4 no-duplicate/sibling
coherence and the append-don't-substitute ADR-172 amendment; `user_data` headroom (11,728/32,768);
`hr-no-ssh-fallback-in-runbooks`; CI registration in the correct file; the `${VAR:?}` ban; and the
reporter↔shipper coupling's direction and sentinels.
