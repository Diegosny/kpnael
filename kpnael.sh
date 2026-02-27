#!/bin/bash

set -euo pipefail

BASE_DIR="$HOME/.kpnael-dashboard"
mkdir -p "$BASE_DIR/backups"

get_current_ns() {
  local current=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default")
  echo "${current:-default}"
}

ns=$(get_current_ns)

fzf_with_preview() {
  local prompt="$1"
  local type="$2"
  local preview_cmd=""

  case "$type" in
    pod)    preview_cmd="kubectl describe pod {} -n $ns" ;;
    deploy) preview_cmd="kubectl describe deploy {} -n $ns" ;;
    secret) preview_cmd="kubectl describe secret {} -n $ns" ;;
    cj)     preview_cmd="kubectl describe cronjob {} -n $ns" ;;
    configmap) preview_cmd="kubectl describe configmap {} -n $ns" ;;
    *)      preview_cmd="echo 'Sem preview disponível'" ;;
  esac

  fzf \
    --prompt="$prompt > " \
    --height=80% \
    --reverse \
    --border \
    --ansi \
    --preview="$preview_cmd | head -50" \
    --preview-window=right:60%:hidden \
    --bind "tab:toggle-preview"
}

select_resource() {
  local type=$1
  local icon=$2
  local result=$(kubectl get "$type" -n "$ns" --no-headers 2>/dev/null \
    | awk -v i="$icon" '{print i " " $1}' \
    | sed "s/$icon //" \
    | fzf_with_preview "$type" "$type" || echo "")
  echo "$result"
}

select_container() {
  local pod=$1
  [[ -z "$pod" ]] && return
  local containers=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}')
  local count=$(echo "$containers" | wc -w)
  
  if [ "$count" -gt 1 ]; then
    echo "$containers" | tr ' ' '\n' | fzf --prompt="Container > " --height=40% --reverse || echo ""
  else
    echo "$containers"
  fi
}

view_env() {
  local pod=$(select_resource "pod" "📦")
  [[ -z "$pod" ]] && return
  local cont=$(select_container "$pod")
  [[ -z "$cont" ]] && return
  
  gum style --foreground 212 "🔍 Buscando arquivo .env no pod $pod..."
  local env_data=$(kubectl exec "$pod" -c "$cont" -n "$ns" -- sh -c 'cat .env 2>/dev/null || cat /.env 2>/dev/null || cat /app/.env 2>/dev/null' || true)
  
  if [[ -z "$env_data" ]]; then
    gum style --foreground 160 "❌ Arquivo .env não encontrado."
    sleep 2
  else
    echo "$env_data" | gum pager
  fi
}

filter_logs() {
  local pod=$(select_resource "pod" "📦")
  [[ -z "$pod" ]] && return
  local cont=$(select_container "$pod")
  [[ -z "$cont" ]] && return
  
  local keyword=$(gum input --placeholder "Filtrar por:")
  [[ -z "$keyword" ]] && return

  kubectl logs "$pod" -c "$cont" -n "$ns" --tail=2000 | grep -i --color=always "$keyword" | gum pager
}

decode_secret() {
  local sec=$(select_resource "secret" "🔐")
  [[ -z "$sec" ]] && return
  
  kubectl get secret "$sec" -n "$ns" -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n\n"}}{{end}}' | gum pager
}

trigger_cronjob() {
  local cj=$(select_resource "cj" "⏳")
  [[ -z "$cj" ]] && return
  
  local job_name="${cj}-manual-$(date +%s)"
  kubectl create job --from=cronjob/"$cj" "$job_name" -n "$ns" > /dev/null
  
  if gum confirm "Deseja acompanhar os logs deste Job agora?"; then
    sleep 3
    local pod_name=$(kubectl get pods -n "$ns" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [[ -n "$pod_name" ]] && kubectl logs -f "$pod_name" -n "$ns" || sleep 2
  fi
}

rollback_deploy() {
  local deploy=$(select_resource "deploy" "🚀")
  [[ -z "$deploy" ]] && return
  
  if gum confirm "Reverter deployment '$deploy'?"; then
    kubectl rollout undo deploy/"$deploy" -n "$ns"
    sleep 1
  fi
}

clean_failed_pods() {
  local bad_pods=$(kubectl get pods --field-selector status.phase=Failed -n "$ns" --no-headers 2>/dev/null || true)
  if [[ -z "$bad_pods" ]]; then
    gum style --foreground 46 "✨ Tudo limpo!"
    sleep 1; return
  fi
  if gum confirm "Deseja deletar pods com erro?"; then
    kubectl delete pods --field-selector status.phase=Failed -n "$ns" | gum pager
  fi
}

scale_resource() {
  local deploy=$(select_resource "deploy" "🚀")
  [[ -z "$deploy" ]] && return
  local current=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}')
  local replicas=$(gum input --placeholder "Novo valor (Atual: $current):")
  [[ -n "$replicas" ]] && kubectl scale deploy "$deploy" -n "$ns" --replicas="$replicas"
}

