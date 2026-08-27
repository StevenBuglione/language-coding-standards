namespace Warehouse.Domain;

public readonly record struct Quantity
{
    public const int MaxValue = int.MaxValue;

    public Quantity(int value)
    {
        if (value <= 0)
        {
            throw new InvalidOrderException($"quantity must be strictly positive, got {value}");
        }

        Value = value;
    }

    public int Value { get; }
}
