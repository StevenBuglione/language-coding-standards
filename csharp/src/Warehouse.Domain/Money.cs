namespace Warehouse.Domain;

public readonly record struct Money
{
    public const long MaxMinorUnits = 9_007_199_254_740_991L;

    public Money(long minorUnits, string currency)
    {
        ArgumentNullException.ThrowIfNull(currency);
        if (minorUnits < 0)
        {
            throw new InvalidOrderException($"money amount must be non-negative, got {minorUnits}");
        }

        if (minorUnits > MaxMinorUnits)
        {
            throw new InvalidOrderException($"money amount exceeds {MaxMinorUnits}, got {minorUnits}");
        }

        if (!IsIsoStyleCurrency(currency))
        {
            throw new InvalidOrderException(
                $"currency must be a 3-letter uppercase ISO-style code, got {currency}");
        }

        MinorUnits = minorUnits;
        Currency = currency;
    }

    public long MinorUnits { get; }

    public string Currency { get; }

    public Money Add(Money other)
    {
        if (Currency != other.Currency)
        {
            throw new InvalidOrderException($"currency mismatch: {Currency} vs {other.Currency}");
        }

        long total;
        try
        {
            total = checked(MinorUnits + other.MinorUnits);
        }
        catch (OverflowException ex)
        {
            throw new InvalidOrderException("money addition overflows the shared maximum", ex);
        }

        if (total > MaxMinorUnits)
        {
            throw new InvalidOrderException("money addition overflows the shared maximum");
        }

        return new Money(total, Currency);
    }

    public Money Times(int multiplier)
    {
        if (multiplier < 0)
        {
            throw new InvalidOrderException($"multiplier must be non-negative, got {multiplier}");
        }

        long product;
        try
        {
            product = checked(MinorUnits * multiplier);
        }
        catch (OverflowException ex)
        {
            throw new InvalidOrderException("money scaling overflows the shared maximum", ex);
        }

        if (product > MaxMinorUnits)
        {
            throw new InvalidOrderException("money scaling overflows the shared maximum");
        }

        return new Money(product, Currency);
    }

    private static bool IsIsoStyleCurrency(string currency)
    {
        return currency.Length == 3
            && char.IsAsciiLetterUpper(currency[0])
            && char.IsAsciiLetterUpper(currency[1])
            && char.IsAsciiLetterUpper(currency[2]);
    }
}
