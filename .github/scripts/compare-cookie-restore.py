import os
import subprocess
import sys
import time
from pathlib import Path

if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted" or os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("Requires a disposable hosted Mac")
session = Path.home() / "Library/Application Support/Kaizu"
if session.exists(): raise SystemExit("Expected a fresh account")
reader = os.environ["READER"]
if reader not in ("published", "candidate"): raise SystemExit("Unknown reader")
failures = 0
for number, seed in enumerate(("acknowledged", "disk", "disk", "acknowledged"), 1):
    print(f"Starting trial={number} seed={seed} reader={reader}", flush=True)
    root = Path(f"cookie-trial-{number}").resolve()
    root.mkdir()
    subprocess.run(["ditto", "-x", "-k", "previous.zip", str(root / "installed")], check=True)
    archive = "Kaizu.zip" if reader == "candidate" else "previous.zip"
    subprocess.run(["ditto", "-x", "-k", archive, str(root / "reader")], check=True)
    apps = [root / name / "Kaizu.app" for name in ("reader", "installed")]
    for app in apps:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    try:
        result = subprocess.run([sys.executable, "-u", str(Path(__file__).with_name("check-release-launch.py")), *map(str, apps)],
                                env=dict(os.environ, KAIZU_COOKIE_SEED=seed), timeout=135)
        print(f"Result trial={number} seed={seed} reader={reader} exit={result.returncode}", flush=True)
        failures += result.returncode != 0
    finally:
        subprocess.run(["osascript", "-e", 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'], check=True, timeout=35)
        end = time.monotonic() + 30
        while subprocess.run(["pgrep", "-x", "Kaizu"], stdout=subprocess.DEVNULL).returncode == 0:
            if time.monotonic() >= end: raise SystemExit("Kaizu did not quit cleanly")
            time.sleep(.25)
        if session.exists(): session.rename(root / "saved-session")
if failures: raise SystemExit(f"{failures} of four cookie comparisons failed")
