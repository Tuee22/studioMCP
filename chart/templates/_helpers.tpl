{{/*
Expand the name of the chart.
*/}}
{{- define "studiomcp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "studiomcp.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "studiomcp.name" . -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "studiomcp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "studiomcp.labels" -}}
helm.sh/chart: {{ include "studiomcp.chart" . }}
{{ include "studiomcp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "studiomcp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "studiomcp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "studiomcp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "studiomcp.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Generate Redis URL
*/}}
{{- define "studiomcp.redisUrl" -}}
{{- if .Values.redis.enabled -}}
{{- if .Values.redis.password -}}
redis://:{{ .Values.redis.password }}@{{ include "studiomcp.fullname" . }}-redis:{{ .Values.redis.port }}
{{- else -}}
redis://{{ include "studiomcp.fullname" . }}-redis:{{ .Values.redis.port }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Generate Keycloak JWKS URI
*/}}
{{- define "studiomcp.jwksUri" -}}
{{- if .Values.keycloak.enabled -}}
http://{{ include "studiomcp.fullname" . }}-keycloak:{{ .Values.keycloak.httpPort }}/realms/{{ .Values.keycloak.realm }}/protocol/openid-connect/certs
{{- end -}}
{{- end -}}
