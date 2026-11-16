"""Import assets and launch the standalone boat demo at 1080p/60 FPS.

Planned output: only the existing project .godot import cache. No saved world,
export, capture or source copy is produced. The demo uses no archival artifacts.
"""
from pathlib import Path
import os
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
executable = os.environ.get('GODOT_EXE') or shutil.which('godot') or r'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
if not Path(executable).is_file():
    raise SystemExit('Set GODOT_EXE to your Godot 4.7 executable.')
result = subprocess.run([executable, '--headless', '--editor', '--path', str(root), '--import'])
if result.returncode:
    raise SystemExit(result.returncode)
raise SystemExit(subprocess.call([executable, '--path', str(root), '--rendering-method', 'forward_plus', '--fullscreen', '--resolution', '1920x1080', '--max-fps', '60', 'res://boat_demo/main.tscn']))
