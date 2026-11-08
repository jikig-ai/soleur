/**
 * The words a founder-facing legal-acceptance string must never use (#12011, #12197): the card deck (legal-copy.test.ts)
 * and the committed legal texts (founder-acceptance-record.test.ts) both say only how an answer was given, never that
 * anything was verified, reviewed, certified, compliant or legally binding. ONE list so the two suites cannot drift.
 */
export const FORBIDDEN_CLAIMS =
  /verif(?:ied|ies|y)\b|reviewed|certified|enforceable|legally[\s-]+binding|audit[\s-]*ready|complian(?:t|ce)|guarantee[ds]?\b|tamper[\s-]*(?:proof|evident)|attest(?:ed|s|ation)?\b/i;
