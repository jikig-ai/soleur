# Tasks: Remove Infrastructure Identifiers from Legal Docs

## Phase 1: Text Replacements

- [ ] 1.1 Replace `Hetzner CX33, Helsinki` with `Hetzner (Helsinki, Finland, EU)` in `docs/legal/gdpr-policy.md`
- [ ] 1.2 Replace `Hetzner CX33, Helsinki` with `Hetzner (Helsinki, Finland, EU)` in `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- [ ] 1.3 Replace `Helsinki, Finland (hel1)` with `Helsinki, Finland (EU)` in `docs/legal/privacy-policy.md`
- [ ] 1.4 Replace `Helsinki, Finland (hel1)` with `Helsinki, Finland (EU)` in `plugins/soleur/docs/pages/legal/privacy-policy.md`
- [ ] 1.5 Replace `hashed passwords (bcrypt via GoTrue)` with `hashed passwords (managed by Supabase)` in `docs/legal/gdpr-policy.md`
- [ ] 1.6 Replace `hashed passwords (bcrypt via GoTrue)` with `hashed passwords (managed by Supabase)` in `plugins/soleur/docs/pages/legal/gdpr-policy.md`

## Phase 2: Verification

- [ ] 2.1 Grep `docs/legal/` and `plugins/soleur/docs/pages/legal/` for `CX33` -- expect zero matches
- [ ] 2.2 Grep both locations for `hel1` -- expect zero matches
- [ ] 2.3 Grep both locations for `GoTrue` -- expect zero matches
- [ ] 2.4 Verify replacement text is present: `Hetzner (Helsinki, Finland, EU)` in both GDPR Policy copies
- [ ] 2.5 Verify replacement text is present: `Helsinki, Finland (EU)` in both Privacy Policy copies
- [ ] 2.6 Verify replacement text is present: `hashed passwords (managed by Supabase)` in both GDPR Policy copies

## Phase 3: Commit and Ship

- [ ] 3.1 Run compound
- [ ] 3.2 Commit with message `chore(legal): remove infrastructure identifiers from public legal documents`
- [ ] 3.3 Push and create PR referencing `Closes #892`
