using Warehouse.Application;
using Warehouse.Domain;

namespace Warehouse.Adapters;

public sealed class InMemoryOrderRepository : IOrderRepository
{
    private readonly object _gate = new();
    private readonly Dictionary<OrderId, Order> _orders = [];
    private readonly Dictionary<string, IdempotencyRecord> _byKey = [];
    private readonly List<Order> _saved = [];
    private bool _failSave;

    public bool FailSave
    {
        get
        {
            lock (_gate)
            {
                return _failSave;
            }
        }

        set
        {
            lock (_gate)
            {
                _failSave = value;
            }
        }
    }

    public IReadOnlyList<Order> Saved
    {
        get
        {
            lock (_gate)
            {
                return [.. _saved];
            }
        }
    }

    public SaveResult Save(Order order, int expectedVersion)
    {
        ArgumentNullException.ThrowIfNull(order);
        lock (_gate)
        {
            if (_failSave)
            {
                return new SaveResult.Conflict(
                    new PersistenceConflict($"forced save failure for {order.Id.Value}"));
            }

            int currentVersion = _orders.TryGetValue(order.Id, out Order? current) ? current.Version : 0;
            if (currentVersion != expectedVersion)
            {
                return new SaveResult.Conflict(
                    new PersistenceConflict(
                        $"version conflict for {order.Id.Value}: expected {expectedVersion}, stored {currentVersion}"));
            }

            Order stored = order.Snapshot();
            stored.BumpVersion();
            _orders[order.Id] = stored;
            Order returned = stored.Snapshot();
            _saved.Add(returned.Snapshot());
            return new SaveResult.Saved(returned);
        }
    }

    public void RememberIdempotency(string key, string fingerprint, Order order)
    {
        ArgumentNullException.ThrowIfNull(key);
        ArgumentNullException.ThrowIfNull(fingerprint);
        ArgumentNullException.ThrowIfNull(order);
        lock (_gate)
        {
            _byKey[key] = new IdempotencyRecord(fingerprint, order.Snapshot());
        }
    }

    public IdempotencyRecord? GetByIdempotencyKey(string key)
    {
        ArgumentNullException.ThrowIfNull(key);
        lock (_gate)
        {
            if (!_byKey.TryGetValue(key, out IdempotencyRecord found))
            {
                return null;
            }

            return found with { Order = found.Order.Snapshot() };
        }
    }

    public Order? Get(OrderId orderId)
    {
        lock (_gate)
        {
            if (!_orders.TryGetValue(orderId, out Order? stored))
            {
                return null;
            }

            return stored.Snapshot();
        }
    }
}
