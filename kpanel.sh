#!/bin/bash

# ======================================================
#     Kubernetes Dashboard Kpanel
# ======================================================

# Namespace atual
ns=$(kubectl config view --minify -o jsonpath='{..namespace}')
ns=${ns:-default}

# Pasta para salvar favoritos e backups
mkdir -p ~/.k8s-dashboard/backups
mkdir -p ~/.k8s-dashboard/favs

# ---------- FUNÇÕES ESSENCIAIS ----------

select_context() {
  ctx=$(kubectl config get-contexts --no-headers | awk '{print $2}' | gum choose --header "Escolha o contexto (cluster)")
  kubectl config use-context "$ctx"
  ns=$(kubectl config view --minify -o jsonpath='{..namespace}')
  ns=${ns:-default}
}

set_namespace() {
  ns=$(kubectl get ns --no-headers | awk '{print $1}' | gum choose --header "Escolha o namespace")
}

select_pod() {
  kubectl get pods -n "$ns" --no-headers | awk '{print $1}' | gum choose --header "Escolha um Pod"
}

select_deploy() {
  kubectl get deploy -n "$ns" --no-headers | awk '{print $1}' | gum choose --header "Escolha um Deployment"
}

select_resource() {
  kubectl api-resources --no-headers | awk '{print $1}' | gum choose --header "Escolha um tipo de recurso"
}

# ---------- NOVO: FAVORITOS ----------

add_fav() {
  echo "$ns:$1" >> ~/.k8s-dashboard/favs/pods.txt
  gum style --foreground 46 "Adicionado aos favoritos!"
}

list_favs() {
  cat ~/.k8s-dashboard/favs/pods.txt | gum choose --header "Favoritos"
}

# ---------- NOVO: BUSCA GLOBAL ----------

global_search() {
  query=$(gum input --placeholder "Digite parte do nome")
  echo ""
  gum style --bold "Resultados contendo: $query"
  kubectl get all -A | grep "$query" | gum pager
}

# ---------- NOVO: PODS POR LABEL ----------

search_label() {
  label=$(gum input --placeholder "Ex: app=myapp")
  kubectl get pods -n "$ns" -l "$label" | gum pager
}

# ---------- NOVO: HEALTH CHECK VISUAL ----------

health_check() {
  gum style --bold "Health Check do Namespace: $ns"
  echo ""

  kubectl get pods -n "$ns" --no-headers | while read line; do
    pod=$(echo "$line" | awk '{print $1}')
    status=$(echo "$line" | awk '{print $3}')

    if [[ "$status" == "Running" ]]; then
      echo "✔ $pod — OK"
    else
      echo "✖ $pod — $status"
    fi
  done | gum pager
}

# ---------- NOVO: BACKUP DE CONFIGMAPS E SECRETS ----------

backup_configs() {
  gum style --bold --foreground 212 "Gerando backup do namespace: $ns"
  timestamp=$(date +%Y%m%d-%H%M%S)
  outdir=~/.k8s-dashboard/backups/$ns-$timestamp
  mkdir -p "$outdir"

  kubectl get cm -n "$ns" -o yaml > "$outdir/configmaps.yaml"
  kubectl get secrets -n "$ns" -o yaml > "$outdir/secrets.yaml"

  gum style --foreground 46 "Backup salvo em: $outdir"
}

# ---------- NOVO: SALVAR LOGS EM ARQUIVO ----------

save_logs() {
  pod=$(select_pod)
  file=$(gum input --placeholder "arquivo destino ex: /tmp/logs.txt")
  kubectl logs "$pod" -n "$ns" > "$file"
  gum style --foreground 46 "Logs salvos em: $file"
}

# ---------- NOVO: RESTART DE POD ----------

restart_pod() {
  pod=$(select_pod)
  gum confirm "Deseja reiniciar o pod $pod?" && \
    kubectl delete pod "$pod" -n "$ns"
}

# ---------- DASHBOARD PRINCIPAL ----------

dashboard() {
  clear
  gum style --border normal --margin "1" --padding "1" --border-foreground 212 \
  "
  🚀 *Kubernetes Dashboard CLI Kpanel*
  
  Namespace atual: *$ns*
  Contexto:       *$(kubectl config current-context)*

  Escolha uma funcionalidade abaixo:
  "
}

# ---------- MENU PRINCIPAL ----------

