# Tasks: Cloudflare Security Audit for soleur.ai

## Phase 1: Setup and Authentication

- [ ] 1.1 Authenticate with Cloudflare MCP via `mcp__plugin_soleur_cloudflare__authenticate`
- [ ] 1.2 Verify MCP connectivity by listing zones
- [ ] 1.3 Confirm `soleur.ai` zone is discoverable and note zone ID
- [ ] 1.4 Verify CLI tools available: `dig`, `openssl`, `curl`

## Phase 2: DNS Record Audit

- [ ] 2.1 Retrieve all DNS records via MCP `execute`
- [ ] 2.2 Cross-reference MCP results with `apps/web-platform/infra/dns.tf` records
- [ ] 2.3 Check for orphaned records (in Cloudflare but not Terraform)
- [ ] 2.4 Verify proxy status on all records (web-serving proxied, mail unproxied)
- [ ] 2.5 Verify `api.soleur.ai` is unproxied (Supabase requirement)
- [ ] 2.6 Audit email authentication chain: SPF, DKIM, DMARC records
- [ ] 2.7 Check for dangling CNAMEs and wildcard records
- [ ] 2.8 CLI verification: `dig` commands for key records
- [ ] 2.9 Report DNS findings inline (severity-categorized)

## Phase 3: SSL/TLS Certificate Audit

- [ ] 3.1 Retrieve SSL/TLS mode via MCP (expect Full Strict)
- [ ] 3.2 Check "Always Use HTTPS" setting
- [ ] 3.3 Check HSTS configuration (max-age, includeSubDomains, preload)
- [ ] 3.4 Check minimum TLS version (expect 1.2+)
- [ ] 3.5 Check TLS 1.3 support
- [ ] 3.6 Check Opportunistic Encryption and Automatic HTTPS Rewrites
- [ ] 3.7 Check Certificate Transparency Monitoring
- [ ] 3.8 CLI verification: `openssl s_client` for cert chains on key domains
- [ ] 3.9 CLI verification: `curl -sI` for security headers
- [ ] 3.10 Report SSL/TLS findings inline

## Phase 4: Cloudflare Access / Zero Trust Audit

- [ ] 4.1 List all Access applications via MCP
- [ ] 4.2 Verify deploy webhook Access application configuration
- [ ] 4.3 Check Access policy: only GitHub Actions service token has access
- [ ] 4.4 Check service token expiry status
- [ ] 4.5 Verify `expiring_service_token_alert` notification policy is active
- [ ] 4.6 Review tunnel configuration and routes
- [ ] 4.7 Verify catch-all rule returns 404
- [ ] 4.8 Check for stale/orphaned Access applications
- [ ] 4.9 Cross-reference with `apps/web-platform/infra/tunnel.tf`
- [ ] 4.10 Report Access/Zero Trust findings inline

## Phase 5: WAF and Security Features Audit

- [ ] 5.1 Check WAF status (availability per plan tier)
- [ ] 5.2 Review WAF managed rules configuration
- [ ] 5.3 Check Bot Fight Mode status
- [ ] 5.4 Check Browser Integrity Check
- [ ] 5.5 Review Security Level setting
- [ ] 5.6 Check rate limiting rules
- [ ] 5.7 Categorize the 257 detected threats by type
- [ ] 5.8 Check Under Attack Mode status
- [ ] 5.9 Check Scrape Shield settings
- [ ] 5.10 Report WAF findings inline

## Phase 6: DNSSEC Audit

- [ ] 6.1 Check DNSSEC status via MCP
- [ ] 6.2 If enabled: verify DS record at registrar
- [ ] 6.3 CLI verification: `dig +dnssec soleur.ai`
- [ ] 6.4 Report DNSSEC findings inline

## Phase 7: HTTP Security Headers Audit

- [ ] 7.1 Check CSP, X-Frame-Options, X-Content-Type-Options headers
- [ ] 7.2 Check Referrer-Policy and Permissions-Policy headers
- [ ] 7.3 Compare headers across `soleur.ai`, `app.soleur.ai`, docs site
- [ ] 7.4 Report header findings inline

## Phase 8: Remediation

- [ ] 8.1 Apply Cloudflare-side fixes via MCP for critical/high findings
- [ ] 8.2 Update `.tf` files for Terraform-managed resource fixes
- [ ] 8.3 Run `terraform validate` and `terraform fmt` on any `.tf` changes
- [ ] 8.4 Create GitHub issues for deferred/longer-term remediations
- [ ] 8.5 CLI verification of all applied fixes
- [ ] 8.6 Final summary of audit results (inline only)
