using System.Runtime.Serialization;

namespace AutoWifi.Windows;

[DataContract]
public sealed class AppSettings
{
    [DataMember(Order = 1)]
    public string SsidP { get; set; } = "";

    [DataMember(Order = 2)]
    public string SsidB { get; set; } = "";

    [DataMember(Order = 3)]
    public int CheckInterval { get; set; } = 15;

    [DataMember(Order = 4)]
    public bool Running { get; set; }

    [DataMember(Order = 5)]
    public string Language { get; set; } = "zh";

    [DataMember(Order = 6)]
    public bool LaunchAtLogin { get; set; }

    [DataMember(Order = 7)]
    public bool SetupCompleted { get; set; }

    public AppSettings Clone() => (AppSettings)MemberwiseClone();

    public void Normalize()
    {
        SsidP = SsidP.Trim();
        SsidB = SsidB.Trim();
        CheckInterval = Compat.Clamp(CheckInterval, 5, 3600);
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