set_image() {
  local deploy=$(select_resource "deploy" "🚀")
  [[ -z "$deploy" ]] && return
  local containers=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.template.spec.containers[*].name}')
  local container=$(echo "$containers" | tr ' ' '\n' | fzf --prompt="Container > " --height=40% || echo "")
  [[ -z "$container" ]] && return
  
  local new_img=$(gum input --placeholder "Nova imagem:")
  [[ -n "$new_img" ]] && kubectl set image deploy/"$deploy" "$container"="$new_img" -n "$ns"
}

view_events() {
  kubectl get events -n "$ns" --sort-by='.lastTimestamp' | gum pager
}

live_edit() {
  local kind=$(printf "configmap\nsecret" | fzf --prompt="Tipo > " --height=30% || echo "")
  [[ -z "$kind" ]] && return
  local res=$(select_resource "$kind" "📝")
  [[ -z "$res" ]] && return
  kubectl edit "$kind" "$res" -n "$ns"
}

helm_dashboard() {
  if ! command -v helm &>/dev/null; then
    gum style --foreground 160 "❌ Helm não instalado."
    sleep 2; return
  fi
  local release=$(helm ls -n "$ns" --short | fzf --prompt="Release > " --height=40% || echo "")
  [[ -z "$release" ]] && return
  local action=$(printf "📜 Ver Valores\n🔄 Status\n⏪ Rollback" | fzf --prompt="Ação > " --height=40% || echo "")
  case "${action#* }" in
    "Ver Valores") helm get values "$release" -n "$ns" | gum pager ;;
    "Status")      helm status "$release" -n "$ns" | gum pager ;;
    "Rollback")
      local rev=$(helm history "$release" -n "$ns" | fzf --prompt="Revisão > " | awk '{print $1}')
      [[ -n "$rev" ]] && gum confirm "Reverter para revisão $rev?" && helm rollback "$release" "$rev" -n "$ns" ;;
  esac
}

debug_pod() {
  gum style --foreground 212 "🚀 Iniciando Pod de Debug (netshoot)..."
  kubectl run "kpnael-debug-$(date +%s)" --rm -i --tty --image=nicolaka/netshoot -n "$ns" -- /bin/bash
}

