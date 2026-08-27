using Warehouse.Application;
using Warehouse.Domain;

namespace Warehouse.Adapters;

public sealed class InMemoryInventoryGateway : IInventoryGateway
{
    private readonly object _gate = new();
    private readonly Dictionary<Sku, int> _stock;
    private readonly Dictionary<string, List<(Sku Sku, int Amount)>> _reservations = [];
    private bool _failRelease;

    public InMemoryInventoryGateway(IReadOnlyDictionary<Sku, int>? stock = null)
    {
        _stock = stock is null ? [] : new Dictionary<Sku, int>(stock);
    }

    public bool FailRelease
    {
        get
        {
            lock (_gate)
            {
                return _failRelease;
            }
        }

        set
        {
            lock (_gate)
            {
                _failRelease = value;
            }
        }
    }

    public IReadOnlyDictionary<Sku, int> SnapshotStock()
    {
        lock (_gate)
        {
            return new Dictionary<Sku, int>(_stock);
        }
    }

    public ReservationResult ReserveAll(OrderId orderId, IReadOnlyList<OrderLine> lines, string idempotencyKey)
    {
        ArgumentNullException.ThrowIfNull(lines);
        ArgumentNullException.ThrowIfNull(idempotencyKey);
        lock (_gate)
        {
            if (_reservations.ContainsKey(idempotencyKey))
            {
                return new ReservationResult.Reserved(new ReservationToken(orderId, idempotencyKey));
            }

            var needed = new List<(Sku Sku, int Amount)>(lines.Count);
            foreach (OrderLine line in lines)
            {
                int available = _stock.GetValueOrDefault(line.Sku);
                if (available < line.Quantity.Value)
                {
                    return new ReservationResult.Shortage(
                        new InsufficientStock(line.Sku, line.Quantity, available));
                }

                needed.Add((line.Sku, line.Quantity.Value));
            }

            foreach ((Sku sku, int amount) in needed)
            {
                _stock[sku] = _stock[sku] - amount;
            }

            _reservations[idempotencyKey] = needed;
            return new ReservationResult.Reserved(new ReservationToken(orderId, idempotencyKey));
        }
    }

    public ReleaseResult Release(ReservationToken token)
    {
        lock (_gate)
        {
            if (_failRelease)
            {
                return new ReleaseResult.Failed(new CompensationFailure("release", "forced failure"));
            }

            if (!_reservations.Remove(token.IdempotencyKey, out List<(Sku Sku, int Amount)>? held))
            {
                return new ReleaseResult.Released();
            }

            foreach ((Sku sku, int amount) in held)
            {
                _stock[sku] = _stock.GetValueOrDefault(sku) + amount;
            }

            return new ReleaseResult.Released();
        }
    }
}
