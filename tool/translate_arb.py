#!/usr/bin/env python3
"""Generate ARB files from app_en.arb using the public Bing Translator endpoint.

This is a bootstrap tool: the output is machine translation and MUST be
reviewed by native speakers before a store release. Placeholders, brand names
and newlines are protected with sentinels so they survive translation.

Usage:
    python3 tool/translate_arb.py                # generate missing locales
    python3 tool/translate_arb.py --force        # regenerate everything except zh
    python3 tool/translate_arb.py --only de,fr   # only selected locales

`zh` is intentionally skipped because it is the hand-written source language.
`kab` (Kabyle) is not supported by Bing; it is copied from English as a
placeholder until a native translation is contributed.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N = os.path.join(ROOT, "lib", "l10n")
EN_PATH = os.path.join(L10N, "app_en.arb")

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
)
SEPARATOR = "\n@@\n"
BATCH_SIZE = 20
RETRIES = 4

# locale -> Bing target language (None means unsupported / copy English)
LANGUAGES = {
    "ar": "ar",
    "ca": "ca",
    "cs": "cs",
    "de": "de",
    "el": "el",
    "es": "es",
    "et": "et",
    "fa": "fa",
    "fi": "fi",
    "fr": "fr",
    "he": "he",
    "hr": "hr",
    "id": "id",
    "it": "it",
    "ja": "ja",
    "kab": None,
    "ko": "ko",
    "lt": "lt",
    "lv": "lv",
    "nb": "nb",
    "nl": "nl",
    "pl": "pl",
    "pt": "pt-pt",
    "pt_BR": "pt",
    "ru": "ru",
    "sk": "sk",
    "sl": "sl",
    "sr": "sr-Cyrl",
    "th": "th",
    "tr": "tr",
    "uk": "uk",
    "vi": "vi",
    "zh_TW": "zh-Hant",
}

PROTECT = [
    (re.compile(r"\bTrackerOne\b"), "QZXBRANDXZQ"),
    (re.compile(r"\bTraccar\b"), "QZXTRACCARXZQ"),
    (re.compile(r"\bAMap\b"), "QZXAMAPXZQ"),
    (re.compile(r"\bJPush\b"), "QZXJPUSHXZQ"),
    (re.compile(r"\bFCM\b"), "QZXFCMXZQ"),
    (re.compile(r"\bWebSocket\b"), "QZXWEBSOCKETXZQ"),
    (re.compile(r"\bAndroid\b"), "QZXANDROIDXZQ"),
    (re.compile(r"\biOS\b"), "QZXIOSXZQ"),
    (re.compile(r"\bGPS\b"), "QZXGPSXZQ"),
    (re.compile(r"\bSDK\b"), "QZXSDKXZQ"),
]

RESTORE = {
    "QZXBRANDXZQ": "TrackerOne",
    "QZXTRACCARXZQ": "Traccar",
    "QZXAMAPXZQ": "AMap",
    "QZXJPUSHXZQ": "JPush",
    "QZXFCMXZQ": "FCM",
    "QZXWEBSOCKETXZQ": "WebSocket",
    "QZXANDROIDXZQ": "Android",
    "QZXIOSXZQ": "iOS",
    "QZXGPSXZQ": "GPS",
    "QZXSDKXZQ": "SDK",
}
PLACEHOLDER = re.compile(r"\{([a-zA-Z0-9_]+)\}")
PLACEHOLDER_TOKEN = "QZXPH{}XZQ"


def protect(text: str) -> tuple[str, list[str]]:
    names: list[str] = []

    def replace_placeholder(match: re.Match[str]) -> str:
        names.append(match.group(1))
        return PLACEHOLDER_TOKEN.format(len(names) - 1)

    protected = PLACEHOLDER.sub(replace_placeholder, text)
    for pattern, token in PROTECT:
        protected = pattern.sub(token, protected)
    return protected, names


def restore_text(text: str, names: list[str]) -> str:
    result = text
    for index, name in enumerate(names):
        result = result.replace(PLACEHOLDER_TOKEN.format(index), "{" + name + "}")
    for token, value in RESTORE.items():
        result = result.replace(token, value)
    return result


class BingTranslator:
    def __init__(self) -> None:
        self._key = ""
        self._token = ""
        self._ig = ""
        self._refresh_auth()

    def _fetch(self, url: str, data: bytes | None = None):
        request = urllib.request.Request(
            url,
            data=data,
            headers={
                "User-Agent": UA,
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": "https://www.bing.com/translator",
            },
        )
        return urllib.request.urlopen(request, timeout=45)

    def _refresh_auth(self) -> None:
        with self._fetch("https://www.bing.com/translator") as response:
            html = response.read().decode("utf-8", "replace")
        helper = re.search(
            r"params_AbusePreventionHelper\s*=\s*\[([^\]]+)\]", html
        )
        ig = re.search(r'IG:"([^"]+)"', html)
        if helper is None or ig is None:
            raise RuntimeError("Bing translator auth not found")
        parts = helper.group(1).split(",")
        self._key = parts[0].strip().strip('"')
        self._token = parts[1].strip().strip('"')
        self._ig = ig.group(1)

    def translate(self, target: str, texts: list[str]) -> list[str]:
        protected_texts: list[str] = []
        names: list[list[str]] = []
        for text in texts:
            protected, placeholders = protect(text)
            protected_texts.append(protected)
            names.append(placeholders)
        joined = SEPARATOR.join(protected_texts)
        last_error: Exception | None = None

        for attempt in range(RETRIES):
            try:
                data = urllib.parse.urlencode(
                    {
                        "fromLang": "en",
                        "to": target,
                        "text": joined,
                        "token": self._token,
                        "key": self._key,
                    }
                ).encode()
                url = (
                    "https://www.bing.com/ttranslatev3?isVertical=1"
                    f"&&IG={self._ig}&IID=translator.5028.1"
                )
                with self._fetch(url, data) as response:
                    payload = json.load(response)
                if not isinstance(payload, list) or not payload:
                    raise RuntimeError(f"unexpected response: {payload}")
                output = payload[0]["translations"][0]["text"]
                parts = output.split(SEPARATOR)
                if len(parts) == len(texts):
                    return [
                        restore_text(part, placeholders)
                        for part, placeholders in zip(parts, names)
                    ]
                raise ValueError(f"expected {len(texts)} parts, got {len(parts)}")
            except Exception as error:  # noqa: BLE001
                last_error = error
                time.sleep(2 * (attempt + 1))
                try:
                    self._refresh_auth()
                except Exception:  # noqa: BLE001
                    time.sleep(3)

        # Fallback: split large batches recursively. This keeps placeholders
        # and avoids hammering the endpoint with hundreds of single requests.
        if len(texts) > 1:
            print(
                f"    split batch of {len(texts)} ({last_error})",
                file=sys.stderr,
                flush=True,
            )
            middle = len(texts) // 2
            return self.translate(target, texts[:middle]) + self.translate(
                target, texts[middle:]
            )

        return texts

    def translate_single(self, target: str, text: str) -> list[str]:
        protected, names = protect(text)
        data = urllib.parse.urlencode(
            {
                "fromLang": "en",
                "to": target,
                "text": protected,
                "token": self._token,
                "key": self._key,
            }
        ).encode()
        url = (
            "https://www.bing.com/ttranslatev3?isVertical=1"
            f"&&IG={self._ig}&IID=translator.5028.1"
        )
        with self._fetch(url, data) as response:
            payload = json.load(response)
        output = payload[0]["translations"][0]["text"]
        return [restore_text(output, names)]


def generate(
    locale: str,
    target: str | None,
    source: OrderedDict[str, str],
    force: bool,
) -> None:
    output_path = os.path.join(L10N, f"app_{locale}.arb")
    if os.path.exists(output_path) and not force:
        print(f"skip {locale} (exists)", flush=True)
        return
    if target is None:
        print(f"copy {locale} (no endpoint support)", flush=True)
        translated = list(source.values())
    else:
        print(f"translate {locale} ({len(source)} keys)", flush=True)
        translator = BingTranslator()
        translated = []
        values = list(source.values())
        for start in range(0, len(values), BATCH_SIZE):
            batch = values[start : start + BATCH_SIZE]
            translated.extend(translator.translate(target, batch))
            print(
                f"  {locale} {min(start + BATCH_SIZE, len(values))}/{len(values)}",
                flush=True,
            )

    data = OrderedDict()
    data["@@locale"] = locale
    data.update(zip(source.keys(), translated))
    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"done {locale}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--only", default="")
    parser.add_argument("--workers", type=int, default=8)
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
        if not only or locale in only
    ]

    from concurrent.futures import ThreadPoolExecutor, as_completed

    failures = 0
    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        futures = {
            pool.submit(generate, locale, target, source, args.force): locale
            for locale, target in targets
        }
        for future in as_completed(futures):
            locale = futures[future]
            try:
                future.result()
            except Exception as error:  # noqa: BLE001
                failures += 1
                print(f"FAILED {locale}: {error}", file=sys.stderr, flush=True)

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
