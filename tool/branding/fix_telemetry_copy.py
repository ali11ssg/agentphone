#!/usr/bin/env python3
"""Rewrites the telemetry copy in every locale.

AgentPhone has no analytics vendor, no crash-reporting vendor and no
performance tracing. The strings that used to describe those services are
replaced with the truth for this fork, in every language, and in the
generated localisation files (which are committed).

    python3 tool/branding/fix_telemetry_copy.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
L10N = ROOT / "lib" / "l10n"

KEYS = [
    "telemetryConsentTitle",
    "telemetryConsentBody",
    "telemetryConsentSends",
    "telemetryConsentNever",
    "telemetryUsageTitle",
    "telemetryUsageDetail",
    "telemetryCrashesTitle",
    "telemetryCrashesDetail",
]

COPY: dict[str, dict[str, str]] = {
    "en": {
        "telemetryConsentTitle": "AgentPhone sends nothing",
        "telemetryConsentBody": "AgentPhone never sends usage numbers or crash reports anywhere. Nothing leaves your phone unless you send a problem report yourself.",
        "telemetryConsentSends": "Sent: nothing. AgentPhone has no analytics and no crash-reporting service.",
        "telemetryConsentNever": "Never sent: your code, conversations, files, server addresses or keys.",
        "telemetryUsageTitle": "Usage and app health",
        "telemetryUsageDetail": "Nothing is collected and nothing is sent. AgentPhone has no analytics service.",
        "telemetryCrashesTitle": "Crash reports",
        "telemetryCrashesDetail": "Crash reports stay on this phone. They are never sent automatically; you can copy them into a problem report yourself.",
    },
    "ar": {
        "telemetryConsentTitle": "تطبيق AgentPhone لا يرسل أي بيانات",
        "telemetryConsentBody": "تطبيق AgentPhone لا يرسل أرقام الاستخدام ولا تقارير الأعطال. لا شيء يخرج من جوالك إلا إذا أرسلت تقرير مشكلة بنفسك.",
        "telemetryConsentSends": "ما يُرسل: لا شيء. لا يوجد في التطبيق خدمة تحليلات ولا تقارير أعطال.",
        "telemetryConsentNever": "لا يُرسل أبداً: كودك أو محادثاتك أو ملفاتك أو عناوين الخوادم أو مفاتيحك.",
        "telemetryUsageTitle": "الاستخدام وحالة التطبيق",
        "telemetryUsageDetail": "لا يُجمع شيء ولا يُرسل شيء. لا توجد في التطبيق خدمة تحليلات.",
        "telemetryCrashesTitle": "تقارير الأعطال",
        "telemetryCrashesDetail": "تقارير الأعطال تبقى على جوالك. لا تُرسل تلقائياً، ويمكنك نسخها داخل تقرير المشكلة.",
    },
    "es": {
        "telemetryConsentTitle": "AgentPhone no envía datos",
        "telemetryConsentBody": "AgentPhone nunca envía datos de uso ni informes de fallos. Nada sale de tu teléfono salvo que envíes tú un informe de problema.",
        "telemetryConsentSends": "Enviado: nada. AgentPhone no tiene analítica ni servicio de informes de fallos.",
        "telemetryConsentNever": "Nunca se envía: tu código, conversaciones, archivos, direcciones de servidor ni claves.",
        "telemetryUsageTitle": "Uso y estado de la aplicación",
        "telemetryUsageDetail": "No se recopila nada ni se envía nada. AgentPhone no tiene servicio de analítica.",
        "telemetryCrashesTitle": "Informes de fallos",
        "telemetryCrashesDetail": "Los informes de fallos se quedan en el teléfono. Nunca se envían solos; puedes copiarlos en un informe de problema.",
    },
    "ja": {
        "telemetryConsentTitle": "AgentPhone はデータを送信しません",
        "telemetryConsentBody": "AgentPhone は使用状況の数値やクラッシュレポートを一切送信しません。自分で問題レポートを送らない限り、端末から何も外へ出ません。",
        "telemetryConsentSends": "送信されるもの: なし。AgentPhone にはアナリティクスもクラッシュ報告サービスもありません。",
        "telemetryConsentNever": "送信されないもの: コード、会話、ファイル、サーバーアドレス、キー。",
        "telemetryUsageTitle": "利用状況とアプリの状態",
        "telemetryUsageDetail": "何も収集せず、何も送信しません。AgentPhone にはアナリティクスサービスがありません。",
        "telemetryCrashesTitle": "クラッシュレポート",
        "telemetryCrashesDetail": "クラッシュレポートはお端末内に保存されます。自動送信はせず、問題レポートに貼り付けられます。",
    },
    "pt": {
        "telemetryConsentTitle": "O AgentPhone não envia dados",
        "telemetryConsentBody": "O AgentPhone nunca envia dados de uso nem relatórios de falhas. Nada sai do telemóvel sem enviares tu um relatório de problema.",
        "telemetryConsentSends": "Enviado: nada. O AgentPhone não tem análise nem serviço de relatórios de falhas.",
        "telemetryConsentNever": "Nunca enviado: o teu código, conversas, ficheiros, endereços de servidores ou chaves.",
        "telemetryUsageTitle": "Utilização e estado da aplicação",
        "telemetryUsageDetail": "Nada é recolhido nem enviado. O AgentPhone não tem serviço de análise.",
        "telemetryCrashesTitle": "Relatórios de falhas",
        "telemetryCrashesDetail": "Os relatórios de falhas ficam no telemóvel. Nunca são enviados sozinhos; podes copiá-los para um relatório de problema.",
    },
    "ru": {
        "telemetryConsentTitle": "AgentPhone ничего не отправляет",
        "telemetryConsentBody": "AgentPhone не отправляет данные об использовании и отчёты о сбоях. С телефона ничего не уходит, пока вы сами не отправите отчёт о проблеме.",
        "telemetryConsentSends": "Отправляется: ничего. В AgentPhone нет аналитики и службы отчётов о сбоях.",
        "telemetryConsentNever": "Никогда не отправляется: ваш код, переписка, файлы, адреса серверов и ключи.",
        "telemetryUsageTitle": "Использование и состояние приложения",
        "telemetryUsageDetail": "Ничего не собирается и ничего не отправляется. В AgentPhone нет службы аналитики.",
        "telemetryCrashesTitle": "Отчёты о сбоях",
        "telemetryCrashesDetail": "Отчёты о сбоях остаются на телефоне. Они не отправляются автоматически; вы можете вставить их в отчёт о проблеме.",
    },
    "zh": {
        "telemetryConsentTitle": "AgentPhone 不发送任何数据",
        "telemetryConsentBody": "AgentPhone 不会发送使用数据或崩溃报告。除非你自己发送问题报告，否则不会有任何数据离开手机。",
        "telemetryConsentSends": "发送内容：无。AgentPhone 没有分析服务，也没有崩溃报告服务。",
        "telemetryConsentNever": "永不发送：你的代码、对话、文件、服务器地址或密钥。",
        "telemetryUsageTitle": "使用情况与应用状态",
        "telemetryUsageDetail": "不收集任何内容，也不发送任何内容。AgentPhone 没有分析服务。",
        "telemetryCrashesTitle": "崩溃报告",
        "telemetryCrashesDetail": "崩溃报告只保存在手机里，绝不会自动发送；你可以自己复制到问题报告中。",
    },
}

# Translator notes that named a vendor are neutralised in every language.
NOTE_REPLACEMENTS = [
    (
        "Privacy and data: switch for anonymous usage counts, performance and device ranges (Google Analytics for Firebase).",
        "Privacy and data: AgentPhone collects no usage counts, no performance data and no device ranges.",
    ),
    (
        "Privacy and data: switch for sending crash reports (Google Firebase Crashlytics).",
        "Privacy and data: AgentPhone sends no crash reports anywhere.",
    ),
    (
        "One-time question on the first start of a build that can send analytics: title.",
        "One-time question on the first start: title.",
    ),
    (
        "One-time analytics question: what agreeing does and where to turn it off. Must match PRIVACY.md.",
        "One-time question: what agreeing does. Must match PRIVACY.md.",
    ),
    (
        "One-time analytics question: what is sent.",
        "One-time question: what is sent.",
    ),
    (
        "One-time analytics question: what is never sent.",
        "One-time question: what is never sent.",
    ),
    (
        "One-time analytics question: the button that turns sharing on.",
        "One-time question: the button that turns sharing on.",
    ),
    (
        "One-time analytics question: the button that leaves sharing off and never asks again.",
        "One-time question: the button that leaves sharing off and never asks again.",
    ),
    (
        "One-time analytics question: the link that opens the two separate switches.",
        "One-time question: the link that opens the two separate switches.",
    ),
    (
        "One-time analytics question: the button that applies the two switches as set.",
        "One-time question: the button that applies the two switches as set.",
    ),
]


def escape_dart(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")


def rewrite_arb(path: Path, locale: str) -> dict[str, str]:
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
    old_values: dict[str, str] = {}
    for key in KEYS:
        if key in data and isinstance(data[key], str):
            old_values[key] = data[key]
    for old, new in NOTE_REPLACEMENTS:
        raw = raw.replace(old, new)
    for key, new in COPY[locale].items():
        if key not in data:
            continue
        old = old_values[key]
        raw = raw.replace(json.dumps(old, ensure_ascii=False), json.dumps(new, ensure_ascii=False))
    path.write_text(raw, encoding="utf-8")
    return old_values


def rewrite_generated(path: Path, old_values: dict[str, str], locale: str) -> None:
    raw = path.read_text(encoding="utf-8")
    for key in KEYS:
        old = old_values.get(key)
        if not old:
            continue
        new = COPY[locale][key]
        raw = raw.replace(escape_dart(old), escape_dart(new))
    for old, new in NOTE_REPLACEMENTS:
        raw = raw.replace(old, new)
    path.write_text(raw, encoding="utf-8")


def main() -> int:
    for locale, copy in COPY.items():
        arb = L10N / f"app_{locale}.arb"
        if not arb.is_file():
            print(f"missing {arb}")
            continue
        old_values = rewrite_arb(arb, locale)
        generated = L10N / f"app_localizations_{locale}.dart"
        if generated.is_file():
            rewrite_generated(generated, old_values, locale)
        print(f"{locale}: {len(old_values)} strings rewritten")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
