"""Repeat the unmodified production updater with a fresh profile in each disposable hosted trial."""
import os
from pathlib import Path
import subprocess
import sys
import time

if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted" or os.environ.get("CI") != "true":
    raise SystemExit("This fixture requires a disposable GitHub-hosted runner")
root = Path(os.environ["RUNNER_TEMP"]).resolve()
scratch = root / "cookie-trials"
scratch.mkdir()
support = Path.home() / "Library/Application Support/Kaizu"
if support.exists():
    raise SystemExit("Expected a fresh account without a Kaizu profile")
fixture = Path(".github/scripts/check-release-launch.py").resolve(strict=True)
archive = (root / "artifact/Kaizu.zip").resolve(strict=True)
outcomes = []
for trial in range(1, 7):
    folder = scratch / str(trial)
    folder.mkdir()
    subprocess.run(["ditto", "-x", "-k", archive, folder], check=True)
    app = folder / "Kaizu.app"
    subprocess.run(["codesign", "--verify", "--strict", app], check=True)
    print(f"Trial {trial}", flush=True)
    result = subprocess.run([sys.executable, "-u", fixture, app, "--signed-update"], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    print(result.stdout, flush=True)
    lost_cookie = "restored launch: login cookie missing" in result.stdout
    if result.returncode and not lost_cookie:
        raise SystemExit(f"Trial {trial} failed before its login result")
    outcomes.append("cookie missing" if lost_cookie else "cookie and storage restored")
    # After a failed page assertion the test app can still be open.
    subprocess.run(["osascript", "-e", 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'],
                   check=True, timeout=20)
    time.sleep(2)
    support.rename(folder / "finished-test-profile")
    print(f"Trial {trial} result: {outcomes[-1]}", flush=True)
print("All trial outcomes:", outcomes, flush=True)
if "cookie missing" in outcomes:
    raise SystemExit("The production updater lost at least one generated test login")
