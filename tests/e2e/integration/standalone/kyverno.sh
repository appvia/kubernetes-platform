# Description: used to check if kyverno is installed and configured correctly

load ../../lib/helper

setup() {
  [[ ! -f ${BATS_PARENT_TMPNAME}.skip ]] || skip "skip remaining tests"
}

teardown() {
  [[ -n $BATS_TEST_COMPLETED   ]] || touch "${BATS_PARENT_TMPNAME}.skip"
}

@test "We should have a Kyverno application" {
  runit "kubectl get application system-kyverno-dev -n argocd"
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

@test "We should have running deployments in the kyverno-system namespace" {
  kubectl "wait --for=condition=available --timeout=120s deployment/kyverno-admission-controller -n kyverno-system"
  kubectl "wait --for=condition=available --timeout=120s deployment/kyverno-background-controller -n kyverno-system"
  kubectl "wait --for=condition=available --timeout=120s deployment/kyverno-cleanup-controller -n kyverno-system"
  kubectl "wait --for=condition=available --timeout=120s deployment/kyverno-reports-controller -n kyverno-system"
}

@test "We should have the kyverno crds" {
  kubectl "get crd clusterpolicies.kyverno.io"
  kubectl "get crd policies.kyverno.io"
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

@test "We should have a Kyverno policies application" {
  kubectl "get application system-kyverno-policies-dev -n argocd"
}

@test "We should be able to force a resync of the kyverno application" {
  OPTIONS="argocd.argoproj.io/sync-options=Force=true,Replace=true argocd.argoproj.io/refresh=hard"

  kubectl "-n argocd annotate application system-kyverno-policies-dev ${OPTIONS} --overwrite"
}

@test "We should have a deny-default-namespace policy" {
  kubectl "get clusterpolicy deny-default-namespace"
}

@test "We should be able to force again a resync of the kyverno application" {
  OPTIONS="argocd.argoproj.io/sync-options=Force=true,Replace=true argocd.argoproj.io/refresh=hard"

  kubectl "-n argocd annotate application system-kyverno-policies-dev ${OPTIONS} --overwrite"
}

@test "We should not be permitted to run anything in the default namespace" {
  # Ensure the Kyverno admission controller and webhook service have ready endpoints
  # before checking enforcement. This reduces long convergence waits in e2e.
  kubectl "wait --for=condition=available --timeout=120s deployment/kyverno-admission-controller -n kyverno-system"
  kubectl "get endpoints kyverno-svc -n kyverno-system -o jsonpath='{.subsets[*].addresses[*].ip}' | grep -q ."
  kubectl "-n default run console --image=busybox:1.28.3 2>&1 | grep deny-default-namespace"
}

@test "We should not be permitted to use an image latest" {
  kubectl "-n default run console --image=busybox:latest 2>&1 | grep deny-latest-image"
}
