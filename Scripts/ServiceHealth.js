/*
 * Surge generic script: 检查 ChatGPT、GitHub 与 YouTube 的网络连通性。
 * 只判断服务端是否可达；不检查帐户登录、区域资格或订阅权益。
 */
const checks = [
  { name: "ChatGPT", url: "https://chatgpt.com/", policy: "AI" },
  { name: "GitHub", url: "https://api.github.com/zen", policy: "Developer" },
  { name: "YouTube", url: "https://www.youtube.com/generate_204", policy: "Media" },
];
const results = [];
let pending = checks.length;

checks.forEach((check) => {
  const startedAt = Date.now();
  $httpClient.get({ url: check.url, policy: check.policy, timeout: 10000 }, (error, response) => {
    const elapsed = Date.now() - startedAt;
    const status = response ? response.status : 0;
    const reachable = !error && status > 0 && status < 500;
    results.push(check.name + ": " + (reachable ? "可达 " + elapsed + "ms（HTTP " + status + "）" : "失败 " + String(error || status)));
    pending -= 1;
    if (pending === 0) {
      $done({
        title: "服务连通性检查",
        subtitle: results.every((item) => item.includes("可达")) ? "全部可达" : "存在不可达服务",
        message: results.join("\n"),
      });
    }
  });
});
