// C# 9 records and init-only setters need this type. It ships with .NET 5+,
// but not with .NET Framework 4.8.
namespace System.Runtime.CompilerServices
{
    internal static class IsExternalInit
    {
    }
}
