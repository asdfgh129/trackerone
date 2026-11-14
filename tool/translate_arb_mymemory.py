#!/usr/bin/env python3
"""Translate missing ARB keys with the public MyMemory API + round-trip check.

Why the round trip: MyMemory serves short strings from a translation memory,
which sometimes returns a wrong language (e.g. German requested, Turkish
returned). Every translation is therefore translated back to English and
compared with the source. Low similarity means the result is unusable and the
English source is kept instead, so the release check can flag it.

Usage:
    python3 tool/translate_arb_mymemory.py            # fill all missing keys
    python3 tool/translate_arb_mymemory.py --only de  # single locale
"""
from __future__ import annotations

import argparse
import difflib
import html
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = os.path.join(ROOT, "lib", "l10n")
EN_PATH = os.path.join(L10N, "app_en.arb")

LANGUAGES = {
    "ar": "ar", "ca": "ca", "cs": "cs", "de": "de", "el": "el", "es": "es",
    "et": "et", "fa": "fa", "fi": "fi", "fr": "fr", "he": "he", "hr": "hr",
    "id": "id", "it": "it", "ja": "ja", "kab": None, "ko": "ko", "lt": "lt",
    "lv": "lv", "nb": "nb", "nl": "nl", "pl": "pl", "pt": "pt", "pt_BR": "pt-BR",
    "ru": "ru", "sk": "sk", "sl": "sl", "sr": "sr", "th": "th", "tr": "tr",
    "uk": "uk", "vi": "vi", "zh_TW": "zh-TW",
}

PLACEHOLDER = re.compile(r"\{([a-zA-Z0-9_]+)\}")
SENTINEL = "ZZPH{}ZZ"
UA = "TrackerOneArbTranslator/1.0"
SIMILARITY_MIN = 0.45


def protect(text: str) -> tuple[str, list[str]]:
    names: list[str] = []

    def replace(match: re.Match[str]) -> str:
        names.append(match.group(1))
        return SENTINEL.format(len(names) - 1)

    return PLACEHOLDER.sub(replace, text), names


def restore(text: str, names: list[str]) -> str:
    for index, name in enumerate(names):
        # 机器翻译可能把哨兵拆开或加空格，用宽松正则还原。
        text = re.sub(r"ZZ\s*PH\s*%d\s*ZZ" % index, "{" + name + "}", text)
    return text


def translate(target: str, text: str) -> str | None:
    query = urllib.parse.urlencode({"q": text, "langpair": f"en|{target}"})
    request = urllib.request.Request(
        "https://api.mymemory.translated.net/get?" + query,
        headers={"User-Agent": UA},
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.load(response)
            if int(payload.get("responseStatus", 0)) != 200:
                time.sleep(1 + attempt)
                continue
            result = html.unescape(payload["responseData"]["translatedText"])
            result = re.sub(r"<[^>]+>", "", result).strip()
            result = result.replace("\xa0", " ")
            if not result:
                return None
            return result
        except Exception:  # noqa: BLE001
            time.sleep(1 + attempt)
    return None


def normalize(text: str) -> str:
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def similarity(left: str, right: str) -> float:
    return difflib.SequenceMatcher(None, normalize(left), normalize(right)).ratio()


def translate_key(target: str, key: str, source: str) -> tuple[str, bool]:
    """Return (text, verified). ``verified`` 为 False 表示回译校验未通过。"""
    protected, names = protect(source)
    translated = translate(target, protected)
    if translated is None:
        return source, False
    restored = restore(translated, names)
    if set(PLACEHOLDER.findall(source)) != set(PLACEHOLDER.findall(restored)):
        return source, False
    if normalize(restored) == normalize(source):
        # 服务端没有翻译（返回原文），视为不可用。
        return source, False
    back = translate("en", restored)
    if back is None:
        return restored, True
    if similarity(back, source) < SIMILARITY_MIN:
        return source, False
    return restored, True


def fill(locale: str, target: str | None, keys: list[str], source: dict[str, str]) -> None:
    path = os.path.join(L10N, f"app_{locale}.arb")
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle, object_pairs_hook=OrderedDict)

    missing = [key for key in keys if key not in data]
    if not missing:
        print(f"{locale}: up to date", flush=True)
        return

    unverified: list[str] = []
    if target is None:
        # kab 没有翻译接口，按项目约定复制英文占位。
        for key in missing:
            data[key] = source[key]
    else:
        with ThreadPoolExecutor(max_workers=4) as pool:
            futures = {
                pool.submit(translate_key, target, key, source[key]): key
                for key in missing
            }
            results: dict[str, tuple[str, bool]] = {}
            for future in as_completed(futures):
                key = futures[future]
                try:
                    results[key] = future.result()
                except Exception as error:  # noqa: BLE001
                    print(f"  {locale}.{key} failed: {error}", file=sys.stderr)
                    results[key] = (source[key], False)

        for key in missing:
            value, verified = results.get(key, (source[key], False))
            data[key] = value
            if not verified:
                unverified.append(key)

    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"{locale}: +{len(missing)}" + (f" (未通过校验: {len(unverified)})" if unverified else ""), flush=True)
    if unverified:
        print("  " + ", ".join(unverified), file=sys.stderr, flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--workers", type=int, default=6)
    args = parser.parse_args()
    only = {item.strip() for item in args.only.split(",") if item.strip()}

    with open(EN_PATH, encoding="utf-8") as handle:
        english = json.load(handle, object_pairs_hook=OrderedDict)
    source = OrderedDict(
        (key, value)
        for key, value in english.items()
        if not key.startswith("@") and isinstance(value, str)
    )

    targets = [
        (locale, target)
        for locale, target in LANGUAGES.items()
        if (not only or locale in only) and locale != "zh"
    ]

    failures = 0
    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        futures = {
            pool.submit(fill, locale, target, list(source.keys()), source): locale
            for locale, target in targets
        }
        for future in as_completed(futures):
            locale = futures[future]
            try:
                future.result()
            except Exception as error:  # noqa: BLE001
                failures += 1
                print(f"FAILED {locale}: {error}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
