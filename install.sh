#!/bin/bash
set -e

REPO_OWNER="Diegosny"
REPO_NAME="kpnael"
BRANCH="master"

URL_KPNAEL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/kpnael.sh"
URL_DPNAEL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/dpnael.sh"

BIN_KPNAEL="kpnael"
BIN_DPNAEL="dpnael"

OS="$(uname -s)"
case "$OS" in
  Linux*)  PLATFORM=linux ;;
  Darwin*) PLATFORM=mac ;;
  *) echo "❌ Sistema não suportado."; exit 1 ;;
esac

echo "🚀 Iniciando instalação do KPNAEL & DPNAEL..."


install_if_missing() {
  local cmd="$1"
  local install_cmd="$3"
  if ! command -v "$cmd" &>/dev/null; then
    echo "📦 Instalando $cmd..."
    eval "$install_cmd"
  fi
}

if [[ "$PLATFORM" == "mac" ]]; then
  install_if_missing kubectl "kubectl" "brew install kubectl"
  install_if_missing gum "gum" "brew install gum"
  install_if_missing fzf "fzf" "brew install fzf"
  install_if_missing jq "jq" "brew install jq"
fi

if [[ "$PLATFORM" == "linux" ]]; then
  if command -v apt &>/dev/null; then
    sudo apt update -y >/dev/null
    install_if_missing kubectl "kubectl" "curl -fsSL https://dl.k8s.io/release/\$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl | sudo tee /usr/local/bin/kubectl >/dev/null && sudo chmod +x /usr/local/bin/kubectl"
    install_if_missing fzf "fzf" "sudo apt install -y fzf"
    install_if_missing jq "jq" "sudo apt install -y jq"
    install_if_missing gum "gum" "sudo mkdir -p /etc/apt/keyrings && curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg && echo \"deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\" | sudo tee /etc/apt/sources.list.d/charm.list && sudo apt update -y && sudo apt install -y gum"
  else
    echo "⚠️ Dependências devem ser instaladas manualmente (fzf, gum, jq, kubectl)."
  fi
fi

echo "📥 Baixando scripts do GitHub..."

sudo curl -fsSL "$URL_KPNAEL" -o /usr/local/bin/"$BIN_KPNAEL"
sudo chmod +x /usr/local/bin/"$BIN_KPNAEL"

sudo curl -fsSL "$URL_DPNAEL" -o /usr/local/bin/"$BIN_DPNAEL"
sudo chmod +x /usr/local/bin/"$BIN_DPNAEL"

echo "✅ Instalação concluída com sucesso!"

ESCOLHA=$(gum choose "☸️  kpnael" "🐳 dpnael" "❌ Sair" < /dev/tty)

case "$ESCOLHA" in
  "☸️  kpnael") "$BIN_KPNAEL" < /dev/tty ;;
  "🐳 dpnael") "$BIN_DPNAEL" < /dev/tty ;;
  *) echo "Tudo pronto! Digite kpnael ou dpnael quando precisar." ;;
esac