# 🚀 PNAEL Suite (kpnael & dpnael)

[![Bash Shell](https://badges.aleen42.com/src/bash.svg)](https://gnu.org/software/bash/)
[![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?logo=kubernetes&logoColor=white)](#)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?logo=docker&logoColor=white)](#)

Uma suíte de painéis interativos ultraleves para o terminal (TUI) desenvolvida para transformar tarefas complexas de DevOps e SRE em operações de um único clique. 

Pare de digitar comandos gigantes e foque no que importa.

## 🛠️ Ferramentas Inclusas

* **`kpnael` (Kubernetes):** O seu canivete suíço para gerenciar clusters, pods, secrets, RBAC, e realizar troubleshooting avançado em tempo real.
* **`dpnael` (Docker):** Um dashboard ágil para administrar containers locais, reverter arquiteturas e analisar redes sem consumir a memória da sua máquina.

## ✨ Features Nível Sênior (Day-2 Operations)

- 🐙 **Engenharia Reversa (Autocompose):** Selecione um container Docker em execução e gere o arquivo `docker-compose.yml` original instantaneamente.
- 🐘 **Laravel Tinker Interativo:** Injeção de código PHP multilinha direto nos containers de produção via `stdin`.
- 🩻 **Raio-X de Imagens:** Integração nativa com o `dive` para analisar o peso camada por camada de qualquer imagem (K8s/Docker).
- 🕸️ **Sniffer de Rede Efêmero:** Injeta o `netshoot` na interface de rede de containers/pods rodando para interceptar tráfego (tcpdump) sem reiniciar a aplicação.
- 📈 **Radar de Auto-Scaling (HPA):** Monitore alvos, avalie a prontidão de "Requests" e injete carga (Stress Test) para auditar a elasticidade do cluster.
- 🗄️ **Explorador de Banco de Dados:** Faça dumps (`.sql`) ou consulte tabelas do Postgres/MySQL interativamente, com syntax highlighting via `bat`.

## 📥 Como Instalar (Linux & macOS)

Rode o comando abaixo no seu terminal. O script cuidará de instalar todas as dependências mágicas (`fzf`, `gum`, `jq` e `kubectl`) e configurar os binários de forma segura:

```bash
curl -fsSL [https://raw.githubusercontent.com/Diegosny/kpnael/main/install.sh](https://raw.githubusercontent.com/Diegosny/kpnael/main/install.sh) | bash