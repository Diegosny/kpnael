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
    elif command -v batcat &>/dev/null; then 
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

hpa_radar() {
  local acao=$(gum choose "📊 Status Real-Time (Alvos e Réplicas)" "📜 Cronômetro de Eventos (Logs)" "⚠️  Scanner de Prontidão (Requests)" "🔥 Forçar Carga (Stress Test CPU)" "❌ Voltar")
  [[ -z "$acao" || "$acao" == "❌ Voltar" ]] && return

  case "$acao" in
    "📊 Status Real-Time (Alvos e Réplicas)")
      gum style --foreground 212 "📈 Status dos HPAs no namespace: $ns"
      local hpa_data=$(kubectl get hpa -n "$ns" 2>/dev/null)
      if [[ -z "$hpa_data" || "$hpa_data" == *"No resources found"* ]]; then
         gum style --foreground 160 "❌ Nenhum HPA configurado neste namespace."
         sleep 2; return
      fi
      if command -v bat &>/dev/null; then
        echo "$hpa_data" | bat -l bash --style=plain --paging=always
      elif command -v batcat &>/dev/null; then
        echo "$hpa_data" | batcat -l bash --style=plain --paging=always
      else
        echo "$hpa_data" | gum pager
      fi
      ;;
    "📜 Cronômetro de Eventos (Logs)")
      local hpa=$(kubectl get hpa -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' | fzf --prompt="Selecione o HPA > ")
      [[ -z "$hpa" ]] && return
      gum style --foreground 212 "⏱️ Eventos de Escalabilidade para: $hpa"
      local events=$(kubectl describe hpa "$hpa" -n "$ns" | grep -A 50 "Events:")
      if command -v bat &>/dev/null; then
        echo "$events" | bat -l yaml --style=plain --paging=always
      elif command -v batcat &>/dev/null; then
        echo "$events" | batcat -l yaml --style=plain --paging=always
      else
        echo "$events" | gum pager
      fi
      ;;
    "⚠️  Scanner de Prontidão (Requests)")
      gum style --foreground 212 "⚠️  Verificando se os Pods têm 'Requests' de CPU definidos (Obrigatório para o HPA funcionar)..."
      local audit=$(kubectl get pods -n "$ns" -o custom-columns="POD:.metadata.name,CPU-REQ:.spec.containers[*].resources.requests.cpu,MEM-REQ:.spec.containers[*].resources.requests.memory" | awk '{if (NR>1) { if ($2=="<none>" || $3=="<none>") print "❌ CEGO: " $0; else print "✅ PRONTO: " $0 } else print $0}')
      if command -v bat &>/dev/null; then
        echo "$audit" | bat -l bash --style=plain --paging=always
      elif command -v batcat &>/dev/null; then
        echo "$audit" | batcat -l bash --style=plain --paging=always
      else
        echo "$audit" | gum pager
      fi
      ;;
    "🔥 Forçar Carga (Stress Test CPU)")
      local pod=$(select_resource "pod" "📦")
      [[ -z "$pod" ]] && return
      local cont=$(select_container "$pod")
      [[ -z "$cont" ]] && return
      
      gum style --foreground 160 "🔥 ATENÇÃO: Isso vai forçar 100% de uso de CPU em um core do container por 60s!"
      gum style --foreground 240 "Ideal para testar se a regra do HPA (ex: >70%) vai engatilhar."
      
      if gum confirm "Deseja iniciar o incêndio controlado?"; then
        gum style --foreground 212 "⏳ Queimando CPU... Monitore o status do HPA em outra aba."
        # Roda um loop infinito silencioso em background para esgotar a CPU
        kubectl exec "$pod" -c "$cont" -n "$ns" -- sh -c 'end=$((SECONDS+60)); while [ $SECONDS -lt $end ]; do i=$((i+1)); done' &
        gum spin --title "Processando carga (60s)..." -- sleep 60
        gum style --foreground 46 "✅ Carga finalizada! Verifique o Log de Eventos para medir o tempo do Scale-Up."
        sleep 4
      fi
      ;;
  esac
}

laravel_tinker() {
  local pod=$(select_resource "pod" "📦")
  [[ -z "$pod" ]] && return
  local cont=$(select_container "$pod")
  [[ -z "$cont" ]] && return
  
  gum style --foreground 212 "🐘 Editor Laravel Tinker (Multi-linha)"
  local code=$(gum write --placeholder "Cole seu código PHP. Pressione [Ctrl+D] para enviar ao pod.")
  [[ -z "$code" ]] && return
  
  gum style --foreground 212 "⏳ Executando código no Tinker..."
  local result=$(echo "$code" | kubectl exec -i "$pod" -c "$cont" -n "$ns" -- php artisan tinker 2>&1 | sed -e '/^Psy Shell v/d' -e '/^> /d' -e '/^\. /d' -e '/^>$/d' -e '/^Exit:  Ctrl+D/d')
  
  if command -v bat &>/dev/null; then
    echo "$result" | bat -l php --style=plain --paging=always
  elif command -v batcat &>/dev/null; then
    echo "$result" | batcat -l php --style=plain --paging=always
  else
    echo "$result" | gum pager
  fi
}

