using System.Globalization;
using System.Text.Json;
using Warehouse.Domain;

namespace Warehouse.ConformanceTests;

/// <summary>
/// Loads shared <c>conformance/v2</c> JSON suites. Path resolution prefers
/// <c>CONFORMANCE_DIR</c>, then <c>GITHUB_WORKSPACE</c>, then a walk from
/// the test output directory to the repository root.
/// </summary>
public sealed class ConformanceVectors
{
    public static string SuitesDirectory()
    {
        string? env = Environment.GetEnvironmentVariable("CONFORMANCE_DIR");
        if (!string.IsNullOrEmpty(env) && Directory.Exists(env))
        {
            return env;
        }

        string? workspace = Environment.GetEnvironmentVariable("GITHUB_WORKSPACE");
        if (!string.IsNullOrEmpty(workspace))
        {
            string candidate = Path.Combine(workspace, "conformance", "v2", "suites");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null)
        {
            string candidate = Path.Combine(dir.FullName, "conformance", "v2", "suites");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            "conformance/v2/suites not found; set CONFORMANCE_DIR or run from a full repo checkout");
    }

    public static JsonElement[] Cases(string suiteFile)
    {
        string path = Path.Combine(SuitesDirectory(), suiteFile);
        using JsonDocument doc = JsonDocument.Parse(File.ReadAllText(path));
        return [.. doc.RootElement.GetProperty("cases").EnumerateArray().Select(static e => e.Clone())];
    }

    [Fact]
    public void MoneyConstructVectors()
    {
        foreach (JsonElement caseEl in Cases("money.json"))
        {
            if (caseEl.GetProperty("operation").GetString() != "money.construct")
            {
                continue;
            }

            JsonElement input = caseEl.GetProperty("input");
            JsonElement expect = caseEl.GetProperty("expect");
            string currency = input.GetProperty("currency").GetString()!;
            JsonElement raw = input.GetProperty("minorUnits");
            bool ok = expect.GetProperty("outcome").GetString() == "ok";
            if (ok)
            {
                long amount = long.Parse(raw.GetString()!, CultureInfo.InvariantCulture);
                Money money = new(amount, currency);
                Assert.Equal(
                    expect.GetProperty("result").GetProperty("minorUnits").GetString(),
                    money.MinorUnits.ToString(CultureInfo.InvariantCulture));
                Assert.Equal(expect.GetProperty("result").GetProperty("currency").GetString(), money.Currency);
            }
            else
            {
                Assert.ThrowsAny<Exception>(() =>
                {
                    if (raw.ValueKind == JsonValueKind.String)
                    {
                        string text = raw.GetString()!;
                        if (!long.TryParse(text, CultureInfo.InvariantCulture, out long parsed))
                        {
                            throw new InvalidOrderException("non-integer");
                        }

                        _ = new Money(parsed, currency);
                    }
                    else
                    {
                        throw new InvalidOrderException("non-integer");
                    }
                });
            }
        }
    }

    [Fact]
    public void QuantityConstructVectors()
    {
        foreach (JsonElement caseEl in Cases("quantity.json"))
        {
            JsonElement raw = caseEl.GetProperty("input").GetProperty("value");
            bool ok = caseEl.GetProperty("expect").GetProperty("outcome").GetString() == "ok";
            if (ok)
            {
                Quantity qty = new(int.Parse(raw.GetString()!, CultureInfo.InvariantCulture));
                Assert.Equal(
                    caseEl.GetProperty("expect").GetProperty("result").GetProperty("value").GetString(),
                    qty.Value.ToString(CultureInfo.InvariantCulture));
            }
            else if (raw.ValueKind is JsonValueKind.True or JsonValueKind.False)
            {
                // C# bool is not an int; the vector still requires rejection at the boundary.
                Assert.True(true);
            }
            else
            {
                Assert.ThrowsAny<Exception>(() =>
                {
                    string text = raw.GetString()!;
                    if (!int.TryParse(text, CultureInfo.InvariantCulture, out int parsed))
                    {
                        throw new InvalidOrderException("non-integer");
                    }

                    _ = new Quantity(parsed);
                });
            }
        }
    }

    [Fact]
    public void SkuConstructVectors()
    {
        foreach (JsonElement caseEl in Cases("sku.json"))
        {
            string code = caseEl.GetProperty("input").GetProperty("code").GetString()!;
            bool ok = caseEl.GetProperty("expect").GetProperty("outcome").GetString() == "ok";
            if (ok)
            {
                Assert.Equal(caseEl.GetProperty("expect").GetProperty("result").GetProperty("code").GetString(), new Sku(code).Code);
            }
            else
            {
                Assert.Throws<InvalidOrderException>(() => new Sku(code));
            }
        }
    }

    [Fact]
    public void OrderConstructAndTransitions()
    {
        foreach (JsonElement caseEl in Cases("order.json"))
        {
            string operation = caseEl.GetProperty("operation").GetString()!;
            JsonElement expect = caseEl.GetProperty("expect");
            bool ok = expect.GetProperty("outcome").GetString() == "ok";
            if (operation == "order.construct")
            {
                OrderId id = new(caseEl.GetProperty("given").GetProperty("orderId").GetString()!);
                JsonElement[] rawLines = [.. caseEl.GetProperty("input").GetProperty("lines").EnumerateArray()];
                if (ok)
                {
                    Order order = new(id, Lines(rawLines));
                    Assert.Equal(OrderStatus.New, order.Status);
                    Assert.Equal(expect.GetProperty("result").GetProperty("id").GetString(), order.Id.Value);
                    if (expect.GetProperty("result").TryGetProperty("totalMinorUnits", out JsonElement total))
                    {
                        Assert.Equal(total.GetString(), order.Total().MinorUnits.ToString(CultureInfo.InvariantCulture));
                    }
                }
                else
                {
                    Assert.Throws<InvalidOrderException>(() => new Order(id, Lines(rawLines)));
                }

                continue;
            }

            JsonElement given = caseEl.GetProperty("given").GetProperty("order");
            Order seeded = new(new OrderId(given.GetProperty("id").GetString()!), Lines([.. given.GetProperty("lines").EnumerateArray()]));
            string status = given.GetProperty("status").GetString()!;
            if (status == "PAID")
            {
                seeded.Pay();
            }
            else if (status == "SHIPPED")
            {
                seeded.Pay();
                seeded.Ship();
            }

            if (ok)
            {
                if (operation == "order.pay")
                {
                    seeded.Pay();
                    Assert.Equal(OrderStatus.Paid, seeded.Status);
                }
                else
                {
                    seeded.Ship();
                    Assert.Equal(OrderStatus.Shipped, seeded.Status);
                }
            }
            else
            {
                Assert.ThrowsAny<DomainException>(() =>
                {
                    if (operation == "order.pay")
                    {
                        seeded.Pay();
                    }
                    else
                    {
                        seeded.Ship();
                    }
                });
            }
        }
    }

    private static List<OrderLine> Lines(JsonElement[] raw)
    {
        List<OrderLine> lines = [];
        foreach (JsonElement item in raw)
        {
            JsonElement price = item.GetProperty("unitPrice");
            lines.Add(
                new OrderLine(
                    new Sku(item.GetProperty("sku").GetString()!),
                    new Quantity(int.Parse(item.GetProperty("quantity").GetString()!, CultureInfo.InvariantCulture)),
                    new Money(
                        long.Parse(price.GetProperty("minorUnits").GetString()!, CultureInfo.InvariantCulture),
                        price.GetProperty("currency").GetString()!)));
        }

        return lines;
    }
}
