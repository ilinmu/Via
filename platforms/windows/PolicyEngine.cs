using System.Runtime.InteropServices;
using System.Text;

namespace Via.Windows;

public enum PolicyActionKind
{
    Scan = 1,
    Associate = 2,
    CheckNow = 3,
    Stop = 4,
    WaitForPermission = 5,
    Log = 6,
    RefreshStatus = 7
}

public enum PolicyScanPurpose
{
    PriorityCheck = 1,
    BackupCheck = 2,
    PriorityClassification = 3,
    BackupFailover = 4,
    BackupRecovery = 5
}

public enum PolicyStopReason
{
    NotConfigured = 1,
    ManualOverrideBackup = 2,
    ManualOverrideUnmanaged = 3
}

public enum PolicyLogEvent
{
    Started = 1,
    Stopped = 2,
    PriorityConnected = 3,
    PriorityVisibleWaiting = 4,
    NetworkDisconnectedWaiting = 5,
    AutomaticFailover = 6,
    PriorityLostConnectingBackup = 7,
    BackupConnectedPNotFound = 8,
    NeitherFound = 9,
    BackupNotFound = 10,
    BackupNotFoundWaiting = 11,
    PreviousBackupReconnect = 12,
    SystemJoinedBackup = 13,
    TreatingAsFallback = 14,
    CooldownSkipped = 15,
    AssociationSuccess = 16,
    AssociationTimeout = 17,
    AssociationFailure = 18,
    AssociationLateSuccess = 19,
    AssociationLateFailure = 20,
    PermissionRequired = 21,
    PriorityVisibleUnknown = 22
}

public sealed record PolicyAction(
    PolicyActionKind Kind,
    string? Ssid,
    int Role,
    int Purpose,
    int Reason);

public sealed record PolicySnapshot(
    bool Running,
    int Role,
    int Permission,
    string? CurrentSsid,
    bool IsAssociating,
    long CooldownUntilMs,
    string? CooldownTarget);

public sealed record PolicyResult(
    IReadOnlyList<PolicyAction> Actions,
    PolicySnapshot Snapshot);

public sealed class PolicyEngine : IDisposable
{
    private readonly object _gate = new();
    private IntPtr _handle;
    private bool _disposed;

    static PolicyEngine()
    {
        NativeCore.EnsureLoaded();
    }

    public PolicyEngine(string ssidP, string ssidB)
    {
        _handle = Native.via_engine_new(ssidP, ssidB);
        if (_handle == IntPtr.Zero)
        {
            throw new InvalidOperationException("Could not create the shared policy engine.");
        }
    }

