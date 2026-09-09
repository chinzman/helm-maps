{{/*
  _helpers.tpl — Reusable template helpers for ml-api-chart
  These are not rendered directly; they're called by other templates.
*/}}

{{/* Expand the name of the chart. */}}
{{- define "ml-api-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
  Create a default fully qualified app name.
  We truncate at 63 chars because Kubernetes name fields are limited.
*/}}
{{- define "ml-api-chart.fullname" -}}
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

{{/* Create chart label (used in selectors) */}}
{{- define "ml-api-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels — applied to all resources */}}
{{- define "ml-api-chart.labels" -}}
helm.sh/chart: {{ include "ml-api-chart.chart" . }}
{{ include "ml-api-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/environment: {{ .Values.environment }}
{{- end }}

{{/* Selector labels — used in Deployment/Service matchLabels */}}
{{- define "ml-api-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ml-api-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Service account name */}}
{{- define "ml-api-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ml-api-chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Resolved image tag — falls back to Chart.AppVersion */}}
{{- define "ml-api-chart.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion }}
{{- end }}
