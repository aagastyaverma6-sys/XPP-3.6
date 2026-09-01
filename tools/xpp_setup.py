#!/usr/bin/env python3
"""
X++ v0.4.1 - one-shot setup engine (cross platform).

Run through setup.bat / setup.sh (or directly: python3 tools/xpp_setup.py --all)

Installs, when missing and possible:
  * pip deps (lark, requests) + editable install  -> `x` command
  * xppvm native VM (ZCOM/ZITR/ZJIT)              -> no Python needed to run
  * X++ VS Code extension (syntax + FILE ICONS) + Code Runner run button
  * OS file-icon registration so .xp files show the X++ logo everywhere
  * PATH registration for x / xppvm

Never needs admin where user-level installs are possible.
"""
import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "icons"
NATIVE = ROOT / "native"
VSCODE_EXT = ROOT / "vscode" / "xpp-vscode"
IS_WIN = os.name == "nt"
IS_MAC = sys.platform == "darwin"
HOME = Path.home()


def banner(msg):
    print("\n" + "=" * 68)
    print("  X++ v0.4.1 SETUP  *  " + msg)
    print("=" * 68)


def sh(cmd, cwd=None, check=False, env=None, echo=True):
    if echo:
        print("  $ " + (" ".join(cmd) if isinstance(cmd, list) else cmd))
    try:
        return subprocess.run(cmd, cwd=cwd, env=env, shell=isinstance(cmd, str),
                              capture_output=False, text=True)
    except FileNotFoundError as e:
        print(f"  ! command not found: {e}")
        return None


def note(txt):
    print("  [OK] " + txt)


def warn(txt):
    print("  [!] " + txt)


# --------------------------------------------------------------------------
# 1. Python deps + editable install (the `x` command)
# --------------------------------------------------------------------------
def install_python_pkg():
    banner("python packages")
    base = [sys.executable, "-m", "pip", "install"]
    attempts = [
        base + ["-e", str(ROOT)],
        base + ["-e", str(ROOT), "--user"],
        base + ["-e", str(ROOT), "--break-system-packages"],
        base + ["-e", str(ROOT), "--user", "--break-system-packages"],
    ]
    ok = False
    for a in attempts:
        r = sh(a, cwd=ROOT, echo=True)
        if r is not None and r.returncode == 0:
            ok = True
            break
    if not ok:
        warn("pip editable install failed - writing a direct `x` shim instead; "
             "the VM still works via xppvm.")
    install_x_shim()
    # best-effort optional deps (lark = --strict-ast, requests = ITR/AI mode)
    for dep in ("lark", "requests"):
        try:
            __import__(dep.replace("-", "_"))
        except ImportError:
            sh(base + [dep, "--quiet"])
    note("python package installed")


def install_x_shim():
    """Guarantee `x`/`xpp`/`xite` work even when pip/network is unavailable.

    The shim is always (re)written so it points at *this* checkout and at
    the Python interpreter that is actually running setup.
    """
    if IS_WIN:
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
            note(f"{name} shim: {shim}")
        add_windows_path(str(bin_dir))
    else:
        bin_dir = HOME / ".local" / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        py = sys.executable
        for name in ("x", "xpp", "xite"):
            shim = bin_dir / name
            shim.write_text(
                '#!/bin/sh\n'
                f'export PYTHONPATH="{ROOT}:${{PYTHONPATH:-}}"\n'
                f'exec "{py}" -m xpp_core.cli "$@"\n',
                encoding="utf-8")
            shim.chmod(0o755)
            note(f"{name} shim: {shim}")
        add_shell_path(str(bin_dir))


def _x_script_dir():
    if IS_WIN:
        return None  # console script lives in Python Scripts dir
    return HOME / ".local" / "bin"


def _has_installed_x():
    return shutil.which("x") is not None or (_x_script_dir() / "x").exists()


# --------------------------------------------------------------------------
# 2. Build + install xppvm
# --------------------------------------------------------------------------
def find_gxx():
    g = shutil.which("g++") or shutil.which("clang++")
    if g:
        return g
    for p in (r"C:\msys64\mingw64\bin\g++.exe",
              r"C:\MinGW\bin\g++.exe",
              r"C:\Program Files\mingw64\bin\g++.exe"):
        if Path(p).exists():
            return p
    return None


def build_native():
    banner("native VM (xppvm)")
    g = find_gxx()
    if IS_WIN:
        env = os.environ.copy()
        if g:
            env["PATH"] = os.path.dirname(g) + os.pathsep + env["PATH"]
        # Run the batch through cmd.exe with a quoted path. This avoids cmd
        # matching the `)` in folder names such as "AAV (Aagastya Verma)".
        bat = str(ROOT / "build_xppvm.bat")
        r = sh([os.environ.get("COMSPEC", "cmd.exe"), "/c", bat],
               cwd=ROOT, env=env)
        ok = r is not None and r.returncode == 0
    else:
        cxx = "clang++" if IS_MAC else os.environ.get("CXX", "g++")
        r = sh(["make", "-C", str(NATIVE), f"CXX={cxx}"], cwd=ROOT)
        ok = r is not None and r.returncode == 0
    note("xppvm build: " + ("ok" if ok else "failed"))
    return ok


