# Tasks: fix CSP Cloudflare challenge script blocked

## Phase 1: Documentation

- [ ] 1.1 Read `plugins/soleur/docs/_includes/base.njk` to verify current CSP meta tag location (line 24)
- [ ] 1.2 Add HTML comment above CSP meta tag in `base.njk` documenting the known Cloudflare Bot Fight Mode console error and referencing #1149

## Phase 2: Verification

- [ ] 2.1 Verify no changes to CSP directives or hashes in the meta tag (HTML comment is outside the tag, so no impact expected)
- [ ] 2.2 Run Eleventy build and `bash plugins/soleur/skills/seo-aeo/scripts/validate-csp.sh _site` to confirm CSP validation still passes
- [ ] 2.3 Note: `validate-csp.sh` does NOT need modification -- it scans static HTML files, and the Cloudflare-injected script only appears in live responses through Cloudflare's proxy

## Phase 3: Issue Closure

- [ ] 3.1 Close #1149 with a comment explaining the "accept as known limitation" decision, referencing this plan and the Cloudflare docs confirmation that meta tag nonces are unsupported
