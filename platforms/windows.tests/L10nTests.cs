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
            Assert.Equal("优先网络", L10n.T("role_priority"));

            L10n.Language = "en";
            Assert.Equal("Status", L10n.T("tab_status"));
            Assert.Equal("Priority", L10n.T("role_priority"));
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
