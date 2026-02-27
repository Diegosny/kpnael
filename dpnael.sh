#!/bin/bash

# Removemos o set -e para que comandos com erro não matem o painel
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

  local ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$target" 2>/dev/null || echo "")
  [[ -z "$ip" ]] && { msg_error "Container sem IP interno (Bridge) ativo."; return; }

  local domain=$(gum input --placeholder "Domínio (ex: api.local):")
  [[ -z "$domain" ]] && return

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo sed -i '' "/[[:space:]]$domain\t# dpnael:/d" /etc/hosts 2>/dev/null || true
  else
    sudo sed -i "/[[:space:]]$domain\t# dpnael:/d" /etc/hosts 2>/dev/null || true
  fi
  
  echo -e "$ip\t$domain\t# dpnael:$target" | sudo tee -a /etc/hosts > /dev/null
  msg_success "Domínio mapeado!"
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
     gum style --foreground 240 "Docker Scout não detectado. Invocando Trivy (Aqua Security)..."
     docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image "$img" | gum pager || { msg_error "Falha no scan com Trivy."; sleep 2; }
  fi
}

container_to_compose() {
  local target=$(fzf_select "container" "{{.Names}}" "$icon_container")
  [[ -z "$target" ]] && return
  
  # Pergunta a pasta de destino (o default é '.' que significa pasta atual)
  local dest_dir=$(gum input --placeholder "Pasta de destino (Enter para pasta atual):" --value ".")
  [[ -z "$dest_dir" ]] && dest_dir="."
  
  # Cria a pasta caso ela não exista (ignora erros se já existir)
  mkdir -p "$dest_dir" 2>/dev/null || { msg_error "Sem permissão para criar a pasta $dest_dir."; return; }
  
  local file_out="${dest_dir}/docker-compose-${target}.yml"
  
  gum style --foreground 212 "🐙 Engenharia reversa (Compose) no container: $target"
  gum style --foreground 240 "Lendo configurações e salvando em: $file_out"
  
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock red5d/docker-autocompose "$target" > "$file_out" 2> "/tmp/dpnael-compose-error.log" || true
  
  if [ -s "$file_out" ]; then
    # Checagem de segurança: verifica se o script Python não guspiu o erro "Traceback" dentro do YAML
    if grep -q "Traceback" "$file_out"; then
      gum style --foreground 160 "❌ Erro ao gerar YAML. O container pode estar usando uma rede incompatível (ex: host)."
      cat "$file_out" | tail -n 5
      rm -f "$file_out"
      sleep 4
    else
      msg_success "Salvo com sucesso em: $file_out"
    fi
  else
    gum style --foreground 160 "❌ Erro ao gerar YAML. O arquivo não pôde ser criado."
    cat "/tmp/dpnael-compose-error.log" | tail -n 5
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

while true; do
  clear
  printf "\e[?2004l"
  
  stats=$(docker info --format '{{.ContainersRunning}} UP / {{.Containers}} Total' 2>/dev/null || echo "Offline")
  disco=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0B")
  
  gum style --border normal --margin 1 --padding 1 --border-foreground "$PRIMARY_COLOR" "🚀 DPNAEL | $stats | Disco: $disco"

  action=$(printf "%s\n" \
    "🔍 Logs" \
    "🐚 Shell" \
    "🐙 Compose Local" \
    "🔗 Criar Domínio (/etc/hosts)" \
    "🗑️  Remover Domínio" \
    "📊 Stats de Consumo" \
    "⚡ Restart/Stop" \
    "🖼️  Backup de Imagem" \
    "🛡️  Escanear Imagem (CVEs)" \
    "🧬 Reverter Container p/ Compose" \
    "🌐 Mapa de Redes" \
    "🧹 Faxina (Prune)" \
    "❌ Remover Container" \
    "🚀 Sair" \
    | fzf --prompt="Menu > " --height=85% --reverse --border --ansi || echo "")

  case "$action" in
    "🔍 Logs")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && (docker logs -f --tail 100 "$target" | gum pager || { msg_error "Erro ao ler logs."; }) ;;
    "🐚 Shell")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && (docker exec -it "$target" bash 2>/dev/null || docker exec -it "$target" sh || { msg_error "Erro ao entrar no container."; }) ;;
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
    "🧬 Reverter Container p/ Compose") container_to_compose ;;
    "🌐 Mapa de Redes") network_map ;;
    "🧹 Faxina (Prune)")
      if gum confirm "Limpar sistema (containers parados e cache não utilizado)?"; then
        docker system prune -f >/dev/null && msg_success "Limpeza concluída"
      fi ;;
    "❌ Remover Container")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && gum confirm "Deletar container $target?" && docker rm -f "$target" >/dev/null && msg_success "Removido" ;;
    "🚀 Sair") clear; exit 0 ;;
  esac
done