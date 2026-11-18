// The Soleur identity of every server-built commit: the approved cc push's commit and every commit the KB sync builds
// (CTO ruling L). A leaf (no imports), so the KB sync modules read it without importing server/push-branch.ts
// (#12600, rulings D21 and D25(4)).
export const AGENT_AUTHOR_NAME = "Soleur Agent";
export const AGENT_AUTHOR_EMAIL = "agent@soleur.ai";
