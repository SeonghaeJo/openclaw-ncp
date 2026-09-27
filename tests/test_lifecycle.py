import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from openclaw_lifecycle import choose_image, choose_spec, choose_zone, supported_lts_releases

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
        self.assertIn('security', text)
        self.assertIn('add-generic-password', text)
        self.assertIn('"-w"]', text)
        self.assertNotIn('24.04")}', text)
        self.assertNotIn('"KR-2"', text)
        self.assertIn('confirm("APPLY"', text)
        self.assertIn('confirm("DESTROY"', text)
        for forbidden in ("NCP_SECRET_KEY=", "OPENCLAW_GATEWAY_TOKEN="):
            self.assertNotIn(forbidden, text)

    def test_discovery_is_separate_from_resource_configuration(self):
        self.assertTrue((ROOT / "terraform-discovery/main.tf").exists())
        discovery = (ROOT / "terraform-discovery/main.tf").read_text()
        self.assertIn('data "ncloud_vpcs"', discovery)
        self.assertIn('data "ncloud_subnets"', discovery)
        self.assertIn('data "ncloud_zones"', discovery)
        self.assertIn('data "ncloud_server_image_numbers"', discovery)
        self.assertIn('data "ncloud_server_specs"', discovery)
        self.assertNotIn('resource "ncloud_', discovery)

    def test_image_selection_uses_release_not_image_number_across_releases(self):
        images = [
            {"server_image_number": "99999999", "name": "ubuntu-22.04-base", "description": "", "hypervisor_type": "KVM", "os_type": "UBUNTU", "cpu_architecture_type": "x86_64"},
            {"server_image_number": "100", "name": "ubuntu-24.04-base", "description": "", "hypervisor_type": "KVM", "os_type": "UBUNTU", "cpu_architecture_type": "x86_64"},
        ]
        self.assertEqual(choose_image(images)["ubuntu_release"], "24.04")
        self.assertEqual(choose_image(images, "22.04")["server_image_number"], "99999999")
        same_release = [
            {"server_image_number": "9", "name": "ubuntu-24.04-base", "description": "", "hypervisor_type": "KVM", "os_type": "UBUNTU", "cpu_architecture_type": "x86_64"},
            {"server_image_number": "10", "name": "ubuntu-24.04-base", "description": "", "hypervisor_type": "KVM", "os_type": "UBUNTU", "cpu_architecture_type": "x86_64"},
        ]
        self.assertEqual(choose_image(same_release)["server_image_number"], "10")

    def test_automatic_selection_excludes_eol_ubuntu(self):
        self.assertNotIn("20.04", supported_lts_releases())

    def test_zone_selection_fails_closed_without_override(self):
        with self.assertRaises(ValueError):
            choose_zone([{"zone_code": "KR-1"}, {"zone_code": "KR-2"}])
        self.assertEqual(choose_zone([{"zone_code": "KR-1"}], None)["zone_code"], "KR-1")

    def test_spec_selection_is_compatible_and_deterministic(self):
        specs = [
            {"server_spec_code": "xen", "hypervisor_type": "XEN", "cpu_architecture_type": "x86_64", "memory_size": 16 * 1024**3, "cpu_count": 2},
            {"server_spec_code": "c2-g3", "hypervisor_type": "KVM", "cpu_architecture_type": "x86_64", "memory_size": 4 * 1024**3, "cpu_count": 2},
        ]
        self.assertEqual(choose_spec(specs)["server_spec_code"], "c2-g3")


if __name__ == "__main__":
    unittest.main(verbosity=2)
