#!/bin/bash

trap 'printf "\e[?2004l"; clear' EXIT
trap '' SIGTSTP

BASE_DIR="$HOME/.dpnael-dashboard"
BACKUP_DIR="$BASE_DIR/backups"
mkdir -p "$BACKUP_DIR"

PRIMARY_COLOR="#D126F7"
icon_container="📦"
icon_image="🖼️"

msg_success() { gum style --foreground 46 "✔ $1"; sleep 1; }
msg_error() { gum style --foreground 160 "✖ $1"; sleep 2; }

get_preview_cmd() {
  local type="$1"
  if [[ "$type" == "container" ]]; then
    if command -v jq &>/dev/null; then
      echo "docker inspect {} --format '{{json .State}}' | jq . 2>/dev/null || docker inspect {}"
    else
      echo "docker inspect {}"
    fi
  else
    echo "docker history {}"
  fi
}

fzf_select() {
  local type="$1"
  local format="$2"
  local icon="$3"
  local cmd=$([[ "$type" == "container" ]] && echo "docker ps -a" || echo "docker images")
  
  $cmd --format "$format" | awk -v i="$icon" '{print i " " $1}' | sed "s/$icon //" | \
    fzf --prompt="$type > " --height=80% --reverse --border --ansi \
        --preview="$(get_preview_cmd "$type") | head -40" \
        --preview-window=right:60%:hidden \
        --bind "tab:toggle-preview" || echo ""
}

manage_compose() {
  local file=$(find . -maxdepth 2 -name "*compose*.yml" -o -name "*compose*.yaml" 2>/dev/null | grep -v "node_modules" | fzf --prompt="Compose > " --height=30% || echo "")
  [[ -z "$file" ]] && return

  local action=$(printf "🚀 Up\n🛑 Down\n♻️ Restart\n📖 Logs" | fzf --prompt="Ação > " --height=40% || echo "")
  [[ -z "$action" ]] && return
  
  case "${action#* }" in
    "Up")      docker compose -f "$file" up -d && msg_success "Up concluído" ;;
    "Down")    docker compose -f "$file" down && msg_success "Down concluído" ;;
    "Restart") docker compose -f "$file" restart && msg_success "Restart concluído" ;;
    "Logs")    docker compose -f "$file" logs -f --tail=100 | gum pager ;;
  esac
}

set_local_domain() {
  local target=$(fzf_select "container" "{{.Names}}" "$icon_container")
  [[ -z "$target" ]] && return

  local domain=$(gum input --placeholder "Domínio (ex: api.local):")
  [[ -z "$domain" ]] && return

  local ip="127.0.0.1"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo sed -i '' "/[[:space:]]$domain\t# dpnael:/d" /etc/hosts 2>/dev/null || true
  else
    sudo sed -i "/[[:space:]]$domain\t# dpnael:/d" /etc/hosts 2>/dev/null || true
  fi
  
  echo -e "$ip\t$domain\t# dpnael:$target" | sudo tee -a /etc/hosts > /dev/null
  
  msg_success "Domínio mapeado!"
  gum style --foreground 240 "⚠️ Dica: No navegador, não esqueça de colocar a porta exposta! (Ex: http://$domain:3000)"
  sleep 4
}

remove_local_domain() {
  local entry=$(grep "# dpnael:" /etc/hosts | fzf --prompt="Remover > " --height=40% --reverse || echo "")
  [[ -z "$entry" ]] && return
  local domain=$(echo "$entry" | awk '{print $2}')

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo sed -i '' "/[[:space:]]$domain\t# dpnael:/d" /etc/hosts
  else
    sudo sed -i "/[[:space:]]$domain\t# dpnael:/d" /etc/hosts
  fi
  msg_success "Domínio removido do /etc/hosts"
}

backup_image() {
  local img=$(fzf_select "image" "{{.Repository}}:{{.Tag}}" "$icon_image")
  [[ -z "$img" ]] && return
  local filename=$(echo "$img" | tr ': /' '---').tar
  gum spin --title "Exportando..." -- docker save -o "$BACKUP_DIR/$filename" "$img"
  msg_success "Salvo em $BACKUP_DIR"
}

