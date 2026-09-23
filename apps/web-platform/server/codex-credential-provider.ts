import { decryptKey, decryptKeyLegacy, zeroize } from "./byok";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import type { CodexAuthProvider, CodexCredentialLease } from "./codex-code-adapter";

const DEFAULT_LEASE_TTL_MS = 5 * 60 * 1_000;

interface EncryptedCodexCredentialRow {
  encrypted_key: string;
  iv: string;
  auth_tag: string;
  key_version: number;
}

interface CodexApiKeyProviderOptions {
  userId: string;
  load: () => Promise<EncryptedCodexCredentialRow | null>;
  now?: () => number;
  leaseTtlMs?: number;
}

function credentialError(message: string, code: string): Error {
  return Object.assign(new Error(message), { code });
}

/** Construct the per-user API-key provider from the authenticated settings credential. */
export function createCodexApiKeyProvider(options: CodexApiKeyProviderOptions): CodexAuthProvider {
  const now = options.now ?? Date.now;
  const leaseTtlMs = options.leaseTtlMs ?? DEFAULT_LEASE_TTL_MS;
  let loggedOut = false;

  const loadLease = async (): Promise<CodexCredentialLease> => {
    if (loggedOut) throw credentialError("Codex credentials have been logged out", "codex_credentials_logged_out");
    const row = await options.load();
    if (!row) throw credentialError("Codex API key is not configured", "codex_credentials_missing");
    try {
      const encrypted = Buffer.from(row.encrypted_key, "base64");
      const iv = Buffer.from(row.iv, "base64");
      const tag = Buffer.from(row.auth_tag, "base64");
      const plaintext = row.key_version === 1
        ? decryptKeyLegacy(encrypted, iv, tag)
        : decryptKey(encrypted, iv, tag, options.userId);
      try {
        const accessToken = plaintext.toString("utf8");
        if (!accessToken.trim()) throw credentialError("Codex API key is empty", "codex_credentials_invalid");
        return { accessToken, expiresAt: now() + leaseTtlMs };
      } finally {
        zeroize(plaintext);
      }
    } catch (error) {
      if (error instanceof Error && "code" in error) throw error;
      throw credentialError("Codex API key could not be decrypted", "codex_credentials_invalid");
    }
  };

  return {
    mode: "api-key",
    acquire: loadLease,
    refresh: loadLease,
    logout: async () => { loggedOut = true; },
  };
}

/** Production loader: RLS-scoped to the authenticated user who owns the settings credential. */
export function createCodexApiKeyProviderForUser(userId: string): CodexAuthProvider {
  return createCodexApiKeyProvider({
    userId,
    load: async () => {
      const tenant = await getFreshTenantClient(userId);
      const { data, error } = await tenant
        .from("api_keys")
        .select("encrypted_key, iv, auth_tag, key_version")
        .eq("user_id", userId)
        .eq("provider", "openai")
        .eq("is_valid", true)
        .limit(1)
        .maybeSingle();
      if (error) throw credentialError("Codex credential lookup failed", "codex_credentials_lookup_failed");
      return (data as EncryptedCodexCredentialRow | null) ?? null;
    },
  });
}
