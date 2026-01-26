#!/bin/bash
# =========================================================
# Kpanel PRO - ULTIMATE (Persistente + Novos Recursos)
# =========================================================

set -uo pipefail

# Função para pegar o namespace atual do contexto real do K8s
get_current_ns() {
    kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default"
}

ns=$(get_current_ns)

has_cmd() { command -v "$1" >/dev/null 2>&1; }

view_content() {
    if has_cmd glow; then glow -l yaml; else gum pager; fi
}

# --- Funções de Seleção ---
select_resource() {
    local type=$1
    local prompt=$2
    local selection
    selection=$(kubectl get "$type" -n "$ns" --no-headers 2>/dev/null | fzf --height=40% --reverse --prompt="$prompt > " | awk '{print $1}')
    [[ -z "$selection" ]] && return 1
    echo "$selection"
}

select_container() {
    local pod=$1
    local containers=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}')
    if [[ $(echo "$containers" | wc -w) -gt 1 ]]; then
        local sel=$(echo "$containers" | tr ' ' '\n' | fzf --height=20% --reverse --prompt="Container > ")
        [[ -z "$sel" ]] && return 1
        echo "$sel"
    else
        echo "$containers"
    fi
}

# --- Loop Principal ---
while true; do
    clear
    ns=$(get_current_ns) # Atualiza a variável baseado no config do kubectl
    current_ctx=$(kubectl config current-context 2>/dev/null || echo "N/A")
    
    gum style --border normal --padding "0 1" --border-foreground 57 "🚀 Kpanel PRO | Context: $current_ctx | NS: $ns"

    action=$(printf "%s\n" \
        "📦 Logs Pod (Tail -f)" \
        "💻 Smart Exec (Shell)" \
        "🚀 Deployments" \
        "🔌 Services" \
        "🌐 Ingresses" \
        "🔐 Secrets" \
        "💎 External Secrets" \
        "📝 Ver YAML (Pod)" \
        "🔍 Global Search" \
        "🔄 Mudar Namespace (PERSISTENTE)" \
        "🌐 Mudar Contexto" \
        "💀 Deletar Pod (Force)" \
        "🚪 Sair" | fzf --height=70% --reverse --prompt="Menu > " || echo "ESC")

    [[ "$action" == "ESC" ]] && continue
    [[ "$action" == "🚪 Sair" ]] && exit 0

    case "$action" in
        "📦 Logs Pod (Tail -f)")
            pod=$(select_resource "pods" "Logs") || continue
            container=$(select_container "$pod") || continue
            kubectl logs -f "$pod" -n "$ns" -c "$container" --tail=100
            ;;
        "💻 Smart Exec (Shell)")
            pod=$(select_resource "pods" "Exec") || continue
            container=$(select_container "$pod") || continue
            kubectl exec -it "$pod" -n "$ns" -c "$container" -- /bin/bash || kubectl exec -it "$pod" -n "$ns" -c "$container" -- /bin/sh
            ;;
        "🚀 Deployments")
            deploy=$(select_resource "deploy" "Deployments") || continue
            kubectl describe deploy "$deploy" -n "$ns" | gum pager
            ;;
        "🔌 Services")
            svc=$(select_resource "svc" "Services") || continue
            kubectl describe svc "$svc" -n "$ns" | gum pager
            ;;
        "🌐 Ingresses")
            ing=$(select_resource "ing" "Ingress") || continue
            kubectl describe ing "$ing" -n "$ns" | gum pager
            ;;
        "🔐 Secrets")
            sec=$(select_resource "secrets" "Secrets") || continue
            kubectl get secret "$sec" -n "$ns" -o yaml | view_content
            ;;
        "💎 External Secrets")
            esec=$(select_resource "externalsecrets" "ExternalSecrets") || continue
            kubectl describe externalsecrets "$esec" -n "$ns" | gum pager
            ;;
        "📝 Ver YAML (Pod)")
            pod=$(select_resource "pods" "YAML") || continue
            kubectl get pod "$pod" -n "$ns" -o yaml | view_content
            ;;
        "🔍 Global Search")
            kubectl get pods,deploy,svc,ing,secrets,externalsecrets -A --no-headers 2>/dev/null | \
            fzf --height=80% --reverse --preview "echo {} | awk '{print \$1 \" \" \$2}' | xargs -n2 sh -c 'kubectl describe \$2 -n \$1 | head -30'" || true
            ;;
        "🔄 Mudar Namespace (PERSISTENTE)")
            new_ns=$(kubectl get ns --no-headers | awk '{print $1}' | fzf --prompt="Novo NS > ")
            if [[ -n "$new_ns" ]]; then
                # Define o namespace no contexto atual para persistir após o logout
                kubectl config set-context --current --namespace="$new_ns" >/dev/null
                gum style --foreground 46 "✅ Namespace alterado para $new_ns permanentemente."
            fi
            ;;
        "🌐 Mudar Contexto")
            ctx=$(kubectl config get-contexts -o name | fzf --prompt="Contexto > ")
            [[ -n "$ctx" ]] && kubectl config use-context "$ctx"
            ;;
        "💀 Deletar Pod (Force)")
            pod=$(select_resource "pods" "DELETE") || continue
            gum confirm "Deletar $pod?" && kubectl delete pod "$pod" -n "$ns" --grace-period=0 --force
            ;;
    esac

    echo ""
    gum style --foreground 242 "Pressione qualquer tecla para voltar..."
    read -n 1 -s
done