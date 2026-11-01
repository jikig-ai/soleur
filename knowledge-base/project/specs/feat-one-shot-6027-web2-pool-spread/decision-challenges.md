# Decision Challenges — feat-one-shot-6027-web2-pool-spread

Planning ran on the Devin CLI harness with no Task/subagent capability, so
`pending - assumed` placeholders are written per the technical-ruling-delegation
contract; the parent pipeline's technical-ruling gate resolves the pending rows
via a real `soleur:engineering:cto` spawn. Rows marked `resolved` were settled at
plan time by live evidence or ADR authority (cited inline). `soleur:ship` renders
this table into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Monitor probe semantics — `type=https`/null-port (probes origin:443/TLS) vs `type=http`/`port=80` vs `type=tcp` | technical | resolved 2026-11-01 by live evidence: CF pool-health API shows origin 135.181.45.178 `healthy:false`/`TCP connection failed`; cloud-init.yml:808 publishes `0.0.0.0:80:3000` only; Flexible-SSL config rule makes HTTP:80 the real CF→origin path. Ruled: `type="http"`, `port=80`, `/health`, `expected_codes="200"` (ADR-068 §(b) reachability-only; "200" retained over the ADR's "2xx" — stricter, same semantics) |
| web-2 origin weight — brief asked `weight=1` (immediate serving) | technical | resolved by authority + live gate state: ADR-068 §(b) prescribes weight 0 (drained) until GA; lb-weight-gate.sh top-guard passes weight==0 && not-in-rotation; `GIT_DATA_STORE_ENABLED=false`, `GIT_DATA_LUKS_CUTOVER_AT` absent, `SOLEUR_PROXY_BIND` absent (measured 2026-11-01) → flip NOT authorized. Ruled: `weight=0` in this PR; 0→1 is the #6027 window act |
| web-2 DC placement fork (brief open q2: cross-DC spread vs move web-2 to web-1's DC) | technical | resolved — stale premise: current web-2 was born hel1 2026-07-24 (ADR-143/#6459, `var.web_hosts` default `location="hel1"`) INSIDE `web_spread`; the 2026-07-13 hel1→fsn1 move was the retired warm standby (#6538). No DC decision exists; stale server.tf:362-366 comment corrected in the window PR |
| Steering shape — LB `steering_policy` ("off"→"random"/"geo") vs pool `origin_steering.policy` | technical | pending - assumed: LB `steering_policy` stays `"off"` (pool-level knob, one default pool — the brief's fork targets the wrong layer); declare `origin_steering { policy = "random" }` on `cloudflare_load_balancer_pool.web_1` (provider default made explicit; `hash` rejected — silent session affinity while `session_affinity="none"` and serving is lease-routed by the relay) |
| Apply-arm partitioning for GA-trio updates — one combined `ga-update` arm vs purpose-scoped arms | technical | pending - assumed: TWO arms — `ga-monitor-fix` (update monitor only; deployable immediately, no flip authorization) + `ga-pool-update` (update pool+LB; `mode` input drain/serve; `serve` runs `lb-weight-gate-with-marker.sh` fail-closed). Rationale: per-arm confirm literals are the repo convention and the monitor fix must not inherit the pooling arm's authorization tier |
| Land drained-shape config pre-authorization vs defer everything to the window PR | technical | pending - assumed: pre-stage now — committed weight-0 config is inert (GA trio are `-target`-excluded from routine apply; the new arms are confirm+environment gated), the monitor fix is deployable immediately, and deferring it to the window would leave a KNOWN-dead health signal in place for an unbounded cutover wait |
| Brand-survival threshold → `requires_cpo_signoff` | operator (scope) | pending - assumed: `single-user incident` carried from the #11181 spec's `brand_survival_threshold`; CPO sign-off required at plan time before `soleur:work` — flag renders in the PR body for the parent's gate |
| Window PR scope — `ignore_changes=[placement_group_id]` removal + weight 0→1 + `[skip-web-platform-apply]` merge + vector-redeliver allow-set update | technical | resolved by #6027's ordered sequence + server.tf:614's own instruction ("REMOVE this entry in the GA maintenance-window PR as its FIRST diff"): these ride the window PR, not this one — merging the removal now would trip `reboot_updates` on every routine apply until the window |
