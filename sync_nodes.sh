#!/bin/bash 

nodes="node01 node02 node03 node51 node52 node53"

for node in $nodes; do
    echo "refreshing script"
    scp sync_all.sh root@$node:.
    echo "creating user accounts on $node"
    ssh $node "./sync_all 10.0.0.254:/etc"
done
