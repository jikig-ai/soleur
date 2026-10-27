# Decision Challenges — feat-one-shot-cloudflared-emudhra-upgrade

Headless pipeline run (Devin CLI, no subagent/AskUserQuestion channel). Per
technical-ruling-delegation: technical rulings that would go to
`soleur:engineering:cto` are recorded `pending - assumed: <default>` — no agent
tool exists in this harness.

| Item | Class | Ruling |
|------|-------|--------|
| Prod path for web-1's vulnerable connector: rule-compliant connector migration vs amending hr-prod-host-config-change-immutable-redeploy for an in-place apt patch | technical | pending - assumed: migration (web-1→web-2). The rule forbids in-place edits "even a one-liner"; a compliant path exists, so no rule amendment. If a CTO/agent session disagrees, the alternative is an ADR + rule-corpus amendment permitting CVE-class single-package upgrades convergent with declared cloud-init state |
| Connector target host: web-2 (cattle standby) vs inngest (co-located, pending replace anyway) vs dedicated new host | technical | pending - assumed: web-2 — the existing web-host connector machinery (`%{ if web_tunnel_connector }` block, NIC gate, readiness gate) plus the purpose-built `web-host-replace` dispatch make it the minimal-diff, already-gated target; inngest co-location adds a near-cap user_data block and couples tunnel uptime to inngest's replace cadence; a dedicated host has no birth dispatch and adds a monitored host class |
| Credential kill for web-1's live connector: `terraform apply -replace` of the tunnel vs token rotation (dashboard/API `PATCH tunnel_secret` + `DELETE /connections`) | technical | pending - assumed: `terraform -replace` — IaC-auditable, and every consumer resolves the tunnel by name/state not literal ID; rotation preserves the tunnel ID (less DNS churn) and is the documented fallback |
| Version pin: 2026.10.4 vs advisory-minimum 2026.10.2 | technical | pending - assumed: 2026.10.4 — latest patch (post-advisory fixes); floor remains 2026.10.2 in the census verdict |
| cloud-init install mechanism: pinned `.deb` + sha256 vs keep unpinned apt-latest | technical | pending - assumed: pinned `.deb` — deterministic, fails closed, mirrors the adjacent webhook install; unpinned apt is what produced the 7-month-stale 2026.3.0 state |
| Acceptable management-plane dark window during migration (tunnel dead O1→O2, ~job duration) | operator (irreversible/production-mutating authorization) | pending - assumed: acceptable — `app.soleur.ai` unaffected (direct A record); operator picks dispatch timing and gives per-command go-ahead per hr-menu-option-ack |
| Operator-side dev machines (macOS/Linux) running cloudflared | operator (scope) | pending - assumed: ship-message action item (macOS floor 2026.10.3); the repo cannot reach these hosts |

Status legend: `pending - assumed: X` = default taken by the headless run; a CTO
ruling supersedes it before the affected work starts.
