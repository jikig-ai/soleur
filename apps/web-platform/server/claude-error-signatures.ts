/** Claude Agent SDK error-message signatures — external SDK message contracts
 *  shared by every discriminator (sanitizer, legacy agent-runner re-throw,
 *  soleur-go-runner stale-resume arm) so an SDK wording change degrades all
 *  consumers in lockstep instead of silently diverging. Leaf module by
 *  design: many test files `vi.mock` error-sanitizer, which would undefined
 *  this const for agent-runner under those mocks.
 *
 *  Two kinds of signature live here: a THROWN-error signature (`SDK_STALE_RESUME_SESSION_ID`, echoed through the iterator's
 *  thrown error) and REPLY signatures (`CLI_AUTH_FAILURE_REPLIES`, `SDK_AUTHENTICATION_FAILED`: messages the CLI prints
 *  as ordinary stream messages when it has no usable credential), consumed by `agent-auth-failure.ts`.
 */

/** Echoed through the iterator's thrown error when `query({ resume })`
 *  targets a session that no longer exists. */
export const SDK_STALE_RESUME_SESSION_ID =
  "No conversation found with session ID";

/** The SDK's own structured assistant-message error code for a failed CLI login (`SDKAssistantMessageError` in
 *  sdk.d.ts). Wording-independent, so it keeps firing when the CLI text below changes. The message translator in
 *  `claude-code-message-translator.ts` carries its own copy of the code set (not touched by the auth-failure
 *  diagnostic); a comment on each names the other. */
export const SDK_AUTHENTICATION_FAILED = "authentication_failed";

/** The `ApiKeySource` union of sdk.d.ts (the `apiKeySource` the CLI reports in its `system`/`init` message): the closed
 *  set of credential SOURCES the CLI names. It names where the credential came from, never its value. Mirrored here
 *  (not imported) so this leaf module stays SDK-free; re-derive on every SDK bump. */
export const SDK_API_KEY_SOURCES = [
  "ANTHROPIC_API_KEY",
  "apiKeyHelper",
  "/login managed key",
  "none",
  "user",
  "project",
  "org",
  "temporary",
  "oauth",
] as const;

export type CliAuthFailureKind =
  | "not_logged_in"
  | "invalid_api_key"
  | "oauth_token_revoked"
  | "session_expired";

/** REPLY signatures: texts the Claude CLI itself PRINTS as an assistant reply or an error result when it has no usable
 *  credential (unlike `SDK_STALE_RESUME_SESSION_ID` above, which is echoed through a THROWN error). Each pattern is
 *  anchored on the WHOLE message, so the near-miss "Invalid API key format. API key must contain only ..." and model prose
 *  such as "you are not logged in to gh" do not match. The separator is U+00B7, written as the \u00B7 escape
 *  (cq-regex-unicode-separators-escape-only). No nested or overlapping quantifiers: every pattern is a literal with at
 *  most one alternation, so matching is linear in the (<= 200 char) input.
 *
 *  Wording read from the bundled `claude` binary of @anthropic-ai/claude-agent-sdk 0.3.284 on 2026-10-25 (`grep -a` over the
 *  binary, read-only, no credentials): "Invalid API key", "Session expired. Please run /login to sign in again." and
 *  "Not logged in. Run claude auth login" are present. "Your session has expired. Please run /login to sign in again." is
 *  also present (three hits), but only in the remote-session fetch paths, where it is THROWN or returned as an error and not
 *  printed as a stream reply, so that alternative is kept as a spare whose stream reachability is unverified. The same holds
 *  for "Session expired. Please run /login to sign in again.": it too sits in a throw path, so `session_expired` has no
 *  stream-reply evidence yet. Real CLI strings not matched here (`Login expired`, `Authentication required`, `Invalid auth
 *  token`, each followed by the /login hint) fall to the structured arm when the CLI also sets `authentication_failed`. A further
 *  wording, "Not logged in. This session uses a Cloud gateway; start `claude` and sign in with /login.", sits in what looks
 *  like interactive render code and is not matched here. Checked 2026-10-29 (#11086): both "Not logged in" variants sit in the
 *  `claude auth status` text renderer (next to the `loggedIn`, `orgName` and `forcedLoginMethod` keys), not in a stream reply,
 *  so no pattern is needed. Three more wordings measured on 2026-10-29 are deliberately left to the structured arm, which
 *  classifies them as `structured` (CTO ruling: a new kind would widen what the #11085 removal deletes): "Failed to
 *  authenticate. API Error: 401 ..." (a used token the API refused), "Invalid auth token \u00B7 Fix external auth token ..."
 *  (an embedded line break) and "Invalid API key \u00B7 Fix external API key" (an API-key-shaped value in the API-key variable). RE-DERIVE ON EVERY
 *  SDK BUMP: the structured `SDK_AUTHENTICATION_FAILED` arm covers most of a wording change, but nothing else re-checks
 *  this list. */
export const CLI_AUTH_FAILURE_REPLIES: ReadonlyArray<{ kind: CliAuthFailureKind; pattern: RegExp }> = [
  {
    kind: "not_logged_in",
    pattern: /^Not logged in(?: \u00B7 Please run \/login|\. Run claude auth login to authenticate\.)$/,
  },
  { kind: "invalid_api_key", pattern: /^(?:API Error: 401 )?Invalid API key \u00B7 Please run \/login$/ },
  { kind: "oauth_token_revoked", pattern: /^OAuth token revoked \u00B7 Please run \/login$/ },
  {
    kind: "session_expired",
    pattern: /^(?:Session expired|Your session has expired)\. Please run \/login to sign in again\.$/,
  },
];