def install_binary():
    banner("installing xppvm")
    src = ROOT / ("build/xppvm.exe" if IS_WIN else "xppvm")
    runtime = NATIVE / "zjit_runtime.hpp"
    if not src.exists():
        warn(f"xppvm binary not found at {src} - skipping install")
        return

    targets = []
    if IS_WIN:
        bin_dir = HOME / ".xpp" / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        targets.append(bin_dir)
        add_windows_path(str(bin_dir))
    else:
        bin_dir = HOME / ".local" / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        targets.append(bin_dir)
        # try system location if writable
        if Path("/usr/local/bin").is_dir() and os.access("/usr/local/bin", os.W_OK):
            targets.insert(0, Path("/usr/local/bin"))
        # always put the runtime next to the binary (ZJIT looks there)
    for d in targets:
        try:
            shutil.copy2(src, d / src.name)
            shutil.copy2(runtime, d / "zjit_runtime.hpp")
        except OSError as e:
            warn(f"could not copy to {d}: {e}")
    if not IS_WIN:
        add_shell_path(str(bin_dir))
        profile_hint = " (restart terminal after setup)"
    else:
        profile_hint = ""
    note(f"xppvm + zjit_runtime.hpp installed{profile_hint}")


# --------------------------------------------------------------------------
# 3. PATH registration
# --------------------------------------------------------------------------
def add_shell_path(path):
    lines = []
    for f in (HOME / ".profile", HOME / ".bashrc", HOME / ".zshrc",
              HOME / ".zprofile", HOME / ".bash_profile"):
        if not f.exists():
            continue
        lines.append(f.read_text(errors="ignore"))
    block = f'\n# ---- X++ v0.4.1 ----\nexport PATH="{path}:$PATH"\nexport XPP_NATIVE_DIR="{path}"\n'
    if any(path in t for t in lines):
        note("PATH already registered")
        return
    target = HOME / ".profile" if not IS_MAC else HOME / ".zprofile"
    with target.open("a") as f:
        f.write(block)
    note(f"updated {target.name}")


def add_windows_path(path):
    try:
        import winreg
    except ImportError:
        return
    k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0,
                       winreg.KEY_READ | winreg.KEY_SET_VALUE)
    try:
        cur, _ = winreg.QueryValueEx(k, "Path")
    except OSError:
        cur = ""
    # Put the X++ bin dir at the front so the fresh x.cmd / xppvm.cmd shims
    # win over any older x.exe/xite.exe already on PATH.
    parts = [p for p in cur.split(";") if p and p.lower() != path.lower()]
    new = path + ((";" + ";".join(parts)) if parts else "")
    if new.lower() == cur.lower():
        note("Windows PATH already registered")
    else:
        winreg.SetValueEx(k, "Path", 0, winreg.REG_EXPAND_SZ, new)
        note("Windows user PATH updated (restart terminals / VS Code)")
    winreg.CloseKey(k)
    # notify running processes
    try:
        import ctypes
        HWND_BROADCAST, WM_SETTINGCHANGE = 0xFFFF, 0x001A
        ctypes.windll.user32.SendMessageTimeoutW(
            HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment",
            2, 5000, None)
    except Exception:
        pass
    note("Windows user PATH registered (restart terminals / VS Code)")


