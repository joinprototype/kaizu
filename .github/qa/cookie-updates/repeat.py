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
    log = folder / "trial.log"
    with log.open("w") as output:
        try:
            result = subprocess.run([sys.executable, "-u", fixture, app, "--signed-update"],
                                    stdout=output, stderr=subprocess.STDOUT, timeout=240)
            passed = result.returncode == 0
        except subprocess.TimeoutExpired:
            passed = False
            print(f"Trial {trial} exceeded 240 seconds", flush=True)
    transcript = log.read_text()
    print(transcript, flush=True)
    if passed and "Restored the tab in its original space and profile" in transcript:
        outcome = "cookie and storage restored"
    elif "restored launch: login cookie missing" in transcript:
        outcome = "cookie missing"
    elif "restored launch: login cookie match, local storage missing" in transcript:
        outcome = "local storage missing"
    else:
        outcome = "incomplete"
    outcomes.append(outcome)
    # After a failed page assertion the test app can still be open.
    subprocess.run(["osascript", "-e", 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'],
                   check=True, timeout=20)
    time.sleep(2)
    if support.exists():
        support.rename(folder / "finished-test-profile")
    print(f"Trial {trial} result: {outcomes[-1]}", flush=True)
print("All trial outcomes:", outcomes, flush=True)
if any(outcome != "cookie and storage restored" for outcome in outcomes):
    raise SystemExit("One or more trials failed to demonstrate a complete restore")
