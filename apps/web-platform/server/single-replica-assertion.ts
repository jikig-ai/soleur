import { reportSilentFallback, warnSilentFallback } from "@/server/observability";

const ADR = "ADR-027";
const FEATURE = "single-replica-assertion";
const OVERRIDE_ENV = "ALLOW_MULTI_REPLICA";
const REPLICAS_ENV = "WEB_PLATFORM_REPLICAS";

export function assertSingleReplicaInvariant(): void {
  const raw = process.env[REPLICAS_ENV];
  if (raw === undefined || raw === "") return;

  const n = Number.parseInt(raw, 10);

  if (Number.isNaN(n)) {
    warnSilentFallback(null, {
      feature: FEATURE,
      op: "parse",
      message: `${REPLICAS_ENV}='${raw}' is not a valid integer. Defaulting to single-replica behavior. See ${ADR}.`,
      extra: { [REPLICAS_ENV]: raw },
    });
    return;
  }

  if (n <= 1) return;

  if (process.env[OVERRIDE_ENV] === "1") {
    warnSilentFallback(null, {
      feature: FEATURE,
      op: "override",
      message: `${REPLICAS_ENV}=${n} with ${OVERRIDE_ENV}=1 override. See ${ADR} for the migration path before removing the override.`,
      extra: { [REPLICAS_ENV]: n },
    });
    return;
  }

  // Sentry capture is best-effort: process.exit(1) below does not await
  // transport flush, so the breadcrumb can be dropped in flight. The pino
  // mirror inside reportSilentFallback writes synchronously to container
  // stdout — that is the durable signal per cq-silent-fallback-must-mirror-
  // to-sentry. Operators see the boot abort in container logs / Better Stack
  // regardless of Sentry transport state.
  reportSilentFallback(null, {
    feature: FEATURE,
    op: "abort",
    message:
      `${REPLICAS_ENV}=${n} violates the single-replica invariant. ` +
      `See ${ADR}. Set ${OVERRIDE_ENV}=1 (dev only) to bypass, or supersede ${ADR} with a migration plan before increasing replica count.`,
    extra: { [REPLICAS_ENV]: n },
  });
  process.exit(1);
}
