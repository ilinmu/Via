namespace AutoWifi.Windows;

public sealed class AppSettings
{
    public string SsidP { get; set; } = "";
    public string SsidB { get; set; } = "";
    public int CheckInterval { get; set; } = 15;
    public bool Running { get; set; }
    public string Language { get; set; } = "zh";
    public bool LaunchAtLogin { get; set; }
    public bool SetupCompleted { get; set; }

    public AppSettings Clone() => (AppSettings)MemberwiseClone();

    public void Normalize()
    {
        SsidP = SsidP.Trim();
        SsidB = SsidB.Trim();
        CheckInterval = Math.Clamp(CheckInterval, 5, 3600);
        Language = Language == "en" ? "en" : "zh";
    }

    public bool IsComplete =>
        !string.IsNullOrWhiteSpace(SsidP) && !string.IsNullOrWhiteSpace(SsidB);
}

public enum WifiRole
{
    None = 0,
    Priority = 1,
    Backup = 2,
    Other = 3
}

public sealed record MonitorStatus(
    string? CurrentSsid,
    WifiRole Role,
    bool Running,
    string Message,
    DateTimeOffset? NextCheck);
