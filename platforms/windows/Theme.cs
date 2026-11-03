using System;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace AutoWifi.Windows;

/// <summary>
/// Replaces the brush tokens from <c>Styles.xaml</c> with values that follow
/// the Windows light/dark setting and the user's accent colour. WPF on .NET
/// Framework has no built-in dark theme, so the palette is applied by hand and
/// refreshed when the system preference changes.
/// </summary>
public static class Theme
{
    private static bool _watching;

    public static void Apply()
    {
        var resources = System.Windows.Application.Current?.Resources;
        if (resources is null)
        {
            return;
        }

        var dark = IsDark();
        var accent = AccentColor();
        var hover = dark ? Lighten(accent, 1.18) : Darken(accent, 0.86);

        Set(resources, "BackgroundBrush", dark ? "#1E1E1E" : "#F6F6F6");
        Set(resources, "SurfaceBrush", dark ? "#2A2A2C" : "#FFFFFF");
        Set(resources, "FieldBrush", dark ? "#1A1A1C" : "#FFFFFF");
        Set(resources, "HoverBrush", dark ? "#3A3A3C" : "#F0F0F2");
        Set(resources, "PressedBrush", dark ? "#454547" : "#E6E6E8");
        Set(resources, "TextBrush", dark ? "#F2F2F7" : "#1C1C1E");
        Set(resources, "SecondaryTextBrush", dark ? "#A1A1A6" : "#6E6E73");
        Set(resources, "TertiaryTextBrush", dark ? "#7C7C80" : "#9A9AA0");
        Set(resources, "SeparatorBrush", dark ? "#3A3A3C" : "#E2E2E6");
        Set(resources, "SegmentTrackBrush", dark ? "#333335" : "#EDEDF0");
        Set(resources, "SegmentSelectedBrush", dark ? "#5A5A5E" : "#FFFFFF");
        Set(resources, "ControlTrackBrush", dark ? "#5A5A5E" : "#D2D2D7");
        Set(resources, "AccentBrush", accent);
        Set(resources, "AccentHoverBrush", hover);
        Set(resources, "AccentSoftBrush", Color.FromArgb(0x22, accent.R, accent.G, accent.B));
        Set(resources, "AccentTextBrush", Colors.White);
        Set(resources, "DangerBrush", dark ? "#FF6B6B" : "#D70015");
        Set(resources, "WarningBrush", dark ? "#FFB340" : "#C93400");
        Set(resources, "SuccessBrush", dark ? "#4CD964" : "#248A3D");
        Set(resources, "BadgeBrush", dark ? "#2EFFFFFF" : "#14000000");
    }

    public static void Watch()
    {
        if (_watching)
        {
            return;
        }

        _watching = true;
        try
        {
            SystemEvents.UserPreferenceChanged += (_, _) =>
            {
                var app = System.Windows.Application.Current;
                app?.Dispatcher.BeginInvoke(new Action(Apply));
            };
        }
        catch
        {
            // SystemEvents is unavailable in some hosted environments; the
            // palette still applies at startup.
        }
    }

    private static bool IsDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
        }
        catch
        {
            return false;
        }
    }

    private static Color AccentColor()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\DWM");
            if (key?.GetValue("AccentColor") is int value)
            {
                // AccentColor is stored as 0xAABBGGRR.
                var r = (byte)(value & 0xFF);
                var g = (byte)((value >> 8) & 0xFF);
                var b = (byte)((value >> 16) & 0xFF);
                if (r + g + b > 30)
                {
                    return Color.FromRgb(r, g, b);
                }
            }
        }
        catch
        {
            // Fall through to the default Windows accent.
        }

        return Color.FromRgb(0x00, 0x78, 0xD4);
    }

    private static Color Lighten(Color color, double factor)
    {
        return Color.FromRgb(
            (byte)Math.Min(255, color.R * factor),
            (byte)Math.Min(255, color.G * factor),
            (byte)Math.Min(255, color.B * factor));
    }

    private static Color Darken(Color color, double factor)
    {
        return Color.FromRgb(
            (byte)(color.R * factor),
            (byte)(color.G * factor),
            (byte)(color.B * factor));
    }

    private static void Set(ResourceDictionary resources, string key, string hex)
    {
        Set(resources, key, (Color)ColorConverter.ConvertFromString(hex));
    }

    private static void Set(ResourceDictionary resources, string key, Color color)
    {
        resources[key] = new SolidColorBrush(color);
    }
}
