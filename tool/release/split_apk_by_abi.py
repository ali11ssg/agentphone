#!/usr/bin/env python3
"""Derive a single-ABI APK from the universal Shorebird release APK.

Shorebird registers the universal APK's per-architecture libapp.so files, so
the universal APK stays the release of record. Removing the other ABIs'
native libraries leaves every kept file byte-identical (Dart code, assets,
dex, the matching libapp.so), so Shorebird patches still apply. The result is
re-aligned and re-signed with the same key.

Signing secrets come from the environment, never argv:
  OC_KS (keystore path), OC_KS_ALIAS, OC_KS_PASS, OC_KEY_PASS
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ABIS = ('arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86')


def entries_to_drop(names, keep_abi):
    """Names removed for a build that keeps only keep_abi."""
    if keep_abi not in ABIS:
        raise ValueError(f'Unknown ABI {keep_abi}')
    drop = []
    for name in names:
        parts = name.split('/')
        if len(parts) >= 2 and parts[0] == 'lib' and parts[1] in ABIS and parts[1] != keep_abi:
            drop.append(name)
        elif name == 'META-INF/MANIFEST.MF' or (
                len(parts) == 2 and parts[0] == 'META-INF' and parts[1].rsplit('.', 1)[-1] in ('SF', 'RSA', 'DSA', 'EC')):
            drop.append(name)
    return drop


def build_tools():
    root = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or Path.home() / 'Android/Sdk') / 'build-tools'
    versions = sorted((p for p in root.iterdir() if p.is_dir()), key=lambda p: [int(x) if x.isdigit() else 0 for x in p.name.replace('-', '.').split('.')])
    if not versions:
        raise SystemExit('No Android build-tools found')
    return versions[-1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--apk', required=True, type=Path)
    ap.add_argument('--abi', required=True, choices=ABIS)
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--min-sdk', default='26')
    a = ap.parse_args()
    with zipfile.ZipFile(a.apk) as z:
        names = z.namelist()
    if not any(n.startswith(f'lib/{a.abi}/libapp.so') for n in names):
        raise SystemExit(f'{a.apk} has no lib/{a.abi}/libapp.so')
    drop = entries_to_drop(names, a.abi)
    tools = build_tools()
    with tempfile.TemporaryDirectory() as tmp:
        stripped = Path(tmp) / 'stripped.apk'
        aligned = Path(tmp) / 'aligned.apk'
        shutil.copyfile(a.apk, stripped)
        # `zip -d` keeps every remaining entry's bytes and compression as is.
        # Patterns go on stdin so a long list never hits the argv limit.
        subprocess.run(['zip', '-q', '-d', str(stripped), '-@'], input='\n'.join(drop) + '\n', text=True, check=True)
        subprocess.run([str(tools / 'zipalign'), '-f', '-P', '16', '4', str(stripped), str(aligned)], check=True)
        env = dict(os.environ)
        for k in ('OC_KS', 'OC_KS_ALIAS', 'OC_KS_PASS', 'OC_KEY_PASS'):
            if not env.get(k):
                raise SystemExit(f'{k} must be set in the environment')
        a.out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(tools / 'apksigner'), 'sign', '--min-sdk-version', a.min_sdk,
                        '--v1-signing-enabled', 'false', '--ks', env['OC_KS'],
                        '--ks-key-alias', env['OC_KS_ALIAS'],
                        '--ks-pass', 'env:OC_KS_PASS', '--key-pass', 'env:OC_KEY_PASS',
                        '--out', str(a.out), str(aligned)], check=True, env=env)
        Path(str(a.out) + '.idsig').unlink(missing_ok=True)
    subprocess.run([str(tools / 'apksigner'), 'verify', '--min-sdk-version', a.min_sdk, str(a.out)], check=True)
    print(f'{a.out}: {a.out.stat().st_size} bytes, kept {a.abi}, dropped {len(drop)} entries')


if __name__ == '__main__':
    sys.exit(main())
