# Catan framework — Framework de jeu de plateau modable (Godot 4.3)

Un moteur de jeu de plateau **modable** où le **core** ne gère que les **tours** et les **points de victoire**. **Tout le reste est un module** : ressources, bâtiments, dés, voleur, cartes, échanges, ports… Le jeu « Catan classique » livré est lui-même un assemblage de deux modules (`classic_catan` + `vanilla_robber`).

---
## 1. Compte rendu — état du projet

### Ce qui est fait
- **Core agnostique** : tours, victoire par seuil, bus d'événements, registre générique, chargeur de mods, **son « à toi de jouer »**. Aucun mot « bois / colonie / voleur / dés » en dur dans le core.
- **Jeu de base complet** (modules) : ressources, colonie/route/ville, placement initial (snake), lancer de dés + production, voleur sur 7 (défausse / déplacement / vol), **échanges joueur↔joueur (1-à-1 ou « à tous » en même temps)** et banque, **ports** (2:1 / 3:1), cartes développement (chevalier, monopole, invention, construction de routes, point de victoire), **plus longue route** et **plus grande armée**.
- **UI = scènes Godot éditables** : menu (`scenes/main_menu.tscn`) et HUD (`scenes/hud.tscn`) sont des scènes + un **thème partagé** (`ui/theme.tres`) → tout est restylable par un designer dans l'éditeur. **Tous les panneaux** (HUD **et** pop-ups : échange, banque, défausse, vol…) sont **déplaçables** (barre de titre) et **redimensionnables** (poignée), positions/tailles mémorisées (**F1** = réinitialiser). **Journal** d'événements, **ventilation des points** au clic sur un joueur, **icônes/textures de ressources** moddables.
- **Génération de carte moddable** : taille réglable au lobby + mods de map (`balanced_map`, `island_map`) qui ne dépendent de rien.
- **Modèles 3D** : point d'extension pour donner un mesh/scène à n'importe quel bâtiment (sinon primitive par défaut).
- **Multijoueur** P2P (un joueur héberge, pas de serveur dédié) : hôte autoritaire, synchro complète du jeu de base, jusqu'à **10 joueurs**, pseudos affichés, défausse simultanée.

