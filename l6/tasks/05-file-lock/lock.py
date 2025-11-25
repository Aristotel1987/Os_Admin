#!/usr/bin/env python3
import fcntl,time,sys
fd=open("/tmp/shared.lock","w")
fcntl.flock(fd,fcntl.LOCK_EX)
print("locked",flush=True)
time.sleep(300)