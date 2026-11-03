using System.Diagnostics;

namespace AutoWifi.Windows;

/// <summary>
/// Shims for APIs that .NET Framework 4.8 does not provide.
/// </summary>
internal static class Compat
{
    public static int Clamp(int value, int min, int max) =>
        value < min ? min : (value > max ? max : value);

    /// <summary>
    /// `Environment.ProcessPath` is .NET 6+; this is its .NET Framework
    /// equivalent. It can throw in constrained environments, so it never
    /// propagates.
    /// </summary>
    public static string? ProcessPath
    {
        get
        {
            try
            {
                using (var process = Process.GetCurrentProcess())
                {
                    return process.MainModule?.FileName;
                }
            }
            catch
            {
                return null;
            }
        }
    }
}
