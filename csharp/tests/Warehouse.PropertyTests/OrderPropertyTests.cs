using Warehouse.Domain;

namespace Warehouse.PropertyTests;

public sealed class OrderPropertyTests
{
    public static TheoryData<OrderLine[]> ValidLineSets()
    {
        var data = new TheoryData<OrderLine[]>();
        int[] quantities = [1, 2, 5];
        long[] prices = [0L, 17L, 500L, 5000L];
        int seed = 0;
        foreach (int qty in quantities)
        {
            foreach (long price in prices)
            {
                seed++;
                data.Add(
                [
                    new OrderLine(new Sku($"SKU-{seed}"), new Quantity(qty), new Money(price, "USD")),
                ]);
                data.Add(
                [
                    new OrderLine(new Sku($"SKU-{seed}-A"), new Quantity(qty), new Money(price, "USD")),
                    new OrderLine(new Sku($"SKU-{seed}-B"), new Quantity(1), new Money(price + 1, "USD")),
                ]);
            }
        }

        return data;
    }

    [Theory]
    [MemberData(nameof(ValidLineSets))]
    public void TotalAlwaysEqualsSumOfLineTotals(OrderLine[] lines)
    {
        ArgumentNullException.ThrowIfNull(lines);
        var order = new Order(new OrderId("ord-prop"), lines);
        Money expected = lines[0].LineTotal;
        for (int i = 1; i < lines.Length; i++)
        {
            expected = expected.Add(lines[i].LineTotal);
        }

        Assert.Equal(expected, order.Total());
    }

    [Theory]
    [MemberData(nameof(ValidLineSets))]
    public void FullLifeCyclePreservesTotalAndLocksMutation(OrderLine[] lines)
    {
        ArgumentNullException.ThrowIfNull(lines);
        var order = new Order(new OrderId("ord-prop"), lines);
        Money originalTotal = order.Total();
        order.Pay();
        Assert.Equal(OrderStatus.Paid, order.Status);
        order.Ship();
        Assert.Equal(originalTotal, order.Total());
        Assert.Throws<OrderAlreadyShipped>(order.Pay);
    }
}
