#!/usr/bin/env bash
PDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export PATH="$PATH:$PDIR"
t_coffee "$@"
