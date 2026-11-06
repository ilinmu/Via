namespace Via.Windows;

public sealed class WifiService
{
    public string? GetCurrentSsid() => WlanApi.GetCurrentSsid();

    public (string? Previous, string? Current)[] TakeTransitions() =>
        WlanApi.TakeTransitions();

    public IReadOnlyList<string> Scan() => WlanApi.ScanNetworks();

    public bool? IsVisible(string ssid, CancellationToken token = default)
    {
        if (string.IsNullOrWhiteSpace(ssid))
        {
            return null;
        }

        var networks = WlanApi.ScanNetworks(token);
        if (networks.Count == 0)
        {
            // Empty might mean throttling or a Windows query failure. Never
            // convert it into a confirmed P loss.
            return null;
        }
        return networks.Any(
            candidate => string.Equals(candidate, ssid, StringComparison.Ordinal));
    }

    public bool Connect(string ssid, string? password, CancellationToken token = default)
    {
        return WlanApi.Connect(ssid, password, TimeSpan.FromSeconds(15), token);
    }
}
