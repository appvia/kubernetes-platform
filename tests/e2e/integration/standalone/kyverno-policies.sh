# Description: used to check if kyuverno-policies are installed and configured correctly

load ../../lib/helper

setup() {
  [[ ! -f ${BATS_PARENT_TMPNAME}.skip ]] || skip "skip remaining tests"
}

teardown() {
  [[ -n $BATS_TEST_COMPLETED   ]] || touch "${BATS_PARENT_TMPNAME}.skip"
}

@test "We should have a Kyverno policies application" {
  kubectl_argocd "get application system-kyverno-policies-dev"
}

@test "We should be able to override the platform default policies" {
  runit "kubectl -n argocd get application system-kyverno-policies-dev -o yaml" "grep -qF deny-eks-resources || exit 0"
}

@test "We should not have the deny-eks-resources cluster policy applied to the cluster" {
  kubectl "get clusterpolicy deny-eks-resources || true"
}

