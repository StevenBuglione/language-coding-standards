using Warehouse.Application;
using Warehouse.Domain;

namespace Warehouse.Adapters;

public sealed class SequenceOrderIdGenerator : IOrderIdGenerator
{
    private readonly string _prefix;
    private readonly object _gate = new();
    private int _n;

    public SequenceOrderIdGenerator(string prefix = "ord")
    {
        ArgumentNullException.ThrowIfNull(prefix);
        _prefix = prefix;
    }

    public OrderId Next()
    {
        lock (_gate)
        {
            _n++;
            return new OrderId($"{_prefix}-{_n}");
        }
    }
}

public sealed class FixedOrderIdGenerator : IOrderIdGenerator
{
    private readonly OrderId _orderId;

    public FixedOrderIdGenerator(OrderId orderId)
    {
        _orderId = orderId;
    }

    public OrderId Next() => _orderId;
}
