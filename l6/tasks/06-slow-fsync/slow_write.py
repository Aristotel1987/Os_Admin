#!/usr/bin/env python3
import os
f=open("/tmp/bigfile","wb",buffering=0)
f.write(b"x"*1024*1024*64)
os.fsync(f.fileno())