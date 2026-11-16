#!/usr/bin/env python3
"""Generate offline source-package notices from pinned SwiftPM revisions.

--check validates the committed lockfile/resource pair without network access.
Regeneration fetches source only; binary SDK notices require a separate review.
"""
import argparse
import concurrent.futures
import hashlib
import json
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
LOCK = ROOT / 'Chatforia/Chatforia.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
OUTPUT = ROOT / 'Chatforia/Chatforia/ThirdPartyNotices.txt'
MANIFEST = ROOT / 'docs/third-party-notices-manifest.json'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def run(args):
    return subprocess.check_output(args, stderr=subprocess.PIPE, timeout=120).decode('utf-8')


def collect(pin, cache):
    revision = pin['state']['revision']
    url = pin['location']
    identity = pin['identity']
    if not re.fullmatch(r'[0-9a-f]{40}', revision) or not re.fullmatch(r'[a-z0-9._-]+', identity):
        raise ValueError('Invalid pinned package identity/revision')
    if not re.fullmatch(r'https://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', url):
        raise ValueError('Review new package host before collecting notices')
    checkout = cache / identity
    checkout.mkdir(parents=True, exist_ok=True)
    if not (checkout / '.git').exists():
        run(['git', 'init', '-q', str(checkout)])
    try:
        run(['git', '-C', str(checkout), 'cat-file', '-e', revision + '^{commit}'])
    except subprocess.CalledProcessError:
        run(['git', '-C', str(checkout), 'fetch', '--depth', '1', url, revision])
    files = run(['git', '-C', str(checkout), 'ls-tree', '-r', '--name-only', revision]).splitlines()
    notices = []
    for file in sorted(files):
        if re.match(r'^(license|licence|notice|copying|copyright)([._-]|$)', pathlib.PurePosixPath(file).name, re.I):
            text = run(['git', '-C', str(checkout), 'show', revision + ':' + file])
            notices.append({'path': file, 'text': text, 'sha256': digest(text.encode())})
    package = run(['git', '-C', str(checkout), 'show', revision + ':Package.swift']) if 'Package.swift' in files else ''
    return {**pin, 'notices': notices, 'binaryTargets': '.binaryTarget(' in package}


def generate(cache):
    pins = json.loads(LOCK.read_text())['pins']
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        packages = list(pool.map(lambda pin: collect(pin, cache), pins))
    chunks = ['Chatforia — third-party source notices\n\n'
              'The following notices are preserved from the pinned Swift Package Manager repositories. '
              'Repository notices may include ancillary source files. They do not replace separate terms '
              'or notices for binary SDKs, downloaded assets, or services.\n']
    manifest_packages = []
    for package in sorted(packages, key=lambda p: p['identity']):
        state = package['state']
        chunks.append('\n' + '=' * 72 + '\n' + package['identity'] + '\n'
                      + 'Version: ' + state.get('version', 'pinned revision') + '\n'
                      + 'Revision: ' + state['revision'] + '\n' + package['location'] + '\n')
        if package['binaryTargets']:
            chunks.append('This package references binary SDKs. Source repository notices below do not establish the license of those binaries.\n')
        if not package['notices']:
            chunks.append('No license text was found in the pinned source repository. Separate SDK terms and notices require review.\n')
        for notice in package['notices']:
            chunks.append('\n--- ' + notice['path'] + ' ---\n' + notice['text'])
        manifest_packages.append({**package, 'notices': [{k: v for k, v in n.items() if k != 'text'} for n in package['notices']]})
    content = '\n'.join(chunks).encode('utf-8')
    manifest = {'lockSha256': digest(LOCK.read_bytes()), 'noticesSha256': digest(content), 'packages': manifest_packages}
    MANIFEST.parent.mkdir(exist_ok=True)
    OUTPUT.write_bytes(content)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Generated source notices for {len(packages)} pinned packages; binary SDK review remains separate.')


def check():
    manifest = json.loads(MANIFEST.read_text())
    if manifest['lockSha256'] != digest(LOCK.read_bytes()):
        raise SystemExit('Package.resolved changed: regenerate and review notices.')
    if manifest['noticesSha256'] != digest(OUTPUT.read_bytes()):
        raise SystemExit('Bundled notices differ from their reviewed manifest.')
    print('PASS: pinned dependencies and bundled source notices match the manifest.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--cache', type=pathlib.Path)
    args = parser.parse_args()
    if args.check:
        check()
    elif args.cache:
        generate(args.cache)
    else:
        with tempfile.TemporaryDirectory(prefix='chatforia-notices-') as directory:
            generate(pathlib.Path(directory))
