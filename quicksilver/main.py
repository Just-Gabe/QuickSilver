import psutil
import getpass
import requests
import collections
import json 
from typing import List, Dict, Any, Tuple

class ProcessManager:
    """
    Uma classe para gerenciar e consultar uma lista de processos de forma eficiente.
    """
    def __init__(self, process_list: List[Dict[str, Any]]):
        self._processes = process_list
        self.by_name = collections.defaultdict(list)
        self.by_pid = {}
        self._organize()

    def _organize(self):
        """Método interno para popular as estruturas de dados."""
        for process in self._processes:
            self.by_pid[process['pid']] = process
            self.by_name[process['name']].append(process)

    def get_by_pid(self, pid: int) -> Dict[str, Any] | None:
        """Retorna os detalhes de um processo pelo seu PID."""
        return self.by_pid.get(pid)

    def get_by_name(self, name: str) -> List[Dict[str, Any]]:
        """Retorna uma lista de todos os processos com um determinado nome."""
        return self.by_name.get(name, [])

    def get_pids_by_name(self, name: str) -> List[int]:
        """Retorna uma lista de PIDs para um determinado nome de processo."""
        return [p['pid'] for p in self.get_by_name(name)]
    
    def list_unique_processes(self) -> List[str]:
        """Retorna uma lista com os nomes de todos os processos únicos."""
        return sorted(list(self.by_name.keys()))



def send_notification(message: str, topic: str, title: str = "Alerta do Sistema"):
    """
    Envia uma notificação para um tópico ntfy.sh com um título.
    """
    try:
        requests.post(
            f"https://ntfy.sh/{topic}",
            data=str(message).encode(encoding='utf-8'),
            headers={"Title": title}
        )
        print(f"Notificação enviada para o tópico '{topic}'.")
    except requests.exceptions.RequestException as e:
        print(f"Erro ao enviar notificação: {e}")

def get_user_processes() -> List[Dict[str, Any]]:
    """
    Obtém todos os processos pertencentes ao usuário atual.
    """
    try:
        current_username = getpass.getuser()
    except Exception:
        # Fallback caso getpass falhe em alguns ambientes
        current_username = psutil.Process().username()
        
    process_list = []
    for proc in psutil.process_iter(['pid', 'name', 'username', 'status']):
        try:
            if proc.info['username'] == current_username:
                process_list.append(proc.info)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return process_list

def get_processes() -> list[Dict[str, any]]:
    process_list = []
    for proc in psutil.process_iter(['pid', 'name', 'username', 'status']):
        try:
            process_list.append(proc.info)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return process_list


def get_cpu_status() -> Tuple[float, psutil._common.scpufreq]:
    """
    Retorna a porcentagem de uso e a frequência da CPU.
    """
    cpu_percent = psutil.cpu_percent(interval=1) # Usar um intervalo para medição mais precisa
    cpu_freq = psutil.cpu_freq()
    
    message = f"Uso atual: {cpu_percent}% | Frequência: {cpu_freq.current if cpu_freq else 'N/A'} MHz"
    send_notification(message, 'cpu_usage', title="Status da CPU")

    return cpu_percent, cpu_freq

def save_data_as_json(data: Any, filename: str):
    """
    Converte um objeto Python (lista ou dicionário) para JSON e salva em um arquivo.

    Args:
        data: O objeto Python a ser convertido.
        filename: O nome do arquivo de saída (ex: 'dados.json').
    """
    try:
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
        print(f"Dados salvos com sucesso em '{filename}'")
    except (IOError, TypeError) as e:
        print(f"Erro ao salvar o arquivo '{filename}': {e}")


def main():
    print("Coletando processos...")
    all_processes_list = get_processes()
    user_processes_list = get_user_processes()
    get_cpu_status()
    
    proc_manager = ProcessManager(all_processes_list)
    print(f"Encontrados {len(all_processes_list)} processos no total.")
    print(f"Encontrados {len(user_processes_list)} processos para o usuário '{getpass.getuser()}'.")
    print(f"Número de nomes de processos únicos: {len(proc_manager.list_unique_processes())}\n")
    
    print("Agrupando processos por status...")
    processes_by_status = collections.defaultdict(list)
    for item in all_processes_list:
        processes_by_status[item['status']].append(item)
    
    processes_by_status = dict(processes_by_status)
    
    print("\nExportando dados para JSON...")
    
    save_data_as_json(all_processes_list, 'todos_os_processos.json')
    
    save_data_as_json(user_processes_list, 'processos_do_usuario.json')

    save_data_as_json(processes_by_status, 'processos_por_status.json')


if __name__ == "__main__":
    main()
