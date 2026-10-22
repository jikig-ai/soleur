# Decision Challenges — feat-one-shot-10390-verify-blob-reject

Headless planning session (one-shot plan subagent). No subagent-spawn capability in this harness, so
technical rulings carry `pending - assumed:` per the pipeline contract; ship renders them for the
operator.

| Item | Class | Ruling |
|---|---|---|
| Diagnostic surface: new `diagnose-inngest-verify.yml` dispatch workflow vs. bolting a job onto an existing `packages: read` workflow (e.g., `scheduled-vinngest-digest-freshness.yml`) | technical | pending - assumed: new dedicated dispatch workflow (single-purpose, digest-parameterized, kept as the sanctioned no-SSH probe for future `reason=signature` rows; avoids coupling a diagnostic to a scheduled comparator) |
| Stderr surfacing shape: bounded `detail=` classification token on the VERIFY_FAIL row vs. full stderr text in the marker | technical | pending - assumed: classified token + bounded on-host `verify.stderr` file (marker rows cross `inngest-redact.sh` and the drift executor's key parser; full stderr can carry arbitrary text and must not ride the row) |
| `reason=` taxonomy: keep `reason=signature` + additive `detail=` vs. split into new `reason=` codes | technical | pending - assumed: keep `reason=signature` (drift executor's `_summ_row` key set and any downstream greps stay valid; `detail=` is additive) |
| If Phase 0's stderr is a `LoadJSONFromPath` gate error on a cosign-written bundle: producer-side fix vs. host-side verify-flag change | technical | pending - assumed: fix whichever side the `jq`/stderr evidence names; if the bundle is cosign-conforming and only the host's mount/read fails, the fix is host-side |
| If Phase 0 prints `Verified OK`: treat as host-state divergence and ship only the stderr capture via replace | technical | pending - assumed: yes — a clean repro is itself diagnostic; Phase 2 capture then surfaces the real host-side stderr on the next failing tick |
| Whether any verification-relaxing flag may ship as the fix (`--insecure-ignore-tlog`, `--insecure-ignore-sct`, `--key`, `--new-bundle-format`) | technical | pending - assumed: never — a weakening is a security posture change requiring an ADR-135 amendment, not a patch (AC10) |
| `brand_survival_threshold` / `requires_cpo_signoff` | technical | pending - assumed: `single-user incident` / `true` — the change edits the cryptographic provenance gate on the sole production scheduler |
