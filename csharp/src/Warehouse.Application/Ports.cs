using Warehouse.Domain;

namespace Warehouse.Application;

public readonly record struct ReservationToken(OrderId OrderId, string IdempotencyKey);

public readonly record struct ChargeReceipt(OrderId OrderId, string IdempotencyKey);

public readonly record struct IdempotencyRecord(string Fingerprint, Order Order);

public abstract record ReservationResult
{
    public sealed record Reserved(ReservationToken Token) : ReservationResult;

    public sealed record Shortage(InsufficientStock Error) : ReservationResult;
}

public abstract record ReleaseResult
{
    public sealed record Released : ReleaseResult;

    public sealed record Failed(CompensationFailure Error) : ReleaseResult;
}

public abstract record ChargeResult
{
    public sealed record Charged(ChargeReceipt Receipt) : ChargeResult;

    public sealed record Declined(PaymentDeclined Error) : ChargeResult;
}

public abstract record RefundResult
{
    public sealed record Refunded : RefundResult;

    public sealed record Failed(CompensationFailure Error) : RefundResult;
}

public abstract record SaveResult
{
    public sealed record Saved(Order Snapshot) : SaveResult;

    public sealed record Conflict(PersistenceConflict Error) : SaveResult;
}

public interface IOrderIdGenerator
{
    OrderId Next();
}

public interface IInventoryGateway
{
    ReservationResult ReserveAll(OrderId orderId, IReadOnlyList<OrderLine> lines, string idempotencyKey);

    ReleaseResult Release(ReservationToken token);
}

public interface IPaymentProcessor
{
    ChargeResult Charge(Order order, string idempotencyKey);

    RefundResult Refund(ChargeReceipt receipt);
}

public interface IOrderRepository
{
    SaveResult Save(Order order, int expectedVersion);

    Order? Get(OrderId orderId);

    IdempotencyRecord? GetByIdempotencyKey(string key);

    void RememberIdempotency(string key, string fingerprint, Order order);
}
