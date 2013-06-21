service = File.dirname(File.expand_path(__FILE__)).split('/').last
config_dir = "#{ENV['HOME']}/.opentox/config"
log_dir = "#{ENV['HOME']}/.opentox/log"
log_file = File.join log_dir, "#{service}.log"
require File.join config_dir, service
port = eval("$#{service}[:port]")
listen port
pid File.join(log_dir,"#{service}.pid")
stderr_path log_file
stdout_path log_file

