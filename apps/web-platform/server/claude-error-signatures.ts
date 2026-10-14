/** Claude Agent SDK error-message signatures — external SDK message contracts
 *  shared by every discriminator (sanitizer, legacy agent-runner re-throw,
 *  soleur-go-runner stale-resume arm) so an SDK wording change degrades all
 *  consumers in lockstep instead of silently diverging. Leaf module by
 *  design: many test files `vi.mock` error-sanitizer, which would undefined
 *  this const for agent-runner under those mocks.
 */

/** Echoed through the iterator's thrown error when `query({ resume })`
 *  targets a session that no longer exists. */
export const SDK_STALE_RESUME_SESSION_ID =
  "No conversation found with session ID";
