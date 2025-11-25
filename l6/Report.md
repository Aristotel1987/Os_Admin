# Отчет
# По лабораторной работе № 6

Выполнил студент
Выдумкин Илья, группа p4250  
Дата выполнения задания: 23.11.2025  
Наименование дисциплины: системное администрирование
## ## Лабораторная работа анатомия системного сбоя — диагностика с помощью strace
## Системные требования
Все протестировано и гарантированно работает на orangepi 3b, debian 13 Trixie, aarch64
## Структура папки lab6
├── report.md - данный файл
├── analysis.md
├── Makefile
├── logs
└── tasks/
├── 01-permissions/
├── 02-missing-file/
├── 03-dns-timeout/
├── 04-port-denied/
├── 05-file-lock/
├── 06-slow-fsync/
├── 07-daemonize/
└── 08-apparmor/
## Инструкция по запуску
1. Установить нужные пакеты (в моем случае их не было):
sudo apt update
sudo apt install -y make strace apparmor-utils netcat-openbsd
2. Перейти в каталог и выполнить makefile:всех логов
git clone https://github.com/nikkov199525/system_administration.git
cd system_administration/lab6
make alltasks
Что делает make alltasks?
делает все скрипты исполняемыми
последовательно запускает все 8 задач с правильными флагами strace
сохраняет логи в logs/01.strace … 08.strace
для задачи 05 автоматически запускает и убивает блокирующий процесс
для задачи 08 временно подгружает тестовый AppArmor-профиль
можно запускать отдельно
make task1
make task2
и т.д.
