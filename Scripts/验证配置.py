#!/usr/bin/env python3
"""Surge 工程的轻量静态校验：规则、重复项、空文件、URL 与模块结构。"""
from __future__ import annotations

import argparse
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / "Rules"
MODULES = ROOT / "Modules"
SCRIPTS = ROOT / "Scripts"
MAIN = ROOT / "Config" / "Main.conf"
NODES = ROOT / "Nodes"
SUBSCRIPTION = ROOT / "Subscription"
SERVER = ROOT / "Server"
REQUIRED_SECTIONS = ("[General]", "[Proxy]", "[Proxy Group]", "[Rule]", "[Panel]", "[Script]", "[MITM]")
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
    panel_line = re.search(r"^网络诊断\s*=.*script-name=NetworkDiagnosticsPanel.*update-interval=600", text, re.M)
    if not panel_line:
        errors.append("网络诊断 Panel 定义缺失或刷新周期不是 600 秒")
    script_line = re.search(r"^NetworkDiagnosticsPanel\s*=.*Scripts/Panel\.js.*argument=proxy-group=Proxy", text, re.M)
    if not script_line:
        errors.append("网络诊断 Panel 脚本引用缺失或未显式使用 Proxy 策略组")
    forbidden_general = ("hijack-dns", "fake-ip", "ipv6 = false", "internet-test-url")
    for item in forbidden_general:
        if item.casefold() in text.casefold():
            errors.append(f"主配置包含不应由 Panel 引入的网络改动：{item}")
    if re.search(r"^\s*encrypted-dns-server\s*=", text, re.M | re.I):
        errors.append("主配置仍包含已禁用的 encrypted-dns-server")
    if not re.search(r"^Spotify\s*=\s*select,\s*Proxy,\s*DIRECT", text, re.M):
        errors.append("Spotify 独立策略组缺失或未同时提供 Proxy 与 DIRECT")
    if "Rules/Spotify.list,Spotify" not in text:
        errors.append("Spotify 规则集引用缺失")
    if not re.search(r"^外部节点\s*=\s*select,\s*DIRECT,\s*include-all-proxies=true,\s*policy-path=https://xxxxxxx\.invalid/surge-external-proxies\.list", text, re.M):
        errors.append("外部节点策略组缺失或 policy-path 占位入口错误")
    if not re.search(r"^Proxy\s*=\s*select,\s*Auto,\s*外部节点,\s*DIRECT", text, re.M):
        errors.append("总 Proxy 策略组未纳入外部节点")


def check_scripts(errors: list[str]) -> None:
    panel = SCRIPTS / "Panel.js"
    if not panel.is_file() or not panel.read_text(encoding="utf-8").strip():
        errors.append("网络诊断 Panel 脚本缺失或为空：Scripts/Panel.js")
        return
    text = panel.read_text(encoding="utf-8")
    required_tokens = (
        "policy: proxyGroup",
        "api.ip.sb/geoip",
        "cp.cloudflare.com/generate_204",
        "resolverState()",
        "$persistentStore",
        "$notification.post",
        "$done({",
    )
    for token in required_tokens:
        if token not in text:
            errors.append(f"Panel 脚本缺少关键能力：{token}")


def check_rule_coverage(errors: list[str]) -> None:
    expected = {
        "AI.list": ("openai.com", "anthropic.com", "cursor.com", "mistral.ai"),
        "Social.list": ("tiktokcdn.com", "byteoversea.com", "telegram-cdn.org", "discord.com"),
        "Streaming.list": ("youtube.com", "netflix.com", "disneyplus.com", "twitch.tv"),
        "Spotify.list": ("spotify.com", "scdn.co", "spoti.fi"),
    }
    for filename, domains in expected.items():
        path = RULES / filename
        if not path.is_file():
            errors.append(f"规则集缺失：Rules/{filename}")
            continue
        content = path.read_text(encoding="utf-8")
        for domain in domains:
            if domain not in content:
                errors.append(f"规则集覆盖不完整：{filename} 缺少 {domain}")


def check_node_layer(errors: list[str]) -> None:
    required = (
        NODES / "README.md",
        NODES / "本地节点模板.conf",
        SUBSCRIPTION / "generate-surge-subscription.sh",
        SUBSCRIPTION / "订阅安全说明.md",
        SERVER / "deploy-shadowtls.sh",
        SERVER / "deploy-anytls.sh",
        SERVER / "deploy-hysteria2.sh",
        SERVER / "deploy-snell.sh",
        SERVER / "lib" / "common.sh",
    )
    for path in required:
        if not path.is_file() or not path.read_text(encoding="utf-8").strip():
            errors.append(f"节点管理文件缺失或为空：{path.relative_to(ROOT)}")


def check_urls(errors: list[str]) -> None:
    sources = list(ROOT.rglob("*.conf")) + list(ROOT.rglob("*.sgmodule"))
    urls: set[str] = set()
    for path in sources:
        urls.update(re.findall(r"https://[^,\s]+", path.read_text(encoding="utf-8")))
    for url in sorted(urls):
        # 配置中的 RULE-SET 可以使用中文目录名；urllib 只接受 ASCII URL，
        # 因此请求前保留协议分隔符并对路径中的非 ASCII 字符做百分号编码。
        encoded_url = urllib.parse.quote(url, safe=":/?&=#%")
        parsed = urllib.parse.urlsplit(encoded_url)

        # 外部节点的 .invalid URL 是公开配置中的可搜索占位符，不是待访问的远程资源。
        if parsed.netloc == "xxxxxxx.invalid":
            continue

        # DoH 地址不是普通网页。没有携带 DNS 查询报文时，符合规范的服务会返回
        # HTTP 400；对它发送 HEAD/GET 反而会把有效的 Surge 配置误判为失效。
        if parsed.scheme == "https" and parsed.netloc and parsed.path.rstrip("/").endswith("/dns-query"):
            continue

        request = urllib.request.Request(encoded_url, method="HEAD", headers={"User-Agent": "surge-project-validator"})
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                if response.status >= 400:
                    errors.append(f"URL 无效：{url}（HTTP {response.status}）")
        except urllib.error.HTTPError as exc:
            # 少数静态托管站点禁用 HEAD；使用极小范围的 GET 再确认一次。
            if exc.code not in (405, 501):
                errors.append(f"URL 无法访问：{url}（HTTP {exc.code}）")
                continue
            fallback = urllib.request.Request(
                encoded_url,
                method="GET",
                headers={"User-Agent": "surge-project-validator", "Range": "bytes=0-0"},
            )
            try:
                with urllib.request.urlopen(fallback, timeout=15) as response:
                    if response.status >= 400:
                        errors.append(f"URL 无效：{url}（HTTP {response.status}）")
            except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError) as fallback_exc:
                errors.append(f"URL 无法访问：{url}（{fallback_exc}）")
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
    check_scripts(errors)
    check_rule_coverage(errors)
    check_node_layer(errors)
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
