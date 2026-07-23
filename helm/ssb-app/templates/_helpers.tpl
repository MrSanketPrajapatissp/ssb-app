{{/*
_helpers.tpl — Shared template helpers for ssb-app Helm chart.
These follow the same pattern as `helm create` generated templates.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "ssb-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncate at 63 chars because some Kubernetes name fields have a limit.
*/}}
{{- define "ssb-app.fullname" -}}
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
Create chart label, used in selector and metadata labels.
*/}}
{{- define "ssb-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to all resources.
Includes recommended Kubernetes well-known labels.
*/}}
{{- define "ssb-app.labels" -}}
helm.sh/chart: {{ include "ssb-app.chart" . }}
{{ include "ssb-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ssb-digital-platform
{{- end }}

{{/*
Selector labels — used in Deployment selector and Service selector.
Must be stable across upgrades; do not add volatile labels here.
*/}}
{{- define "ssb-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ssb-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "ssb-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ssb-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference — combines repository and tag.
Used in Deployment container spec.
*/}}
{{- define "ssb-app.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}
