#!/usr/bin/env ruby

# TODO: transformar isso em um servidor para o gui e analises

require 'httparty'
require 'sys/proctable'
require 'json'
require 'time'
require './logo.rb'

NTFY_TOPIC = "quicksilver"

TASKS = []

if ARGV[0] == '-h' or ARGV[0] == '--help'
  pick_logo
  print %q{
  -h/--help: prints help text
  -t <task name>: defines task name, can be used with "" to declare names with spaces
  -i: defines initial time for the defined task
  -e: defines time for the task to end
 
  }
  exit
else
  taskName = ARGV[0]
  taskInitial = ARGV[1]
  taskEnd = ARGV[2]
end

print "Iniciando tarefa: #{taskName} de #{taskInitial} a #{taskEnd}\n"
new_task = {
    name: taskName,
    start_time: taskInitial,
    end_time: taskEnd,
    notified: false
}

TASKS << new_task


LOG_FILE = "quicksilver_log.json"


module SystemMonitor
  include Sys

  def self.send_notification(message)
    url = "https://ntfy.sh/#{NTFY_TOPIC}"
    begin
      HTTParty.post(url, body: message.encode("UTF-8"))
      puts "[NTFY] Notificação enviada: #{message}"
    rescue => e
      puts "[ERRO] Falha ao enviar notificação: #{e.message}"
    end
  end

  def self.get_system_stats
    output = `sensors 2>/dev/null` 
    temp_match = output.match(/(?:Tctl|Package id 0|temp1):\s+\+([\d\.]+)/)
    
    temp = temp_match ? temp_match[1] : "N/A"
    cpu_usage = `grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}'`.strip.to_f.round(2) rescue 0
    mem_info = `free -m | grep Mem | awk '{print $3}'`.strip rescue "0"
    
    timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")

    {
      timestamp: timestamp,
      cpu_usage: "#{cpu_usage}%",
      ram_usage: "#{mem_info}MB",
      temperature: temp
    }
  end
end

SystemMonitor.send_notification("Quicksilver iniciado...")

loop do
  now = Time.now
  current_time_str = now.strftime("%H:%M") # Ex: "10:35"
  
  TASKS.each do |task|
    t_start = Time.parse(task[:start_time])
    t_end   = Time.parse(task[:end_time])
    
    seconds_diff = t_start - now

    if seconds_diff > 0 && seconds_diff <= 600 && !task[:notified]
      minutes, seconds = seconds_diff.divmod(60)
      SystemMonitor.send_notification("Prepare-se! Sua tarefa #{task[:name]} começa em #{format('%02d:%02d', minutes, seconds.round)} minutos (#{task[:start_time]}).")
      task[:notified] = true
    end

    # resetar notificação se já passou muito do horário (para o dia seguinte)
    task[:notified] = false if (now - t_end) > 3600 

    if now >= t_start && now <= t_end
      puts "Monitorando #{task[:name]}..."

      stats = SystemMonitor.get_system_stats
      
      log_entry = {
        task: task[:name],
        stats: stats,
      }

      File.open(LOG_FILE, 'a') do |f|
        f.puts(log_entry.to_json)
      end
    end
  end

  sleep 60
end
