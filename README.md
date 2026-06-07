# Catan framework — Framework de jeu de plateau modable (Godot 4.6)

Un moteur de jeu de plateau **modable** où le **core** ne gère que les **tours** et les **points de victoire**. **Tout le reste est un module** : ressources, bâtiments, dés, voleur, cartes, échanges, ports… Le jeu « Catan classique » livré est lui-même un assemblage de deux modules (`classic_catan` + `vanilla_robber`).

> ### 🧠 Modèle mental (à lire en premier — surtout pour une IA)
> **Règle d'or : `core/` ne référence JAMAIS `modules/`** ni aucun mot de gameplay (bois, colonie, voleur, dés, 7…). Le core ne connaît que : *tours, joueurs, points de victoire, plateau hexagonal générique, bus d'événements, registre, UI*. **Tout le contenu (les règles de Catan incluses) vit dans `modules/`.**
>
> **Litmus test** « core vs module » : *« si je remplaçais Catan par un jeu de plateau totalement différent, devrais-je réécrire ce code ? »* — Oui → module. Non → core. Un *nom* générique (un joueur, un point de victoire, un panneau) → **core**. Un *verbe* de jeu (produire, voler, échanger, lancer les dés) → **un module**.
>
> **Flux d'une action** (clé pour lire le code) : `clic 3D` → `scripts/main.gd` en fait une **commande** → routée vers le **pair autoritaire** → l'autorité **émet un événement générique** (`"vertex_clicked"`, `"tile_clicked"`…) → **les mods abonnés** (`reg.on(...)`) réagissent (pose, production…) → l'autorité **diffuse un snapshot** → les clients l'appliquent. Le core **n'appelle jamais** un mod : il **émet**, les mods **s'abonnent**.
>
> **3 couches :** `core/` (moteur agnostique) · `scripts/` (l'app : assemble, réseau, HUD) · `modules/` (le jeu). Un mod = une classe `extends GameMod` **auto-détectée** (rien à enregistrer dans une liste).

---
## 1. Compte rendu — état du projet

### Ce qui est fait
- **Core agnostique** : tours, victoire par seuil, bus d'événements, registre générique, chargeur de mods, **son « à toi de jouer »**. Aucun mot « bois / colonie / voleur / dés » en dur dans le code du core (uniquement dans des commentaires d'exemple).
- **Jeu de base complet** (modules) : ressources, colonie/route/ville, placement initial (snake), lancer de dés + production, voleur sur 7 (défausse / déplacement / vol), **échanges joueur↔joueur (1-à-1 ou « à tous »)** et banque, **ports** (2:1 / 3:1), cartes développement (chevalier, monopole, invention, construction de routes, point de victoire), **plus longue route** et **plus grande armée**.
- **UI = scènes Godot éditables** : menu (`scenes/main_menu.tscn`) et HUD (`scenes/hud.tscn`) sont des scènes + un **thème partagé** (`ui/theme.tres`) → tout est restylable par un designer dans l'éditeur. **Tous les panneaux** (HUD **et** pop-ups : échange, banque, défausse, vol…) sont **déplaçables** (barre de titre) et **redimensionnables** (poignée), positions/tailles mémorisées (**F1** = réinitialiser). Texte rendu en **MSDF** → reste **net même agrandi**. **Journal** d'événements, **ventilation des points** au clic sur un joueur, **icônes/textures de ressources** moddables.
- **Génération de carte moddable** : taille réglable au lobby + mods de map (`balanced_map`, `island_map`) qui ne dépendent de rien.
- **Modèles 3D** : tuiles (hex), bâtiments et pion voleur (`.glb`) ; point d'extension pour donner un mesh/scène à n'importe quel bâtiment (sinon primitive par défaut) ; **panneau de dés** persistant ; teinte joueur configurable.
- **Multijoueur** : modèle **autoritaire** ; jusqu'à **10 joueurs** ; pseudos affichés ; **snapshot incrémental** (ne rafraîchit que ce qui change) ; défausse simultanée.
  - **LAN/direct** : un joueur héberge (`Héberger`), les autres se connectent à son IP.
  - **Serveur-relais UDP** (sans port forwarding) : un process headless sert de relais ; **le 1ᵉʳ connecté devient l'autorité** ; auth par **mot de passe** (token). Voir §7.
