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

☸️ Manual de Uso: Kpnael (Kubernetes)
Para abrir o painel, digite kpnael no seu terminal. Abaixo estão os passos para usar as principais funcionalidades:

1 - Como ver e filtrar Logs
No menu principal, selecione a opção "🔎 Logs (Filtrar)" ou "📖 Logs (Pager)".

Digite ou use as setas para encontrar o Pod desejado e pressione Enter.

Se o Pod tiver mais de um container, selecione qual container deseja inspecionar.

Se escolheu filtrar, digite a palavra-chave (ex: error ou Exception). O painel vai varrer as últimas 2000 linhas e trazer apenas o que importa, colorido na tela.

2 - Como validar o Auto-Scaling (HPA)
No menu principal, selecione "📈 Radar de Auto-Scaling (HPA)".

Para ver se suas regras estão certas, escolha "Scanner de Prontidão (Requests)". Ele mostrará se algum Pod está sem configuração de CPU/Memória.

Para testar na prática, escolha "🔥 Forçar Carga (Stress Test CPU)" e selecione um Pod. O painel vai injetar 100% de uso de CPU por 60 segundos.

Após o teste, vá em "📜 Cronômetro de Eventos (Logs)" para ver a exata hora em que o Kubernetes disparou a criação de novos Pods.

3 - Como executar comandos com o Laravel Tinker
No menu principal, selecione "🐘 Laravel Tinker (Multi-linha)".

Escolha o Pod e o container onde o Laravel está rodando.

Um mini-editor de texto abrirá no seu terminal. Cole ou digite seu código PHP (ex: $u = User::first(); return $u;).

Pressione Ctrl+D. O painel enviará o código para o Pod e exibirá a resposta limpa e formatada com as cores do PHP.

4 - Como usar o Explorador de Banco de Dados
No menu principal, selecione "🗄️ Explorador de Banco de Dados".

Selecione o Pod onde seu banco de dados (PostgreSQL ou MySQL) está rodando.

Digite as credenciais de acesso (Usuário, Senha e Nome do Banco).

Escolha se quer Listar Tabelas, ver a Estrutura de uma Tabela ou Exportar Dump.

Se escolher Exportar Dump, digite a pasta do seu computador onde quer salvar o arquivo .sql e aguarde a finalização.

5 - Como analisar tráfego com o Sniffer de Rede
No menu principal, selecione "🕸️ Sniffer de Rede (Ao Vivo)".

Escolha o Pod que deseja monitorar.

Digite a porta específica que quer observar (ex: 80) ou deixe em branco para todas.

O painel vai injetar um container temporário e começar a exibir todo o tráfego HTTP/TCP em ASCII na sua tela em tempo real. Pressione Ctrl+C para parar.

🐳 Manual de Uso: Dpnael (Docker Local)
Para abrir o painel, digite dpnael no seu terminal.

1 - Como reverter um container para Docker Compose
No menu principal, selecione "🧬 Reverter Container p/ Compose".

Busque e selecione o container que deseja fazer a engenharia reversa.

Digite a pasta onde o arquivo deve ser salvo (ou deixe em branco e aperte Enter para salvar na pasta atual).

O script vai analisar o container em tempo de execução e gerar o docker-compose.yml completo com redes, volumes e variáveis de ambiente.

2 - Como inspecionar o tamanho das Imagens (Raio-X)
No menu principal, selecione "🩻 Raio-X de Camadas (Dive)".

Selecione a imagem Docker que você quer analisar.

Use as Setas (Cima/Baixo) para navegar pelas etapas de construção (Dockerfile) no lado esquerdo da tela.

Aperte a tecla Tab para passar para o lado direito da tela e ver quais arquivos exatos pesaram gigabytes na sua imagem.

3 - Como mapear domínios locais (/etc/hosts)
No menu principal, selecione "🔗 Criar Domínio (/etc/hosts)".

Selecione o container rodando.

Digite o domínio falso que deseja usar (ex: minha-api.local).

O painel pegará o IP interno do container e o vinculará ao seu computador. Você já pode abrir o navegador e testar a URL!