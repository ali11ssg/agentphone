#!/usr/bin/env python3
"""Adds the Computer panel strings to every locale.

The generated localisation files are committed in this repository, and the
build phone cannot run `flutter gen-l10n`. This script keeps the `.arb`
sources and the generated Dart in step: it appends the same keys with the
same values to both, in every language.

    python3 tool/branding/add_computer_panel_strings.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
L10N = ROOT / "lib" / "l10n"

KEYS = [
    "usageTaskLimitTitle",
    "usageTaskLimitHelper",
    "usageTaskLimitInvalid",
    "computerPanelOpen",
    "computerPanelIdle",
    "computerPanelTakeOver",
    "computerPanelTabTerminal",
    "computerPanelTabFiles",
    "computerPanelTabPlan",
    "computerPanelTabBrowser",
    "computerPanelEmpty",
    "computerPanelRunning",
]

DESCRIPTIONS = {
    "usageTaskLimitTitle": "Usage screen: the cost limit for one task, the run the phone stops.",
    "usageTaskLimitHelper": "Usage screen: the helper line under the task limit.",
    "usageTaskLimitInvalid": "Usage screen: the task limit must be a number.",
    "computerPanelOpen": "Computer panel: the button that opens the panel over the conversation.",
    "computerPanelIdle": "Computer panel: the one-line status when the agent has not done anything yet.",
    "computerPanelTakeOver": "Computer panel: the button that stops the agent so the person can take over.",
    "computerPanelTabTerminal": "Computer panel: the tab with the commands the agent ran.",
    "computerPanelTabFiles": "Computer panel: the tab with the files the agent changed.",
    "computerPanelTabPlan": "Computer panel: the tab with the agent's task list.",
    "computerPanelTabBrowser": "Computer panel: the tab with the pages the agent opened.",
    "computerPanelEmpty": "Computer panel: the line shown in a tab with nothing in it.",
    "computerPanelRunning": "Computer panel: the word that says the call is still running.",
}

COPY = {
    "en": {
        "usageTaskLimitTitle": "Limit for one task",
        "usageTaskLimitHelper": "A run that passes this limit is stopped by the phone. Leave it empty for no limit.",
        "usageTaskLimitInvalid": "Write an amount in US dollars, for example 2.50.",
        "computerPanelOpen": "Computer",
        "computerPanelIdle": "Nothing yet",
        "computerPanelTakeOver": "Take over",
        "computerPanelTabTerminal": "Terminal",
        "computerPanelTabFiles": "Files",
        "computerPanelTabPlan": "Plan",
        "computerPanelTabBrowser": "Browser",
        "computerPanelEmpty": "Nothing here yet",
        "computerPanelRunning": "running",
    },
    "ar": {
        "usageTaskLimitTitle": "حدّ المهمة الواحدة",
        "usageTaskLimitHelper": "إذا تجاوزت المهمة هذا الحد يوقفها التطبيق. اتركه فارغاً بلا حد.",
        "usageTaskLimitInvalid": "اكتب المبلغ بالدولار، مثل 2.50.",
        "computerPanelOpen": "الكمبيوتر",
        "computerPanelIdle": "لا شيء بعد",
        "computerPanelTakeOver": "تولَّ الأمر",
        "computerPanelTabTerminal": "الطرفية",
        "computerPanelTabFiles": "الملفات",
        "computerPanelTabPlan": "الخطة",
        "computerPanelTabBrowser": "المتصفح",
        "computerPanelEmpty": "لا شيء هنا بعد",
        "computerPanelRunning": "قيد التنفيذ",
    },
}

# The other locales fall back to English in the generated files.
FALLBACK = "en"


def arb_path(locale: str) -> Path:
    return L10N / f"app_{locale}.arb"


def generated_path(locale: str) -> Path:
    return L10N / f"app_localizations_{locale}.dart"


def escape_dart(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")


def add_to_arb(path: Path, values: dict[str, str]) -> bool:
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
    if all(key in data for key in KEYS):
        return False
    lines = raw.rstrip().split("\n")
    if lines[-1] != "}":
        raise SystemExit(f"{path} does not end with a closing brace")
    lines = lines[:-1]
    # The last entry needs a comma before the new ones start.
    if lines and lines[-1].strip() and not lines[-1].rstrip().endswith(","):
        lines[-1] = lines[-1] + ","
    for key in KEYS:
        if key in data:
            continue
        lines.append(f'  "{key}": {json.dumps(values[key], ensure_ascii=False)},')
        lines.append(f'  "@{key}": {{')
        lines.append(f'    "description": {json.dumps(DESCRIPTIONS[key], ensure_ascii=False)}')
        lines.append("  },")
    # JSON has no trailing comma: the last entry closes the object.
    if lines and lines[-1].rstrip().endswith(","):
        lines[-1] = lines[-1].rstrip()[:-1]
    lines.append("}")
    path.write_text("\n".join(lines), encoding="utf-8")
    return True


def add_to_generated(path: Path, values: dict[str, str]) -> bool:
    raw = path.read_text(encoding="utf-8")
    missing = [key for key in KEYS if f"String get {key}" not in raw]
    if not missing:
        return False
    block: list[str] = []
    for key in missing:
        block.append("")
        block.append("  /// ${DESCRIPTIONS[key]}")
        block.append("  ///")
        block.append("  /// In en, this message translates to:")
        block.append(f"  /// **'{escape_dart(values[key])}'**")
        block.append(f"  String get {key};")
    # The base class declares the getters; the per-locale ones implement them.
    abstract_anchor = "  String get telemetryConsentTitle;"
    if abstract_anchor in raw:
        index = raw.find(abstract_anchor)
        end = raw.index("\n", index) + 1
        raw = raw[:end] + "\n".join(block) + "\n" + raw[end:]
    else:
        implementation: list[str] = []
        for key in missing:
            implementation.append("")
            implementation.append("  @override")
            implementation.append(
                f"  String get {key} => '{escape_dart(values[key])}';"
            )
        anchor = "  @override\n  String get telemetryConsentTitle =>"
        index = raw.find(anchor)
        if index < 0:
            raise SystemExit(f"{path}: no anchor for the implementation")
        # Insert before the anchor's "@override" line, so the annotation
        # stays with the getter it belongs to.
        raw = raw[:index] + "\n".join(implementation) + "\n\n" + raw[index:]
    path.write_text(raw, encoding="utf-8")
    return True


def main() -> int:
    locales = sorted(
        path.stem.removeprefix("app_")
        for path in L10N.glob("app_*.arb")
    )
    # The base class declares every getter.
    base = L10N / "app_localizations.dart"
    if base.is_file():
        changed_base = add_to_generated(base, COPY[FALLBACK])
        print(f"base: dart={'updated' if changed_base else 'unchanged'}")

    for locale in locales:
        values = COPY.get(locale, COPY[FALLBACK])
        arb = arb_path(locale)
        changed_arb = add_to_arb(arb, values)
        generated = generated_path(locale)
        changed_generated = add_to_generated(generated, values) if generated.is_file() else False
        print(
            f"{locale}: arb={'updated' if changed_arb else 'unchanged'}, "
            f"dart={'updated' if changed_generated else 'unchanged'}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