- **Sauvegardes** (multi) : bouton « 💾 Sauvegarder » (autorité), reprise depuis le **Salon** avec contrainte de **roster exact** ; même seed + chaque joueur récupère son siège par pseudo.
- **Timer de tour** (core, optionnel, réglé au lobby/solo) : décompte synchronisé ; **pause uniquement sur les événements obligatoires** (défausse, voleur — via les sous-phases) ; **n'est PAS stoppé par l'échange/la banque** ; à l'expiration, passe le tour et **annule les pop-ups optionnelles** ouvertes.
- **Échange « à tous »** : le **premier qui accepte conclut**, et l'UI d'échange se ferme aussitôt chez tout le monde.
- **Banque finie** (19 de chaque ressource, règle officielle) : gains plafonnés + distribution stricte, **panneau de stock toujours visible**.
- **Menu en 4 écrans** (Accueil / Solo / Multijoueur / Salon) : en multi, l'**autorité règle mods + timer + taille** et **tout le monde le voit en direct**.

### Conformité aux règles de Catan classique
**Respecté fidèlement** : plateau **19 tuiles** (4 bois / 3 brique / 4 mouton / 4 blé / 3 minerai / 1 désert) + **18 jetons** (2 et 12 ×1, 3→11 ×2, pas de 7) · setup en **serpent** (2 colonies + 2 routes, 2ᵉ colonie = ressources adjacentes) · **coûts & PV exacts** (route 1 bois+1 brique ; colonie 1/1/1/1 = 1 PV ; ville 2 blé+3 minerai = 2 PV) · règle de **distance** · production (colonie ×1, ville ×2) · **voleur posé sur le désert**, bloque sa tuile · **7** = défausse de la moitié (>7 cartes), déplacement + vol d'un voisin · cartes dev (**deck 25** = 14 chevalier / 5 PV / 2 monopole / 2 invention / 2 routes ; coût minerai+blé+mouton ; **injouable le tour de l'achat** ; **1 carte/tour**) · chevalier → voleur + vol · **plus grande armée** (≥3) et **plus longue route** (≥5) à +2 PV, transférables · banque **4:1** + ports **3:1 / 2:1** (sur les **2 coins** de l'arête côtière) · **victoire à 10 PV** · **PV des cartes cachés** aux adversaires (points publics calculés à part).

Seule simplification assumée : les données de cartes transitent dans le snapshot réseau (l'UI ne les révèle pas, mais **pas d'anti-triche** — choix volontaire : l'hôte/l'autorité pourrait de toute façon tricher).

### Limites connues / pistes
- **Pas d'anti-triche** (assumé) : les cartes en main transitent dans le snapshot.
- **Déconnexion de l'autorité** en cours de partie : tout le monde revient au menu proprement (`on_authority_lost`) ; on reprend via une **sauvegarde** (pas de migration d'autorité à chaud — choix v1). **F5** = forcer une resynchro depuis l'autorité.
- La **disposition/forme** du plateau est moddable (`set_map_generator`), mais la **géométrie hexagonale** elle-même (rendu, voisinage) reste dans le core ; la rendre carrée/triangulaire serait un refactor (point d'extension non fait — tolérance assumée d'un « framework Catan-flavored »).

### Lancer le jeu
Ouvre le projet dans **Godot 4.6** et lance (F5). Le menu propose **Solo**, **Héberger**, **Rejoindre** (IP directe / LAN) et **Rejoindre un serveur** (relais : adresse + port `24545` + mot de passe).
- Tester le réseau en local : *Déboguer → Exécuter plusieurs instances → 2+ instances*.
- Monter un relais : voir **§7**.

---

## 2. Architecture

Trois couches.

