server           = true
bootstrap_expect = 1
datacenter       = "dc1"
node_name        = "haproxy"
data_dir         = "/var/lib/consul"

bind_addr   = "0.0.0.0"
client_addr = "0.0.0.0"

ui_config { enabled = true }

# Habilitamos DNS de Consul para service discovery en HAProxy
ports { dns = 8600 }

log_level = "INFO"
