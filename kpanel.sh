#!/bin/bash
# =========================================================
# Kpanel PRO FINAL - Kubernetes Dashboard (gum + fzf)
# =========================================================
# Dependências: kubectl | gum | fzf
# =========================================================

set -euo pipefail

# ---------------------------------------------------------
# Configuração
# ---------------------------------------------------------
BASE_DIR="$HOME/.k8s-dashboard"
CACHE_DIR="$BASE_DIR/cache"
FAV_DIR="$BASE_DIR/favs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$CACHE_DIR" "$FAV_DIR" "$BACKUP_DIR"

# Namespace atual
ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)
ns=${ns:-default}

# ---------------------------------------------------------
# Ícones
# ---------------------------------------------------------
icon_pod="📦"
icon_deploy="🚀"
icon_svc="🔌"
icon_cm="🧩"
icon_secret="🔐"

# ---------------------------------------------------------
# FZF com preview ativado por TAB
# ---------------------------------------------------------
fzf_with_preview() {
  local prompt="$1"
  local type="$2"

  local preview_cmd=""
  case "$type" in
    pod)
      preview_cmd="kubectl describe pod {} -n $ns || kubectl top pod {} -n $ns"
      ;;
    deploy)
      preview_cmd="kubectl describe deploy {} -n $ns"
      ;;
    svc)
      preview_cmd="kubectl describe svc {} -n $ns"
      ;;
    cm)
      preview_cmd="kubectl describe cm {} -n $ns"
      ;;
    secret)
      preview_cmd="kubectl describe secret {} -n $ns | sed 's/:[^ ]*/: [REDACTED]/g'"
      ;;
    *)
      preview_cmd="echo 'Sem preview'"
      ;;
  esac

  fzf \
    --prompt="$prompt > " \
    --height=80% \
    --reverse \
    --border \
    --ansi \
    --preview="$preview_cmd" \
    --preview-window=right:60%:hidden \
    --bind "tab:toggle-preview"
}

# ---------------------------------------------------------
# Seletores
# ---------------------------------------------------------
select_pod() {
  kubectl get pods -n "$ns" --no-headers \
    | awk "{print \"$icon_pod \" \$1}" \
    | sed "s/$icon_pod //" \
    | fzf_with_preview "Pod" "pod"
}

select_deploy() {
  kubectl get deploy -n "$ns" --no-headers \
    | awk "{print \"$icon_deploy \" \$1}" \
    | sed "s/$icon_deploy //" \
    | fzf_with_preview "Deployment" "deploy"
}

select_service() {
  kubectl get svc -n "$ns" --no-headers \
    | awk "{print \"$icon_svc \" \$1}" \
    | sed "s/$icon_svc //" \
    | fzf_with_preview "Service" "svc"
}

select_configmap() {
  kubectl get cm -n "$ns" --no-headers \
    | awk "{print \"$icon_cm \" \$1}" \
    | sed "s/$icon_cm //" \
    | fzf_with_preview "ConfigMap" "cm"
}

select_secret() {
  kubectl get secrets -n "$ns" --no-headers \
    | awk "{print \"$icon_secret \" \$1}" \
    | sed "s/$icon_secret //" \
    | fzf_with_preview "Secret" "secret"
}

# ---------------------------------------------------------
# Contexto / Namespace
# ---------------------------------------------------------
select_context() {
  ctx=$(kubectl config get-contexts --no-headers | awk '{print $2}' | fzf)
  kubectl config use-context "$ctx"
  ns=$(kubectl config view --minify -o jsonpath='{..namespace}')
  ns=${ns:-default}
}

set_namespace() {
  ns=$(kubectl get ns --no-headers | awk '{print $1}' | fzf)
}

# ---------------------------------------------------------
# Funcionalidades
# ---------------------------------------------------------
add_fav() {
  echo "$ns:$1" >> "$FAV_DIR/pods.txt"
  gum style --foreground 46 "⭐ Pod adicionado aos favoritos!"
}

list_favs() {
  [[ -f "$FAV_DIR/pods.txt" ]] || gum style --foreground 160 "Nenhum favorito"
  cat "$FAV_DIR/pods.txt" | fzf
}

