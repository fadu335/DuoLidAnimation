#!/usr/bin/env python3
import json
from pathlib import Path
root = Path(__file__).resolve().parent
(root/'overlay.json').write_text(json.dumps({'version': 0, 'roots': [{
    'type': 'file',
    'name': '/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap',
    'external-contents': str(root/'empty.modulemap')
}]}))
