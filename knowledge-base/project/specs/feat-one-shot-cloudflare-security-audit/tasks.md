# Tasks: Cloudflare Security Audit for soleur.ai

## Phase 1: Setup and Authentication

- [x] 1.1 Authenticate with Cloudflare MCP via `mcp__plugin_soleur_cloudflare__authenticate`
- [x] 1.2 Verify MCP connectivity by listing zones via `search` + `execute`
- [x] 1.3 Confirm `soleur.ai` zone is discoverable and note zone ID
- [x] 1.4 Verify CLI tools available: `dig`, `openssl`, `curl`
- [x] 1.5 Verify MCP OAuth scope includes required permissions (Zone:Read, DNS:Read, SSL:Read, Firewall:Read, Access:Read, Account Settings:Read, Notifications:Read)

## Phase 2: DNS Record Audit

- [x] 2.1 Retrieve all DNS records via MCP `execute`
- [x] 2.2 Cross-reference MCP results with `apps/web-platform/infra/dns.tf` records
- [x] 2.3 Check for orphaned records (in Cloudflare but not Terraform)
- [x] 2.4 Verify proxy status on all records (web-serving proxied, mail unproxied)
- [x] 2.5 Verify `api.soleur.ai` is unproxied (Supabase requirement)
- [x] 2.6 Audit email authentication chain: SPF, DKIM, DMARC records
- [x] 2.7 Verify DMARC policy is `p=quarantine` or `p=reject`, not `p=none`
- [x] 2.8 Verify SPF records use `-all` or `~all`, not `+all`
- [x] 2.9 Check for dangling CNAMEs and wildcard records
- [x] 2.10 Verify no records use `name = "@"` (Terraform drift issue)
- [x] 2.11 Check CAA records via `dig CAA soleur.ai` (auto-managed, invisible in dashboard)
- [x] 2.12 CLI verification: `dig` commands for key records
- [x] 2.13 Report DNS findings inline (severity-categorized)

## Phase 3: SSL/TLS Certificate Audit

- [x] 3.1 Retrieve SSL/TLS mode via MCP (expect Full Strict)
- [x] 3.2 Check if zone uses Automatic SSL/TLS mode vs manual mode
- [x] 3.3 Check "Always Use HTTPS" setting
- [x] 3.4 Check HSTS configuration (max-age, includeSubDomains, preload)
- [x] 3.5 Check minimum TLS version (expect 1.2+)
- [x] 3.6 Check TLS 1.3 support
- [x] 3.7 Check Opportunistic Encryption and Automatic HTTPS Rewrites
- [x] 3.8 Check Certificate Transparency Monitoring
- [x] 3.9 Verify origin certificate validity
- [x] 3.10 CLI verification: `openssl s_client` for cert chains on key domains
- [x] 3.11 CLI verification: `curl -sI` for security headers
- [x] 3.12 Check for double HSTS headers (Cloudflare + app)
- [x] 3.13 Report SSL/TLS findings inline

## Phase 4: Cloudflare Access / Zero Trust Audit

- [x] 4.1 List all Access applications via MCP
- [x] 4.2 Verify deploy webhook Access application configuration
- [x] 4.3 Check Access policy: only GitHub Actions service token has access
- [x] 4.4 Check service token expiry status (flag if within 60 days)
- [x] 4.5 Verify `expiring_service_token_alert` notification policy is active
- [x] 4.6 Review tunnel configuration and routes
- [x] 4.7 Verify catch-all rule returns 404
- [x] 4.8 Check for stale/orphaned Access applications
- [x] 4.9 Verify tunnel health and connection status
- [x] 4.10 Cross-reference with `apps/web-platform/infra/tunnel.tf`
- [x] 4.11 Verify `non_identity` decision type and 24h session duration
- [x] 4.12 Report Access/Zero Trust findings inline

## Phase 5: WAF and Security Features Audit

- [x] 5.1 Check WAF status (availability per plan tier)
- [x] 5.2 Review WAF managed rules (Cloudflare Managed Ruleset + OWASP Core Ruleset)
- [x] 5.3 Check Bot Fight Mode status -- expected OFF (intentional, document compensating controls)
- [x] 5.4 Check Browser Integrity Check
- [x] 5.5 Review Security Level setting
- [x] 5.6 Check rate limiting rules
- [x] 5.7 Categorize the 257 detected threats via Security Analytics (type, source, target paths)
- [x] 5.8 Check Under Attack Mode status
- [x] 5.9 Check Scrape Shield settings
- [x] 5.10 Check User Agent Blocking rules
- [x] 5.11 Review Cloudflare Audit Logs for unauthorized changes (last 30 days)
- [x] 5.12 Report WAF findings inline

## Phase 6: DNSSEC Audit

- [x] 6.1 Check DNSSEC status via MCP
- [x] 6.2 If enabled: verify DS record at registrar
- [x] 6.3 CLI verification: `dig +dnssec soleur.ai`
- [x] 6.4 CLI verification: `dig DS soleur.ai @<parent-ns>`
- [x] 6.5 Report DNSSEC findings inline

## Phase 7: HTTP Security Headers Audit

- [x] 7.1 Check CSP, X-Frame-Options, X-Content-Type-Options headers
- [x] 7.2 Check Referrer-Policy, Permissions-Policy, COOP, CORP headers
- [x] 7.3 Compare headers across `soleur.ai`, `app.soleur.ai`, docs site
- [x] 7.4 Check for Cloudflare header conflicts (double HSTS, CSP interference from Rocket Loader/Email Obfuscation)
- [x] 7.5 Report header findings inline

## Phase 8: Remediation

- [x] 8.1 Prioritize findings: Critical > High > Medium > Low
- [x] 8.2 Apply Cloudflare-side fixes via MCP ONE AT A TIME with CLI verification after each
- [x] 8.3 Update `.tf` files for Terraform-managed resource fixes
- [x] 8.4 Run `terraform validate` and `terraform fmt` on any `.tf` changes (use v4 naming)
- [x] 8.5 Create GitHub issues for deferred/longer-term remediations
- [x] 8.6 CLI verification of all applied fixes
- [x] 8.7 Final summary of audit results (inline only -- never persist to files)
