/*
 * Surge generic script: 检查普通 HTTPS 端点；异常时触发通知。
 * 该脚本用于验证通知链路，建议仅在排障时手动运行或由 Debug 模块加载。
 */
const endpoint = "https://cp.cloudflare.com/generate_204";

$httpClient.get({ url: endpoint, policy: "Proxy", timeout: 8000 }, (error, response) => {
  const ok = !error && response && response.status === 204;
  if (!ok) {
    $notification.post("Surge 网络异常", "HTTPS 连通性探测失败", String(error || (response && response.status) || "unknown"));
  }
  $done({
    title: "异常通知测试",
    subtitle: ok ? "正常" : "已发送异常通知",
    message: ok ? "代理 HTTPS 端点可达。" : "请检查网络或当前策略。",
  });
});
