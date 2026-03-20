const PRODUCTION_ORIGINS = new Set(["https://app.soleur.ai"]);
const DEV_ORIGINS = new Set(["https://app.soleur.ai", "http://localhost:3000"]);

export function getAllowedOrigins(): Set<string> {
  return process.env.NODE_ENV === "development" ? DEV_ORIGINS : PRODUCTION_ORIGINS;
}
