{{/* Common labels. app.kubernetes.io/* so Prometheus, Kiali etc. pick them up. */}}
{{- define "ecommerce.labels" -}}
app.kubernetes.io/part-of: {{ $.root.Release.Name }}
app.kubernetes.io/managed-by: {{ $.root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" $.root.Chart.Name $.root.Chart.Version }}
{{ include "ecommerce.selector" . }}
{{- end }}

{{- define "ecommerce.selector" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ $.root.Release.Name }}
{{- end }}

{{- define "ecommerce.fullname" -}}
{{ printf "%s-%s" .root.Release.Name .name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Image reference. Fails the render if CI forgot to pass registry or tag,
     so we never silently deploy ":latest" or an empty image. */}}
{{- define "ecommerce.image" -}}
{{- $g := .root.Values.global.image -}}
{{- $registry := required "global.image.registry must be set by the pipeline" $g.registry -}}
{{- $tag := required "global.image.tag must be set by the pipeline" $g.tag -}}
{{ printf "%s/%s:%s" $registry (default .name .svc.image) $tag }}
{{- end }}

{{/* Merge per-service settings over chart defaults. */}}
{{- define "ecommerce.resources" -}}
{{- toYaml (default .root.Values.defaults.resources .svc.resources) }}
{{- end }}
