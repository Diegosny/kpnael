#!/bin/bash
set -e

SCRIPT_KPNAEL="kpnael.sh"
BIN_KPNAEL="kpnael"
SCRIPT_DPNAEL="dpnael.sh"
BIN_DPNAEL="dpnael"

OS="$(uname -s)"
case "$OS" in
  Linux*)  PLATFORM=linux ;;
  Darwin*) PLATFORM=mac ;;
  *) exit 1 ;;
esac

install_if_missing() {
  local cmd="$1"
  local install_cmd="$3"
  if ! command -v "$cmd" &>/dev/null; then
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
    sudo apt update
    install_if_missing kubectl "kubectl" "curl -fsSL https://dl.k8s.io/release/\$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl | sudo tee /usr/local/bin/kubectl >/dev/null && sudo chmod +x /usr/local/bin/kubectl"
    install_if_missing fzf "fzf" "sudo apt install -y fzf"
    install_if_missing jq "jq" "sudo apt install -y jq"
    install_if_missing gum "gum" "sudo mkdir -p /etc/apt/keyrings && curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg && echo \"deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\" | sudo tee /etc/apt/sources.list.d/charm.list && sudo apt update && sudo apt install -y gum"
  fi
fi

sudo cp "$SCRIPT_KPNAEL" /usr/local/bin/"$BIN_KPNAEL"
sudo chmod +x /usr/local/bin/"$BIN_KPNAEL"
sudo cp "$SCRIPT_DPNAEL" /usr/local/bin/"$BIN_DPNAEL"
sudo chmod +x /usr/local/bin/"$BIN_DPNAEL"

ESCOLHA=$(gum choose "☸️  kpnael" "🐳 dpnael" "❌ Sair")
case "$ESCOLHA" in
  "☸️  kpnael") "$BIN_KPNAEL" ;;
  "🐳 dpnael") "$BIN_DPNAEL" ;;
esac