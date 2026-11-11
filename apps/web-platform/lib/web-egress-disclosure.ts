/**
 * #12469: what stops working when Agent web access is on, and what replaces it. While a session's web access is running, its sandbox
 * carries no GitHub credentials, so the command-line `gh` is unavailable; the platform's read tools cover public repositories (a
 * session whose web access fails to start keeps its credentials; see the #12197 paragraph below). Each string is shared by the
 * toggle's ON block, its enable dialog and the Scope Grants page (CPO ruling: the three surfaces must carry the identical sentence).
 * A plain module, not exported from the "use client" toggle: a server component importing a value from a client module receives a
 * client reference, not the string. Copy only: this module enforces nothing; it describes what other code enforces.
 *
 * #12197 (CTO ruling F3, CPO W1, CLO W2, 2026-11-10): ADR-309 items 8(a) and 12 bind this copy to be accurate in BOTH forwarder
 * states. A toggle-on session whose web access fails to start runs as if the toggle were off (it keeps its repository credentials
 * and can push), so neither sentence makes an absolute "while this is on" claim; each is scoped to a session whose web access is
 * running. PUSH_DISCLOSURE claims owner approval only for a push an agent asks for (`github_push_branch`), never for every push: the
 * post-session sync push (`syncPush`) is a separate path (#12600). Render each constant
 * in its own paragraph and never split one.
 */
export const PUSH_DISCLOSURE =
  "While this is on and a session's web access is running, commands an agent runs in its sandbox have no stored credentials, so they can't push to git remotes or use stored API keys. If web access can't start for a session, that session runs as if this were off: it has no web access, and its commands keep their usual access to your connected repository, which can include pushing. An agent may still ask to push a branch to your connected repository through Soleur; nothing is pushed that way unless the workspace owner approves that push.";

export const GH_DISCLOSURE =
  "While this is on and a session's web access is running, the command-line gh tool is unavailable to agents in that session; for public repositories they still read your issues, pull requests, and CI status through Soleur, but can't create or edit them, and private repositories can't be read.";
