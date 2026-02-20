# 🎌 anime-dl.sh

> Téléchargeur d'animes depuis **Anime-Sama** en ligne de commande, avec menu interactif et détection automatique du meilleur lecteur.

![Bash](https://img.shields.io/badge/bash-5.0%2B-green?style=flat-square&logo=gnubash)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Docker-lightgrey?style=flat-square)

---

## ✨ Fonctionnalités

- 🔍 **Menu interactif** (via `fzf`) pour naviguer, chercher et configurer
- 🚀 **Téléchargement multi-lecteurs** avec détection automatique du meilleur
- 🔄 **Fallback automatique** si un lecteur échoue
- 🎯 **Filtres** : langue, saison, épisode début/fin, qualité vidéo
- ⚡ **Aria2c** pour des téléchargements parallèles rapides (16 connexions)
- 📋 **Mode info** : liste les lecteurs disponibles et teste leur accessibilité
- 🏷️ **Métadonnées** ajoutées automatiquement au fichier `.mkv`
- 🖥️ **Compatible Docker** (BusyBox, Alpine, Debian)

---

## 📦 Dépendances

| Outil | Rôle | Installation |
|-------|------|-------------|
| `bash` ≥ 5.0 | Shell principal | Préinstallé sur Linux |
| `curl` | Requêtes HTTP | `apt install curl` |
| `python3` | Parsing HTML/JS | `apt install python3` |
| `yt-dlp` | Extraction & téléchargement vidéo | `pip install -U yt-dlp` |
| `aria2c` | Téléchargement parallèle | `apt install aria2` |
| `fzf` | Menu interactif TUI | `apt install fzf` |

### Installation rapide (Debian/Ubuntu)

```bash
sudo apt update && sudo apt install -y curl python3 aria2 fzf
pip install -U yt-dlp
```

### Installation rapide (Alpine / Docker)

```bash
apk add bash curl python3 aria2 fzf
pip install -U yt-dlp
```

---

## 🚀 Installation

```bash
# Cloner le dépôt
git clone https://github.com/ton-user/anime-dl.git
cd anime-dl

# Rendre le script exécutable
chmod +x anime-dl.sh

# (Optionnel) Installer globalement
sudo cp anime-dl.sh /usr/local/bin/anime-dl
```

---

## 🎮 Utilisation

### Menu interactif (recommandé)

```bash
./anime-dl.sh
```

Lance un menu TUI complet pour télécharger, consulter les infos ou configurer les paramètres de session.

### Mode CLI direct

```bash
# Télécharger un anime (VOSTFR, saison 1, tous les épisodes)
./anime-dl.sh "Hell Mode"

# Choisir la langue et la saison
./anime-dl.sh -l vf -s 2 "Sword Art Online"

# Télécharger seulement les épisodes 5 à 12
./anime-dl.sh -e 5 -E 12 "Jujutsu Kaisen"

# Forcer un lecteur spécifique (1 à 8)
./anime-dl.sh -L 2 "One Piece"

# Afficher les infos & tester les lecteurs sans télécharger
./anime-dl.sh -i "Bleach"

# Dry-run (simuler sans télécharger)
./anime-dl.sh -n "Naruto"
```

### Options disponibles

```
  -i        Info : liste épisodes & teste les lecteurs (pas de DL)
  -s N      Saison (défaut: 1)
  -l LANG   vostfr | vf | vj ...  (défaut: vostfr)
  -L N      Forcer le lecteur 1-8
  -e N      Épisode début (défaut: 1)
  -E N      Épisode fin   (défaut: auto)
  -q QUAL   Qualité yt-dlp (défaut: bestvideo[height<=1080]+bestaudio/best)
  -o DIR    Dossier de sortie (défaut: /downloads)
  -n        Dry-run
  -v        Verbose
  -h        Aide
```

---

## 🐳 Utilisation avec Docker

Ce script est conçu pour tourner dans un conteneur Docker. Exemple de `docker-compose.yml` :

```yaml
services:
  anime-dl:
    build: .
    container_name: anime-dl
    volumes:
      - ~/Media:/downloads
    environment:
      - TERM=xterm-256color
    stdin_open: true
    tty: true
```

Lancer le menu interactif :

```bash
docker compose run --rm anime-dl
```

Télécharger directement depuis l'hôte :

```bash
docker run -it --rm \
  -v ~/Media:/downloads \
  -e TERM=xterm-256color \
  anime-dl "Hell Mode"
```

---

## 📁 Structure des fichiers téléchargés

```
/downloads/
└── Hell Mode/
    └── Season 01/
        ├── Hell Mode S01E01.mkv
        ├── Hell Mode S01E02.mkv
        └── ...
```

---

## ⚙️ Fonctionnement interne

1. **Slug** : le nom de l'anime est converti en slug compatible Anime-Sama (`Hell Mode` → `hell-mode`)
2. **episodes.js** : le script récupère et parse le fichier JS contenant les URLs de chaque lecteur
3. **Test des lecteurs** : yt-dlp teste chaque lecteur sur l'épisode 1 pour déterminer le meilleur
4. **Téléchargement** : aria2c est utilisé comme backend avec 16 connexions parallèles
5. **Fallback** : si un lecteur échoue en cours de route, les autres sont essayés automatiquement

---

## 📝 Licence

MIT — libre d'utilisation, modification et distribution.

---

## 🤖 Généré avec l'aide de l'IA

Le script `anime-dl.sh` ainsi que ce README ont été développés avec l'assistance de [Claude](https://claude.ai) (Anthropic).

> *"Le code a été conçu et itéré en collaboration avec une IA — pas copié depuis Stack Overflow comme tout le monde."* 😄

> **Disclaimer** : Ce script est destiné à un usage personnel. Respectez les conditions d'utilisation des sites sources et les lois en vigueur dans votre pays.
