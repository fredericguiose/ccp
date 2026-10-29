# ccp.sh — routeur de profils Claude Code, portage Linux de ccp.psm1 (09/10/2026).
# Même principe : un compte = un CLAUDE_CONFIG_DIR, persisté dans ~/.claude-profiles/.active.
# À sourcer depuis ~/.bashrc (ou ~/.bashrc.d/) :  source ~/.claude-profiles/ccp.sh
#
#   ccp [profil] [args claude…]   lance claude sur le profil (sans nom : le profil actif)
#   ccpm                           menu : choisit, enregistre, lance
#   ccps                           qui est connecté où, sans exposer un jeton
#   ccpt <profil> [args…]          même chose dans une session tmux « cc-<profil> » (détachée)
#   ccp-add <nom> [--email E] [--label L] [--connectors] [--dir D]
#   ccp-active <profil>            enregistre le profil du prochain démarrage
#
# Différences avec la version Windows :
#   - liens symboliques au lieu des jonctions NTFS (projects/ et skills/ partagés) ;
#   - champ optionnel « Dir » : un profil peut pointer sur un dossier existant
#     (ex. ~/.claude, déjà connecté) au lieu de ~/.claude-profiles/<nom> ;
#   - titre tmux/terminal au lieu de $Host.UI.RawUI.WindowTitle ; pas de règle de BOM.
# Garde-fous conservés : connecteurs bloqués ×2 (settings + variable) quand Connectors=false,
# aucun serveur MCP recopié sur ces profils, aucun credential jamais copié.

CCP_ROOT="${CCP_ROOT:-$HOME/.claude-profiles}"
CCP_TABLE="$CCP_ROOT/profiles.json"
CCP_SHARED="${CCP_SHARED:-$HOME/.claude}"   # projects/ et skills/ communs (mémoire comprise)

_ccp_py() { python3 - "$@"; }

# Une ligne par profil : nom<TAB>connecteurs(0/1)<TAB>dossier<TAB>email<TAB>label
_ccp_rows() {
  [ -f "$CCP_TABLE" ] || { echo "ccp: $CCP_TABLE absent (ccp-add pour créer un profil)" >&2; return 1; }
  _ccp_py "$CCP_TABLE" "$CCP_ROOT" <<'PY'
import json, os, sys
t, root = sys.argv[1], sys.argv[2]
try:
    rows = json.load(open(t, encoding="utf-8"))
except Exception as e:
    sys.exit(f"ccp: {t} illisible ({e})")
for p in rows:
    d = os.path.expanduser(p.get("Dir") or os.path.join(root, p["Name"]))
    print("\t".join([p["Name"], "1" if p.get("Connectors") else "0", d,
                     p.get("Email") or "", p.get("Label") or ""]))
PY
}

_ccp_row() {  # _ccp_row <nom ou numéro>
  local want="$1" i=0 line
  while IFS= read -r line; do
    i=$((i+1))
    if [ "${line%%$'\t'*}" = "$want" ] || [ "$i" = "$want" ]; then printf '%s\n' "$line"; return 0; fi
  done < <(_ccp_rows)
  return 1
}

_ccp_json_path() {  # sans CLAUDE_CONFIG_DIR, Claude Code range .claude.json dans $HOME, pas dans ~/.claude
  if [ "$1" = "$CCP_SHARED" ]; then echo "$HOME/.claude.json"; else echo "$1/.claude.json"; fi
}

_ccp_email() {  # compte connecté, lu dans .claude.json (jamais .credentials.json)
  _ccp_py "$(_ccp_json_path "$1")" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding="utf-8")).get("oauthAccount", {}).get("emailAddress", ""))
except Exception:
    print("")
PY
}

