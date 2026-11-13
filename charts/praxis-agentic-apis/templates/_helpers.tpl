{{/*
PostgreSQL password Secret name. Also called from praxis-gateway.env through tpl, so it
reads only .Values.global and .Release.
*/}}
{{- define "praxis-agentic-apis.postgresSecret" -}}
{{- .Values.global.database.secretName | default (printf "%s-postgres" .Release.Name) -}}
{{- end }}

{{- define "praxis-agentic-apis.postgresLabels" -}}
app.kubernetes.io/name: postgresql
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end }}

{{- define "praxis-agentic-apis.gatewaySelector" -}}
app.kubernetes.io/name: praxis-gateway
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end }}
