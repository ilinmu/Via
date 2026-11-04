using System.IO;
using System.Runtime.Serialization.Json;
using System.Text;
using Microsoft.Win32;

namespace Via.Windows;

public static class SettingsStore
{
    private static string SettingsDirectory =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Via");

    private static string SettingsPath => Path.Combine(SettingsDirectory, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
            {
                return new AppSettings();
            }

            var json = File.ReadAllText(SettingsPath);
            using (var stream = new MemoryStream(Encoding.UTF8.GetBytes(json)))
            {
                var serializer = new DataContractJsonSerializer(typeof(AppSettings));
                var settings = serializer.ReadObject(stream) as AppSettings ?? new AppSettings();
                settings.Normalize();
                return settings;
            }
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static void Save(AppSettings settings)
    {
        settings.Normalize();
        Directory.CreateDirectory(SettingsDirectory);
        using (var stream = new MemoryStream())
        {
            var serializer = new DataContractJsonSerializer(typeof(AppSettings));
            serializer.WriteObject(stream, settings);
            File.WriteAllText(SettingsPath, Encoding.UTF8.GetString(stream.ToArray()));
        }
    }
}

public static class StartupManager
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Via";

    public static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: false);
        return key?.GetValue(ValueName) is string value && !string.IsNullOrWhiteSpace(value);
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
            ?? Registry.CurrentUser.CreateSubKey(RunKey);

        if (key is null)
        {
            return;
        }

        if (enabled)
        {
            var executable = Compat.ProcessPath;
            if (!string.IsNullOrWhiteSpace(executable))
            {
                key.SetValue(ValueName, $"\"{executable}\"");
            }
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
