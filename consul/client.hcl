server      = false
datacenter  = "dc1"
node_name   = "{{HOSTNAME}}"
data_dir    = "/var/lib/consul"
bind_addr   = "0.0.0.0"
client_addr = "0.0.0.0"

retry_join = ["192.168.100.10"]  # IP de haproxy (Consul server)

log_level = "INFO"
