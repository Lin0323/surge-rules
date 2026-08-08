/*
 * Surge generic script: 显示当前出口 IP、国家、城市和 ASN。
 * 手动运行：Surge -> 更多 -> 脚本 -> 出口 IP 检查。
 */
const endpoint = "https://api.ip.sb/geoip";

$httpClient.get(endpoint, (error, response, data) => {
  if (error) {
    $done({ title: "出口 IP 检查失败", subtitle: "请求失败", message: String(error) });
    return;
  }

  try {
    const info = JSON.parse(data);
    const asn = info.asn ? "AS" + info.asn : "未知 ASN";
    const location = [info.country, info.region, info.city].filter(Boolean).join(" · ");
    $done({
      title: "当前出口 IP",
      subtitle: info.ip || "未返回 IP",
      message: (location || "未知位置") + "\n" + asn + " " + (info.organization || ""),
    });
  } catch (parseError) {
    $done({ title: "出口 IP 检查失败", subtitle: "响应无法解析", message: String(parseError) });
  }
});
