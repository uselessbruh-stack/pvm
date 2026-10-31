# PVM for Windows

## Switch Python versions from one simple command.

PVM makes it easy to install multiple Python versions, switch the version used by your terminal, and keep existing Python installations available.

**[Download PVM for Windows](https://raw.githubusercontent.com/uselessbruh-stack/pvm/main/dist/PVM-Setup.exe)**

The installer is about 171 KB and does not bundle Python. PVM downloads the Python version you choose from official Python sources and shows download progress while it runs.

## Get started

1. Download and run `PVM-Setup.exe`. No administrator access is required.
2. Open **PVM for Windows** from the Windows Start menu, or open a new Command Prompt or PowerShell window.
3. Install and activate a Python version:

```powershell
pvm install 3.12
pvm use 3.12
python --version
```

PVM installs the latest matching patch release. To see installed versions, run `pvm list`. To browse releases available online, run `pvm list-remote`.

## What you can do

| Command | What it does |
| --- | --- |
| `pvm install 3.12` | Install the latest available Python 3.12 release |
| `pvm install 3.12.4` | Install a specific release |
| `pvm use 3.12` | Switch to an installed matching version |
| `pvm list` | View PVM versions and Python installations already on your PC |
| `pvm list-remote` | Browse available Python releases |
| `pvm current` | Show the active Python version |
| `pvm uninstall 3.12.4` | Remove a version installed and managed by PVM |
| `pvm off` / `pvm on` | Temporarily disable or re-enable PVM on your PATH |
| `pvm help` | Show command help |

## Use Python already on your PC

PVM detects Python installations registered with the Windows launcher or registry, along with Python executables on your PATH. They appear in `pvm list` and can be selected with `pvm use <version>`.

PVM switches to an existing installation without moving or managing its files. `pvm uninstall` only removes versions installed in PVM's own versions folder.

## How PVM works

PVM installs managed versions under `%USERPROFILE%\.pvm\versions` and points `%USERPROFILE%\.pvm\current` at the active version. Your user PATH points to that active version, so `python` and `pip` use the selected runtime in new terminals.

PVM uses the official full Windows installer from python.org when one is available. For releases distributed through the Python install manager, PVM can use its `py install --target` command. Both methods install a regular Python runtime with pip. PVM uses directory junctions to switch versions without requiring administrator access.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- Internet access to download Python releases

## Uninstall

Run the included installer script to remove PVM from your PATH, PowerShell profile, and Start menu. Your installed Python versions are preserved:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.pvm\install.ps1" -Uninstall
```

To remove PVM and all Python versions managed by it, delete `%USERPROFILE%\.pvm` after uninstalling.

## Build from source

On Windows with the .NET Framework C# compiler available, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

This produces `dist\PVM-Setup.exe` and `dist\pvm.exe`. Both use `favicon.png` as their Windows icon. The setup executable includes the PVM manager and installer and adds a **PVM for Windows** shortcut to the current user's Start menu.

## License

MIT
