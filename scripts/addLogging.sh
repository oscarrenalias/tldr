#!/bin/bash
source $(dirname ${BASH_SOURCE[0]})/docker-functions.sh
source $(dirname ${BASH_SOURCE[0]})/nodeNames.sh

if isAWS; then
  REGISTRY=$(docker-machine inspect --format='{{.Driver.PrivateIPAddress}}' $REGISTRY_MACHINE_NAME):5000
  ELASTICSEARCH=http://$(docker-machine inspect --format '{{.Driver.PrivateIPAddress}}' $INFRA_MACHINE_NAME):9200
  LOGSTASH=syslog://$(docker-machine inspect --format '{{.Driver.PrivateIPAddress}}' $INFRA_MACHINE_NAME):5000
  SWARM_MEMBERS=$(docker-machine ls | grep 'swarm-aws-.' | awk '{print $1}' | xargs)
  KIBANA=http://$(docker-machine ip $INFRA_MACHINE_NAME):5601
else
  REGISTRY=$(docker-machine ip $REGISTRY_MACHINE_NAME):5000
  ELASTICSEARCH=http://$(docker-machine ip $INFRA_MACHINE_NAME):9200
  LOGSTASH=syslog://$(docker-machine ip $INFRA_MACHINE_NAME):5000
  SWARM_MEMBERS=$(docker-machine ls | grep 'swarm-.[ ]' | awk '{print $1}' | xargs)
  KIBANA=http://$(docker-machine ip $INFRA_MACHINE_NAME):5601
fi

eval $(docker-machine env $INFRA_MACHINE_NAME)

if ! docker inspect elasticsearch &> /dev/null; then
  print "Starting ElasticSearch"
  docker run -d --name elasticsearch -h elasticsearch -p 9300:9300 -p 9200:9200 $REGISTRY/tldr/elasticsearch
else
  print "ElasticSearch container already running\e[33m***\e[0m\n"
fi

if ! docker inspect logstash &> /dev/null; then
  print "Starting Logstash"
  docker run -d --name logstash -h logstash -p 5000:5000/udp -p 5000:5000 --link elasticsearch $REGISTRY/tldr/logstash
else
  print "Logstash container already running\e[33m***\e[0m\n"
fi

if ! docker inspect kibana &> /dev/null; then
  print "Starting Kibana"
  docker run -d --name kibana -h kibana -p 5601:5601 --link elasticsearch $REGISTRY/tldr/kibana
else
  print "Kibana container already running\e[33m***\e[0m\n"
fi

print "Servers in the swarm: $SWARM_MEMBERS"
for server in $SWARM_MEMBERS; do
  if ! docker $(docker-machine config $server) inspect logspout &> /dev/null; then
    print "Starting logspout on $server"
    docker $(docker-machine config $server) run -d \
      --name $server-logspout \
      -h logspout \
      -p 8100:8000 \
      -v "//var/run/docker.sock:/tmp/docker.sock" \
      --restart=always \
      $REGISTRY/tldr/logspout $LOGSTASH
  else
    print "Logspout already running on $server"
  fi
done
print "Logging system started, Kibana is available at \e[31m$KIBANA"
