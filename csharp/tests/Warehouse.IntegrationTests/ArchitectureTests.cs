using Warehouse.Adapters;
using Warehouse.Application;
using Warehouse.Domain;

namespace Warehouse.IntegrationTests;

public sealed class ArchitectureTests
{
    [Fact]
    public void DomainDoesNotReferenceApplicationOrAdapters()
    {
        HashSet<string?> names = Referenced(typeof(Money).Assembly);
        Assert.DoesNotContain("Warehouse.Application", names);
        Assert.DoesNotContain("Warehouse.Adapters", names);
    }

    [Fact]
    public void ApplicationDoesNotReferenceAdapters()
    {
        HashSet<string?> names = Referenced(typeof(PlaceOrderUseCase).Assembly);
        Assert.DoesNotContain("Warehouse.Adapters", names);
        Assert.Contains("Warehouse.Domain", names);
    }

    [Fact]
    public void AdaptersMayReferenceApplicationAndDomain()
    {
        HashSet<string?> names = Referenced(typeof(InMemoryOrderRepository).Assembly);
        Assert.Contains("Warehouse.Application", names);
        Assert.Contains("Warehouse.Domain", names);
    }

    private static HashSet<string?> Referenced(System.Reflection.Assembly assembly)
    {
        return assembly.GetReferencedAssemblies().Select(name => name.Name).ToHashSet();
    }
}
