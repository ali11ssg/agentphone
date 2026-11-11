"""Parser regression controls for constructors lost or changed by R8."""
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

from verify_scheduled_prompt_apk import REQUIRED, verify_apk, verify_dex_files


def uleb(value):
    result = bytearray()
    while True:
        byte = value & 0x7f
        value >>= 7
        result.append(byte | (0x80 if value else 0))
        if not value:
            return result


def dex_fixture(rows, *, missing=(), private=(), changed=()):
    """Build just the DEX tables read by the verifier, not an executable file."""
    types = list(dict.fromkeys(['V', *rows, *(part for args in rows.values() for part in args)]))
    strings = [*types, '<init>']
    string_ids = 112
    type_ids = string_ids + len(strings) * 4
    proto_ids = type_ids + len(types) * 4
    method_ids = proto_ids + len(rows) * 12
    class_defs = method_ids + len(rows) * 8
    data = bytearray(class_defs + len(rows) * 32)
    data[:8] = b'dex\n035\0'
    for offset, count, start in ((56, len(strings), string_ids), (64, len(types), type_ids),
                                 (72, len(rows), proto_ids), (88, len(rows), method_ids),
                                 (96, len(rows), class_defs)):
        struct.pack_into('<II', data, offset, count, start)
    for index, text in enumerate(strings):
        struct.pack_into('<I', data, string_ids + index * 4, len(data))
        data += uleb(len(text)) + text.encode() + b'\0'
    for index, descriptor in enumerate(types):
        struct.pack_into('<I', data, type_ids + index * 4, strings.index(descriptor))
    for index, (descriptor, arguments) in enumerate(rows.items()):
        if descriptor in changed:
            arguments = ()
        while len(data) % 4:
            data.append(0)
        params = len(data) if arguments else 0
        if arguments:
            data += struct.pack('<I', len(arguments))
            for argument in arguments:
                data += struct.pack('<H', types.index(argument))
        struct.pack_into('<III', data, proto_ids + index * 12, strings.index('V'), types.index('V'), params)
        struct.pack_into('<HHI', data, method_ids + index * 8, types.index(descriptor), index, strings.index('<init>'))
        definition = len(data)
        present = descriptor not in missing
        data += b'\0\0' + uleb(int(present)) + b'\0'
        if present:
            data += uleb(index) + uleb(2 if descriptor in private else 1) + b'\0'
        struct.pack_into('<IIIIIIII', data, class_defs + index * 32,
                         types.index(descriptor), 1, 0xffffffff, 0, 0xffffffff, 0, definition, 0)
    struct.pack_into('<I', data, 32, len(data))
    return bytes(data)


class ScheduledPromptApkReflectionTest(unittest.TestCase):
    def test_valid_public_constructors_across_multiple_dex_files(self):
        verify_dex_files(dex_fixture({name: args}) for name, args in REQUIRED.items())

    def test_named_class_with_removed_default_constructor_is_rejected(self):
        database = 'Landroidx/work/impl/WorkDatabase_Impl;'
        with self.assertRaisesRegex(ValueError, 'WorkDatabase_Impl'):
            verify_dex_files([dex_fixture(REQUIRED, missing={database})])

    def test_worker_constructor_signature_must_match_reflection(self):
        worker = 'Lio.github.agentphone.app/ScheduledPromptWorker;'
        with self.assertRaisesRegex(ValueError, 'ScheduledPromptWorker'):
            verify_dex_files([dex_fixture(REQUIRED, changed={worker})])

    def test_non_public_constructor_is_rejected(self):
        merger = 'Landroidx/work/OverwritingInputMerger;'
        with self.assertRaisesRegex(ValueError, 'OverwritingInputMerger'):
            verify_dex_files([dex_fixture(REQUIRED, private={merger})])

    def test_missing_class_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'WorkDatabase_Impl'):
            verify_dex_files([])

    def test_apk_scans_double_digit_multidex_and_ignores_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'release.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('classes10.dex', dex_fixture(REQUIRED))
                archive.writestr('assets/irrelevant.dex', b'not a dex file')
            verify_apk(apk)

    def test_corrupt_dex_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'DEX header'):
            verify_dex_files([b'not dex'])


if __name__ == '__main__':
    unittest.main()
