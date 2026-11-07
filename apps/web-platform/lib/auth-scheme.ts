// The two credential schemes the agent CLI can run under (#11086). Defined once here so the server (agent-env.ts) and the
// WebSocket error frame (lib/types.ts, lib/ws-zod-schemas.ts) share one literal instead of carrying copies.
export const CREDENTIAL_SCHEMES = ["api_key", "oauth_token"] as const;
export type CredentialScheme = (typeof CREDENTIAL_SCHEMES)[number];
