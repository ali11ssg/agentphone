"""Regression for the release-only WorkDatabase_Impl startup crash."""
from pathlib import Path
import re
import unittest

from tool.qa.verify_widget_release_rules import REQUIRED, verify_mapping


def retained_mapping():
    return '\n'.join(
        f'{name} -> {name}:\n    1:2:void <init>({parameters}):1:2 -> <init>'
        for name, parameters in REQUIRED.items()
    )


class WidgetReleaseRulesTest(unittest.TestCase):
    def test_retained_reflective_constructor_abi(self):
        verify_mapping(retained_mapping())

    def test_stripped_room_default_constructor_fails(self):
        mapping = retained_mapping().replace('    1:2:void <init>():1:2 -> <init>', '')
        with self.assertRaisesRegex(ValueError, 'constructor removed.*WorkDatabase_Impl'):
            verify_mapping(mapping)

    def test_worker_constructor_or_class_rename_fails(self):
        name = 'io.github.agentphone.app.WidgetStatusWorker'
        for mapping in (
            retained_mapping().replace('void <init>(android.content.Context,androidx.work.WorkerParameters)',
                                       'void <init>()'),
            retained_mapping().replace(f'{name} -> {name}:', f'{name} -> a.b:'),
        ):
            with self.assertRaises(ValueError):
                verify_mapping(mapping)

    def test_production_release_always_includes_keep_rules(self):
        root = Path(__file__).resolve().parents[2]
        gradle = (root / 'android/app/build.gradle.kts').read_text()
        self.assertRegex(gradle, r'release\s*\{\s*signingConfig\s*=\s*'
                         r'signingConfigs.getByName\("release"\)\s*'
                         r'proguardFiles\("widget-status-release.pro"\)')
        rules = (root / 'android/app/widget-status-release.pro').read_text()
        for name, parameters in REQUIRED.items():
            block = re.search(r'-keep class ' + re.escape(name) + r'\s*\{([^}]+)}', rules)
            self.assertIsNotNone(block)
            self.assertIn('public <init>(' + parameters + ');', block[1].replace(', ', ','))


if __name__ == '__main__':
    unittest.main()
