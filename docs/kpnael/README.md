# ☸️ KPNAEL PRO ULTRA - O Canivete Suíço do Kubernetes

Um painel interativo, moderno e super completo para gerenciar clusters Kubernetes **direto do terminal**, usando **GUM (Charm)**, **fzf** e `kubectl`.

Transforme seu terminal em uma verdadeira interface gráfica para Kubernetes. Esqueça ter que decorar dezenas de comandos longos: navegue, edite, debugue e faça manutenções complexas com poucos toques no teclado.

---

## ✨ Demonstração

![Dashboard do K8s](docs/img/dashboard.png)
*(Adicione as imagens do seu painel aqui)*

---

## ⭐ Destaques e Funcionalidades

O **kpnael** foi desenhado para resolver dores reais do dia a dia de SREs e Desenvolvedores:

* **🔎 Busca Dinâmica com Preview:** Visualize YAMLs e descrições de Pods, Deployments e Secrets instantaneamente enquanto navega pelas listas.
* **🕵️ Troubleshooting Avançado:**
  * **Radar de Eventos:** Veja avisos e erros do cluster em ordem cronológica.
  * **Caçador de OOMKilled:** Encontre rapidamente Pods que morreram por falta de memória.
  * **Ler `.env` Direto do Pod:** Leia variáveis de ambiente da aplicação sem precisar entrar no container.
  * **Netshoot Automático:** Suba um Pod temporário de rede (curl, ping, dns) que se autodestrói após o uso.
* **🚀 Operações Ágeis:**
  * **Live Edit:** Edite ConfigMaps e Secrets ao vivo direto no terminal (vim/nano).
  * **Helm Dashboard:** Veja *releases*, inspecione valores aplicados e faça rollback pelo Helm.
  * **Port-Forward Descomplicado:** Abra túneis locais interativamente.
  * **Troca de Imagem & Scale:** Altere a imagem de um Deployment ou escale réplicas com dois cliques.
* **🛡️ Segurança & Manutenção:**
  * **Decodificador de Secrets:** Leia valores em Base64 já descriptografados na tela.
  * **Rollback:** Reverte Deployments com facilidade.
  * **Faxina (Prune):** Limpe Pods *Evicted* ou *Failed* com um botão.
  * **Backup Local:** Salve ConfigMaps e Secrets do namespace atual em `.yaml`.

---