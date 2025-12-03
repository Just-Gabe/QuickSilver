#!/usr/bin/env ruby

# TODO: transformar isso em um servidor para o gui e analises

require 'httparty'
require 'sys/proctable'
require 'json'
require 'time'
require_relative 'logo'

class QuicksilverApp
  include Sys

  NTFY_TOPIC = "quicksilver" # TODO: fazer ser configuravel
  LOG_FILE = File.join(Dir.home, "quicksilver_log.json")

  def initialize(args)
    @args = args
    @tasks = []
  end

  def run
    handle_arguments
    start_monitoring
  end

  private

  def handle_arguments
    if @args.empty? || @args.include?('-h') || @args.include?('--help')
      show_help
      exit
    end

    if @args.length < 3
      puts "[ERRO] Faltam argumentos!".colorize(:red) rescue puts "[ERRO] Faltam argumentos!"
      puts "Uso: quicksilver <nome> <inicio> <fim>"
      exit 1
    end

    task_name = @args[0]
    task_start = @args[1]
    task_end = @args[2]

    puts "Agendando: #{task_name} | #{task_start} -> #{task_end}"
    
    @tasks << {
      name: task_name,
      start_time: task_start, # Mantemos como string para converter no loop
      end_time: task_end,
      notified_start: false,
      notified_end: false
    }
  end

  def show_help
    begin
      pick_logo 
    rescue
      puts "QuickSilver"
    end

    print %q{
    Uso:
      quicksilver <nome_tarefa> <hora_inicio> <hora_fim>

    Exemplos:
      quicksilver "Estudar Ruby" 14:00 16:00
      quicksilver "Reunião" 10:30 11:00

    Opções:
      -h, --help    Mostra esta mensagem
    }
    puts ""
  end

  def send_notification(message)
    url = "https://ntfy.sh/#{NTFY_TOPIC}"
    begin
      HTTParty.post(url, body: message.encode("UTF-8"))
      puts "[NTFY] Enviado: #{message}"
    rescue => e
      puts "[ERRO NTFY] #{e.message}"
    end
  end

  def get_system_stats
    # Sensores de temperatura
    output = `sensors 2>/dev/null`
    temp_match = output.match(/(?:Tctl|Package id 0|temp1):\s+\+([\d\.]+)/)
    temp = temp_match ? temp_match[1] : "N/A"

    # CPU (Comando genérico Linux)
    cpu_usage = `grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}'`.strip.to_f.round(2) rescue 0
    
    # RAM
    mem_info = `free -m | grep Mem | awk '{print $3}'`.strip rescue "0"
    
    timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")

    {
      timestamp: timestamp,
      cpu_usage: "#{cpu_usage}%",
      ram_usage: "#{mem_info}MB",
      temperature: temp
    }
  end

  def start_monitoring
    send_notification("Quicksilver iniciado para: #{@tasks.first[:name]}")
    puts "Monitoramento iniciado. (Ctrl+C para parar)"

    loop do
      now = Time.now
      
      @tasks.each do |task|
        # Parseia a hora baseada no dia de hoje
        t_start = Time.parse(task[:start_time])
        t_end   = Time.parse(task[:end_time])

        # Se o horário final for menor que o inicial adiciona 1 dia
        t_end += 86400 if t_end < t_start

        seconds_to_start = t_start - now
        seconds_to_end   = t_end - now

        if seconds_to_start > 0 && seconds_to_start <= 600 && !task[:notified_start]
          minutes = (seconds_to_start / 60).to_i
          send_notification("Prepare-se! '#{task[:name]}' começa em #{minutes} minutos.")
          task[:notified_start] = true
        end

        if seconds_to_end <= 0 && !task[:notified_end]
          send_notification("Tarefa Finalizada: #{task[:name]}!")
          task[:notified_end] = true
          puts "Tarefa finalizada. Encerrando monitor."
          exit 0 # Sai do programa pois a tarefa acabou
        end

        if now >= t_start && now < t_end
          puts "[LOG] Monitorando #{task[:name]}... (Temp: #{get_system_stats[:temperature]}°C)"
          
          log_entry = {
            task: task[:name],
            stats: get_system_stats
          }

          File.open(LOG_FILE, 'a') do |f|
            f.puts(log_entry.to_json)
          end
        elsif now < t_start
             puts "Aguardando início... Falta #{(seconds_to_start/60).round} min."
        end
      end

      sleep 60
    end
  end
end
