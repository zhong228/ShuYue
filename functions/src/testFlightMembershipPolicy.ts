import {bindingGrantsEntitlement, lifetimeProductId, productionEnvironment, type EntitlementBinding} from "./entitlementPolicy.js";

/** Online check only: transport failures propagate and cannot grant cached access. */
export async function verifyCurrentLifetimeMembership<T extends EntitlementBinding & {productId: string}>(
  load: () => Promise<T[]>,
  refreshFromApple: (binding: T) => Promise<void>
): Promise<boolean> {
  const bindings = await load();
  for (const binding of bindings) {
    if (binding.environment === productionEnvironment && binding.productId === lifetimeProductId) {
      await refreshFromApple(binding);
    }
  }
  // A newer refund arriving while Apple was queried must take precedence.
  return (await load()).some(binding =>
    binding.productId === lifetimeProductId && bindingGrantsEntitlement(binding, productionEnvironment)
  );
}
