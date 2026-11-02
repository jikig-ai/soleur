// #8211 / #9066 follow-up — single source of truth for the account-deletion erasure-pending
// copy shared by the Delete Account dialog (client) and the `account_delete_initiate` agent
// tool (server). Pure strings, no imports, so both sides can import it.
//
// DRAFT COPY — PENDING CLO SIGN-OFF. Derived from the CLO recommendation
// knowledge-base/legal/audits/2026-11-02-clo-recommendation-9066-erasure-ledger-disclosure.md
// ("Follow-ups that are code"). Edit only with CLO sign-off.
//
// Legal constraints on every string here:
//   * never say the repository copy is "erased"/"deleted"/"removed" without the
//     retry-and-ledger qualifier;
//   * assert nothing about the lock files or the `.gc-cursor` progress marker (#9066 is the
//     owner's decision; no purge/erasure claim may be made for that residue).
// The qualifier describes behaviour that exists only once the pending-erasure ledger and its
// re-drive cron (PR #10905) ship, and cites Privacy Policy section 4.16 (disclosure PR #11889).

export const PRIVACY_POLICY_URL = "https://soleur.ai/legal/privacy-policy/";
export const PRIVACY_POLICY_CITATION = "Privacy Policy, section 4.16";

/** The retry-and-ledger qualifier (CLO-suggested wording), without the policy citation. */
export const ERASURE_RETRY_QUALIFIER =
  "If our repository store cannot confirm the removal of your workspace copy straight away, " +
  "we keep your workspace identifier and try again until it does.";

/** Agent-tool result message when `deleteAccount` reported `gitDataErasurePending`. */
export const ERASURE_PENDING_TOOL_MESSAGE =
  "Your account, conversations and workspace files have been deleted. " +
  "We could not confirm the removal of the repository copy of your workspace from our " +
  "repository store, so it is not reported as removed. " +
  "We keep your workspace identifier and try again until the store confirms " +
  `(${PRIVACY_POLICY_CITATION}). ` +
  "Relay this to the user with that qualification intact.";

/** Agent-tool result message when the whole cascade, including the repository removal, completed. */
export const ERASURE_COMPLETE_TOOL_MESSAGE = "Account deletion cascade complete.";
