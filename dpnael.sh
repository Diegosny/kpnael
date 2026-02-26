#!/bin/bash
# =========================================================
# DPANEL PRO ULTRA - Docker Dashboard (Leve & Otimizado)
# =========================================================

set -euo pipefail

# Configurações
BASE_DIR="$HOME/.dpanel-dashboard"
BACKUP_DIR="$BASE_DIR/backups"
mkdir -p "$BACKUP_DIR"

# Ícones
icon_container="📦"
icon_image="🖼️"

# --- Funções de Interface ---

fzf_with_preview() {
  local prompt="$1"
  local type="$2"
  local preview_cmd=""

  # Otimização: Evita jq se não estiver instalado para não gerar erros no preview
  if command -v jq &>/dev/null; then
    local fmt="--format '{{json .State}}' | jq ."
  else
    local fmt=""
  fi

  case "$type" in
    container) preview_cmd="docker inspect {} $fmt 2>/dev/null || docker inspect {}" ;;
    image)     preview_cmd="docker history {}" ;;
    *)         preview_cmd="echo 'Sem preview disponível'" ;;
  esac

  fzf \
    --prompt="$prompt > " \
    --height=80% \
    --reverse \
    --border \
    --ansi \
    --preview="$preview_cmd | head -40" \
    --preview-window=right:60%:hidden \
    --bind "tab:toggle-preview"
}

select_resource() {
  local type="$1"
  local format="$2"
  local icon="$3"
  
  local result=$(
    if [[ "$type" == "container" ]]; then
      docker ps -a --format "$format"
    else
      docker images --format "$format"
    fi | awk -v i="$icon" '{print i " " $1}' | sed "s/$icon //" | fzf_with_preview "$type" "$type" || echo ""
  )
  echo "$result"
}

# --- Funcionalidades ---

manage_compose() {
  local file=$(ls | grep -E "^docker-compose\.(yml|yaml)$|^compose\.(yml|yaml)$" | fzf --prompt="Arquivo Compose > " --height=30% || echo "")
  [[ -z "$file" ]] && return

  local action=$(printf "Up (Detached)\nDown (Stop/Remove)\nRestart\nLogs" | fzf --prompt="Ação > " --height=40%)
  [[ -z "$action" ]] && return
  
  case "$action" in
    "Up (Detached)")      docker compose -f "$file" up -d ;;
    "Down (Stop/Remove)") docker compose -f "$file" down ;;
    "Restart")            docker compose -f "$file" restart ;;
    "Logs")               docker compose -f "$file" logs -f --tail=100 | gum pager ;;
  esac
}

set_local_domain() {
  local target=$(select_resource "container" "{{.Names}}" "$icon_container")
  [[ -z "$target" ]] && return

  local ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$target" 2>/dev/null || echo "")
  
  if [[ -z "$ip" ]]; then
    gum style --foreground 160 "❌ Falha ao obter IP. Container pode estar parado ou usar host network."
    sleep 2; return
  fi

  local domain=$(gum input --placeholder "Digite o domínio (ex: meuapp.local)")
  [[ -z "$domain" ]] && return

  gum style --foreground 212 "🔐 Precisamos de permissão (sudo) para atualizar o /etc/hosts"
  
  # Lógica cruzada Mac/Linux simplificada
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo sed -i '' "/[[:space:]]$domain\t# dpanel:/d" /etc/hosts 2>/dev/null || true
  else
    sudo sed -i "/[[:space:]]$domain\t# dpanel:/d" /etc/hosts 2>/dev/null || true
  fi
  
  echo -e "$ip\t$domain\t# dpanel:$target" | sudo tee -a /etc/hosts > /dev/null
  gum style --foreground 46 "✅ Mapeado: http://$domain -> $ip ($target)"
  sleep 2
}

remove_local_domain() {
  local entry=$(grep "# dpanel:" /etc/hosts | fzf --prompt="Remover > " --height=40% --reverse || echo "")
  [[ -z "$entry" ]] && return

  local domain=$(echo "$entry" | awk '{print $2}')
  gum style --foreground 212 "🔐 Removendo '$domain' (requer sudo)..."

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo sed -i '' "/[[:space:]]$domain\t# dpanel:/d" /etc/hosts
  else
    sudo sed -i "/[[:space:]]$domain\t# dpanel:/d" /etc/hosts
  fi
  gum style --foreground 46 "🗑️ Domínio removido com sucesso!"
  sleep 1
}

backup_image() {
  local img=$(select_resource "image" "{{.Repository}}:{{.Tag}}" "$icon_image")
  [[ -z "$img" ]] && return

  local filename=$(echo "$img" | tr ': /' '---').tar
  gum spin --title "Exportando imagem para $filename..." -- docker save -o "$BACKUP_DIR/$filename" "$img"
  gum style --foreground 46 "💾 Backup concluído em: $BACKUP_DIR/"
  sleep 2
}

# --- Loop Principal ---

while true; do
  clear
  # Otimização: Chama o docker info apenas uma vez para pegar os números em vez de rodar docker ps 3 vezes
  stats=$(docker info --format '{{.ContainersRunning}} ativos / {{.Containers}} total | Imagens: {{.Images}}' 2>/dev/null || echo "Docker indisponível")
  
  gum style --border normal --margin 1 --padding 1 --border-foreground 212 "
🚀 **DPANEL PRO ULTRA**

**Status:** $stats
**Disco:** $(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "0B")

TAB → Toggle Preview | ESC → Sair de menus
"

  action=$(printf "%s\n" \
    "🔍 Logs de Container" \
    "🐚 Shell (Exec)" \
    "🐙 Docker Compose (Gerenciar)" \
    "🔗 Criar Domínio Local (/etc/hosts)" \
    "🗑️  Remover Domínio Local" \
    "📊 Stats (Recursos Ao Vivo)" \
    "⚡ Restart/Stop Container" \
    "🖼️  Backup de Imagem (.tar)" \
    "🧹 Faxina (Prune System)" \
    "❌ Remover Container" \
    "🚀 Sair" \
    | fzf --prompt="Menu > " --height=80% --reverse --border)

  case "$action" in
    "🔍 Logs de Container")
      target=$(select_resource "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && docker logs -f --tail 100 "$target" | gum pager ;;

    "🐚 Shell (Exec)")
      target=$(select_resource "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && (docker exec -it "$target" bash 2>/dev/null || docker exec -it "$target" sh) ;;

    "🐙 Docker Compose (Gerenciar)") manage_compose ;;
    "🔗 Criar Domínio Local (/etc/hosts)") set_local_domain ;;
    "🗑️  Remover Domínio Local") remove_local_domain ;;
    
    "📊 Stats (Recursos Ao Vivo)") 
      docker stats ;;

    "⚡ Restart/Stop Container")
      target=$(select_resource "container" "{{.Names}}" "$icon_container")
      if [[ -n "$target" ]]; then
        op=$(printf "Restart\nStop" | fzf --prompt="Ação > " --height=30%)
        [[ "$op" == "Restart" ]] && docker restart "$target"
        [[ "$op" == "Stop" ]] && docker stop "$target"
      fi ;;

    "🖼️  Backup de Imagem (.tar)") backup_image ;;

    "🧹 Faxina (Prune System)")
      if gum confirm "Remover containers parados e cache não usado?"; then
        docker system prune -f
        sleep 2
      fi ;;

    "❌ Remover Container")
      target=$(select_resource "container" "{{.Names}}" "$icon_container")
      [[ -n "$target" ]] && gum confirm "Deletar container $target?" && docker rm -f "$target" ;;

    "🚀 Sair") exit 0 ;;
  esac
done
