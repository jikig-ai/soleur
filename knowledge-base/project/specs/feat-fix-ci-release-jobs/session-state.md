# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/fix-ci-release-jobs/knowledge-base/project/plans/2026-03-21-fix-ci-release-deploy-failures-plan.md
- Status: complete

### Errors
None

### Decisions
- Async webhook is the recommended timeout fix. Cloudflare's 120s Proxy Read Timeout is not configurable on non-Enterprise plans, eliminating the "increase timeout" option. adnanh/webhook natively supports fire-and-forget via `include-command-output-in-response: false` + `success-http-response-code: 202`, requiring zero external tools.
- Separate tunnel per server for telegram-bridge. The telegram-bridge runs on a different Hetzner server than web-platform, so it needs its own Cloudflare Tunnel (`deploy-bridge.soleur.ai`) rather than routing through the web-platform tunnel. This preserves server isolation and aligns with the separate Terraform roots architecture.
- Manual provisioning is required alongside Terraform. cloud-init only runs at server creation, and `lifecycle { ignore_changes = [user_data] }` means Terraform won't reprovision running servers. Both cloud-init.yml (for future rebuilds) and manual SSH commands (for current servers) are needed.
- Five distinct failure modes identified, not one. The failures span Bot Fight Mode (HTTP 403), ci-deploy.sh execution errors (HTTP 500), Cloudflare edge timeout (HTTP 524), wrong-server routing, and missing webhook infrastructure -- each requiring a separate fix.
- Terraform provider v4 naming must be validated. The project pins `cloudflare ~> 4.0` but research agents and docs default to v5 naming (`tunnel_secret` vs `secret`, `ingress {}` vs `ingress_rule {}`). `terraform validate` after every new resource is mandatory.

### Components Invoked
- `skill: soleur:plan` -- initial plan creation with local research
- `skill: soleur:deepen-plan` -- plan enhancement with external research
- `WebSearch` -- Cloudflare timeout limits, adnanh/webhook async patterns, tunnel config
- `WebFetch` -- Cloudflare connection limits docs, error 524 docs, webhook hook configuration, adnanh/webhook GitHub issues
- `gh run list` / `gh run view` -- CI failure log analysis (10+ runs inspected across both workflows)
- `gh issue view` -- existing issue #968 context
- Local file reads: 6 learnings, 2 cloud-init.yml, 3 workflow files, reusable-release.yml, ci-deploy.sh, ci-deploy.test.sh, tunnel.tf, server.tf (both apps), constitution.md, AGENTS.md, brainstorm, spec
