load ../../lib/helper

setup() {
  [[ ! -f ${BATS_PARENT_TMPNAME}.skip ]] || skip "skip remaining tests"
}

teardown() {
  [[ -n $BATS_TEST_COMPLETED   ]] || touch "${BATS_PARENT_TMPNAME}.skip"
}

@test "We should have argocd namespace" {
  kubectl "get namespace argocd"
}

@test "We should have argocd projects for the system" {
  kubectl_argocd "get appprojects.argoproj.io system"
}

@test "We should have argocd project setup fo tenant applications" {
  kubectl_argocd "get appprojects.argoproj.io tenant-apps"
}

@test "We should have argocd project setup fo tenant system applications" {
  kubectl_argocd "get appprojects.argoproj.io tenant-system"
}

