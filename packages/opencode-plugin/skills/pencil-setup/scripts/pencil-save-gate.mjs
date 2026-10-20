// pencil-save-gate.mjs — pure decision function for auto-save after a
// pencil REPL mutation. Extracted so it can be unit-tested without
// importing the adapter.
//
// Why this exists: the adapter previously called save() unconditionally
// after every mutating op (batch_design, open_document, set_variables,
// etc.). When a mutation errored (auth failure, invalid property), the
// follow-up save() still ran and wrote a 0-byte or stale .pen file to
// disk. The caller saw a successful save but no real content — the
// "silent drop" that preceded #2630's fabricated "headless stub"
// narrative.

/**
 * Decide whether to SKIP the post-mutation save() call.
 *
 * Returns true only when the last classification explicitly reports
 * isError === truthy. Missing/null/undefined classifications allow
 * the save (preserves existing behavior for first-call and for callers
 * that don't track classifications).
 */
export function shouldSkipSave(lastClassification) {
  if (!lastClassification || typeof lastClassification !== "object") {
    return false;
  }
  return Boolean(lastClassification.isError);
}