while true; do
  dashboard

  action=$(gum choose \
    "Trocar Contexto" \
    "Trocar Namespace" \
    "Lista de Pods" \
    "Watch Pods" \
    "Descrever Pod" \
    "YAML do Pod" \
    "Logs (Follow)" \
    "Logs de Todos Containers" \
    "Salvar Logs em Arquivo" \
    "Exec Bash" \
    "Restart Pod" \
    "Port-forward" \
    "Pods por Label" \
    "Buscar Global" \
    "Adicionar Pod aos Favoritos" \
    "Listar Favoritos" \
    "Deployments" \
    "Reiniciar Deployment" \
    "Rollback Deployment" \
    "Histórico do Deployment" \
    "ConfigMaps" \
    "Secrets" \
    "Backup de ConfigMaps/Secrets" \
    "Ingress" \
    "Endpoints" \
    "Eventos do Namespace" \
    "Health Check" \
    "Top Pods" \
    "Top Nodes" \
    "Cluster Info" \
    "Nodes" \
    "Descrever Node" \
    "Apply YAML" \
    "Editar Recurso" \
    "Deletar Recurso" \
    "Buscar Recurso" \
    "Sair")

  case "$action" in

    "Trocar Contexto") select_context ;;
    "Trocar Namespace") set_namespace ;;
    "Lista de Pods") kubectl get pods -n "$ns" | gum pager ;;
    "Watch Pods") kubectl get pods -n "$ns" -w ;;
    "Descrever Pod") kubectl describe pod "$(select_pod)" -n "$ns" | gum pager ;;
    "YAML do Pod") kubectl get pod "$(select_pod)" -n "$ns" -o yaml | gum pager ;;
    "Logs (Follow)") kubectl logs -f "$(select_pod)" -n "$ns" ;;
    "Logs de Todos Containers")
      pod=$(select_pod)
      for c in $(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}'); do
        gum style --foreground 212 --bold "=== $c ==="
        kubectl logs -f "$pod" -c "$c" -n "$ns"
      done ;;
    "Salvar Logs em Arquivo") save_logs ;;
    "Exec Bash") kubectl exec -it "$(select_pod)" -n "$ns" -- bash ;;
    "Restart Pod") restart_pod ;;
    "Port-forward") kubectl port-forward pod/"$(select_pod)" -n "$ns" "$(gum input --placeholder 'ex 8080:80')" ;;
    "Pods por Label") search_label ;;
    "Buscar Global") global_search ;;
    "Adicionar Pod aos Favoritos") add_fav "$(select_pod)" ;;
    "Listar Favoritos") list_favs ;;
    "Deployments") kubectl get deploy -n "$ns" | gum pager ;;
    "Reiniciar Deployment") kubectl rollout restart deploy "$(select_deploy)" -n "$ns" ;;
    "Rollback Deployment") kubectl rollout undo deploy "$(select_deploy)" -n "$ns" ;;
    "Histórico do Deployment") kubectl rollout history deploy "$(select_deploy)" -n "$ns" | gum pager ;;
    "ConfigMaps") kubectl get cm -n "$ns" | gum pager ;;
    "Secrets") kubectl get secrets -n "$ns" | gum pager ;;
    "Backup de ConfigMaps/Secrets") backup_configs ;;
    "Ingress") kubectl get ing -n "$ns" | gum pager ;;
    "Endpoints") kubectl get endpoints -n "$ns" | gum pager ;;
    "Eventos do Namespace") kubectl get events -n "$ns" --sort-by=.metadata.creationTimestamp | gum pager ;;
    "Health Check") health_check ;;
    "Top Pods") kubectl top pod -n "$ns" | gum pager ;;
    "Top Nodes") kubectl top node | gum pager ;;
    "Cluster Info") kubectl cluster-info | gum pager ;;
    "Nodes") kubectl get nodes | gum pager ;;
    "Descrever Node")
      kubectl describe node "$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | gum choose)" | gum pager ;;
    "Apply YAML") kubectl apply -f "$(gum input --placeholder 'caminho do arquivo')" ;;
    "Editar Recurso") 
      kubectl edit "$(select_resource)" "$(kubectl get "$(select_resource)" -n "$ns" --no-headers | awk '{print $1}' | gum choose)" -n "$ns" ;;
    "Deletar Recurso")
      res=$(select_resource)
      name=$(kubectl get "$res" -n "$ns" --no-headers | awk '{print $1}' | gum choose)
      kubectl delete "$res" "$name" -n "$ns"
      gum style --foreground 160 --bold "Recurso deletado!"
      ;;
    "Buscar Recurso") kubectl get "$(select_resource)" -n "$ns" | gum pager ;;
    "Sair") exit ;;
  esac

  gum confirm "Voltar ao menu?" || exit 0
done
