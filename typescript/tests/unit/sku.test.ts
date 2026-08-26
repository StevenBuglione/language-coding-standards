/**
 * Unit tests for the Sku value object invariant.
 */

import { describe, expect, it } from "vitest";

import { createSku } from "../../src/domain/sku";

describe("createSku", () => {
  it("trims surrounding whitespace", () => {
    expect(createSku("  ABC-1  ")).toBe("ABC-1");
  });

  it("rejects blank-after-trim codes", () => {
    expect(() => createSku(" ".repeat(3))).toThrow(/non-empty/);
  });

  it("rejects the empty string", () => {
    expect(() => createSku("")).toThrow(/non-empty/);
  });
});
