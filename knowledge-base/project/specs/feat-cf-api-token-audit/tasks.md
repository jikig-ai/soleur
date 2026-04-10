# Tasks: Expand CF API Token Permissions for Security Monitoring

Issue: #1837

## Known Identifiers

- Account: <Jean.deruelle@jikigai.com> (`4d5ba6f096b2686fbdd404167dd4e125`)
- Zone: soleur.ai (`5af02a2f394e9ba6e0ea23c381a26b67`)

## Phase 1: Create Cloudflare API Token

- [ ] 1.0 Pre-check: test `POST /user/tokens` via MCP (if succeeds, use API path instead of Playwright)
- [ ] 1.1 Open Cloudflare dashboard API tokens page via Playwright MCP (`https://dash.cloudflare.com/profile/api-tokens`)
- [ ] 1.2 Create custom token named `soleur-security-audit`
- [ ] 1.3 Add Zone permissions: Zone Settings Read, DNS Read, SSL and Certificates Read, Firewall Services Read
- [ ] 1.4 Add Account permissions: Access Read, Account Settings Read, Notifications Read, Audit Logs Read
- [ ] 1.5 Set zone resources: Specific zone > soleur.ai
- [ ] 1.6 Do NOT set expiry (permanent token) or IP restrictions
- [ ] 1.7 Create token and copy the value (shown only once)
- [ ] 1.8 Verify token via API: `curl -H "Authorization: Bearer <token>" https://api.cloudflare.com/client/v4/user/tokens/verify`
- [ ] 1.9 Close browser via `browser_close`

## Phase 2: Store in Doppler

- [ ] 2.1 Store token in Doppler `dev` config: `doppler secrets set CF_API_TOKEN_AUDIT=<value> -p soleur -c dev`
- [ ] 2.2 Verify retrieval: `doppler secrets get CF_API_TOKEN_AUDIT -p soleur -c dev --plain | head -c 20`

## Phase 3: Update infra-security Agent

- [ ] 3.1 Read `plugins/soleur/agents/engineering/infra/infra-security.md`
- [ ] 3.2 Add API-token fallback section to the Audit Protocol
  - [ ] 3.2.1 Document `CF_API_TOKEN_AUDIT` environment variable and when to use it
  - [ ] 3.2.2 Add curl-based check commands for each permission category with exact endpoints
  - [ ] 3.2.3 Document the fallback chain: MCP -> API token -> CLI-only
  - [ ] 3.2.4 Note which endpoints may require paid plan (WAF rules, custom rulesets)
- [ ] 3.3 Run markdownlint on the modified file

## Phase 4: Verification

- [ ] 4.1 Test token verify: `GET /user/tokens/verify` returns `status: active`
- [ ] 4.2 Test zone listing: `GET /zones?account.id=4d5ba6f096b2686fbdd404167dd4e125` returns soleur.ai
- [ ] 4.3 Test zone settings read: `GET /zones/5af02a2f394e9ba6e0ea23c381a26b67/settings/ssl`
- [ ] 4.4 Test DNS records read: `GET /zones/5af02a2f394e9ba6e0ea23c381a26b67/dns_records?per_page=1`
- [ ] 4.5 Test SSL certificates read: `GET /zones/5af02a2f394e9ba6e0ea23c381a26b67/ssl/certificate_packs`
- [ ] 4.6 Test firewall rules read: `GET /zones/5af02a2f394e9ba6e0ea23c381a26b67/firewall/rules`
- [ ] 4.7 Test account settings read: `GET /accounts/4d5ba6f096b2686fbdd404167dd4e125/`
- [ ] 4.8 Test audit logs read: `GET /accounts/4d5ba6f096b2686fbdd404167dd4e125/audit_logs?per_page=1`
- [ ] 4.9 Test notifications read: `GET /accounts/4d5ba6f096b2686fbdd404167dd4e125/alerting/v3/policies`
- [ ] 4.10 Test write rejection: `PATCH /zones/5af02a2f394e9ba6e0ea23c381a26b67/settings/ssl` returns error
- [ ] 4.11 Verify existing `CF_API_TOKEN` still active: `GET /user/tokens/verify`
