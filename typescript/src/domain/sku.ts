/**
 * Sku value object: a non-empty trimmed stock-keeping-unit code.
 */

import { InvalidOrder } from "./errors";

declare const brand: unique symbol;

/**
 * Branded stock-keeping-unit code.
 *
 * The brand makes raw strings and validated SKU codes structurally
 * incompatible, so a map keyed by {@link Sku} can never be poisoned by an
 * unvalidated string (and vice versa).
 */
export type Sku = string & { readonly [brand]: "Sku" };

/**
 * Creates a validated, trimmed `Sku`, raising `InvalidOrder` on violation.
 *
 * @param code - the raw code; surrounding whitespace is normalized away.
 * @returns the branded, trimmed code.
 * @throws InvalidOrder when the code is empty after trimming.
 */
export function createSku(code: string): Sku {
  const trimmed = code.trim();
  if (trimmed.length === 0) {
    throw new InvalidOrder("sku code must be non-empty");
  }
  return trimmed as Sku;
}
