"""Offline release-build contracts; transport and signing are fixture commands."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / 'tool/qa/vps_build_apk.sh'
EXPECTED_SIGNER = '1DE5BF08146F269BCD9EB5C2FFC94469CE4617D37806285955F978A62494D60C'


class VpsBuildApkTest(unittest.TestCase):
    def run_fixture(self, root, signer):
        binary = root / 'bin'
        binary.mkdir()
        calls = root / 'transport-calls'
        scripts = {
            'git': '#!/bin/sh\nprintf "%s\\n" "$FIXTURE_ROOT"\n',
            'rsync': '#!/bin/sh\nprintf "%s\\n" "$@" >> "$FIXTURE_CALLS"\n',
            'ssh': '#!/bin/sh\nprintf "%s\\n" "$@" >> "$FIXTURE_CALLS"\n',
            'scp': '#!/usr/bin/env python3\nimport pathlib,sys\npathlib.Path(sys.argv[-1]).write_bytes(b"fixture artifact")\n',
            'zipalign': '#!/bin/sh\nexit 0\n',
            'apksigner': '''#!/usr/bin/env python3
import os,pathlib,shutil,sys
if sys.argv[1] == 'sign':
    assert '--ks-pass' in sys.argv and 'env:OC_KS_PASS' in sys.argv
    assert '--key-pass' in sys.argv and 'env:OC_KEY_PASS' in sys.argv
    assert os.environ['OC_KS_PASS'] == 'fixture-store-password'
    assert os.environ['OC_KEY_PASS'] == 'fixture-key-password'
    shutil.copyfile(sys.argv[-1], sys.argv[sys.argv.index('--out') + 1])
else:
    print('Signer #1 certificate SHA-256 digest: ' + os.environ['FIXTURE_SIGNER'])
''',
        }
        for name, text in scripts.items():
            path = binary / name
            path.write_text(text)
            path.chmod(0o755)
        properties = root / 'fixture.properties'
        properties.write_text('storeFile=fixture.jks\nkeyAlias=fixture\n'
                              'storePassword=fixture-store-password\n'
                              'keyPassword=fixture-key-password\n')
        env = dict(os.environ, PATH=f'{binary}:{os.environ["PATH"]}',
                   FIXTURE_ROOT=str(root), FIXTURE_CALLS=str(calls),
                   FIXTURE_SIGNER=signer, OC_VPS_HOST='fixture-build-host',
                   XDG_CONFIG_HOME=str(root / 'config'),
                   OC_KEY_PROPERTIES=str(properties), ANDROID_BUILD_TOOLS=str(binary))
        result = subprocess.run(['bash', str(SCRIPT), '2420'],
                                env=env, text=True, capture_output=True)
        return result, calls.read_text()

    def test_remote_release_build_queues_and_local_signer_is_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'fixture-worktree'
            root.mkdir()
            result, calls = self.run_fixture(root, EXPECTED_SIGNER)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('flock $HOME/.oc-vps-apk-build.lock flutter build apk --release --build-number=2420', calls)
            self.assertNotIn('flock -n', calls)
            self.assertIn('--exclude\nandroid/key.properties', calls)
            self.assertIn('--exclude\n*.keystore', calls)
            self.assertIn('--exclude\n*.jks', calls)
            self.assertIn('signer:       ' + EXPECTED_SIGNER, result.stdout)
            self.assertTrue((root / 'build/vps-apk/app-release-2420.apk').is_file())
            self.assertFalse((root / 'build/vps-apk/app-release-server-2420.apk').exists())
            for private in ('fixture-build-host', 'fixture-store-password', 'fixture-key-password'):
                self.assertNotIn(private, result.stdout + result.stderr)
            for secret in ('fixture-store-password', 'fixture-key-password'):
                self.assertNotIn(secret, calls)

    def test_wrong_signer_removes_the_final_apk(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'fixture-worktree'
            root.mkdir()
            result, _ = self.run_fixture(root, '0' * 64)
            self.assertEqual(result.returncode, 1)
            self.assertIn('signer digest mismatch', result.stderr)
            self.assertFalse((root / 'build/vps-apk/app-release-2420.apk').exists())

    def test_missing_number_and_unsupported_modes_are_refused(self):
        for args in [[], ['x'], ['--unsigned', '2420'], ['--compile-only', '2420']]:
            with self.subTest(args=args):
                result = subprocess.run(['bash', str(SCRIPT), *args], text=True, capture_output=True)
                self.assertEqual(result.returncode, 64)
                self.assertIn('usage:', result.stderr)


if __name__ == '__main__':
    unittest.main()
