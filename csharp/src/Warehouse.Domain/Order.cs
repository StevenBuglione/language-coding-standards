namespace Warehouse.Domain;

public enum OrderStatus
{
    New,
    Paid,
    Shipped,
}

public readonly record struct OrderId
{
    public OrderId(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOrderException("order id must be non-empty");
        }

        Value = value;
    }

    public string Value { get; }
}

public readonly record struct OrderLine
{
    public OrderLine(Sku sku, Quantity quantity, Money unitPrice)
    {
        Sku = sku;
        Quantity = quantity;
        UnitPrice = unitPrice;
    }

    public Sku Sku { get; }

    public Quantity Quantity { get; }

    public Money UnitPrice { get; }

    public Money LineTotal => UnitPrice.Times(Quantity.Value);
}

public sealed class Order
{
    private readonly OrderLine[] _lines;

    public Order(OrderId id, IReadOnlyList<OrderLine> lines)
    {
        ArgumentNullException.ThrowIfNull(lines);
        if (lines.Count == 0)
        {
            throw new InvalidOrderException("an order requires at least one line");
        }

        var codes = new HashSet<string>(StringComparer.Ordinal);
        string currency = lines[0].UnitPrice.Currency;
        foreach (OrderLine line in lines)
        {
            if (!codes.Add(line.Sku.Code))
            {
                throw new InvalidOrderException("duplicate SKUs across order lines are not allowed");
            }

            if (line.UnitPrice.Currency != currency)
            {
                throw new InvalidOrderException("mixed currencies are not allowed");
            }
        }

        Id = id;
        _lines = [.. lines];
        Status = OrderStatus.New;
        Version = 0;
    }

    private Order(OrderId id, OrderLine[] lines, OrderStatus status, int version)
    {
        Id = id;
        _lines = lines;
        Status = status;
        Version = version;
    }

    public OrderId Id { get; }

    public OrderStatus Status { get; private set; }

    public int Version { get; private set; }

    public IReadOnlyList<OrderLine> Lines => _lines;

    public Money Total()
    {
        Money total = _lines[0].LineTotal;
        for (int i = 1; i < _lines.Length; i++)
        {
            total = total.Add(_lines[i].LineTotal);
        }

        return total;
    }

    public void Pay()
    {
        EnsureNotShipped();
        if (Status == OrderStatus.Paid)
        {
            throw new InvalidOrderException("order has already been paid");
        }

        Status = OrderStatus.Paid;
    }

    public void Ship()
    {
        EnsureNotShipped();
        if (Status != OrderStatus.Paid)
        {
            throw new InvalidOrderException("only paid orders can be shipped");
        }

        Status = OrderStatus.Shipped;
    }

    public void BumpVersion() => Version++;

    public Order Snapshot() => new(Id, _lines, Status, Version);

    private void EnsureNotShipped()
    {
        if (Status == OrderStatus.Shipped)
        {
            throw new OrderAlreadyShipped($"order {Id.Value} has already shipped");
        }
    }
}
