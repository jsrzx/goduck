#!/usr/bin/env bash

set -e

WORKDIR=ethereum

RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

function print_blue() {
  printf "${BLUE}%s${NC}\n" "$1"
}

function print_red() {
  printf "${RED}%s${NC}\n" "$1"
}

function printHelp() {
  print_blue "Usage:  "
  echo "  ethereum.sh <mode>"
  echo "    <mode> - one of 'binary', 'docker'"
  echo "      - 'binary' - bring up the ethereum with local binary geth"
  echo "      - 'docker' - clear the ethereum with geth in docker"
  echo "      - 'down' - shut down ethereum binary and docker container"
  echo "  ethereum.sh -h (print this message)"
}

function binaryUp() {
  # clean up datadir
  cd ${WORKDIR}
  rm -rf datadir
  tar xf datadir.tar.gz

  print_blue "start geth with datadir in ${WORKDIR}/datadir"
  nohup geth --datadir $HOME/.goduck/ethereum/datadir --dev --ws --rpc \
      --rpccorsdomain https://remix.ethereum.org \
      --wsaddr "0.0.0.0" --rpcaddr "0.0.0.0" --rpcport 8545 \
      --rpcapi "eth,web3,personal,net,miner,admin,debug" >/dev/null 2>&1 &
  echo $! >ethereum.pid
}

function dockerUp() {
  if [ ! "$(docker ps -q -f name=ethereum-node)" ]; then
    if [ "$(docker ps -aq -f status=exited -f name=ethereum-node)" ]; then
        # restart your container
        print_blue "restart your ethereum-node container"
        docker restart ethereum-node
    else
      print_blue "start a new ethereum-node container"
      docker run -d --name ethereum-node \
        -p 8545:8545 -p 8546:8546 -p 30303:30303 \
        meshplus/ethereum:1.0.0 \
        --datadir /root/datadir --dev --ws --rpc \
        --rpccorsdomain https://remix.ethereum.org \
        --rpcaddr "0.0.0.0" --rpcport 8545 --wsaddr "0.0.0.0" \
        --rpcapi "eth,web3,personal,net,miner,admin,debug"
    fi
  else
    print_red "ethereum-node is already running, use old container..."
  fi

}

function etherDown() {
  set +e
  if [ -a "${WORKDIR}"/ethereum.pid ]; then
    list=$(cat "${WORKDIR}"/ethereum.pid)
    for pid in $list; do
      kill "$pid"
      if [ $? -eq 0 ]; then
        echo "node pid:$pid exit"
      else
        print_red "program exit fail, try use kill -9 $pid"
      fi
    done
    rm "${WORKDIR}"/ethereum.pid
  fi

  if [ "$(docker container ls | grep -c ethereum-node)" -ge 1 ]; then
    print_blue "===> stop ethereum-node..."
    docker rm -f ethereum-node
    echo "ethereum docker container stopped"
  fi
}

MODE=$1

if [ "$MODE" == "binary" ]; then
  binaryUp
elif [ "$MODE" == "docker" ]; then
  dockerUp
elif [ "$MODE" == "down" ]; then
  etherDown
else
  printHelp
  exit 1
fi
