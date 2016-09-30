#!/bin/bash

NODENUM=$1
PORT=$2
CMD=$3
ARG1=$4
ARG2=$5

stack exec dkvs-client -- $NODENUM $PORT $CMD $ARG1 $ARG2 2>/dev/null
