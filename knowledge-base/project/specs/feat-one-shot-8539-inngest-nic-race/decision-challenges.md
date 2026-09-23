# Decision challenges: feat-one-shot-8539-inngest-nic-race

Plan-review taste findings that the headless planning run did NOT apply. The plan's own choice
stands until someone decides otherwise. Recorded for `ship` to render.

## T1: keep the new `inngest_private_ip` template var (code-simplicity #3)

- **Challenge:** drop the var. Hardcode `10.0.1.40` at the call site, as the existing `net-health`
  diag does, and add one test assert that the literal equals `local.inngest_private_ip`. That
  saves four render-site edits.
- **Plan's choice:** keep the var. ADR-115 makes single-sourcing the private IP "part of the
  decision, not an implementation detail". A var gives one definition by construction; a test
  gives it only by check. The ripple is four stub maps, each a one-line addition.
- **Cost of being wrong:** four extra one-line edits and one AC.

## T2: keep `networkctl reload` as its own early runcmd item (code-simplicity #4)

- **Challenge:** move the reload into the helper's first line, which removes one runcmd item and
  two Guard 1 rows.
- **Plan's choice:** keep it separate and early. The reload is what makes the fallback live for
  the rest of the boot, whether or not the helper runs. The helper stays a pure reporter that
  writes nothing and reloads nothing, which keeps its "never mutates network state" contract
  checkable from the stub call log.
- **Cost of being wrong:** one runcmd item and two guard rows.

## T3: keep the harness rows and the token-vs-construct row (DHH #5, code-simplicity #5)

- **Challenge:** drop the harness rows, Guard 1 rows 4, 8 and 10, and the must-PASS inputs.
- **Plan's choice:** keep them. The plan skill's Guard Contract gate (Phase 2.12) requires both a
  second-member row and harness rows. Row 8 is the census principle from the sharp-edges
  catalogue; it now matches private-net ACTIONS only (Kieran P0-2, DHH #1). The token-vs-construct
  row was later dropped at deepen-plan as unfailable (test-design review), so this challenge is
  partly conceded.
- **Cost of being wrong:** about six extra mutation rows in an existing battery.

## T4: the `Spec lacks valid lane:` line in the plan body (DHH #8)

- **Challenge:** delete it as pipeline leftover.
- **Plan's choice:** keep it. The plan skill requires this note when no spec carries `lane:`.

## T5: dedicated post-merge replace vs ride-along delivery (deepen-plan Phase 4.55)

- **Challenge (zero-downtime-first):** do not replace the host just to deliver this change. The
  running host already has its NIC, and the fix only matters on the next fresh boot. Let the new
  `user_data` ride along with the next replace that is needed anyway. That means zero scheduler
  outage.
- **Stated direction (default):** the orchestrator performs a dedicated operator-approved
  `inngest-host-replace` after merge, then `op=resume`.
- **Trade:** the dedicated replace costs one scheduler outage window (about 15 min). It buys
  immediate production verification of the good-case claim (`by=10-netplan-*`) and removes the
  standing pending-replace drift. Ride-along costs nothing now, but leaves the drift and the
  unverified claim until the next replace.

## T6: security-review hardening not adopted (deepen-plan)

- **Challenge (security-sentinel P2):**
  - (a) Narrow the fallback match to `enp*` names or the Hetzner MAC prefix.
  - (b) Add an interface-scoped `iifname "eth0" … drop` before the nftables `:8288/:8289` accept,
    and set `rp_filter=1`.
- **Plan's choice:** neither is adopted.
  - (a) would bind the fix to a naming scheme observed on one NIC (`enp7s0`) and could miss a
    differently-named private NIC, which is the failure being fixed. `Driver=virtio_net` +
    `Name=!eth0` already excludes the public NIC, docker and bridges.
  - (b) hardens a pre-existing source-address rule. It is independent of this change: the
    fallback only configures a link that Hetzner attached. It deserves its own change, with
    nftables tests.
- **Cost of being wrong:** a spoofed web-host source address on an unexpected private link could
  reach the unauthenticated control API. This requires an attacker already on the Hetzner private
  L2.
