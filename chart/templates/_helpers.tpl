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
Generate the public base URL used by ingress-facing components.
*/}}
{{- define "studiomcp.publicBaseUrl" -}}
{{- if .Values.global.publicBaseUrl -}}
{{- .Values.global.publicBaseUrl -}}
{{- else if and .Values.ingress.enabled (gt (len .Values.ingress.hosts) 0) (ne (default "" (index .Values.ingress.hosts 0).host) "") -}}
{{- if .Values.global.tls.enabled -}}https{{- else -}}http{{- end -}}://{{ (index .Values.ingress.hosts 0).host }}
{{- else -}}
http://{{ include "studiomcp.fullname" . }}
{{- end -}}
{{- end -}}

{{/*
Generate the public object-storage endpoint used for presigned URLs.
*/}}
{{- define "studiomcp.objectStoragePublicEndpoint" -}}
{{- if .Values.global.objectStorage.publicEndpoint -}}
{{- .Values.global.objectStorage.publicEndpoint -}}
{{- else -}}
http://{{ .Release.Name }}-minio:9000
{{- end -}}
{{- end -}}

{{/*
Generate the internal Keycloak issuer.
NOTE: The Bitnami Keycloak chart exposes the service on port 80 (not the container's httpPort).
*/}}
{{- define "studiomcp.keycloakInternalIssuer" -}}
http://{{ include "studiomcp.fullname" . }}-keycloak:80/kc/realms/{{ .Values.keycloak.realm }}
{{- end -}}

{{/*
Generate the public Keycloak issuer.
*/}}
{{- define "studiomcp.keycloakPublicIssuer" -}}
{{ include "studiomcp.publicBaseUrl" . }}/kc/realms/{{ .Values.keycloak.realm }}
{{- end -}}

{{/*
Generate Keycloak JWKS URI
*/}}
{{- define "studiomcp.jwksUri" -}}
{{- if .Values.keycloak.enabled -}}
{{ include "studiomcp.keycloakInternalIssuer" . }}/protocol/openid-connect/certs
{{- end -}}
{{- end -}}

{{/*
Generate comma-separated list of additional Keycloak issuers.
For Kind/local dev, includes both the in-cluster issuer and host.docker.internal issuer.
*/}}
{{- define "studiomcp.keycloakAdditionalIssuers" -}}
{{- $issuers := list -}}
{{- $issuers = append $issuers (include "studiomcp.keycloakInternalIssuer" .) -}}
{{- if .Values.auth.additionalIssuers -}}
{{- range .Values.auth.additionalIssuers -}}
{{- $issuers = append $issuers . -}}
{{- end -}}
{{- end -}}
{{- join "," $issuers -}}
{{- end -}}
