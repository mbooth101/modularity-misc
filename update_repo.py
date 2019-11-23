#!/usr/bin/python3

import sys, os
import yaml
from subprocess import run

module = sys.argv[1]
builddir = sys.argv[2]

repo = f"{builddir}/{module}"
repoconf = f"{builddir}/conf/{module}.repo"

# Re-write modulemd yaml to include all newly build RPMs
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

# Generate yum repo configuration if needed
if not os.path.isfile(repoconf):
    sys.stderr.write(f"Generating yum repo configuration at {repoconf}\n")
    with open(repoconf, 'w') as repoconf_file:
        absolute_path = os.path.abspath(repo)
        repoconf_file.write(f"[{module}]\n")
        repoconf_file.write(f"name={module}\n")
        repoconf_file.write(f"baseurl=file://{absolute_path}\n")
        repoconf_file.write(f"enabled=1\n")
        repoconf_file.write(f"sslverify=0\n")
        repoconf_file.write(f"gpgcheck=0\n")
        repoconf_file.write(f"priority=1\n")
