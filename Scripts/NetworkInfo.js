/*
 * Surge generic script: 汇总当前网络可读取的信息，并通过直连探测网络基础可达性。
 */
const endpoint = "https://cp.cloudflare.com/generate_204";
const network = typeof $network === "undefined" ? {} : $network;
const wifi = network.wifi || {};
const cellular = network.cellular || {};
const networkName = wifi.ssid || cellular.carrier || "未读取到网络名称";

$httpClient.get({ url: endpoint, policy: "DIRECT", timeout: 8000 }, (error, response) => {
  const ok = !error && response && response.status === 204;
  $done({
    title: "网络信息",
    subtitle: networkName,
    message: "直连基础连通性：" + (ok ? "正常" : "异常") + "\n建议：节点状态请运行“节点健康检查”。",
  });
});
