using Warehouse.Domain;

namespace Warehouse.PropertyTests;

public sealed class MoneyPropertyTests
{
    private static readonly long[] Amounts = [0L, 1L, 17L, 250L, 9_007_199_254_740_990L];
    private static readonly string[] Currencies = ["USD", "EUR", "GBP"];

    [Fact]
    public void AdditionIsCommutativeAcrossSeededAmounts()
    {
        foreach (long left in Amounts)
        {
            foreach (long right in Amounts)
            {
                if (left > Money.MaxMinorUnits - right)
                {
                    continue;
                }

                var a = new Money(left, "USD");
                var b = new Money(right, "USD");
                Assert.Equal(a.Add(b), b.Add(a));
            }
        }
    }

    [Fact]
    public void ScalingDistributesOverAddition()
    {
        int[] scales = [0, 1, 2, 7, 100];
        foreach (long baseAmount in Amounts[..3])
        {
            foreach (int scale in scales)
            {
                foreach (int extra in scales)
                {
                    var money = new Money(baseAmount, "USD");
                    Money distributed = money.Times(scale).Add(money.Times(extra));
                    Assert.Equal(distributed, money.Times(scale + extra));
                }
            }
        }
    }

    [Fact]
    public void CrossCurrencyAdditionIsInvalid()
    {
        foreach (string leftCurrency in Currencies)
        {
            foreach (string rightCurrency in Currencies)
            {
                if (leftCurrency == rightCurrency)
                {
                    continue;
                }

                var left = new Money(100, leftCurrency);
                var right = new Money(100, rightCurrency);
                InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => left.Add(right));
                Assert.Contains("mismatch", error.Message, StringComparison.Ordinal);
            }
        }
    }

    [Fact]
    public void OverflowIsRejected()
    {
        var max = new Money(Money.MaxMinorUnits, "USD");
        Assert.Throws<InvalidOrderException>(() => max.Add(new Money(1, "USD")));
    }
}
