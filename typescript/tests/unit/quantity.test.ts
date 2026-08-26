/**
 * Unit tests for the Quantity value object invariant.
 */

import { describe, expect, it } from "vitest";

import { Quantity } from "../../src/domain/quantity";

describe("Quantity", () => {
  it("accepts strictly positive values", () => {
    expect(Quantity.create(1).value).toBe(1);
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
});
