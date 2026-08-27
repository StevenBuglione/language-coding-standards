using Warehouse.Application;
using Warehouse.Domain;

namespace Warehouse.Adapters;

public sealed class FakePaymentProcessor : IPaymentProcessor
{
    private readonly object _gate = new();
    private readonly bool _decline;
    private readonly List<Order> _chargedOrders = [];
    private readonly List<ChargeReceipt> _refunded = [];
    private readonly Dictionary<string, ChargeResult> _outcomes = [];
    private bool _failRefund;

    public FakePaymentProcessor(bool decline = false)
    {
        _decline = decline;
    }

    public bool FailRefund
    {
        get
        {
            lock (_gate)
            {
                return _failRefund;
            }
        }

        set
        {
            lock (_gate)
            {
                _failRefund = value;
            }
        }
    }

    public IReadOnlyList<Order> ChargedOrders
    {
        get
        {
            lock (_gate)
            {
                return [.. _chargedOrders];
            }
        }
    }

    public IReadOnlyList<ChargeReceipt> Refunded
    {
        get
        {
            lock (_gate)
            {
                return [.. _refunded];
            }
        }
    }

    public ChargeResult Charge(Order order, string idempotencyKey)
    {
        ArgumentNullException.ThrowIfNull(order);
        ArgumentNullException.ThrowIfNull(idempotencyKey);
        lock (_gate)
        {
            if (_outcomes.TryGetValue(idempotencyKey, out ChargeResult? existing))
            {
                return existing;
            }

            _chargedOrders.Add(order);
            if (_decline)
            {
                ChargeResult declined = new ChargeResult.Declined(
                    new PaymentDeclined($"payment declined for order {order.Id.Value}"));
                _outcomes[idempotencyKey] = declined;
                return declined;
            }

            var receipt = new ChargeReceipt(order.Id, idempotencyKey);
            ChargeResult charged = new ChargeResult.Charged(receipt);
            _outcomes[idempotencyKey] = charged;
            return charged;
        }
    }

    public RefundResult Refund(ChargeReceipt receipt)
    {
        lock (_gate)
        {
            if (_failRefund)
            {
                return new RefundResult.Failed(new CompensationFailure("refund", "forced failure"));
            }

            _refunded.Add(receipt);
            return new RefundResult.Refunded();
        }
    }
}
