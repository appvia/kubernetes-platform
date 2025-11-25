# Description: used to check if kyverno is installed and configured correctly

load ../../lib/helper

setup() {
  [[ ! -f ${BATS_PARENT_TMPNAME}.skip ]] || skip "skip remaining tests"
}

teardown() {
  [[ -n $BATS_TEST_COMPLETED   ]] || touch "${BATS_PARENT_TMPNAME}.skip"
}

@test "We should have a Kyverno application" {
  runit "kubectl get application system-kyverno-hub -n argocd"
}

@test "We should have a kyverno-system namespace" {
  kubectl "get namespace kyverno-system"
}

@test "We should have a kyverno-system deployment" {
  kubectl "get deployment kyverno-admission-controller -n kyverno-system"
  kubectl "get deployment kyverno-background-controller -n kyverno-system"
  kubectl "get deployment kyverno-cleanup-controller -n kyverno-system"
  kubectl "get deployment kyverno-reports-controller -n kyverno-system"
}

@test "We should have a kyverno-system validating webhook" {
  NAMES=(
    kyverno-cleanup-validating-webhook-cfg
    kyverno-exception-validating-webhook-cfg
    kyverno-global-context-validating-webhook-cfg
    kyverno-policy-validating-webhook-cfg
    kyverno-resource-validating-webhook-cfg
    kyverno-ttl-validating-webhook-cfg
  )
  for NAME in "${NAMES[@]}"; do
    kubectl "get validatingwebhookconfiguration ${NAME}"
  done
}