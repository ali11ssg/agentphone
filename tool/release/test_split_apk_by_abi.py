import sys
import unittest
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from split_apk_by_abi import entries_to_drop

NAMES = ['classes.dex', 'resources.arsc', 'lib/arm64-v8a/libapp.so', 'lib/armeabi-v7a/libapp.so',
         'lib/x86_64/libapp.so', 'lib/x86_64/libproot.so', 'assets/flutter_assets/x', 'META-INF/CERT.RSA',
         'META-INF/MANIFEST.MF', 'META-INF/services/foo']


class SplitTest(unittest.TestCase):
    def test_keeps_only_requested_abi_and_non_native_entries(self):
        drop = entries_to_drop(NAMES, 'arm64-v8a')
        self.assertEqual(sorted(drop), sorted(['lib/armeabi-v7a/libapp.so', 'lib/x86_64/libapp.so',
                                               'lib/x86_64/libproot.so', 'META-INF/CERT.RSA', 'META-INF/MANIFEST.MF']))

    def test_other_abi(self):
        self.assertIn('lib/arm64-v8a/libapp.so', entries_to_drop(NAMES, 'x86_64'))
        self.assertNotIn('lib/x86_64/libproot.so', entries_to_drop(NAMES, 'x86_64'))

    def test_unknown_abi_refused(self):
        with self.assertRaises(ValueError):
            entries_to_drop(NAMES, 'mips')


if __name__ == '__main__':
    unittest.main()
