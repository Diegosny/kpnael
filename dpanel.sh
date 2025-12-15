#!/bin/bash

set -euo pipefail

BASE_DIR="$HOME/.docker-dashboard"
CACHE_DIR="$BASE_DIR/cache"
FAV_DIR="$BASE_DIR/favs"
BACKUP_DIR="$BASE_DIR/backups"

mkdir -p "$CACHE_DIR" "$FAV_DIR" "$BACKUP_DIR"

icon_container="📦"
icon_image="🖼️"
icon_volume="💾"
icon_network="🌐"

fzf_with_preview() {
  local prompt="$1"
  local type="$2"

  local preview_cmd=""
  case "$type" in
    container)
      preview_cmd="docker inspect {} | head -20"
      ;;
    image)
      preview_cmd="docker image inspect {} | head -20"
      ;;
    volume)
      preview_cmd="docker volume inspect {} | head -20"
      ;;
    network)
      preview_cmd="docker network inspect {} | head -20"
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

select_container() {
  docker ps -a --format "{{.Names}}" \
    | awk "{print \"$icon_container \" \$1}" \
    | sed "s/$icon_container //" \
    | fzf_with_preview "Container" "container"
}

select_image() {
  docker images --format "{{.Repository}}:{{.Tag}}" \
    | awk "{print \"$icon_image \" \$1}" \
    | sed "s/$icon_image //" \
    | fzf_with_preview "Imagem" "image"
}

select_volume() {
  docker volume ls -q \
    | awk "{print \"$icon_volume \" \$1}" \
    | sed "s/$icon_volume //" \
    | fzf_with_preview "Volume" "volume"
}

select_network() {
  docker network ls --format "{{.Name}}" \
    | awk "{print \"$icon_network \" \$1}" \
    | sed "s/$icon_network //" \
    | fzf_with_preview "Network" "network"
}

dashboard() {
  clear
  gum style --border normal --margin 1 --padding 1 --border-foreground 212 "
🚀 Dpanel PRO - Docker Dashboard

Containers: $(docker ps -q | wc -l)
Images: $(docker images -q | wc -l)
Volumes: $(docker volume ls -q | wc -l)
Networks: $(docker network ls -q | wc -l)

TAB → Preview | Busca fuzzy em tudo
"
}

while true; do
  dashboard

  action=$(printf "%s\n" \
    "Listar Containers" \
    "Logs de Container" \
    "Exec Bash no Container" \
    "Reiniciar Container" \
    "Remover Container" \
    "Listar Imagens" \
    "Remover Imagem" \
    "Listar Volumes" \
    "Remover Volume" \
    "Listar Networks" \
    "Sair" \
    | fzf --prompt="Menu > " --height=70% --reverse --border)

  case "$action" in
    "Listar Containers") docker ps -a | gum pager ;;
    "Logs de Container") docker logs -f "$(select_container)" | gum pager ;;
    "Exec Bash no Container") docker exec -it "$(select_container)" bash ;;
    "Reiniciar Container") docker restart "$(select_container)" ;;
    "Remover Container") docker rm -f "$(select_container)" ;;
    "Listar Imagens") docker images | gum pager ;;
    "Remover Imagem") docker rmi "$(select_image)" ;;
    "Listar Volumes") docker volume ls | gum pager ;;
    "Remover Volume") docker volume rm "$(select_volume)" ;;
    "Listar Networks") docker network ls | gum pager ;;
    "Sair") exit 0 ;;
  esac

  gum confirm "Voltar ao menu?" || exit 0
done
