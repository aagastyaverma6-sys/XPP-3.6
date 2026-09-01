#!/usr/bin/env python3
"""Small Windows-only helper: create/refresh the x/xpp/xite shims and PATH.

Use from cmd:  python tools\\fix_x.py
Or double-click fix-x.bat.
"""
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOME = Path.home()


def main():
    if os.name != "nt":
        print("This helper is only needed on Windows. Use tools/xpp_setup.py elsewhere.")
        return 0

    bin_dir = HOME / ".xpp" / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    py = sys.executable
    for name in ("x", "xpp", "xite"):
        shim = bin_dir / (name + ".cmd")
        shim.write_text(
            '@echo off\r\n'
            f'set "PYTHONPATH={ROOT};%PYTHONPATH%"\r\n'
            f'set "PYTHONUNBUFFERED=1"\r\n'
            f'"{py}" -m xpp_core.cli %*\r\n',
            encoding="utf-8")
        print(f"[OK] {shim}")

    # Prepend to user PATH, remove duplicates, keep existing entries.
    import winreg
    key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0,
                         winreg.KEY_READ | winreg.KEY_SET_VALUE)
    try:
        cur, _ = winreg.QueryValueEx(key, "Path")
    except OSError:
        cur = ""
    target = str(bin_dir)
    parts = [p for p in cur.split(";") if p and p.lower() != target.lower()]
    new = target + ((";" + ";".join(parts)) if parts else "")
    if new.lower() == cur.lower():
        print("[OK] user PATH already contains", target)
    else:
        winreg.SetValueEx(key, "Path", 0, winreg.REG_EXPAND_SZ, new)
        print("[OK] added", target, "to user PATH")
    winreg.CloseKey(key)

    # Try to notify open shells.
    try:
        import ctypes
        HWND_BROADCAST, WM_SETTINGCHANGE = 0xFFFF, 0x001A
        ctypes.windll.user32.SendMessageTimeoutW(
            HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment", 2, 5000, None)
    except Exception:
        pass

    print("\nNow open a NEW terminal and run:")
    print("    x version")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
