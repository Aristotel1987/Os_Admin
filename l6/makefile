alltasks: task1 task2 task3 task4 task5 task6 task7 task8
task1: prep
	strace -tt -T -y -e trace=file -o logs/01.strace ./tasks/01-permissions/broken.sh || true
task2: prep
	strace -tt -T -s 200 -e trace=file -o logs/02.strace ./tasks/02-missing-file/broken.sh || true
task3: prep
	strace -f -tt -T -yy -s 200 -o logs/03.strace -e trace=network,recvfrom,sendto,connect,getsockopt,select,poll,epoll_pwait python3 tasks/03-dns-timeout/client.py || true
task4: prep
	strace -tt -T -yy -e trace=network -o logs/04.strace ./tasks/04-port-denied/tcp.sh || true
task5: prep
	strace -f -tt -T -s 200 -y -o logs/05.strace python3 tasks/05-file-lock/lock.py &
	sleep 1
	pkill -f lock.py
task6: prep
	strace -tt -T -e trace=write,fsync,futex -o logs/06.strace python3 tasks/06-slow-fsync/slow_write.py || true
task7: prep
	timeout 2 strace -ff -o logs/07 -tt -T -f -s 120 -y bash tasks/07-daemonize/daemon.sh || true
task8: prep
	AA_CACHE=$$(mktemp -d) ; /sbin/apparmor_parser -r -T $$AA_CACHE tasks/08-apparmor/profile ; strace -tt -T -y -e trace=file -o logs/08.strace python3 -c "open('/etc/shadow').read()" || true
prep:
	chmod +x tasks/*/*.sh tasks/*/*.py