scan_image() {
  local img=$(fzf_select "image" "{{.Repository}}:{{.Tag}}" "$icon_image")
  [[ -z "$img" ]] && return
  
  gum style --foreground 212 "🔍 Escaneando $img por vulnerabilidades..."
  
  if docker scout --help &>/dev/null; then
     docker scout cves "$img" | gum pager || { msg_error "Erro no Docker Scout."; sleep 2; }
  else
     gum style --foreground 240 "Docker Scout não detectado. Invocando Trivy..."
     docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image "$img" | gum pager || { msg_error "Falha no scan com Trivy."; sleep 2; }
  fi
}

image_xray() {
  local img=$(fzf_select "image" "{{.Repository}}:{{.Tag}}" "$icon_image")
  [[ -z "$img" ]] && return
  
  gum style --foreground 212 "🩻 Preparando motor Raio-X (Dive) para: $img"
  sleep 2
  
  docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive:latest "$img" || { msg_error "Falha ao executar o Raio-X."; sleep 2; }
}

network_sniffer() {
  local target=$(fzf_select "container" "{{.Names}}" "$icon_container")
  [[ -z "$target" ]] && return
  
  local port=$(gum input --placeholder "Porta para escutar (ex: 80) ou deixe em branco para todas:")
  local filter=""
  [[ -n "$port" ]] && filter="port $port"
  
  gum style --foreground 212 "🕸️ Injetando Sniffer de Rede (netshoot) em: $target"
  sleep 3
  
  docker run -it --rm --network "container:$target" nicolaka/netshoot tcpdump -i any -A -nn $filter || { msg_error "Falha ao executar o sniffer."; sleep 2; }
}

container_to_compose() {
  local target=$(fzf_select "container" "{{.Names}}" "$icon_container")
  [[ -z "$target" ]] && return
  
  local dest_dir=$(gum input --placeholder "Pasta de destino (Enter para pasta atual):" --value ".")
  [[ -z "$dest_dir" ]] && dest_dir="."
  
  mkdir -p "$dest_dir" 2>/dev/null || { msg_error "Sem permissão p/ criar a pasta."; return; }
  local file_out="${dest_dir}/docker-compose-${target}.yml"
  
  gum style --foreground 212 "🐙 Engenharia reversa (Compose) no container: $target"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock red5d/docker-autocompose "$target" > "$file_out" 2> "/tmp/dpnael-compose-error.log" || true
  
  if [ -s "$file_out" ]; then
    if grep -q "Traceback" "$file_out"; then
      gum style --foreground 160 "❌ Erro ao gerar YAML. O container pode estar usando rede incompatível."
      rm -f "$file_out"
      sleep 4
    else
      msg_success "Salvo em: $file_out"
    fi
  else
    gum style --foreground 160 "❌ Erro. O arquivo não pôde ser criado."
    rm -f "$file_out"
    sleep 4
  fi
}

network_map() {
  local net=$(docker network ls --format "{{.Name}}" | fzf --prompt="Inspecionar Rede > " --preview="docker network inspect {}" || echo "")
  [[ -z "$net" ]] && return
  
  gum style --foreground 212 "🌐 Containers conectados na rede: $net"
  docker network inspect "$net" --format '{{range .Containers}} - {{.Name}} (IP: {{.IPv4Address}}){{println}}{{else}}Nenhum container ativo nesta rede.{{end}}' | gum pager || { msg_error "Erro ao inspecionar a rede."; }
}