# --------------------------------------------------------------------------
# 4. VS Code: extension (syntax + file icons) + Run button
# --------------------------------------------------------------------------
def find_code():
    c = shutil.which("code")
    if c:
        return c
    cands = []
    if IS_WIN:
        cands += [HOME / "AppData/Local/Programs/Microsoft VS Code/bin/code.cmd",
                  Path(r"C:\Program Files\Microsoft VS Code\bin\code.cmd")]
    elif IS_MAC:
        cands += [Path("/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"),
                  HOME / "Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]
    else:
        cands += [Path("/usr/bin/code"), Path("/usr/local/bin/code"),
                  HOME / ".local/bin/code"]
    for c in cands:
        if c.exists():
            return str(c)
    return None


def vscode_user_dir():
    if IS_WIN:
        return HOME / "AppData/Roaming/Code/User"
    if IS_MAC:
        return HOME / "Library/Application Support/Code/User"
    return HOME / ".config/Code/User"


def install_vscode():
    banner("VS Code integration (file icons + run button)")
    code = find_code()
    if not code:
        warn("VS Code not found - syntax highlighting + file icons will be "
             "picked up automatically when VS Code is installed later "
             "(rerun setup after installing VS Code).")
        return
    # extension folder (contains package.json, icon theme, grammar)
    r = sh([code, "--install-extension", str(VSCODE_EXT), "--force"])
    if r is None or r.returncode != 0:
        warn("could not install X++ extension")
        return
    # Code Runner -> the Run button
    r = sh([code, "--install-extension", "formulahendry.code-runner", "--force"])
    if r is None or r.returncode != 0:
        warn("could not install Code Runner (Run button) - rerun later or "
             "install 'Code Runner' from the marketplace manually")

    udir = vscode_user_dir()
    udir.mkdir(parents=True, exist_ok=True)
    settings = udir / "settings.json"
    data = {}
    if settings.exists():
        try:
            data = json.loads(settings.read_text(encoding="utf-8"))
        except Exception:
            data = {}
    data.setdefault("workbench", {})["iconTheme"] = "xpp-file-icons"
    files = data.setdefault("files", {})
    files.setdefault("associations", {})["*.xp"] = "xpp"
    data.setdefault("code-runner.executorMap", {})[".xp"] = "x run \"$fullFileName\""
    data["code-runner.runInTerminal"] = True
    settings.write_text(json.dumps(data, indent=2), encoding="utf-8")
    note("VS Code extension installed: syntax highlighting, X++ file icons, "
         "Run button (Code Runner). Restart VS Code to see the icons.")


# --------------------------------------------------------------------------
# 5. OS file icons
# --------------------------------------------------------------------------
def register_windows_icons():
    if not IS_WIN:
        return
    try:
        import winreg
    except ImportError:
        return
    banner("Windows file-type icons")
    base = r"Software\Classes"
    ico = str(ICONS / "xpp.ico")
    pythonw = shutil.which("pythonw") or shutil.which("python") or sys.executable
    code = find_code()
    def setv(sub, name, val):
        k = winreg.CreateKey(winreg.HKEY_CURRENT_USER, base + "\\" + sub)
        winreg.SetValueEx(k, name, 0, winreg.REG_SZ, val)
        winreg.CloseKey(k)
    setv(".xp", "", "XppSourceFile")
    setv(r"XppSourceFile\DefaultIcon", "", ico)
    setv(r"XppSourceFile\shell\run", "", "Run with X++")
    setv(r"XppSourceFile\shell\run\command", "", f'cmd /c x run "%1"')
    setv(r"XppSourceFile\shell\edit", "", "Edit in Xite")
    setv(r"XppSourceFile\shell\edit\command", "", f'"{pythonw}" "{ROOT / "xite.py"}" "%1"')
    if code:
        setv(r"XppSourceFile\shell\open\command", "", f'"{code}" "%1"')
    note("registered: .xp files now show the X++ logo in Explorer")


def install_linux_icons():
    if IS_WIN or IS_MAC:
        return
    banner("Linux file icon registration")
    share = HOME / ".local" / "share"
    mime_dir = share / "mime" / "packages"
    icon_base = share / "icons" / "hicolor"
    apps = share / "applications"
    for d in (mime_dir, apps):
        d.mkdir(parents=True, exist_ok=True)
    (mime_dir / "xpp.xml").write_text(textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8"?>
        <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
          <mime-type type="application/x-xpp">
            <comment>X++ Source</comment>
            <glob pattern="*.xp"/>
          </mime-type>
        </mime-info>
    """))
    for n in ("16", "32", "48", "64", "128", "256", "512"):
        d = icon_base / f"{n}x{n}" / "apps"
        d.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ICONS / f"xpp-logo-{n}.png", d / "xpp.png")
    (apps / "xpp.desktop").write_text(textwrap.dedent("""\
        [Desktop Entry]
        Type=Application
        Name=X++ Runner
        Comment=Run X++ pseudocode
        Exec=x run %F
        Icon=xpp
        Terminal=true
        MimeType=application/x-xpp;
        Categories=Development;
    """))
    for tool, args in (("update-mime-database", [str(share / "mime")]),
                       ("gtk-update-icon-cache", ["-f", str(icon_base)])):
        if shutil.which(tool):
            sh([tool] + args, echo=False)
    if shutil.which("xdg-mime"):
        sh(["xdg-mime", "default", "xpp.desktop", "application/x-xpp"], echo=False)
    note(".xp files registered with X++ logo in supported file managers")


def install_macos_app():
    if not IS_MAC:
        return
    banner("macOS file-type icons")
    app = HOME / "Applications" / "X++ Files.app"
    res = app / "Contents" / "Resources"
    mac = app / "Contents" / "MacOS"
    for d in (res, mac):
        d.mkdir(parents=True, exist_ok=True)
    (res / "xpp.icns").write_bytes((ICONS / "xpp.icns").read_bytes())
    (res / "xpp.png").write_bytes((ICONS / "xpp-logo-256.png").read_bytes())
    (mac / "XPlusPlus").write_text("#!/bin/sh\nexec x run \"$@\"\n", encoding="utf-8")
    (mac / "XPlusPlus").chmod(0o755)
    (app / "Contents" / "Info.plist").write_text(textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key><string>com.atomsoftware.xpp</string>
          <key>CFBundleName</key><string>X++ Files</string>
          <key>CFBundleDisplayName</key><string>X++ Files</string>
          <key>CFBundleExecutable</key><string>XPlusPlus</string>
          <key>CFBundleIconFile</key><string>xpp</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleDocumentTypes</key>
          <array>
            <dict>
              <key>CFBundleTypeExtensions</key><array><string>xp</string></array>
              <key>CFBundleTypeName</key><string>X++ Source</string>
              <key>CFBundleTypeRole</key><string>Editor</string>
              <key>LSHandlerRank</key><string>Alternate</string>
            </dict>
          </array>
        </dict>
        </plist>
    """))
    lsreg = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/"
                 "LaunchServices.framework/Support/lsregister")
    if lsreg.exists():
        sh([str(lsreg), "-f", str(app)], echo=False)
        sh(["killall", "Finder"], check=False, echo=False)
    if shutil.which("duti"):
        sh(["duti", "-s", "com.atomsoftware.xpp", "xp", "all"], echo=False)
    note("macOS handler app 'X++ Files' registered (Finder shows the logo for .xp)")


