#!/bin/bash

set -euo pipefail

BASE_DIR="$HOME/.dpnael-dashboard"
BACKUP_DIR="$BASE_DIR/backups"
mkdir -p "$BACKUP_DIR"

PRIMARY_COLOR="#D126F7"
icon_container="📦"
icon_image="🖼️"

trap 'clear; exit' INT TERM

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
    "Up")      docker compose -f "$file" up -d && msg_success "Up" ;;
    "Down")    docker compose -f "$file" down && msg_success "Down" ;;
    "Restart") docker compose -f "$file" restart && msg_success "Restart" ;;
    "Logs")    docker compose -f "$file" logs -f --tail=100 | gum pager ;;
  esac
}

set_local_domain() {
  local target=$(fzf_select "container" "{{.Names}}" "$icon_container")
  [[ -z "$target" ]] && return

  local ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$target" 2>/dev/null || echo "")
  [[ -z "$ip" ]] && { msg_error "Sem IP"; return; }

  local domain=$(gum input --placeholder "Domínio:")
  [[ -z "$domain" ]] && return

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo sed -i '' "/[[:space:]]$domain\t# dpanel:/d" /etc/hosts 2>/dev/null || true
  else
    sudo sed -i "/[[:space:]]$domain\t# dpanel:/d" /etc/hosts 2>/dev/null || true
  fi
  
  echo -e "$ip\t$domain\t# dpanel:$target" | sudo tee -a /etc/hosts > /dev/null
  msg_success "Mapeado"
}

remove_local_domain() {
  local entry=$(grep "# dpanel:" /etc/hosts | fzf --prompt="Remover > " --height=40% --reverse || echo "")
  [[ -z "$entry" ]] && return
  local domain=$(echo "$entry" | awk '{print $2}')

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo sed -i '' "/[[:space:]]$domain\t# dpanel:/d" /etc/hosts
  else
    sudo sed -i "/[[:space:]]$domain\t# dpanel:/d" /etc/hosts
  fi
  msg_success "Removido"
}

backup_image() {
  local img=$(fzf_select "image" "{{.Repository}}:{{.Tag}}" "$icon_image")
  [[ -z "$img" ]] && return
  local filename=$(echo "$img" | tr ': /' '---').tar
  gum spin --title "Exportando..." -- docker save -o "$BACKUP_DIR/$filename" "$img"
  msg_success "Salvo em $BACKUP_DIR"
}

while true; do
  clear
  stats=$(docker info --format '{{.ContainersRunning}} UP / {{.Containers}} Total' 2>/dev/null || echo "Offline")
  disco=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0B")
  
  gum style --border normal --margin 1 --padding 1 --border-foreground "$PRIMARY_COLOR" "🚀 DPNAEL | $stats | $disco"

  action=$(printf "%s\n" \
    "🔍 Logs" \
    "🐚 Shell" \
    "🐙 Compose" \
    "🔗 Criar Domínio" \
    "🗑️  Remover Domínio" \
    "📊 Stats" \
    "⚡ Restart/Stop" \
    "🖼️  Backup" \
    "🧹 Faxina" \
    "❌ Remover Container" \
    "🚀 Sair" \
    | fzf --prompt="Menu > " --height=80% --reverse --border --ansi || echo "")

  case "$action" in
    "🔍 Logs")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && docker logs -f --tail 100 "$target" | gum pager ;;
    "🐚 Shell")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && (docker exec -it "$target" bash 2>/dev/null || docker exec -it "$target" sh) ;;
    "🐙 Compose") manage_compose ;;
    "🔗 Criar Domínio") set_local_domain ;;
    "🗑️  Remover Domínio") remove_local_domain ;;
    "📊 Stats") docker stats ;;
    "⚡ Restart/Stop")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      if [[ -n "$target" ]]; then
        op=$(printf "Restart\nStop" | fzf --prompt="Ação > " --height=30% || echo "")
        [[ "$op" == "Restart" ]] && docker restart "$target" >/dev/null && msg_success "OK"
        [[ "$op" == "Stop" ]] && docker stop "$target" >/dev/null && msg_success "OK"
      fi ;;
    "🖼️  Backup") backup_image ;;
    "🧹 Faxina")
      if gum confirm "Limpar tudo?"; then
        docker system prune -f >/dev/null && msg_success "Limpo"
      fi ;;
    "❌ Remover Container")
      target=$(fzf_select "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && gum confirm "Deletar?" && docker rm -f "$target" >/dev/null && msg_success "OK" ;;
    "🚀 Sair") clear; exit 0 ;;
  esac
done