# Feature: UTM Conventions

## Problem Statement

Content distribution uses bare URLs with no attribution tracking. There is no way to determine which distribution channel (Discord, X, IndieHackers, Reddit, HN, LinkedIn) drives blog traffic. Plausible Analytics supports UTM parameters natively but none are being generated.

## Goals

- Define UTM parameter conventions for all distribution channels
- Inject platform-specific UTM parameters at content generation time (social-distribute skill)
- Enable per-channel traffic attribution in Plausible's Sources > Campaigns report
- Update 4 unpublished distribution-content files with UTM-tagged URLs

## Non-Goals

- Publish-time UTM injection in content-publisher.sh (generation-time covers all platforms)
- `utm_content` or `utm_term` parameters (no variant tracking or paid search)
- Retroactive updates to 2 already-published content files
- Link shortening or redirect infrastructure
- Campaign naming namespacing (just article slug, no prefixes)

## Functional Requirements

### FR1: UTM Parameter Generation

social-distribute skill appends UTM query parameters to article URLs during Phase 3 content generation. Each platform section gets a URL with platform-specific parameters.

### FR2: Platform-Specific UTM Rules

| Platform | utm_source | utm_medium | utm_campaign |
|----------|-----------|-----------|-------------|
| Discord | `discord` | `community` | `<article-slug>` |
| X/Twitter | `x` | `social` | `<article-slug>` |
| IndieHackers | `indiehackers` | `community` | `<article-slug>` |
| Hacker News | `hackernews` | `community` | `<article-slug>` |
| LinkedIn | `linkedin` | `social` | `<article-slug>` |
| Reddit | `reddit` | (none) | (none) |
| Email | `email` | `newsletter` | `<article-slug>` |

Reddit gets `utm_source=reddit` only to avoid spam filter risk.

### FR3: Existing Content Updates

Update 4 unpublished distribution-content files with UTM-tagged URLs:
- `02-operations-management.md`
- `03-competitive-intelligence.md`
- `04-brand-guide-creation.md`
- `05-business-validation.md`

### FR4: Convention Documentation

Add UTM conventions section to `knowledge-base/marketing/content-strategy.md`.

## Technical Requirements

### TR1: UTM Value Sanitization

UTM parameter values must be validated with strict character allowlist: alphanumeric, hyphens, underscores. This prevents query parameter injection (documented risk from OAuth signature learning).

### TR2: URL Construction

UTM parameters appended as standard query string: `?utm_source=x&utm_medium=social&utm_campaign=slug`. If the URL already contains a query string, use `&` separator.

### TR3: Article Slug Derivation

Campaign slug derived from the blog post URL path (e.g., `/blog/caas-pillar/` -> `caas-pillar`). Strip leading/trailing slashes.
