import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LifecycleTests(unittest.TestCase):
    def test_status_is_safe_without_a_profile(self):
        with tempfile.TemporaryDirectory() as d:
            env = {**os.environ, "OPENCLAW_NCP_CONFIG_DIR": str(Path(d) / "config"), "OPENCLAW_NCP_DATA_DIR": str(Path(d) / "data")}
            p = subprocess.run([str(ROOT / "openclaw"), "status"], cwd=ROOT, env=env, text=True, capture_output=True)
            self.assertEqual(p.returncode, 0)
            self.assertIn("No installation profile", p.stdout)
            self.assertNotIn("NCP_ACCESS_KEY", p.stdout + p.stderr)

    def test_profile_metadata_has_no_secret_fields(self):
        text = (ROOT / "openclaw").read_text()
        self.assertIn('secrets.token_urlsafe(48)', text)
        self.assertIn('secret-tool', text)
        self.assertIn('confirm("APPLY"', text)
        self.assertIn('confirm("DESTROY"', text)
        for forbidden in ("NCP_SECRET_KEY=", "OPENCLAW_GATEWAY_TOKEN="):
            self.assertNotIn(forbidden, text)

    def test_discovery_is_separate_from_resource_configuration(self):
        self.assertTrue((ROOT / "terraform-discovery/main.tf").exists())
        discovery = (ROOT / "terraform-discovery/main.tf").read_text()
        self.assertIn('data "ncloud_vpcs"', discovery)
        self.assertIn('data "ncloud_subnets"', discovery)
        self.assertNotIn('resource "ncloud_', discovery)


if __name__ == "__main__":
    unittest.main(verbosity=2)
