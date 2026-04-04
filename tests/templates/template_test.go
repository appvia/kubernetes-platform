package templates_test

import (
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	yamlv3 "gopkg.in/yaml.v3"
)

// Representative merged-generator parameters (git file + cluster matrix shape) per ApplicationSet.
// Edit here when templates require new keys; patch bodies are regenerated via make generate-template-fixtures.
const (
	paramsSystemHelm = `
{
  "feature": "cert_manager",
  "repository": "https://charts.jetstack.io",
  "chart": "cert-manager",
  "namespace": "cert-manager",
  "version": "v1.20.1",
  "repository_path": "",
  "sync": {
    "phase": "primary",
    "wave": "10"
  },
  "server": "https://kubernetes.default.svc",
  "metadata": {
    "labels": {
      "cluster_name": "dev",
      "environment": "release",
      "cloud_vendor": "aws"
    },
    "annotations": {
      "platform_repository": "https://github.com/appvia/kubernetes-platform.git",
      "platform_revision": "main",
      "tenant_repository": "https://github.com/appvia/kubernetes-platform.git",
      "tenant_revision": "main",
      "tenant_path": "release/standalone"
    }
  }
}
`

	paramsSystemKustomize = `
{
  "server": "https://kubernetes.default.svc",
  "sync": {
    "phase": "secondary",
    "wave": "15"
  },
  "metadata": {
    "labels": {
      "cluster_name": "dev",
      "environment": "release",
      "cloud_vendor": "aws"
    },
    "annotations": {
      "platform_repository": "https://github.com/appvia/kubernetes-platform.git",
      "platform_revision": "main",
      "tenant_repository": "https://github.com/appvia/kubernetes-platform.git",
      "tenant_revision": "main",
      "tenant_path": "release/standalone"
    }
  },
  "path": {
    "basenameNormalized": "cert-manager",
    "path": "addons/kustomize/oss/cert-manager",
    "segments": [
      "addons",
      "kustomize",
      "oss",
      "cert-manager"
    ]
  },
  "kustomize": {
    "feature": "cert_manager",
    "path": "base",
    "commonLabels": {
      "addon": "cert-manager"
    },
    "commonAnnotations": {},
    "patches": [
      {
        "target": {
          "kind": "ClusterIssuer",
          "name": "selfsigned-issuer"
        },
        "patch": [
          {
            "op": "add",
            "path": "/metadata/labels/cluster_name",
            "key": ".metadata.labels.cluster_name",
            "prefix": "cert-manager-"
          }
        ]
      }
    ]
  },
  "namespace": {
    "name": "cert-manager-system"
  }
}
`

	paramsTenantAppsHelm = `
{
  "server": "https://kubernetes.default.svc",
  "sync": {
    "phase": "secondary"
  },
  "metadata": {
    "labels": {
      "cluster_name": "dev",
      "environment": "release"
    },
    "annotations": {
      "platform_repository": "https://github.com/appvia/kubernetes-platform.git",
      "platform_revision": "main",
      "tenant_repository": "https://github.com/appvia/kubernetes-platform.git",
      "tenant_revision": "main",
      "tenant_path": "release/standalone",
      "tenant": "tenant"
    }
  },
  "path": {
    "basenameNormalized": "dev",
    "path": "release/standalone/workloads/applications/helm-app",
    "segments": [
      "release",
      "standalone",
      "workloads",
      "applications",
      "helm-app"
    ]
  },
  "helm": {
    "repository": "https://helm.github.io/examples",
    "version": "0.1.0",
    "chart": "hello-world",
    "path": ""
  }
}
`

	paramsTenantAppsKustomize = `
{
  "server": "https://kubernetes.default.svc",
  "sync": {
    "phase": "secondary"
  },
  "metadata": {
    "labels": {
      "cluster_name": "dev",
      "environment": "release"
    },
    "annotations": {
      "platform_repository": "https://github.com/appvia/kubernetes-platform.git",
      "platform_revision": "main",
      "tenant_repository": "https://github.com/appvia/kubernetes-platform.git",
      "tenant_revision": "main",
      "tenant_path": "release/standalone",
      "tenant": "tenant"
    }
  },
  "path": {
    "basenameNormalized": "dev",
    "path": "release/standalone/workloads/applications/kustomize-app",
    "segments": [
      "release",
      "standalone",
      "workloads",
      "applications",
      "kustomize-app"
    ]
  },
  "kustomize": {
    "path": "base"
  }
}
`

	paramsTenantSystemHelm = `
{
  "server": "https://kubernetes.default.svc",
  "sync": {
    "phase": "secondary"
  },
  "metadata": {
    "labels": {
      "cluster_name": "dev",
      "environment": "release"
    },
    "annotations": {
      "platform_repository": "https://github.com/appvia/kubernetes-platform.git",
      "platform_revision": "main",
      "tenant_repository": "https://github.com/appvia/kubernetes-platform.git",
      "tenant_revision": "main",
      "tenant_path": "release/standalone",
      "tenant": "tenant"
    }
  },
  "path": {
    "basenameNormalized": "dev",
    "path": "release/standalone/workloads/system/ingress-system",
    "segments": [
      "release",
      "standalone",
      "workloads",
      "system",
      "ingress-system"
    ]
  },
  "helm": {
    "repository": "https://helm.github.io/examples",
    "version": "0.1.0",
    "chart": "hello-world",
    "path": ""
  },
  "namespace": {
    "pod_security": "baseline"
  }
}
`

	paramsTenantSystemKustomize = `
{
  "server": "https://kubernetes.default.svc",
  "sync": {
    "phase": "secondary"
  },
  "metadata": {
    "labels": {
      "cluster_name": "dev",
      "environment": "release"
    },
    "annotations": {
      "platform_repository": "https://github.com/appvia/kubernetes-platform.git",
      "platform_revision": "main",
      "tenant_repository": "https://github.com/appvia/kubernetes-platform.git",
      "tenant_revision": "main",
      "tenant_path": "release/standalone",
      "tenant": "tenant"
    }
  },
  "path": {
    "basenameNormalized": "dev",
    "path": "release/standalone/workloads/system/ingress-system",
    "segments": [
      "release",
      "standalone",
      "workloads",
      "system",
      "ingress-system"
    ]
  },
  "kustomize": {
    "feature": "ingress",
    "path": "base",
    "revision": "main"
  },
  "namespace": {
    "name": "ingress-system",
    "pod_security": "baseline"
  }
}
`
)

