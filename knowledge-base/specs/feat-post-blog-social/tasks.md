# Tasks: Distribute CaaS Blog Post to X and Discord

## Phase 1: Prerequisites & Credential Setup

- [ ] 1.1 Source `.env` to load `DISCORD_WEBHOOK_URL`
- [ ] 1.2 Verify X API credentials are available (check `.env` for `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET`)
- [ ] 1.3 If X credentials missing, prompt user to export them or run `x-setup.sh write-env`
- [ ] 1.4 Verify X API access with `x-community.sh fetch-metrics`
- [ ] 1.5 Verify Discord webhook with a test (or trust env var presence)

## Phase 2: Execute social-distribute Skill

- [ ] 2.1 Invoke `skill: soleur:social-distribute plugins/soleur/docs/blog/what-is-company-as-a-service.md`
- [ ] 2.2 Review all 5 generated variants (Discord, X/Twitter, IndieHackers, Reddit, HN)
- [ ] 2.3 Approve and post Discord announcement
- [ ] 2.4 Capture X/Twitter thread text from skill output

## Phase 3: Post X/Twitter Thread

- [ ] 3.1 Post hook tweet via `x-community.sh post-tweet`
- [ ] 3.2 Post reply tweets in sequence using `--reply-to` with previous tweet ID
- [ ] 3.3 Verify thread is connected (all tweets appear as replies)

## Phase 4: Verification & Summary

- [ ] 4.1 Confirm Discord post appeared in channel
- [ ] 4.2 Confirm X thread is visible at `https://x.com/soleur_ai`
- [ ] 4.3 Report distribution summary (Discord: posted, X: posted, others: manual output provided)