laravel_tinker() {
  local target=$(fzf_select "container" "{{.Names}}" "$icon_container")
  [[ -z "$target" ]] && return
  
  gum style --foreground 212 "🐘 Editor Laravel Tinker (Multi-linha)"
  local code=$(gum write --placeholder "Cole seu código PHP. Pressione [Ctrl+D] para enviar.")
  [[ -z "$code" ]] && return
  
  gum style --foreground 212 "⏳ Executando código no Tinker..."
  local result=$(echo "$code" | docker exec -i "$target" php artisan tinker 2>&1 | sed -e '/^Psy Shell v/d' -e '/^> /d' -e '/^\. /d' -e '/^>$/d' -e '/^Exit:  Ctrl+D/d')
  
  if command -v bat &>/dev/null; then
    echo "$result" | bat -l php --style=plain --paging=always
  elif command -v batcat &>/dev/null; then
    echo "$result" | batcat -l php --style=plain --paging=always
  else
    echo "$result" | gum pager
  fi
}

database_explorer() {
  local target=$(fzf_select "container" "{{.Names}}" "$icon_container")
  [[ -z "$target" ]] && return

  local db_type=$(gum choose "🐘 PostgreSQL" "🐬 MySQL/MariaDB" "❌ Cancelar")
  [[ "$db_type" == "❌ Cancelar" || -z "$db_type" ]] && return

  gum style --foreground 212 "🔑 Credenciais do Banco de Dados"
  local user=$(gum input --placeholder "Usuário (ex: postgres, root):")
  local pass=$(gum input --password --placeholder "Senha:")
  local db=$(gum input --placeholder "Nome do Banco de Dados:")

  [[ -z "$user" || -z "$db" ]] && { msg_error "Usuário e Banco são obrigatórios."; return; }

  local action=$(gum choose "📊 Listar Tabelas" "🔎 Ver Estrutura da Tabela" "💾 Exportar Dump (.sql)")
  [[ -z "$action" ]] && return

  gum style --foreground 212 "⏳ Conectando ao banco de dados no container $target..."

  if [[ "$action" == "💾 Exportar Dump (.sql)" ]]; then
    local ts=$(date +%s)
    local dest_dir=$(gum input --placeholder "Pasta destino (Enter para atual):" --value ".")
    [[ -z "$dest_dir" ]] && dest_dir="."
    mkdir -p "$dest_dir" 2>/dev/null || { msg_error "Sem permissão p/ criar pasta."; return; }
    
    local file_out="${dest_dir}/dump-${target}-${db}-${ts}.sql"

    if [[ "$db_type" == *"PostgreSQL"* ]]; then
      docker exec -i "$target" sh -c "PGPASSWORD='$pass' pg_dump -U '$user' -d '$db'" > "$file_out" 2>/dev/null
    else
      docker exec -i "$target" sh -c "mysqldump -u'$user' -p'$pass' '$db'" > "$file_out" 2>/dev/null
    fi

    if [ -s "$file_out" ]; then
      msg_success "Dump salvo em: $file_out"
    else
      msg_error "Erro ao gerar o Dump. Verifique as credenciais."
      rm -f "$file_out"
    fi
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

  local result=$(docker exec -i "$target" sh -c "$query_cmd" 2>&1 | grep -v "Using a password on the command line interface can be insecure.")

  if command -v bat &>/dev/null; then
    echo "$result" | bat -l sql --style=plain --paging=always
  elif command -v batcat &>/dev/null; then
    echo "$result" | batcat -l sql --style=plain --paging=always
  else
    echo "$result" | gum pager
  fi
}

run_quick_container() {
  gum style --foreground 212 "🚀 Assistente de Criação Rápida de Container"
  
  local image=$(gum input --placeholder "Nome da imagem (ex: nginx:alpine, redis:latest):")
  [[ -z "$image" ]] && return
  
  local name=$(gum input --placeholder "Nome do container (Opcional, Enter para aleatório):")
  local ports=$(gum input --placeholder "Mapeamento de portas (ex: 8080:80) (Opcional):")
  local envs=$(gum input --placeholder "Variáveis/Flags extras (ex: -e MYSQL_ROOT_PASSWORD=123) (Opcional):")
  
  local cmd="docker run -d"
  
  if [[ -n "$name" ]]; then
    cmd="$cmd --name \"$name\""
  fi
  
  if [[ -n "$ports" ]]; then
    cmd="$cmd -p \"$ports\""
  fi
  
  if [[ -n "$envs" ]]; then
    cmd="$cmd $envs"
  fi
  
  cmd="$cmd \"$image\""
  
  gum style --foreground 240 "Executando: $cmd"
  
  # Usamos o eval para que as flags enviadas em $envs sejam interpretadas corretamente pelo bash
  if eval "$cmd" >/dev/null; then
    msg_success "Container iniciado com sucesso!"
  else
    msg_error "Falha ao iniciar. Verifique se a imagem existe ou se a porta já está em uso."
  fi
}

