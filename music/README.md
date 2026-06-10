# Musique

Le lecteur (`scripts/music.gd`, autoload **Music**) joue des **playlists par contexte**, sur le bus
**Musique** (volume réglable dans les options). Une playlist = un sous-dossier ici, rempli de pistes
audio (**`.ogg` recommandé** ; `.mp3` / `.wav` acceptés). Les pistes sont mélangées puis enchaînées ;
un changement de playlist déclenche un **fondu enchaîné**.

## Dossiers

| Dossier  | Quand                                                                 |
|----------|-----------------------------------------------------------------------|
| `menu/`  | Menu principal.                                                       |
| `day/`   | En jeu, **le jour** (`DayNight.day_factor ≥ 0.5`).                    |
| `night/` | En jeu, **la nuit**.                                                  |
| `rain/`, `snow/`, `wind/` | **Futur — météo.** Prioritaire sur jour/nuit quand `Music.weather` vaut ce nom. |

`Music.weather = "normal"` (défaut) → jour/nuit. `Music.weather = "rain"` → playlist `rain/`, etc.

## Ajouter de la musique

Dépose tes pistes dans le bon dossier — **remplace les `dummy_*.ogg` silencieux** fournis pour les
tests. Rien à coder : le lecteur scanne les dossiers au démarrage. (Relance le jeu après ajout.)

## Ajouter une météo (futur)

1. Crée `music/<météo>/` + des pistes (ex. `music/rain/`).
2. Quelque part dans le code : `Music.weather = "rain"` (et `"normal"` pour revenir au jour/nuit).

Aucune autre modification : `_target()` dans `music.gd` choisit déjà la playlist météo si elle existe.
