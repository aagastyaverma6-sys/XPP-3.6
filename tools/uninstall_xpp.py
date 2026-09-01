#!/usr/bin/env python3
"""
X++ (XPlusPlus) uninstaller / cleanup tool.

Safely removes X++ install artifacts that were placed on the system by the
official X++ setup (setup.bat / setup.sh / setup.command / xpp_setup.py).

  * pip package "xpp-lang" and its console scripts (x, xpp, xite)
  * native VM (xppvm) and its ZJIT runtime header
  * user-level shims/bins (~/.xpp, ~/.local/bin, /usr/local/bin)
  * Windows registry file-type registration (.xp / XppSourceFile)
  * Linux MIME/desktop/hicolor file icons
  * macOS "X++ Files.app" handler
  * VS Code extension + Code Runner / settings changes made by setup
  * shell profile PATH blocks added by setup
  * optional deep find of XPP/xite-named binaries and folders anywhere

Safety semantics (IMPORTANT):

  * DEFAULT MODE IS DRY-RUN. Nothing is changed until you pass --yes.
  * Your source-code `.xp` files are NEVER touched.
  * The repository/folder that contains this script is NEVER touched unless
    you pass --include-repo.
  * A deep name find only considers XPP/Xite *install-like* names; it is a
    heuristic, so review --dry-run output before running --yes --deep.

Examples:
  python3 tools/uninstall_xpp.py                  # dry-run (safe, fast)
  python3 tools/uninstall_xpp.py --verbose        # dry-run with details
  python3 tools/uninstall_xpp.py --yes            # really remove known installs
  python3 tools/uninstall_xpp.py --yes --deep     # also clean xpp-named folders
  python3 tools/uninstall_xpp.py --yes --full     # scan whole filesystem (slower)
"""

import argparse
import fnmatch
import json
import os
import re
import shutil
import site
import subprocess
import sys
import sysconfig
import textwrap
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants / protections
# ---------------------------------------------------------------------------
SCRIPT = Path(__file__).resolve()
REPO_ROOT = SCRIPT.parent.parent  # xpp repo that contains this script
HOME = Path.home()

# This script never removes these (they have no business being deleted).
HARD_PROTECTED = {
    Path("/") if os.name != "nt" else Path("C:\\"),
    HOME,
    REPO_ROOT,
}

# Substrings that make a path "the wrong kind of xpp" on the system roots.
# These are just extra exclusions for deep/full scans.
SYSTEM_NO_WALK = {
    # Linux/macOS pseudo + package dirs
    "/proc", "/sys", "/dev", "/run", "/tmp", "/var", "/snap",
    "/boot", "/srv", "/lost+found", "/mnt", "/media", "/initrd",
    # Windows system / appstore areas we should not walk wholesale
    "C:\\Windows", "C:\\Program Files\\WindowsApps", "C:\\ProgramData\\Package Cache",
    "C:\\$Recycle.Bin", "C:\\System Volume Information",
}

# X++ name patterns used for the deep/full "anywhere" find.
# These match install-like things, NOT .xp source programs.
DEEP_NAME_PATTERNS = [
    "xpp", "xppvm", "xppvm.exe", "xppvm.bat",
    "xppvm*", "xpp-lang*", "xpp_lang*", "xpp_core*", "xpp-*",
    "XPP*", "XPP-*", "X++*", "XPlusPlus*", "xplusplus*",
    "xite", "xite.py", "xite.exe", "xite-group*", "xite*",
    "zjit_runtime.hpp", "X++ Files.app", "xpp.xml", "xpp.desktop",
    "xpp.ico", "xpp.icns", "xpp.png", "xpp-logo*",
]

# We never auto-remove these even in --deep --full.
DEEP_EXCLUDE_EXTENSIONS = {".xp", ".xpp", ".xbc", ".zexe", ".src.cpp"}


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
def log(msg):
    print(msg)


def info(msg):
    print("[*] " + msg)


def warn(msg):
    print("[!] " + msg)


def is_protected(path: Path) -> bool:
    """True if this path is the user home, repo, system root, or a drive root."""
    try:
        p = path.resolve()
    except OSError:
        p = path
    if p in HARD_PROTECTED:
        return True
    if p == Path(p.anchor):
        return True
    return False


def is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (OSError, ValueError):
        return False