while true; do
  clear
  printf "\e[?2004l"
  
  stats=$(docker info --format '{{.ContainersRunning}} UP / {{.Containers}} Total' 2>/dev/null || echo "Offline")
  disco=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0B")
  
  gum style --border normal --margin 1 --padding 1 --border-foreground "$PRIMARY_COLOR" "🚀 DPNAEL | $stats | Disco: $disco"

  action=$(printf "%s\n" \
    "🚀 Rodar Container Rápido (Run)" \
    "🔍 Logs" \
    "🐚 Shell" \
    "🐘 Laravel Tinker (Multi-linha)" \
    "🗄️ Explorador de Banco de Dados" \
    "🐙 Compose Local" \
    "🔗 Criar Domínio (/etc/hosts)" \
    "🗑️  Remover Domínio" \
    "📊 Stats de Consumo" \
    "⚡ Restart/Stop" \
    "🖼️  Backup de Imagem" \
    "🛡️  Escanear Imagem (CVEs)" \
    "🩻 Raio-X de Camadas (Dive)" \
    "🕸️ Sniffer de Rede (Ao Vivo)" \
    "🧬 Reverter Container p/ Compose" \
    "🌐 Mapa de Redes" \
    "🧹 Faxina (Prune)" \
    "❌ Remover Container" \
    "🚀 Sair" \
    | fzf --prompt="Menu > " --height=85% --reverse --border --ansi || echo "")

  case "$action" in
    "🚀 Rodar Container Rápido (Run)") run_quick_container ;;
    "🔍 Logs")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && (docker logs -f --tail 100 "$target" | gum pager || { msg_error "Erro ao ler logs."; }) ;;
    "🐚 Shell")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && (docker exec -it "$target" bash 2>/dev/null || docker exec -it "$target" sh || { msg_error "Erro ao entrar no container."; }) ;;
    "🐘 Laravel Tinker (Multi-linha)") laravel_tinker ;;
    "🗄️ Explorador de Banco de Dados") database_explorer ;;
    "🐙 Compose Local") manage_compose ;;
    "🔗 Criar Domínio (/etc/hosts)") set_local_domain ;;
    "🗑️  Remover Domínio") remove_local_domain ;;
    "📊 Stats de Consumo") docker stats ;;
    "⚡ Restart/Stop")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      if [[ -n "$target" ]]; then
        op=$(printf "Restart\nStop" | fzf --prompt="Ação > " --height=30% || echo "")
        [[ "$op" == "Restart" ]] && docker restart "$target" >/dev/null && msg_success "Reiniciado"
        [[ "$op" == "Stop" ]] && docker stop "$target" >/dev/null && msg_success "Parado"
      fi ;;
    "🖼️  Backup de Imagem") backup_image ;;
    "🛡️  Escanear Imagem (CVEs)") scan_image ;;
    "🩻 Raio-X de Camadas (Dive)") image_xray ;;
    "🕸️ Sniffer de Rede (Ao Vivo)") network_sniffer ;;
    "🧬 Reverter Container p/ Compose") container_to_compose ;;
    "🌐 Mapa de Redes") network_map ;;
    "🧹 Faxina (Prune)")
      if gum confirm "Limpar sistema?"; then
        docker system prune -f >/dev/null && msg_success "Limpeza concluída"
      fi ;;
    "❌ Remover Container")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && gum confirm "Deletar container $target?" && docker rm -f "$target" >/dev/null && msg_success "Removido" ;;
    "🚀 Sair") clear; exit 0 ;;
  esac
done