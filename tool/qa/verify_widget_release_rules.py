#!/usr/bin/env python3
"""Verify release R8 output retains the widget's reflective constructor ABI."""
import argparse
from pathlib import Path
import re


REQUIRED = {
    'androidx.work.impl.WorkDatabase_Impl': '',
    'io.github.agentphone.app.WidgetStatusWorker':
        'android.content.Context,androidx.work.WorkerParameters',
}


def verify_mapping(mapping: str) -> None:
    classes = list(re.finditer(r'^([^ #\n]+) -> ([^\n:]+):$', mapping, re.MULTILINE))
    sections = {}
    for index, entry in enumerate(classes):
        end = classes[index + 1].start() if index + 1 < len(classes) else len(mapping)
        sections[entry[1]] = (entry[2], mapping[entry.end():end])
    for name, parameters in REQUIRED.items():
        section = sections.get(name)
        if section is None or section[0] != name:
            raise ValueError(f'Reflective class missing or renamed: {name}')
        signature = 'void <init>(' + parameters + ')'
        if signature not in section[1].replace(', ', ','):
            raise ValueError(f'Reflective constructor removed: {name}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mapping', type=Path)
    args = parser.parse_args()
    verify_mapping(args.mapping.read_text())
    print('Widget release reflective constructors retained.')


if __name__ == '__main__':
    main()
