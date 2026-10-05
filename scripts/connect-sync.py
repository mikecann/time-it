#!/usr/bin/env python3
"""Stage a connection for the installed app without putting the sync key in argv or logs."""
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 scripts/connect-sync.py https://your-deployment.convex.site < protected-key-file")
url = sys.argv[1].strip()
parsed = urlparse(url)
if parsed.scheme != 'https' or not (parsed.hostname or '').endswith('.convex.site') or parsed.username or parsed.password or parsed.port or parsed.path not in ('', '/') or parsed.query or parsed.fragment:
    raise SystemExit("Use an HTTPS Convex HTTP URL ending in .convex.site.")
key = sys.stdin.read().strip()
if len(key) < 32 or '\n' in key or '\r' in key:
    raise SystemExit("Use a single-line sync key of at least 32 characters.")
folder = Path.home() / 'Library/Application Support/com.mikerosoft.time-it'
folder.mkdir(mode=0o700, parents=True, exist_ok=True)
folder.chmod(0o700)
target = folder / 'connection-bootstrap.json'
# Do not overwrite another setup attempt. The app deletes this file after saving the key.
fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as output:
    json.dump({'url': url.rstrip('/'), 'key': key}, output)
print('Connection staged. Restart Time It to save it in Keychain and connect.')
