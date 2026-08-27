/**
 * Unit tests for the Sku value object invariant.
 */

import { describe, expect, it } from "vitest";

import { createSku, SKU_MAX_UTF8_BYTES } from "../../src/domain/sku";

describe("createSku", () => {
  it("strips ASCII space, tab, CR, and LF", () => {
    expect(createSku(" \tABC-1\r\n ")).toBe("ABC-1");
  });

  it("preserves interior spaces and case", () => {
    expect(createSku("sku a")).toBe("sku a");
  });

  it("keeps a leading U+00A0", () => {
    expect(createSku("\u{A0}ABC")).toBe("\u{A0}ABC");
  });

  it("allows 2-, 3-, and 4-byte UTF-8 characters within the limit", () => {
    expect(createSku("café")).toBe("café");
    expect(createSku("€")).toBe("€");
    expect(createSku("😀")).toBe("😀");
  });

  it("accepts a code at the UTF-8 byte limit", () => {
    expect(createSku("A".repeat(SKU_MAX_UTF8_BYTES))).toBe("A".repeat(SKU_MAX_UTF8_BYTES));
  });

  it("rejects codes over the UTF-8 byte limit", () => {
    expect(() => createSku("A".repeat(SKU_MAX_UTF8_BYTES + 1))).toThrow(/UTF-8 bytes/);
  });

  it("rejects blank-after-trim codes", () => {
    expect(() => createSku(" ".repeat(3))).toThrow(/non-empty/);
  });

  it("rejects the empty string", () => {
    expect(() => createSku("")).toThrow(/non-empty/);
  });
});
