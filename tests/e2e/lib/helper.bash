#!/usr/bin/env bash
#

# Retry a command $1 times until it succeeds. If a second command is given, it will be run on the output of the first command.
retry() {
  local attempts
  local cmd
  local subcmd

  if [ $# -gt 3 ]; then
    echo "Invalid number of arguments for retry: \"$*\" ($#)"
    exit 1
  fi

  attempts=$1
  shift
  cmd=$1
  shift
  subcmd="${1:-}"  # Get subcmd if provided, otherwise empty

  local delay=5
  local i
  local result
  local cmd_status

  for ((i = 1; i <= attempts; i++)); do
    run bash -c "$cmd"
    cmd_status=${status}
    result="${output}"

    # If subcmd is provided, run it on the output
    if [[ -n "${subcmd}" ]]; then
      run bash -c "${subcmd}" < <(echo -n "${result}")
      if [[ ${status} -eq 0 ]]; then
        echo "${output}"
        return 0
      fi
    else
      # No subcmd, just check if the original command succeeded
      if [[ ${cmd_status} -eq 0 ]]; then
        echo "${result}"
        return 0
      fi
    fi

    if [[ $i -lt $attempts ]]; then
      sleep $delay
    fi
  done

  printf "Error: command \"%s\" (subcommand: \"%s\") failed %d times\nStatus: %s\nOutput: %s\n" "${cmd}" "${subcmd}" "${attempts}" "${status}" "${result}" | sed 's/WAYFINDER_TOKEN=.* //' >&2
  false
}

runit() {
  retry 5 "$@"
}

kubectl_argocd() {
  runit "kubectl -n argocd $@"
}

kubectl() {
  runit "kubectl $@"
}
