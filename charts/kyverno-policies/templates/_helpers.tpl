{{/*
Expand the name of the chart.
*/}}
{{- define "kyverno-policies.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "kyverno-policies.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kyverno-policies.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Return combined excluded namespaces (always + additional + policy-specific)
Used by all policies to exclude system namespaces and user-configured namespaces.
*/}}
{{- define "kyverno-policies.excludedNamespaces" -}}
{{- $always := .Values.globalExclusions.always | default list }}
{{- $additional := .Values.globalExclusions.additional | default list }}
{{- $combined := concat $always $additional | uniq }}
{{- range $combined | sortAlpha }}
- {{ . }}
{{- end }}
{{- end }}

{{/*
Return combined excluded namespaces including policy-specific exclusions.
Args: policy-specific exclusions list
*/}}
{{- define "kyverno-policies.excludedNamespacesWithPolicy" -}}
{{- $policyExclusions := . }}
{{- $always := .Values.globalExclusions.always | default list }}
{{- $additional := .Values.globalExclusions.additional | default list }}
{{- $combined := concat $always $additional $policyExclusions | uniq }}
{{- range $combined | sortAlpha }}
- {{ . }}
{{- end }}
{{- end }}

{{/*
Simple mode registry restriction policy
Generates a single rule that applies to all namespaces (minus exclusions)
*/}}
{{- define "kyverno-policies.restrictImageRegistriesSimple" -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registries
  annotations:
    policies.kyverno.io/title: Restrict Image Registries
    policies.kyverno.io/category: Security
    policies.kyverno.io/severity: high
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      This policy restricts container images to allowed registries only.
      Images not matching the allowed registry list will be rejected.
spec:
  validationFailureAction: {{ .Values.policies.restrictImageRegistries.validationFailureAction }}
  background: {{ .Values.policies.restrictImageRegistries.background }}
  rules:
    - name: validate-registries
      skipBackgroundRequests: true
      match:
        any:
          - resources:
              kinds:
                - Pod
      exclude:
        resources:
          namespaces:
            {{- $policyExclude := .Values.policies.restrictImageRegistries.excludeNamespaces | default list }}
            {{- $always := .Values.globalExclusions.always | default list }}
            {{- $additional := .Values.globalExclusions.additional | default list }}
            {{- $combined := concat $always $additional $policyExclude | uniq | sortAlpha }}
            {{- range $combined }}
            - {{ . }}
            {{- end }}
      validate:
        allowExistingViolations: true
        message: "Image registry not allowed. Allowed registries are: {{ .Values.policies.restrictImageRegistries.allowedRegistries | join ", " }}"
        pattern:
          spec:
            containers:
              - image: "{{ join "|" .Values.policies.restrictImageRegistries.allowedRegistries }}/*"
{{- end }}

{{/*
Complex mode registry restriction policy
Generates per-registry rules with namespace-specific allow lists
*/}}
{{- define "kyverno-policies.restrictImageRegistriesComplex" -}}
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: restrict-image-registries
  annotations:
    policies.kyverno.io/title: Restrict Image Registries
    policies.kyverno.io/category: Security
    policies.kyverno.io/severity: high
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      This policy restricts container images to allowed registries with per-registry namespace rules.
spec:
  validationFailureAction: {{ .Values.policies.restrictImageRegistries.validationFailureAction }}
  background: {{ .Values.policies.restrictImageRegistries.background }}
  rules:
    {{- $globalExclude := .Values.globalExclusions.always | default list }}
    {{- $additionalExclude := .Values.globalExclusions.additional | default list }}
    {{- $policyExclude := .Values.policies.restrictImageRegistries.excludeNamespaces | default list }}
    {{- $allExcluded := concat $globalExclude $additionalExclude $policyExclude | uniq }}
    {{- range $registry := .Values.policies.restrictImageRegistries.registries }}
    - name: validate-registry-{{ $registry.name | replace "." "-" | replace "/" "-" }}
      skipBackgroundRequests: true
      match:
        any:
          - resources:
              kinds:
                - Pod
              {{- if $registry.allowedNamespaces }}
              namespaces:
                {{- range $registry.allowedNamespaces | sortAlpha }}
                - {{ . }}
                {{- end }}
              {{- end }}
      exclude:
        resources:
          namespaces:
            {{- range $allExcluded | sortAlpha }}
            - {{ . }}
            {{- end }}
      validate:
        allowExistingViolations: true
        message: "Image must come from {{ $registry.name }} registry"
        pattern:
          spec:
            containers:
              - image: "{{ $registry.name }}/*"
    {{- end }}
{{- end }}
