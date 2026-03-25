# Tasks: feat-csp-header

## Phase 1: Setup

- [ ] 1.1 Compute SHA-256 hashes for the two inline scripts in `base.njk`
  - [ ] 1.1.1 Extract Plausible init script content (line 70 between `<script>` tags)
  - [ ] 1.1.2 Extract form handler script content (lines 119-168 between `<script>` tags)
  - [ ] 1.1.3 Compute SHA-256 hashes using `openssl dgst -sha256 -binary | openssl base64 -A`
  - [ ] 1.1.4 Record both hashes for use in CSP meta tag

## Phase 2: Core Implementation

- [ ] 2.1 Add CSP `<meta>` tag to `plugins/soleur/docs/_includes/base.njk`
  - [ ] 2.1.1 Insert `<meta http-equiv="Content-Security-Policy">` after existing meta tags, before `<base href="/">`
  - [ ] 2.1.2 Include directives: `default-src 'self'`, `script-src 'self' https://plausible.io 'sha256-<hash1>' 'sha256-<hash2>'`, `connect-src 'self' https://buttondown.com https://plausible.io`, `style-src 'self' 'unsafe-inline'`, `img-src 'self' data:`, `font-src 'self'`, `base-uri 'self'`, `form-action 'self' https://buttondown.com`, `object-src 'none'`
- [ ] 2.2 Create CSP validation script at `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh`
  - [ ] 2.2.1 Script extracts inline scripts from built `_site/index.html`
  - [ ] 2.2.2 Script computes SHA-256 hashes of extracted scripts
  - [ ] 2.2.3 Script extracts hash values from the CSP meta tag
  - [ ] 2.2.4 Script compares computed vs declared hashes and exits non-zero on mismatch
  - [ ] 2.2.5 Script follows shell conventions: `#!/usr/bin/env bash`, `set -euo pipefail`
- [ ] 2.3 Add CSP validation step to `.github/workflows/deploy-docs.yml`
  - [ ] 2.3.1 Add step after "Validate SEO" and before "Verify build output"
  - [ ] 2.3.2 Step runs: `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site`

## Phase 3: Testing

- [ ] 3.1 Build docs locally with `npx @11ty/eleventy`
- [ ] 3.2 Verify no CSP violations in browser console on index page
- [ ] 3.3 Verify no CSP violations on pricing page (waitlist forms, JSON-LD)
- [ ] 3.4 Verify Plausible analytics script loads (check Network tab)
- [ ] 3.5 Verify newsletter form fetch to Buttondown works
- [ ] 3.6 Verify waitlist form fetch to Buttondown works
- [ ] 3.7 Verify JSON-LD structured data blocks cause no CSP errors
- [ ] 3.8 Run CSP validation script against built output
- [ ] 3.9 Test hash mismatch detection: temporarily modify inline script, run validation, confirm failure
