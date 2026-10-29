# ccp — plusieurs comptes Claude Code sur la même machine Linux

Lancer [Claude Code](https://code.claude.com) sur le compte de son choix, sans se
déconnecter des autres : un compte = un `CLAUDE_CONFIG_DIR`, choisi par une commande.

## Commandes

| Commande | Effet |
|---|---|
| `ccp [profil] [args claude…]` | lance `claude` sur le profil (sans nom : le profil actif) |
| `ccpm` | menu : choisit, enregistre, lance |
| `ccps` | qui est connecté sur quel profil, sans afficher de jeton |
| `ccpt <profil> [args…]` | même chose dans une session tmux `cc-<profil>` détachée (machine sans écran, SSH) |
| `ccp-add <nom> [--email E] [--label L] [--connectors] [--dir D]` | ajoute un profil |
| `ccp-active <profil>` | enregistre le profil du prochain lancement |

## Installation

```sh
mkdir -p ~/.claude-profiles
ln -s "$PWD/ccp.sh" ~/.claude-profiles/ccp.sh
echo '[ -f ~/.claude-profiles/ccp.sh ] && source ~/.claude-profiles/ccp.sh' >> ~/.bashrc
source ~/.claude-profiles/ccp.sh

# le compte déjà connecté dans ~/.claude, connecteurs claude.ai autorisés
ccp-add perso --dir "$HOME/.claude" --connectors --email moi@exemple.fr
# un second compte, isolé, connecteurs bloqués
ccp-add second --email autre@exemple.fr
ccp second        # puis /login avec le second compte
```

Dépendances : bash, python3, `claude`. tmux seulement pour `ccpt`.

## Fonctionnement

- La table des profils est `~/.claude-profiles/profiles.json` (nom, email attendu, libellé,
  connecteurs, dossier). Un profil sans `--dir` vit dans `~/.claude-profiles/<nom>/`.
- `projects/` et `skills/` de chaque profil sont des liens vers ceux de `~/.claude` :
  mémoire et skills communs à tous les comptes.
- Sur un profil sans `--connectors`, les connecteurs claude.ai sont bloqués deux fois
  (`disableClaudeAiConnectors` dans ses réglages et `ENABLE_CLAUDEAI_MCP_SERVERS=false`).
  `ccps` signale une dérive si le réglage disparaît.
- Aucun identifiant n'est jamais copié d'un profil à l'autre ; `ccps` lit le compte connecté
  dans `.claude.json`, jamais dans `.credentials.json`.
- Le profil qui réutilise `~/.claude` est lancé **sans** `CLAUDE_CONFIG_DIR` : avec la
  variable, Claude Code cherche `~/.claude/.claude.json` au lieu de `~/.claude.json` et se
  croit déconnecté.

## Pourquoi pas un échangeur de comptes

Les outils qui basculent de compte réécrivent `~/.claude/.credentials.json` et
`~/.claude.json`. Ces fichiers portent aussi les jetons OAuth des serveurs MCP et
l'historique des projets : un échange les écrase, et un seul compte est actif à la fois.
Avec un `CLAUDE_CONFIG_DIR` par compte, chaque profil garde les siens et plusieurs
sessions tournent en parallèle.

## Licence

GPL v3.
