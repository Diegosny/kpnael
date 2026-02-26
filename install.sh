#!/bin/bash
set -e

# Configurações de Nomes
SCRIPT_KPNAEL="kpnael.sh"
BIN_KPNAEL="kpnael"

SCRIPT_DPNAEL="dpnael.sh"
BIN_DPNAEL="dpnael"

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

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# macOS
# ---------------------------------------------------------
if [[ "$PLATFORM" == "mac" ]]; then
  if ! command -v brew &>/dev/null; then
    echo "🍺 Homebrew não encontrado. Instalando..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  install_if_missing kubectl "kubectl" "brew install kubectl"
  install_if_missing gum "gum" "brew install gum"
  install_if_missing fzf "fzf" "brew install fzf"
  install_if_missing jq "jq" "brew install jq"
fi

# ---------------------------------------------------------
# Linux
# ---------------------------------------------------------
if [[ "$PLATFORM" == "linux" ]]; then
  if command -v apt &>/dev/null; then
    sudo apt update

    install_if_missing kubectl "kubectl" "
      curl -fsSL https://dl.k8s.io/release/\$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl |
      sudo tee /usr/local/bin/kubectl >/dev/null &&
      sudo chmod +x /usr/local/bin/kubectl
    "

    install_if_missing fzf "fzf" "sudo apt install -y fzf"
    install_if_missing jq "jq" "sudo apt install -y jq"

    # Instalação do Gum via repositório oficial Charm (mais estável que o script)
    install_if_missing gum "gum" "
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
      echo \"deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\" | sudo tee /etc/apt/sources.list.d/charm.list
      sudo apt update && sudo apt install -y gum
    "
  else
    echo "⚠️ Gerenciador de pacotes não suportado automaticamente (apenas APT)."
    echo "Certifique-se de ter instalado manualmente: kubectl, gum, fzf, jq"
  fi
fi

echo ""
echo "✅ Verificação de dependências concluída!"
echo ""

# ---------------------------------------------------------
# Validação dos Arquivos
# ---------------------------------------------------------
if [[ ! -f "$SCRIPT_KPNAEL" ]]; then
  echo "❌ Erro: O arquivo '$SCRIPT_KPNAEL' não foi encontrado nesta pasta."
  exit 1
fi

if [[ ! -f "$SCRIPT_DPNAEL" ]]; then
  echo "❌ Erro: O arquivo '$SCRIPT_DPNAEL' não foi encontrado nesta pasta."
  exit 1
fi

# ---------------------------------------------------------
# Instalação dos Binários
# ---------------------------------------------------------
echo "🚀 Instalando '$BIN_KPNAEL' e '$BIN_DPNAEL' em /usr/local/bin..."

sudo cp "$SCRIPT_KPNAEL" /usr/local/bin/"$BIN_KPNAEL"
sudo chmod +x /usr/local/bin/"$BIN_KPNAEL"

sudo cp "$SCRIPT_DPNAEL" /usr/local/bin/"$BIN_DPNAEL"
sudo chmod +x /usr/local/bin/"$BIN_DPNAEL"

echo ""
echo "🎉 Instalação concluída com sucesso!"
echo "👉 Comandos disponíveis: $BIN_KPNAEL e $BIN_DPNAEL"
echo ""

# Pergunta interativa sobre o que fazer agora
echo "O que deseja fazer agora?"
ESCOLHA=$(gum choose "☸️  Abrir kpnael (Kubernetes)" "🐳 Abrir dpnael (Docker)" "❌ Sair")

case "$ESCOLHA" in
  "☸️  Abrir kpnael (Kubernetes)") "$BIN_KPNAEL" ;;
  "🐳 Abrir dpnael (Docker)")      "$BIN_DPNAEL" ;;
  "❌ Sair")                       echo "Tudo pronto! Use os comandos quando precisar." ;;
esac
