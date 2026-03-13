#!/bin/bash

trap 'printf "\e[?2004l"; clear' EXIT
trap '' SIGTSTP

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
    if command -v bat &>/dev/null; then
      echo "$env_data" | bat -l properties --style=numbers,changes --paging=always
    elif command -v batcat &>/dev/null; then # Tratativa para Ubuntu/Debian
      echo "$env_data" | batcat -l properties --style=numbers,changes --paging=always
    else
      echo "$env_data" | gum pager
    fi
  fi
}

filter_logs() {
  local pod=$(select_resource "pod" "📦")
  [[ -z "$pod" ]] && return
  local cont=$(select_container "$pod")
  [[ -z "$cont" ]] && return
  
  local keyword=$(gum input --placeholder "Filtrar por:")
  [[ -z "$keyword" ]] && return

  kubectl logs "$pod" -c "$cont" -n "$ns" --tail=2000 | grep -i --color=always "$keyword" | gum pager || { gum style --foreground 160 "❌ Erro ao buscar logs."; sleep 2; }
}

decode_secret() {
  local sec=$(select_resource "secret" "🔐")
  [[ -z "$sec" ]] && return
  
  local secret_data=$(kubectl get secret "$sec" -n "$ns" -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n\n"}}{{end}}')
  
  if command -v bat &>/dev/null; then
    echo "$secret_data" | bat -l yaml --style=numbers --paging=always
  elif command -v batcat &>/dev/null; then
    echo "$secret_data" | batcat -l yaml --style=numbers --paging=always
  else
    echo "$secret_data" | gum pager
  fi
}

trigger_cronjob() {
  local cj=$(select_resource "cj" "⏳")
  [[ -z "$cj" ]] && return
  
  local job_name="${cj}-manual-$(date +%s)"
  kubectl create job --from=cronjob/"$cj" "$job_name" -n "$ns" > /dev/null || { gum style --foreground 160 "❌ Erro ao disparar Job."; sleep 2; return; }
  
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
    kubectl rollout undo deploy/"$deploy" -n "$ns" || { gum style --foreground 160 "❌ Erro no rollback."; sleep 2; }
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
  [[ -n "$replicas" ]] && kubectl scale deploy "$deploy" -n "$ns" --replicas="$replicas" || { gum style --foreground 160 "❌ Erro ao escalar."; sleep 2; }
}

set_image() {
  local deploy=$(select_resource "deploy" "🚀")
  [[ -z "$deploy" ]] && return
  local containers=$(kubectl get deploy "$deploy" -n "$ns" -o jsonpath='{.spec.template.spec.containers[*].name}')
  local container=$(echo "$containers" | tr ' ' '\n' | fzf --prompt="Container > " --height=40% || echo "")
  [[ -z "$container" ]] && return
  
  local new_img=$(gum input --placeholder "Nova imagem:")
  [[ -n "$new_img" ]] && kubectl set image deploy/"$deploy" "$container"="$new_img" -n "$ns" || { gum style --foreground 160 "❌ Erro ao trocar imagem."; sleep 2; }
}

view_events() {
  kubectl get events -n "$ns" --sort-by='.lastTimestamp' | gum pager || { gum style --foreground 160 "❌ Erro ao buscar eventos."; sleep 2; }
}

live_edit() {
  local kind=$(printf "configmap\nsecret" | fzf --prompt="Tipo > " --height=30% || echo "")
  [[ -z "$kind" ]] && return
  local res=$(select_resource "$kind" "📝")
  [[ -z "$res" ]] && return
  kubectl edit "$kind" "$res" -n "$ns" || { gum style --foreground 160 "❌ Edição cancelada ou falhou."; sleep 2; }
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
  kubectl run "kpnael-debug-$(date +%s)" --rm -i --tty --image=nicolaka/netshoot -n "$ns" -- /bin/bash || { gum style --foreground 160 "❌ Erro ao iniciar debug."; sleep 2; }
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

audit_resources() {
  gum style --foreground 212 "📊 Auditoria: Limites e Requisições (Namespace: $ns)..."
  kubectl get pods -n "$ns" -o custom-columns="POD:.metadata.name,CPU-REQ:.spec.containers[*].resources.requests.cpu,CPU-LIM:.spec.containers[*].resources.limits.cpu,MEM-REQ:.spec.containers[*].resources.requests.memory,MEM-LIM:.spec.containers[*].resources.limits.memory" | gum pager || { gum style --foreground 160 "❌ Erro ao auditar recursos."; sleep 2; }
}

rbac_tester() {
  local sa=$(kubectl get sa -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' | fzf --prompt="ServiceAccount > " || echo "")
  [[ -z "$sa" ]] && return
  gum style --foreground 212 "🔐 Avaliando permissões da ServiceAccount: $sa..."
  kubectl auth can-i --list --as="system:serviceaccount:$ns:$sa" -n "$ns" | gum pager
}

manage_storage() {
  local pvc=$(kubectl get pvc -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' | fzf --prompt="PVC > " --preview="kubectl describe pvc {} -n $ns" || echo "")
  [[ -z "$pvc" ]] && return
  local action=$(printf "📝 Editar YAML\n🗑️ Deletar PVC" | fzf --prompt="Ação > " --height=30% || echo "")
  case "${action#* }" in
    "Editar YAML") kubectl edit pvc "$pvc" -n "$ns" ;;
    "Deletar PVC") gum confirm "Deletar PVC $pvc de forma permanente?" && kubectl delete pvc "$pvc" -n "$ns" ;;
  esac
}

image_xray() {
  local pod=$(select_resource "pod" "📦")
  [[ -z "$pod" ]] && return
  local cont=$(select_container "$pod")
  [[ -z "$cont" ]] && return
  
  local img=$(kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[?(@.name=='$cont')].image}")
  gum style --foreground 212 "🩻 Analisando as camadas da imagem: $img"
  gum style --foreground 240 "Aviso: Executando o motor localmente via Docker."
  
  if command -v docker &>/dev/null; then
     docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive:latest "$img" || { gum style --foreground 160 "❌ Falha ao executar Raio-X. Imagem pode não ser pública."; sleep 3; }
  else
     gum style --foreground 160 "❌ Docker não detectado na sua máquina local. O Raio-X precisa dele."
     sleep 3
  fi
}

network_sniffer() {
  local pod=$(select_resource "pod" "📦")
  [[ -z "$pod" ]] && return
  local cont=$(select_container "$pod")
  [[ -z "$cont" ]] && return
  
  local port=$(gum input --placeholder "Porta para escutar (ex: 8080) ou deixe em branco para todas:")
  local filter=""
  [[ -n "$port" ]] && filter="port $port"
  
  gum style --foreground 212 "🕸️ Injetando Sniffer Efêmero no Pod $pod..."
  gum style --foreground 240 "Pressione Ctrl+C para parar a captura a qualquer momento."
  sleep 2
  
  kubectl debug -it "$pod" -n "$ns" --target="$cont" --image=nicolaka/netshoot -- tcpdump -i any -A -nn $filter || { gum style --foreground 160 "❌ Falha. Seu cluster pode não ter suporte a Ephemeral Containers."; sleep 3; }
}

create_namespace() {
  local new_ns=$(gum input --placeholder "Nome do novo namespace:")
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
  printf "\e[?2004l"
  
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
    "💰 Auditor de Recursos" \
    "🔐 Testar RBAC (Permissões)" \
    "💾 Gerenciar Storage (PVC)" \
    "🩻 Raio-X da Imagem (Dive)" \
    "🕸️ Sniffer de Rede (Ao Vivo)" \
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
    | fzf --prompt="Menu > " --height=95% --reverse --border || echo "")

  case "$action" in
    "🔎 Logs (Filtrar)") filter_logs ;;
    "📖 Logs (Pager)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      [[ -n "$pod" && -n "$cont" ]] && (kubectl logs "$pod" -c "$cont" -n "$ns" --tail=300 | gum pager || { gum style --foreground 160 "❌ O Pod não está pronto ou falhou."; sleep 3; }) ;;
    "🔴 Logs (Real-time)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      [[ -n "$pod" && -n "$cont" ]] && (kubectl logs -f "$pod" -c "$cont" -n "$ns" --tail=20 || { gum style --foreground 160 "❌ O Pod não está pronto ou falhou."; sleep 3; }) ;;
    "🐚 Shell (Exec)")
      pod=$(select_resource "pod" "📦")
      [[ -n "$pod" ]] && cont=$(select_container "$pod")
      [[ -n "$pod" && -n "$cont" ]] && (kubectl exec -it "$pod" -c "$cont" -n "$ns" -- bash 2>/dev/null || kubectl exec -it "$pod" -c "$cont" -n "$ns" -- sh || { gum style --foreground 160 "❌ Erro de conexão. O Pod está rodando?"; sleep 3; }) ;;
    "📄 Ver .env") view_env ;;
    "🔓 Decodificar Secret") decode_secret ;;
    "⚠️  Radar de Eventos") view_events ;;
    "✏️  Editor (ConfigMap/Secret)") live_edit ;;
    "🚀 Helm Dashboard") helm_dashboard ;;
    "🕵️  Pod de Debug (Netshoot)") debug_pod ;;
    "💀 Caçador de OOMKilled") oom_hunter ;;
    "💰 Auditor de Recursos") audit_resources ;;
    "🔐 Testar RBAC (Permissões)") rbac_tester ;;
    "💾 Gerenciar Storage (PVC)") manage_storage ;;
    "🩻 Raio-X da Imagem (Dive)") image_xray ;;
    "🕸️ Sniffer de Rede (Ao Vivo)") network_sniffer ;;
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
      [[ -n "$pod" && -n "$local_p" && -n "$pod_p" ]] && (kubectl port-forward pod/"$pod" -n "$ns" "$local_p":"$pod_p" || { gum style --foreground 160 "❌ Erro no túnel. O Pod está rodando?"; sleep 3; }) ;;
    "📊 Métricas")
      if ! kubectl get --raw "/apis/metrics.k8s.io/v1beta1" &>/dev/null; then
        gum style --foreground 160 "❌ Erro: O 'Metrics Server' não está instalado."
        read -p "Pressione Enter para voltar..."
      else
        kubectl top nodes
        kubectl top pods -n "$ns" --sort-by=cpu | head -n 11 2>/dev/null || true
        read -p "Enter..."
      fi ;;
    "🌐 Contexto/Namespace")
      sub=$(printf "Contexto\nNamespace" | fzf)
      [[ "$sub" == "Contexto" ]] && { 
        ctx=$(kubectl config get-contexts -o name | fzf)
        [[ -n "$ctx" ]] && kubectl config use-context "$ctx" >/dev/null; ns=$(get_current_ns); 
      } || {
        ns_temp=$(kubectl get ns -o name | sed 's|namespace/||' | fzf)
        if [[ -n "$ns_temp" ]]; then
          kubectl config set-context --current --namespace="$ns_temp" >/dev/null
          ns="$ns_temp"
        fi
      } ;;
    "➕ Criar Namespace") create_namespace ;;
    "💾 Backup")
      ts=$(date +%s); mkdir -p "$BASE_DIR/backups/$ns"
      kubectl get cm,secret -n "$ns" -o yaml > "$BASE_DIR/backups/$ns/backup-$ts.yaml"
      sleep 1 ;;
    "❌ Sair") exit 0 ;;
  esac
done