using System;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
// UseWindowsForms adds an implicit `System.Drawing` using, so the WPF colour
// type has to be named explicitly.
using Color = System.Windows.Media.Color;
using ColorConverter = System.Windows.Media.ColorConverter;

namespace Via.Windows;

/// <summary>
/// Replaces the brush tokens from <c>Styles.xaml</c> with values that follow
/// the Windows light/dark setting. WPF on .NET Framework has no built-in dark
/// theme, so the palette is applied by hand and refreshed when the system
/// preference changes.
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
        var accent = dark
            ? Color.FromRgb(0x3C, 0x7D, 0x6C)
            : Color.FromRgb(0x2E, 0x6B, 0x5C);
        var accentLink = dark
            ? Color.FromRgb(0x8C, 0xC4, 0xB2)
            : Color.FromRgb(0x2E, 0x6B, 0x5C);
        var hover = dark ? Lighten(accent, 1.18) : Darken(accent, 0.86);

        Set(resources, "BackgroundBrush", dark ? "#1B1A18" : "#F7F5F1");
        Set(resources, "SurfaceBrush", dark ? "#232120" : "#FFFFFF");
        Set(resources, "FieldBrush", dark ? "#232120" : "#FFFFFF");
        Set(resources, "HoverBrush", dark ? "#33302C" : "#EFEAE2");
        Set(resources, "PressedBrush", dark ? "#3D3934" : "#E6E0D6");
        Set(resources, "TextBrush", dark ? "#F2EEE8" : "#1F1D1A");
        Set(resources, "SecondaryTextBrush", dark ? "#A8A29A" : "#726D65");
        Set(resources, "TertiaryTextBrush", dark ? "#A8A29A" : "#726D65");
        Set(resources, "SeparatorBrush", dark ? "#3A3733" : "#E4DFD7");
        Set(resources, "SegmentTrackBrush", dark ? "#2E2B27" : "#EDE7DE");
        Set(resources, "SegmentSelectedBrush", dark ? "#3D3934" : "#FFFFFF");
        Set(resources, "ControlTrackBrush", dark ? "#5A554E" : "#C9C2B8");
        Set(resources, "AccentBrush", accent);
        Set(resources, "AccentLinkBrush", accentLink);
        Set(resources, "AccentHoverBrush", hover);
        Set(resources, "AccentSoftBrush", Color.FromArgb(0x22, accent.R, accent.G, accent.B));
        Set(resources, "AccentTextBrush", Colors.White);
        Set(resources, "DangerBrush", dark ? "#E58C82" : "#A33A32");
        Set(resources, "WarningBrush", dark ? "#E0A458" : "#A15C00");
        Set(resources, "SuccessBrush", accent);
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
