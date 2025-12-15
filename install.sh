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

  # Configurar fzf (opcional, mas recomendado)
  if [[ -f "$(brew --prefix)/opt/fzf/install" ]]; then
    echo "⚙️ Configurando fzf..."
    "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish || true
  fi
fi

# ---------------------------------------------------------
# Linux
# ---------------------------------------------------------
if [[ "$PLATFORM" == "linux" ]]; then
  # Atualizar apt se disponível
  if command -v apt &>/dev/null; then
    sudo apt update

    install_if_missing kubectl "kubectl" "
      curl -fsSL https://dl.k8s.io/release/\$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl |
      sudo tee /usr/local/bin/kubectl >/dev/null &&
      sudo chmod +x /usr/local/bin/kubectl
    "

    install_if_missing fzf "fzf" "sudo apt install -y fzf"

    install_if_missing gum "gum" "
      curl -fsSL https://gum.style/install.sh | bash &&
      export PATH=\$HOME/.gum/bin:\$PATH
    "
  else
    echo "⚠️ Gerenciador de pacotes não suportado automaticamente."
    echo "Instale manualmente: kubectl, gum, fzf"
    exit 1
  fi
fi

echo ""
echo "✅ Todas as dependências instaladas!"
echo ""

if [[ ! -f "$SCRIPT_NAME_KPANEL" ]]; then
  echo "❌ Erro: $SCRIPT_NAME_KPANEL não encontrado no diretório atual."
  exit 1
fi

if [[ ! -f "$SCRIPT_NAME_DPNAEL" ]]; then
  echo "❌ Erro: $SCRIPT_NAME_DPNAEL não encontrado no diretório atual."
  exit 1
fi

echo "🚀 Instalando '$BIN_NAME_KPANEL' globalmente..."
echo "🚀 Instalando '$BIN_NAME_DPANEL' globalmente..."

sudo cp "$SCRIPT_NAME_KPANEL" /usr/local/bin/"$BIN_NAME_KPANEL"
sudo chmod +x /usr/local/bin/"$BIN_NAME_KPANEL"

sudo cp "$SCRIPT_NAME_DPNAEL" /usr/local/bin/"$BIN_NAME_DPANEL"
sudo chmod +x /usr/local/bin/"$BIN_NAME_DPANEL"

echo ""
echo "🎉 Instalação concluída com sucesso!"
echo "👉 Execute o dashboard com o comando: $BIN_NAME_KPANEL"
echo ""

read -p "Deseja abrir o dashboard agora? (y/N): " open_now
if [[ "$open_now" =~ ^[Yy]$ ]]; then
  "$BIN_NAME_KPANEL"
fi
