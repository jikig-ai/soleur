import type { EngineDataClass, EngineSelection } from "./agent-engine-contract";

export type VendorDpaStatus = "verified" | "unverified";
export type TransferGeography = "eea" | "adequacy" | "scc" | "unknown";
export type DeletionSupport = "verified" | "unsupported" | "unknown";

/** Evidence recorded by a reviewed engine definition before provider dispatch. */
export interface EngineDataEgressEvidence {
  endpoint: string;
  allowedHosts: readonly string[];
  acceptedDataClasses: readonly EngineDataClass[];
  vendorDpaStatus: VendorDpaStatus;
  transferGeography: TransferGeography;
  deletionSupport: DeletionSupport;
  approvalRequired: boolean;
  approvalGranted?: boolean;
}

/** Non-secret decision metadata suitable for an audit event. */
export interface EngineDataEgressDecision {
  endpoint: string;
  engineId: string;
  authMode: string;
  dataClass: EngineDataClass;
  vendorDpaStatus: VendorDpaStatus;
  transferGeography: Exclude<TransferGeography, "unknown">;
  deletionSupport: DeletionSupport;
  approvalRequired: boolean;
}

export class EngineDataEgressError extends Error {
  constructor(message: string, readonly code: "engine_egress_denied" | "engine_egress_approval_required") {
    super(message);
    this.name = "EngineDataEgressError";
  }
}

function deny(message: string): never {
  throw new EngineDataEgressError(message, "engine_egress_denied");
}

function normalizeEndpoint(endpoint: string, allowedHosts: readonly string[]): string {
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    return deny("engine egress endpoint is invalid");
  }
  if (url.protocol !== "https:" || url.username || url.password) {
    return deny("engine egress requires an HTTPS endpoint without URL credentials");
  }
  const hostname = url.hostname.toLowerCase();
  if (!allowedHosts.some((host) => host.toLowerCase() === hostname)) {
    return deny("engine egress endpoint is not allowlisted");
  }
  return url.toString();
}

/**
 * Makes the provider transfer decision immediately before dispatch. The
 * client never supplies this evidence; reviewed server-side composition does.
 */
export function authorizeEngineDataEgress(
  selection: EngineSelection,
  evidence: EngineDataEgressEvidence | undefined,
): EngineDataEgressDecision {
  if (!evidence) return deny("engine egress evidence is missing");
  const endpoint = normalizeEndpoint(evidence.endpoint, evidence.allowedHosts);
  if (!evidence.acceptedDataClasses.includes(selection.dataClass)) {
    return deny("engine egress data class is not qualified");
  }
  if (evidence.vendorDpaStatus !== "verified" || evidence.transferGeography === "unknown") {
    return deny("engine egress vendor transfer evidence is incomplete");
  }
  if (selection.dataClass === "customer" && evidence.deletionSupport !== "verified") {
    return deny("customer data requires verified provider deletion support");
  }
  if (evidence.approvalRequired && evidence.approvalGranted !== true) {
    throw new EngineDataEgressError("engine egress approval is required", "engine_egress_approval_required");
  }
  return {
    endpoint,
    engineId: selection.engineId,
    authMode: selection.authMode,
    dataClass: selection.dataClass,
    vendorDpaStatus: evidence.vendorDpaStatus,
    transferGeography: evidence.transferGeography,
    deletionSupport: evidence.deletionSupport,
    approvalRequired: evidence.approvalRequired,
  };
}
