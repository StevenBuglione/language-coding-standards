/**
 * Unit tests for the Quantity value object invariant.
 */

import { describe, expect, it } from "vitest";

import { Quantity, QUANTITY_MAX } from "../../src/domain/quantity";

describe("Quantity", () => {
  it("accepts strictly positive values", () => {
    expect(Quantity.create(1).value).toBe(1);
  });

  it("accepts the shared maximum", () => {
    expect(Quantity.create(QUANTITY_MAX).value).toBe(QUANTITY_MAX);
  });

  it("rejects zero", () => {
    expect(() => Quantity.create(0)).toThrow(/strictly positive/);
  });

  it("rejects negative values", () => {
    expect(() => Quantity.create(-3)).toThrow(/strictly positive/);
  });

  it("rejects fractional values", () => {
    expect(() => Quantity.create(1.5)).toThrow(/strictly positive/);
  });

  it("rejects values above the shared maximum", () => {
    expect(() => Quantity.create(QUANTITY_MAX + 1)).toThrow(/exceeds/);
  });
});
