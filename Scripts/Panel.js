/*
 * Surge iOS dynamic Panel: network diagnostics.
 *
 * The panel runs one complete, low-frequency diagnostic pass. All external
 * probes explicitly use the configured root proxy group, so the exit IP and
 * service results represent the current Surge proxy path instead of DIRECT.
 *
 * This file intentionally has no dependency on an unsupported require/import
 * mechanism. The legacy one-shot scripts remain in this repository as focused
 * troubleshooting references; Main.conf no longer exposes them as daily
 * manual actions.
 */

const args = parseArguments(typeof $argument === "string" ? $argument : "");
const proxyGroup = args["proxy-group"] || "Proxy";
const timeout = 10000;
const storeKey = "lin0323.surge.network-diagnostics.v1";

function parseArguments(input) {
  return input.split("&").filter(Boolean).reduce((result, item) => {
    const index = item.indexOf("=");
    const key = decodeURIComponent(index < 0 ? item : item.slice(0, index));
    const value = decodeURIComponent(index < 0 ? "" : item.slice(index + 1));
    result[key] = value;
    return result;
  }, {});
}

function request(options) {
  return new Promise((resolve) => {
    $httpClient.get(options, (error, response, body) => {
      resolve({ error, response, body });
    });
  });
}

function surgeAPI(method, path, body) {
  return new Promise((resolve) => {
    if (typeof $httpAPI === "undefined") {
      resolve({});
      return;
    }
    $httpAPI(method, path, body, (result) => resolve(result || {}));
  });
}

function isReachable(result) {
  const status = result.response ? result.response.status : 0;
  return !result.error && status > 0 && status < 500;
}

function is204(result) {
  return !result.error && result.response && result.response.status === 204;
}

function elapsed(started) {
  return Date.now() - started;
}

function networkType() {
  const network = typeof $network === "undefined" ? {} : ($network || {});
  const types = [];
  if (network.wifi) types.push("Wi-Fi");
  if (network.cellular) types.push("Cellular");
  return types.length ? types.join(" + ") : "未知";
}

function resolverState() {
  const network = typeof $network === "undefined" ? {} : ($network || {});
  const dns = Array.isArray(network.dns) ? network.dns : [];
  return dns.length ? "已配置" : "未读取";
}

function loadState() {
  try {
    return JSON.parse($persistentStore.read(storeKey) || "{}");
  } catch (_) {
    return {};
  }
}

function saveState(state) {
  $persistentStore.write(JSON.stringify(state), storeKey);
}

function updateStatus(state, key, ok, detail, threshold) {
  const previous = state[key] || { failures: 0, bad: false, notified: false };
  const next = {
    failures: ok ? 0 : previous.failures + 1,
    bad: !ok,
    notified: previous.notified,
  };
  const notifications = [];

  if (!ok && next.failures >= threshold && !previous.notified) {
    next.notified = true;
    notifications.push({ title: "Surge 网络诊断异常", subtitle: key, message: detail });
  }
  if (ok && previous.bad && previous.notified) {
    next.notified = false;
    notifications.push({ title: "Surge 网络诊断已恢复", subtitle: key, message: detail });
  }
  state[key] = next;
  return notifications;
}

function findAutoCandidate(value, groupName) {
  if (!value || typeof value !== "object") return "";
  if (value[groupName] && typeof value[groupName] === "object") {
    return chooseLowestRTT(value[groupName].data || value[groupName]);
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const candidate = findAutoCandidate(item, groupName);
      if (candidate) return candidate;
    }
  }
  for (const key of Object.keys(value)) {
    if (key === "data" && value.group_name === groupName) {
      const candidate = chooseLowestRTT(value[key]);
      if (candidate) return candidate;
    }
    const candidate = findAutoCandidate(value[key], groupName);
    if (candidate) return candidate;
  }
  return "";
}

function chooseLowestRTT(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) return "";
  let bestName = "";
  let bestRTT = Number.POSITIVE_INFINITY;
  Object.keys(data).forEach((name) => {
    const item = data[name];
    if (!item || typeof item !== "object") return;
    const rtt = Number(item.rtt || item.available || item.receive || item.tcp);
    if (Number.isFinite(rtt) && rtt > 0 && rtt < bestRTT) {
      bestRTT = rtt;
      bestName = name;
    }
  });
  return bestName;
}

