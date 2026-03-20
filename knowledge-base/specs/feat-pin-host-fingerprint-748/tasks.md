# Tasks: Pin Host Key Fingerprint in CI Deploy

## Phase 1: Setup

- [ ] 1.1 Obtain the server's Ed25519 host key SHA256 fingerprint
  - [ ] 1.1.1 SSH into the server and run `ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub`
  - [ ] 1.1.2 Extract the SHA256 fingerprint (second field from output)
- [ ] 1.2 Store the fingerprint as a GitHub Actions secret
  - [ ] 1.2.1 Run `gh secret set WEB_PLATFORM_HOST_FINGERPRINT --body "<fingerprint>"`
  - [ ] 1.2.2 Verify secret is listed with `gh secret list | grep FINGERPRINT`

## Phase 2: Core Implementation

- [ ] 2.1 Update `web-platform-release.yml` deploy step
  - [ ] 2.1.1 Add `fingerprint: ${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}` to the ssh-action `with:` block (line ~47)
- [ ] 2.2 Update `telegram-bridge-release.yml` env setup step
  - [ ] 2.2.1 Add `fingerprint: ${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}` to the first ssh-action `with:` block (line ~42)
- [ ] 2.3 Update `telegram-bridge-release.yml` deploy step
  - [ ] 2.3.1 Add `fingerprint: ${{ secrets.WEB_PLATFORM_HOST_FINGERPRINT }}` to the second ssh-action `with:` block (line ~60)

## Phase 3: Testing

- [ ] 3.1 Run compound check before commit
- [ ] 3.2 Push branch and create PR (Closes #748)
- [ ] 3.3 Verify CI passes on the PR
- [ ] 3.4 After merge, trigger a manual deploy workflow run to verify fingerprint verification works end-to-end
  - [ ] 3.4.1 `gh workflow run web-platform-release.yml` or wait for next push-to-main trigger
  - [ ] 3.4.2 Confirm deploy step succeeds with fingerprint verification
