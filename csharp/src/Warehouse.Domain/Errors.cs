namespace Warehouse.Domain;

public abstract class DomainException : Exception
{
    protected DomainException(string message)
        : base(message)
    {
    }

    protected DomainException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public sealed class InvalidOrderException : DomainException
{
    public InvalidOrderException(string message)
        : base(message)
    {
    }

    public InvalidOrderException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

public sealed class InsufficientStock : DomainException
{
    public InsufficientStock(Sku sku, Quantity requested, int available)
        : base($"insufficient stock for {sku.Code}: requested {requested.Value}, available {available}")
    {
        Sku = sku;
        Requested = requested;
        Available = available;
    }

    public Sku Sku { get; }

    public Quantity Requested { get; }

    public int Available { get; }
}

public sealed class PaymentDeclined : DomainException
{
    public PaymentDeclined(string message)
        : base(message)
    {
    }
}

public sealed class PersistenceConflict : DomainException
{
    public PersistenceConflict(string message)
        : base(message)
    {
    }
}

public sealed class InfrastructureFailure : DomainException
{
    public InfrastructureFailure(string stage, bool retryable, string detail)
        : base($"{stage}: {detail}")
    {
        Stage = stage;
        Retryable = retryable;
        Detail = detail;
    }

    public string Stage { get; }

    public bool Retryable { get; }

    public string Detail { get; }
}

public sealed class CompensationFailure : DomainException
{
    public CompensationFailure(string stage, string detail)
        : base($"compensation failed at {stage}: {detail}")
    {
        Stage = stage;
        Detail = detail;
    }

    public string Stage { get; }

    public string Detail { get; }
}

public sealed class OrderAlreadyShipped : DomainException
{
    public OrderAlreadyShipped(string message)
        : base(message)
    {
    }
}
