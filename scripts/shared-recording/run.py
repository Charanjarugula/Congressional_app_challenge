#!/usr/bin/env python3
"""Build the shared demo and open two simulators. No Docker or backend credentials needed."""
import argparse
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUNDLE = 'com.charanjarugula.courtly.sharedrecording'
BUILD = ROOT / '.recording/shared-build'
parser = argparse.ArgumentParser()
parser.add_argument('--skip-build', action='store_true')
args = parser.parse_args()
def run(*args, **kwargs):
    return subprocess.run(list(args), check=True, cwd=ROOT, **kwargs)
def simlist(kind):
    return json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', kind, '-j']))[kind]
if not args.skip_build:
    BUILD.mkdir(parents=True, exist_ok=True)
    with (BUILD / 'build.log').open('w') as log:
        run('xcodebuild', 'build', '-project', 'ios/Courtly.xcodeproj', '-scheme', 'Courtly',
            '-configuration', 'Debug', '-sdk', 'iphonesimulator',
            '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(BUILD),
            f'PRODUCT_BUNDLE_IDENTIFIER={BUNDLE}', 'CODE_SIGNING_ALLOWED=NO',
            stdout=log, stderr=subprocess.STDOUT)
runtimes = [r for r in simlist('runtimes') if r.get('isAvailable') and 'iOS' in r['name']]
if not runtimes:
    raise SystemExit('Install an iOS simulator runtime in Xcode Settings → Components first.')
runtime = sorted(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))[-1]['identifier']
types = [t for t in simlist('devicetypes') if t['name'].startswith('iPhone')]
device_type = next((t['identifier'] for t in types if t['name']=='iPhone 17 Pro'), types[-1]['identifier'])
devices = simlist('devices').get(runtime, [])
for person in ('Ana', 'Luis'):
    name = f'Courtly Shared Demo — {person}'
    existing = next((d for d in devices if d['name']==name and d.get('isAvailable')), None)
    udid = existing['udid'] if existing else subprocess.check_output(
        ['xcrun', 'simctl', 'create', name, device_type, runtime], text=True).strip()
    if not existing or existing['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', udid)
    run('xcrun', 'simctl', 'bootstatus', udid, '-b')
    run('xcrun', 'simctl', 'install', udid, str(BUILD/'Build/Products/Debug-iphonesimulator/Courtly.app'))
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, BUNDLE], capture_output=True)
    run('xcrun', 'simctl', 'launch', udid, BUNDLE)
    print(f'{person}: recording.{person.lower()}@courtly.app — enter the private 8-digit code at sign-in.')
run('open', '-a', 'Simulator')
