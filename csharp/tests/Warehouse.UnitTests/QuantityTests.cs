using Warehouse.Domain;

namespace Warehouse.UnitTests;

public sealed class QuantityTests
{
    [Fact]
    public void AcceptsStrictlyPositiveValue()
    {
        Assert.Equal(1, new Quantity(1).Value);
    }

    [Fact]
    public void AcceptsSharedMaximum()
    {
        Assert.Equal(Quantity.MaxValue, new Quantity(Quantity.MaxValue).Value);
    }

    [Fact]
    public void RejectsZero()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => new Quantity(0));
        Assert.Contains("strictly positive", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RejectsNegative()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => new Quantity(-3));
        Assert.Contains("strictly positive", error.Message, StringComparison.Ordinal);
    }
}
