import { readFileSync } from "fs";
import { cpus } from "os";
import { serverUrl } from "@/lib/supabase/service";
import {
  getActiveSessionCount,
  getActiveWorkspaceCount,
} from "./session-metrics";

// Cached at module load — cpu count never changes without a reboot, and this
// avoids parsing /proc/cpuinfo on every /internal/metrics request.
const CORE_COUNT = Math.max(1, cpus().length);

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

// Public /health response. INTENTIONALLY excludes capacity (CPU/RAM) and
// per-user count fields: those are competitive/attacker-useful and live on
// /internal/metrics behind a loopback Host-header gate (see server/index.ts).
export interface HealthResponse {
  status: string;
  version: string;
  supabase: string;
  sentry: string;
  uptime: number;
  memory: number;
}

// Internal metrics response. Served only on /internal/metrics to loopback
// callers (resource-monitor.sh sysd timer, curl 127.0.0.1:3000). Host-header
// gated in the route handler — capacity/session counts would otherwise let
// external attackers tune L7 load against WARN/CRIT thresholds and scrape
// concurrent user counts.
export interface InternalMetricsResponse extends HealthResponse {
  // loadavg-derived proxy for CPU; authoritative utilization is sampled in
  // resource-monitor.sh's /proc/stat delta on its 5-min systemd timer.
  cpu_load_pct: number;
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

function readCpuLoadPct(): number {
  const load = readLoadAvg1m();
  return Math.min(100, Math.max(0, Math.floor((load / CORE_COUNT) * 100)));
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
  };
}

export async function buildInternalMetricsResponse(): Promise<InternalMetricsResponse> {
  const base = await buildHealthResponse();
  return {
    ...base,
    cpu_load_pct: readCpuLoadPct(),
    mem_pct: readMemPct(),
    load_avg_1m: readLoadAvg1m(),
    active_sessions: getActiveSessionCount(),
    active_workspaces: getActiveWorkspaceCount(),
  };
}
