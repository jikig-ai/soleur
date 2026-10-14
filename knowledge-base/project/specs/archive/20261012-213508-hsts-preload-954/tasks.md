# Tasks: HSTS Preload Submission for soleur.ai

## Phase 1: Submit to HSTS Preload List

- [ ] 1.1 Navigate to hstspreload.org using Playwright MCP
- [ ] 1.2 Enter `soleur.ai` in the domain check field
- [ ] 1.3 Verify eligibility check passes (green checkmarks, no errors)
- [ ] 1.4 Check acknowledgment checkboxes (removal difficulty, all subdomains HTTPS-only)
- [ ] 1.5 Submit the domain
- [ ] 1.6 Capture confirmation status (screenshot or status text)

## Phase 2: Verify Submission

- [ ] 2.1 Query API: `https://hstspreload.org/api/v2/status?domain=soleur.ai`
- [ ] 2.2 Verify status changed from `unknown` to `pending` (or equivalent)

## Phase 3: Update Documentation

- [ ] 3.1 Update `knowledge-base/operations/domains.md` Security Configuration table with preload submission status and date
- [ ] 3.2 Add "HSTS Preload Commitment" section to `knowledge-base/operations/domains.md` documenting the constraint on future subdomains
- [ ] 3.3 Update `knowledge-base/project/learnings/2026-03-20-nextjs-static-csp-security-headers.md` HSTS table entry to include `preload`

## Phase 4: Commit and Ship

- [ ] 4.1 Run compound before commit
- [ ] 4.2 Commit documentation updates
- [ ] 4.3 Push and create PR (closes #954)
