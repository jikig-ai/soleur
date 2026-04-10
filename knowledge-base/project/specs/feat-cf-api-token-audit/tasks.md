# Tasks: Expand CF API Token Permissions for Security Monitoring

Issue: #1837

## Phase 1: Create Cloudflare API Token

- [ ] 1.1 Open Cloudflare dashboard API tokens page via Playwright MCP
- [ ] 1.2 Create custom token named `soleur-security-audit`
- [ ] 1.3 Add Zone permissions: Zone Settings Read, DNS Read, SSL and Certificates Read, Firewall Services Read
- [ ] 1.4 Add Account permissions: Access Read, Account Settings Read, Notifications Read, Audit Logs Read
- [ ] 1.5 Set zone resources scope (all zones or specific zones)
- [ ] 1.6 Create token and copy the value
- [ ] 1.7 Verify token via API: `curl -H "Authorization: Bearer <token>" https://api.cloudflare.com/client/v4/user/tokens/verify`
- [ ] 1.8 Close browser via `browser_close`

## Phase 2: Store in Doppler

- [ ] 2.1 Store token in Doppler `dev` config as `CF_API_TOKEN_AUDIT`
- [ ] 2.2 Verify retrieval: `doppler secrets get CF_API_TOKEN_AUDIT -p soleur -c dev --plain`
- [ ] 2.3 Check if token has expiry date; if so, note for Phase 4

## Phase 3: Update infra-security Agent

- [ ] 3.1 Read `plugins/soleur/agents/engineering/infra/infra-security.md`
- [ ] 3.2 Add API-token fallback section to the Audit Protocol
  - [ ] 3.2.1 Document `CF_API_TOKEN_AUDIT` environment variable
  - [ ] 3.2.2 Add curl-based check commands for each permission category
  - [ ] 3.2.3 Document the fallback chain: MCP -> API token -> CLI-only
- [ ] 3.3 Run markdownlint on the modified file

## Phase 4: Verification

- [ ] 4.1 Test zone settings read: `GET /zones/<zone_id>/settings`
- [ ] 4.2 Test DNS records read: `GET /zones/<zone_id>/dns_records`
- [ ] 4.3 Test SSL certificates read: `GET /zones/<zone_id>/ssl/certificate_packs`
- [ ] 4.4 Test firewall rules read: `GET /zones/<zone_id>/firewall/rules`
- [ ] 4.5 Test account settings read: `GET /accounts/<account_id>/`
- [ ] 4.6 Test audit logs read: `GET /accounts/<account_id>/audit_logs`
- [ ] 4.7 Test notifications read: `GET /accounts/<account_id>/alerting/v3/policies`
- [ ] 4.8 Test write rejection: `PATCH /zones/<zone_id>/settings` returns 403
- [ ] 4.9 Verify existing `CF_API_TOKEN` still works for Terraform operations
- [ ] 4.10 If token has expiry, add to `scheduled-cf-token-expiry-check.yml` scope or create tracking issue
