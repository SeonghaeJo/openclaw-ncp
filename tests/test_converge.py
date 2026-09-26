import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('converge', ROOT / 'ansible/roles/openclaw/files/converge.py')
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

class Tests(unittest.TestCase):
    def test_model_policy_is_explicit_and_legacy_model_is_removed(self):
        policy = c.desired('/tmp/workspace', 18789)['agents']
        self.assertEqual(policy['defaults']['model'], {
            'primary': 'openai/gpt-5.6-luna',
            'fallbacks': ['nvidia/nemotron-3-ultra-550b-a55b'],
        })
        self.assertEqual(policy['defaults']['utilityModel'], 'openai/gpt-5.6-luna')
        self.assertEqual(policy['defaults']['contextPruning'], {'mode': 'cache-ttl', 'ttl': '1h'})
        self.assertEqual(policy['defaults']['compaction'], {'mode': 'safeguard'})
        self.assertEqual(policy['defaults']['subagents']['maxConcurrent'], 3)
        self.assertEqual(policy['entries']['coordinator']['subagents']['delegationMode'], 'suggest')
        self.assertEqual(policy['entries']['researcher']['model'], 'openai/gpt-5.6-luna')
        self.assertEqual(policy['entries']['writer']['model'], 'openai/gpt-5.6-terra')
        self.assertEqual(policy['entries']['reviewer']['model'], 'openai/gpt-5.6-terra')
        self.assertIsNone(policy['defaults']['models']['openai/gpt-6-astra'])

    def test_token_lifecycle(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.tools') as d:
            p = Path(d) / 'gateway.env'
            with self.assertRaises(RuntimeError): c.ensure_token(p, '')
            self.assertTrue(c.ensure_token(p, 'a' * 64))
            self.assertFalse(c.ensure_token(p, ''))
            self.assertFalse(c.ensure_token(p, 'a' * 64))
            with self.assertRaises(RuntimeError): c.ensure_token(p, 'b' * 64)
            with self.assertRaises(RuntimeError): c.ensure_token(p, 'x' * 32 + '$bad', True)
            self.assertTrue(c.ensure_token(p, 'b' * 64, True))
            self.assertEqual(p.stat().st_mode & 0o777, 0o600)
            p.write_text('malformed')
            with self.assertRaises(RuntimeError): c.ensure_token(p, 'a' * 64)

    def test_listener_negative_cases(self):
        def row(addr): return f'LISTEN 0 511 {addr}:18789 0.0.0.0:*'
        self.assertTrue(c.listeners_ok(row('127.0.0.1'), 18789))
        self.assertTrue(c.listeners_ok(row('[::1]'), 18789))
        for addr in ['0.0.0.0', '[::]', '*', '10.0.0.2']:
            self.assertFalse(c.listeners_ok(row('127.0.0.1') + '\n' + row(addr), 18789))
        self.assertFalse(c.listeners_ok('', 18789))

    def test_service_mock_first_second_restart_drift(self):
        import subprocess
        with tempfile.TemporaryDirectory(dir=ROOT / '.tools') as d, patch.dict(os.environ, {'HOME': d, 'NCP_RESTART': '0'}):
            unit = Path(d) / '.config/systemd/user/openclaw-gateway.service'
            unit.parent.mkdir(parents=True)
            (Path(d) / '.config/openclaw').mkdir()
            calls = []
            def fake(args, **kw):
                calls.append(args)
                if args[:3] == ['openclaw', 'gateway', 'install']: unit.write_text('mock unit')
                return subprocess.CompletedProcess(args, 0, '', '')
            with patch.object(c, 'run', fake):
                self.assertTrue(c.service(18789, '/opt/node'))
                self.assertFalse(c.service(18789, '/opt/node'))
                self.assertEqual(sum(a[:3] == ['openclaw', 'gateway', 'install'] for a in calls), 1)
                with patch.dict(os.environ, {'NCP_RESTART': '1'}): self.assertTrue(c.service(18789, '/opt/node'))
                self.assertTrue(c.service(18790, '/opt/node'))

    @unittest.skipUnless(os.environ.get('NCP_REAL_CLI_TEST') == '1', 'explicit sandbox CLI test')
    def test_real_cli_config_first_second_merge(self):
        with tempfile.TemporaryDirectory(dir=ROOT / '.tools') as d:
            home = Path(d)
            state = home / '.openclaw'
            state.mkdir()
            config = state / 'openclaw.json'
            config.write_text(json.dumps({'messages': {'ackReactionScope': 'group-mentions'}}))
            env = {'PATH': str(Path.home() / '.npm-global/bin') + ':' + os.environ['PATH'], 'HOME': d, 'OPENCLAW_STATE_DIR': str(state), 'OPENCLAW_CONFIG_PATH': str(config),
                   'OPENCLAW_GATEWAY_TOKEN': 'sandbox-only-' + 'x' * 64}
            with patch.dict(os.environ, env):
                self.assertTrue(c.ensure_config(str(home / 'workspace'), 28789))
                before = config.read_bytes()
                self.assertFalse(c.ensure_config(str(home / 'workspace'), 28789))
                self.assertEqual(config.read_bytes(), before)
                self.assertEqual(json.loads(config.read_text())['messages']['ackReactionScope'], 'group-mentions')
                self.assertNotIn(env['OPENCLAW_GATEWAY_TOKEN'], config.read_text())
                config.unlink()
                self.assertTrue(c.ensure_config(str(home / 'workspace'), 28789))
                self.assertFalse(c.ensure_config(str(home / 'workspace'), 28789))

if __name__ == '__main__': unittest.main(verbosity=2)
