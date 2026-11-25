using Xunit;

namespace Via.Windows.Tests;

public sealed class L10nTests
{
    [Fact]
    public void ReturnsLocalizedValuesForBothLanguages()
    {
        var original = L10n.Language;
        try
        {
            L10n.Language = "zh";
            Assert.Equal("状态", L10n.T("tab_status"));
            Assert.Equal("首选网络", L10n.T("role_priority"));

            L10n.Language = "en";
            Assert.Equal("Status", L10n.T("tab_status"));
            Assert.Equal("Preferred network", L10n.T("role_priority"));
        }
        finally
        {
            L10n.Language = original;
        }
    }

    [Fact]
    public void DurationsAndCountsAreReadable()
    {
        var original = L10n.Language;
        try
        {
            L10n.Language = "zh";
            Assert.Equal("1 分 30 秒", L10n.Duration(90));
            Assert.Equal("发现 1 个网络", L10n.NetworksFound(1));
            Assert.Equal("发现 3 个网络", L10n.NetworksFound(3));

            L10n.Language = "en";
            Assert.Equal("1 hr 30 min", L10n.Duration(5400));
            Assert.Equal("1 network found", L10n.NetworksFound(1));
        }
        finally
        {
            L10n.Language = original;
        }
    }

    [Fact]
    public void UnknownKeyReturnsTheKey()
    {
        Assert.Equal("missing_key", L10n.T("missing_key"));
    }
}