oom_hunter() {
  gum style --foreground 212 "💀 Caçando Pods OOMKilled no namespace $ns..."
  local oom=$(kubectl get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{" - "}{range .status.containerStatuses[*]}{.lastState.terminated.reason}{"\n"}{end}{end}' | grep OOMKilled || true)
  if [[ -z "$oom" ]]; then
    gum style --foreground 46 "✅ Nenhum Pod OOMKilled encontrado!"
    sleep 2
  else
    echo "$oom" | gum pager
  fi
}

create_namespace() {
  local new_ns=$(gum input --placeholder "Nome do novo namespace (ex: meu-projeto):")
  [[ -z "$new_ns" ]] && return

  if kubectl get ns "$new_ns" >/dev/null 2>&1; then
    gum style --foreground 160 "❌ O namespace '$new_ns' já existe."
    sleep 2
  else
    gum style --foreground 212 "⏳ Criando namespace '$new_ns'..."
    kubectl create namespace "$new_ns" >/dev/null
    gum style --foreground 46 "✅ Namespace criado com sucesso!"
    
    if gum confirm "Deseja mudar para este namespace agora?"; then
      kubectl config set-context --current --namespace="$new_ns" >/dev/null
      ns="$new_ns"
    fi
  fi
}

while true; do
  clear
  ctx=$(kubectl config current-context)
  gum style --border normal --margin 1 --padding 1 --border-foreground 57 "☸️  KPNAEL | $ctx | $ns"

  action=$(printf "%s\n" \
    "🔎 Logs (Filtrar)" \
    "📖 Logs (Pager)" \
    "🔴 Logs (Real-time)" \
    "🐚 Shell (Exec)" \
    "📄 Ver .env" \
    "🔓 Decodificar Secret" \
    "⚠️  Radar de Eventos" \
    "✏️  Editor (ConfigMap/Secret)" \
    "🚀 Helm Dashboard" \
    "🕵️  Pod de Debug (Netshoot)" \
    "💀 Caçador de OOMKilled" \
    "⏪ Rollback" \
    "⏳ Disparar CronJob" \
    "⚖️  Scale" \
    "🖼️  Trocar Imagem" \
    "🧹 Faxina" \
    "🔌 Port-Forward" \
    "📊 Métricas" \
    "🌐 Contexto/Namespace" \
    "➕ Criar Namespace" \
    "💾 Backup" \
    "❌ Sair" \
    | fzf --prompt="Menu > " --height=90% --reverse --border)

  case "$action" in
    "🔎 Logs (Filtrar)") filter_logs ;;
    "📖 Logs (Pager)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      [[ -n "$pod" && -n "$cont" ]] && kubectl logs "$pod" -c "$cont" -n "$ns" --tail=300 | gum pager ;;
    "🔴 Logs (Real-time)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      [[ -n "$pod" && -n "$cont" ]] && kubectl logs -f "$pod" -c "$cont" -n "$ns" --tail=20 ;;
    "🐚 Shell (Exec)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      [[ -n "$pod" && -n "$cont" ]] && (kubectl exec -it "$pod" -c "$cont" -n "$ns" -- bash 2>/dev/null || kubectl exec -it "$pod" -c "$cont" -n "$ns" -- sh) ;;
    "📄 Ver .env") view_env ;;
    "🔓 Decodificar Secret") decode_secret ;;
    "⚠️  Radar de Eventos") view_events ;;
    "✏️  Editor (ConfigMap/Secret)") live_edit ;;
    "🚀 Helm Dashboard") helm_dashboard ;;
    "🕵️  Pod de Debug (Netshoot)") debug_pod ;;
    "💀 Caçador de OOMKilled") oom_hunter ;;
    "⏪ Rollback") rollback_deploy ;;
    "⏳ Disparar CronJob") trigger_cronjob ;;
    "⚖️  Scale") scale_resource ;;
    "🖼️  Trocar Imagem") set_image ;;
    "🧹 Faxina") clean_failed_pods ;;
    "🔌 Port-Forward")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && ports=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].ports[*].containerPort}')
      [[ -n "$pod" ]] && local_p=$(gum input --placeholder "Porta Local")
      [[ -n "$pod" && -n "$local_p" ]] && pod_p=$(gum input --value "${ports%% *}" --placeholder "Porta no Pod")
      [[ -n "$pod" && -n "$local_p" && -n "$pod_p" ]] && kubectl port-forward pod/"$pod" -n "$ns" "$local_p":"$pod_p" ;;
    "📊 Métricas")
      kubectl top nodes 2>/dev/null || echo "Metrics Server OFF"
      kubectl top pods -n "$ns" --sort-by=cpu | head -n 11 2>/dev/null || true
      read -p "Enter..." ;;
    "🌐 Contexto/Namespace")
      sub=$(printf "Contexto\nNamespace" | fzf)
      [[ "$sub" == "Contexto" ]] && { 
        ctx=$(kubectl config get-contexts -o name | fzf)
        [[ -n "$ctx" ]] && kubectl config use-context "$ctx" >/dev/null; ns=$(get_current_ns); 
      } || {
        ns_temp=$(kubectl get ns -o name | sed 's|namespace/||' | fzf)
        [[ -n "$ns_temp" ]] && ns="$ns_temp"
      } ;;
    "➕ Criar Namespace") create_namespace ;;
    "💾 Backup")
      ts=$(date +%s); mkdir -p "$BASE_DIR/backups/$ns"
      kubectl get cm,secret -n "$ns" -o yaml > "$BASE_DIR/backups/$ns/backup-$ts.yaml"
      sleep 1 ;;
    "❌ Sair") exit 0 ;;
  esac
done