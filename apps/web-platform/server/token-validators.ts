import type { Provider } from "@/lib/types";
import logger from "@/server/logger";

const VALIDATION_TIMEOUT_MS = 5_000;

interface ValidatorConfig {
  url: string | (() => string);
  headers: (token: string) => Record<string, string>;
  method?: string;
  // Probed in order ONLY after a 403 — the token is alive but the primary
  // endpoint's scopes aren't granted (#9188).
  fallbackUrls?: string[];
  // "manual" keeps a Bearer from riding a 30x to an arbitrary host.
  redirect?: "manual";
}

const VALIDATOR_CONFIGS: Partial<Record<Provider, ValidatorConfig>> = {
  openai: {
    url: "https://api.openai.com/v1/models",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  anthropic: {
    url: "https://api.anthropic.com/v1/models",
    headers: (token) => ({ "x-api-key": token, "anthropic-version": "2023-06-01" }),
    method: "GET",
  },
  cloudflare: {
    url: "https://api.cloudflare.com/client/v4/user/tokens/verify",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  stripe: {
    url: "https://api.stripe.com/v1/balance",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  plausible: {
    url: () => `https://plausible.io/api/v1/stats/realtime/visitors?site_id=${encodeURIComponent(process.env.PLAUSIBLE_SITE_ID ?? "soleur.ai")}`,
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  hetzner: {
    url: "https://api.hetzner.cloud/v1/servers?per_page=1",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  github: {
    url: "https://api.github.com/user",
    headers: (token) => ({ Authorization: `Bearer ${token}`, "User-Agent": "soleur" }),
  },
  doppler: {
    url: "https://api.doppler.com/v3/me",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  resend: {
    url: "https://api.resend.com/api-keys",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  x: {
    url: "https://api.x.com/2/users/me",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  linkedin: {
    // Two developer apps mint our tokens: the OIDC app (openid; userinfo works)
    // and the Community app (w_organization_social et al; NO openid). A pasted
    // token's minting app is unknowable — tokens are opaque — so on exactly
    // 403 we ask each cheaper-to-authorize endpoint what this token can do:
    // /v2/me catches member-liveness scopes, organizationalEntityAcls (the same
    // URL the cron probes) catches org-capable/member-denied shapes. Same
    // capability-aware chain as cron-linkedin-token-check's TOKEN_PROBES.
    url: "https://api.linkedin.com/v2/userinfo",
    fallbackUrls: [
      "https://api.linkedin.com/v2/me",
      "https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED",
    ],
    redirect: "manual",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  bluesky: {
    url: "https://bsky.social/xrpc/app.bsky.actor.getProfile?actor=self",
    headers: (token) => ({ Authorization: `Bearer ${token}` }),
  },
  buttondown: {
    url: "https://api.buttondown.com/v1/emails?page_size=1",
    headers: (token) => ({ Authorization: `Token ${token}` }),
  },
};

export async function validateToken(
  provider: Provider,
  token: string,
): Promise<boolean> {
  const config = VALIDATOR_CONFIGS[provider];
  if (!config) return false;
  try {
    const primary = typeof config.url === "function" ? config.url() : config.url;
    // One shared deadline across the whole chain — the total budget stays
    // VALIDATION_TIMEOUT_MS, not per-probe.
    const signal = AbortSignal.timeout(VALIDATION_TIMEOUT_MS);
    for (const url of [primary, ...(config.fallbackUrls ?? [])]) {
      const res = await fetch(url, {
        method: config.method,
        headers: config.headers(token),
        redirect: config.redirect,
        signal,
      });
      if (res.ok) return true;
      // 401 = dead token; burn no fallbacks. 403 = alive but this endpoint's
      // scopes aren't granted; keep asking. Anything else is inconclusive.
      if (res.status === 401) return false;
      if (res.status !== 403) {
        if (config.fallbackUrls) {
          logger.warn(
            { fn: "validateToken", provider, status: res.status },
            "token validation inconclusive",
          );
        }
        return false;
      }
    }
    return false;
  } catch {
    if (config.fallbackUrls) {
      logger.warn(
        { fn: "validateToken", provider },
        "token validation probe failed",
      );
    }
    return false;
  }
}
