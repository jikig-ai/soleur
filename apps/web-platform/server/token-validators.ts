import type { Provider } from "@/lib/types";

const VALIDATION_TIMEOUT_MS = 5_000;

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
): Promise<Response> {
  return fetch(url, { ...init, signal: AbortSignal.timeout(VALIDATION_TIMEOUT_MS) });
}

// --- Per-provider validators ---

async function validateAnthropic(token: string): Promise<boolean> {
  const res = await fetchWithTimeout("https://api.anthropic.com/v1/models", {
    method: "GET",
    headers: { "x-api-key": token, "anthropic-version": "2023-06-01" },
  });
  return res.ok;
}

async function validateCloudflare(token: string): Promise<boolean> {
  const res = await fetchWithTimeout(
    "https://api.cloudflare.com/client/v4/user/tokens/verify",
    { headers: { Authorization: `Bearer ${token}` } },
  );
  return res.ok;
}

async function validateStripe(token: string): Promise<boolean> {
  const res = await fetchWithTimeout("https://api.stripe.com/v1/balance", {
    headers: { Authorization: `Bearer ${token}` },
  });
  return res.ok;
}

async function validatePlausible(token: string): Promise<boolean> {
  const res = await fetchWithTimeout(
    "https://plausible.io/api/v1/stats/realtime/visitors?site_id=soleur.ai",
    { headers: { Authorization: `Bearer ${token}` } },
  );
  // 200 = valid token (may return 0 visitors), 401/403 = invalid
  return res.ok;
}

async function validateHetzner(token: string): Promise<boolean> {
  const res = await fetchWithTimeout(
    "https://api.hetzner.cloud/v1/servers?per_page=1",
    { headers: { Authorization: `Bearer ${token}` } },
  );
  return res.ok;
}

async function validateGithub(token: string): Promise<boolean> {
  const res = await fetchWithTimeout("https://api.github.com/user", {
    headers: { Authorization: `Bearer ${token}`, "User-Agent": "soleur" },
  });
  return res.ok;
}

async function validateDoppler(token: string): Promise<boolean> {
  const res = await fetchWithTimeout("https://api.doppler.com/v3/me", {
    headers: { Authorization: `Bearer ${token}` },
  });
  return res.ok;
}

async function validateResend(token: string): Promise<boolean> {
  const res = await fetchWithTimeout("https://api.resend.com/api-keys", {
    headers: { Authorization: `Bearer ${token}` },
  });
  return res.ok;
}

async function validateX(token: string): Promise<boolean> {
  const res = await fetchWithTimeout("https://api.x.com/2/users/me", {
    headers: { Authorization: `Bearer ${token}` },
  });
  return res.ok;
}

async function validateLinkedin(token: string): Promise<boolean> {
  const res = await fetchWithTimeout("https://api.linkedin.com/v2/userinfo", {
    headers: { Authorization: `Bearer ${token}` },
  });
  return res.ok;
}

async function validateBluesky(token: string): Promise<boolean> {
  // Use describeServer to avoid createSession side effect.
  // describeServer is unauthenticated, so we fall back to getProfile.
  const res = await fetchWithTimeout(
    "https://bsky.social/xrpc/app.bsky.actor.getProfile?actor=self",
    { headers: { Authorization: `Bearer ${token}` } },
  );
  return res.ok;
}

async function validateButtondown(token: string): Promise<boolean> {
  const res = await fetchWithTimeout(
    "https://api.buttondown.com/v1/emails?page_size=1",
    { headers: { Authorization: `Token ${token}` } },
  );
  return res.ok;
}

// --- Registry ---

const VALIDATORS: Partial<Record<Provider, (token: string) => Promise<boolean>>> = {
  anthropic: validateAnthropic,
  cloudflare: validateCloudflare,
  stripe: validateStripe,
  plausible: validatePlausible,
  hetzner: validateHetzner,
  github: validateGithub,
  doppler: validateDoppler,
  resend: validateResend,
  x: validateX,
  linkedin: validateLinkedin,
  bluesky: validateBluesky,
  buttondown: validateButtondown,
};

export async function validateToken(
  provider: Provider,
  token: string,
): Promise<boolean> {
  const validator = VALIDATORS[provider];
  if (!validator) return false;
  try {
    return await validator(token);
  } catch {
    // Timeout, network error, etc.
    return false;
  }
}
