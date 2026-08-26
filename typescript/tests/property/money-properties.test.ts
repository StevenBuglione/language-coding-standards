/**
 * Property-based tests for Money arithmetic over randomly generated amounts.
 */

import fc from "fast-check";
import { describe, expect, it } from "vitest";

import { Money } from "../../src/domain/money";

const amounts = fc.nat(1_000_000_000);
const currencies = fc.constantFrom("USD", "EUR", "GBP");

describe("Money properties", () => {
  it("addition is commutative over random same-currency pairs", () => {
    fc.assert(
      fc.property(amounts, amounts, currencies, (leftAmount, rightAmount, currency) => {
        const left = Money.create(leftAmount, currency);
        const right = Money.create(rightAmount, currency);
        expect(left.add(right).equals(right.add(left))).toBe(true);
      }),
    );
  });

  it("scaling distributes over addition", () => {
    fc.assert(
      // Multipliers stay small so every product remains a safe integer —
      // the Money invariant rejects amounts beyond Number.MAX_SAFE_INTEGER.
      fc.property(
        amounts,
        fc.nat(1000),
        fc.nat(1000),
        currencies,
        (base, scale, extra, currency) => {
          const money = Money.create(base, currency);
          const distributed = money.times(scale).add(money.times(extra));
          expect(distributed.equals(money.times(scale + extra))).toBe(true);
        },
      ),
    );
  });

  it("cross-currency addition is always invalid", () => {
    fc.assert(
      fc.property(amounts, currencies, currencies, (amount, leftCurrency, rightCurrency) => {
        fc.pre(leftCurrency !== rightCurrency);
        const left = Money.create(amount, leftCurrency);
        const right = Money.create(amount, rightCurrency);
        expect(() => left.add(right)).toThrow(/mismatch/);
      }),
    );
  });
});
