# lolfix

Detector e reparador de processos travados do **League of Legends** no macOS.

Resolve, sem reiniciar a máquina, o caso clássico do **botão "Jogar" que pisca e não abre nada** depois de um patch.

```bash
lolfix              # detecta e lista — não altera nada
lolfix --unstick    # destrava o cache de assinatura do kernel
lolfix --fix        # kill + unstick + cache: a receita completa
```

---

## O problema principal

Depois de um patch, você clica em **Jogar** no Riot Client, o botão fica cinza por um instante e volta ao normal. Nenhuma janela, nenhuma mensagem de erro. Reiniciar o Mac resolve — e é a única coisa que resolve.

O crash report do macOS mostra o que acontece de verdade:

```
signal:        SIGKILL (Code Signature Invalid)
termination:   CODESIGNING / "Taskgated Invalid Signature"
codeSigningID: ""
procName:      LeagueClient
```

O kernel do macOS mantém a assinatura de código de um binário **associada ao inode** do arquivo. Quando um patch reescreve o `LeagueClient`, o cache do kernel continua apontando para o conteúdo antigo. Toda tentativa de carregar o binário novo falha na validação e o processo é morto com `SIGKILL` antes de desenhar qualquer janela.

Reiniciar funciona apenas porque esvazia esse cache.

Isso explica o conjunto de sintomas que parece contraditório:

| Sintoma | Causa |
|---|---|
| `codesign` diz `valid on disk`, mas o kernel mata o processo | disco íntegro, cache do kernel obsoleto |
| Reboot resolve, reinstalar é desnecessário | o reboot só limpa o cache |
| O botão reseta sem erro nenhum | o processo morre antes da primeira janela |
| Limpar cache do cliente não adianta | é outro cache — do kernel, não do app |

### A correção

Recriar o arquivo dá a ele um **inode novo**, forçando o kernel a reler a assinatura do zero:

```bash
lolfix --unstick
```

Roda em 7 binários (`LeagueClient`, `LeagueClientUx`, os crash handlers, Chromium Embedded Framework, vivox, discord sdk). Usa `ditto` para preservar permissões, xattrs e ACLs, e um `mv` atômico por cima do original.

O arquivo antigo **não pode** ficar dentro do bundle — qualquer sobra quebra o selo do code signing com `a sealed resource is missing or invalid`. Por isso a substituição é atômica, e ao final o `--unstick` verifica as assinaturas dos dois bundles, abortando com aviso se algo não bater.

Resultado medido: exit `137` (SIGKILL) → exit `0`, em execuções consecutivas sem novos crash reports.

---

## Instalação

```bash
git clone https://github.com/lucca-quintas-wh/lolfix-macos.git
cd lolfix-macos
install -m 755 lolfix ~/.local/bin/lolfix
```

Certifique-se de que `~/.local/bin` está no seu `PATH`. Sem dependências além do que já vem no macOS.

---

## Uso

| Comando | O que faz |
|---|---|
| `lolfix` | Detecta e lista. **Somente leitura.** |
| `lolfix --kill` / `-k` | Encerra os processos (`TERM`, depois `KILL -9` nos teimosos) |
| `lolfix --unstick` / `-u` | Destrava o cache de assinatura do kernel. Substitui o reboot |
| `lolfix --cache` / `-c` | Limpa caches e lockfiles do Riot/League |
| `lolfix --fix` / `-f` | `--kill` + `--unstick` + `--cache` |
| `lolfix --reset-config` | Reseta as configurações do jogo (com backup automático) |
| `lolfix -y` | Não pede confirmação |
| `lolfix --help` / `-h` | Ajuda |

O modo padrão não altera nada: lista processos com PID/CPU/memória/tempo, mostra lockfiles pendentes e quanto cada diretório de cache está ocupando.

### Detecção

Procura por `RiotClientServices`, `RiotClientUx`, `LeagueClient`, `LeagueCrashHandler`, `RiotClientCrashHandler`, Riot Repair Tool e o binário do jogo — deduplicando PIDs, com guarda para nunca matar a si mesmo nem o shell que o invocou.

### Segurança

- O modo padrão é read-only
- Toda ação destrutiva pede confirmação (`-y` para pular)
- `--cache` se recusa a rodar com o cliente aberto
- `--reset-config` faz backup com timestamp antes de qualquer coisa
- `--unstick` verifica as assinaturas ao final e aborta se algo não conferir
- Sem confirmação possível (sem TTY), o script cancela em vez de prosseguir

---

## Limpeza de cache

`--cache` remove os diretórios abaixo, todos recriados automaticamente pelo cliente:

```
~/Library/Application Support/Riot Client/{Cache,Code Cache,GPUCache,DawnCache,blob_storage}
~/Library/Application Support/riot-client-ux/{Cache,Code Cache,GPUCache,DawnCache,blob_storage}
~/Library/Application Support/com.riotgames.LeagueofLegends.{LeagueClient,GameClient}/logs
/Applications/League of Legends.app/Contents/LoL/Logs
```

Mais os lockfiles que sobram quando o cliente morre de forma suja. Numa instalação com algum tempo de uso isso costuma passar de 600 MB.

---

## Problema relacionado: "The application can't be opened"

Se abrir pelo ícone do Finder dá esse erro, é um problema **diferente** — o bundle externo está corrompido, sem `Contents/MacOS/` e sem `_CodeSignature`:

```
Contents/
├── LoL/          ok
├── Resources/    ok
├── Info.plist    ok
└── MacOS/        ausente
```

Todo app do macOS precisa de `Contents/MacOS/<executável>`. Sem ele o LaunchServices desiste antes de rodar qualquer coisa, e a mensagem do Finder não diz o motivo.

O `lolfix` **não conserta isso** — exigiria escrever dentro de um bundle assinado. As saídas são o **Riot Repair Tool** ou reinstalar o launcher.

Enquanto isso, abra pelo Riot Client, que ignora a casca quebrada e vai direto no `LeagueClient.app` interno:

```bash
open "/Users/Shared/Riot Games/Riot Client.app" --args \
     --launch-product=league_of_legends --launch-patchline=live
```

---

## Ressalvas

**A hipótese do inode foi confirmada empiricamente, não por documentação da Apple.** O comportamento bate de forma reprodutível (`137` → `0`), mas se um dia o `--unstick` não resolver, o reboot continua sendo o plano B garantido.

Os caminhos foram mapeados de uma instalação real. Se a Riot mudar a estrutura em algum patch grande, o script ignora o que não existe — não quebra, apenas limpa menos.

Testado no macOS 26 (Darwin 25.6) em Apple Silicon (M4 Pro), com o `LeagueClient` rodando via Rosetta.

---

## Licença

MIT