### Le `core/` (le moteur — agnostique)
| Fichier | Rôle |
|---|---|
| `game_mod.gd` (`GameMod`) | Classe de base d'un mod (identité, dépendances, `register()`). |
| `game_registry.gd` (`GameRegistry`) | **Le hub**. Bus d'événements + UI + tout ce que les mods déclarent (ressources, bâtiments, actions, panneaux, pools, paramètres). Calcule les PV. |
| `event_bus.gd` (`EventBus`) | Pub/sub à priorités, contexte mutable. |
| `game_state.gd` (`GameState`) | Joueurs, joueur courant, `phase` (SETUP/PLAY/GAME_OVER), `sub_phase` (libre, gérée par les mods), `is_busy()`. |
| `player.gd` (`Player`) | Données joueur typées (`resources`, `buildings`, `cards`, `effects`) + `custom_data` + signaux. |
| `board.gd` (`Board`) | Graphe générique (sommets/arêtes/tuiles, propriété, marqueurs) + signaux. |
| `board_view.gd` | Plateau hexagonal : **plan** (quelle tuile où — surchargeable via `set_map_generator`) puis **rendu 3D** + eau + graphe, routage des clics, modèles custom. |
| `mod_loader.gd` | Tri topologique des `depends_on`, détection de conflits/cycles. |
| `ui_registry.gd` (`UIRegistry`) | Panneaux : `show_panel` (modal, async) + panneaux **persistants** (`show_persistent`) + `cancel_open_modals`. |
| `turn_timer.gd` (`TurnTimer`) | Timer de tour core (décompte, pause sur sous-phase, émet `"turn_timeout"`). |
| `window_mover.gd` (`WindowMover`) | Rend un panneau déplaçable + redimensionnable, position/taille persistées (`user://hud_layout.cfg`). Partagé par le HUD **et** les pop-ups. |
| Types | `building_type.gd`, `development_card.gd`, `game_action.gd`, `placed_building.gd`, `player_effect.gd`, `contexts/click_context.gd` |
| `hex_math.gd` | Géométrie hexagonale. |
| `turn_audio.gd` | Joue un son quand c'est ton tour (`core/sounds/your_turn.*`). |

### La couche `scripts/` (l'application — assemble le jeu)
| Fichier | Rôle |
|---|---|
| `main.gd` | Bootstrap, routage entrées/clics, couche réseau (commandes + snapshot), sauvegardes. |
| `main_menu.gd` | Logique du menu (4 écrans) : solo / héberger / rejoindre / **rejoindre un serveur** / salon. |
| `hud.gd` (`GameHud`) | Logique du HUD : remplit les panneaux, journal (drag/redim délégués à `WindowMover`), bouton Sauvegarder. |
| `game_config.gd` (`GameConfig`) | Config partagée (nb joueurs, mods, réseau, seed, `authority_peer_id`, sauvegardes). |
| `mod_catalog.gd` (`ModCatalog`) | **Auto-détection des mods** : tout `extends GameMod` du projet + packs `.pck`/`.zip` du dossier `mods/`. |
| `net.gd` (autoload `Net`) | Multijoueur : connexion, salon, snapshot, panneaux réseau, **mode relais + auth token**. |

### Les `modules/` (le contenu de jeu)
- `classic_catan/` — ressources, bâtiments, dés, production, setup, échanges, banque/ports, cartes, plus longue route.
- `vanilla_robber/` — voleur sur 7, défausse, vol, plus grande armée.
- `balanced_map/`, `island_map/` — générateurs de carte (mods de démo, ne dépendent de rien).

### `scenes/` et `ui/` (présentation — éditable par un designer)
- `scenes/main.tscn` (jeu), `scenes/main_menu.tscn` (menu), `scenes/hud.tscn` (HUD).
- `ui/theme.tres` — **thème partagé** dont héritent le HUD, le menu et **tous les pop-ups**. **Le levier n°1 pour rendre l'UI plus jolie.**

---

## 3. Tutoriel express — créer un mod

On crée un mod **« Temples »** : un bâtiment *Temple* à **3 PV**. **Aucun code du core ni de `classic_catan` n'est modifié.**

`modules/temple_mod/temple.gd` :
```gdscript
class_name Temple
extends BuildingType

func _init() -> void:
    id = "temple"
    display_name = "Temple"
    target = "vertex"                  # "vertex" (sommet) ou "edge" (arête)
    cost = {"ore": 3, "wheat": 2}
    victory_points = 3                 # <-- compté automatiquement par le core

func can_place(board: Board, player_id: int, key: String) -> bool:
    return board.get_vertex_owner(key) == player_id \
        and board.get_vertex_type(key) == "settlement"

func on_placed(board: Board, player_id: int, key: String) -> void:
    board.place_on_vertex(key, player_id, id)

func get_production_amount() -> int:
    return 3
```

