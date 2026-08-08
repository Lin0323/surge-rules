#!/usr/bin/env python3
"""Surge 工程的轻量静态校验：规则、重复项、空文件、URL 与模块结构。"""
from __future__ import annotations

import argparse
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / "Rules"
MODULES = ROOT / "Modules"
MAIN = ROOT / "Config" / "Main.conf"
REQUIRED_SECTIONS = ("[General]", "[Proxy]", "[Proxy Group]", "[Rule]", "[DNS]", "[Script]", "[MITM]")
RULE_PREFIXES = {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "IP-CIDR", "IP-CIDR6", "GEOIP", "USER-AGENT", "URL-REGEX"}


def meaningful_lines(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith(("#", ";", "//"))]


def check_rules(errors: list[str]) -> None:
    seen: dict[str, Path] = {}
    for path in sorted(RULES.glob("*.list")):
        lines = meaningful_lines(path)
        if not lines:
            errors.append(f"规则文件为空：{path.relative_to(ROOT)}")
            continue
        for line in lines:
            key = line.casefold()
            if key in seen:
                errors.append(f"重复规则：{line}（{seen[key].name} 与 {path.name}）")
            else:
                seen[key] = path
            parts = [item.strip() for item in line.split(",")]
            if len(parts) < 2 or parts[0] not in RULE_PREFIXES:
                errors.append(f"规则格式异常：{path.name} -> {line}")


def check_modules(errors: list[str]) -> None:
    for path in sorted(MODULES.glob("*.sgmodule")):
        text = path.read_text(encoding="utf-8")
        if "#!name=" not in text or "#!desc=" not in text:
            errors.append(f"模块缺少元数据：{path.relative_to(ROOT)}")
        if not re.search(r"^\[[A-Za-z ]+\]$", text, re.M):
            errors.append(f"模块缺少配置区段：{path.relative_to(ROOT)}")


def check_main(errors: list[str]) -> None:
    text = MAIN.read_text(encoding="utf-8")
    for section in REQUIRED_SECTIONS:
        if section not in text:
            errors.append(f"主配置缺少区段：{section}")
    forbidden = ("uuid=", "private-key", "reality-opts", "password=<真实", "VPS_PASSWORD")
    for item in forbidden:
        if item.casefold() in text.casefold():
            errors.append(f"主配置疑似包含敏感字段：{item}")


def check_urls(errors: list[str]) -> None:
    sources = list(ROOT.rglob("*.conf")) + list(ROOT.rglob("*.sgmodule"))
    urls: set[str] = set()
    for path in sources:
        urls.update(re.findall(r"https://[^,\s]+", path.read_text(encoding="utf-8")))
    for url in sorted(urls):
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "surge-project-validator"})
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                if response.status >= 400:
                    errors.append(f"URL 无效：{url}（HTTP {response.status}）")
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            errors.append(f"URL 无法访问：{url}（{exc}）")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-urls", action="store_true", help="仅用于推送前本地静态检查")
    args = parser.parse_args()
    errors: list[str] = []
    check_rules(errors)
    check_modules(errors)
    check_main(errors)
    if not args.skip_urls:
        check_urls(errors)
    if errors:
        print("校验失败：", file=sys.stderr)
        print("\n".join("- " + item for item in errors), file=sys.stderr)
        return 1
    print("校验通过：规则、模块、主配置" + ("（跳过 URL）" if args.skip_urls else "、URL"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
