#!/bin/bash

source $(dirname ${BASH_SOURCE[0]})/docker-functions.sh
source $(dirname ${BASH_SOURCE[0]})/nodeNames.sh

# Creates infra node if needed
if isAWS; then
  # Check if the node already exists
  REGISTRY=$(docker-machine inspect --format='{{.Driver.PrivateIPAddress}}' $REGISTRY_MACHINE_NAME):5000
  if ! docker-machine inspect $INFRA_MACHINE_NAME &> /dev/null; then
    print "Creating infra node into AWS"
    # we use larger isntance type to ensure that we have enough capacity to run Prometheus
    docker-machine create -d amazonec2 \
      --amazonec2-security-group $TLDR_INFRA_NODE_SG_NAME \
      --amazonec2-instance-type t2.large \
      --engine-insecure-registry=$REGISTRY $INFRA_MACHINE_NAME
  fi
  eval $(docker-machine env $INFRA_MACHINE_NAME)
else
  REGISTRY=$(docker-machine ip $REGISTRY_MACHINE_NAME):5000
  if ! docker-machine inspect $INFRA_MACHINE_NAME &> /dev/null; then
    print "Creating infra node locally"
    docker-machine create -d virtualbox --engine-insecure-registry=$REGISTRY $INFRA_MACHINE_NAME
  fi
  eval $(docker-machine env $INFRA_MACHINE_NAME)
fi
# Start Consul if not already running
if ! docker inspect consul &> /dev/null; then
  print "Starting consul container"
  docker run -d -p 53:53 -p 53:53/udp -p 8500:8500 --name consul $REGISTRY/consul -server -bootstrap-expect 1
else
  print "Consul already running"
fi

# Start registrator
docker run -d --dns 172.17.0.1 -v /var/run/docker.sock:/tmp/docker.sock -h registrator --name registrator $REGISTRY/registrator -internal consul://consul.service.consul:8500
