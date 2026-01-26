#!/bin/bash
set -e

SCRIPT_NAME_KPANEL="kpanel.sh"
SCRIPT_NAME_DPNAEL="dpanel.sh"
BIN_NAME_KPANEL="kpanel"
BIN_NAME_DPANEL="dpanel"

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "🔍 Detectando sistema operacional..."

case "$OS" in
  Linux*)  PLATFORM=linux ;;
  Darwin*) PLATFORM=mac ;;
  *) echo "❌ Sistema não suportado: $OS"; exit 1 ;;
esac

echo "✅ Plataforma detectada: $PLATFORM ($ARCH)"
echo ""

install_if_missing() {
  local cmd="$1"
  local name="$2"
  local install_cmd="$3"

  if ! command -v "$cmd" &>/dev/null; then
    echo "📦 Instalando $name..."
    eval "$install_cmd"
  else
    echo "✔ $name já instalado"
  fi
}

# --- macOS ---
if [[ "$PLATFORM" == "mac" ]]; then
  if ! command -v brew &>/dev/null; then
    echo "🍺 Homebrew não encontrado. Instalando..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  install_if_missing kubectl "kubectl" "brew install kubectl"
  install_if_missing gum "gum" "brew install gum"
  install_if_missing fzf "fzf" "brew install fzf"
  install_if_missing glow "glow" "brew install glow"
fi

# --- Linux ---
if [[ "$PLATFORM" == "linux" ]]; then
  if command -v apt &>/dev/null; then
    sudo apt update
    install_if_missing kubectl "kubectl" "curl -L \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" -o /tmp/kubectl && sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl"
    install_if_missing fzf "fzf" "sudo apt install -y fzf"
    install_if_missing gum "gum" "curl -fsSL https://gum.style/install.sh | bash && sudo cp ~/.gum/bin/gum /usr/local/bin/"
    
    # Instalando Glow via repositório Charm
    if ! command -v glow &>/dev/null; then
      echo "📦 Instalando glow..."
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
      echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
      sudo apt update && sudo apt install -y glow
    fi
  else
    echo "⚠️ Gerenciador de pacotes não suportado automaticamente para dependências completas."
    exit 1
  fi
fi

echo "🚀 Instalando binários globais..."
sudo cp "$SCRIPT_NAME_KPANEL" /usr/local/bin/"$BIN_NAME_KPANEL" && sudo chmod +x /usr/local/bin/"$BIN_NAME_KPANEL"
sudo cp "$SCRIPT_NAME_DPNAEL" /usr/local/bin/"$BIN_NAME_DPANEL" && sudo chmod +x /usr/local/bin/"$BIN_NAME_DPANEL"

echo "🎉 Instalação concluída! Execute: $BIN_NAME_KPANEL"