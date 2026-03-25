# Tasks: feat-csp-header

## Phase 1: Setup

- [ ] 1.1 Compute SHA-256 hashes for the two inline scripts in `base.njk`
  - [ ] 1.1.1 Extract Plausible init script content (line 70, exact bytes between `<script>` and `</script>`)
  - [ ] 1.1.2 Extract form handler script content (lines 119-168, exact bytes between `<script>` and `</script>`)
  - [ ] 1.1.3 Compute SHA-256 hashes: `echo -n '<content>' | openssl dgst -sha256 -binary | openssl base64 -A`
  - [ ] 1.1.4 Verify hashes match by checking Chrome DevTools CSP violation messages if mismatched
  - [ ] 1.1.5 Record both hashes for use in CSP meta tag

## Phase 2: Core Implementation

- [ ] 2.1 Add CSP `<meta>` tag to `plugins/soleur/docs/_includes/base.njk`
  - [ ] 2.1.1 Insert `<meta http-equiv="Content-Security-Policy">` at line 23 (before JSON-LD `<script>` block, after Twitter meta tags) -- CSP only applies to content after the meta tag
  - [ ] 2.1.2 Include directives: `default-src 'self'`; `script-src 'self' https://plausible.io 'sha256-<hash1>' 'sha256-<hash2>'`; `connect-src 'self' https://buttondown.com https://plausible.io`; `style-src 'self' 'unsafe-inline'`; `img-src 'self' data:`; `font-src 'self'`; `base-uri 'self'`; `form-action 'self' https://buttondown.com`; `object-src 'none'`
  - [ ] 2.1.3 Verify meta tag does NOT contain `strict-dynamic`, `report-uri`, `report-to`, `frame-ancestors`, or `sandbox` (unsupported in meta tags)
- [ ] 2.2 Create CSP validation script at `plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh`
  - [ ] 2.2.1 Script follows shell conventions: `#!/usr/bin/env bash`, `set -euo pipefail`
  - [ ] 2.2.2 Script accepts `_site` directory as argument (same pattern as `validate-seo.sh`)
  - [ ] 2.2.3 Script extracts CSP meta tag from `_site/index.html`
  - [ ] 2.2.4 Script parses hash values from `script-src` directive
  - [ ] 2.2.5 Script extracts each inline `<script>` block (excluding `type="application/ld+json"`)
  - [ ] 2.2.6 Script computes SHA-256 hash of each extracted script
  - [ ] 2.2.7 Script verifies every computed hash has a matching entry in CSP
  - [ ] 2.2.8 Script verifies no orphan hashes in CSP (hashes that match no inline script)
  - [ ] 2.2.9 Script prints new hash values when mismatch detected (for developer convenience)
  - [ ] 2.2.10 Script exits non-zero on any mismatch or orphan
- [ ] 2.3 Add CSP validation step to `.github/workflows/deploy-docs.yml`
  - [ ] 2.3.1 Add step after "Validate SEO" and before "Verify build output"
  - [ ] 2.3.2 Step runs: `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site`

## Phase 3: Testing

- [ ] 3.1 Build docs locally with `npx @11ty/eleventy` (from repo root per learning)
- [ ] 3.2 Open `_site/index.html` in browser with DevTools Console -- verify zero CSP violations
- [ ] 3.3 Verify no CSP violations on pricing page (waitlist forms, JSON-LD, inline styles)
- [ ] 3.4 Verify no CSP violations on agents page (inline `style=` attributes on card-dot elements)
- [ ] 3.5 Verify Plausible analytics script loads (Network tab: GET to `plausible.io/js/...`)
- [ ] 3.6 Verify Plausible pageview event sends (Network tab: POST to `plausible.io/api/event`)
- [ ] 3.7 Verify newsletter form `fetch()` to `buttondown.com` succeeds
- [ ] 3.8 Verify waitlist form `fetch()` to `buttondown.com` succeeds
- [ ] 3.9 Verify JSON-LD structured data blocks cause no CSP errors
- [ ] 3.10 Run `validate-csp.sh _site` -- verify exit code 0
- [ ] 3.11 Temporarily modify an inline script in `base.njk`, rebuild, run `validate-csp.sh` -- verify it fails with clear error and prints expected hash
