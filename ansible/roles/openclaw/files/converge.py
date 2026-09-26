#!/usr/bin/env python3
"""Pinned new-host convergence. Never print credentials or raw CLI output."""
import json
import hashlib
import urllib.request
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

TOKEN_RE = re.compile(r'[A-Za-z0-9_-]{32,256}')


def run(args, *, stdin=None, check=True, env=None):
    p = subprocess.run(args, input=stdin, text=True, capture_output=True, env=env)
    if check and p.returncode:
        raise RuntimeError('command failed: ' + ' '.join(args[:3]))
    return p


def atomic(path, text):
    path = Path(path)
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_token(path):
    text = Path(path).read_text()
    prefix = 'OPENCLAW_GATEWAY_TOKEN='
    if not text.startswith(prefix) or not TOKEN_RE.fullmatch(text[len(prefix):].rstrip('\n')):
        raise RuntimeError('invalid managed token file; recover manually')
    return text[len(prefix):].rstrip('\n')


def ensure_token(path, supplied, rotate=False):
    old = read_token(path) if Path(path).exists() else None
    if supplied and not TOKEN_RE.fullmatch(supplied):
        raise RuntimeError('token must be 32..256 URL-safe characters')
    if old and supplied and old != supplied and not rotate:
        raise RuntimeError('token differs; explicit rotation required')
    if rotate and not supplied:
        raise RuntimeError('rotation requires supplied token')
    token = supplied if (old is None or rotate) else old
    if not token:
        raise RuntimeError('first run requires externally supplied token')
    changed = token != old
    if changed:
        atomic(path, 'OPENCLAW_GATEWAY_TOKEN=' + token + '\n')
    if Path(path).stat().st_mode & 0o777 != 0o600:
        os.chmod(path, 0o600)
        changed = True
    return changed


def desired(workspace, port):
    return {'gateway': {'mode': 'local', 'bind': 'loopback', 'port': int(port),
                        'auth': {'mode': 'token', 'token': {'source': 'env', 'provider': 'ncp_env', 'id': 'OPENCLAW_GATEWAY_TOKEN'}}},
            'secrets': {'providers': {'ncp_env': {'source': 'env', 'allowlist': ['OPENCLAW_GATEWAY_TOKEN']}}},
            'agents': {
                'defaults': {
                    'workspace': workspace,
                    'model': {
                        'primary': 'openai/gpt-5.6-luna',
                        'fallbacks': ['nvidia/nemotron-3-ultra-550b-a55b'],
                    },
                    'utilityModel': 'openai/gpt-5.6-luna',
                    'contextPruning': {'mode': 'cache-ttl', 'ttl': '1h'},
                    'compaction': {'mode': 'safeguard'},
                    'subagents': {'maxConcurrent': 3, 'archiveAfterMinutes': 60},
                    'models': {
                        'openai/gpt-5.6-luna': {},
                        'openai/gpt-5.6-terra': {},
                        'nvidia/nemotron-3-ultra-550b-a55b': {},
                        # A null entry in the patch removes the retired legacy key.
                        'openai/gpt-6-astra': None,
                    },
                },
                'entries': {
                    'coordinator': {'subagents': {'delegationMode': 'suggest'}},
                    'researcher': {'model': 'openai/gpt-5.6-luna'},
                    'writer': {'model': 'openai/gpt-5.6-terra'},
                    'reviewer': {'model': 'openai/gpt-5.6-terra'},
                },
            }}


def contains(current, patch):
    if isinstance(patch, dict):
        return isinstance(current, dict) and all(k in current and contains(current[k], v) for k, v in patch.items())
    return current == patch


def config_matches(current, patch):
    """Match authored values while treating null patch values as deletions."""
    if not isinstance(current, dict) or not isinstance(patch, dict):
        return current == patch
    for key, value in patch.items():
        if value is None:
            if key in current:
                return False
        elif key not in current or not config_matches(current[key], value):
            return False
    return True


def config_read():
    path = Path(os.environ['OPENCLAW_CONFIG_PATH'])
    if not path.exists():
        return {}
    # config get intentionally redacts even provider source/allowlist in 2026.9.6.
    # Parse JSON5 privately using the pinned application's dependency, never print.
    script = "const fs=require('fs'),p=require('path');const root=p.dirname(fs.realpathSync(process.argv[1]));const j=require(require.resolve('json5',{paths:[root]}));process.stdout.write(JSON.stringify(j.parse(fs.readFileSync(process.env.OPENCLAW_CONFIG_PATH,'utf8'))));"
    import shutil
    return json.loads(run(['node', '-e', script, shutil.which('openclaw')]).stdout)


def ensure_config(workspace, port):
    current = config_read()
    patch = desired(workspace, port)
    provider = current.get('secrets', {}).get('providers', {}).get('ncp_env')
    if provider is not None and provider != patch['secrets']['providers']['ncp_env']:
        raise RuntimeError('reserved ncp_env provider conflict')
    # The model registry entry is intentionally deleted through a null patch;
    # it must therefore be checked separately from recursive value matching.
    legacy_models = current.get('agents', {}).get('defaults', {}).get('models', {})
    if config_matches(current, patch) and 'openai/gpt-6-astra' not in legacy_models:
        run(['openclaw', 'config', 'validate'])
        return False
    run(['openclaw', 'config', 'patch', '--stdin', '--dry-run'], stdin=json.dumps(patch))
    run(['openclaw', 'config', 'patch', '--stdin'], stdin=json.dumps(patch))
    return True


