#!/usr/bin/env python3
"""Resolve a current supported Node/OpenClaw pair without handling credentials."""
import json
import re
import sys
import urllib.request


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "openclaw-ncp-runtime-resolver"})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def main():
    requested = sys.argv[1] if len(sys.argv) > 1 else "latest"
    package = get("https://registry.npmjs.org/openclaw/" + requested)
    engines = str(package.get("engines", {}).get("node", ">=22"))
    majors = {int(x) for x in re.findall(r"(?:^|[^0-9])(2[0-9])(?:\\.[0-9]+)?", engines)}
    if not majors:
        majors = {22, 24}
    releases = [x for x in get("https://nodejs.org/dist/index.json") if x.get("lts") and int(x["version"].lstrip("v").split(".")[0]) in majors and x.get("files") and "linux-x64" in x["files"]]
    if not releases:
        raise SystemExit("no supported Node LTS release found")
    node = releases[0]
    version = node["version"].lstrip("v")
    archive = f"node-v{version}-linux-x64.tar.xz"
    sums = urllib.request.urlopen(f"https://nodejs.org/dist/v{version}/SHASUMS256.txt", timeout=30).read().decode()
    sha = next((line.split()[0] for line in sums.splitlines() if line.endswith(archive)), "")
    if not sha:
        raise SystemExit("Node archive checksum was not published")
    print(json.dumps({"openclaw_version": package["version"], "openclaw_tarball": package["dist"]["tarball"], "openclaw_integrity": package["dist"]["integrity"], "node_version": version, "node_sha256": sha}))


if __name__ == "__main__":
    main()