### Limites connues / pistes
- Cartes dev **visibles de tous** en réseau (simplification ; le vrai Catan les garde secrètes).
- **Déconnexions** en cours de partie non gérées proprement (**F5** = forcer une resynchro depuis l'hôte).
- La **disposition/forme** du plateau est moddable (`set_map_generator`), mais la **géométrie hexagonale** elle-même (rendu, voisinage) reste dans le core ; la rendre carrée/triangulaire serait un refactor (point d'extension non fait).

### Lancer le jeu
Ouvre le projet dans Godot 4.3 et lance (F5). Le menu propose **Solo**, **Héberger** et **Rejoindre** (IP, défaut `127.0.0.1`, port `24545`). Pour tester le réseau en local : *Déboguer → Exécuter plusieurs instances → 2 instances*.

---

## 2. Architecture

Trois couches :

### Le `core/` (le moteur — agnostique)
| Fichier | Rôle |
|---|---|
| `game_mod.gd` | Classe de base d'un mod (identité, dépendances, `register()`). |
| `game_registry.gd` | **Le hub**. Bus d'événements + UI + tout ce que les mods déclarent (ressources, bâtiments, actions, panneaux, pools, paramètres). Calcule les PV. |
| `event_bus.gd` | Pub/sub à priorités, contexte mutable. |
| `game_state.gd` | Joueurs, joueur courant, `phase` (SETUP/PLAY/GAME_OVER), `sub_phase` (libre, gérée par les mods). |
| `player.gd` | Données joueur typées (`resources`, `buildings`, `cards`, `effects`) + `custom_data` + signaux. |
| `board.gd` | Graphe générique (sommets/arêtes/tuiles, propriété, marqueurs) + signaux. |
| `board_view.gd` | Plateau hexagonal : **plan** (quelle tuile où — surchargeable par un mod via `set_map_generator`) puis **rendu 3D** + eau + graphe, routage des clics, modèles custom. |
| `mod_loader.gd` | Tri topologique des `depends_on`, détection de conflits/cycles. |
| `ui_registry.gd` | Enregistrement de panneaux + `show_panel` (async). |
| Types | `building_type.gd`, `development_card.gd`, `game_action.gd`, `placed_building.gd`, `player_effect.gd`, `contexts/click_context.gd` |
| `hex_math.gd` | Géométrie hexagonale. |
| `turn_audio.gd` | Joue un son quand c'est ton tour (remplace `core/sounds/your_turn.*`). |
| `window_mover.gd` (`WindowMover`) | Rend un panneau déplaçable + redimensionnable, position/taille persistées (`user://hud_layout.cfg`). Partagé par le HUD **et** les pop-ups. |

### La couche `scripts/` (l'application — assemble le jeu)
| Fichier | Rôle |
|---|---|
| `main.gd` | Bootstrap, routage entrées/clics, couche réseau (commandes + snapshot). |
| `main_menu.gd` | Logique du menu (scène `scenes/main_menu.tscn`) : solo / héberger / rejoindre / salon. |
| `hud.gd` (`GameHud`) | Logique du HUD (scène `scenes/hud.tscn`) : remplit les panneaux, journal (drag/redim délégués à `WindowMover`). |
| `camera_3d.gd` | Caméra orbitale (clic-droit = tourner, molette = zoomer). |
| `game_config.gd` (`GameConfig`) | Config partagée (nb joueurs, mods, réseau, seed). |
| `mod_catalog.gd` (`ModCatalog`) | **Auto-détection des mods** : tout `extends GameMod` du projet + packs `.pck`/`.zip` du dossier `mods/`. |
| `net.gd` (autoload `Net`) | Multijoueur : connexion, salon, snapshot, panneaux réseau. |

### Les `modules/` (le contenu de jeu)
- `classic_catan/` — ressources, bâtiments, dés, production, setup, échanges, banque/ports, cartes, plus longue route.
- `vanilla_robber/` — voleur sur 7, plus grande armée.
- `balanced_map/`, `island_map/` — générateurs de carte (mods de démo, ne dépendent de rien).

### `scenes/` et `ui/` (présentation — éditable par un designer)
- `scenes/main.tscn` (jeu), `scenes/main_menu.tscn` (menu), `scenes/hud.tscn` (HUD).
- `ui/theme.tres` — **thème partagé** (couleurs, polices, styles de panneaux/boutons) dont héritent le HUD, le menu et **tous les pop-ups**. **Le levier n°1 pour rendre l'UI plus jolie.**

---

## 3. Tutoriel — créer un mod

On va créer un mod **« Temples »** qui ajoute un bâtiment *Temple* valant **3 points de victoire**. Ça montre l'essentiel : déclarer un bâtiment, l'action de sélection, et brancher le mod. **Aucun code du core ni de `classic_catan` n'est modifié.**

### Étape 1 — le bâtiment

Crée `modules/temple_mod/temple.gd` :

```gdscript
class_name Temple
extends BuildingType

func _init() -> void:
    id = "temple"
    display_name = "Temple"
    target = "vertex"            # "vertex" (sommet) ou "edge" (arête)
    cost = {"ore": 3, "wheat": 2}
    victory_points = 3           # <-- détecté et compté automatiquement par le core

# Où peut-on le poser ? (ici : sur une de SES colonies, comme une ville)
func can_place(board: Board, player_id: int, key: String) -> bool:
    return board.get_vertex_owner(key) == player_id \
        and board.get_vertex_type(key) == "settlement"

# Ce qui se passe à la pose : on inscrit le bâtiment sur le plateau.
func on_placed(board: Board, player_id: int, key: String) -> void:
    board.place_on_vertex(key, player_id, id)

# Combien de ressources il produit quand son numéro tombe.
func get_production_amount() -> int:
    return 3
```

> Le core lit `victory_points` de façon générique : pas besoin de toucher au calcul des points. Le HUD affichera tout seul « Temple ×1 : 3 » dans la ventilation au clic sur le joueur.

### Étape 2 — le mod

Crée `modules/temple_mod/temple_mod.gd` :

```gdscript
class_name TempleMod
extends GameMod

var _state: GameState

func _init() -> void:
    mod_id = "temple_mod"
    mod_name = "Temples"
    description = "Ajoute le Temple (3 PV), construit sur une de tes colonies"
    depends_on = ["classic_catan"]   # on réutilise ses ressources + son flux de pose

func register(reg: GameRegistry) -> void:
    # 1) Déclarer le bâtiment au registre
    reg.declare_building(Temple.new())

    # 2) Une action pour passer en "mode temple" (touche 4 + bouton dans le HUD)
    var act := GameAction.new()
    act.id = "select_temple"
    act.label = "Sélectionner : Temple"
    act.hotkey = KEY_4
    act.category = "build"
    act.building_id = "temple"   # IMPORTANT : relie l'action au bâtiment -> le HUD affiche
                                 # tout seul le tooltip (coût / PV / production). Sans ça, pas de tooltip.
    act.callback = func() -> void:
        _state.build_mode_id = "temple"
    act.is_available = func() -> bool:
        return _state != null and _state.phase != GameState.Phase.GAME_OVER
    reg.register_action(act)

    # 3) Récupérer l'état au démarrage (pour les callbacks)
    reg.on("game_start", func(ctx): _state = ctx["state"])
```

### Étape 3 — rien à faire, c'est auto-détecté

Le jeu **scanne automatiquement** tous les `class_name … extends GameMod`. Dès que ton fichier existe, le mod est détecté — **aucune liste à éditer**.

> **Distribuer un mod sans recompiler le jeu** : exporte-le en `.pck`/`.zip` et dépose-le dans un dossier `mods/` à côté de l'exécutable ; le jeu le charge au démarrage et le détecte comme les autres. (En dev, tu peux aussi déposer un dossier de mod source dans `res://mods/`.)

### C'est tout
- Le mod **apparaît automatiquement** dans le lobby — **indenté sous sa dépendance** (`TempleMod` apparaît sous `Catan classique` puisqu'il en `depends_on`).
- En jeu : touche **4** ou le bouton « Sélectionner : Temple », puis clic sur une de tes colonies → un temple à **3 PV** se pose, payé en minerai/blé.
- Les points sont **comptés et affichés** sans rien d'autre à coder.
- **Ça marche en multijoueur tout seul** : la pose passe par un clic plateau → l'hôte applique → snapshot → tout le monde voit le temple (voir §5).

---

## 4. Référence rapide de l'API

### `GameMod` (à étendre)
`mod_id`, `mod_name`, `description`, `version`, `author`, `depends_on: Array[String]`, `conflicts_with: Array[String]`, `provides: Array[String]`, et **`func register(reg: GameRegistry)`**.
- `provides` = **slots à fournisseur unique** (ex: `["map_generator"]`). Deux mods activés qui fournissent le même slot **s'excluent** : le lobby les met en exclusion mutuelle (cocher l'un décoche l'autre) et le `ModLoader` n'en garde qu'un (garde-fou).

### `GameRegistry` (dans `register()`)
```gdscript
reg.declare_resource(id, {"name": "...", "color": Color(...), "is_desert": false,
    "icon": "res://.../x.png", "texture": "res://.../x.png",  # images: icon=UI, texture=tuile (option.)
    "model": "res://.../x.glb"})                              # modèle 3D de tuile (option., remplace l'hexagone)
reg.declare_building(mon_building_type)            # un BuildingType
reg.override_building_cost(id, {"wood": 2})
reg.add_to_tile_pool(resource_id, count)           # génération du plateau
reg.add_to_number_pool(number, count)
reg.set_board_radius(2)
reg.set_map_generator(mon_callable)                # remplace la disposition (voir §5)
reg.set_victory_threshold(10)
reg.set_player_count_range(2, 4)
reg.register_action(une_game_action)               # tooltip HUD: renseigne building_id (-> coût/PV/prod auto), ou tooltip/cost
reg.register_panel("mon_panneau", preload("res://.../panel.tscn"))
reg.register_sub_phase_label("mon_mod:ma_phase", "Texte affiché")
reg.on(event_id, callback, priority := 0)          # s'abonner
reg.emit(event_id, contexte)                       # émettre
reg.compute_victory_points(player)                 # somme générique
reg.compute_victory_breakdown(player)              # [{name, count, points}]
```

### Événements utiles
- **Cycle de vie / plateau (émis par le core)** : `"game_start"` (ctx = `{state, board, registry, board_view}`), `"vertex_clicked"`, `"edge_clicked"`, `"tile_clicked"` (ctx = un `ClickContext`).
- **Journal du HUD** : `registry.emit("game_log", {"text": "..."})` ajoute une ligne au panneau « Journal » (haut-centre), synchronisé en réseau. Pour afficher tes propres événements (ex. un mod de dés affiche son résultat) sans rien coder côté app.
- **Possédés par `classic_catan`** (constantes namespacées, accessibles à un mod qui en `depends_on`) : `ClassicCatanMod.EVT_DICE_ROLL`, `EVT_AFTER_DICE`, `EVT_BEFORE_PRODUCE`, `EVT_BEFORE_PLACE`, `EVT_AFTER_PLACE`, `EVT_TRADE_COMPLETED`, `EVT_BANK_TRADE_COMPLETED`, `EVT_KNIGHT_PLAYED`…

### `BuildingType` (à étendre)
`id`, `display_name`, `target` (`"vertex"`/`"edge"`), `cost: Dictionary`, `victory_points`, `mesh_radius`, `mesh_height`, `model_scene: PackedScene`.
Méthodes à surcharger : `can_place`, `on_placed`, `get_production_amount`, `get_color`, `create_visual`.

### `PlayerEffect` (récompense / trophée à PV — auto-détecté)
```gdscript
var eff := PlayerEffect.new()
eff.id = "mon_trophee"
eff.source_mod = mod_id
eff.display_name = "Mon trophée"
eff.victory_points = 2
player.add_effect(eff)   # apparaît dans les Trophées du HUD + compte dans les PV
```

---

## 5. Points avancés

### Modèles 3D
Deux façons de donner un visuel custom à un bâtiment :
1. **Le plus simple** : `building.model_scene = preload("res://.../maison.glb")`.
2. **Procédural** : surcharger `func create_visual(player_color: Color) -> Node3D` et renvoyer un `Node3D` (renvoyer `null` = primitive par défaut).
Pour la teinte joueur, le modèle peut implémenter `func set_player_color(color)` ; sinon les `MeshInstance3D` sont teintés automatiquement. (Voir `Settlement`/`City` pour un exemple procédural.)

### Personnaliser l'UI (scènes + thème)
Le HUD et le menu sont des **scènes** (`scenes/hud.tscn`, `scenes/main_menu.tscn`) et tout hérite de **`ui/theme.tres`** → un designer édite couleurs/polices/styles dans l'éditeur, **sans code**. Les panneaux du HUD sont **déplaçables** (barre de titre) et **redimensionnables** (poignée bas-droite), positions/tailles sauvegardées dans `user://hud_layout.cfg` (**F1** = réinitialiser). Tout pop-up affiché via `registry.ui.show_panel` / `Net.show_panel_for` **hérite automatiquement du thème**.

### Images & son
- **Images de ressources** : `declare_resource(id, {..., "icon": "res://.../x.png", "texture": "res://.../y.png"})` — `icon` = à côté du nom dans le HUD, `texture` = sur la tuile hexagonale (repli sur `icon`). Sans image → la couleur. Lecture : `reg.get_resource_icon(id)` / `reg.get_resource_texture(id)`.
- **Modèles 3D de tuiles** : `declare_resource(id, {..., "model": "res://.../x.glb"})` — remplace l'hexagone procédural par un vrai modèle 3D (base hex de rayon ≈1, sommets pointe-en-haut). Sans modèle → l'hexagone coloré/texturé. Les tuiles Catan de base sont dans `modules/classic_catan/tiles/`. Si une tuile semble mal orientée, ajuste la rotation dans `_add_tile_model` (`core/board_view.gd`).
- **Pion voleur 3D** : `vanilla_robber` charge `modules/vanilla_robber/robber.glb` comme visuel du voleur (repli sur un cône sombre si le `.glb` est absent).
- **Son « à toi de jouer »** : remplace `core/sounds/your_turn.wav` (ou dépose un `your_turn.ogg`, prioritaire).

### Générer la carte (map)
Par défaut le core mélange `tile_pool`/`number_pool` et les distribue sur un disque hexagonal. Un mod peut **remplacer entièrement la disposition** :
```gdscript
func register(reg: GameRegistry) -> void:
    reg.set_map_generator(_generate)

# reg -> { Vector2(q, r): {"resource": String, "number": int} }
func _generate(reg: GameRegistry) -> Dictionary:
    # Lis reg.tile_pool / reg.number_pool / reg.resources / reg.board_radius,
    # renvoie le plan. Le core fait le rendu 3D, l'eau et le graphe.
    ...
```
- Le générateur ne manipule que des **données** (jamais de `Node3D`) : il décide *quelle tuile va où*. La **forme de l'île** suit librement les coordonnées renvoyées (eau + graphe s'adaptent), pas seulement un disque.
- **Faut-il dépendre de `classic_catan` ? Non — `depends_on = []`.** Un générateur lit le `tile_pool`/`number_pool` *remplis par d'autres mods* : il est donc agnostique et marche avec les ressources de **n'importe quel jeu**, pas seulement Catan. (La *distribution* des tuiles appartient au mod de règles ; la *disposition* appartient au mod de map.)
- **Multijoueur** : n'utilise QUE le RNG global (`Array.shuffle()`, `randi()`), déjà semé identiquement partout → même carte chez tous. N'instancie pas ton propre `RandomNumberGenerator`.
- **Taille de la map** : `reg.board_radius` = la taille choisie dans le **lobby** (option « Taille de la map », 2→6). Lis-la pour t'y adapter. Les générateurs fournis (défaut, `balanced_map`, `island_map`) remplissent **n'importe quelle taille** en répétant le pool de tuiles.
- **Deux mods de map en même temps ?** Déclare `provides = ["map_generator"]` dans ton `_init()` : ils deviennent mutuellement exclusifs (cocher l'un décoche l'autre dans le lobby ; le `ModLoader` n'en garde qu'un par sécurité). Voir §4 → `GameMod.provides`.
- Exemples complets et commentés (chacun `ne dépend de rien` + `provides = ["map_generator"]`) :
  - `modules/balanced_map/` — étale les numéros (aucun voisin de même numéro).
  - `modules/island_map/` — **îles / archipels** : map hexagonale standard découpée par de l'eau, **ratio terre/eau configurable** (le plan ne renvoie que la terre ; les cases omises deviennent de l'eau). Consts en tête de fichier : `LAND_RATIO`, `MAP_RADIUS`, `ISLAND_SEEDS` (1 = île reliée, 2+ = archipel), `ROUGHNESS`.

### Multijoueur
Modèle **hôte autoritaire** : les clients envoient leurs actions, l'hôte applique et diffuse un *snapshot* d'état.
- Un mod basé sur des **clics plateau + événements standards** est compatible réseau **sans rien faire** (la pose, la production, les PV se synchronisent tout seuls).
- Un mod qui ouvre un **panneau** (UI interactive) doit utiliser **`await Net.show_panel_for(player_index, "mon_panneau", params_sérialisables)`** au lieu de `registry.ui.show_panel(...)` : le panneau s'affiche sur l'écran du **bon joueur** et le résultat revient à l'hôte. Pour plusieurs panneaux simultanés (ex. défausse), `await Net.show_panels_parallel([...])`.
- Le plateau est identique chez tous via une **seed** partagée diffusée au lancement.
- port 24545 

### Sous-phases
Pour un déroulé multi-étapes (ex. « pose 2 routes gratuites »), pose `state.sub_phase = "mon_mod:ma_phase"` (et `register_sub_phase_label`). Tant que `sub_phase != ""`, `state.is_busy()` est vrai et les actions globales sont bloquées. Remets `""` quand c'est fini.

### Dépendances entre mods
`depends_on` garantit l'ordre de chargement (le `ModLoader` fait un tri topologique) et permet d'utiliser les constantes/bâtiments du mod parent (ex. `vanilla_robber` dépend de `classic_catan`). `conflicts_with` empêche deux mods incompatibles de coexister.
