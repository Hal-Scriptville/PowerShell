# Example: Google Chrome Enterprise (Intune Win32 App)

Reference package showing a complete Win32 app built with `Build-IntuneAppBuilder.ps1`.

## Files

| File | Purpose |
|------|---------|
| `install.ps1` | Silent install via msiexec, logs to IME log dir |
| `uninstall.ps1` | Uninstall by product code |
| `detect.ps1` | Version-based detection on chrome.exe |

## Build

1. Download `googlechromestandaloneenterprise64.msi` from https://chromeenterprise.google/download/
2. Place it alongside `install.ps1` (same `Source\` folder)
3. From the package root:
   ```powershell
   .\Build-IntuneAppBuilder.ps1 -AppName Chrome -Build
   ```
4. Upload `Output\install.intunewin` to Intune.

## Intune app settings

- **Install command:** `powershell.exe -ExecutionPolicy Bypass -File install.ps1`
- **Uninstall command:** `powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1`
- **Install behavior:** System
- **Detection rule:** Custom script → upload `detect.ps1`, run as 32-bit: No

## Notes

- Replace `{CHROME-PRODUCT-CODE-GUID}` in `uninstall.ps1` with the actual product code of the MSI you packaged.
- `detect.ps1` uses version >= 120. Update `$minVersion` to gate on a specific baseline.
