import type { Provider } from "@/lib/types";

export interface ProviderConfig {
  envVar: string;
  category: "llm" | "infrastructure" | "social";
  label: string;
}

export const PROVIDER_CONFIG: Record<Provider, ProviderConfig> = {
  anthropic: { envVar: "ANTHROPIC_API_KEY", category: "llm", label: "Anthropic" },
  bedrock: { envVar: "AWS_ACCESS_KEY_ID", category: "llm", label: "AWS Bedrock" },
  vertex: { envVar: "GOOGLE_APPLICATION_CREDENTIALS", category: "llm", label: "Google Vertex" },
  cloudflare: { envVar: "CLOUDFLARE_API_TOKEN", category: "infrastructure", label: "Cloudflare" },
  stripe: { envVar: "STRIPE_SECRET_KEY", category: "infrastructure", label: "Stripe" },
  plausible: { envVar: "PLAUSIBLE_API_KEY", category: "infrastructure", label: "Plausible" },
  hetzner: { envVar: "HETZNER_API_TOKEN", category: "infrastructure", label: "Hetzner" },
  github: { envVar: "GITHUB_TOKEN", category: "infrastructure", label: "GitHub" },
  doppler: { envVar: "DOPPLER_TOKEN", category: "infrastructure", label: "Doppler" },
  resend: { envVar: "RESEND_API_KEY", category: "infrastructure", label: "Resend" },
  x: { envVar: "X_BEARER_TOKEN", category: "social", label: "X / Twitter" },
  linkedin: { envVar: "LINKEDIN_ACCESS_TOKEN", category: "social", label: "LinkedIn" },
  bluesky: { envVar: "BLUESKY_APP_PASSWORD", category: "social", label: "Bluesky" },
  buttondown: { envVar: "BUTTONDOWN_API_KEY", category: "social", label: "Buttondown" },
};

// Providers excluded from the Connected Services UI (multi-value credentials)
export const EXCLUDED_FROM_SERVICES_UI: ReadonlySet<Provider> = new Set([
  "bedrock",
  "vertex",
]);

// Providers available in the Connected Services page
export const SERVICE_PROVIDERS = (Object.keys(PROVIDER_CONFIG) as Provider[]).filter(
  (p) => !EXCLUDED_FROM_SERVICES_UI.has(p),
);