def _run_show(cls_cmd):
    try:
        if IS_WIN:
            r = subprocess.run([os.environ.get("COMSPEC", "cmd.exe"), "/c",
                                *(str(c) for c in cls_cmd)],
                               capture_output=True, text=True, timeout=10)
        else:
            r = subprocess.run([str(c) for c in cls_cmd],
                               capture_output=True, text=True, timeout=10)
        out = (r.stdout or "").strip() or (r.stderr or "").strip()
        return out or ("(no output)" if r.returncode == 0 else f"(exit {r.returncode})")
    except Exception as e:
        return f"(could not run: {e})"


def verify_install():
    """Check that the x / xppvm commands actually work from a fresh shell."""
    banner("VERIFY")
    if IS_WIN:
        bin_dir = HOME / ".xpp" / "bin"
    else:
        bin_dir = HOME / ".local" / "bin"

    x = bin_dir / ("x.cmd" if IS_WIN else "x")
    if not x.exists():
        warn(f"x command was not created at {x}")
    else:
        out = _run_show([x, "version"])
        print(f"  x       -> {x}")
        print(f"  x check -> {out}")

    xppvm = bin_dir / ("xppvm.exe" if IS_WIN else "xppvm")
    if not xppvm.exists():
        warn(f"xppvm was not installed at {xppvm}")
    else:
        out = _run_show([xppvm, "version"])
        print(f"  xppvm   -> {xppvm}")
        print(f"  xppvm check -> {out}")


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="run every step")
    ap.add_argument("--no-vscode", action="store_true")
    ap.add_argument("--shim", action="store_true",
                    help="only install/refresh the x/xpp/xite commands (fast)")
    ap.add_argument("--verify", action="store_true",
                    help="only check that x/xppvm work")
    args = ap.parse_args()

    print("\nX++ v0.4.1 universal setup   (repo: " + str(ROOT) + ")")
    print("Platform: " + platform.platform())

    if args.shim:
        install_x_shim()
        verify_install()
        return
    if args.verify:
        verify_install()
        return

    install_python_pkg()
    if build_native():
        install_binary()
    else:
        warn("xppvm not built - legacy XCOM/XITR still work; ZJIT needs g++/clang")

    if not args.no_vscode:
        install_vscode()

    if IS_WIN:
        register_windows_icons()
    elif IS_MAC:
        install_macos_app()
    else:
        install_linux_icons()

    verify_install()
    banner("DONE")
    x = shutil.which("x") or (_x_script_dir() / "x" if _x_script_dir() else None)
    print("""
  Everything is set up. Now:

    1. Write X++ pseudocode in any editor (VS Code, Notepad, anything):
             out "hello world"
       (save as  hello.xp )

    2. Run it:
             x run hello.xp          <- native VM (ZITR)
             x run hello.xp --mode ZJIT   <- fastest (native AOT)
                                                    
       In VS Code: open the folder, press the Code Runner play button.
       .xp files now show the X++ logo in VS Code / Explorer / Finder.

    Optional AI mode (RNM=ITR): export OPENROUTER_API_KEY, then
             x run ai_demo.xp --mode ITR
""")


if __name__ == "__main__":
    main()
