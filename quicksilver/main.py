import psutil
import os
import requests

def notification(message, topico):
    requests.post(f"https://ntfy.sh/{topico}", data=str(message).encode(encoding='utf-8'))

def get_current_user_processes():
    # Get the username of the current Python process
    current_username = psutil.Process(os.getpid()).username()
    print(f'Usuário: {current_username}')
 
    process_list = []

    for proc in psutil.process_iter(['pid', 'name', 'username']):
        try:
            if proc.info['username'] == current_username:
                process_list.append(proc.info)
        except (psutil.NoSuchProcess, psutil.AccessDenied, PermissionError):
            pass

    return process_list

def get_cpu_status():
    cpu_percent = psutil.cpu_percent(interval=None)
    cpu_times = psutil.cpu_times()
    notification(cpu_percent, 'cpu_usage')
    return cpu_times, cpu_percent

user_processes = get_current_user_processes()
for p in user_processes:
    print(f"PID: {p['pid']}, Name: {p['name']}")

print(get_cpu_status())

