using Xunit;

namespace Via.Windows.Tests;

public sealed class PackagingTests
{
    /// <summary>
    /// The portable exe ships alone, so the native core has to be embedded in
    /// the app assembly; <see cref="NativeCore"/> extracts it at startup.
    /// </summary>
    [Fact]
    public void PolicyCoreIsEmbeddedForThePortableBuild()
    {
        using var stream = typeof(PolicyEngine).Assembly
            .GetManifestResourceStream("via_core.dll");

        Assert.NotNull(stream);
        Assert.True(stream!.Length > 0);
    }
}
