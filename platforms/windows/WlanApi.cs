using System.Runtime.InteropServices;
using System.Security;
using System.Text;

namespace Via.Windows;

/// <summary>
/// Minimal native WLAN adapter built on wlanapi.dll. It covers the operations
/// the policy needs: read the current SSID, scan, and connect through a
/// per-network profile.
/// </summary>
public static class WlanApi
{
    private const int WlanIntfOpcodeCurrentConnection = 7;
    private const int WlanConnectionModeProfile = 0;
    private const int Dot11BssTypeInfrastructure = 1;
    private const uint ErrorSuccess = 0;
    private const int WlanNotificationSourceAcm = 0x8;
    private const int WlanNotificationAcmConnectionComplete = 10;
    private const int WlanNotificationAcmDisconnected = 21;
    private static readonly object Sync = new();
    private static WlanNotificationCallback? _notificationCallback;
    private static string? _lastCurrentSsid;
    private static readonly List<string> _recentTransitions = new();

    /// <summary>
    /// SSID transitions delivered by WlanRegisterNotification. Polling alone can
    /// compress P → disconnected → B into one observation and misclassify a
    /// lost priority network as a manual switch.
    /// </summary>
    public static (string? Previous, string? Current)[] TakeTransitions()
    {
        lock (Sync)
        {
            var count = _recentTransitions.Count / 2;
            var result = new (string? Previous, string? Current)[count];
            for (var index = 0; index < count; index++)
            {
                result[index] = (
                    DecodeSsid(_recentTransitions[index * 2]),
                    DecodeSsid(_recentTransitions[index * 2 + 1]));
            }
            _recentTransitions.Clear();
            return result;
        }
    }

    /// <summary>Registers connection notifications once and keeps the delegate alive.</summary>
    public static void EnsureNotifications()
    {
        IntPtr handle;
        WlanNotificationCallback callback;
        lock (Sync)
        {
            if (_notificationCallback != null)
            {
                return;
            }

            handle = OpenOwnedHandle();
            if (handle == IntPtr.Zero)
            {
                return;
            }

            // Install the baseline before registration. A callback can run
            // synchronously, and holding Sync across the native registration
            // would deadlock when it tried to take it.
            callback = OnNotification;
            _notificationCallback = callback;
            _lastCurrentSsid = GetCurrentSsid(handle, ownsHandle: false);
            _recentTransitions.Clear();
        }

        var result = WlanRegisterNotification(
            handle,
            WlanNotificationSourceAcm,
            true,
            callback,
            IntPtr.Zero,
            IntPtr.Zero,
            out _);
        if (result == ErrorSuccess)
        {
            // The handle stays open for the lifetime of the registration.
            return;
        }

        lock (Sync)
        {
            _notificationCallback = null;
            _lastCurrentSsid = null;
            _recentTransitions.Clear();
        }
        WlanCloseHandle(handle, IntPtr.Zero);
    }

    private static void OnNotification(
        ref WlanNotificationData notificationData,
        IntPtr context)
    {
        if (notificationData.NotificationSource != WlanNotificationSourceAcm)
        {
            return;
        }

        if (notificationData.NotificationCode != WlanNotificationAcmConnectionComplete &&
            notificationData.NotificationCode != WlanNotificationAcmDisconnected)
        {
            return;
        }

        // Never call a WLAN API from inside the notification callback. The
        // callback can run on the WLAN service's notification thread, and
        // re-entering WlanQueryInterface there risks deadlock. The notification
        // payload already carries the SSID for a completed connection.
        string? newSsid;
        if (notificationData.NotificationCode == WlanNotificationAcmDisconnected)
        {
            newSsid = null;
        }
        else if (!TryReadNotificationSsid(notificationData, out newSsid))
        {
            // The payload was unavailable; the regular poll will notice the
            // change without fabricating a transition.
            return;
        }

        lock (Sync)
        {
            if (_lastCurrentSsid == newSsid)
            {
                return;
            }
            _recentTransitions.Add(_lastCurrentSsid ?? "");
            _recentTransitions.Add(newSsid ?? "");
            _lastCurrentSsid = newSsid;
            // Bound the queue so a stopped service cannot grow it indefinitely.
            while (_recentTransitions.Count > 64)
            {
                _recentTransitions.RemoveRange(0, 2);
            }
        }
    }

    private static bool TryReadNotificationSsid(
        WlanNotificationData notificationData,
        out string? ssid)
    {
        ssid = null;
        if (notificationData.Data == IntPtr.Zero ||
            notificationData.DataSize < (uint)Marshal.SizeOf<WlanConnectionNotificationData>())
        {
            return false;
        }

        var data = Marshal.PtrToStructure<WlanConnectionNotificationData>(notificationData.Data);
        var value = SsidToString(data.dot11Ssid);
        if (value.Length == 0)
        {
            return false;
        }

        ssid = value;
        return true;
    }

