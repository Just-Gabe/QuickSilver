require 'httparty'
require 'sys/proctable'
require 'json'
require 'time'
require 'securerandom'
require 'fileutils'
require_relative 'logo'

class QuicksilverApp
  include Sys
  
  BASE_DIR = File.join(Dir.home, ".quicksilver")
  LOG_FILE = File.join(BASE_DIR, "quicksilver_history.json")
  PID_DIR  = File.join(BASE_DIR, "pids")
  
if File.exist?(BASE_DIR)
  NTFY_TOPIC = File.read("#{BASE_DIR}/config.txt")
else
  NTFY_FILE = File.write("#{BASE_DIR}/config.txt", "quicksilver") # Padrão "quicksilver" mas mude
  NTFY_TOPIC = File.read("#{BASE_DIR}/config.txt")
end

  def initialize(args)
    FileUtils.mkdir_p(BASE_DIR)
    FileUtils.mkdir_p(PID_DIR)

    @args = args
    @tasks = []
    @session_id = SecureRandom.uuid 
  end

  def run
    handle_arguments
    
    if @args.include?('-d') || @args.include?('--daemon')
      daemonize_process
    end

    start_monitoring
  end

  private

  def handle_arguments
    if @args.empty? || @args.include?('-h') || @args.include?('--help')
      show_help
      exit
    end

    if @args.include?('status') || @args.include?('--list')
      list_active_tasks
      exit
    end

    clean_args = @args.reject { |a| a.start_with?('-') }
    if clean_args.length < 3
      puts "[ERRO] Faltam argumentos!".colorize(:red) rescue puts "[ERRO] Faltam argumentos!"
      exit 1
    end

    @tasks << {
      name: clean_args[0],
      start_time: clean_args[1],
      end_time: clean_args[2],
      notified_start: false,
      notified_end: false
    }
  end

  def daemonize_process
    puts "Quicksilver indo para background..."
    puts "ID da Sessão: #{@session_id}"
    
    Process.daemon(true, true) 

    # redireciona STDOUT e STDERR para um arquivo de debug
    debug_log = File.open(File.join(BASE_DIR, "output.log"), 'a')
    $stdout.reopen(debug_log)
    $stderr.reopen(debug_log)

    # salva o PID para mapeamento de processos/tarefas
    pid_file = File.join(PID_DIR, "#{@session_id}.pid")
    File.write(pid_file, Process.pid)
    
    # garante que o arquivo PID seja deletado quando o processo morrer
    at_exit { File.delete(pid_file) if File.exist?(pid_file) }
  end

  def list_active_tasks
    pids = Dir.glob(File.join(PID_DIR, "*.pid"))
    
    if pids.empty?
      puts "Nenhuma tarefa do Quicksilver rodando em background."
      return
    end

    puts "=== Tarefas Ativas ==="
    pids.each do |pid_file|
      pid = File.read(pid_file).to_i
      begin
        Process.getpgid(pid)
        puts "PID: #{pid} | Arquivo: #{File.basename(pid_file)}"
      rescue Errno::ESRCH
        puts "PID: #{pid} (Processo morreu mas arquivo PID sobrou)"
        File.delete(pid_file)
      end
    end
  end

  def log_data(task_name, status, stats = nil)
    entry = {
      session_id: @session_id, 
      timestamp: Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      task: task_name,
      status: status, # START, RUNNING, FINISHED
      stats: stats
    }
    
    File.open(LOG_FILE, 'a') { |f| f.puts(entry.to_json) }
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
      -h, --help    mostra esta mensagem
      -d, --daemon  passa processo para background
      --list/status lista tarefas

      para configurar o servidor do ntfy, mude o arquivo em .quicksilver/config.txt
    }
    puts ""
  end

  def send_notification(message)
    url = "https://ntfy.sh/#{NTFY_TOPIC}"
    begin; HTTParty.post(url, body: message.encode("UTF-8")); rescue; end
  end

  # def get_system_stats # TODO: fazer para windows também
  #   output = `sensors 2>/dev/null`
  #   temp = output.match(/(?:Tctl|Package id 0|temp1):\s+\+([\d\.]+)/)&.captures&.first || "N/A"
  #   cpu = `grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}'`.strip.to_f.round(2) rescue 0
  #   { temperature: temp, cpu_usage: cpu }
  # end

  def start_monitoring
    task = @tasks.first
    send_notification("Quicksilver agendado: #{task[:name]}")
    
    log_data(task[:name], "SCHEDULED")

    loop do
      now = Time.now
      t_start = Time.parse(task[:start_time])
      t_end   = Time.parse(task[:end_time])
      t_end += 86400 if t_end < t_start

      seconds_to_start = t_start - now
      seconds_to_end   = t_end - now

      if seconds_to_start > 0 && seconds_to_start <= 600 && !task[:notified_start]
        send_notification("#{task[:name]} começa em #{(seconds_to_start/60).to_i} min.")
        task[:notified_start] = true
      end

      if now >= t_start && !@started_flag
         log_data(task[:name], "STARTED")
         @started_flag = true
      end

      if seconds_to_end <= 0 && !task[:notified_end]
        send_notification("Finalizado: #{task[:name]}!")
        log_data(task[:name], "FINISHED")
        exit 0 
      end

      if now >= t_start && now < t_end
        # stats = get_system_stats
        # LOG DE MONITORAMENTO
        # log_data(task[:name], "RUNNING", stats)
        log_data(task[:name], "RUNNING")
        
        puts "Monitorando..." unless @args.include?('-d')
      end

      sleep 60
    end
  end
end
