```markdown
# 🐳 DPNAEL PRO ULTRA - Docker Dashboard

Um painel interativo e ultraleve para gerenciar seu ambiente Docker e Docker Compose local direto do terminal. Desenvolvido com **GUM (Charm)** e **fzf**.

Diga adeus à lentidão dos apps de interface gráfica pesados. O **dpnael** traz o controle total dos seus containers para o terminal com uma usabilidade fluida, rápida e inteligente.

---

## ✨ Demonstração

![Dashboard do Docker](docs/img/docker-dashboard.png)
*(Adicione as imagens do seu painel aqui)*

---

## ⭐ Destaques e Funcionalidades

* **🐙 Gerenciamento de Compose Integrado:** O script detecta automaticamente seus arquivos `docker-compose.yml` e permite rodar `Up`, `Down`, `Restart` ou acompanhar os `Logs` de toda a stack.
* **🔗 Gestor de Domínios Locais (Magia do `/etc/hosts`):** * Selecione um container, digite um domínio (ex: `meuapp.local`) e o **dpnael** descobre o IP interno do container e cria o mapeamento automaticamente para você acessar no navegador.
  * Menu inteligente para listar e remover domínios criados anteriormente.
* **👀 Navegação com Preview:** Veja detalhes e *status* (JSON coloridos) dos containers ou o histórico de camadas das imagens antes de selecioná-las.
* **💾 Gestão de Imagens:** Exporte imagens para arquivos de backup (`.tar`) com facilidade.
* **🛠️ Operações Clássicas Super Rápidas:**
  * Shell (`exec`) inteligente (tenta `bash`, com fallback para `sh`).
  * Monitoramento de métricas em tempo real (`docker stats`).
  * Logs com *pager* e *follow*.
  * Restart, Stop e Remoção segura de containers.
  * Faxina de sistema (System Prune) para liberar espaço em disco.

---