    public void SetConfig(string ssidP, string ssidB)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_set_config(_handle, ssidP, ssidB);
        }
    }

    public PolicyResult Start(int permission, string? currentSsid)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_start(_handle, NowMs(), permission, currentSsid, out var result);
            return Read(result);
        }
    }

    public PolicyResult Stop()
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_stop(_handle, out var result);
            return Read(result);
        }
    }

    public PolicyResult CheckBegin(int permission, string? currentSsid)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_check_begin(_handle, NowMs(), permission, currentSsid, out var result);
            return Read(result);
        }
    }

    public PolicyResult ScanResult(bool? found)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_scan_result(_handle, FoundCode(found), NowMs(), out var result);
            return Read(result);
        }
    }

    public PolicyResult ClassificationResult(bool? priorityVisible)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_classification_result(
                _handle,
                FoundCode(priorityVisible),
                NowMs(),
                out var result);
            return Read(result);
        }
    }

    public PolicyResult BackupScanResult(bool? found)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_backup_scan_result(_handle, FoundCode(found), NowMs(), out var result);
            return Read(result);
        }
    }

    public ulong AssociationStarted(string ssid)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            return Native.via_engine_association_started(_handle, ssid, NowMs());
        }
    }

    public PolicyResult AssociationResult(string ssid, ulong generation, int outcome)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_association_result(
                _handle,
                ssid,
                generation,
                outcome,
                NowMs(),
                out var result);
            return Read(result);
        }
    }

    public PolicyResult LateAssociationResult(string ssid, ulong generation, bool succeeded)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_late_association_result(
                _handle,
                ssid,
                generation,
                succeeded ? 1 : 0,
                NowMs(),
                out var result);
            return Read(result);
        }
    }

    public PolicyResult ObservedChange(string? previousSsid, string? newSsid)
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_observed_change(
                _handle,
                previousSsid,
                newSsid,
                NowMs(),
                out var result);
            return Read(result);
        }
    }

    public PolicySnapshot Snapshot()
    {
        lock (_gate)
        {
            ThrowIfDisposed();
            Native.via_engine_snapshot(_handle, out var snapshot);
            return ReadSnapshot(snapshot);
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            Native.via_engine_free(_handle);
            _handle = IntPtr.Zero;
            _disposed = true;
        }
    }

    private void ThrowIfDisposed()
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(PolicyEngine));
        }
    }

    private static long NowMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

    // -1 = unknown, 0 = absent, 1 = visible.
    private static int FoundCode(bool? found) => found is null ? -1 : (found.Value ? 1 : 0);

    private static PolicyResult Read(Native.ViaResult result)
    {
        var actions = new List<PolicyAction>(Math.Max(0, result.Count));
        var size = Marshal.SizeOf<Native.ViaAction>();
        for (var index = 0; index < result.Count; index++)
        {
            var pointer = IntPtr.Add(result.Actions, index * size);
            var raw = Marshal.PtrToStructure<Native.ViaAction>(pointer);
            actions.Add(new PolicyAction(
                (PolicyActionKind)raw.Kind,
                ReadUtf8(raw.Ssid),
                raw.Role,
                raw.Purpose,
                raw.Reason));
        }

        return new PolicyResult(actions, ReadSnapshot(result.Snapshot));
    }

    private static PolicySnapshot ReadSnapshot(Native.ViaSnapshot snapshot)
    {
        return new PolicySnapshot(
            snapshot.Running != 0,
            snapshot.Role,
            snapshot.Permission,
            ReadUtf8(snapshot.CurrentSsid),
            snapshot.IsAssociating != 0,
            snapshot.CooldownUntilMs,
            ReadUtf8(snapshot.CooldownTarget));
    }

    private static string? ReadUtf8(IntPtr pointer)
    {
        if (pointer == IntPtr.Zero)
        {
            return null;
        }

        var length = 0;
        while (Marshal.ReadByte(pointer, length) != 0)
        {
            length++;
        }

        if (length == 0)
        {
            return string.Empty;
        }

        var buffer = new byte[length];
        Marshal.Copy(pointer, buffer, 0, length);
        return Encoding.UTF8.GetString(buffer);
    }

    private static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct ViaAction
        {
            public int Kind;
            public int Role;
            public int Reason;
            public int Purpose;
            public long DelayMs;
            public IntPtr Ssid;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct ViaSnapshot
        {
            public int Running;
            public int Role;
            public int Permission;
            public int IsAssociating;
            public long CooldownUntilMs;
            public IntPtr CurrentSsid;
            public IntPtr CooldownTarget;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct ViaResult
        {
            public int Count;
            public IntPtr Actions;
            public ViaSnapshot Snapshot;
        }

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        public static extern IntPtr via_engine_new(
            [MarshalAs(UnmanagedType.LPUTF8Str)] string ssidP,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string ssidB);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_free(IntPtr engine);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_set_config(
            IntPtr engine,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string ssidP,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string ssidB);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_start(
            IntPtr engine,
            long nowMs,
            int permission,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string? currentSsid,
            out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_stop(IntPtr engine, out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_check_begin(
            IntPtr engine,
            long nowMs,
            int permission,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string? currentSsid,
            out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_scan_result(
            IntPtr engine,
            int found,
            long nowMs,
            out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_classification_result(
            IntPtr engine,
            int priorityVisible,
            long nowMs,
            out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_backup_scan_result(
            IntPtr engine,
            int found,
            long nowMs,
            out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern ulong via_engine_association_started(
            IntPtr engine,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string ssid,
            long nowMs);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_association_result(
            IntPtr engine,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string ssid,
            ulong generation,
            int outcome,
            long nowMs,
            out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_late_association_result(
            IntPtr engine,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string ssid,
            ulong generation,
            int succeeded,
            long nowMs,
            out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_observed_change(
            IntPtr engine,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string? previousSsid,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string? newSsid,
            long nowMs,
            out ViaResult result);

        [DllImport("via_core", CallingConvention = CallingConvention.Cdecl)]
        public static extern void via_engine_snapshot(IntPtr engine, out ViaSnapshot snapshot);
    }
}
