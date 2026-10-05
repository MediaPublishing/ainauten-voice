#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent

def run_command(cmd, shell=False):
    print(f"[Build] Führe aus: {' '.join(cmd) if isinstance(cmd, list) else cmd}", flush=True)
    res = subprocess.run(cmd, shell=shell, cwd=str(PROJECT_ROOT))
    if res.returncode != 0:
        print(f"[Build] FEHLER bei Befehl: {cmd}", flush=True)
        sys.exit(res.returncode)

def main():
    print("=========================================")
    print("  LocalWhisper Native Swift Build Script ")
    print("=========================================")

    dist_dir = PROJECT_ROOT / "dist"
    build_dir = PROJECT_ROOT / "build"
    
    # 1. Clean previous build folders
    if dist_dir.exists():
        print("[Build] Bereinige altes dist/-Verzeichnis...", flush=True)
        shutil.rmtree(dist_dir)
    if build_dir.exists():
        print("[Build] Bereinige altes build/-Verzeichnis...", flush=True)
        shutil.rmtree(build_dir)
        
    dist_dir.mkdir(exist_ok=True)

    # 2. Check and install Python compile dependencies
    print("[Build] Überprüfe Python-Build-Abhängigkeiten...", flush=True)
    pip_cmd = ["pip", "install", "pyinstaller", "rumps"]
    if shutil.which("uv"):
        pip_cmd = ["uv", "pip", "install", "pyinstaller", "rumps"]
    run_command(pip_cmd)

    # 3. Compile Python Backend with PyInstaller (One-Directory Mode)
    print("[Build] Starte PyInstaller für den Python-Hintergrunddienst (One-Directory)...", flush=True)
    
    # Resolve pyinstaller path dynamically from virtual env
    pyinstaller_bin = "pyinstaller"
    venv_bin = PROJECT_ROOT / ".venv" / "bin" / "pyinstaller"
    if venv_bin.exists():
        pyinstaller_bin = str(venv_bin)
    else:
        sys_bin = Path(sys.executable).parent / "pyinstaller"
        if sys_bin.exists():
            pyinstaller_bin = str(sys_bin)

    pycommand = [
        pyinstaller_bin,
        "--clean",
        "-y",
        "--name=LocalWhisperBackend",
        "--onedir",
        "--add-data=web:web",  # flask web views
        "main.py"
    ]
    run_command(pycommand)

    # 4. Compile Swift Frontend using swiftc
    print("[Build] Starte native Swift-Kompilierung (swiftc)...", flush=True)
    
    # Locate SDK path
    sdk_path_proc = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], capture_output=True, text=True)
    sdk_path = sdk_path_proc.stdout.strip()
    if not sdk_path:
        print("[Build] FEHLER: macOS SDK-Pfad konnte nicht ermittelt werden!", flush=True)
        sys.exit(1)
        
    swift_bin_path = dist_dir / "LocalWhisper"
    swift_cmd = [
        "swiftc",
        "-sdk", sdk_path,
        "-parse-as-library",
        "LocalWhisper.swift",
        "-o", str(swift_bin_path)
    ]
    run_command(swift_cmd)
    
    if not swift_bin_path.exists():
        print("[Build] FEHLER: Swift-Kompilierung fehlgeschlagen!", flush=True)
        sys.exit(1)
    print("[Build] Swift-GUI-Anwendung erfolgreich kompiliert.", flush=True)

    # 5. Build macOS .app bundle directory structure
    print("[Build] Erstelle macOS .app Struktur...", flush=True)
    app_dir = dist_dir / "LocalWhisper.app"
    contents_dir = app_dir / "Contents"
    macos_dir = contents_dir / "MacOS"
    resources_dir = contents_dir / "Resources"
    
    macos_dir.mkdir(parents=True, exist_ok=True)
    resources_dir.mkdir(parents=True, exist_ok=True)
    
    # 1. Copy Swift executable as main app binary
    shutil.copy2(swift_bin_path, macos_dir / "LocalWhisper")
    swift_bin_path.unlink()  # remove temp swift bin in dist
    
    # 2. Copy Info.plist
    shutil.copy2(PROJECT_ROOT / "Info.plist", contents_dir / "Info.plist")
    
    # 2b. Copy AppIcon.icns if exists
    icon_file = PROJECT_ROOT / "AppIcon.icns"
    if icon_file.exists():
        print("[Build] Kopiere App-Icon (AppIcon.icns) in Ressourcen...", flush=True)
        shutil.copy2(icon_file, resources_dir / "AppIcon.icns")
    
    # 3. Copy PyInstaller compiled folder into Resources/python_backend
    print("[Build] Bündele Python-Hintergrunddienst im App-Ressourcen-Ordner...", flush=True)
    backend_src = dist_dir / "LocalWhisperBackend"
    backend_dest = resources_dir / "python_backend"
    
    # Copy directory structure
    shutil.copytree(backend_src, backend_dest, symlinks=True)
    shutil.rmtree(backend_src) # clean temp folder
    
    print(f"[Build] App-Bundle erfolgreich gebaut unter: {app_dir}", flush=True)

    # 6. Package into .dmg Disk Image
    dmg_path = dist_dir / "LocalWhisper.dmg"
    print(f"[Build] Erstelle macOS DMG-Installer: {dmg_path}...", flush=True)
    
    dmg_temp_dir = PROJECT_ROOT / "dmg_temp"
    if dmg_temp_dir.exists():
        shutil.rmtree(dmg_temp_dir)
    dmg_temp_dir.mkdir()
    
    # Copy App to DMG temp
    shutil.copytree(app_dir, dmg_temp_dir / "LocalWhisper.app", symlinks=True)
    
    # Create symlink to /Applications
    os.symlink("/Applications", dmg_temp_dir / "Programme")
    
    hdiutil_cmd = [
        "hdiutil", "create",
        "-volname", "LocalWhisper",
        "-srcfolder", str(dmg_temp_dir),
        "-ov",
        "-format", "UDZO",
        str(dmg_path)
    ]
    run_command(hdiutil_cmd)
    
    # Clean up temp dmg directory
    shutil.rmtree(dmg_temp_dir)
    
    print("=========================================")
    print("[Build] ERFOLG! Native macOS Swift-App ist bereit.")
    print(f"-> Native App: {app_dir}")
    print(f"-> DMG-Installer: {dmg_path}")
    print("=========================================")

if __name__ == "__main__":
    main()
