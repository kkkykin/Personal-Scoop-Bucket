# Register WezTerm's existing Scoop shortcut for Windows desktop notifications.
# Can also be run manually for an already installed version:
# .\set-appusermodelid.ps1 -ShortcutPath "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Scoop Apps\WezTerm.lnk"
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ShortcutPath
)

$ErrorActionPreference = 'Stop'
$appId = 'org.wezfurlong.wezterm'
$shortcutPath = (Resolve-Path -LiteralPath $ShortcutPath).ProviderPath
if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf) -or
    [IO.Path]::GetExtension($shortcutPath) -ne '.lnk') {
    throw 'ShortcutPath must point to an existing Windows shortcut (.lnk).'
}

if (-not ('WezTermToast.ShortcutProperties' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WezTermToast
{
    [StructLayout(LayoutKind.Sequential)]
    public struct PropertyKey
    {
        public Guid FormatId;
        public uint PropertyId;
    }

    // The union starts at byte 8; the largest native union is 16 bytes on x64.
    [StructLayout(LayoutKind.Explicit, Size = 24)]
    public struct PropVariant
    {
        [FieldOffset(0)] public ushort VariantType;
        [FieldOffset(8)] public IntPtr StringValue;
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    public static class ShortcutProperties
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int SHGetPropertyStoreFromParsingName(
            string path, IntPtr bindContext, uint flags, ref Guid iid,
            [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

        [DllImport("ole32.dll", ExactSpelling = true)]
        private static extern int PropVariantClear(ref PropVariant variant);

        public static void SetAppId(string shortcutPath, string appId)
        {
            Guid iid = typeof(IPropertyStore).GUID;
            IPropertyStore store;
            // GPS_READWRITE opens the shortcut's property store for editing.
            Marshal.ThrowExceptionForHR(SHGetPropertyStoreFromParsingName(
                shortcutPath, IntPtr.Zero, 2, ref iid, out store));
            PropVariant value = new PropVariant();
            try
            {
                PropertyKey key = new PropertyKey {
                    FormatId = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
                    PropertyId = 5 // System.AppUserModel.ID
                };
                // InitPropVariantFromString is an inline SDK helper, not a DLL export.
                value.StringValue = Marshal.StringToCoTaskMemUni(appId);
                value.VariantType = 31; // VT_LPWSTR
                Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref value));
                Marshal.ThrowExceptionForHR(store.Commit());
            }
            finally
            {
                PropVariantClear(ref value);
                Marshal.FinalReleaseComObject(store);
            }
        }
    }
}
'@
}

[WezTermToast.ShortcutProperties]::SetAppId($shortcutPath, $appId)
# Read the stored property directly; Start Menu indexing may take time.
$shell = New-Object -ComObject Shell.Application
try {
    $folder = $shell.Namespace((Split-Path -Parent $shortcutPath))
    $item = $folder.ParseName([IO.Path]::GetFileName($shortcutPath))
    $storedAppId = $item.ExtendedProperty('System.AppUserModel.ID')
    if ($storedAppId -ne $appId) {
        throw "Shortcut AppUserModelID verification failed: '$storedAppId'."
    }
}
finally {
    if ($null -ne $item) {
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($item) > $null
    }
    if ($null -ne $folder) {
        [Runtime.InteropServices.Marshal]::FinalReleaseComObject($folder) > $null
    }
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) > $null
}

Write-Host "Registered WezTerm desktop notifications: $storedAppId"