`modules/temple_mod/temple_mod.gd` :
```gdscript
class_name TempleMod
extends GameMod

var _state: GameState

func _init() -> void:
    mod_id = "temple_mod"
    mod_name = "Temples"
    description = "Ajoute le Temple (3 PV), construit sur une de tes colonies"
    depends_on = ["classic_catan"]     # on réutilise ses ressources + son flux de pose

func register(reg: GameRegistry) -> void:
    reg.declare_building(Temple.new())

    var act := GameAction.new()
    act.id = "select_temple"
    act.label = "Sélectionner : Temple"
    act.hotkey = KEY_4
    act.category = "build"
    act.building_id = "temple"         # relie l'action au bâtiment -> tooltip HUD auto (coût/PV/prod)
    act.callback = func() -> void: _state.build_mode_id = "temple"
    act.is_available = func() -> bool:
        return _state != null and _state.phase != GameState.Phase.GAME_OVER
    reg.register_action(act)

    reg.on("game_start", func(ctx): _state = ctx["state"])
```

**C'est tout.** Le jeu **scanne automatiquement** tous les `class_name … extends GameMod` — aucune liste à éditer. Le mod apparaît dans le lobby (indenté sous `classic_catan`), marche en **multijoueur** sans rien de plus, et les PV s'affichent seuls.

> **Distribuer sans recompiler** : exporte le mod en `.pck`/`.zip` et dépose-le dans un dossier `mods/` à côté de l'exécutable.

---

## 4. Référence rapide de l'API

### `GameMod` (à étendre)
`mod_id`, `mod_name`, `description`, `version`, `author`, `depends_on: Array[String]`, `conflicts_with: Array[String]`, `provides: Array[String]`, et **`func register(reg: GameRegistry)`**.
- `provides` = **slots à fournisseur unique** (ex: `["map_generator"]`) : deux mods activés qui fournissent le même slot **s'excluent** (radio dans le lobby + garde-fou `ModLoader`).

### `GameRegistry` (dans `register()`)
```gdscript
reg.declare_resource(id, {"name": "...", "color": Color(...), "is_desert": false,
    "icon": "res://.../x.png", "texture": "res://.../x.png",  # icon=UI, texture=tuile (option.)
    "model": "res://.../x.glb"})                              # modèle 3D de tuile (option.)
reg.declare_building(mon_building_type)            # un BuildingType
reg.override_building_cost(id, {"wood": 2})
reg.add_to_tile_pool(resource_id, count)           # génération du plateau
reg.add_to_number_pool(number, count)
reg.set_board_radius(2)
reg.set_map_generator(mon_callable)                # remplace la disposition (voir Cookbook)
reg.set_victory_threshold(10)
reg.set_player_count_range(2, 10)
reg.register_action(une_game_action)               # tooltip HUD via building_id (auto) ou tooltip/cost
reg.register_panel("mon_panneau", preload("res://.../panel.tscn"))
reg.register_sub_phase_label("mon_mod:ma_phase", "Texte affiché")
reg.on(event_id, callback, priority := 0)          # s'abonner
reg.emit(event_id, contexte)                       # émettre
reg.compute_victory_points(player)                 # somme générique
reg.compute_public_victory_points(player)          # idem sans les cartes à PV (vue adversaire)
reg.compute_victory_breakdown(player, hide := false) # [{name, count, points}]
reg.check_victory(state)                            # déclenche game_over si seuil atteint
# Lectures : reg.get_building(id), reg.get_resource_color/icon/texture/model(id), reg.ui
```

### Événements
- **Émis par le core** : `"game_start"` (`{state, board, registry, board_view}`), `"vertex_clicked"` / `"edge_clicked"` / `"tile_clicked"` (un `ClickContext`), `"game_over"` (`{state, winner}`), `"turn_timeout"` (`{state, player}`).
- **Journal HUD** : `reg.emit("game_log", {"text": "..."})` → ligne dans le panneau « Journal » (synchronisé réseau).
- **Possédés par `classic_catan`** (constantes namespacées, pour un mod qui en `depends_on`) : `ClassicCatanMod.EVT_DICE_ROLL`, `EVT_AFTER_DICE`, `EVT_BEFORE_PRODUCE`, `EVT_BEFORE_PLACE`, `EVT_AFTER_PLACE`, `EVT_TRADE_COMPLETED`, `EVT_BANK_TRADE_COMPLETED`, `EVT_KNIGHT_PLAYED`, `EVT_ROAD_BUILDING_PLAYED`…

