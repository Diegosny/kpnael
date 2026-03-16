# 🚀 PNAEL Suite (kpnael & dpnael)

[![Bash Shell](https://img.shields.io/badge/bash-%23121011.svg?style=flat&logo=gnu-bash&logoColor=white)](#)
[![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?logo=kubernetes&logoColor=white)](#)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?logo=docker&logoColor=white)](#)

O **PNAEL Suite** é um conjunto de painéis interativos ultraleves para o terminal (TUI) desenvolvidos para transformar tarefas complexas de DevOps e SRE em operações de um único clique. 

Pare de digitar comandos gigantes, memorizar flags obscuras e foque na engenharia. O projeto é dividido em duas frentes:
* **`kpnael`**: O seu canivete suíço para troubleshooting avançado em clusters Kubernetes.
* **`dpnael`**: Um dashboard ágil para administrar arquiteturas Docker locais.

---

## 📥 Instalação (Linux & macOS)

Execute o comando abaixo no seu terminal. O instalador configura os binários e baixa automaticamente as dependências visuais (`fzf`, `gum`, `jq`, `kubectl`, `bat`):

```bash
curl -fsSL [https://raw.githubusercontent.com/Diegosny/kpnael/main/install.sh](https://raw.githubusercontent.com/Diegosny/kpnael/main/install.sh) | bash