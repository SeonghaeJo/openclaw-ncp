"""Small, side-effect-free helpers used by the OpenClaw NCP lifecycle."""
from __future__ import annotations

import datetime as dt
import ipaddress
import re

UBUNTU_RELEASE_RE = re.compile(r"(?<!\d)(\d{2})\.04(?!\d)")


def ubuntu_release_from_image(image: dict) -> str | None:
    """Extract a release from provider metadata, never from image number."""
    text = " ".join(str(image.get(key, "")) for key in ("name", "description"))
    match = UBUNTU_RELEASE_RE.search(text)
    return match.group(0) if match else None


def supported_lts_releases(today: dt.date | None = None) -> set[str]:
    today = today or dt.date.today()
    # Only releases in their normal support window are eligible. EOL images
    # remain possible only through an explicit, separately-reviewed override
    # outside this automatic selector (and are not silently adopted).
    releases = set()
    for year in range(2000, today.year + 1, 2):
        release = f"{year % 100:02d}.04"
        release_date = dt.date(year, 4, 1)
        standard_support_end = dt.date(year + 5, 5, 1)
        if release_date <= today < standard_support_end:
            releases.add(release)
    return releases


def compatible_images(images: list[dict], release: str | None = None) -> list[dict]:
    allowed = supported_lts_releases()
    result = []
    for image in images:
        if str(image.get("hypervisor_type", "")).upper() != "KVM":
            continue
        if str(image.get("os_type", "")).upper() != "UBUNTU":
            continue
        if "x86_64" not in str(image.get("cpu_architecture_type", "")).lower():
            continue
        found = ubuntu_release_from_image(image)
        if not found or found not in allowed or (release and found != release):
            continue
        result.append({**image, "ubuntu_release": found})
    return result


def choose_image(images: list[dict], release: str | None = None) -> dict:
    candidates = compatible_images(images, release)
    if not candidates:
        wanted = release or "the newest supported Ubuntu LTS"
        raise ValueError(f"NCP returned no compatible image for {wanted}")
    newest_release = max(c["ubuntu_release"] for c in candidates)
    same_release = [c for c in candidates if c["ubuntu_release"] == newest_release]
    # Prefer the most specific/base image deterministically; image number is
    # only a tie-breaker within one release, never across releases.
    def image_number(candidate: dict) -> int:
        try: return int(candidate.get("server_image_number", 0))
        except (TypeError, ValueError): return -1
    def image_text(candidate: dict) -> str:
        return (str(candidate.get("name", "")) + " " + str(candidate.get("description", ""))).lower()
    # Prefer a normal non-GPU base image. Within that class, the provider's
    # numeric image number is the deterministic final tie-breaker for one
    # release; it is never compared across releases.
    return max(same_release, key=lambda c: ("gpu" not in image_text(c), "base" in image_text(c), image_number(c)))


def compatible_specs(specs: list[dict], minimum_memory_gb: float = 4) -> list[dict]:
    result = []
    for spec in specs:
        if str(spec.get("hypervisor_type", "")).upper() != "KVM":
            continue
        if "x86_64" not in str(spec.get("cpu_architecture_type", "")).lower():
            continue
        try:
            memory_gb = float(spec.get("memory_size", 0)) / (1024 ** 3)
        except (TypeError, ValueError):
            continue
        if memory_gb < minimum_memory_gb:
            continue
        result.append({**spec, "memory_gb": memory_gb})
    return result


def choose_spec(specs: list[dict], minimum_memory_gb: float = 4) -> dict:
    candidates = compatible_specs(specs, minimum_memory_gb)
    if not candidates:
        raise ValueError("NCP returned no compatible x86_64/KVM server spec")
    return min(candidates, key=lambda s: (
        s["memory_gb"],
        int(s.get("cpu_count", 0) or 0),
        str(s.get("server_spec_code", "")),
    ))


def choose_zone(zones: list[dict], override: str | None = None) -> dict:
    candidates = sorted(zones, key=lambda z: str(z.get("zone_code", "")))
    if override:
        for zone in candidates:
            if zone.get("zone_code") == override:
                return zone
        raise ValueError(f"zone override {override!r} is not available in the selected region")
    if len(candidates) != 1:
        raise ValueError("multiple compatible zones are available; select one explicitly")
    return candidates[0]


def fingerprint_lines(scan_output: str) -> list[str]:
    """Return SHA256 host-key fingerprints from ssh-keyscan output."""
    import subprocess
    lines = []
    for line in scan_output.splitlines():
        if not line or line.startswith("#"):
            continue
        proc = subprocess.run(["ssh-keygen", "-lf", "-", "-E", "sha256"], input=line + "\n", text=True, capture_output=True)
        if proc.returncode == 0:
            fields = proc.stdout.split()
            if len(fields) >= 2 and fields[1].startswith("SHA256:"):
                lines.append(fields[1])
    return sorted(set(lines))


def fingerprint_for_key_line(line: str) -> str:
    import subprocess
    proc = subprocess.run(["ssh-keygen", "-lf", "-", "-E", "sha256"], input=line + "\n", text=True, capture_output=True, check=True)
    fields = proc.stdout.split()
    return fields[1]


def is_ipv4_cidr(value: str) -> bool:
    try:
        return ipaddress.ip_network(value, strict=False).version == 4 and ipaddress.ip_network(value, strict=False).prefixlen == 32
    except ValueError:
        return False
