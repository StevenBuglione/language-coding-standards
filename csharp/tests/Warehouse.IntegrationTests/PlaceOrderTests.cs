using Warehouse.Adapters;
using Warehouse.Application;
using Warehouse.Domain;

namespace Warehouse.IntegrationTests;

public sealed class PlaceOrderTests
{
    private sealed record Pipeline(
        PlaceOrderUseCase UseCase,
        FakePaymentProcessor Payments,
        InMemoryOrderRepository Repository,
        InMemoryInventoryGateway Inventory);

    private static Pipeline Create(Dictionary<string, int> stock, bool decline = false, string orderId = "ord-1")
    {
        var initial = stock.ToDictionary(pair => new Sku(pair.Key), pair => pair.Value);
        var inventory = new InMemoryInventoryGateway(initial);
        var payments = new FakePaymentProcessor(decline);
        var repository = new InMemoryOrderRepository();
        var useCase = new PlaceOrderUseCase(
            inventory,
            payments,
            repository,
            new FixedOrderIdGenerator(new OrderId(orderId)));
        return new Pipeline(useCase, payments, repository, inventory);
    }

    private static List<OrderLine> Lines(params (string Code, int Qty, long MinorUnits)[] specs)
    {
        return specs
            .Select(spec => new OrderLine(
                new Sku(spec.Code),
                new Quantity(spec.Qty),
                new Money(spec.MinorUnits, "USD")))
            .ToList();
    }

    [Fact]
    public void HappyPathPersistsPaid()
    {
        Pipeline pipeline = Create(new Dictionary<string, int> { ["SKU-1"] = 10 });
        PlaceOrderResult result = pipeline.UseCase.Execute(Lines(("SKU-1", 2, 500)), "idem-1");

        var success = Assert.IsType<PlaceOrderResult.Success>(result);
        Assert.Equal(OrderStatus.Paid, success.Order.Status);
        Assert.Equal("ord-1", success.Order.Id.Value);
        Assert.Equal(new Money(1000, "USD"), success.Order.Total());
        Assert.Single(pipeline.Payments.ChargedOrders);
        Order? stored = pipeline.Repository.Get(success.Order.Id);
        Assert.NotNull(stored);
        Assert.Equal(OrderStatus.Paid, stored.Status);
        Assert.NotSame(stored, success.Order);
        Assert.Equal(8, pipeline.Inventory.SnapshotStock()[new Sku("SKU-1")]);
    }

    [Fact]
    public void InsufficientStockFailsWithoutChargeOrPersist()
    {
        Pipeline pipeline = Create(new Dictionary<string, int> { ["SKU-1"] = 1 });
        PlaceOrderResult result = pipeline.UseCase.Execute(Lines(("SKU-1", 5, 500)), "idem-2");

        var failure = Assert.IsType<PlaceOrderResult.Failure>(result);
        var stock = Assert.IsType<InsufficientStock>(failure.Error);
        Assert.Equal(1, stock.Available);
        Assert.Empty(pipeline.Payments.ChargedOrders);
        Assert.Empty(pipeline.Repository.Saved);
        Assert.Equal(1, pipeline.Inventory.SnapshotStock()[new Sku("SKU-1")]);
    }

    [Fact]
    public void PaymentDeclineReleasesReservation()
    {
        Pipeline pipeline = Create(new Dictionary<string, int> { ["SKU-1"] = 10 }, decline: true);
        PlaceOrderResult result = pipeline.UseCase.Execute(Lines(("SKU-1", 1, 500)), "idem-3");

        var failure = Assert.IsType<PlaceOrderResult.Failure>(result);
        Assert.IsType<PaymentDeclined>(failure.Error);
        Assert.Single(pipeline.Payments.ChargedOrders);
        Assert.Empty(pipeline.Repository.Saved);
        Assert.Equal(10, pipeline.Inventory.SnapshotStock()[new Sku("SKU-1")]);
    }

    [Fact]
    public void SaveFailureRefundsAndReleases()
    {
        Pipeline pipeline = Create(new Dictionary<string, int> { ["SKU-1"] = 10 });
        pipeline.Repository.FailSave = true;
        PlaceOrderResult result = pipeline.UseCase.Execute(Lines(("SKU-1", 1, 500)), "idem-4");

        var failure = Assert.IsType<PlaceOrderResult.Failure>(result);
        Assert.IsType<PersistenceConflict>(failure.Error);
        Assert.Single(pipeline.Payments.Refunded);
        Assert.Equal(10, pipeline.Inventory.SnapshotStock()[new Sku("SKU-1")]);
    }

    [Fact]
    public void CompensationFailureAfterSaveFailure()
    {
        Pipeline pipeline = Create(new Dictionary<string, int> { ["SKU-1"] = 10 });
        pipeline.Repository.FailSave = true;
        pipeline.Payments.FailRefund = true;
        PlaceOrderResult result = pipeline.UseCase.Execute(Lines(("SKU-1", 1, 500)), "idem-5");

        var failure = Assert.IsType<PlaceOrderResult.Failure>(result);
        Assert.IsType<CompensationFailure>(failure.Error);
    }

    [Fact]
    public void InvalidLinesFailValidation()
    {
        Pipeline pipeline = Create([]);
        PlaceOrderResult result = pipeline.UseCase.Execute([], "idem-6");

        var failure = Assert.IsType<PlaceOrderResult.Failure>(result);
        Assert.IsType<InvalidOrderException>(failure.Error);
    }

    [Fact]
    public void GetReturnsNullForUnknownId()
    {
        Pipeline pipeline = Create(new Dictionary<string, int> { ["SKU-1"] = 10 });
        Assert.Null(pipeline.Repository.Get(new OrderId("missing-order")));
    }

    [Fact]
    public void IdempotentReplayDoesNotDoubleCharge()
    {
        var inventory = new InMemoryInventoryGateway(new Dictionary<Sku, int> { [new Sku("SKU-1")] = 10 });
        var payments = new FakePaymentProcessor();
        var repository = new InMemoryOrderRepository();
        var useCase = new PlaceOrderUseCase(inventory, payments, repository, new SequenceOrderIdGenerator());
        PlaceOrderResult first = useCase.Execute(Lines(("SKU-1", 2, 300)), "idem-7");
        Assert.IsType<PlaceOrderResult.Success>(first);
        PlaceOrderResult second = useCase.Execute(Lines(("SKU-1", 2, 300)), "idem-7");
        Assert.IsType<PlaceOrderResult.Success>(second);
        Assert.Single(payments.ChargedOrders);
    }

    [Fact]
    public void ReusedKeyWithDifferentPayloadIsInvalid()
    {
        Pipeline pipeline = Create(new Dictionary<string, int> { ["SKU-1"] = 10, ["SKU-2"] = 10 });
        Assert.IsType<PlaceOrderResult.Success>(pipeline.UseCase.Execute(Lines(("SKU-1", 1, 100)), "idem-8"));
        PlaceOrderResult second = pipeline.UseCase.Execute(Lines(("SKU-2", 1, 100)), "idem-8");
        var failure = Assert.IsType<PlaceOrderResult.Failure>(second);
        Assert.IsType<InvalidOrderException>(failure.Error);
        Assert.Contains("idempotency key reused", failure.Error.Message, StringComparison.Ordinal);
    }
}
