using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace Via.Windows;

/// <summary>
/// Loads the Rust policy core (`via_core.dll`).
///
/// .NET Framework has no `NativeLibrary` resolver, so the embedded copy is
/// extracted to `%LocalAppData%\Via\bin` and loaded with an absolute path
/// before the first P/Invoke. The Windows loader then resolves the plain
/// `via_core` import in <see cref="PolicyEngine"/> to that module.
/// </summary>
internal static class NativeCore
{
    private const string DllName = "via_core.dll";
    private static readonly object Gate = new();
    private static bool _loaded;

    public static void EnsureLoaded()
    {
        lock (Gate)
        {
            if (_loaded)
            {
                return;
            }

            // Dev builds and test runs keep the DLL next to the exe.
            if (TryLoad(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, DllName)))
            {
                _loaded = true;
                return;
            }

            var extracted = ExtractEmbedded();
            if (extracted != null && TryLoad(extracted))
            {
                _loaded = true;
                return;
            }

            throw new DllNotFoundException(
                "Could not load " + DllName + "; the application files may be incomplete.");
        }
    }

    private static bool TryLoad(string path)
    {
        return File.Exists(path) && LoadLibrary(path) != IntPtr.Zero;
    }

    private static string? ExtractEmbedded()
    {
        try
        {
            using (var resource = Assembly.GetExecutingAssembly()
                       .GetManifestResourceStream(DllName))
            {
                if (resource == null)
                {
                    return null;
                }

                var directory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Via",
                    "bin");
                Directory.CreateDirectory(directory);
                var target = Path.Combine(directory, DllName);

                // Re-extract after an update so the loader never uses a stale
                // core with an older ABI.
                if (!File.Exists(target) || new FileInfo(target).Length != resource.Length)
                {
                    var temporary = target + ".tmp";
                    using (var output = File.Create(temporary))
                    {
                        resource.CopyTo(output);
                    }

                    if (File.Exists(target))
                    {
                        File.Delete(target);
                    }

                    File.Move(temporary, target);
                }

                return target;
            }
        }
        catch
        {
            return null;
        }
    }

    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibrary(string fileName);
}