### Types à étendre
- `BuildingType` : `id`, `display_name`, `description`, `target`, `cost`, `victory_points`, `mesh_radius`, `mesh_height`, `model_scene` ; méthodes `can_place`, `on_placed`, `get_production_amount`, `get_color`, `create_visual`.
- `DevelopmentCard` : `id`, `display_name`, `description`, `image`, `victory_points`, `is_passive` ; méthodes `is_playable`, `on_play`.
- `PlayerEffect` : `id`, `source_mod`, `display_name`, `description`, `victory_points`, `data` (récompense / trophée à PV — compté auto).
- `GameAction` : `id`, `label`, `hotkey`, `callback`, `is_available`, `category`, `building_id`, `tooltip`, `cost`.

### UI & réseau
```gdscript
reg.ui.show_panel(id, params)                      # MODAL (await), retourne le résultat
reg.ui.show_persistent(id, params)                 # PERSISTANT non bloquant (crée ou maj)
reg.ui.update_persistent(id, params) / hide_persistent(id)
await Net.show_panel_for(player_index, id, raw)    # panneau chez LE bon joueur (réseau)
await Net.show_panels_parallel([{player_index, panel_id, raw}, ...])   # plusieurs, attend TOUT
await Net.show_panels_race(requests, accept)       # plusieurs, 1er "accept" gagne + ferme les autres
```

---

## 5. Cookbook — un mini-mod par feature

Chaque recette est autonome et **compile** contre l'API réelle. Mets-les dans `modules/<ton_mod>/`.

### 5.1 — Le squelette d'un mod
```gdscript
class_name MonMod
extends GameMod

func _init() -> void:
    mod_id = "mon_mod"          # unique, sert de préfixe d'events ("mon_mod:...")
    mod_name = "Mon mod"
    description = "..."
    version = "1.0.0"
    author = "Moi"
    # depends_on = ["classic_catan"]   # optionnel
    # provides = ["map_generator"]     # optionnel (slot exclusif)

func register(reg: GameRegistry) -> void:
    pass   # tout se déclare ici
```

### 5.2 — Déclarer une ressource
```gdscript
func register(reg: GameRegistry) -> void:
    reg.declare_resource("mana", {
        "name": "Mana",
        "color": Color(0.4, 0.2, 0.9),
        "is_desert": false,                              # true = ne produit rien (comme le désert)
        "icon": "res://modules/mon_mod/img/mana.png",    # petite image UI (option.)
        "texture": "res://modules/mon_mod/img/mana_tile.png", # image de tuile (option., repli sur icon)
        "model": "res://modules/mon_mod/mana.glb",       # modèle 3D de tuile (option., remplace l'hexagone)
    })
    # Le mettre sur le plateau : reg.add_to_tile_pool("mana", 3)
```

### 5.3 — Déclarer un bâtiment (coût, PV, production, pose)
```gdscript
class_name Tower
extends BuildingType

func _init() -> void:
    id = "tower" ; display_name = "Tour"
    target = "vertex"                 # ou "edge" pour une route/mur
    cost = {"ore": 2, "mana": 1}
    victory_points = 1

func can_place(board: Board, player_id: int, key: String) -> bool:
    return board.get_vertex_owner(key) < 0       # case libre
func on_placed(board: Board, player_id: int, key: String) -> void:
    board.place_on_vertex(key, player_id, id)
func get_production_amount() -> int:
    return 1
# -> reg.declare_building(Tower.new())
```

### 5.4 — Paramètres & génération du plateau
```gdscript
func register(reg: GameRegistry) -> void:
    reg.set_board_radius(2)               # taille (le lobby peut l'écraser)
    reg.set_victory_threshold(10)         # PV pour gagner
    reg.set_player_count_range(2, 6)
    for r in ["mana","mana","ore","ore","desert"]:
        reg.add_to_tile_pool(r)           # quelles tuiles existent
    for n in [3,4,5,6,8,9,10,11]:
        reg.add_to_number_pool(n)         # quels jetons
    reg.set_map_generator(_plan)          # disposition custom (sinon: disque hex par défaut)

# Renvoie { Vector2(q,r): {"resource": String, "number": int} }. Données pures, pas de Node3D.
func _plan(reg: GameRegistry) -> Dictionary:
    var tiles := reg.tile_pool.duplicate() ; tiles.shuffle()   # RNG global = même carte chez tous
    var plan := {}
    var i := 0
    for q in range(-2, 3):
        for r in range(-2, 3):
            if i >= tiles.size(): break
            plan[Vector2(q, r)] = {"resource": tiles[i], "number": (i % 11) + 2}
            i += 1
    return plan
```
> Les cases **omises** deviennent de l'eau → la forme de l'île suit librement les coordonnées. Pour deux mods de map exclusifs, mets `provides = ["map_generator"]`. Exemples complets : `modules/balanced_map/`, `modules/island_map/`.

