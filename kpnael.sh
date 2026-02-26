#!/bin/bash
# =========================================================
# KPNAEL PRO ULTRA - O Canivete Suíço do Kubernetes
# =========================================================

set -euo pipefail

# Configurações de diretórios
BASE_DIR="$HOME/.kpnael-dashboard"
mkdir -p "$BASE_DIR/backups"

# --- Funções Auxiliares ---

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

# --- Funcionalidades do Dia a Dia ---

view_env() {
  local pod=$(select_resource "pod" "📦")
  [[ -z "$pod" ]] && return
  local cont=$(select_container "$pod")
  [[ -z "$cont" ]] && return
  
  gum style --foreground 212 "🔍 Buscando arquivo .env no pod $pod..."
  
  # Tenta ler o .env no diretório de trabalho (WORKDIR) ou na raiz (/)
  local env_data=$(kubectl exec "$pod" -c "$cont" -n "$ns" -- sh -c 'cat .env 2>/dev/null || cat /.env 2>/dev/null || cat /app/.env 2>/dev/null' || true)
  
  if [[ -z "$env_data" ]]; then
    gum style --foreground 160 "❌ Arquivo .env não encontrado (buscamos em ./.env, /.env e /app/.env)."
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
  
  local keyword=$(gum input --placeholder "Filtrar por (ex: ERROR, Exception, timeout):")
  [[ -z "$keyword" ]] && return

  kubectl logs "$pod" -c "$cont" -n "$ns" --tail=2000 | grep -i --color=always "$keyword" | gum pager
}

decode_secret() {
  local sec=$(select_resource "secret" "🔐")
  [[ -z "$sec" ]] && return
  
  gum style --foreground 212 "🔓 Decodificando Secret: $sec"
  kubectl get secret "$sec" -n "$ns" -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n\n"}}{{end}}' | gum pager
}

trigger_cronjob() {
  local cj=$(select_resource "cj" "⏳")
  [[ -z "$cj" ]] && return
  
  local job_name="${cj}-manual-$(date +%s)"
  gum style --foreground 212 "⏳ Criando Job: $job_name..."
  kubectl create job --from=cronjob/"$cj" "$job_name" -n "$ns" > /dev/null
  
  gum style --foreground 46 "✅ Job disparado com sucesso!"
  
  if gum confirm "Deseja acompanhar os logs deste Job agora?"; then
    gum style --foreground 212 "Aguardando o Pod iniciar..."
    sleep 3
    local pod_name=$(kubectl get pods -n "$ns" -l job-name="$job_name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$pod_name" ]]; then
      gum style --foreground 212 "Aperte Ctrl+C para sair do log"
      kubectl logs -f "$pod_name" -n "$ns"
    else
      echo "O Pod está demorando para iniciar. Verifique pelo menu de Logs depois."
      sleep 3
    fi
  fi
}

rollback_deploy() {
  local deploy=$(select_resource "deploy" "🚀")
  [[ -z "$deploy" ]] && return
  
  if gum confirm "⚠️ Reverter (rollback) o deployment '$deploy' para a versão anterior?"; then
    kubectl rollout undo deploy/"$deploy" -n "$ns"
    gum style --foreground 46 "⏪ Rollback executado!"
    sleep 2
  fi
}

clean_failed_pods() {
  gum style --foreground 212 "🔍 Procurando pods com erro (Failed/Evicted)..."
  
  local bad_pods=$(kubectl get pods --field-selector status.phase=Failed -n "$ns" --no-headers 2>/dev/null || true)
  
  if [[ -z "$bad_pods" ]]; then
    gum style --foreground 46 "✨ Tudo limpo! Nenhum Pod com erro encontrado."
    sleep 2
    return
  fi

  echo "⚠️ Os seguintes Pods estão com erro e serão removidos:"
  echo "$bad_pods" | awk '{print " - " $1 " (" $3 ")"}'
  echo ""

  if gum confirm "🧹 Deseja deletar estes Pods agora?"; then
    kubectl delete pods --field-selector status.phase=Failed -n "$ns" | gum pager
    gum style --foreground 46 "✨ Faxina concluída!"
  else
    gum style --foreground 160 "❌ Operação cancelada."
    sleep 1
  fi
}

# --- Funções Clássicas Mantidas ---

scale_resource() {
  local deploy=$(select_resource "deploy" "🚀")
  [[ -z "$deploy" ]] && return
  local current=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}')
  local replicas=$(gum input --placeholder "Replicas atuais: $current. Novo valor:")
  if [[ -n "$replicas" ]]; then
    kubectl scale deploy "$deploy" -n "$ns" --replicas="$replicas"
    gum style --foreground 46 "✅ Scale concluído!"
    sleep 1
  fi
}

