# Tasks: fix SEO audit agent curl redirect handling (#1169)

## Phase 1: Core Implementation

### 1.1 Add curl -L guidance to Important Guidelines section

- [ ] Read `plugins/soleur/agents/marketing/seo-aeo-analyst.md`
- [ ] Add bullet to "Important Guidelines" section: "When fetching live URLs with curl, always use `-L` to follow redirects -- Cloudflare Bot Fight Mode and similar CDN protections return 301/302 redirects that strip all page content from the initial response"

### 1.2 Add inline curl note to Meta Tags audit step

- [ ] Add guidance note within Step 2 Meta Tags block: "When fetching live pages for verification, always use `curl -sL` (follow redirects) -- Cloudflare Bot Fight Mode returns 301 redirects that strip all page content"

## Phase 2: Verification

### 2.1 Grep verification

- [ ] Verify `grep -c 'curl' plugins/soleur/agents/marketing/seo-aeo-analyst.md` returns at least 2

### 2.2 Post-merge validation

- [ ] After merge, verify next scheduled SEO audit does not produce false positives for meta tags or feed entries
