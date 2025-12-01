#!/usr/bin/env ruby

require 'httparty'
require 'sys/proctable'
require 'json'
require 'time'

NTFY_TOPIC = "quicksilver"

TASKS = []
 DEFAULT_APPS = ['nvim', 'firefox', 'gnome-terminal', 'alacritty', 'zsh', 'kitty', 'bash']
print "\nQuantas tarefas para hoje? "
taskI = gets.chomp.to_i

taskI.times do |i|
  print "Defina o nome da sua tarefa: "
  taskName = gets.chomp

  print "Horário inicial da tarefa ('ex: 10:00'): "
  taskInitial = gets.chomp

  print "Horário para finalizar a tarefa: "
  taskEnd = gets.chomp

  new_task = {
    name: taskName,
    start_time: taskInitial,
    end_time: taskEnd,
    apps_of_interest: DEFAULT_APPS,
    notified: false
  }

  TASKS << new_task
end

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

  def self.get_running_apps(interest_list)
    # filtra processos que correspondem aos nomes na lista de interesse
    found = []
    ProcTable.ps do |p|
      # verifica se o nome do executável contém algo da lista
      if interest_list.any? { |app| p.comm.include?(app) || p.cmdline.include?(app) }
        found << p.comm unless found.include?(p.comm)
      end
    end
    found
  end

  def self.get_system_stats
    temp = `sensors 2>/dev/null | grep 'Package id 0' | awk '{print $4}'`.strip # FIX: não esta funcionando como deveria
    temp = "N/A" if temp.empty?

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

puts "Iniciando monitor de tarefas..."
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
      active_apps = SystemMonitor.get_running_apps(task[:apps_of_interest])
      
      log_entry = {
        task: task[:name],
        stats: stats,
        active_apps: active_apps
      }

      File.open(LOG_FILE, 'a') do |f|
        f.puts(log_entry.to_json)
      end
    end
  end

  sleep 60
end
