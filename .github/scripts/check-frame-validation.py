"""Check that the actual release gate detects wrong decoded color and dimensions."""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import unquote

if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted" or os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("Requires a disposable hosted Mac")
app = Path(sys.argv[1]).resolve(strict=True)
scratch = Path(sys.argv[2])
session = Path.home() / "Library/Application Support/Kaizu"
if session.exists():
    raise SystemExit("Expected an unused hosted session")
source = Path(__file__).parent
for case in ("correct", "green", "wrong-size"):
    fixture = scratch / case
    fixture.mkdir()
    for name in ("check-release-launch.py", "check-media-call.html", "check-video-source.js"):
        shutil.copy2(source / name, fixture / name)
    if case == "green":
        worker = fixture / "check-video-source.js"
        content = worker.read_text()
        for a, b in (("number % 2 ? 224 : 32", "32"), ("number % 2 ? 32 : 224", "32"), ("pixels[i + 1] = 48", "pixels[i + 1] = 224")):
            assert a in content
            content = content.replace(a, b)
        worker.write_text(content)
    if case == "wrong-size":
        # The worker still emits 640×480. Ask the validator to require 800×600 instead.
        page = fixture / "check-media-call.html"
        content = page.read_text()
        for a, b in (("fromWorker ? 640", "fromWorker ? 800"), ("fromWorker ? 480", "fromWorker ? 600"),
                     ("worker.postMessage({width, height})", "worker.postMessage({width: 640, height: 480})")):
            assert a in content
            content = content.replace(a, b)
        page.write_text(content)
    try:
        with (fixture / "test.log").open("w+") as log:
            test = subprocess.run([sys.executable, str(fixture / "check-release-launch.py"), str(app), "--media-call"],
                                  env=dict(os.environ, KAIZU_TEST_VIDEO_SOURCE="frames"),
                                  stdout=log, stderr=subprocess.STDOUT, timeout=140)
            log.seek(0)
            output = log.read()
        if case == "correct":
            if test.returncode or "decoded non-silent audio, rendered video and echoed" not in output:
                raise SystemExit(output[-3500:])
            print("Correct color and 640×480 H.264 passed the packaged check.", flush=True)
            continue
        failures = [line for line in output.splitlines() if line.startswith("/media-call/failure?message=")]
        if not test.returncode or not failures:
            raise SystemExit("Missing expected rejection: " + output[-3500:])
        message = unquote(failures[-1].split("message=", 1)[1])
        state = json.loads(message[message.index("{"):])
        page = state["page"]
        videos = [r for r in state["receiver"]["media"] if r.get("direction") == "inbound-rtp" and r.get("kind") == "video"]
        if not (page["echoed"] and state["receiver"]["relay"] and page["firstRendered"] == [640, 480]
                and any(r.get("codec", "").lower() == "video/h264" and r["frames"] > 0 for r in videos)):
            raise SystemExit("Expected rendered H.264 and working data: " + message)
        if case == "green" and "did not contain the generated color" not in message:
            raise SystemExit(message)
        if case == "wrong-size" and ("Timeout during waiting for video and data" not in message or page["expected"] != [800, 600]):
            raise SystemExit(message)
        print(f"{case}: rejected rendered 640×480 H.264, {videos[0]['frames']} decoded frames, relay and echo confirmed.", flush=True)
    finally:
        subprocess.run(["osascript", "-e", 'if application id "com.joinprototype.kaizu" is running then tell application id "com.joinprototype.kaizu" to quit'], check=True, timeout=35)
        end = time.monotonic() + 30
        while subprocess.run(["pgrep", "-x", "Kaizu"], stdout=subprocess.DEVNULL).returncode == 0:
            if time.monotonic() >= end: raise SystemExit("The packaged app remained open")
            time.sleep(.25)
        if session.exists(): session.rename(scratch / ("session-" + case))
