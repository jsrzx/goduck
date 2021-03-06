#!/usr/bin/env bash

set -e
source x.sh

CURRENT_PATH=$(pwd)
CONFIG_PATH="${CURRENT_PATH}"/bitxhub

OPT=$1
VERSION=$2
TYPE=$3
MODE=$4
N=$5
SYSTEM=$(uname -s)
BXH_PATH="${CURRENT_PATH}/bin/bitxhub_${VERSION}"

function printHelp() {
  print_blue "Usage:  "
  echo "  playground.sh <mode>"
  echo "    <OPT> - one of 'up', 'down', 'restart'"
  echo "      - 'up' - bring up the bitxhub network"
  echo "      - 'down' - clear the bitxhub network"
  echo "      - 'restart' - restart the bitxhub network"
  echo "  playground.sh -h (print this message)"
}

function binary_prepare() {
  cd "${BXH_PATH}"
  if [ ! -a "${BXH_PATH}"/bitxhub ]; then
    if [ "${SYSTEM}" == "Linux" ]; then
      tar xf bitxhub_linux-amd64_$VERSION.tar.gz
      cp ./build/* . && rm -r build
      export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:"${BXH_PATH}"/
    elif [ "${SYSTEM}" == "Darwin" ]; then
      tar xf bitxhub_macos_x86_64_$VERSION.tar.gz
      cp ./build/* . && rm -r build
      install_name_tool -change @rpath/libwasmer.dylib "${BXH_PATH}"/libwasmer.dylib "${BXH_PATH}"/bitxhub
    else
      print_red "Bitxhub does not support the current operating system"
    fi
  fi

  if [ -a "${CONFIG_PATH}"/bitxhub.pid ]; then
    print_red "Bitxhub already run in daemon processes"
    exit 1
  fi
}

function bitxhub_binary_solo() {
  binary_prepare

  cd "${CONFIG_PATH}"
  if [ ! -d nodeSolo/plugins ]; then
    mkdir nodeSolo/plugins
    cp -r "${BXH_PATH}"/solo.so nodeSolo/plugins
  fi
  print_blue "Start bitxhub solo by binary"
  nohup "${BXH_PATH}"/bitxhub --repo "${CONFIG_PATH}"/nodeSolo start >/dev/null 2>&1 &
  PID=$!
  sleep 1
  if [ -n "$(ps -p ${PID} -o pid=)" ]; then
    echo "===> Start bitxhub solo node successful"
    echo $! >>"${CONFIG_PATH}"/bitxhub.pid
  else
    print_red "===> Start bitxhub solo node fail"
  fi
}

function bitxhub_docker_solo() {
  if [[ -z "$(docker images -q meshplus/bitxhub-solo:latest 2>/dev/null)" ]]; then
    docker pull meshplus/bitxhub-solo:latest
  fi

  print_blue "Start bitxhub solo mode by docker"
  if [ "$(docker container ls -a | grep -c bitxhub_solo)" -ge 1 ]; then
    docker start bitxhub_solo
  else
    docker run -d --name bitxhub_solo \
      -p 60011:60011 -p 9091:9091 -p 53121:53121 -p 40011:40011 \
      -v "${CONFIG_PATH}"/nodeSolo/api:/root/.bitxhub/api \
      -v "${CONFIG_PATH}"/nodeSolo/bitxhub.toml:/root/.bitxhub/bitxhub.toml \
      -v "${CONFIG_PATH}"/nodeSolo/genesis.json:/root/.bitxhub/genesis.json \
      -v "${CONFIG_PATH}"/nodeSolo/network.toml:/root/.bitxhub/network.toml \
      -v "${CONFIG_PATH}"/nodeSolo/order.toml:/root/.bitxhub/order.toml \
      -v "${CONFIG_PATH}"/nodeSolo/certs:/root/.bitxhub/certs \
      meshplus/bitxhub-solo
  fi
}

function bitxhub_binary_cluster() {
  binary_prepare

  cd "${CONFIG_PATH}"
  print_blue "Start bitxhub cluster"
  for ((i = 1; i < N + 1; i = i + 1)); do
    if [ ! -d node${i}/plugins ]; then
      mkdir node${i}/plugins
      cp -r "${BXH_PATH}"/raft.so node${i}/plugins
    fi
    echo "Start bitxhub node${i}"
    nohup "${BXH_PATH}"/bitxhub --repo="${CONFIG_PATH}"/node${i} start >/dev/null 2>&1 &
    PID=$!
    sleep 1
    if [ -n "$(ps -p ${PID} -o pid=)" ]; then
      echo "===> Start bitxhub solo node successful"
      echo $! >>"${CONFIG_PATH}"/bitxhub.pid
    else
      print_red "===> Start bitxhub solo node fail"
    fi

  done
}

function bitxhub_docker_cluster() {
  if [[ -z "$(docker images -q meshplus/bitxhub:latest 2>/dev/null)" ]]; then
    docker pull meshplus/bitxhub:latest
  fi
  print_blue "Start bitxhub cluster mode by docker compose"
  docker-compose -f "${CURRENT_PATH}"/docker/docker-compose.yml up -d
}

function bitxhub_down() {
  set +e
  print_blue "===> Stop bitxhub"

  if [ -a "${CONFIG_PATH}"/bitxhub.pid ]; then
    list=$(cat "${CONFIG_PATH}"/bitxhub.pid)
    for pid in $list; do
      kill "$pid"
      if [ $? -eq 0 ]; then
        echo "node pid:$pid exit"
      else
        print_red "program exit fail, try use kill -9 $pid"
      fi
    done
    rm "${CONFIG_PATH}"/bitxhub.pid
  fi

  if [ "$(docker container ls | grep -c bitxhub_node)" -ge 1 ]; then
    docker-compose -f "${CURRENT_PATH}"/docker/docker-compose.yml stop
    echo "bitxhub docker cluster stop"
  fi

  if [ "$(docker container ls | grep -c bitxhub_solo)" -ge 1 ]; then
    docker stop bitxhub_solo
    echo "bitxhub docker solo stop"
  fi

}

function bitxhub_up() {
  case $MODE in
  "docker")
    case $TYPE in
    "solo")
      bitxhub_docker_solo
      ;;
    "cluster")
      bitxhub_docker_cluster
      ;;
    *)
      print_red "TYPE should be solo or cluster"
      exit 1
      ;;
    esac
    ;;
  "binary")
    case $TYPE in
    "solo")
      bitxhub_binary_solo
      ;;
    "cluster")
      bitxhub_binary_cluster
      ;;
    *)
      print_red "TYPE should be solo or cluster"
      exit 1
      ;;
    esac
    ;;
  *)
    print_red "MODE should be docker or binary"
    exit 1
    ;;
  esac
}

function bitxhub_clean() {
  set +e

  bitxhub_down

  print_blue "===> Clean bitxhub"

  file_list=$(ls ${CONFIG_PATH} 2>/dev/null | grep -v '^$')
  for file_name in $file_list; do
    if [ "${file_name:0:4}" == "node" ]; then
      rm -r "${CONFIG_PATH}"/"$file_name"
      echo "remove bitxhub configure $file_name"
    fi
  done

  if [ "$(docker ps -a | grep -c bitxhub_node)" -ge 1 ]; then
    docker-compose -f "${CURRENT_PATH}"/docker/docker-compose.yml rm -f
    echo "bitxhub docker cluster clean"
  fi

  if [ "$(docker ps -a | grep -c bitxhub_solo)" -ge 1 ]; then
    docker rm bitxhub_solo
    echo "bitxhub docker solo clean"
  fi
}

function bitxhub_restart() {
  bitxhub_down
  bitxhub_up
}

if [ "$OPT" == "up" ]; then
  bitxhub_up
elif [ "$OPT" == "down" ]; then
  bitxhub_down
elif [ "$OPT" == "clean" ]; then
  bitxhub_clean
elif [ "$OPT" == "restart" ]; then
  bitxhub_restart
else
  printHelp
  exit 1
fi