    public static string? GetCurrentSsid() => GetCurrentSsid(OpenOwnedHandle(), ownsHandle: true);

    private static string? GetCurrentSsid(IntPtr handle, bool ownsHandle)
    {
        if (handle == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            var interfaceGuid = FindInterface(handle);
            if (interfaceGuid is null)
            {
                return null;
            }

            var guid = interfaceGuid.Value;
            var result = WlanQueryInterface(
                handle,
                ref guid,
                WlanIntfOpcodeCurrentConnection,
                IntPtr.Zero,
                out _,
                out var data,
                out _);
            if (result != ErrorSuccess || data == IntPtr.Zero)
            {
                return null;
            }

            try
            {
                var attributes = Marshal.PtrToStructure<WlanConnectionAttributes>(data);
                if (attributes.isState != 1)
                {
                    return null;
                }

                return SsidToString(attributes.wlanAssociationAttributes.dot11Ssid);
            }
            finally
            {
                WlanFreeMemory(data);
            }
        }
        finally
        {
            if (ownsHandle)
            {
                WlanCloseHandle(handle, IntPtr.Zero);
            }
        }
    }

    public static IReadOnlyList<string> ScanNetworks(CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        var handle = OpenOwnedHandle();
        if (handle == IntPtr.Zero)
        {
            return Array.Empty<string>();
        }

        try
        {
            var interfaceGuid = FindInterface(handle);
            if (interfaceGuid is null)
            {
                return Array.Empty<string>();
            }

            var guid = interfaceGuid.Value;
            if (WlanScan(handle, ref guid, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero) != ErrorSuccess)
            {
                return Array.Empty<string>();
            }

            // Scanning is asynchronous. A short settle period is enough for
            // the list query below and keeps the UI responsive on a worker.
            // Waiting on the token makes shutdown responsive instead of
            // blocking the monitor thread for the full settle time.
            WaitOrThrow(token, TimeSpan.FromMilliseconds(2500));

            // WLAN_AVAILABLE_NETWORK_INCLUDE_ALL_ADHOC_NETWORKS = 1 omitted;
            // infrastructure networks are the ones the policy can join.
            var result = WlanGetAvailableNetworkList(
                handle,
                ref guid,
                0,
                IntPtr.Zero,
                out var list);
            if (result != ErrorSuccess || list == IntPtr.Zero)
            {
                return Array.Empty<string>();
            }

            try
            {
                var count = (uint)Marshal.ReadInt32(list);
                var networkSize = Marshal.SizeOf<WlanAvailableNetwork>();
                var networks = new List<string>((int)Math.Min(count, 128));
                for (var index = 0; index < count; index++)
                {
                    var networkPointer = IntPtr.Add(list, 8 + index * networkSize);
                    var network = Marshal.PtrToStructure<WlanAvailableNetwork>(networkPointer);
                    var ssid = SsidToString(network.dot11Ssid);
                    if (!string.IsNullOrWhiteSpace(ssid) &&
                        !networks.Contains(ssid, StringComparer.Ordinal))
                    {
                        networks.Add(ssid);
                    }
                }
                return networks;
            }
            finally
            {
                WlanFreeMemory(list);
            }
        }
        finally
        {
            WlanCloseHandle(handle, IntPtr.Zero);
        }
    }

    public static bool Connect(
        string ssid,
        string? password,
        TimeSpan timeout,
        CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        var handle = OpenOwnedHandle();
        if (handle == IntPtr.Zero)
        {
            return false;
        }

        try
        {
            var interfaceGuid = FindInterface(handle);
            if (interfaceGuid is null)
            {
                return false;
            }

            var guid = interfaceGuid.Value;
            var profileName = $"Via-{StableProfileName(ssid)}";
            var profileXml = BuildProfileXml(profileName, ssid, password);
            // WLAN_PROFILE_USER = 0x2 keeps the profile and its keyMaterial
            // under the current user's ACL instead of an all-user profile.
            if (WlanSetProfile(
                    handle,
                    ref guid,
                    0x2,
                    profileXml,
                    null,
                    true,
                    IntPtr.Zero,
                    out _) != ErrorSuccess)
            {
                return false;
            }

            var parameters = new WlanConnectionParameters
            {
                wlanConnectionMode = WlanConnectionModeProfile,
                strProfile = profileName,
                pDot11Ssid = IntPtr.Zero,
                pDesiredBssidList = IntPtr.Zero,
                dot11BssType = Dot11BssTypeInfrastructure,
                dwFlags = 0
            };

            if (WlanConnect(handle, ref guid, ref parameters, IntPtr.Zero) != ErrorSuccess)
            {
                return false;
            }

            var deadline = DateTimeOffset.UtcNow + timeout;
            while (DateTimeOffset.UtcNow < deadline)
            {
                WaitOrThrow(token, TimeSpan.FromMilliseconds(500));
                if (string.Equals(
                        GetCurrentSsid(handle, ownsHandle: false),
                        ssid,
                        StringComparison.Ordinal))
                {
                    return true;
                }
            }

            return false;
        }
        finally
        {
            WlanCloseHandle(handle, IntPtr.Zero);
        }
    }