_ccp_init_dir() {  # _ccp_init_dir <dir> <connecteurs 0/1>
  local d="$1" c="$2"
  [ "$d" = "$CCP_SHARED" ] && [ "$c" = 1 ] && return 0   # installation historique : on n'y écrit rien
  mkdir -p "$d"
  if [ "$d" != "$CCP_SHARED" ]; then
    for sub in projects skills; do
      mkdir -p "$CCP_SHARED/$sub"
      [ -e "$d/$sub" ] || ln -s "$CCP_SHARED/$sub" "$d/$sub"
    done
  fi
  _ccp_py "$d" "$c" "$CCP_SHARED" <<'PY'
import json, os, sys
d, c, shared = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
def load(p):
    try: return json.load(open(p, encoding="utf-8"))
    except Exception: return {}
def save(p, o):
    tmp = p + ".tmp"
    json.dump(o, open(tmp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    os.replace(tmp, p)
s_path = os.path.join(d, "settings.json")
s = load(s_path)
if not s and d != shared:   # copie des préférences (modèle, effort), sans MCP
    s = {k: v for k, v in load(os.path.join(shared, "settings.json")).items() if k != "mcpServers"}
if not c:
    s["disableClaudeAiConnectors"] = True
save(s_path, s)
j_path = os.path.join(d, ".claude.json")
if not os.path.exists(j_path):   # pré-seed minimal ; mergé par Claude Code au premier lancement
    save(j_path, {"hasCompletedOnboarding": True})
PY
}

ccp-active() {
  local row; row=$(_ccp_row "$1") || { echo "ccp: profil inconnu « $1 »" >&2; return 1; }
  mkdir -p "$CCP_ROOT"; printf '%s' "${row%%$'\t'*}" > "$CCP_ROOT/.active"
}

ccp() {
  local name row
  if [ $# -gt 0 ] && _ccp_row "$1" >/dev/null 2>&1; then name="$1"; shift
  else name=$(cat "$CCP_ROOT/.active" 2>/dev/null)
       _ccp_row "$name" >/dev/null 2>&1 || { ccpm "$@"; return; }
  fi
  row=$(_ccp_row "$name"); ccp-active "$name"
  local n c d e l; IFS=$'\t' read -r n c d e l <<<"$row"
  _ccp_init_dir "$d" "$c"
  local regime="connecteurs OK"; [ "$c" = 1 ] || regime="connecteurs bloques x2"
  printf '\033]2;CLAUDE [%s] -- %s\007' "$n" "$regime"
  [ -n "$TMUX" ] && tmux rename-window "cc-$n" 2>/dev/null
  local real; real=$(_ccp_email "$d")
  [ -n "$e" ] && [ -n "$real" ] && [ "$e" != "$real" ] && \
    echo "ccp: ATTENTION, $n est connecté sur $real (attendu : $e)" >&2
  if [ "$d" = "$CCP_SHARED" ]; then
    # profil historique (~/.claude) : surtout pas de CLAUDE_CONFIG_DIR, sinon Claude Code
    # cherche ~/.claude/.claude.json au lieu de ~/.claude.json et se croit déconnecté.
    ( unset CLAUDE_CONFIG_DIR ENABLE_CLAUDEAI_MCP_SERVERS
      [ "$c" = 1 ] || export ENABLE_CLAUDEAI_MCP_SERVERS=false
      command claude "$@" )
  elif [ "$c" = 1 ]; then
    ( export CLAUDE_CONFIG_DIR="$d"; unset ENABLE_CLAUDEAI_MCP_SERVERS; command claude "$@" )
  else
    ( export CLAUDE_CONFIG_DIR="$d" ENABLE_CLAUDEAI_MCP_SERVERS=false; command claude "$@" )
  fi
}

ccps() {
  local active cur n c d e l real i=0
  active=$(cat "$CCP_ROOT/.active" 2>/dev/null); cur="${CLAUDE_CONFIG_DIR:-$CCP_SHARED}"
  printf '%-3s %-14s %-28s %-24s %s\n' "#" "profil" "compte" "connecteurs" "rôle"
  while IFS=$'\t' read -r n c d e l; do
    i=$((i+1)); real=$(_ccp_email "$d")
    local mark=""; [ "$n" = "$active" ] && mark="*"; [ "$d" = "$cur" ] && mark="$mark>"
    local reg="OK"; [ "$c" = 1 ] || reg="bloques"
    local s_off; s_off=$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("disableClaudeAiConnectors", False))
except Exception: print(False)' "$d/settings.json" 2>/dev/null)
    [ "$c" = 0 ] && [ "$s_off" != True ] && reg="DERIVE (flag absent)"
    printf '%-3s %-14s %-28s %-24s %s\n' "$i$mark" "$n" "${real:-(pas connecté)}" "$reg" "$l"
    [ -n "$e" ] && [ -n "$real" ] && [ "$e" != "$real" ] && echo "    ⚠ attendu : $e"
  done < <(_ccp_rows)
  echo "* = actif au prochain démarrage   > = session courante"
}

ccpm() {
  ccps || return
  [ -t 0 ] || return 0
  local pick; read -r -p "Profil (nom ou numéro) : " pick
  _ccp_row "$pick" >/dev/null 2>&1 || { echo "ccp: « $pick » n'est pas dans la table" >&2; return 1; }
  ccp "$(_ccp_row "$pick" | cut -f1)" "$@"
}

ccpt() {  # une session tmux détachée par profil : tmux attach -t cc-<profil>
  local row; row=$(_ccp_row "$1") || { echo "ccp: profil inconnu « $1 »" >&2; return 1; }
  local n="${row%%$'\t'*}"; shift
  tmux has-session -t "cc-$n" 2>/dev/null && { echo "déjà lancée : tmux attach -t cc-$n"; return 0; }
  tmux new-session -d -s "cc-$n" -c "${CCP_CWD:-$PWD}" \
    "bash -ic 'ccp $n $*; exec bash'"
  echo "lancée : tmux attach -t cc-$n"
}

ccp-add() {
  local name="$1"; shift
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "ccp: nom invalide (A-Z a-z 0-9 _ -)" >&2; return 1; }
  local email="" label="" conn=0 dir=""
  while [ $# -gt 0 ]; do case "$1" in
    --email) email="$2"; shift 2;; --label) label="$2"; shift 2;;
    --dir) dir="$2"; shift 2;; --connectors) conn=1; shift;;
    *) echo "ccp: option inconnue $1" >&2; return 1;; esac; done
  mkdir -p "$CCP_ROOT"
  _ccp_py "$CCP_TABLE" "$name" "$email" "$label" "$conn" "$dir" <<'PY'
import json, os, sys
t, name, email, label, conn, d = sys.argv[1:7]
rows = json.load(open(t, encoding="utf-8")) if os.path.exists(t) else []
if any(r["Name"] == name for r in rows):
    sys.exit(f"ccp: {name} existe déjà")
row = {"Name": name, "Connectors": conn == "1", "Email": email or None, "Label": label or None}
if d: row["Dir"] = d
rows.append(row)
tmp = t + ".tmp"
json.dump(rows, open(tmp, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
os.replace(tmp, t)
PY
}
