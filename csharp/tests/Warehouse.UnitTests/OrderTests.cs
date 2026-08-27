using Warehouse.Domain;

namespace Warehouse.UnitTests;

public sealed class OrderTests
{
    private static OrderId Id(string value = "ord-1") => new(value);

    private static OrderLine Line(string code = "SKU-1", int qty = 2, long minorUnits = 500) =>
        new(new Sku(code), new Quantity(qty), new Money(minorUnits, "USD"));

    [Fact]
    public void RejectsEmptyLineSet()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(
            () => new Order(Id(), Array.Empty<OrderLine>()));
        Assert.Contains("at least one line", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RejectsDuplicateSkus()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(
            () => new Order(Id(), [Line("SKU-1"), Line("SKU-1")]));
        Assert.Contains("duplicate", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RejectsDuplicateSkusAfterNormalization()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(
            () => new Order(Id(), [Line("SKU-1"), Line(" SKU-1 ")]));
        Assert.Contains("duplicate", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void TotalEqualsSumOfLineTotals()
    {
        var order = new Order(Id(), [Line("SKU-1", 2, 500), Line("SKU-2", 1, 1000)]);
        Assert.Equal(new Money(2000, "USD"), order.Total());
    }

    [Fact]
    public void RejectsMixedCurrenciesAtConstruction()
    {
        OrderLine[] mixed =
        [
            Line("SKU-1"),
            new OrderLine(new Sku("SKU-2"), new Quantity(1), new Money(100, "EUR")),
        ];
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => new Order(Id(), mixed));
        Assert.Contains("mixed currencies", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void UsesInjectedId()
    {
        var order = new Order(Id("ord-fixed-9"), [Line()]);
        Assert.Equal("ord-fixed-9", order.Id.Value);
        Assert.Equal(OrderStatus.New, order.Status);
        Assert.Equal(0, order.Version);
    }

    [Fact]
    public void PayTransitionsNewToPaid()
    {
        var order = new Order(Id(), [Line()]);
        order.Pay();
        Assert.Equal(OrderStatus.Paid, order.Status);
    }

    [Fact]
    public void DoublePayIsInvalid()
    {
        var order = new Order(Id(), [Line()]);
        order.Pay();
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(order.Pay);
        Assert.Contains("already been paid", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ShipRequiresPaidState()
    {
        var order = new Order(Id(), [Line()]);
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(order.Ship);
        Assert.Contains("paid", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ShipTransitionsPaidToShipped()
    {
        var order = new Order(Id(), [Line()]);
        order.Pay();
        order.Ship();
        Assert.Equal(OrderStatus.Shipped, order.Status);
    }

    [Fact]
    public void PayAfterShipRaisesOrderAlreadyShipped()
    {
        var order = new Order(Id(), [Line()]);
        order.Pay();
        order.Ship();
        Assert.Throws<OrderAlreadyShipped>(order.Pay);
    }

    [Fact]
    public void ShipAfterShipRaisesOrderAlreadyShipped()
    {
        var order = new Order(Id(), [Line()]);
        order.Pay();
        order.Ship();
        Assert.Throws<OrderAlreadyShipped>(order.Ship);
    }

    [Fact]
    public void SnapshotDoesNotAliasMutableState()
    {
        var order = new Order(Id(), [Line()]);
        Order snapshot = order.Snapshot();
        order.Pay();
        Assert.Equal(OrderStatus.New, snapshot.Status);
        Assert.Equal(OrderStatus.Paid, order.Status);
    }
}
