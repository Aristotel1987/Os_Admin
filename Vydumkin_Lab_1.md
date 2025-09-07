# Отчет
# По домашнему заданию № 1 от 02.09.2025

Студент: Выдумкин Илья Александрович
Преподаватель: Некрасов Евгений Андреевич 
Группа: p4250  
Дата выполнения: 07.09.2025  
дисциплина: Системное адмиминистрирование

### Задание 1. SSH

Установим SSH:
  ```bash
  sudo apt-get install openssh-server
  ```
Перенести SSH на порт от 10000 до 65535.
Создать нового пользователя с правами sudo.
Полностью отключить root для входа.
Запретить вход по паролю, оставить только ключи.
Проверить подключение по ключу к новому пользователю.

В терминале:
   ```bash
   sudo nano /etc/ssh/sshd_config
   ```

В файле были изменены параметры:
   ```bash
   Port 55555
   PermitRootLogin no
   PasswordAuthentication no
   StrictModes no
   ```
Примечание: Все параметры были изначально закомментированы.

Затем:
   ```bash
   sudo adduser student
   sudo usermod -aG sudo student
   sudo systemctl restart ssh
   ```
Теперь нужно подключиться к серверу по ssh при помощи ssh- ключей.
Генерация SSH-ключей 
На Windows ключи можно сгенерировать при помощи puttygen.
Процесс несложный. Запускаем утилиту puttygen, жмем "Generrate", (затем из поля "Public key for pasting into OpenSSH authorized_keys file" копируем все содержимое куда-нибудь, оно понадобится дальше. затем сохраняем ключ на компьютере через "file/Save public key".
А теперь в Linux:
   ```bash
   mkdir -p /home/student/.ssh
   ```
   В папку .ssh кладем файл с публичным ключем и называем authorized_keys
   Пытаемся установить права:
   ```bash
   chown -R student:student /home/student/.ssh
   chmod 700 /home/student/.ssh
   chmod 600 /home/student/.ssh/authorized_keys
   ```
Теперь открываем putty, вводим ip-адрес и порт, в моем случае адрес 192.168.1.35 и порт 55555
Затем в дереве нужно найти "connection" и там выбрать  "data" и в поле Auto-login username ввести имя нашего пользователя.
Затем в дереве нужно перейти в "Connection" -> "SSH" -> "Auth" -> "Credentials"и через кнопку "Browse..." выбрать закрытый ключ.
В моем случае результат такой:
student@deb12:/$
Теперь можно с этим работать.
---

### Задание 2. iptables

В Debian 12 отсутствует iptables, установим его
 ```bash
   sudo install iptables
   ```
Разрешить только loopback, установленные соединения и SSH.
Проверить открытые порты через `nmap`.
Сохранить правила iptables и проверить их после перезагрузки.
Разрешаем только loopback, установленные соединения и SSH
   ```bash
   sudo iptables -A INPUT -i lo -j ACCEPT
   sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
   sudo iptables -A INPUT -p tcp --dport 30781 -j ACCEPT
   sudo iptables -A INPUT -j DROP
   ```

Проверяем открытые порты через `nmap`
Устанавливаем:
   sudo apt install nmap
   И проверяем, какие порты открыты.
   ```bash
   nmap -sT localhost
   ```

Результат:
Starting Nmap 7.93 ( https://nmap.org ) at 2025-09-07 21:40 MSK
Nmap scan report for localhost (127.0.0.1)
Host is up (0.00010s latency).
Other addresses for localhost (not scanned): ::1
Not shown: 996 closed tcp ports (conn-refused)
PORT      STATE SERVICE
25/tcp    open  smtp
631/tcp   open  ipp
5432/tcp  open  postgresql
55555/tcp open  unknown

Nmap done: 1 IP address (1 host up) scanned in 0.04 seconds
                  





---

### Задание 3. Fail2ban (дополнительно)

Установить `fail2ban`.

```bash
sudo apt install fail2ban -y
```

Настроить блокировку IP после 3–5 неудачных попыток.
Открываем конфигурационный файл
```bash
   sudo nano /etc/fail2ban/jail.local
```
Находим параметр, отвечающий за количество попыток
   maxretry = 3    

Проверить, что IP блокируется при многократном вводе неверного пароля.
Вход по паролю не разрешен, потому проверить не представляется возможным.
---

### Задание 4. Логирование и анализ

Изучить файл логов:
В Debian 12 отсутствует /var/log/auth.log

В Debian 12 для просмотра системных журналов используется команда
journalctl, поскольку традиционная система syslog была заменена на systemd-journald. Чтобы просмотреть журналы, откройте терминал и введите journalctl
Чтобы просмотреть попытки входа с помощью
journalctl, используйте команду journalctl -u sshd
```bash
   sudo journalctl -u sshd
```

Найти IP-адреса, с которых были попытки входа.
Подсчитать успешные и неуспешные подключения.
Составить краткий отчёт.

---

### Задание 5. Дополнительное

Настроить приветственное сообщение (`/etc/motd`).
Добавить ещё один разрешённый порт в iptables (например, 80 для будущего веб-сервера).
Подготовить список команд, которые вы использовали, и объяснить их назначение.

---

## Итог

* Студенты освоили базовую защиту SSH.
* Настроили межсетевой экран с iptables.
* Научились анализировать логи и применять инструменты защиты (fail2ban).

---

