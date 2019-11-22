#!/usr/bin/python3

import sys, os
import yaml
from subprocess import run

repo = sys.argv[1]

with open(f"{repo}.yaml", 'r') as yaml_file:
    yml = yaml.safe_load(yaml_file)

artifacts = [f[:-4] for f in os.listdir(repo) if f.endswith('.rpm')]
rpms = {'rpms': []}
for a in artifacts:
    epoch = run(f"rpm -qp --queryformat='%{{EPOCH}}:%{{VERSION}}' {repo}/{a}.rpm", shell=True, capture_output=True).stdout
    ev = epoch.decode("utf-8").strip().replace('(none)', '0')
    parts = a.split('-')
    rpms['rpms'].append('-'.join(parts[:-2] + [ev] + parts[-1:]))
yml['data']['artifacts'] = rpms

with open(f"{repo}-modulemd.txt", 'w') as yaml_file:
    yaml.dump(yml, yaml_file)

# Regenerate repository metadata
run(["createrepo_c", repo])
run(["modifyrepo_c", "--mdtype=modules", f"{repo}-modulemd.txt", f"{repo}/repodata"])
