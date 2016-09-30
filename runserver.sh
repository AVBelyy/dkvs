#!/bin/bash

# kill previously running nodes
killall dkvs-server 2>/dev/null

for id in {1..7}; do
    stack exec dkvs-server -- $id 2>/dev/null &
    sleep 0.5
done

while true; do
    sleep 1
done
