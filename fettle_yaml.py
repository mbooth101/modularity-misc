#!/usr/bin/python3

import sys, os
import yaml

with open(sys.argv[1], 'r') as yaml_file:
    yml = yaml.safe_load(yaml_file)

repo = sys.argv[2]
artifacts = [f[:-4] for f in os.listdir(repo) if f.endswith('.rpm')]
rpms = {'rpms': []}
for a in artifacts:
    parts = a.split('-')
    ev = ''.join(parts[-2:-1])
    if ':' not in ev:
        ev = f"0:{ev}"
    rpms['rpms'].append('-'.join(parts[:-2] + [ev] + parts[-1:]))
yml['data']['artifacts'] = rpms

with open(sys.argv[3], 'w') as yaml_file:
    yaml.dump(yml, yaml_file)