async function currentPolicy() {
  const groups = await surgeAPI("GET", "/v1/policy_groups");
  let current = proxyGroup;
  const visited = {};
  for (let level = 0; level < 6 && groups[current] && !visited[current]; level += 1) {
    visited[current] = true;
    const selected = await surgeAPI(
      "GET",
      "/v1/policy_groups/select?group_name=" + encodeURIComponent(current)
    );
    if (!selected || !selected.policy) break;
    current = selected.policy;
  }
  if (groups[current]) {
    const testResults = await surgeAPI("GET", "/v1/policy_groups/test_results");
    const candidate = findAutoCandidate(testResults, current);
    return candidate ? current + " → " + candidate : current + "（自动选路）";
  }
  return current;
}

async function getExitInfo() {
  const first = await request({ url: "https://api.ip.sb/geoip", policy: proxyGroup, timeout });
  if (isReachable(first)) {
    try {
      const data = JSON.parse(first.body || "{}");
      if (data.ip) {
        return { ok: true, ip: data.ip, country: data.country || data.country_code || "未知地区" };
      }
    } catch (_) {}
  }
  const fallback = await request({ url: "https://api64.ipify.org?format=json", policy: proxyGroup, timeout });
  if (isReachable(fallback)) {
    try {
      const data = JSON.parse(fallback.body || "{}");
      if (data.ip) return { ok: true, ip: data.ip, country: "地区未返回" };
    } catch (_) {}
  }
  return { ok: false, ip: "获取失败", country: "未知" };
}

async function run() {
  const started = Date.now();
  const probes = await Promise.all([
    getExitInfo(),
    request({ url: "https://cp.cloudflare.com/generate_204", policy: proxyGroup, timeout }),
    request({ url: "https://www.google.com/generate_204", policy: proxyGroup, timeout }),
    request({ url: "https://www.tiktok.com/", policy: proxyGroup, timeout }),
    request({ url: "https://chatgpt.com/", policy: proxyGroup, timeout }),
    currentPolicy(),
  ]);
  const [exit, nodeProbe, googleProbe, tiktokProbe, chatgptProbe, policyName] = probes;
  const nodeOK = is204(nodeProbe);
  // Keep DNS diagnostics read-only. Do not issue DoH/DoQ probes or alter the
  // resolver path: the current network DNS state is the only DNS signal here.
  const dnsOK = resolverState() !== "未读取";
  const googleOK = isReachable(googleProbe);
  const tiktokOK = isReachable(tiktokProbe);
  const chatgptOK = isReachable(chatgptProbe);
  const serviceFailures = [
    googleOK ? "" : "Google",
    tiktokOK ? "" : "TikTok",
    chatgptOK ? "" : "ChatGPT",
  ].filter(Boolean);
  const coreFailures = [
    exit.ok ? "" : "出口 IP",
    nodeOK ? "" : "节点连通",
    dnsOK ? "" : "DNS",
  ].filter(Boolean);

  const state = loadState();
  let notifications = [];
  notifications = notifications.concat(updateStatus(
    state,
    "核心网络",
    coreFailures.length === 0,
    coreFailures.length ? "检测异常：" + coreFailures.join("、") : "出口 IP、节点连通与 DNS 状态已恢复",
    1
  ));
  notifications = notifications.concat(updateStatus(
    state,
    "关键服务",
    serviceFailures.length === 0,
    serviceFailures.length ? "连续检测失败：" + serviceFailures.join("、") : "Google、TikTok、ChatGPT 已恢复",
    2
  ));
  saveState(state);
  notifications.forEach((item) => $notification.post(item.title, item.subtitle, item.message));

  const allOK = exit.ok && nodeOK && dnsOK && serviceFailures.length === 0;
  const content = [
    "出口 IP：" + exit.ip + "（" + exit.country + "）",
    "节点：" + policyName,
    "网络：" + networkType(),
    "DNS：" + (dnsOK ? "正常（" + resolverState() + "）" : "异常"),
    "节点连通：" + (nodeOK ? "正常" : "异常"),
    "Google：" + (googleOK ? "正常" : "异常"),
    "TikTok：" + (tiktokOK ? "正常" : "异常"),
    "ChatGPT：" + (chatgptOK ? "正常" : "异常"),
    "更新时间：" + new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) + "（" + elapsed(started) + "ms）",
  ].join("\n");

  $done({
    title: "网络诊断",
    content,
    style: allOK ? "good" : "alert",
    icon: allOK ? "stethoscope" : "exclamationmark.triangle.fill",
    "icon-color": allOK ? "#34C759" : "#FF9500",
  });
}

run().catch((error) => {
  $notification.post("Surge 网络诊断异常", "Panel 脚本错误", String(error));
  $done({ title: "网络诊断", content: "诊断脚本执行失败\n" + String(error), style: "error" });
});
