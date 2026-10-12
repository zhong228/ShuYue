interface OrderedTransaction {
  signedDate?: number;
  revocationDate?: unknown;
  purchaseDate?: {toMillis(): number} | null;
}

/** Renewal order precedes representation order; delivery order is neither. */
export function shouldApplyTransaction(
  existing: OrderedTransaction | undefined,
  incoming: OrderedTransaction,
  freshFromApple = false
): boolean {
  if (!existing) return true;
  const previousPurchase = existing.purchaseDate?.toMillis();
  const nextPurchase = incoming.purchaseDate?.toMillis();
  if (previousPurchase !== undefined && nextPurchase !== undefined && previousPurchase !== nextPurchase) {
    return nextPurchase > previousPurchase;
  }
  if (incoming.signedDate === undefined) return false;
  if (existing.signedDate === undefined) {
    // Legacy revoked records have no ordering information. Only a fresh,
    // server-fetched transaction may replace these (handled by the caller).
    return freshFromApple || !existing.revocationDate || !!incoming.revocationDate;
  }
  if (incoming.signedDate < existing.signedDate) return false;
  if (incoming.signedDate === existing.signedDate && existing.revocationDate && !incoming.revocationDate) {
    return false;
  }
  return true;
}
