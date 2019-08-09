# modularity-misc
Some misc scripts for Fedora Modularity

## Cache Module RPMs

Cache locally all the RPMs for the given module, stream and platform.

E.g.:

```
$ ./cache_module_deps.sh javapackages-tools 201801 28
$ ./cache_module_deps.sh tycho 1.4 30
```

## Generate Build Order Graph

Generate a build graph from the given module definition, and optionally show it in EOG.

E.g.:

```
$ ./gen_build_order_graph.py ../tycho/tycho.yaml
$ ./gen_build_order_graph.py ../eclipse/eclipse.yaml --show
```

## Mock Build a Module

Build all RPMs from a module up to, and including, the given rank.

E.g.:

```
$ ./mock_build.sh 20
