"""Summarize native encoder messages while a disposable GitHub Mac runs synthetic calls."""
from collections import Counter
import json
import os
import signal
import subprocess
import sys
import threading


def collect(stream, counts):
    errors = Counter()
    for line in stream:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        message = event.get("eventMessage", "")
        if not message or any(term in message.lower() for term in ("credential", "candidate:", "password", "ice-pwd", "://")):
            continue
        process = os.path.basename(event.get("processImagePath", ""))
        counts[process] += 1
        error = any(term in message.lower() for term in ("error", "failed", "failure", "denied", "unavailable"))
        if error:
            errors[process] += 1
        if counts[process] <= 15 or (error and errors[process] <= 120):
            print(f"Native encoder {event.get('timestamp')} {process}: {message[:450]}", flush=True)


if __name__ == "__main__":
    if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted" or os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("Requires the disposable hosted account")
    predicate = ('(process BEGINSWITH "com.apple.WebKit" OR process CONTAINS[c] "VTEncoder" '
                 'OR subsystem BEGINSWITH "com.apple.videotoolbox" OR process == "Kaizu" OR process == "webkit-control") '
                 'AND (eventMessage CONTAINS[c] "encoder" OR eventMessage CONTAINS[c] "VTCompression" '
                 'OR eventMessage CONTAINS[c] "VideoToolbox" OR eventMessage CONTAINS[c] "H264")')
    with subprocess.Popen(["/usr/bin/log", "stream", "--style", "ndjson", "--level", "debug", "--predicate", predicate],
                          stdout=subprocess.PIPE, text=True, errors="replace") as logger:
        counts = Counter()
        reader = threading.Thread(target=collect, args=(logger.stdout, counts))
        reader.start()
        try:
            result = subprocess.run(sys.argv[1:])
        finally:
            logger.send_signal(signal.SIGINT)
            try:
                logger.wait(timeout=5)
            except subprocess.TimeoutExpired:
                logger.kill()
                logger.wait()
            reader.join()
            print("Native encoder event counts:", dict(counts), flush=True)
    sys.exit(result.returncode)
