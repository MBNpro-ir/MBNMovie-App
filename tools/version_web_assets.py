"""Give every release immutable asset URLs before publishing the web root."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[1]
base = root / 'build/web'
version = hashlib.sha256(b''.join((base / name).read_bytes() for name in
    ('main.dart.js', 'flutter_bootstrap.js', 'web-access.js', 'ass-renderer.js'))
    + (root / 'web/index.html').read_bytes() + b'mbn-web-assets-release-v1').hexdigest()[:12]
index = base / 'index.html'
text = index.read_text(encoding='utf-8')
for name in ('flutter_bootstrap.js', 'web-access.js', 'ass-renderer.js'):
    text = re.sub(r'src="(?:_mbn_web/[a-f0-9]{12}/)?' + re.escape(name) + r'(?:\?[^"]*)?"',
        f'src="_mbn_web/{version}/{name}"', text)
index.write_text(text, encoding='utf-8')
(base / 'mbn-web-version.json').write_text(json.dumps({'version': version}), encoding='utf-8')
print(version)
