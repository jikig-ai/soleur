"use client";

import { useState } from "react";
import {
  PROVIDER_CONFIG,
  EXCLUDED_FROM_SERVICES_UI,
  SERVICE_PROVIDERS,
} from "@/server/providers";
import type { Provider } from "@/lib/types";

interface ServiceRow {
  provider: string;
  is_valid: boolean;
  validated_at: string | null;
  updated_at: string | null;
}

interface Props {
  initialServices: ServiceRow[];
}

const CATEGORY_LABELS: Record<string, string> = {
  llm: "LLM Providers",
  infrastructure: "Infrastructure",
  social: "Social",
};

const CATEGORY_ORDER = ["llm", "infrastructure", "social"] as const;

function formatDate(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function ProviderCard({
  provider,
  connected,
  validatedAt,
  onConnect,
  onRemove,
}: {
  provider: Provider;
  connected: boolean;
  validatedAt: string | null;
  onConnect: (provider: Provider, token: string) => Promise<{ valid: boolean; error?: string }>;
  onRemove: (provider: Provider) => Promise<void>;
}) {
  const config = PROVIDER_CONFIG[provider];
  const [expanded, setExpanded] = useState(false);
  const [token, setToken] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [removing, setRemoving] = useState(false);

  const handleSubmit = async () => {
    if (!token.trim()) return;
    setLoading(true);
    setError("");
    const result = await onConnect(provider, token.trim());
    setLoading(false);
    if (result.valid) {
      setExpanded(false);
      setToken("");
    } else {
      setError(result.error ?? "Token validation failed. Please check and try again.");
    }
  };

  const handleRemove = async () => {
    setRemoving(true);
    await onRemove(provider);
    setRemoving(false);
  };

  return (
    <div
      className={`rounded-lg border p-4 transition-colors ${
        expanded
          ? error
            ? "border-red-900/50"
            : "border-amber-600/50"
          : "border-soleur-border-default"
      }`}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div
            className={`h-2 w-2 rounded-full ${
              connected ? "bg-green-400" : "bg-soleur-bg-surface-2"
            }`}
          />
          <div>
            <span className="text-sm font-medium text-soleur-text-primary">{config.label}</span>
            {connected && validatedAt && (
              <span className="ml-2 text-xs text-soleur-text-muted">
                Connected {formatDate(validatedAt)}
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          {connected ? (
            <>
              <button
                onClick={() => setExpanded(!expanded)}
                className="rounded-lg border border-soleur-border-default px-3 py-1.5 text-xs font-medium text-soleur-text-secondary transition-colors hover:border-soleur-border-default hover:text-soleur-text-primary"
              >
                Rotate
              </button>
              <button
                onClick={handleRemove}
                disabled={removing}
                className="rounded-lg border border-red-900/30 px-3 py-1.5 text-xs font-medium text-red-400 transition-colors hover:border-red-800 hover:text-red-300 disabled:opacity-50"
              >
                {removing ? "Removing..." : "Remove"}
              </button>
            </>
          ) : (
            <button
              onClick={() => setExpanded(!expanded)}
              className="rounded-lg bg-soleur-accent-gold-fill px-3 py-1.5 text-xs font-medium text-soleur-text-on-accent transition-colors hover:opacity-90"
            >
              {expanded ? "Cancel" : "Connect"}
            </button>
          )}
        </div>
      </div>

      {expanded && (
        <div className="mt-4 space-y-3">
          <div>
            <label
              htmlFor={`token-${provider}`}
              className="mb-1 block text-xs font-medium text-soleur-text-secondary"
            >
              API Token
            </label>
            <input
              id={`token-${provider}`}
              type="password"
              value={token}
              onChange={(e) => setToken(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") handleSubmit();
              }}
              placeholder={`Paste your ${config.label} API token`}
              className={`w-full rounded-lg border bg-soleur-bg-surface-1 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted focus:ring-1 ${
                error
                  ? "border-red-800 focus:border-red-600 focus:ring-red-600"
                  : "border-soleur-border-default focus:border-soleur-border-emphasized focus:ring-soleur-border-emphasized"
              }`}
            />
          </div>
          {error && (
            <p className="text-sm text-red-400" role="alert">
              {error}
            </p>
          )}
          <div className="flex items-center justify-between">
            <p className="text-xs text-soleur-text-muted">
              Token will be encrypted at rest and validated before saving.
            </p>
            <button
              onClick={handleSubmit}
              disabled={loading || !token.trim()}
              className="rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:opacity-90 disabled:opacity-50"
            >
              {loading ? "Validating..." : "Save"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export function ConnectedServicesContent({ initialServices }: Props) {
  const [services, setServices] = useState<ServiceRow[]>(initialServices);

  const connectedMap = new Map(
    services
      .filter((s) => !EXCLUDED_FROM_SERVICES_UI.has(s.provider as Provider))
      .map((s) => [s.provider, s]),
  );

  const handleConnect = async (
    provider: Provider,
    token: string,
  ): Promise<{ valid: boolean; error?: string }> => {
    const res = await fetch("/api/services", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider, token }),
    });
    const data = await res.json();
    if (!res.ok) return { valid: false, error: data.error };
    if (!data.valid) return { valid: false, error: data.error };

    // Refresh service list
    const listRes = await fetch("/api/services");
    const listData = await listRes.json();
    if (listRes.ok) setServices(listData.services ?? []);
    return { valid: true };
  };

  const handleRemove = async (provider: Provider) => {
    const res = await fetch("/api/services", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ provider }),
    });
    if (res.ok) {
      setServices((prev) => prev.filter((s) => s.provider !== provider));
    }
  };

  // Group providers by category
  const grouped = new Map<string, Provider[]>();
  for (const provider of SERVICE_PROVIDERS) {
    const config = PROVIDER_CONFIG[provider];
    const list = grouped.get(config.category) ?? [];
    list.push(provider);
    grouped.set(config.category, list);
  }

  return (
    <div className="space-y-10">
      <div>
        <h1 className="text-2xl font-bold text-soleur-text-primary">Connected Services</h1>
        <p className="mt-1 text-sm text-soleur-text-secondary">
          Manage API tokens for third-party services. Tokens are encrypted with
          AES-256-GCM and automatically available to your agent sessions.
        </p>
      </div>

      {CATEGORY_ORDER.map((category) => {
        const providers = grouped.get(category);
        if (!providers?.length) return null;

        return (
          <section
            key={category}
            className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6"
          >
            <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">
              {CATEGORY_LABELS[category]}
            </h2>
            <div className="space-y-3">
              {providers.map((provider) => {
                const service = connectedMap.get(provider);
                return (
                  <ProviderCard
                    key={provider}
                    provider={provider}
                    connected={!!service?.is_valid}
                    validatedAt={service?.validated_at ?? null}
                    onConnect={handleConnect}
                    onRemove={handleRemove}
                  />
                );
              })}
            </div>
          </section>
        );
      })}
    </div>
  );
}