### 5.5 — S'abonner à un événement du core
```gdscript
func register(reg: GameRegistry) -> void:
    reg.on("game_start", func(ctx):
        var state: GameState = ctx["state"]
        print("Partie lancée avec ", state.players.size(), " joueurs"))
    reg.on("vertex_clicked", _on_vertex, 0)        # priorité (plus haut = plus tôt)
    reg.on("game_over", func(ctx): print("Gagnant : J", ctx["winner"]))
    reg.on("turn_timeout", func(ctx): print("Temps écoulé pour J", ctx["player"]))

func _on_vertex(ctx) -> void:           # ctx = ClickContext (key, player_id, board, state…)
    print("Sommet cliqué : ", ctx.key)
```

### 5.6 — Posséder & émettre un événement custom
```gdscript
class_name StormMod
extends GameMod

const EVT_STORM := "storm_mod:storm"     # convention : "<mod_id>:<event>" exposé en constante

func register(reg: GameRegistry) -> void:
    reg.on("game_start", func(ctx): _reg = ctx["registry"])

var _reg: GameRegistry
func _trigger_storm(tile: Vector2) -> void:
    _reg.emit(EVT_STORM, {"tile": tile, "cancelled": false})   # contexte mutable
```

### 5.7 — Réagir à l'événement d'un AUTRE mod (dépendance par event)
```gdscript
class_name TaxMod
extends GameMod

func _init() -> void:
    mod_id = "tax_mod"
    depends_on = ["classic_catan"]       # garantit l'ordre de chargement + accès aux constantes

func register(reg: GameRegistry) -> void:
    # Prélève 1 ressource au gagnant après chaque échange (exemple).
    reg.on(ClassicCatanMod.EVT_TRADE_COMPLETED, func(ctx):
        var responder: Player = ctx["responder"]
        responder.add_resource("ore", -1))
```
> C'est exactement ainsi que `vanilla_robber` s'abonne à `ClassicCatanMod.EVT_AFTER_DICE` pour réagir au 7.

### 5.8 — Une action (bouton HUD + raccourci)
```gdscript
var act := GameAction.new()
act.id = "pray" ; act.label = "Prier"
act.hotkey = KEY_P
act.category = "game"                    # "game"/"build"/"cards"/"trade"/"debug"
act.tooltip = "Gagne 1 mana"             # ou act.building_id = "tower" pour un tooltip auto
act.callback = func() -> void: _state.current_player().add_resource("mana", 1)
act.is_available = func() -> bool: return _state.phase == GameState.Phase.PLAY
reg.register_action(act)
```

### 5.9 — Un panneau modal (UI bloquante avec résultat)
```gdscript
# 1) le panneau (scène) implémente : func show_panel(params) + signal closed(result)
reg.register_panel("mon_choix", preload("res://modules/mon_mod/choix.tscn"))
# 2) l'afficher et attendre la réponse :
var res = await reg.ui.show_panel("mon_choix", {"options": ["A", "B"]})
```
Script minimal du panneau :
```gdscript
extends PanelContainer
signal closed(result)
func show_panel(params: Dictionary) -> void:
    %BtnA.pressed.connect(func(): closed.emit("A"))
    %BtnB.pressed.connect(func(): closed.emit("B"))
```
> Gratuit : tout panneau ainsi affiché est **déplaçable/redimensionnable** et **hérite du thème** (WindowMover + `ui/theme.tres`).

### 5.10 — Un panneau persistant (afficheur live, non bloquant)
```gdscript
reg.register_panel("score_live", preload("res://modules/mon_mod/score.tscn"))
reg.ui.show_persistent("score_live", {"score": 0})    # crée OU met à jour
reg.ui.update_persistent("score_live", {"score": 5})  # maj
reg.ui.hide_persistent("score_live")
```
Le script du panneau implémente `func update_panel(params: Dictionary)`. (Patron des panneaux dés/banque/timer.)

