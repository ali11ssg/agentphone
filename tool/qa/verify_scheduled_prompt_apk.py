#!/usr/bin/env python3
"""Check reflection entry points in the actual shrunk APK, without Android/ADB.

A mapping file or an unshrunk Kotlin compile cannot prove a reflective
constructor survived. Inspect defined DEX direct methods and public access.
"""
from pathlib import Path
import re
import struct
import sys
import zipfile

REQUIRED = {
    'Landroidx/work/impl/WorkDatabase_Impl;': (),
    'Landroidx/work/OverwritingInputMerger;': (),
    'Lio.github.agentphone.app/ScheduledPromptWorker;': (
        'Landroid/content/Context;', 'Landroidx/work/WorkerParameters;',
    ),
}


class Dex:
    def __init__(self, data):
        self.data = data
        if len(data) < 112 or not data.startswith(b'dex\n'):
            raise ValueError('Invalid DEX header')
        self.strings = self.table(56, 4)
        self.types = self.table(64, 4)
        self.protos = self.table(72, 12)
        self.methods = self.table(88, 8)
        self.classes = self.table(96, 32)

    def uint(self, offset):
        return struct.unpack_from('<I', self.data, offset)[0]

    def table(self, offset, width):
        count, start = struct.unpack_from('<II', self.data, offset)
        if start + count * width > len(self.data):
            raise ValueError('DEX table is out of bounds')
        return [start + i * width for i in range(count)]

    def uleb(self, offset):
        value = 0
        for shift in range(0, 35, 7):
            byte = self.data[offset]
            offset += 1
            value |= (byte & 0x7f) << shift
            if not byte & 0x80:
                return value, offset
        raise ValueError('Invalid DEX integer')

    def string(self, index):
        _, start = self.uleb(self.uint(self.strings[index]))
        end = self.data.index(0, start)
        # Required descriptors and method names contain ASCII only.
        return self.data[start:end].decode('utf-8', errors='replace')

    def type(self, index):
        return self.string(self.uint(self.types[index]))

    def parameters(self, proto_index):
        offset = self.uint(self.protos[proto_index] + 8)
        if not offset:
            return ()
        count = self.uint(offset)
        if offset + 4 + count * 2 > len(self.data):
            raise ValueError('DEX parameters are out of bounds')
        return tuple(self.type(struct.unpack_from('<H', self.data, offset + 4 + i * 2)[0])
                     for i in range(count))

    def constructors(self):
        found = {}
        for definition in self.classes:
            descriptor = self.type(self.uint(definition))
            if descriptor not in REQUIRED:
                continue
            constructors = set()
            offset = self.uint(definition + 24)
            if offset:
                counts = []
                for _ in range(4):
                    count, offset = self.uleb(offset)
                    counts.append(count)
                for _ in range(counts[0] + counts[1]):
                    _, offset = self.uleb(offset)
                    _, offset = self.uleb(offset)
                method_index = 0
                for _ in range(counts[2]):
                    delta, offset = self.uleb(offset)
                    access, offset = self.uleb(offset)
                    _, offset = self.uleb(offset)
                    method_index += delta
                    owner, proto, name = struct.unpack_from('<HHI', self.data, self.methods[method_index])
                    if (self.string(name) == '<init>' and access & 1 and
                            self.type(owner) == descriptor and self.uint(definition + 4) & 1):
                        constructors.add(self.parameters(proto))
            found[descriptor] = constructors
        return found


def verify_dex_files(files):
    found = {}
    for data in files:
        for descriptor, constructors in Dex(data).constructors().items():
            if descriptor in found:
                raise ValueError('Duplicate reflection class in APK')
            found[descriptor] = constructors
    missing = [descriptor for descriptor, signature in REQUIRED.items()
               if signature not in found.get(descriptor, set())]
    if missing:
        raise ValueError('Missing public reflective constructor: ' + ', '.join(missing))


def verify_apk(path):
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist() if re.fullmatch(r'classes(?:[2-9]|[1-9][0-9]+)?\.dex', name)]
        if not names:
            raise ValueError('APK contains no DEX files')
        verify_dex_files(archive.read(name) for name in names)


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: verify_scheduled_prompt_apk.py <release.apk>')
    try:
        verify_apk(Path(sys.argv[1]))
    except (ValueError, IndexError, struct.error, zipfile.BadZipFile) as error:
        raise SystemExit(str(error)) from error
    print('Scheduled prompt APK reflection constructors: OK')


if __name__ == '__main__':
    main()
