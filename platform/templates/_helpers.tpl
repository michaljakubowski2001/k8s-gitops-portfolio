{{- define "platform.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  retry:
    limit: 10
    backoff:
      duration: 10s
      factor: 2
      maxDuration: 3m
  {{- with .options }}
  syncOptions:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .labels }}
  managedNamespaceMetadata:
    labels:
      {{- toYaml . | nindent 6 }}
  {{- end }}
{{- end -}}
