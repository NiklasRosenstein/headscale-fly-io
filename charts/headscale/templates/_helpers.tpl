{{/*
Expand the name of the chart.
*/}}
{{- define "headscale.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "headscale.fullname" -}}
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
{{- define "headscale.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "headscale.labels" -}}
helm.sh/chart: {{ include "headscale.chart" . }}
{{ include "headscale.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "headscale.selectorLabels" -}}
app.kubernetes.io/name: {{ include "headscale.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "headscale.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "headscale.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the appropriate apiVersion for ingress
*/}}
{{- define "headscale.ingress.apiVersion" -}}
{{- if semverCompare ">=1.19-0" .Capabilities.KubeVersion.GitVersion -}}
networking.k8s.io/v1
{{- else if semverCompare ">=1.14-0" .Capabilities.KubeVersion.GitVersion -}}
networking.k8s.io/v1beta1
{{- else -}}
extensions/v1beta1
{{- end }}
{{- end }}

{{/*
Return if ingress is stable
*/}}
{{- define "headscale.ingress.isStable" -}}
{{- semverCompare ">=1.19-0" .Capabilities.KubeVersion.GitVersion -}}
{{- end }}

{{/*
Return if ingressClassName is supported
*/}}
{{- define "headscale.ingress.supportsIngressClassName" -}}
{{- semverCompare ">=1.18-0" .Capabilities.KubeVersion.GitVersion -}}
{{- end }}

{{/*
Return the domain name for Headscale
*/}}
{{- define "headscale.domainName" -}}
{{- if .Values.headscale.domainName }}
{{- .Values.headscale.domainName }}
{{- else if and .Values.ingress.enabled (gt (len .Values.ingress.hosts) 0) }}
{{- (index .Values.ingress.hosts 0).host }}
{{- else if and .Values.gatewayApi.enabled (gt (len .Values.gatewayApi.httpRoute.hostnames) 0) }}
{{- index .Values.gatewayApi.httpRoute.hostnames 0 }}
{{- else }}
{{- printf "%s.local" (include "headscale.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the secret name for credentials
*/}}
{{- define "headscale.secretName" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecret }}
{{- else }}
{{- include "headscale.fullname" . }}
{{- end }}
{{- end }}

{{/*
Return the secret name for Litestream AWS credentials
*/}}
{{- define "headscale.litestream.awsSecretName" -}}
{{- if .Values.litestream.aws.existingSecret }}
{{- .Values.litestream.aws.existingSecret }}
{{- else }}
{{- printf "%s-litestream" (include "headscale.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the secret name for OIDC
*/}}
{{- define "headscale.oidc.secretName" -}}
{{- if .Values.headscale.oidc.existingSecret }}
{{- .Values.headscale.oidc.existingSecret }}
{{- else }}
{{- printf "%s-oidc" (include "headscale.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the PVC name
*/}}
{{- define "headscale.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "headscale.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Renders a value that contains template.
Usage:
{{ include "headscale.tplValue" (dict "value" .Values.path.to.value "context" $) }}
*/}}
{{- define "headscale.tplValue" -}}
    {{- if typeIs "string" .value }}
        {{- tpl .value .context }}
    {{- else }}
        {{- tpl (.value | toYaml) .context }}
    {{- end }}
{{- end -}}

{{/*
Return the base URL for Headplane
*/}}
{{- define "headscale.headplane.baseUrl" -}}
{{- if .Values.headplane.baseUrl }}
{{- .Values.headplane.baseUrl }}
{{- else }}
{{- printf "https://%s" (include "headscale.domainName" .) }}
{{- end }}
{{- end }}

{{/*
Return the secret name for Headplane OIDC
*/}}
{{- define "headscale.headplane.oidc.secretName" -}}
{{- if .Values.headplane.oidc.existingSecret }}
{{- .Values.headplane.oidc.existingSecret }}
{{- else }}
{{- printf "%s-headplane-oidc" (include "headscale.fullname" .) }}
{{- end }}
{{- end }}