### 5.11 — Panneaux réseau (le bon joueur / parallèle / course)
```gdscript
# Affiche chez UN joueur précis et récupère sa réponse côté autorité :
var r = await Net.show_panel_for(player_index, "mon_choix", {"raw": "sérialisable"})

# Plusieurs joueurs EN MÊME TEMPS, attendre TOUTES les réponses (ex. défausse) :
var all = await Net.show_panels_parallel([
    {"player_index": 1, "panel_id": "mon_choix", "raw": {}},
    {"player_index": 2, "panel_id": "mon_choix", "raw": {}},
])

# COURSE : le 1er qui "accepte" gagne, les autres panneaux se ferment (ex. échange à tous) :
var outcome = await Net.show_panels_race(requests, func(res): return res != null and res.get("ok"))
if outcome["index"] >= 0:
    print("Gagnant : requête ", outcome["index"], " résultat ", outcome["result"])
```
> `raw` doit être **sérialisable** (pas d'objets). Les objets (registry, player) sont réinjectés localement.

### 5.12 — Une carte de développement
```gdscript
class_name HealCard
extends DevelopmentCard

func _init() -> void:
    id = "heal" ; display_name = "Soin"
    description = "Gagne 2 mana"
    # is_passive = true ; victory_points = 1   # -> carte à PV cachée (pas "jouée")

func on_play(state: GameState, board: Board, registry: GameRegistry, player: Player) -> bool:
    player.add_resource("mana", 2)
    return true     # true = carte consommée
```
> L'ajout au deck/achat suit le mod de règles : voir `modules/classic_catan/cards/` + `_init_dev_deck`.

### 5.13 — Un trophée (PlayerEffect à PV automatiques)
Exemple **« Bâtisseur »** : +2 PV à qui a le plus de colonies (transférable, comme la plus longue route).
```gdscript
func register(reg: GameRegistry) -> void:
    reg.on(ClassicCatanMod.EVT_AFTER_PLACE, func(ctx): _recompute(ctx["state"]))

func _recompute(state: GameState) -> void:
    var best := -1 ; var best_id := -1
    for p in state.players:
        var n := 0
        for b in p.buildings:
            if b.building_type != null and b.building_type.id == "settlement": n += 1
        if n > best: best = n ; best_id = p.id
    for p in state.players:                       # retire l'ancien porteur
        p.remove_effect_by_id("builder_trophy")
    if best >= 3 and best_id >= 0:                # seuil minimal
        var eff := PlayerEffect.new()
        eff.id = "builder_trophy" ; eff.source_mod = mod_id
        eff.display_name = "Bâtisseur (+2)" ; eff.victory_points = 2
        state.players[best_id].add_effect(eff)    # compté auto + visible dans les Trophées
```

### 5.14 — Données joueur 100 % custom
```gdscript
var p := state.current_player()
p.set_data("faith", p.get_data("faith", 0) + 1)   # stocké dans Player.custom_data
print(p.get_data("faith"))                         # synchronisé par le snapshot réseau
```

### 5.15 — Modèle 3D pour un bâtiment
```gdscript
# Le plus simple :
var b := Tower.new()
b.model_scene = preload("res://modules/mon_mod/tower.glb")
# Teinte joueur : le .glb implémente func set_player_color(c), sinon les MeshInstance3D sont teintés.
# Procédural (alternative) : surcharger func create_visual(player_color) -> Node3D (null = primitive).
```

### 5.16 — Sous-phase (étape obligatoire qui met le timer en pause)
```gdscript
const SP_RITUAL := "mon_mod:ritual"
reg.register_sub_phase_label(SP_RITUAL, "Choisis une tuile pour le rituel")
# ... démarrer :
state.sub_phase = SP_RITUAL     # is_busy()==true, actions globales bloquées, TIMER EN PAUSE (synchro)
# ... finir :
state.sub_phase = ""
```
> Le **timer de tour** ne se met en pause QUE sur `sub_phase` (événements obligatoires). Échange/banque (simples pop-ups) ne le stoppent pas.

### 5.17 — Ressource limitée (patron « banque finie »)
```gdscript
const MAX := 19
func remaining(state: GameState, res: String) -> int:
    var owned := 0
    for p in state.players: owned += int(p.resources.get(res, 0))
    return MAX - owned                       # invariant -> synchro réseau gratuite
func give_capped(state: GameState, player: Player, res: String, n: int) -> void:
    player.add_resource(res, min(n, max(0, remaining(state, res))))
```

### 5.18 — Dépendances / conflits / slot exclusif
```gdscript
func _init() -> void:
    mod_id = "expansion_x"
    depends_on = ["classic_catan"]       # chargé après, accès aux constantes/bâtiments
    conflicts_with = ["autre_mod"]       # refus de coexistence
    provides = ["map_generator"]         # exclusif : un seul mod "map_generator" actif
```

### 5.19 — Compatibilité multijoueur (règle d'or)
Un mod est **MP-safe sans rien faire** s'il respecte ces 3 points :
1. Il modifie l'état **via les events/commandes** (qui ne tournent que sur l'autorité) — pas dans `_process` côté client.
2. Tout son état vit dans `GameState` / `Player` (`resources`, `buildings`, `cards`, `effects`, `custom_data`) → **snapshoté automatiquement**.
3. Son aléatoire utilise le **RNG global** (`randi()`, `Array.shuffle()`), déjà semé identiquement partout (`game_seed`). Pas de `RandomNumberGenerator` perso.

