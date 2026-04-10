import type { DomainLeaderId } from "@/server/domain-leaders";

/** Tailwind border-left color classes for each domain leader. */
export const LEADER_COLORS: Record<DomainLeaderId, string> = {
  cmo: "border-l-pink-500",
  cto: "border-l-blue-500",
  cfo: "border-l-green-500",
  cpo: "border-l-purple-500",
  cro: "border-l-orange-500",
  coo: "border-l-yellow-500",
  clo: "border-l-red-500",
  cco: "border-l-teal-500",
  system: "border-l-neutral-500",
};

/** Tailwind background color classes for leader avatar badges. */
export const LEADER_BG_COLORS: Record<DomainLeaderId, string> = {
  cmo: "bg-pink-500",
  cto: "bg-blue-500",
  cfo: "bg-green-500",
  cpo: "bg-purple-500",
  cro: "bg-orange-500",
  coo: "bg-yellow-500",
  clo: "bg-red-500",
  cco: "bg-teal-500",
  system: "bg-neutral-500",
};
