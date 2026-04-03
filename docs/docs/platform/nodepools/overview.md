# Node pools

## What they are

**Node pools** (in the Karpenter sense) are Declarative sets of rules that tell **Karpenter** how to provision worker nodes: which instance sizes, architectures, capacity types (for example Spot versus on-demand), and which **NodeClass** supplies networking and AMI settings. Each pool is a Kubernetes **`NodePool`** object; the controller creates and destroys **nodes** to match pending pods within those constraints.

In this platform, optional **Karpenter node pool** manifests are delivered as a small Helm chart so defaults and tenant-specific overrides stay in Git, alongside cluster definitions.

---

## Next steps

For feature flags, value file layout (`config/karpenter_nodepools/…`), merge order, and examples (Spot-only, ARM64, and so on), see **[Karpenter node pool configuration](karpenter.md)**.
