"""Real VM regressions for exhaustive curriculum verification failure states."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LIBRARY = Path(os.environ.get('QFLI_PY_CONTENT_TEST_LIBRARY',
    str(ROOT / 'native/build/windows/qfli_py_ffi.dll'))).resolve()
SPEC = importlib.util.spec_from_file_location('content_verifier', ROOT / 'tool/verify_python_content.py')
import sys
sys.path.insert(0, str(ROOT / 'tool'))
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)


class ContentVerifierTest(unittest.TestCase):
    def test_real_vm_reports_failures_deadline_and_fixture_isolation(self):
        self.assertTrue(LIBRARY.is_file(),
            'Build the actual VM or set QFLI_PY_CONTENT_TEST_LIBRARY to its library')
        units = [
            {'id': 'fixture', 'topic': 1, 'kind': 'test', 'code':
                'from helper import value\nprint(value)\n',
             'inputFixtures': {'lib/helper.py': 'value = 42\n'}, 'expectedOutput': '42\n',
             'hasBehaviorCheck': True, 'runtime': 'embedded'},
            {'id': 'isolation', 'topic': 1, 'kind': 'test', 'code':
                'try:\n import helper\nexcept ImportError:\n print("isolated")\n',
             'expectedOutput': 'isolated\n', 'hasBehaviorCheck': True, 'runtime': 'embedded'},
            {'id': 'unchecked', 'topic': 1, 'kind': 'test', 'code': 'value = 1\n',
             'hasBehaviorCheck': False, 'runtime': 'embedded'},
            {'id': 'whitespace', 'topic': 1, 'kind': 'test', 'code': 'print("x ")\n',
             'expectedOutput': 'x\n', 'hasBehaviorCheck': True, 'runtime': 'embedded'},
            {'id': 'deadline', 'topic': 1, 'kind': 'test', 'code': 'while True: pass\n',
             'expectedOutput': '', 'hasBehaviorCheck': True, 'runtime': 'embedded'},
            {'id': 'after-deadline', 'topic': 1, 'kind': 'test', 'code': 'print(7)\n',
             'expectedOutput': '7\n', 'hasBehaviorCheck': True, 'runtime': 'embedded'},
        ]
        with tempfile.TemporaryDirectory(prefix='python_content_test_') as directory:
            inventory = Path(directory) / 'inventory.json'
            report_path = Path(directory) / 'report.json'
            inventory.write_text(json.dumps({'units': units}), encoding='utf-8')
            status = VERIFIER.verify(inventory, LIBRARY, report_path, 1.0, None)
            self.assertEqual(status, 1)
            report = json.loads(report_path.read_text(encoding='utf-8'))
            self.assertEqual(report['planned'], 6)
            self.assertEqual(report['completed'], 6)
            self.assertEqual(report['passed'], 3)
            self.assertEqual(report['failed'], 3)
            self.assertFalse(report['deviceGatePassed'])
            cases = {case['id']: case for case in report['cases']}
            self.assertEqual(cases['unchecked']['exitCode'], 0)
            self.assertIn('missing behavioral expectation', cases['unchecked']['problems'])
            self.assertIn('exact stdout mismatch', cases['whitespace']['problems'])
            self.assertEqual(cases['deadline']['status'], 'timeout')
            self.assertEqual(cases['after-deadline']['status'], 'passed')


if __name__ == '__main__':
    unittest.main()