def is_xpp_shim(path: Path) -> bool:
    """True if a script/lib at path looks like the X++ 'x' shim (not another tool)."""
    try:
        with open(path, "rb") as f:
            head = f.read(4096)
    except OSError:
        return False
    low = head.lower()
    return (b"xpp_core" in low or b"xpp-lang" in low or b"xplusplus" in low
            or b"x++" in low or b"xite" in low)


def safe_unlink(path: Path, verbose=False):
    if path.exists() or path.is_symlink():
        if verbose:
            info(f"removing file: {path}")
        if path.is_symlink() or path.is_file():
            path.unlink(missing_ok=True)
        else:
            shutil.rmtree(path, ignore_errors=True)


class Vestige:
    """One thing the uninstaller found (file, dir, registry key, edit...)."""

    def __init__(self, kind, what, detail="", apply_fn=None):
        self.kind = kind  # file | dir | registry | path_edit | settings_edit | cmd
        self.what = what
        self.detail = detail
        self.apply_fn = apply_fn

    def __repr__(self):
        return f"[{self.kind}] {self.what}"


class Cleaner:
    def __init__(self, args):
        self.args = args
        self.items = []  # list[Vestige]
        self.seen = set()
        self.matched_dirs = 0
        self.matched_files = 0

    def add(self, kind, what, detail="", apply_fn=None):
        what_s = str(what)
        key = (kind, what_s)
        if key in self.seen:
            return
        self.seen.add(key)
        self.items.append(Vestige(kind, what, detail, apply_fn))
        if kind == "dir":
            self.matched_dirs += 1
        elif kind in ("file", "registry", "cmd"):
            self.matched_files += 1

    # -- path helpers -----------------------------------------------------
    def add_path(self, path: Path, detail=""):
        if path == REPO_ROOT or is_protected(path):
            return
        if is_under(path, REPO_ROOT) and not self.args.include_repo:
            return
        if not path.exists() and not path.is_symlink():
            return
        if path.is_dir():
            self.add("dir", path, detail)
        else:
            self.add("file", path, detail)

    # -- scans ------------------------------------------------------------
    def scan_python_package(self):
        info("Scanning Python package (pip xpp-lang) ...")
        # pip metadata
        try:
            r = subprocess.run(
                [sys.executable, "-m", "pip", "show", "xpp-lang"],
                capture_output=True, text=True, timeout=20)
            text = r.stdout
        except Exception:
            text = ""
        if text.strip():
            for line in text.splitlines():
                if line.lower().startswith("location:"):
                    loc = line.split(":", 1)[1].strip()
                    self._scan_python_site(Path(loc))
                if line.lower().startswith("editable project location:"):
                    loc = line.split(":", 1)[1].strip()
                    self.add_path(Path(loc), "pip editable install for xpp-lang")
                if line.lower().startswith("installer:") and "pip" not in line.lower():
                    pass

        # known site-packages locations (fast)
        bases = []
        for loc in (sysconfig.get_paths().get("purelib"),
                    sysconfig.get_paths().get("platlib"),
                    site.getsitepackages() if hasattr(site, "getsitepackages") else (),
                    site.getusersitepackages()):
            if isinstance(loc, (list, tuple)):
                bases.extend([l for l in loc if l])
            elif loc:
                bases.append(loc)
        for base in bases:
            self._scan_python_site(Path(base))

        self._scan_console_scripts()

    def _scan_python_site(self, base: Path):
        if not base.exists() or is_protected(base):
            return
        if is_under(base, REPO_ROOT) and not self.args.include_repo:
            return
        info(f"  scanning site-packages: {base}")
        try:
            entries = list(base.iterdir())
        except OSError:
            return
        for e in entries:
            n = e.name.lower()
            if (
                n.startswith("xpp_lang-") or n.startswith("xpp-lang-")
                or n.startswith("xpp_core") or n == "xite"
                or n.startswith("__editable__") and "xpp" in n
                or n == "x_engine.py" or n == "xite.py"
                or n == "xpp-lang.egg-link"
            ):
                self.add_path(e, "X++ Python package files")
            # dist-info could be xpp-lang seen by pip? covered by xpp_lang-.
            if n.startswith("xpp") and n.endswith((".egg-info", ".dist-info")):
                self.add_path(e, "X++ python dist metadata")

    def _scan_console_scripts(self):
        for name in ("x", "xpp", "xite", "xppvm", "x-script.py",
                     "xpp-script.py", "xite-script.py"):
            for cand in self._which_candidates(name):
                p = Path(cand)
                # For the ambiguous plain `x` command, only the X++ shim is
                # removed; never another tool that happens to be named x.
                if name in ("x", "x-script.py") and not is_xpp_shim(p):
                    continue
                # Only delete known X++ locations; a system binary literally
                # named `x` (unlikely) is left alone unless it is under
                # our known X++ install dirs.
                if is_under(p, HOME / ".xpp") or is_under(p, HOME / ".local/bin"):
                    self.add_path(p, "X++ console script / shim")
                elif p.parent.name.lower() == "scripts" and (
                    p.name.lower() in ("x.exe", "xpp.exe", "xite.exe",
                                       "x-script.py", "xpp-script.py", "xite-script.py")
                ):
                    self.add_path(p, "X++ pip console script")

    def _which_candidates(self, name):
        seen = set()
        w = shutil.which(name, mode=os.F_OK | os.X_OK)
        if w and w not in seen:
            seen.add(w)
            yield w
        # common windows locations even if not on PATH
        if os.name == "nt":
            roots = []
            if os.environ.get("LOCALAPPDATA"):
                roots.append(Path(os.environ["LOCALAPPDATA"]) / "Programs" / "Python")
            for r in roots:
                if r.exists():
                    for p in r.rglob(name + ".exe"):
                        yield p
        # mac/linux path candidates
        for p in (HOME / ".local/bin", HOME / ".xpp/bin", Path("/usr/local/bin")):
            for suffix in ("", ".exe", ".bat", ".cmd", ".py"):
                cand = p / (name + suffix)
                if cand.exists():
                    yield cand

    def scan_user_install_dirs(self):
        info("Scanning user-level X++ install dirs ...")
        candidates = []
        candidates.append(HOME / ".xpp")
        candidates.append(HOME / ".xppvm")
        candidates.append(HOME / ".local" / "bin" / "x")
        candidates.append(HOME / ".local" / "bin" / "xpp")
        candidates.append(HOME / ".local" / "bin" / "xite")
        candidates.append(HOME / ".local" / "bin" / "xppvm")
        candidates.append(HOME / ".local" / "bin" / "zjit_runtime.hpp")
        candidates.append(HOME / ".local" / "share" / "xpp")
        candidates.append(HOME / ".local" / "share" / "mime" / "packages" / "xpp.xml")
        candidates.append(HOME / ".local" / "share" / "applications" / "xpp.desktop")
        candidates.append(HOME / "Applications" / "X++ Files.app")
        candidates.append(Path("/usr/local/bin/xppvm"))
        candidates.append(Path("/usr/local/bin/zjit_runtime.hpp"))
        candidates.append(Path("/usr/local/share/xpp"))
        candidates.append(Path("/opt/xpp"))
        candidates.append(Path("/opt/XPP"))
        for p in candidates:
            if p.name in ("x", "x.cmd", "x.bat") and not is_xpp_shim(p):
                continue
            self.add_path(p, "user/system X++ install artifact")

        # hicolor icons
        share = HOME / ".local" / "share" / "icons" / "hicolor"
        if share.exists():
            for p in share.rglob("xpp.png"):
                self.add_path(p, "X++ hicolor icon")
        # older ~/.icons
        icons_root = HOME / ".icons"
        if icons_root.exists():
            for p in icons_root.rglob("xpp.png"):
                self.add_path(p, "X++ icon")

    def scan_vscode(self):
        info("Scanning VS Code X++ integration ...")
        if os.name == "nt":
            ext_roots = [HOME / "AppData" / "Roaming" / "Code" / "User",
                         HOME / ".vscode" / "extensions",
                         HOME / ".vscode-server" / "extensions"]
            user_settings = HOME / "AppData" / "Roaming" / "Code" / "User" / "settings.json"
        elif sys.platform == "darwin":
            ext_roots = [HOME / "Library" / "Application Support" / "Code" / "User",
                         HOME / ".vscode" / "extensions",
                         HOME / ".vscode-server" / "extensions"]
            user_settings = HOME / "Library" / "Application Support" / "Code" / "User" / "settings.json"
        else:
            ext_roots = [HOME / ".config" / "Code" / "User",
                         HOME / ".vscode" / "extensions",
                         HOME / ".vscode-server" / "extensions"]
            user_settings = HOME / ".config" / "Code" / "User" / "settings.json"

        # extension installs created by X++ setup
        global_vscode = _vscode_global_ext_dir()
        for root in list(ext_roots) + ([global_vscode] if global_vscode else []):
            if not root or not root.exists():
                continue
            if root.name == "User":
                continue
            try:
                for child in root.iterdir():
                    if "xpp" in child.name.lower() or "xite" in child.name.lower():
                        self.add_path(child, "VS Code X++ extension")
            except OSError:
                pass
        # extension command invocation
        code = _find_code()
        if code and not self.args.dry_run and not self.args.no_cli:
            self.add(
                "cmd", f"{code} --uninstall-extension atom-software.xpp-lang",
                "uninstall VS Code X++ extension via CLI")
        # settings.json entries created by setup
        self._scan_vscode_settings(user_settings)

    def _scan_vscode_settings(self, settings: Path):
        if not settings.exists():
            return
        try:
            data = json.loads(settings.read_text(encoding="utf-8"))
        except Exception:
            return
        changed = False
        if data.get("workbench", {}).get("iconTheme") == "xpp-file-icons":
            data["workbench"].pop("iconTheme", None)
            if not data.get("workbench"):
                data.pop("workbench", None)
            changed = True
        files = data.get("files", {})
        if files.get("associations", {}).get("*.xp") == "xpp":
            files["associations"].pop("*.xp", None)
            if not files.get("associations"):
                files.pop("associations", None)
            if not files:
                data.pop("files", None)
            changed = True
        cr = data.get("code-runner.executorMap", {})
        if ".xp" in cr:
            cr.pop(".xp", None)
            if not data.get("code-runner.executorMap"):
                data.pop("code-runner.executorMap", None)
            changed = True
        if changed:
            self.add(
                "settings_edit", settings,
                "remove X++ icon/Code Runner bits from VS Code settings",
                apply_fn=lambda: _write_json_settings(settings, data))

    def scan_windows_registry(self):
        if os.name != "nt":
            return
        info("Scanning Windows registry ...")
        import winreg
        keys = [
            r"Software\Classes\.xp",
            r"Software\Classes\XppSourceFile",
            r"Software\Classes\XppSourceFile\DefaultIcon",
            r"Software\Classes\XppSourceFile\shell\run",
            r"Software\Classes\XppSourceFile\shell\run\command",
            r"Software\Classes\XppSourceFile\shell\edit",
            r"Software\Classes\XppSourceFile\shell\edit\command",
            r"Software\Classes\XppSourceFile\shell\open",
            r"Software\Classes\XppSourceFile\shell\open\command",
            r"Software\Classes\XppSourceFile\shell\open\command",
        ]
        for key in keys:
            self.add("registry", key, "Windows .xp / X++ file-type registration",
                     apply_fn=lambda k=key: _winreg_delete(k))

    def scan_shell_profiles(self):
        info("Scanning shell profiles for X++ PATH blocks ...")
        if os.name == "nt":
            return
        profs = [HOME / ".profile", HOME / ".bashrc", HOME / ".zshrc",
                 HOME / ".zprofile", HOME / ".bash_profile"]
        block_re = re.compile(r"#\s*----\s*X\+\+.*?----")
        for prof in profs:
            if not prof.exists():
                continue
            body = prof.read_text(errors="ignore")
            if "# ---- X++" not in body and "XPP_NATIVE_DIR" not in body:
                continue
            self.add(
                "path_edit", prof,
                "remove X++ PATH block added by setup",
                apply_fn=lambda f=prof: _remove_xpp_block(f))

    def scan_macos_duti(self):
        if sys.platform != "darwin" or shutil.which("duti") is None:
            return
        self.add("cmd", "duti -x com.atomsoftware.xpp xpp",
                 "forget macOS X++ handler association")

    # -- deep / full ------------------------------------------------------
    def scan_deep(self, full=False):
        info("Deep name scan (XPP/ Xite install-like names) ...")
        if full:
            # HOME is a protected search root, but we still walk it; the walker
            # skips the protected repo folder and other protected paths below.
            roots = _system_roots() + [HOME]
        else:
            roots = [HOME]
            if os.name == "nt":
                for d in (Path(os.environ.get("USERPROFILE", "")),
                          Path(os.environ.get("PUBLIC", ""))):
                    if d.exists():
                        roots.append(d)
            else:
                for d in (Path("/usr/local"), Path("/opt")):
                    if d.exists():
                        roots.append(d)
        for root in roots:
            if not root.exists():
                continue
            # A protected root is still a valid *search* root (we only skip
            # protected descendants), so do not `continue` on is_protected here.
            for p in self._iter_fast(root, full=full):
                self._match_deep(p)

    def _iter_fast(self, root, full=False):
        """Bounded, fast-walk generator with the obvious system dirs skipped."""
        stack = [root]
        while stack:
            cur = stack.pop()
            try:
                if str(cur) in SYSTEM_NO_WALK or (cur.name and cur.name.lower() in (
                        "node_modules", ".git", "__pycache__", ".venv", "venv",
                        ".cache", ".npm", ".nuxt", "target", "dist", "build",
                        ".next", "out", ".mypy_cache", ".pytest_cache",
                        ".ruff_cache", ".tox", ".direnv", ".snap")):
                    continue
                entries = list(cur.iterdir())
            except (OSError, PermissionError):
                continue
            for e in entries:
                if is_protected(e):
                    continue
                if is_under(e, REPO_ROOT) and not self.args.include_repo:
                    continue
                if e.is_symlink():
                    continue
                yield e
                if e.is_dir():
                    stack.append(e)

    def _match_deep(self, p: Path):
        name = p.name
        # Don't match .xp source files (they're user programs, not installs)
        if p.suffix.lower() in DEEP_EXCLUDE_EXTENSIONS:
            return
        for pat in DEEP_NAME_PATTERNS:
            if not fnmatch.fnmatch(name, pat):
                continue
            # For directories, require that the folder really looks like an
            # X++ install/source kit (setup.sh / native / xppvm / xite.py ...).
            # Otherwise we might delete a user project that just happens to
            # be called XPP.
            if p.is_dir():
                if not self._looks_like_xpp_dir(p):
                    return
            self.add_path(p, "deep X++/Xite name match")
            return

    @staticmethod
    def _looks_like_xpp_dir(p: Path) -> bool:
        signatures = ("setup.bat", "setup.sh", "setup.command",
                      "xppvm", "xppvm.exe", "native", "xpp_core",
                      "xite.py", "xite.exe", "tools", "xpp_setup.py",
                      "zjit_runtime.hpp")
        for s in signatures:
            if (p / s).exists():
                return True
        try:
            with open(p / "pyproject.toml", "rb") as f:
                if b"xpp-lang" in f.read(4096):
                    return True
        except OSError:
            pass
        return False

    # -- apply ------------------------------------------------------------
    def apply(self):
        if self.args.dry_run:
            return
        info(f"Applying changes: removing {len(self.items)} item(s) ...")
        for v in self.items:
            try:
                if v.kind == "file":
                    safe_unlink(Path(v.what), self.args.verbose)
                elif v.kind == "dir":
                    safe_unlink(Path(v.what), self.args.verbose)
                elif v.kind == "registry":
                    if v.apply_fn:
                        v.apply_fn()
                elif v.kind == "path_edit":
                    if v.apply_fn:
                        v.apply_fn()
                elif v.kind == "settings_edit":
                    if v.apply_fn:
                        v.apply_fn()
                elif v.kind == "cmd":
                    if v.apply_fn:
                        v.apply_fn()
                    else:
                        subprocess.run(v.what, shell=os.name == "nt")
            except Exception as e:
                warn(f"could not remove {v.what}: {e}")

    def report(self):
        print()
        print("=" * 78)
        print("  X++ cleanup dry-run / results")
        print("=" * 78)
        if not self.items:
            print("  No X++ install artifacts were found.")
        else:
            for v in self.items:
                print(f"  [{v.kind:<13}] {v.what}" + (f"\n                  {v.detail}" if v.detail else ""))
            print()
            print(f"  Total: {len(self.items)} item(s) to remove"
                  + ("" if not self.args.dry_run else "  (dry-run: nothing changed)"))
        if self.args.dry_run:
            print()
            print("  To really remove these, run with:  --yes")
            print("  Add --deep for XPP/xite-named folders, --full for whole disc.")