    private static void WaitOrThrow(CancellationToken token, TimeSpan delay)
    {
        if (!token.CanBeCanceled)
        {
            Thread.Sleep(delay);
            return;
        }

        if (token.WaitHandle.WaitOne(delay))
        {
            token.ThrowIfCancellationRequested();
        }
    }

    private static IntPtr OpenOwnedHandle()
    {
        var result = WlanOpenHandle(2, IntPtr.Zero, out _, out var handle);
        return result == ErrorSuccess ? handle : IntPtr.Zero;
    }

    private static Guid? FindInterface(IntPtr handle)
    {
        if (WlanEnumInterfaces(handle, IntPtr.Zero, out var list) != ErrorSuccess ||
            list == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            var count = (uint)Marshal.ReadInt32(list);
            if (count == 0)
            {
                return null;
            }

            var infoSize = Marshal.SizeOf<WlanInterfaceInfo>();
            var info = Marshal.PtrToStructure<WlanInterfaceInfo>(IntPtr.Add(list, 8));
            return info.InterfaceGuid;
        }
        finally
        {
            WlanFreeMemory(list);
        }
    }

    private static string? DecodeSsid(string value) => value.Length == 0 ? null : value;

    private static string SsidToString(Dot11Ssid ssid)
    {
        if (ssid.uSSIDLength == 0 || ssid.ucSSID is null)
        {
            return "";
        }

        var length = (int)Math.Min(ssid.uSSIDLength, (uint)ssid.ucSSID.Length);
        var bytes = new byte[length];
        Array.Copy(ssid.ucSSID, bytes, length);
        // SSIDs are byte strings, not guaranteed UTF-8. Compare/transport them
        // as an unambiguous Latin-1 representation to avoid replacement chars.
        return Encoding.GetEncoding("ISO-8859-1").GetString(bytes);
    }

    private static string StableProfileName(string ssid)
    {
        using var sha = System.Security.Cryptography.SHA256.Create();
        var bytes = Encoding.UTF8.GetBytes(ssid);
        return BitConverter.ToString(sha.ComputeHash(bytes))
            .Replace("-", "")
            .Substring(0, 16);
    }

