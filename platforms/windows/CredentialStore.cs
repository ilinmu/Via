using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace AutoWifi.Windows;

/// <summary>
/// Small wrapper over Windows Credential Manager. Passwords are never written
/// to settings.json.
/// </summary>
public sealed class CredentialStore
{
    private const uint CredTypeGeneric = 1;
    private const uint CredPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;

    public string? Load(string account)
    {
        var target = Target(account);
        if (!NativeCredential.CredRead(target, CredTypeGeneric, 0, out var pointer))
        {
            return null;
        }

        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential.Credential>(pointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0)
            {
                return null;
            }

            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.Unicode.GetString(bytes);
        }
        finally
        {
            NativeCredential.CredFree(pointer);
        }
    }

    public void Save(string account, string? password)
    {
        if (string.IsNullOrEmpty(password))
        {
            Delete(account);
            return;
        }

        var target = Target(account);
        var bytes = Encoding.Unicode.GetBytes(password);
        var blob = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new NativeCredential.Credential
            {
                Type = CredTypeGeneric,
                TargetName = target,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = CredPersistLocalMachine,
                UserName = "AutoWifi"
            };

            if (!NativeCredential.CredWrite(ref credential, 0))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
        }
    }

    public void Delete(string account)
    {
        var target = Target(account);
        if (!NativeCredential.CredDelete(target, CredTypeGeneric, 0))
        {
            var error = Marshal.GetLastWin32Error();
            if (error != ErrorNotFound)
            {
                throw new Win32Exception(error);
            }
        }
    }

    private static string Target(string account) => $"AutoWifi/{account}";

    private static class NativeCredential
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct Credential
        {
            public uint Flags;
            public uint Type;
            [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
            [MarshalAs(UnmanagedType.LPWStr)] public string? Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist;
            public uint AttributeCount;
            public IntPtr Attributes;
            [MarshalAs(UnmanagedType.LPWStr)] public string? TargetAlias;
            [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
        }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CredWrite(ref Credential credential, uint flags);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CredRead(
            string target,
            uint type,
            uint flags,
            out IntPtr credential);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CredDelete(string target, uint type, uint flags);

        [DllImport("advapi32.dll")]
        public static extern void CredFree(IntPtr buffer);
    }
}