def versions(node_root):
    if run([node_root + '/bin/node', '--version']).stdout.strip() != 'v24.21.0':
        raise RuntimeError('Node runtime drift')
    changed = False
    for name, version in [('npm', '11.19.0'), ('openclaw', '2026.9.6')]:
        package = Path.home() / '.npm-global/lib/node_modules' / name / 'package.json'
        installed = json.loads(package.read_text()).get('version') if package.exists() else None
        if installed != version:
            manifest = json.loads(Path(__file__).with_name('npm-artifacts.json').read_text())
            artifact = next(a for a in manifest if a['name'] == name and a['version'] == version)
            archive = Path.home() / '.cache' / (name + '-' + version + '.tgz')
            archive.parent.mkdir(parents=True, exist_ok=True)
            data = urllib.request.urlopen(artifact['url'], timeout=120).read()
            if hashlib.sha256(data).hexdigest() != artifact['sha256']:
                raise RuntimeError('npm source artifact checksum mismatch')
            archive.write_bytes(data)
            install_env = {k: v for k, v in os.environ.items() if k not in ('OPENCLAW_GATEWAY_TOKEN', 'NCP_SUPPLIED_TOKEN')}
            run([node_root + '/bin/npm', 'install', '--global', '--prefix', str(Path.home() / '.npm-global'), str(archive)], env=install_env)
            changed = True
    verify_versions(node_root)
    return changed


def verify_versions(node_root):
    if run([node_root + '/bin/node', '--version']).stdout.strip() != 'v24.21.0':
        raise RuntimeError('Node version mismatch')
    if run(['npm', '--version']).stdout.strip() != '11.19.0':
        raise RuntimeError('npm version mismatch')
    if not re.search(r'\b2026\.9\.6\b', run(['openclaw', '--version']).stdout):
        raise RuntimeError('OpenClaw version mismatch')


def listeners_ok(text, port):
    addresses = [line.split()[3].rsplit(':', 1)[0] for line in text.splitlines()
                 if len(line.split()) >= 4 and line.split()[3].rsplit(':', 1)[-1] == str(port)]
    return bool(addresses) and all(a in ('127.0.0.1', '[::1]', '::1') for a in addresses)


def verify(workspace, port, node_root):
    verify_versions(node_root)
    if not config_matches(config_read(), desired(workspace, port)) or not Path(workspace).is_dir():
        raise RuntimeError('config/workspace mismatch')
    run(['openclaw', 'config', 'validate'])
    run(['systemctl', '--user', 'is-active', '--quiet', 'openclaw-gateway.service'])
    run(['systemctl', '--user', 'is-enabled', '--quiet', 'openclaw-gateway.service'])
    run(['openclaw', 'gateway', 'health', '--url', 'ws://127.0.0.1:' + str(port), '--json'])
    if not listeners_ok(run(['ss', '-H', '-ltn']).stdout, port):
        raise RuntimeError('missing loopback or external listener present')


def service(port, node_root):
    unit = Path.home() / '.config/systemd/user/openclaw-gateway.service'
    stamp = Path.home() / '.config/openclaw/service-spec.json'
    spec = json.dumps({'node': node_root, 'openclaw': '2026.9.6', 'port': int(port)}, sort_keys=True)
    changed = False
    run(['systemctl', '--user', 'daemon-reload'])
    expected = spec + ('\n' + hashlib.sha256(unit.read_bytes()).hexdigest() if unit.exists() else '')
    if not unit.exists() or not stamp.exists() or stamp.read_text() != expected:
        run(['openclaw', 'gateway', 'install', '--force', '--runtime', 'node', '--runtime-path', node_root + '/bin/node', '--port', str(port)])
        atomic(stamp, spec + '\n' + hashlib.sha256(unit.read_bytes()).hexdigest())
        changed = True
    elif os.environ.get('NCP_RESTART') == '1' or (Path.home() / '.config/openclaw/restart-pending').exists():
        run(['systemctl', '--user', 'restart', 'openclaw-gateway.service'])
        changed = True
    if run(['systemctl', '--user', 'is-enabled', '--quiet', 'openclaw-gateway.service'], check=False).returncode:
        run(['systemctl', '--user', 'enable', 'openclaw-gateway.service'])
        changed = True
    if run(['systemctl', '--user', 'is-active', '--quiet', 'openclaw-gateway.service'], check=False).returncode:
        run(['systemctl', '--user', 'start', 'openclaw-gateway.service'])
        changed = True
    return changed


def main():
    action, env_file, workspace, port, node_root = sys.argv[1:]
    changed = False
    if action == 'prepare':
        changed = ensure_token(env_file, os.environ.pop('NCP_SUPPLIED_TOKEN', ''), os.environ.pop('NCP_ROTATE_TOKEN', '0') == '1')
    os.environ['OPENCLAW_GATEWAY_TOKEN'] = read_token(env_file)
    if action == 'prepare':
        pending = Path.home() / '.config/openclaw/restart-pending'
        if changed:
            atomic(pending, 'pending')
        package_changed = versions(node_root)
        if package_changed:
            atomic(pending, 'pending')
        config_changed = ensure_config(workspace, port)
        if config_changed:
            atomic(pending, 'pending')
        changed = package_changed or config_changed or changed
    elif action in ('service', 'verify'):
        if action == 'service':
            changed = service(port, node_root)
        for attempt in range(12):
            try:
                verify(workspace, port, node_root)
                if action == 'service':
                    (Path.home() / '.config/openclaw/restart-pending').unlink(missing_ok=True)
                break
            except RuntimeError:
                if attempt == 11:
                    raise
                time.sleep(5)
    else:
        raise RuntimeError('unsupported action')
    print('CHANGED' if changed else 'OK')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('Convergence failed (' + type(exc).__name__ + '); inspect protected host logs.', file=sys.stderr)
        sys.exit(1)
