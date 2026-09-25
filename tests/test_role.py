import pathlib
import unittest
import yaml
from jinja2 import Environment

ROOT = pathlib.Path(__file__).resolve().parents[1]
class RoleTests(unittest.TestCase):
    def test_yaml_modules_and_start_order(self):
        for p in (ROOT / 'ansible').rglob('*.yml'):
            yaml.safe_load(p.read_text())
        tasks = yaml.safe_load((ROOT / 'ansible/roles/openclaw/tasks/main.yml').read_text())
        names = [t['name'] for t in tasks]
        self.assertLess(names.index('Supply SecretRef before any service start'), names.index('Converge and verify service under its owner'))
        for task in tasks:
            self.assertFalse({'owner','group','mode'} & task.keys())
            self.assertNotIn('ansible.builtin.shell', task)
        dropin = next(t for t in tasks if t['name'] == 'Supply SecretRef before any service start')
        rendered = Environment(keep_trailing_newline=True).from_string(dropin['ansible.builtin.copy']['content']).render(openclaw_gateway_env_file='/home/operator/.config/openclaw/gateway.env')
        self.assertEqual(rendered, '[Service]\nEnvironmentFile=/home/operator/.config/openclaw/gateway.env\n')
    def test_ssh_verification_enabled(self):
        text = (ROOT / 'ansible/ansible.cfg').read_text()
        self.assertIn('host_key_checking = True', text)
        self.assertIn('StrictHostKeyChecking=yes', text)
