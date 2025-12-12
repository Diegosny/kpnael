#!/bin/bash
set -e

SCRIPT_NAME="kpanel.sh"
BIN_NAME="kpanel"

OS="$(uname -s)"
ARCH="$(uname -m)"

echo "Detectando sistema operacional..."
case "$OS" in
    Linux*)     PLATFORM=linux;;
    Darwin*)    PLATFORM=mac;;
    *)          echo "Sistema não suportado: $OS"; exit 1;;
esac

if ! command -v gum &> /dev/null
then
    echo "GUM não encontrado. Instalando..."

    if [ "$PLATFORM" == "mac" ]; then
        if command -v brew &> /dev/null; then
            brew install gum
        else
            echo "Homebrew não encontrado. Instalando Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            brew install gum
        fi
    elif [ "$PLATFORM" == "linux" ]; then
        # Usar install script oficial do gum
        curl -fsSL https://gum.style/install.sh | bash
        # Adicionar path temporário caso necessário
        export PATH="$HOME/.gum/bin:$PATH"
    fi
else
    echo "GUM já instalado."
fi

if [ ! -f "$SCRIPT_NAME" ]; then
    echo "Erro: $SCRIPT_NAME não encontrado no diretório atual."
    exit 1
fi

echo "Instalando '$BIN_NAME' globalmente..."

sudo cp "$SCRIPT_NAME" /usr/local/bin/"$BIN_NAME"
sudo chmod +x /usr/local/bin/"$BIN_NAME"

echo "Instalação concluída!"
echo "Agora você pode rodar o dashboard com o comando: $BIN_NAME"

read -p "Deseja abrir o dashboard agora? (y/N): " open_now
if [[ "$open_now" =~ ^[Yy]$ ]]; then
    "$BIN_NAME"
fi
