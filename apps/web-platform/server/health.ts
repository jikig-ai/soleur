import { readFileSync } from "fs";
import { serverUrl } from "@/lib/supabase/service";
import {
  getActiveSessionCount,
  getActiveWorkspaceCount,
} from "./session-metrics";

async function checkSupabase(): Promise<boolean> {
  try {
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY!;
    const response = await fetch(
      `${serverUrl()}/rest/v1/users?select=id&limit=1`,
      {
        headers: {
          apikey: key,
          Authorization: `Bearer ${key}`,
        },
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
  cpu_pct_1m: number;
  mem_pct: number;
  load_avg_1m: number;
  active_sessions: number;
  active_workspaces: number;
}

function readLoadAvg1m(): number {
  try {
    const raw = readFileSync("/proc/loadavg", "utf8").split(" ")[0];
    const parsed = parseFloat(raw);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
  } catch {
    return 0;
  }
}

// `/health` runs on the request hot path (Cloudflare probes + ci-deploy canary).
// A 1-second /proc/stat delta sampler (used by resource-monitor.sh on its 5-min
// systemd timer) would add 1s latency to every probe. Instead, approximate CPU
// utilization here as loadavg / nproc. This is a proxy — the authoritative
// time-windowed signal lives in resource-monitor.sh.
function readCpuPct1m(): number {
  try {
    const load = readLoadAvg1m();
    const cpuinfo = readFileSync("/proc/cpuinfo", "utf8");
    const cores = (cpuinfo.match(/^processor/gm) ?? []).length || 1;
    return Math.min(100, Math.max(0, Math.floor((load / cores) * 100)));
  } catch {
    return 0;
  }
}

// Use MemAvailable (reclaimable buffers/cache included) rather than
// MemTotal - MemFree; MemAvailable is the number that actually predicts OOM.
function readMemPct(): number {
  try {
    const info = readFileSync("/proc/meminfo", "utf8");
    const total = parseInt(info.match(/MemTotal:\s+(\d+)/)?.[1] ?? "0", 10);
    const available = parseInt(
      info.match(/MemAvailable:\s+(\d+)/)?.[1] ?? "0",
      10,
    );
    if (!Number.isFinite(total) || total === 0) return 0;
    return Math.min(100, Math.max(0, Math.floor(((total - available) * 100) / total)));
  } catch {
    return 0;
  }
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
    cpu_pct_1m: readCpuPct1m(),
    mem_pct: readMemPct(),
    load_avg_1m: readLoadAvg1m(),
    active_sessions: getActiveSessionCount(),
    active_workspaces: getActiveWorkspaceCount(),
  };
}
