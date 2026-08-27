using System.Globalization;
using System.Text;
using Warehouse.Domain;

namespace Warehouse.Application;

public abstract record PlaceOrderResult
{
    public sealed record Success(Order Order) : PlaceOrderResult;

    public sealed record Failure(DomainException Error) : PlaceOrderResult;
}

public sealed class PlaceOrderUseCase
{
    private readonly IInventoryGateway _inventory;
    private readonly IPaymentProcessor _payments;
    private readonly IOrderRepository _repository;
    private readonly IOrderIdGenerator _ids;

    public PlaceOrderUseCase(
        IInventoryGateway inventory,
        IPaymentProcessor payments,
        IOrderRepository repository,
        IOrderIdGenerator ids)
    {
        ArgumentNullException.ThrowIfNull(inventory);
        ArgumentNullException.ThrowIfNull(payments);
        ArgumentNullException.ThrowIfNull(repository);
        ArgumentNullException.ThrowIfNull(ids);
        _inventory = inventory;
        _payments = payments;
        _repository = repository;
        _ids = ids;
    }

    public PlaceOrderResult Execute(IReadOnlyList<OrderLine> lines, string idempotencyKey)
    {
        ArgumentNullException.ThrowIfNull(lines);
        ArgumentNullException.ThrowIfNull(idempotencyKey);
        string fingerprint = Fingerprint(lines);
        IdempotencyRecord? remembered = _repository.GetByIdempotencyKey(idempotencyKey);
        if (remembered is { } prior)
        {
            if (prior.Fingerprint != fingerprint)
            {
                return new PlaceOrderResult.Failure(
                    new InvalidOrderException("idempotency key reused with different payload"));
            }

            return new PlaceOrderResult.Success(prior.Order);
        }

        Order order;
        try
        {
            order = new Order(_ids.Next(), lines);
        }
        catch (InvalidOrderException error)
        {
            return new PlaceOrderResult.Failure(error);
        }

        ReservationResult reserved = _inventory.ReserveAll(order.Id, order.Lines, idempotencyKey);
        if (reserved is ReservationResult.Shortage shortage)
        {
            return new PlaceOrderResult.Failure(shortage.Error);
        }

        var reservedOk = (ReservationResult.Reserved)reserved;
        ChargeResult charged = _payments.Charge(order, idempotencyKey);
        if (charged is ChargeResult.Declined declined)
        {
            return ReleaseOrFail(reservedOk.Token, declined.Error);
        }

        var chargedOk = (ChargeResult.Charged)charged;
        try
        {
            order.Pay();
        }
        catch (InvalidOrderException error)
        {
            return Compensate(reservedOk.Token, chargedOk.Receipt, error);
        }

        SaveResult saved = _repository.Save(order, expectedVersion: 0);
        if (saved is SaveResult.Conflict conflict)
        {
            return Compensate(reservedOk.Token, chargedOk.Receipt, conflict.Error);
        }

        var savedOk = (SaveResult.Saved)saved;
        _repository.RememberIdempotency(idempotencyKey, fingerprint, savedOk.Snapshot);
        return new PlaceOrderResult.Success(savedOk.Snapshot);
    }

    private PlaceOrderResult ReleaseOrFail(ReservationToken token, DomainException error)
    {
        ReleaseResult released = _inventory.Release(token);
        if (released is ReleaseResult.Failed failed)
        {
            return new PlaceOrderResult.Failure(failed.Error);
        }

        return new PlaceOrderResult.Failure(error);
    }

    private PlaceOrderResult Compensate(ReservationToken token, ChargeReceipt receipt, DomainException error)
    {
        RefundResult refunded = _payments.Refund(receipt);
        if (refunded is RefundResult.Failed failedRefund)
        {
            return new PlaceOrderResult.Failure(failedRefund.Error);
        }

        return ReleaseOrFail(token, error);
    }

    private static string Fingerprint(IReadOnlyList<OrderLine> lines)
    {
        var builder = new StringBuilder();
        for (int i = 0; i < lines.Count; i++)
        {
            if (i > 0)
            {
                builder.Append('|');
            }

            OrderLine line = lines[i];
            builder.Append(line.Sku.Code);
            builder.Append(':');
            builder.Append(line.Quantity.Value.ToString(CultureInfo.InvariantCulture));
            builder.Append(':');
            builder.Append(line.UnitPrice.Currency);
            builder.Append(':');
            builder.Append(line.UnitPrice.MinorUnits.ToString(CultureInfo.InvariantCulture));
        }

        return builder.ToString();
    }
}