set_image() {
  local deploy=$(select_resource "deploy" "🚀")
  [[ -z "$deploy" ]] && return
  local containers=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.template.spec.containers[*].name}')
  local container=$(echo "$containers" | tr ' ' '\n' | fzf --prompt="Container > " --height=40% || echo "")
  [[ -z "$container" ]] && return
  
  local new_img=$(gum input --placeholder "Nova imagem (ex: nginx:latest)")
  if [[ -n "$new_img" ]]; then
    kubectl set image deploy/"$deploy" "$container"="$new_img" -n "$ns"
    gum style --foreground 46 "✅ Imagem atualizada!"
    sleep 1
  fi
}

# --- Loop Principal ---

while true; do
  clear
  ctx=$(kubectl config current-context)
  gum style --border normal --margin 1 --padding 1 --border-foreground 57 "
  ☸️  **KPNAEL ULTRA** | Contexto: $ctx | Namespace: $ns
  
  TAB → Toggle Preview | ESC → Cancelar/Sair de menus
  "

  action=$(printf "%s\n" \
    "🔎 Logs (Filtrar por Palavra)" \
    "📖 Logs (Histórico em Pager)" \
    "🔴 Logs (Real-time ao vivo)" \
    "🐚 Shell (Exec no Pod)" \
    "📄 Ler arquivo .env do Pod" \
    "🔓 Decodificar Secret (Base64)" \
    "⏪ Rollback de Deployment" \
    "⏳ Disparar CronJob Manual" \
    "⚖️  Escalar Deployment (Scale)" \
    "🖼️  Trocar Imagem do Deployment" \
    "🧹 Faxina (Limpar Pods com Erro)" \
    "🔌 Port-Forward" \
    "📊 Métricas (Top CPU/Memória)" \
    "🌐 Trocar Contexto/Namespace" \
    "💾 Backup CM/Secrets" \
    "❌ Sair" \
    | fzf --prompt="Menu > " --height=85% --reverse --border)

  case "$action" in
    "🔎 Logs (Filtrar por Palavra)") filter_logs ;;
    
    "📖 Logs (Histórico em Pager)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      [[ -n "$pod" && -n "$cont" ]] && kubectl logs "$pod" -c "$cont" -n "$ns" --tail=300 | gum pager ;;

    "🔴 Logs (Real-time ao vivo)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      if [[ -n "$pod" && -n "$cont" ]]; then
        gum style --foreground 212 "Aperte Ctrl+C para sair do log"
        kubectl logs -f "$pod" -c "$cont" -n "$ns" --tail=20
      fi ;;
    
    "🐚 Shell (Exec no Pod)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      [[ -n "$pod" && -n "$cont" ]] && (kubectl exec -it "$pod" -c "$cont" -n "$ns" -- bash 2>/dev/null || kubectl exec -it "$pod" -c "$cont" -n "$ns" -- sh) ;;
      
    "📄 Ler arquivo .env do Pod") view_env ;;
    "🔓 Decodificar Secret (Base64)") decode_secret ;;
    "⏪ Rollback de Deployment")      rollback_deploy ;;
    "⏳ Disparar CronJob Manual")     trigger_cronjob ;;
    "⚖️  Escalar Deployment (Scale)")  scale_resource ;;
    "🖼️  Trocar Imagem do Deployment") set_image ;;
    "🧹 Faxina (Limpar Pods com Erro)") clean_failed_pods ;;
    
    "🔌 Port-Forward")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && ports=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].ports[*].containerPort}')
      [[ -n "$pod" ]] && local_p=$(gum input --placeholder "Porta Local")
      [[ -n "$pod" && -n "$local_p" ]] && pod_p=$(gum input --value "${ports%% *}" --placeholder "Porta no Pod")
      [[ -n "$pod" && -n "$local_p" && -n "$pod_p" ]] && kubectl port-forward pod/"$pod" -n "$ns" "$local_p":"$pod_p" ;;
    
    "📊 Métricas (Top CPU/Memória)")
      kubectl top nodes 2>/dev/null || echo "Metrics Server não disponível."
      echo ""
      kubectl top pods -n "$ns" --sort-by=cpu | head -n 11 2>/dev/null || true
      read -p "Pressione Enter para voltar..." ;;
    
    "🌐 Trocar Contexto/Namespace")
      sub=$(printf "Contexto\nNamespace" | fzf)
      [[ "$sub" == "Contexto" ]] && { 
        ctx=$(kubectl config get-contexts -o name | fzf)
        [[ -n "$ctx" ]] && kubectl config use-context "$ctx" >/dev/null; ns=$(get_current_ns); 
      } || {
        ns_temp=$(kubectl get ns -o name | sed 's|namespace/||' | fzf)
        [[ -n "$ns_temp" ]] && ns="$ns_temp"
      } ;;
      
    "💾 Backup CM/Secrets")
      ts=$(date +%s); mkdir -p "$BASE_DIR/backups/$ns"
      kubectl get cm,secret -n "$ns" -o yaml > "$BASE_DIR/backups/$ns/backup-$ts.yaml"
      gum style --foreground 46 "✅ Backup salvo!"
      sleep 1 ;;

    "❌ Sair") exit 0 ;;
  esac
done
