"""Exercise the receiving video transport on actual relayed and direct calls."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import unquote

if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted" or os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("Requires a disposable GitHub-hosted Mac")
app = Path(sys.argv[1]).resolve(strict=True)
source = Path(__file__).parent
for case in ("relayed", "stale-pair-state", "direct"):
    with tempfile.TemporaryDirectory() as scratch:
        fixture = Path(scratch)
        for name in ("check-media-call.html", "check-release-launch.py", "check-video-source.js"):
            shutil.copy2(source / name, fixture / name)
        page = fixture / "check-media-call.html"
        html = page.read_text()
        if case == "stale-pair-state":
            marker = "    const reports = [...stats.values()];"
            assert marker in html
            html = html.replace(marker, """    stats = new Map([...stats].map(([key, report]) => [key,
                report.type === "candidate-pair" ? {...report, state: "in-progress"} : report]));
""" + marker)
        if case == "direct":
            marker = "new RTCPeerConnection(config)"
            assert html.count(marker) == 2
            # Establish a direct call while the assertion still requires TURN.
            html = html.replace(marker, "new RTCPeerConnection({iceServers: []})")
        marker = '    location.replace("/start");'
        assert marker in html
        html = html.replace(marker, """    const path = videoPath(receiver, await receiver.getStats());
    await fetch("/selected-path?result=" + encodeURIComponent(JSON.stringify(path)));
""" + marker)
        page.write_text(html)
        process = subprocess.run([sys.executable, str(fixture / "check-release-launch.py"), str(app), "--media-call"],
                                 env=dict(os.environ, KAIZU_TEST_VIDEO_SOURCE="frames"), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, timeout=120)
        lines = process.stdout.splitlines()
        if case == "direct":
            errors = [line for line in lines if line.startswith("/media-call/failure?message=")]
            if not errors or not process.returncode:
                raise SystemExit("Direct call did not fail the required relay check: " + process.stdout[-2500:])
            message = unquote(errors[-1].split("message=", 1)[1])
            state = json.loads(message[message.index("{"):])
            peer, page_info = state["receiver"], state["page"]
            decoded = any(r.get("kind") == "video" and r.get("codec", "").lower() == "video/h264" and r.get("frames", 0) > 0 for r in peer["media"])
            if peer["relay"] or "host" not in (peer["path"].get("local"), peer["path"].get("remote")) or not decoded or not page_info["echoed"]:
                raise SystemExit("Expected decoded video and echoed data on an identified direct path: " + message)
            print("Rejected connected direct call with decoded H.264:", peer["path"], flush=True)
        else:
            evidence = [line for line in lines if "GET /selected-path?result=" in line]
            if process.returncode or not evidence:
                raise SystemExit(f"{case}: " + unquote(process.stdout[-4000:]))
            path = json.loads(unquote(evidence[-1].split("result=", 1)[1].split(" HTTP/", 1)[0]))
            if path["local"] != "relay" or path["remote"] != "relay" or (case == "stale-pair-state" and path["source"] == "nominated pair"):
                raise SystemExit(f"{case}: unexpected transport {path}")
            print(f"{case}: rendered H.264, audio and echo verified on {path}", flush=True)
