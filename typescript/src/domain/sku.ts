/**
 * Sku value object: a non-empty stock-keeping-unit code.
 */

import { InvalidOrder } from "./errors";

declare const brand: unique symbol;

const END_WHITESPACE = new Set([" ", "\t", "\r", "\n"]);

/**
 * UTF-8 byte-length ceiling for a normalized SKU code.
 */
export const SKU_MAX_UTF8_BYTES = 64;

/**
 * Branded stock-keeping-unit code.
 *
 * The brand makes raw strings and validated SKU codes structurally
 * incompatible, so a map keyed by {@link Sku} can never be poisoned by an
 * unvalidated string (and vice versa).
 */
export type Sku = string & { readonly [brand]: "Sku" };

/**
 * Strips only ASCII space, tab, CR, and LF from both ends.
 *
 * @param code - the raw SKU text.
 * @returns the code with ASCII edge whitespace removed; interior text and
 * U+00A0 are preserved.
 */
export function normalizeSkuCode(code: string): string {
  let start = 0;
  let end = code.length;
  while (start < end && END_WHITESPACE.has(code[start] ?? "")) {
    start += 1;
  }
  while (end > start && END_WHITESPACE.has(code[end - 1] ?? "")) {
    end -= 1;
  }
  return code.slice(start, end);
}

/**
 * Creates a validated, normalized `Sku`, raising `InvalidOrder` on violation.
 *
 * @param code - the raw code; only ASCII space/tab/CR/LF are stripped from
 * the ends. Case and interior text are preserved.
 * @returns the branded, normalized code.
 * @throws InvalidOrder when the code is empty after normalization or exceeds
 * {@link SKU_MAX_UTF8_BYTES} UTF-8 bytes.
 */
export function createSku(code: string): Sku {
  const trimmed = normalizeSkuCode(code);
  if (trimmed.length === 0) {
    throw new InvalidOrder("sku code must be non-empty");
  }
  if (utf8ByteLength(trimmed) > SKU_MAX_UTF8_BYTES) {
    throw new InvalidOrder(`sku code exceeds ${String(SKU_MAX_UTF8_BYTES)} UTF-8 bytes`);
  }
  return trimmed as Sku;
}

function utf8ByteLength(value: string): number {
  let bytes = 0;
  for (const char of value) {
    const codePoint = char.codePointAt(0) ?? 0;
    if (codePoint <= 127) {
      bytes += 1;
    } else if (codePoint <= 2047) {
      bytes += 2;
    } else if (codePoint <= 65_535) {
      bytes += 3;
    } else {
      bytes += 4;
    }
  }
  return bytes;
}
