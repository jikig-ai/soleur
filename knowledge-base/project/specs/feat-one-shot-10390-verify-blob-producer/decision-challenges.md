# Decision Challenges — feat-one-shot-10390-verify-blob-producer

One-shot planning session, 2026-10-23. No Agent/Task tool available on this harness — technical
rows are `pending - assumed: <default>` per technical-ruling-delegation.md (no CTO spawn possible).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Fix shape: repo-pinned SigningConfig (Rekor v1 + no TSA) via `--signing-config`, vs post-processing the emitted JSON with jq | technical | pending - assumed: pinned SigningConfig primary (also covers the Rekor-v2-emit and TSA-drift arms); jq repair kept as fallback only if the Phase-0 verbatim error names a field the config cannot fix |
| Phase-0 verbatim-error probe (Go `LoadJSONFromPath` repro at sigstore-go@v1.2.0 inside the diagnose workflow) precedes the fix | technical | pending - assumed: yes — `checkNewBundle` swallows the real error; the check name selects the fix arm and the stated prime suspect was already refuted once this session (live A/B on the pinned image: tlog+tsvd co-presence loads fine) |
| Floor 5→6 ordering vs the `doppler_secret` promotion apply | technical | pending - assumed: same-window merge→promote gate recorded in PR body + merge comment (floor 6 with the secret still absent FATALs the next boot; no `inngest-host-replace` dispatch may run between merge and promotion) |
| Producer verify-gate identity regexp derived from `${GITHUB_REF}` (branch dispatches) vs pinning `@refs/heads/main` | technical | pending - assumed: ref-derived with metacharacter escaping, so branch dispatches also exercise the gate; the host-side baked `main` regexp is unchanged |
| Whether `verify-before-publish` asserts full `Verified OK` vs load-only | technical | pending - assumed: full `Verified OK` on the runner (network available); the step hard-fails otherwise |
