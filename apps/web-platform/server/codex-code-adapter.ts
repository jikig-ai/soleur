import type { EngineAdapter } from "./agent-engine-contract";

export const CODEX_ENGINE_ID = "codex" as const;
export type CodexAuthMode = "api-key" | "managed";

export interface CodexCredentialLease {
  readonly accessToken: string;
  readonly expiresAt: number;
}

export interface CodexAuthProvider {
  mode: CodexAuthMode;
  acquire(): Promise<CodexCredentialLease>;
  refresh(): Promise<CodexCredentialLease>;
  logout(): Promise<void>;
}

export interface CodexAuthBoundary {
  readonly mode: CodexAuthMode;
  acquire(): Promise<CodexCredentialLease>;
  refresh(): Promise<CodexCredentialLease>;
  logout(): Promise<void>;
}

/**
 * Keeps Codex credentials behind a mode-stable adapter seam. Callers receive
 * only a short-lived lease; persistence and neutral engine contracts never see
 * the token or provider-specific login state.
 */
export function createCodexAuthBoundary(provider: CodexAuthProvider): CodexAuthBoundary {
  const mode = provider.mode;
  const assertStableMode = () => {
    if (provider.mode !== mode) {
      throw Object.assign(new Error("Codex auth mode changed during a session"), {
        code: "codex_auth_mode_changed",
      });
    }
  };

  return {
    mode,
    acquire: async () => {
      assertStableMode();
      return provider.acquire();
    },
    refresh: async () => {
      assertStableMode();
      return provider.refresh();
    },
    logout: async () => {
      assertStableMode();
      await provider.logout();
    },
  };
}

/** Adapter transport remains a later GREEN-05 seam; Codex stays disabled until qualification. */
export type CodexCodeAdapter = EngineAdapter;
