# modularity-misc
Some misc scripts for Fedora Modularity

## Cache Module RPMs

E.g.:

```
$ ./cache_module_deps.sh javapackages-tools 201801 28
$ ./cache_module_deps.sh tycho 1.4 30
```

## Generate Build Order Graph

E.g.:

```
$ ./gen_build_order_graph.py ../tycho/tycho.yaml
$ ./gen_build_order_graph.py ../eclipse/eclipse.yaml --show
```
