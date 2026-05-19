# SkimSrv License Files

Place your SkimSrv `.reg` license file(s) in this directory.  
All `*.reg` files here are automatically imported into the Wine registry on every container start.

---

## How to extract your license from a licensed Windows machine

SkimSrv uses the **Armadillo** DRM system, which stores its license as binary blobs in the Windows registry under `HKLM\SOFTWARE\WOW6432Node\Licenses`.

### Step 1 — Export from Windows

Open **Command Prompt** or **PowerShell** on the machine where SkimSrv is already registered and run:

```cmd
reg export "HKLM\SOFTWARE\WOW6432Node\Licenses" "%USERPROFILE%\skimsrv_license.reg"
```

This saves the file to `C:\Users\<YourName>\skimsrv_license.reg`.

### Step 2 — Copy to this directory

Transfer `skimsrv_license.reg` to this `licenses/` directory on your Linux host:

```bash
scp user@windowsmachine:skimsrv_license.reg ~/ubersdr/cwskimmer/licenses/
```

Or copy it via USB, network share, etc.

### Step 3 — Restart the container

```bash
bash ~/ubersdr/cwskimmer/restart.sh
```

The license is imported automatically at startup. Check the container logs to confirm:

```
Importing Wine registry file: /tmp/skimsrv_licenses/skimsrv_license.reg
Imported 1 .reg file(s) into Wine registry
```

---

## Notes

- `.reg` files in this directory are **gitignored** and will never be committed to version control.
- You can place multiple `.reg` files here if needed — all are imported.
- If no `.reg` files are present, SkimSrv runs in unregistered/trial mode.
- The license blobs are tied to the Armadillo protection in `SkimSrv.exe`. If the import succeeds but SkimSrv still shows a registration prompt, the license may be machine-locked to your Windows hardware — contact Afreet Software for a re-issue.