# ---------------------------------------------------------------------------
# OS-specific helpers
# ---------------------------------------------------------------------------
def _winreg_delete(key):
    import winreg
    try:
        winreg.DeleteKey(winreg.HKEY_CURRENT_USER, key)
    except FileNotFoundError:
        pass
    except OSError as e:
        warn(f"could not delete registry {key}: {e}")


def _write_json_settings(settings: Path, data):
    settings.write_text(json.dumps(data, indent=2), encoding="utf-8")


def _remove_xpp_block(path: Path):
    try:
        lines = path.read_text(errors="ignore").splitlines(keepends=True)
    except OSError:
        return
    out = []
    skipping = False
    removed = 0
    for line in lines:
        stripped = line.strip()
        if "# ---- X++" in stripped and "----" in stripped:
            skipping = True
            removed += 1
            continue
        if skipping:
            if stripped.startswith("# ----"):
                skipping = False
                out.append(line)
                continue
            if "EXPORT XPP_NATIVE_DIR" in stripped.upper() or "EXPORT PATH" in stripped.upper():
                removed += 1
                continue
            if not stripped:
                # end of block (blank)
                skipping = False
                removed += 1
                continue
            # still inside block-ish lines
            removed += 1
            continue
        out.append(line)
    path.write_text("".join(out), encoding="utf-8")
    if removed:
        info(f"removed {removed} X++ PATH block line(s) from {path}")


