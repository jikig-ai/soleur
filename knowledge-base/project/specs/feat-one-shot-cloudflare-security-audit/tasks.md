# Tasks: Cloudflare Security Audit for soleur.ai

## Phase 1: Setup and Authentication

- [ ] 1.1 Authenticate with Cloudflare MCP via `mcp__plugin_soleur_cloudflare__authenticate`
- [ ] 1.2 Verify MCP connectivity by listing zones via `search` + `execute`
- [ ] 1.3 Confirm `soleur.ai` zone is discoverable and note zone ID
- [ ] 1.4 Verify CLI tools available: `dig`, `openssl`, `curl`
- [ ] 1.5 Verify MCP OAuth scope includes required permissions (Zone:Read, DNS:Read, SSL:Read, Firewall:Read, Access:Read, Account Settings:Read, Notifications:Read)

## Phase 2: DNS Record Audit

- [ ] 2.1 Retrieve all DNS records via MCP `execute`
- [ ] 2.2 Cross-reference MCP results with `apps/web-platform/infra/dns.tf` records
- [ ] 2.3 Check for orphaned records (in Cloudflare but not Terraform)
- [ ] 2.4 Verify proxy status on all records (web-serving proxied, mail unproxied)
- [ ] 2.5 Verify `api.soleur.ai` is unproxied (Supabase requirement)
- [ ] 2.6 Audit email authentication chain: SPF, DKIM, DMARC records
- [ ] 2.7 Verify DMARC policy is `p=quarantine` or `p=reject`, not `p=none`
- [ ] 2.8 Verify SPF records use `-all` or `~all`, not `+all`
- [ ] 2.9 Check for dangling CNAMEs and wildcard records
- [ ] 2.10 Verify no records use `name = "@"` (Terraform drift issue)
- [ ] 2.11 Check CAA records via `dig CAA soleur.ai` (auto-managed, invisible in dashboard)
- [ ] 2.12 CLI verification: `dig` commands for key records
- [ ] 2.13 Report DNS findings inline (severity-categorized)

## Phase 3: SSL/TLS Certificate Audit

- [ ] 3.1 Retrieve SSL/TLS mode via MCP (expect Full Strict)
- [ ] 3.2 Check if zone uses Automatic SSL/TLS mode vs manual mode
- [ ] 3.3 Check "Always Use HTTPS" setting
- [ ] 3.4 Check HSTS configuration (max-age, includeSubDomains, preload)
- [ ] 3.5 Check minimum TLS version (expect 1.2+)
- [ ] 3.6 Check TLS 1.3 support
- [ ] 3.7 Check Opportunistic Encryption and Automatic HTTPS Rewrites
- [ ] 3.8 Check Certificate Transparency Monitoring
- [ ] 3.9 Verify origin certificate validity
- [ ] 3.10 CLI verification: `openssl s_client` for cert chains on key domains
- [ ] 3.11 CLI verification: `curl -sI` for security headers
- [ ] 3.12 Check for double HSTS headers (Cloudflare + app)
- [ ] 3.13 Report SSL/TLS findings inline

## Phase 4: Cloudflare Access / Zero Trust Audit

- [ ] 4.1 List all Access applications via MCP
- [ ] 4.2 Verify deploy webhook Access application configuration
- [ ] 4.3 Check Access policy: only GitHub Actions service token has access
- [ ] 4.4 Check service token expiry status (flag if within 60 days)
- [ ] 4.5 Verify `expiring_service_token_alert` notification policy is active
- [ ] 4.6 Review tunnel configuration and routes
- [ ] 4.7 Verify catch-all rule returns 404
- [ ] 4.8 Check for stale/orphaned Access applications
- [ ] 4.9 Verify tunnel health and connection status
- [ ] 4.10 Cross-reference with `apps/web-platform/infra/tunnel.tf`
- [ ] 4.11 Verify `non_identity` decision type and 24h session duration
- [ ] 4.12 Report Access/Zero Trust findings inline

## Phase 5: WAF and Security Features Audit

- [ ] 5.1 Check WAF status (availability per plan tier)
- [ ] 5.2 Review WAF managed rules (Cloudflare Managed Ruleset + OWASP Core Ruleset)
- [ ] 5.3 Check Bot Fight Mode status -- expected OFF (intentional, document compensating controls)
- [ ] 5.4 Check Browser Integrity Check
- [ ] 5.5 Review Security Level setting
- [ ] 5.6 Check rate limiting rules
- [ ] 5.7 Categorize the 257 detected threats via Security Analytics (type, source, target paths)
- [ ] 5.8 Check Under Attack Mode status
- [ ] 5.9 Check Scrape Shield settings
- [ ] 5.10 Check User Agent Blocking rules
- [ ] 5.11 Review Cloudflare Audit Logs for unauthorized changes (last 30 days)
- [ ] 5.12 Report WAF findings inline

## Phase 6: DNSSEC Audit

- [ ] 6.1 Check DNSSEC status via MCP
- [ ] 6.2 If enabled: verify DS record at registrar
- [ ] 6.3 CLI verification: `dig +dnssec soleur.ai`
- [ ] 6.4 CLI verification: `dig DS soleur.ai @<parent-ns>`
- [ ] 6.5 Report DNSSEC findings inline

## Phase 7: HTTP Security Headers Audit

- [ ] 7.1 Check CSP, X-Frame-Options, X-Content-Type-Options headers
- [ ] 7.2 Check Referrer-Policy, Permissions-Policy, COOP, CORP headers
- [ ] 7.3 Compare headers across `soleur.ai`, `app.soleur.ai`, docs site
- [ ] 7.4 Check for Cloudflare header conflicts (double HSTS, CSP interference from Rocket Loader/Email Obfuscation)
- [ ] 7.5 Report header findings inline

## Phase 8: Remediation

- [ ] 8.1 Prioritize findings: Critical > High > Medium > Low
- [ ] 8.2 Apply Cloudflare-side fixes via MCP ONE AT A TIME with CLI verification after each
- [ ] 8.3 Update `.tf` files for Terraform-managed resource fixes
- [ ] 8.4 Run `terraform validate` and `terraform fmt` on any `.tf` changes (use v4 naming)
- [ ] 8.5 Create GitHub issues for deferred/longer-term remediations
- [ ] 8.6 CLI verification of all applied fixes
- [ ] 8.7 Final summary of audit results (inline only -- never persist to files)
