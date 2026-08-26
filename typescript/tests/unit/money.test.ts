/**
 * Unit tests for the Money value object and its invariants.
 */

import { describe, expect, it } from "vitest";

import { InvalidOrder } from "../../src/domain/errors";
import { Money } from "../../src/domain/money";

describe("Money", () => {
  it("rejects negative amounts", () => {
    expect(() => Money.create(-1, "USD")).toThrow(InvalidOrder);
    expect(() => Money.create(-1, "USD")).toThrow(/non-negative/);
  });

  it("rejects fractional minor units", () => {
    expect(() => Money.create(10.5, "USD")).toThrow(/non-negative integer/);
  });

  it("rejects malformed currency codes", () => {
    expect(() => Money.create(1, "usd")).toThrow(/currency/);
    expect(() => Money.create(1, "USDD")).toThrow(/currency/);
  });

  it("adds same-currency amounts", () => {
    const sum = Money.create(150, "USD").add(Money.create(275, "USD"));
    expect(sum.equals(Money.create(425, "USD"))).toBe(true);
  });

  it("rejects currency mismatch", () => {
    expect(() => Money.create(100, "USD").add(Money.create(100, "EUR"))).toThrow(/mismatch/);
  });

  it("scales amounts", () => {
    const scaled = Money.create(250, "USD").times(3);
    expect(scaled.equals(Money.create(750, "USD"))).toBe(true);
  });

  it("rejects negative multipliers", () => {
    expect(() => Money.create(1, "USD").times(-2)).toThrow(/multiplier/);
  });

  it("compares by value", () => {
    expect(Money.create(10, "EUR").equals(Money.create(10, "EUR"))).toBe(true);
    expect(Money.create(10, "EUR").equals(Money.create(11, "EUR"))).toBe(false);
  });
});
