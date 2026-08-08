/*
 * Surge generic script: 检查 DNS/HTTPS 端点；异常时触发通知。
 * 该脚本用于验证通知链路，建议仅在排障时手动运行或由 Debug 模块加载。
 */
const endpoint = "https://dns.google/dns-query";

$httpClient.get({ url: endpoint, policy: "DIRECT", timeout: 8000 }, (error, response) => {
  const ok = !error && response && response.status >= 200 && response.status < 500;
  if (!ok) {
    $notification.post("Surge 网络异常", "DoH 探测失败", String(error || response.status));
  }
  $done({
    title: "异常通知测试",
    subtitle: ok ? "正常" : "已发送异常通知",
    message: ok ? "DoH 端点可达。" : "请检查网络、DNS 或当前策略。",
  });
});
