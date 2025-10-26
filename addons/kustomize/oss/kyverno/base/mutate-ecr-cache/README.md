# ECR Pull-Through Cache Mutation Policy

This Kyverno policy automatically rewrites container images to use an AWS ECR Docker Hub pull-through cache, redirecting pulls through your ECR cache instead of public registries.

## Purpose

When deployed, this policy:

1. Intercepts container image references in Pods, Deployments, StatefulSets, DaemonSets, Jobs, and CronJobs
2. **Excludes Kubernetes system namespaces**: `kube-system`, `kube-public`, and `kube-node-lease`
3. Processes both `containers` and `initContainers` (initialization containers)
4. Checks if the image matches configured patterns (e.g., `library/nginx:1.25`)
5. Rewrites the image to use your ECR cache prefix
6. Avoids re-writing images that already use ECR

## Image Rewriting

The policy transforms images like:

- `library/nginx:1.25` → `${ECR_CACHE_REGISTRY}/dockerhub/library/nginx:1.25`
- `docker.io/library/redis:7` → `${ECR_CACHE_REGISTRY}/dockerhub/library/redis:7`

## Configuration

### Using with Kustomize (Recommended)

This policy is designed to be consumed via Kustomize with easy patching for:

1. **ECR Registry**: Replace the placeholder with your ECR registry URL
2. **Image Patterns**: Add or modify which images get mutated

#### Step 1: Create a Kustomize Overlay

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../../base  # or appropriate path to base kyverno policies

patches:
  # Patch 1: Replace ECR_REGISTRY_PLACEHOLDER with your registry
  - target:
      kind: ClusterPolicy
      name: mutate-ecr-cache
    patch: |-
      - op: replace
        path: /spec/rules/0/mutate/foreach/0/patchStrategicMerge/spec/containers/0/image
        value: 123456789012.dkr.ecr.us-east-1.amazonaws.com/dockerhub.{{ element.image | regex_replace('^docker\\.io/', '') }}
      
      - op: replace
        path: /spec/rules/0/mutate/foreach/1/patchStrategicMerge/spec/initContainers/0/image
        value: 123456789012.dkr.ecr.us-east-1.amazonaws.com/dockerhub.{{ element.image | regex_replace('^docker\\.io/', '') }}
  
  # Patch 2: Add custom image patterns
  - target:
      kind: ClusterPolicy
      name: mutate-ecr-cache
    patch: |-
      - op: add
        path: /spec/rules/0/mutate/foreach/0/preconditions/any/-
        value:
          key: "{{ element.image }}"
          operator: Contains
          value: "redis"
      
      - op: add
        path: /spec/rules/0/mutate/foreach/0/preconditions/any/-
        value:
          key: "{{ element.image }}"
          operator: Contains
          value: "postgres"
      
      - op: add
        path: /spec/rules/0/mutate/foreach/1/preconditions/any/-
        value:
          key: "{{ element.image }}"
          operator: Contains
          value: "redis"
      
      - op: add
        path: /spec/rules/0/mutate/foreach/1/preconditions/any/-
        value:
          key: "{{ element.image }}"
          operator: Contains
          value: "postgres"
```

#### Step 2: Customize Your Image Patterns

Edit the patch to add patterns that match your images:

```yaml
patches:
  - target:
      kind: ClusterPolicy
      name: mutate-ecr-cache
    patch: |-
      # Add pattern to match nginx images
      - op: add
        path: /spec/rules/0/mutate/foreach/0/preconditions/any/-
        value:
          key: "{{ element.image }}"
          operator: Contains
          value: "nginx"
      
      # Add pattern to match any docker.io image
      - op: add
        path: /spec/rules/0/mutate/foreach/0/preconditions/any/-
        value:
          key: "{{ element.image }}"
          operator: AnyIn
          value:
            - "docker.io/**"
      
      # Add specific image name
      - op: add
        path: /spec/rules/0/mutate/foreach/0/preconditions/any/-
        value:
          key: "{{ element.image }}"
          operator: Contains
          value: "alpine"
```

### Alternative: Direct Edit

If not using kustomize, edit `policy.yaml` and replace:

- `ECR_REGISTRY_PLACEHOLDER` with your actual ECR registry URL
- Add more conditions in the `any:` blocks under both containers and initContainers sections

**Note**: ECR registry format should be: `${AWS_ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com`

### Supported Operators for Image Matching

- `Contains`: Matches if image contains substring
- `Equals`: Exact match
- `NotContains`: Excludes images containing substring
- `AnyIn`: Match against a list of values

### Excluding Additional Namespaces

By default, the policy excludes `kube-system`, `kube-public`, and `kube-node-lease`. To exclude additional namespaces, use a kustomize patch:

```yaml
patches:
  - target:
      kind: ClusterPolicy
      name: mutate-ecr-cache
    patch: |-
      - op: add
        path: /spec/rules/0/exclude/resources/namespaces/-
        value: your-namespace-to-exclude
      - op: add
        path: /spec/rules/0/exclude/resources/namespaces/-
        value: another-namespace
```

## Prerequisites

1. **ECR Pull-Through Cache Repository**: Create an ECR private registry with a pull-through cache configured for `public.ecr.aws` or Docker Hub
2. **AWS Authentication**: Your cluster must have AWS IAM roles/credentials configured to access ECR
3. **Kyverno Installed**: This policy runs as a Kyverno ClusterPolicy

## ECR Pull-Through Cache Setup

To create an ECR pull-through cache:

```bash
# Create the ECR repository with pull-through cache enabled
aws ecr create-repository \
  --repository-name dockerhub \
  --image-scanning-configuration scanOnPush=true \
  --image-tag-mutability MUTABLE \
  --region us-east-1
```

Note: ECR pull-through cache is only available in certain regions. Check AWS documentation for availability.

## Example

### Regular Containers

Before the policy:

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: nginx
    image: library/nginx:1.25
```

After the policy mutates it:

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: nginx
    image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/dockerhub/library/nginx:1.25
```

### Init Containers

The policy also mutates `initContainers`:

```yaml
apiVersion: v1
kind: Pod
spec:
  initContainers:
  - name: setup
    image: library/busybox:latest
  containers:
  - name: app
    image: library/nginx:1.25
```

Will be mutated to:

```yaml
apiVersion: v1
kind: Pod
spec:
  initContainers:
  - name: setup
    image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/dockerhub/library/busybox:latest
  containers:
  - name: app
    image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/dockerhub/library/nginx:1.25
```

## Security Benefits

- **Centralized Logging**: All image pulls are logged in CloudTrail
- **Vulnerability Scanning**: Automatically scan images with ECR scanning
- **Access Control**: Control who can pull images via IAM
- **Network Security**: Pulls go through your VPC endpoints instead of public internet
- **Rate Limiting**: Avoid Docker Hub rate limits
