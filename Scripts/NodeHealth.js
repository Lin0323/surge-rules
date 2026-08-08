/*
 * Surge generic script: 测试 Auto、Proxy 与 Backup 策略组的延迟和可达性。
 * Surge 脚本无法安全地从通用配置枚举每一个私有节点，因此按策略组测试。
 */
const testURL = "https://cp.cloudflare.com/generate_204";
const policies = ["Auto", "Proxy", "Backup"];
const results = [];
let pending = policies.length;

policies.forEach((policy) => {
  const startedAt = Date.now();
  $httpClient.get({ url: testURL, policy, timeout: 8000 }, (error, response) => {
    const elapsed = Date.now() - startedAt;
    const ok = !error && response && response.status === 204;
    results.push(policy + ": " + (ok ? "正常 " + elapsed + "ms" : "失败 " + String(error || response.status)));
    pending -= 1;
    if (pending === 0) {
      $done({
        title: "策略组健康检查",
        subtitle: results.every((item) => item.includes("正常")) ? "全部可用" : "存在不可用策略",
        message: results.join("\n"),
      });
    }
  });
});
