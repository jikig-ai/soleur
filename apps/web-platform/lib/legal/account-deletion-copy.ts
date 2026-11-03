// #8211 / #9066 follow-up — single source of truth for the account-deletion erasure-pending
// copy shared by the Delete Account dialog (client), the post-delete notice on the login page
// (server component) and the `account_delete_initiate` agent tool (server). Pure strings, no
// imports, so every side can import it (client/server import boundary).
//
// STATUS: wording derived from the merged Privacy Policy, section "Pending-erasure record after
// account deletion" (docs/legal/privacy-policy.md; disclosure PR #11889). It is NOT an Article 17
// attestation and does not adopt the #9066 posture. No separate CLO sign-off is recorded for these
// strings; a change here must be re-read against that policy section.
//
// Legal constraints on every string here (they follow the policy, which is best effort):
//   * never say the repository copy is, has been or will certainly be erased/deleted/removed;
//   * the record of the workspace identifier is best effort (its write is bounded and can fail),
//     so say "we try to keep a record", never "we keep" or "will be completed";
//   * assert nothing about the lock files or the `.gc-cursor` progress marker (never say that
//     residue is gone) and nothing about local workspace files;
//   * give no timeline (no "straight away", no "within N days").

export const PRIVACY_POLICY_URL = "https://soleur.ai/legal/privacy-policy/";

/**
 * Policy heading the strings cite. Cited by heading name, not section number: numbers move when
 * the policy is renumbered, the heading is what a reader can search for.
 */
export const PRIVACY_POLICY_SECTION_HEADING = "Pending-erasure record after account deletion";
export const PRIVACY_POLICY_CITATION = `Privacy Policy, “${PRIVACY_POLICY_SECTION_HEADING}”`;

/** What the user can be told as a fact once the outcome is known: the one thing not confirmed. */
export const ERASURE_PENDING_HEADLINE =
  "Your account is deleted, but we cannot yet confirm the repository copy is removed.";

/** The unconfirmed fact, without a removal verb. */
export const ERASURE_PENDING_DETAIL =
  "The server that holds the repository copy of your workspace has not confirmed its removal.";

/** The best-effort retry-and-record qualifier, without the policy citation. */
export const ERASURE_RETRY_QUALIFIER =
  "If the server that holds your repository copy does not confirm its removal, we try to keep " +
  "a record of your workspace ID so that we can ask again until it confirms. The record is " +
  "best effort, so this is not a guarantee of removal.";

/** Text of the visually-hidden cue added to the policy link (it opens in a new tab). */
export const NEW_TAB_CUE = " (opens in a new tab)";

/** Agent-tool result `message` when `deleteAccount` reported `gitDataErasurePending`. */
export const ERASURE_PENDING_TOOL_MESSAGE =
  `${ERASURE_PENDING_HEADLINE} ${ERASURE_PENDING_DETAIL} ${ERASURE_RETRY_QUALIFIER} ` +
  `See ${PRIVACY_POLICY_CITATION}.`;

/**
 * Instruction for the calling agent, returned in a SEPARATE result field (`agentInstruction`) so
 * the user-facing `message` stays a self-contained, qualified statement.
 */
export const ERASURE_PENDING_AGENT_INSTRUCTION =
  "Relay the message to the user with its qualification intact. Do not tell the user the " +
  "repository copy has been, or will certainly be, erased or removed.";

/**
 * Agent-tool result `message` when `deleteAccount` did not report an owed repository removal
 * (the store confirmed it, or no removal was attempted). Says nothing about workspace files.
 */
export const ERASURE_COMPLETE_TOOL_MESSAGE =
  "Your account and conversations have been deleted from our application, and no repository " +
  "removal is outstanding.";
