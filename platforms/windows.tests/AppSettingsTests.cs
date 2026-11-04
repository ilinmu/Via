using Xunit;

namespace Via.Windows.Tests;

public sealed class AppSettingsTests
{
    [Fact]
    public void NormalizeTrimsNetworksAndClampsInterval()
    {
        var settings = new AppSettings
        {
            SsidP = "  NetworkP  ",
            SsidB = "\tNetworkB\n",
            CheckInterval = 1,
            Language = "en"
        };

        settings.Normalize();

        Assert.Equal("NetworkP", settings.SsidP);
        Assert.Equal("NetworkB", settings.SsidB);
        Assert.Equal(5, settings.CheckInterval);
        Assert.Equal("en", settings.Language);
    }

    [Fact]
    public void NormalizeCapsIntervalAtOneHour()
    {
        var settings = new AppSettings { CheckInterval = 99_999 };

        settings.Normalize();

        Assert.Equal(3600, settings.CheckInterval);
    }

    [Theory]
    [InlineData("en", "en")]
    [InlineData("zh", "zh")]
    [InlineData("fr", "zh")]
    [InlineData("", "zh")]
    public void NormalizeFallsBackToChinese(string language, string expected)
    {
        var settings = new AppSettings { Language = language };

        settings.Normalize();

        Assert.Equal(expected, settings.Language);
    }

    [Fact]
    public void IsCompleteRequiresBothNetworks()
    {
        Assert.False(new AppSettings { SsidP = "P" }.IsComplete);
        Assert.False(new AppSettings { SsidB = "B" }.IsComplete);
        Assert.False(new AppSettings { SsidP = "  ", SsidB = "B" }.IsComplete);
        Assert.True(new AppSettings { SsidP = "P", SsidB = "B" }.IsComplete);
    }
}
