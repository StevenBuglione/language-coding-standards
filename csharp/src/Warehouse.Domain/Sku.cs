using System.Text;

namespace Warehouse.Domain;

public readonly record struct Sku
{
    public const int MaxUtf8Bytes = 64;

    public Sku(string code)
    {
        ArgumentNullException.ThrowIfNull(code);
        string trimmed = StripAsciiEdges(code);
        if (trimmed.Length == 0)
        {
            throw new InvalidOrderException("sku code must be non-empty");
        }

        if (Encoding.UTF8.GetByteCount(trimmed) > MaxUtf8Bytes)
        {
            throw new InvalidOrderException($"sku code exceeds {MaxUtf8Bytes} UTF-8 bytes");
        }

        Code = trimmed;
    }

    public string Code { get; }

    private static string StripAsciiEdges(string code)
    {
        int start = 0;
        int end = code.Length;
        while (start < end && IsAsciiEdgeWhitespace(code[start]))
        {
            start++;
        }

        while (end > start && IsAsciiEdgeWhitespace(code[end - 1]))
        {
            end--;
        }

        return code[start..end];
    }

    private static bool IsAsciiEdgeWhitespace(char c) => c is ' ' or '\t' or '\r' or '\n';
}
