# Tasks: Repo Connection Launch Content

## Phase 1: Product Update Blog Post

- [ ] 1.1 Run `soleur:content-writer` with topic "Your AI Team Now Works From Your Actual Codebase"
  - [ ] 1.1.1 Pass outline covering: the problem (empty workspace), the solution (repo connection), onboarding flow, auto-create option, sync model, compound knowledge angle
  - [ ] 1.1.2 Pass keywords: "AI team codebase", "GitHub AI agent", "AI development workflow", "agentic engineering codebase"
  - [ ] 1.1.3 Specify audience as both general and technical registers
- [ ] 1.2 Review generated draft against brand guide voice requirements
- [ ] 1.3 Verify all factual claims against PR #1257 implementation code
- [ ] 1.4 Verify Eleventy frontmatter and JSON-LD structured data

## Phase 2: Technical Blog Post

- [ ] 2.1 Run `soleur:content-writer` with topic "Credential Helper Isolation: Secure Git Auth in Sandboxed Environments"
  - [ ] 2.1.1 Pass outline covering: the problem, credential helper pattern, GitHub App tokens vs PAT, security hardening, best-effort sync philosophy
  - [ ] 2.1.2 Pass keywords: "git credential helper", "sandboxed git auth", "GitHub App authentication", "credential isolation pattern"
  - [ ] 2.1.3 Specify audience as technical register
- [ ] 2.2 Verify code examples match actual implementation files
  - [ ] 2.2.1 Cross-check against `apps/web-platform/server/workspace.ts`
  - [ ] 2.2.2 Cross-check against `apps/web-platform/server/github-app.ts`
  - [ ] 2.2.3 Cross-check against `apps/web-platform/server/session-sync.ts`
- [ ] 2.3 Verify technical register voice and security claim accuracy

## Phase 3: Social Distribution and Content Strategy Updates

- [ ] 3.1 Run `soleur:social-distribute` on the product update blog post path
- [ ] 3.2 Review platform-specific variants for character limits and formatting (prioritize Discord, X, LinkedIn)
- [ ] 3.3 Verify brand voice consistency across primary channel variants
- [ ] 3.4 Verify distribution content file has correct YAML frontmatter
- [ ] 3.5 Update `knowledge-base/marketing/content-strategy.md` Gap 4 with reference to new content
- [ ] 3.6 Update `knowledge-base/marketing/campaign-calendar.md` with new entries
- [ ] 3.7 Final review: verify all acceptance criteria are met