def _find_code():
    c = shutil.which("code")
    if c:
        return c
    if os.name == "nt":
        cands = [HOME / "AppData/Local/Programs/Microsoft VS Code/bin/code.cmd",
                 Path(r"C:\Program Files\Microsoft VS Code\bin\code.cmd")]
    elif sys.platform == "darwin":
        cands = [Path("/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"),
                 HOME / "Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]
    else:
        cands = [Path("/usr/bin/code"), Path("/usr/local/bin/code"),
                 HOME / ".local/bin/code"]
    for p in cands:
        if p.exists():
            return str(p)
    return None


def _vscode_global_ext_dir():
    if os.name == "nt":
        return HOME / ".vscode" / "extensions"
    return HOME / ".vscode" / "extensions"


def _system_roots():
    if os.name == "nt":
        roots = []
        for drive in "CDEFGH":
            p = Path(f"{drive}:\\")
            if p.exists():
                roots.append(p)
        return roots
    return [Path("/")]


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Find/remove X++ (XPlusPlus) install artifacts safely.")
    ap.add_argument("--yes", "-y", action="store_true",
                    help="actually delete/edit; without this, dry-run only")
    ap.add_argument("--deep", action="store_true",
                    help="also scan for XPP/xite-named install-like folders")
    ap.add_argument("--full", action="store_true",
                    help="with --deep, scan the whole filesystem (slower)")
    ap.add_argument("--verbose", "-v", action="store_true",
                    help="print each individual removal")
    ap.add_argument("--include-repo", action="store_true",
                    help="dangerous: allow cleaning the X++ repo containing this script")
    ap.add_argument("--no-cli", action="store_true",
                    help="do not shell out to VS Code / duti")
    args = ap.parse_args(argv)
    args.dry_run = not args.yes

    print()
    print("=" * 78)
    print("  X++ UNINSTALL / CLEANUP" + ("  (DRY-RUN - nothing is changed)"
          if args.dry_run else "  (LIVE)"))
    print("=" * 78)
    print(f"  Platform : {sys.platform} / {os.name}")
    print(f"  Repo     : {REPO_ROOT}  (protected{'} unless --include-repo' if args.include_repo else ''})")
    print(f"  Mode     : {'deep' if args.deep else 'targeted'}"
          + (" + full-disc" if args.full else "") + " scan")
    print()

    cleaner = Cleaner(args)
    cleaner.scan_python_package()
    cleaner.scan_user_install_dirs()
    cleaner.scan_vscode()
    cleaner.scan_windows_registry()
    cleaner.scan_shell_profiles()
    cleaner.scan_macos_duti()
    if args.deep:
        cleaner.scan_deep(full=args.full)

    cleaner.report()

    if args.dry_run:
        return 0
    if cleaner.items:
        print()
        answer = input(f"Type 'delete' to remove {len(cleaner.items)} X++ item(s): ").strip()
        if answer.lower() != "delete":
            print("Aborted. Nothing was changed.")
            return 1
    cleaner.apply()
    print("\nDone. Open a NEW terminal and run:  x version  (should be gone / not found).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
