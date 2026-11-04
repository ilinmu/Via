namespace Via.Windows;

public sealed class WifiService
{
    public string? GetCurrentSsid() => WlanApi.GetCurrentSsid();

    public IReadOnlyList<string> Scan() => WlanApi.ScanNetworks();

    public bool IsVisible(string ssid)
    {
        if (string.IsNullOrWhiteSpace(ssid))
        {
            return false;
        }

        return WlanApi.ScanNetworks()
            .Any(candidate => string.Equals(candidate, ssid, StringComparison.Ordinal));
    }

    public bool Connect(string ssid, string? password)
    {
        return WlanApi.Connect(ssid, password, TimeSpan.FromSeconds(15));
    }
}
