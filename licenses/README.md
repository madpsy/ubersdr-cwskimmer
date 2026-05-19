# SkimSrv License Files

Place your SkimSrv `.reg` license file(s) in this directory.
All `*.reg` files here are automatically imported into the Wine registry on every container start.

> **Note:** SkimSrv runs fully functional for 30 days without a license. After the trial period it will prompt for registration on startup. If you're just getting started, you don't need to do any of this yet — come back here when the 30-day nag appears.

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

## What the .reg file should look like

The exported file should have this structure (hex values will be unique to your license):

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Licenses]
"{K7C0DB872A3F777C0}"=hex:d7,d8,e4,c3,5b,26,1f,ff,ff,ff,ff,52,48,8a,8c,4b,c2,\
  30,49,c6,f8,58,b2,86,bb,85,f4,...
"{IB3C3B61550D45B7A}"=hex:0b,04,00,00
"{0B3C3B61550D45B7A}"=hex:5b,3e,8f,0f,ef,81,a3,aa,0f,67,25,f2,5a,dd,68,e9,b2,\
  5f,f2,0d,b6,c5,03,83,...
```

The GUIDs and hex values will differ for each licensed installation — the above are illustrative only.

---

## Notes

- `.reg` files in this directory are **gitignored** and will never be committed to version control.
- You can place multiple `.reg` files here if needed — all are imported.
- If no `.reg` files are present, SkimSrv runs in unregistered/trial mode.
- The license blobs are tied to the Armadillo protection in `SkimSrv.exe`. If the import succeeds but SkimSrv still shows a registration prompt, the license may be machine-locked to your Windows hardware — contact Afreet Software for a re-issue.
