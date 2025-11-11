# Отчёт  
По лабораторной работе № 7

- Студент: Выдумкин Илья 
- Группа: p4250  
- Дата выполнения: 10.11.2025  
- Дисциплина: Системное администрирование  
- Задание: L7 — Тюнинг ядра и GRUB

## Цель работы
Познакомиться с параметрами ядра Linux и загрузчиком GRUB, понять, как ядро принимает параметры при старте системы, научиться проверять, какие параметры реально применяются, и разобраться в их назначении для производительности и безопасности.

---

## 0. Резервное копирование конфига GRUB
Назначение: создать резервную копию файла /etc/default/grub перед изменениями.  
Команда:

sudo cp /etc/default/grub /etc/default/grub.bak

Результат: копия успешно создана.  
Вывод: файл /etc/default/grub.bak создан и может быть использован для отката.

---

## 1. Редактирование файла /etc/default/grub
Назначение: добавить необходимые параметры ядра в конфигурацию GRUB.  
Команда:

sudo nano /etc/default/grub

Изменённые строки:
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_idle.max_cstate=0 noinvpcid nopcid nopti nospectre_v2 processor.max_cstate=1 apparmor=0"
GRUB_CMDLINE_LINUX="intel_idle.max_cstate=0 noinvpcid nopcid nopti nospectre_v2 processor.max_cstate=1 apparmor=0"

Пояснение: параметры ядра разделяются пробелами, потому что каждый параметр является отдельным аргументом командной строки ядра. Запятые используются только внутри одного параметра, если он принимает список значений.  
Вывод: параметры добавлены корректно, конфигурация подготовлена к обновлению загрузчика.

---

## 2. Обновление конфигурации загрузчика GRUB
Назначение: применить изменения в конфигурации GRUB.  
Команда:

sudo update-grub

Результат: конфигурация обновлена без ошибок.  
Вывод: изменения в /etc/default/grub учтены, загрузчик готов к перезагрузке с новыми параметрами.

---

## 3. Перезагрузка системы и фиксация применённых параметров
Назначение: перезагрузить систему и зафиксировать строку загрузки ядра.  
Команды:

sudo reboot
cat /proc/cmdline > ~/L7_tuning/logs/cmdline.txt

Вывод:

BOOT_IMAGE=/boot/vmlinuz-6.1.0-40-amd64 root=UUID=13004976-f859-4449-b4f3-bf826315c551 ro quiet splash intel_idle.max_cstate=0 noinvpcid nopcid nopti nospectre_v2 processor.max_cstate=1 apparmor=0

Вывод: все параметры, добавленные в GRUB, применены при загрузке системы.

---

## 4. Проверка параметров через /sys/module/*/parameters/
Назначение: подтвердить применение параметров, связанных с энергосбережением и AppArmor.  
Команды:

cat /sys/module/intel_idle/parameters/max_cstate
sudo cat /sys/module/processor/parameters/max_cstate
cat /sys/module/apparmor/parameters/enabled

Вывод:

intel_idle/max_cstate: 0
processor/max_cstate: 1
apparmor/enabled: N

Вывод: параметры intel_idle.max_cstate=0 и processor.max_cstate=1 применены. AppArmor отключён (значение N).

---

## 5. Проверка статуса уязвимостей и митигаций
Назначение: определить статус защиты Spectre/Meltdown и связанных технологий.  
Команда:

paste -d ': ' <(basename -a /sys/devices/system/cpu/vulnerabilities/*) \
              <(cat /sys/devices/system/cpu/vulnerabilities/*) \
  > ~/L7_tuning/logs/vulns_summary.txt

Фрагмент вывода:

spectre_v1: Mitigation: usercopy/swapgs barriers and __user pointer sanitization
spectre_v2: Vulnerable; IBPB: disabled; STIBP: disabled; PBRSB-eIBRS: Not affected; BHI: Not affected
meltdown: Not affected

Вывод: параметр nospectre_v2 ядром не распознан, защита Spectre v2 не активна. Остальные статусы сохранены для отчёта.

## 6. Проверка dmesg на наличие подтверждений и сообщений ядра
Назначение: зафиксировать, какие параметры были распознаны и применены ядром.  
Команда:

sudo dmesg | grep -i -E 'kernel command line|page table isolation|pti|spectre|meltdown|pcid|invpcid' > ~/L7_tuning/logs/dmesg_mitigations.txt

Фрагмент вывода:

[    0.000000] Command line: ... intel_idle.max_cstate=0 noinvpcid nopcid nopti nospectre_v2 processor.max_cstate=1 apparmor=0
[    0.000000] noinvpcid: INVPCID feature disabled
[    0.009010] Unknown kernel command line parameters "splash nopti nospectre_v2 BOOT_IMAGE=/boot/vmlinuz-6.1.0-40-amd64", will be passed to user space.
[    0.049124] Spectre V2 : User space: Vulnerable

Вывод: параметр noinvpcid успешно применён. Параметры nopti и nospectre_v2 ядром не распознаны и были проигнорированы.

---

## 7. Проверка флагов CPU и наличия модулей
Назначение: определить поддержку PCID/INVPCID и наличие подсистем в виде модулей.  
Команды:

grep -m1 '^flags' /proc/cpuinfo > ~/L7_tuning/logs/cpu_flags_one_core.txt
{
  echo "[intel_idle]"; lsmod | grep -E '^intel_idle\s'   echo "not in lsmod (may be built-in)";
  echo; echo "[processor]"; lsmod | grep -E '^processor\s'  echo "not in lsmod (may be built-in or unused)";
  echo; echo "[apparmor]";  lsmod | grep -E '^apparmor\s'  || echo "not in lsmod (may be built-in or disabled)";
} > ~/L7_tuning/logs/lsmod_relevant.txt

Фрагмент вывода флагов:

flags : ... svm amd_lbr_v2 ...

Фрагмент вывода lsmod:

[intel_idle]
not in lsmod (may be built-in)

[processor]
not in lsmod (may be built-in or unused)

[apparmor]
not in lsmod (may be built-in or disabled)

Вывод: PCID отсутствует в списке флагов CPU, что объясняет отсутствие эффекта от параметра nopcid. Подсистемы не отображаются в lsmod, что означает их встроенность в ядро.

---

## 8. Сводная таблица параметров

| Параметр                         | Статус на данной системе        | Доказательство                                                      | Назначение                                      |
|----------------------------------|---------------------------------|---------------------------------------------------------------------|-------------------------------------------------|
| intel_idle.max_cstate=0          | Применён                        | /sys/module/intel_idle/parameters/max_cstate = 0                   | Запрет глубоких C-states драйвера intel_idle    |
| processor.max_cstate=1           | Применён                        | /sys/module/processor/parameters/max_cstate = 1                    | Ограничение C-states через драйвер processor    |
| apparmor=0                       | Применён                        | /sys/module/apparmor/parameters/enabled = N                        | Отключение AppArmor                             |
| noinvpcid                        | Применён                        | dmesg: noinvpcid: INVPCID feature disabled                         | Отключение использования INVPCID                |
| nopcid                           | Неактуален (PCID отсутствует)   | отсутствует флаг pcid в /proc/cpuinfo                               | Отключение PCID (не поддерживается на AMD)      |
| nopti                            | Игнорируется ядром              | dmesg: Unknown kernel command line parameter 'nopti'               | Отключение PTI                                  |
| nospectre_v2                     | Игнорируется ядром              | dmesg: Unknown kernel command line parameter 'nospectre_v2'        | Отключение защиты Spectre v2                    |

---

## 9. Итог работы

- Конфигурация загрузчика GRUB изменена, параметры ядра успешно добавлены.  
- Обновление конфигурации GRUB и перезагрузка выполнены без ошибок.  
- Параметры подтверждены через /proc/cmdline.  
- Применение параметров intel_idle.max_cstate, processor.max_cstate, apparmor=0 зафиксировано через /sys/module.  
- Параметр noinvpcid успешно применён.  
- Параметры nopti и nospectre_v2 ядром не распознаны и были проигнорированы.  
- nopcid не актуален для данной системы, так как PCID не поддерживается процессором.  
- Все результаты зафиксированы в текстовом виде и сохранены в папке ~/L7/logs/.

---

## 10. Приложения (фрагменты логов)

GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_idle.max_cstate=0 noinvpcid nopcid nopti nospectre_v2 processor.max_cstate=1 apparmor=0"
GRUB_CMDLINE_LINUX=""

BOOT_IMAGE=/boot/vmlinuz-6.1.0-40-amd64 root=UUID=13004976-f859-4449-b4f3-bf826315c551 ro quiet splash intel_idle.max_cstate=0 noinvpcid nopcid nopti nospectre_v2 processor.max_cstate=1 apparmor=0

noinvpcid: INVPCID feature disabled
Unknown kernel command line parameters "splash nopti nospectre_v2 ...", will be passed to user space.

spectre_v2: Vulnerable; IBPB: disabled; STIBP: disabled; PBRSB-eIBRS: Not affected; BHI: Not affected
meltdown: Not affected