func assertRenderedPatchIsValidYAML(patch, paramsJSON string) {
	params, err := paramsFromEmbeddedJSON(paramsJSON)
	Expect(err).NotTo(HaveOccurred())

	out, err := RenderTemplatePatch(patch, params)
	Expect(err).NotTo(HaveOccurred(), "templatePatch render failed")

	trimmed := strings.TrimSpace(out)
	Expect(trimmed).NotTo(BeEmpty(), "rendered output is empty")

	var doc map[string]any
	Expect(yamlv3.Unmarshal([]byte(trimmed), &doc)).To(Succeed(), "rendered output must be valid YAML")
	Expect(doc).NotTo(BeEmpty(), "rendered YAML should decode to a non-empty document")
}

var _ = Describe("ApplicationSet templatePatch", func() {
	Context("apps/system", func() {
		When("system-helm ApplicationSet", func() {
			It("renders without error and produces valid YAML", func() {
				assertRenderedPatchIsValidYAML(patchSystemHelm, paramsSystemHelm)
			})
		})

		When("system-kustomize ApplicationSet", func() {
			It("renders without error and produces valid YAML", func() {
				assertRenderedPatchIsValidYAML(patchSystemKustomize, paramsSystemKustomize)
			})
		})
	})

	Context("apps/tenant", func() {
		When("apps-helm ApplicationSet", func() {
			It("renders without error and produces valid YAML", func() {
				assertRenderedPatchIsValidYAML(patchTenantAppsHelm, paramsTenantAppsHelm)
			})
		})

		When("apps-kustomize ApplicationSet", func() {
			It("renders without error and produces valid YAML", func() {
				assertRenderedPatchIsValidYAML(patchTenantAppsKustomize, paramsTenantAppsKustomize)
			})
		})

		When("system-helm ApplicationSet", func() {
			It("renders without error and produces valid YAML", func() {
				assertRenderedPatchIsValidYAML(patchTenantSystemHelm, paramsTenantSystemHelm)
			})
		})

		When("system-kustomize ApplicationSet", func() {
			It("renders without error and produces valid YAML", func() {
				assertRenderedPatchIsValidYAML(patchTenantSystemKustomize, paramsTenantSystemKustomize)
			})
		})
	})
})
