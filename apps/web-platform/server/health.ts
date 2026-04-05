async function checkSupabase(): Promise<boolean> {
  try {
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`,
      {
        headers: { apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "" },
        signal: AbortSignal.timeout(2000),
      },
    );
    return response.ok;
  } catch {
    return false;
  }
}

export interface HealthResponse {
  status: string;
  version: string;
  supabase: string;
  sentry: string;
  uptime: number;
  memory: number;
}

export async function buildHealthResponse(): Promise<HealthResponse> {
  const supabaseOk = await checkSupabase();
  return {
    status: "ok",
    version: process.env.BUILD_VERSION || "dev",
    supabase: supabaseOk ? "connected" : "error",
    sentry: process.env.SENTRY_DSN ? "configured" : "not-configured",
    uptime: Math.floor(process.uptime()),
    memory: Math.floor(process.memoryUsage().rss / 1024 / 1024),
  };
}
