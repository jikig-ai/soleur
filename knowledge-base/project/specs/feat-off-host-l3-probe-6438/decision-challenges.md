# Decision Challenges — feat-off-host-l3-probe-6438

Recorded during /work (headless). Surfaced by /ship into the PR body + an `action-required` issue
for operator visibility.

## 1. Phase A5 (future-host cloud-init bake + arm-gate `var.web_hosts` iteration): DEFERRED to #6459

- **Class:** scope — deviation from the operator-confirmed "full bundle" direction (tasks.md A5).
- **Plan said:** bake the B/C probe scripts + §3 guard into `cloud-init.yml` so a future fresh host
  (#6459 active-active-N) self-arms them at boot; make the arm gate iterate `var.web_hosts`.
- **Decision at /work:** DEFER A5 to a #6459-coupled follow-up. Ship the LIVE path only (the SSH
  `terraform_data` provisioner arms web-1; the measured-beat arm gate hardcodes `web-1`, which is
  correct for the single-host fleet).
- **Why (weighed against target-user impact):**
  1. **No current value.** A5's value materializes only when a SECOND web host exists. web-2 retired
     2026-07-17 (#6538); the fleet is single-host and #6459 is deferred. There is no host that A5
     would arm today.
  2. **The safety net already exists.** `apply-web-platform-infra.yml:450-456` HALTs any per-PR
     apply that would birth a host — so #6459 cannot add a host without deliberate arm-gate + probe
     coverage. A missing cloud-init bake is caught there, by construction, not silently.
  3. **The plan itself frames A5 as a "#6459 dependency"** (Phase A5 bullet: "the SSH provisioner is
     the web-1-unrebuildable *exception*, not the only path … Tracked as a #6459 dependency").
  4. **Risk asymmetry.** The cloud-init render is the highest-escaping-risk surface in this repo
     (templatefile `$${…}` / `%{` scanner + the 32 KB user_data cap + `cloud-init schema` render
     validation). A bug there breaks the LIVE fresh-host provisioning path. Shipping that risk for
     hosts that do not exist is a net loss under `hr-weigh-every-decision-against-target-user-impact`.
- **What still ships (the brand-critical core is NOT deferred):** the zot consumer probe (#6438 §1),
  the §3 NIC self-report (detect+emit+alarm, no reboot), git-data reachability (#6548), the
  measured-beat arm gate (the #6400-shape prevention), all delivered to web-1 and armed by a real
  measured beat. #6438 §1/§3 and #6548 are resolved for the current (single-host) fleet.
- **If the operator wants A5 now:** it is a self-contained follow-up (bake the three standalone
  scripts + six unit files into `cloud-init.yml` via `indent()`-verbatim templatefile-variable
  injection — the scripts are already env-driven so no per-`${VAR}` escaping is needed — plus a
  runcmd env-file + `enable --now` block, and change the arm gate's three hardcoded `web-1` calls to
  a `for host in $(… var.web_hosts)` loop). Tracked as the follow-up issue below.