backup_configs() {
  ts=$(date +%Y%m%d-%H%M%S)
  out="$BACKUP_DIR/$ns-$ts"
  mkdir -p "$out"

  kubectl get cm -n "$ns" -o yaml > "$out/configmaps.yaml"
  kubectl get secrets -n "$ns" -o yaml > "$out/secrets.yaml"

  gum style --foreground 46 "📦 Backup criado em $out"
}

health_check() {
  kubectl get pods -n "$ns" --no-headers | awk '
    $3=="Running" {print "✔ " $1}
    $3!="Running" {print "✖ " $1 " - " $3}
  ' | gum pager
}

# ---------------------------------------------------------
# 🌍 Busca Global
# ---------------------------------------------------------
global_resource_search() {
  kubectl api-resources --verbs=list --namespaced -o name \
    | while read -r res; do
        kubectl get "$res" -A --no-headers 2>/dev/null \
          | awk -v r="$res" '{print r "\t" $1 "\t" $2}'
      done \
    | fzf \
        --prompt="Buscar Recurso > " \
        --height=90% \
        --reverse \
        --border \
        --preview "kubectl get {1} {3} -n {2} -o yaml 2>/dev/null | head -200"
}

# ---------------------------------------------------------
# UI
# ---------------------------------------------------------
dashboard() {
  clear
  gum style --border normal --margin 1 --padding 1 --border-foreground 212 "
🚀 Kpanel PRO FINAL

Contexto:  $(kubectl config current-context)
Namespace: $ns

TAB → Preview | Busca fuzzy em tudo
"
}

# ---------------------------------------------------------
# MENU COM BUSCADOR
# ---------------------------------------------------------
while true; do
  dashboard

  action=$(printf "%s\n" \
    "Trocar Contexto" \
    "Trocar Namespace" \
    "Descrever Pod" \
    "Logs do Pod" \
    "YAML do Pod" \
    "Exec Bash no Pod" \
    "Restart Pod" \
    "Deployments" \
    "Restart Deployment" \
    "Services" \
    "ConfigMaps" \
    "Secrets" \
    "Adicionar Pod aos Favoritos" \
    "Listar Favoritos" \
    "Health Check" \
    "Backup ConfigMaps/Secrets" \
    "Buscar Recurso (Global)" \
    "Cluster Info" \
    "Nodes" \
    "Sair" \
    | fzf --prompt="Menu > " --height=70% --reverse --border)

  case "$action" in
    "Trocar Contexto") select_context ;;
    "Trocar Namespace") set_namespace ;;
    "Descrever Pod") kubectl describe pod "$(select_pod)" -n "$ns" | gum pager ;;
    "Logs do Pod") kubectl logs "$(select_pod)" -n "$ns" | gum pager ;;
    "YAML do Pod") kubectl get pod "$(select_pod)" -n "$ns" -o yaml | gum pager ;;
    "Exec Bash no Pod") kubectl exec -it "$(select_pod)" -n "$ns" -- bash ;;
    "Restart Pod") kubectl delete pod "$(select_pod)" -n "$ns" ;;
    "Deployments") kubectl get deploy -n "$ns" | gum pager ;;
    "Restart Deployment") kubectl rollout restart deploy "$(select_deploy)" -n "$ns" ;;
    "Services") kubectl get svc -n "$ns" | gum pager ;;
    "ConfigMaps") kubectl get cm -n "$ns" | gum pager ;;
    "Secrets") kubectl get secrets -n "$ns" | gum pager ;;
    "Adicionar Pod aos Favoritos") add_fav "$(select_pod)" ;;
    "Listar Favoritos") list_favs ;;
    "Health Check") health_check ;;
    "Backup ConfigMaps/Secrets") backup_configs ;;
    "Buscar Recurso (Global)") global_resource_search ;;
    "Cluster Info") kubectl cluster-info | gum pager ;;
    "Nodes") kubectl get nodes | gum pager ;;
    "Sair") exit 0 ;;
  esac

  gum confirm "Voltar ao menu?" || exit 0
done
