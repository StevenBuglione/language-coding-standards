using Warehouse.Domain;

namespace Warehouse.UnitTests;

public sealed class SkuTests
{
    [Fact]
    public void TrimsSurroundingWhitespace()
    {
        Assert.Equal("ABC-1", new Sku("  ABC-1  ").Code);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("\t\n")]
    [InlineData(" \r ")]
    public void RejectsBlankAfterTrim(string code)
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(() => new Sku(code));
        Assert.Contains("non-empty", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void StripsOnlyAsciiSpaceTabCrLf()
    {
        Assert.Equal("SKU-42", new Sku(" \t\r\nSKU-42 \t\r\n").Code);
    }

    [Fact]
    public void KeepsInteriorSpacingIntact()
    {
        Assert.Equal("SKU 42", new Sku("SKU 42").Code);
    }

    [Fact]
    public void PreservesCase()
    {
        Assert.Equal("sku-a", new Sku("sku-a").Code);
        Assert.NotEqual(new Sku("sku-a"), new Sku("SKU-A"));
    }

    [Fact]
    public void PreservesNbspPrefix()
    {
        Assert.Equal("\u00a0ABC", new Sku("\u00a0ABC").Code);
    }

    [Fact]
    public void AcceptsMaxUtf8Bytes()
    {
        Assert.Equal(Sku.MaxUtf8Bytes, new Sku(new string('A', Sku.MaxUtf8Bytes)).Code.Length);
    }

    [Fact]
    public void RejectsOverByteLimit()
    {
        InvalidOrderException error = Assert.Throws<InvalidOrderException>(
            () => new Sku(new string('A', Sku.MaxUtf8Bytes + 1)));
        Assert.Contains("UTF-8 bytes", error.Message, StringComparison.Ordinal);
    }
}