Pour de l'UI par joueur, utilise `Net.show_panel_for/parallel/race` (§5.11). **Les sauvegardes sont gratuites** : tout ce qui est dans `GameState`/`Player` est inclus dans le snapshot sauvegardé/rechargé.

---

## 6. Points avancés (rappels)

- **Personnaliser l'UI** : HUD/menu = scènes + `ui/theme.tres`. Texte en **MSDF** (`project.godot` → `gui/theme/default_font_multichannel_signed_distance_field`) → net à toute échelle. Panneaux déplaçables/redim (poignée bas-droite), positions dans `user://hud_layout.cfg`, **F1** = reset.
- **Images & son** : ressources via `icon`/`texture`/`model` (§5.2) ; voleur 3D dans `modules/vanilla_robber/robber.glb` ; son « à toi de jouer » = `core/sounds/your_turn.*`.
- **Timer de tour** : `GameConfig.turn_timer` (s, `0`=off, réglé au lobby/solo). Pause sur sous-phase uniquement ; à l'expiration → `"turn_timeout"` + annulation des pop-ups optionnelles (échange/banque). Un mod le traduit en fin de tour.
- **Victoire** : `set_victory_threshold`, `compute_victory_points` (total), `compute_public_victory_points` (vue adversaire, sans cartes à PV), `check_victory(state)` à appeler après tout gain de points.

---

## 7. Déployer un serveur-relais (multi sans port forwarding)

Le relais est un **process Godot headless** qui est le serveur ENet (pair 1) **mais ne joue pas** : il valide un token, et **le 1ᵉʳ client connecté devient l'autorité** de jeu. Tout le monde se connecte **en sortant** → pas de port forwarding côté joueurs. **1 partie = 1 process = 1 port.**

```bash
# Lancer un relais (token = mot de passe partagé) :
godot --headless --path /chemin/vers/catan-2 -- --relay 24545 MONTOKEN
# -> "[relais] en écoute sur le port 24545"
```
Plusieurs parties = plusieurs ports (`24545`, `24546`, …). En service (Linux, auto-redémarrage) : un `systemd` templé `catan-relay@.service` avec `ExecStart=... -- --relay %i MONTOKEN`, puis `systemctl enable --now catan-relay@24545`.

Côté joueurs : **Multijoueur → Rejoindre un serveur** → adresse du serveur + port + mot de passe. Le 1ᵉʳ arrivé règle les options et lance ; il peut aussi **reprendre une sauvegarde** (roster exact requis).

> ⚠️ ENet = **UDP** : un tunnel HTTP/TCP (type cloudflared) ne convient pas. Sur un NAS, passe par un VPN mesh (Tailscale/WireGuard) ou un VPS à IP publique avec le port UDP ouvert.

---

## 8. Sauvegardes

- **Sauvegarder** (multi) : bouton « 💾 Sauvegarder » visible pour l'**autorité** en jeu → `user://saves/<nom>.json` (`{meta, snapshot}`).
- **Reprendre** : dans le **Salon**, l'autorité voit la liste des sauvegardes. La reprise n'est possible que si les **pseudos du salon == pseudos sauvegardés** ; chacun retrouve son siège par pseudo, même seed.
- **Pour un mod** : rien à faire — tout ce qui est dans `GameState`/`Player` (y compris `custom_data`, `effects`) est inclus dans le snapshot.
