#!/usr/bin/env python3
import urllib.request
print(urllib.request.urlopen("http://example.local:8080/",timeout=3).read().decode())