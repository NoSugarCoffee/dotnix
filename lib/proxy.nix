{
  proxyUrl = "http://127.0.0.1:7890";
  # 100.64.0.0/10 is Tailscale's CGNAT range: tailnet peers are reachable
  # without the proxy and not reachable through it.
  noProxy = "localhost,127.0.0.1,10.96.0.0/12,192.168.59.0/24,192.168.49.0/24,192.168.39.0/24,100.64.0.0/10,.ctripcorp.com,.tripqate.com,.larkenterprise.com";
}
