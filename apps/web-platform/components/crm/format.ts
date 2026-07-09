// Shared CRM display formatters (feat-beta-crm-ui #6172). Extracted so the
// board card (pipeline-column) and the detail drawer (contact-detail-sheet)
// share ONE currency formatter instead of duplicating it (review P2-2).

/** Owner-currency amount, or "—" when unset. Never throws on a bad ISO code. */
export function formatAmount(
  amount: number | null,
  currency: string | null,
): string {
  if (amount == null) return "—";
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currency ?? "USD",
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    // Unknown/invalid currency code — never throw in render.
    return `${amount}${currency ? ` ${currency}` : ""}`;
  }
}
