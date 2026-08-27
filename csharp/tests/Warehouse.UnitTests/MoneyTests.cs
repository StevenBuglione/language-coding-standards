using Warehouse.Domain;

namespace Warehouse.UnitTests;

public sealed class MoneyTests
{
    [Fact]
    public void RejectsNegativeAmount()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => new Money(-1, "USD"));
        Assert.Contains("non-negative", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RejectsMalformedCurrency()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => new Money(1, "usd"));
        Assert.Contains("currency", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void AddSumsSameCurrency()
    {
        Assert.Equal(new Money(425, "USD"), new Money(150, "USD").Add(new Money(275, "USD")));
    }

    [Fact]
    public void AddRejectsCurrencyMismatch()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(
            () => new Money(100, "USD").Add(new Money(100, "EUR")));
        Assert.Contains("mismatch", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void TimesScalesAmount()
    {
        Assert.Equal(new Money(750, "USD"), new Money(250, "USD").Times(3));
    }

    [Fact]
    public void TimesRejectsNegativeMultiplier()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => new Money(1, "USD").Times(-2));
        Assert.Contains("multiplier", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void EqualityIsValueBased()
    {
        Assert.Equal(new Money(10, "EUR"), new Money(10, "EUR"));
    }

    [Fact]
    public void AcceptsIsoStyleZzz()
    {
        Assert.Equal("ZZZ", new Money(0, "ZZZ").Currency);
    }

    [Fact]
    public void RejectsAboveSharedMaximum()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(
            () => new Money(9_007_199_254_740_992L, "USD"));
        Assert.Contains("exceeds", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void AddRejectsOverflow()
    {
        var max = new Money(Money.MaxMinorUnits, "USD");
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => max.Add(new Money(1, "USD")));
        Assert.Contains("overflows", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void TimesRejectsOverflow()
    {
        var amount = new Money(Money.MaxMinorUnits, "USD");
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => amount.Times(2));
        Assert.Contains("overflows", error.Message, StringComparison.Ordinal);
    }
}
