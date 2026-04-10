import type { Provider } from "@/lib/types";

const VALIDATION_TIMEOUT_MS = 5_000;

interface ValidatorConfig {
  url: string | (() => string);
  headers: (token: string) => Record<string, string>;
  method?: string;
}

const VALIDATOR_CONFIGS: Partial<Record<Provider, ValidatorConfig>> = {
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
    url: "https://api.linkedin.com/v2/userinfo",
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
    const url = typeof config.url === "function" ? config.url() : config.url;
    const res = await fetch(url, {
      method: config.method,
      headers: config.headers(token),
      signal: AbortSignal.timeout(VALIDATION_TIMEOUT_MS),
    });
    return res.ok;
  } catch {
    return false;
  }
}
