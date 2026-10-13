# Session state — feat-one-shot-9962-envfile-storm-class

## Phase
review — panel spawning at 2200469734

## Decisions
- Conditioned units: flip svc+timer, soleur-inngest-provision, heartbeat
  svc+timer, inngest-server, vector — all unprefixed-EnvironmentFile carriers
  on late-runcmd files with early-boot activation (census beyond the issue's
  named three, per write-boundary sweep).
- inngest-redis: deliberately loud (RequiresMountsFor is its designed signal).
- Needle: `Failed to start (inngest|vector|soleur-inngest)` name-group + `[="]UNIT` anchored scope (a bare `inngest` prefix is blind to `vector.service`/`soleur-inngest-provision.service` — journald text is unit-name-first) + BOOT_STAGE-row exclusion
  arm (doppler `_SYSTEMD_UNIT` field cannot launder).
- GuardA carrier drift is the sanctioned red window (precedent: #9944 →
  #10027); green returns on the next vinngest tag + pin bump.

## Fix round (panel of 8, 4 returned, 4 rate-limited)
- P2 needle blind to vector.service/soleur-inngest-provision.service → widened
  to (inngest|vector|soleur-inngest) on both arms; fixtures added.
- P2 embedded-journalctl FP (post-boot-health jl= embeds prior-life
  `systemd[N]: Failed to start` text) → BOOT_STAGE rows excluded pre-scope;
  fixture added.
- P3 inngest-server comment misattributed heartbeat (co-conditioned) → names
  inngest_consumer + tolerant probe; plan detector-set claim corrected
  (inngest_server_probe monitor still paused/feeder-less, #9703).
- P3 timer-skip stickiness documented (no re-evaluation until re-arm).
- Filed #10078: web-host probe/webhook/vector units — same class, out of scope.
- Inline lens coverage for rate-limited seats: mutation check (3 FAILs on
  condition removal), _boot_unit delimiter-collision check, sibling-needle
  census (clean — doc example only), no-history-of-deliberate-nonconditioning,
  carrier-set match.

## Fix round 2 (panel complete: 8/8 — retries returned after rate-limit reset)
- test-design P2: capture floor MIN=31 -> 36 (slack).
- git-history P2: pin set thinner than AC-1 -> set-identity + unprefixed +
  reset-line asserts for all heredoc units (_sec_body_vals), timer-vs-service
  equality, provision envfile-subset. Floors re-measured (451).
- test-design P3: unnegated-latch additive hole -> explicit G3 guard row.
- _boot_unit `.?` slack -> anchored `<<'d'$` (quote via -v q, \x27 not portable).
- server/heartbeat detector attribution rewritten (co-conditioned heartbeat is
  never a detector; names inngest_consumer + tolerant probe).
- BOOT_STAGE exclusion comment now names the bounded silence direction.
- All suites green post-round: inngest 451/451, capture 36/36, provision 162 C0
  + 83 rows + Tier B.
- Trailers: Reviewed-By-Soleur 8/8 + Reviewed-Fix-Round over 2200469734.
- Learning: learnings/bug-fixes/2026-10-11-conditioning-a-unit-....

## Errors
- `_sec_body` section matcher initially used exact `[Unit]` equality — missed
  the yaml-indented header; fixed indent-tolerant. Caught by suite RED.
- Timer condition first written into [Timer] section (inert lvalue) — moved to
  [Unit] before commit. Caught on self-review of the diff.

## Forwarded
- After merge: mint vinngest-v1.1.51 + run the pin-bump workflow so GuardA
  greens (same flow as v1.1.50/#10027). Carrier drift rows stay red meanwhile.
