#!/usr/bin/env python3
"""Execute every exported curriculum unit on the real shipped embedded VM.

Each unit has a fresh process/project and finite deadline. CPython only hosts
ctypes; it never executes a curriculum program. An unchecked answer fails even
when its compilation or execution happens to succeed.
"""
import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
import time

from verify_python_modules import Result, Vm, verify_manifest

ROOT = Path(__file__).resolve().parents[1]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n',
                    encoding='utf-8', newline='\n')


def materialize(project, fixtures):
    for name, content in fixtures.items():
        if name == 'stdin':
            continue
        relative = PurePosixPath(name)
        if (not name or relative.is_absolute() or '..' in relative.parts
                or '\\' in name or ':' in name or name == 'main.py'
                or relative.parts[0] == '.qfli' or not isinstance(content, str)):
            raise ValueError('Invalid curriculum fixture: ' + name)
        target = project.joinpath(*relative.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8', newline='\n')


def child(request_path, result_path):
    request = json.loads(request_path.read_text(encoding='utf-8'))
    unit = request['unit']
    with tempfile.TemporaryDirectory(prefix='qfli_content_unit_', dir=request_path.parent) as temporary:
        project = Path(temporary)
        assets = ROOT / 'assets/python_stdlib'
        manifest = verify_manifest(assets)
        bundled = project / '.qfli/python/bundled/v1'
        for entry in manifest['files']:
            target = bundled / entry['path']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(assets / entry['path'], target)
        fixtures = unit.get('inputFixtures', {})
        materialize(project, fixtures)
        source = unit['code']
        entry = project / 'main.py'
        entry.write_text(source, encoding='utf-8', newline='\n')
        vm = Vm(Path(request['library']))
        result = Result()
        vm.library.qfli_py_run_into(ctypes.byref(result), source.encode('utf-8'),
            fixtures.get('stdin', '').encode('utf-8'), 8192,
            str(project).encode('utf-8'), str(entry).encode('utf-8'), 0)
        try:
            observed = {
                'runtimeVersion': vm.version,
                'exitCode': result.exit_code,
                'output': ctypes.string_at(result.output).decode('utf-8') if result.output else '',
                'error': ctypes.string_at(result.error).decode('utf-8') if result.error else '',
                'truncated': bool(result.truncated),
            }
        finally:
            vm.library.qfli_py_result_free(ctypes.byref(result))
        write_json(result_path, observed)


def verify(inventory_path, library, report_path, timeout, topics):
    started = datetime.now(timezone.utc).isoformat()
    inventory_bytes = inventory_path.read_bytes()
    inventory = json.loads(inventory_bytes)
    units = inventory['units']
    if topics:
        units = [unit for unit in units if unit['topic'] in topics]
    if not units or len({unit['id'] for unit in units}) != len(units):
        raise ValueError('Inventory is empty or has duplicate unit IDs')
    verify_manifest(ROOT / 'assets/python_stdlib')
    records = []
    report = {
        'schemaVersion': 1,
        'kind': 'python-content-host-embedded-execution',
        'startedAtUtc': started,
        'inventoryPath': str(inventory_path),
        'inventorySha256': digest(inventory_bytes),
        'inventoryOrigin': inventory.get('origin'),
        'assetMismatches': inventory.get('assetMismatches', []),
        'shippedAssetDigests': inventory.get('assetDigests', {}),
        'libraryPath': str(library),
        'librarySha256': digest(library.read_bytes()),
        'assetDigests': {str(path.relative_to(ROOT)).replace('\\', '/'): digest(path.read_bytes())
                        for path in sorted((ROOT / 'assets/python_stdlib').rglob('*')) if path.is_file()},
        'planned': len(units),
        'selection': sorted(topics) if topics else 'all',
        'deviceGatePassed': False,
        'cases': records,
    }
    with tempfile.TemporaryDirectory(prefix='qfli_content_verify_') as temporary:
        request_path = Path(temporary) / 'request.json'
        result_path = Path(temporary) / 'result.json'
        for unit in units:
            if result_path.exists():
                result_path.unlink()
            write_json(request_path, {'unit': unit, 'library': str(library)})
            begin = time.monotonic()
            row = {key: unit[key] for key in ('id', 'topic', 'kind')}
            row.update({
                'codeSha256': digest(unit['code'].encode('utf-8')),
                'fixtureSha256': digest(json.dumps(unit.get('inputFixtures', {}),
                    ensure_ascii=False, sort_keys=True).encode('utf-8')),
                'expectedOutput': unit.get('expectedOutput'),
                'hasBehaviorCheck': unit.get('hasBehaviorCheck', False),
                'status': 'failed',
            })
            try:
                process = subprocess.run([sys.executable, str(Path(__file__).resolve()),
                    '--child', str(request_path), str(result_path)],
                    capture_output=True, timeout=timeout)
                if process.returncode != 0 or not result_path.is_file():
                    row['harnessError'] = process.stderr.decode('utf-8', 'replace')
                    row['processExitCode'] = process.returncode
                else:
                    row.update(json.loads(result_path.read_text(encoding='utf-8')))
                    expected = unit.get('expectedOutput')
                    problems = []
                    if unit.get('runtime') != 'embedded':
                        problems.append('requires external runtime')
                    if not row['hasBehaviorCheck']:
                        problems.append('missing behavioral expectation')
                    if row['exitCode'] != 0 or row['error'] or row['truncated']:
                        problems.append('runtime failure or truncated output')
                    if expected is not None and row['output'].replace('\r\n', '\n') != expected.replace('\r\n', '\n'):
                        problems.append('exact stdout mismatch')
                    if not problems:
                        row['status'] = 'passed'
                    row['problems'] = problems
            except subprocess.TimeoutExpired:
                row['status'] = 'timeout'
                row['harnessError'] = 'Child VM exceeded finite deadline; subprocess killed and waited.'
            row['durationSeconds'] = round(time.monotonic() - begin, 4)
            records.append(row)
            report['completed'] = len(records)
            write_json(report_path, report)
    report['passed'] = sum(row['status'] == 'passed' for row in records)
    report['failed'] = len(records) - report['passed']
    report['ok'] = report['passed'] == len(units) and not report['assetMismatches']
    report['finishedAtUtc'] = datetime.now(timezone.utc).isoformat()
    write_json(report_path, report)
    print(json.dumps({key: report[key] for key in ('planned', 'passed', 'failed', 'ok')}))
    return 0 if report['ok'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--child', nargs=2, metavar=('REQUEST', 'RESULT'))
    parser.add_argument('--inventory', type=Path, default=ROOT / 'build/python-content-authored.json')
    parser.add_argument('--library', type=Path, default=ROOT / 'native/build/windows/qfli_py_ffi.dll')
    parser.add_argument('--report', type=Path, default=ROOT / 'build/reports/python-content-host.json')
    parser.add_argument('--timeout', type=float, default=8)
    parser.add_argument('--topics', help='Optional comma-separated topic IDs; report is explicitly partial')
    args = parser.parse_args()
    if args.child:
        child(*(Path(value) for value in args.child))
        return 0
    topics = set(map(int, args.topics.split(','))) if args.topics else None
    return verify(args.inventory.resolve(), args.library.resolve(), args.report.resolve(), args.timeout, topics)


if __name__ == '__main__':
    raise SystemExit(main())
