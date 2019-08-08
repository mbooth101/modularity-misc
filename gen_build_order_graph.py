#!/usr/bin/python3

import sys
import yaml
from pygraphviz import AGraph
from subprocess import call

if len(sys.argv) < 2:
    sys.stderr.write("Must specify module yaml file\n")
    sys.exit(2)

show = False
if len(sys.argv) > 2:
    if sys.argv[2] == "--show":
        show = True

with open(sys.argv[1], 'r') as stream:
    yaml = yaml.safe_load(stream)

rpms = yaml['data']['components']['rpms']

g = AGraph(directed=True, name="G", strict=False, label="Build Order Graph")
ranks = {}
for key, value in rpms.items():
    # Add each buildorder rank as a distinct sub-graph
    rank = value['buildorder']
    if rank not in ranks:
        ranks[rank] = [key]
    else:
        ranks[rank].append(key)
    subg = g.get_subgraph(f"{rank}")
    if subg is None:
        subg = g.add_subgraph(name=f"{rank}", label=f"Build Order {rank}", rank="same")
    subg.add_node(f"{rank}")
    # Parse the dependency relationships
    reqs = []
    breqs = []
    api = False
    for r in value['rationale'].replace('\n', ' ').split('.'):
        r = r.strip()
        if not r:
            continue
        if r == 'Module API':
            api = True
            continue
        if r.startswith('Runtime dependency of'):
            r = r[len('Runtime dependency of'):]
            reqs = [x.strip() for x in r.split(',')]
        if r.startswith('Build dependency of'):
            r = r[len('Build dependency of'):]
            breqs = [x.strip() for x in r.split(',')]
    # Highlight packages that form the module API
    if api:
        subg.add_node(key, color='green')
    else:
        subg.add_node(key)
    # Add the dependency relationships to the graph
    for req in reqs:
        # For Rs, check if also a BR
        if req not in breqs:
            g.add_edge(key, req, color='blue')
        else:
            g.add_edge(key, req, color='purple')
    for breq in breqs:
        # For BRs, check if also a R
        if breq not in reqs:
            g.add_edge(key, breq, color='red')
# Add the ranking key to the graph
order = list(ranks.keys())
order.sort()
for idx, rank in enumerate(order):
    if idx+1 < len(order):
        g.add_edge(rank, order[idx+1], weight=1000)

# Generate graph
g.draw("build_order_graph.png", prog="dot")
if show:
    call('eog build_order_graph.png &', shell=True)

# Generate build order lists for build script
f=open("build_order_graph.sh","w+")
for idx, rank in enumerate(order):
    f.write(f"declare -a RANK_{rank}\n")
    rank_array = ""
    for r in ranks[rank]:
        rank_array = rank_array + f"'{r}' "
    rank_array = f"RANK_{rank}=( " + rank_array + ")\n"
    f.write(rank_array)
f.write(f"declare -a RANKS\n")
order_array = ""
for o in order:
    order_array = order_array + f"'RANK_{o}' "
order_array = f"RANKS=( " + order_array + ")\n"
f.write(order_array)
f.close()