database_explorer() {
  local pod=$(select_resource "pod" "📦")
  [[ -z "$pod" ]] && return
  local cont=$(select_container "$pod")
  [[ -z "$cont" ]] && return

  local db_type=$(gum choose "🐘 PostgreSQL" "🐬 MySQL/MariaDB" "❌ Cancelar")
  [[ "$db_type" == "❌ Cancelar" || -z "$db_type" ]] && return

  gum style --foreground 212 "🔑 Credenciais do Banco de Dados"
  local user=$(gum input --placeholder "Usuário (ex: postgres, root):")
  local pass=$(gum input --password --placeholder "Senha:")
  local db=$(gum input --placeholder "Nome do Banco de Dados:")

  [[ -z "$user" || -z "$db" ]] && { gum style --foreground 160 "❌ Usuário e Banco são obrigatórios."; sleep 2; return; }

  local action=$(gum choose "📊 Listar Tabelas" "🔎 Ver Estrutura da Tabela" "💾 Exportar Dump (.sql)")
  [[ -z "$action" ]] && return

  gum style --foreground 212 "⏳ Conectando ao banco de dados no pod $pod..."

  if [[ "$action" == "💾 Exportar Dump (.sql)" ]]; then
    local ts=$(date +%s)
    local dest_dir=$(gum input --placeholder "Pasta destino (Enter para atual):" --value ".")
    [[ -z "$dest_dir" ]] && dest_dir="."
    mkdir -p "$dest_dir" 2>/dev/null || { gum style --foreground 160 "❌ Sem permissão p/ criar pasta."; sleep 2; return; }
    
    local file_out="${dest_dir}/dump-${pod}-${db}-${ts}.sql"
    gum style --foreground 240 "Baixando dados... Isso pode demorar dependendo do tamanho."

    if [[ "$db_type" == *"PostgreSQL"* ]]; then
      kubectl exec "$pod" -c "$cont" -n "$ns" -- sh -c "PGPASSWORD='$pass' pg_dump -U '$user' -d '$db'" > "$file_out" 2>/dev/null
    else
      kubectl exec "$pod" -c "$cont" -n "$ns" -- sh -c "mysqldump -u'$user' -p'$pass' '$db'" > "$file_out" 2>/dev/null
    fi

    if [ -s "$file_out" ]; then
      gum style --foreground 46 "✅ Dump salvo com sucesso em: $file_out"
    else
      gum style --foreground 160 "❌ Erro ao gerar o Dump. Verifique as credenciais."
      rm -f "$file_out"
    fi
    sleep 3
    return
  fi

  local query_cmd=""
  local table=""

  if [[ "$action" == "🔎 Ver Estrutura da Tabela" ]]; then
    table=$(gum input --placeholder "Digite o nome da tabela:")
    [[ -z "$table" ]] && return
  fi

  if [[ "$db_type" == *"PostgreSQL"* ]]; then
    if [[ "$action" == "📊 Listar Tabelas" ]]; then
      query_cmd="PGPASSWORD='$pass' psql -U '$user' -d '$db' -c '\dt'"
    else
      query_cmd="PGPASSWORD='$pass' psql -U '$user' -d '$db' -c '\d $table'"
    fi
  else
    if [[ "$action" == "📊 Listar Tabelas" ]]; then
      query_cmd="mysql -u'$user' -p'$pass' -D '$db' -e 'SHOW TABLES;'"
    else
      query_cmd="mysql -u'$user' -p'$pass' -D '$db' -e 'DESCRIBE $table;'"
    fi
  fi

  local result=$(kubectl exec -i "$pod" -c "$cont" -n "$ns" -- sh -c "$query_cmd" 2>&1 | grep -v "Using a password on the command line interface can be insecure.")

  if command -v bat &>/dev/null; then
    echo "$result" | bat -l sql --style=plain --paging=always
  elif command -v batcat &>/dev/null; then
    echo "$result" | batcat -l sql --style=plain --paging=always
  else
    echo "$result" | gum pager
  fi
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
     gum style --foreground 160 "❌ Docker não detectado na sua máquina local."
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
    "📈 Radar de Auto-Scaling (HPA)" \
    "🐘 Laravel Tinker (Multi-linha)" \
    "🗄️ Explorador de Banco de Dados" \
    "🔓 Decodificar Secret" \
    "⚠️  Radar de Eventos" \
    "✏️  Editor (ConfigMap/Secret)" \
    "🚀 Helm Dashboard" \
    "🕵️  Pod de Debug (Netshoot)" \
    "💀 Caçador de OOMKilled" \
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
    "📈 Radar de Auto-Scaling (HPA)") hpa_radar ;;
    "🐘 Laravel Tinker (Multi-linha)") laravel_tinker ;;
    "🗄️ Explorador de Banco de Dados") database_explorer ;;
    "🔓 Decodificar Secret") decode_secret ;;
    "⚠️  Radar de Eventos") view_events ;;
    "✏️  Editor (ConfigMap/Secret)") live_edit ;;
    "🚀 Helm Dashboard") helm_dashboard ;;
    "🕵️  Pod de Debug (Netshoot)") debug_pod ;;
    "💀 Caçador de OOMKilled") oom_hunter ;;
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