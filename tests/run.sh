#!/bin/bash

set -e

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

docker_exec() {
    docker-compose exec "${@}"
}

run_action() {
    docker_exec "${1}" make "${@:2}" -f /usr/local/bin/actions.mk
}

docker-compose up -d

run_action ruby check-ready max_try=20 wait_seconds=5 delay_seconds=60

docker_exec ruby tests.sh

docker-compose down