    private static string BuildProfileXml(string name, string ssid, string? password)
    {
        var escapedName = SecurityElement.Escape(name) ?? name;
        var escapedSsid = SecurityElement.Escape(ssid) ?? ssid;

        if (string.IsNullOrEmpty(password))
        {
            return $"""
                <?xml version="1.0"?>
                <WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
                  <name>{escapedName}</name>
                  <SSIDConfig><SSID><name>{escapedSsid}</name></SSID></SSIDConfig>
                  <connectionType>ESS</connectionType>
                  <connectionMode>auto</connectionMode>
                  <MSM>
                    <security>
                      <authEncryption>
                        <authentication>open</authentication>
                        <encryption>none</encryption>
                        <useOneX>false</useOneX>
                      </authEncryption>
                    </security>
                  </MSM>
                </WLANProfile>
                """;
        }

        // WlanSetProfile accepts plaintext keyMaterial when protected is false
        // and encrypts it before writing the profile to the store. Setting
        // protected=true here would require pre-encrypted hexadecimal input.
        var escapedPassword = SecurityElement.Escape(password) ?? password;
        return $"""
            <?xml version="1.0"?>
            <WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
              <name>{escapedName}</name>
              <SSIDConfig><SSID><name>{escapedSsid}</name></SSID></SSIDConfig>
              <connectionType>ESS</connectionType>
              <connectionMode>auto</connectionMode>
              <MSM>
                <security>
                  <authEncryption>
                    <authentication>WPA2PSK</authentication>
                    <encryption>AES</encryption>
                    <useOneX>false</useOneX>
                  </authEncryption>
                  <sharedKey>
                    <keyType>passPhrase</keyType>
                    <protected>false</protected>
                    <keyMaterial>{escapedPassword}</keyMaterial>
                  </sharedKey>
                </security>
              </MSM>
            </WLANProfile>
            """;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Dot11Ssid
    {
        public uint uSSIDLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)]
        public byte[] ucSSID;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WlanAssociationAttributes
    {
        public Dot11Ssid dot11Ssid;
        public int dot11BssType;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 6)]
        public byte[] dot11Bssid;
        public int dot11PhyType;
        public uint uDot11PhyIndex;
        public uint wlanSignalQuality;
        public uint ulRxRate;
        public uint ulTxRate;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WlanSecurityAttributes
    {
        public int bSecurityEnabled;
        public int bOneXEnabled;
        public int dot11AuthAlgorithm;
        public int dot11CipherAlgorithm;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WlanConnectionAttributes
    {
        public int isState;
        public int wlanConnectionMode;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strProfileName;
        public WlanAssociationAttributes wlanAssociationAttributes;
        public WlanSecurityAttributes wlanSecurityAttributes;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WlanInterfaceInfo
    {
        public Guid InterfaceGuid;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strInterfaceDescription;
        public int isState;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WlanAvailableNetwork
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strProfileName;
        public Dot11Ssid dot11Ssid;
        public int dot11BssType;
        public uint uNumberOfBssids;
        public int bNetworkConnectable;
        public uint wlanNotConnectableReason;
        public uint uNumberOfPhyTypes;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public int[] dot11PhyTypes;
        public int bMorePhyTypes;
        public uint wlanSignalQuality;
        public int bSecurityEnabled;
        public int dot11DefaultAuthAlgorithm;
        public int dot11DefaultCipherAlgorithm;
        public uint dwFlags;
        public uint dwReserved;
    }

    private delegate void WlanNotificationCallback(
        ref WlanNotificationData notificationData,
        IntPtr context);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WlanConnectionNotificationData
    {
        public int wlanConnectionMode;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string strProfileName;
        public Dot11Ssid dot11Ssid;
        public int dot11BssType;
        [MarshalAs(UnmanagedType.Bool)]
        public bool bSecurityEnabled;
        public uint wlanReasonCode;
        public uint dwFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WlanNotificationData
    {
        public int NotificationSource;
        public int NotificationCode;
        public Guid InterfaceGuid;
        public uint DataSize;
        public IntPtr Data;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WlanConnectionParameters
    {
        public int wlanConnectionMode;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string strProfile;
        public IntPtr pDot11Ssid;
        public IntPtr pDesiredBssidList;
        public int dot11BssType;
        public uint dwFlags;
    }

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanOpenHandle(
        uint clientVersion,
        IntPtr reserved,
        out uint negotiatedVersion,
        out IntPtr clientHandle);

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanCloseHandle(IntPtr clientHandle, IntPtr reserved);

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanEnumInterfaces(
        IntPtr clientHandle,
        IntPtr reserved,
        out IntPtr interfaceList);

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanRegisterNotification(
        IntPtr clientHandle,
        int notificationSource,
        [MarshalAs(UnmanagedType.Bool)] bool ignoreDuplicate,
        WlanNotificationCallback? callback,
        IntPtr callbackContext,
        IntPtr reserved,
        out uint previousNotificationSource);

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanQueryInterface(
        IntPtr clientHandle,
        ref Guid interfaceGuid,
        int opcode,
        IntPtr reserved,
        out uint dataSize,
        out IntPtr data,
        out int opcodeValueType);

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanGetAvailableNetworkList(
        IntPtr clientHandle,
        ref Guid interfaceGuid,
        uint flags,
        IntPtr reserved,
        out IntPtr availableNetworkList);

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanScan(
        IntPtr clientHandle,
        ref Guid interfaceGuid,
        IntPtr dot11Ssid,
        IntPtr informationElementData,
        IntPtr reserved);

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanSetProfile(
        IntPtr clientHandle,
        ref Guid interfaceGuid,
        uint flags,
        [MarshalAs(UnmanagedType.LPWStr)] string profileXml,
        [MarshalAs(UnmanagedType.LPWStr)] string? allUserProfileSecurity,
        [MarshalAs(UnmanagedType.Bool)] bool overwrite,
        IntPtr reserved,
        out uint reasonCode);

    [DllImport("wlanapi.dll", SetLastError = true)]
    private static extern uint WlanConnect(
        IntPtr clientHandle,
        ref Guid interfaceGuid,
        ref WlanConnectionParameters connectionParameters,
        IntPtr reserved);

    [DllImport("wlanapi.dll")]
    private static extern void WlanFreeMemory(IntPtr memory);
}
