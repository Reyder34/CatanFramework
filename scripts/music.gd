extends Node
## Lecteur de musique (autoload "Music"). Joue des PLAYLISTS par contexte, sur le bus "Musique"
## (volume réglé dans les options). Une playlist = un sous-dossier res://music/<nom>/ rempli de
## pistes audio (.ogg recommandé ; .mp3/.wav acceptés). Les pistes sont mélangées puis enchaînées ;
## un changement de playlist déclenche un FONDU ENCHAÎNÉ (2 lecteurs).
##
## Contextes :
##   - "menu" -> playlist  music/menu/
##   - "game" -> jour/nuit AUTO (music/day, music/night). La météo (futur) est prioritaire (voir `weather`).
##
## ÉTENDRE (ex. la pluie) = déposer un dossier music/rain/ + des pistes, puis `Music.weather = "rain"`.
## Aucun autre code à toucher. weather "" ou "normal" -> jour/nuit.

const MUSIC_DIR := "res://music"
const AUDIO_EXT := ["ogg", "mp3", "wav"]
const FADE_TIME := 1.5
const QUIET_DB := -40.0

signal track_changed(title: String)   # nouvelle piste -> pour la banderole MusicBanner
signal paused_changed(paused: bool)

var weather := "normal"   # futur : "rain"/"snow"/"wind" -> playlist prioritaire si != "normal"

var _context := "menu"
var _current := ""               # nom de la playlist en cours
var _lists: Dictionary = {}      # nom -> Array[AudioStream]
var _credits: Dictionary = {}    # nom_fichier -> {title?, artist, source?} (music/credits.json)
var _order: Array = []           # ordre mélangé de la playlist en cours
var _i := 0
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _fade: Tween

func _ready() -> void:
	if Net.is_relay:
		set_process(false)
		return  # process relais (serveur headless) : pas de musique
	_a = _make_player()
	_b = _make_player()
	_a.finished.connect(_on_finished.bind(_a))
	_b.finished.connect(_on_finished.bind(_b))
	_active = _a
	_scan()
	_load_credits()

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Musique"
	add_child(p)
	return p

# Appelé par les scènes : "menu" (main_menu) ou "game" (main).
func set_context(ctx: String) -> void:
	_context = ctx
	_update()

func _process(_dt: float) -> void:
	_update()  # suit les transitions jour/nuit (et futur météo) en jeu

func _update() -> void:
	if _active == null:
		return
	var target := _target()
	if target != _current:
		_play_list(target)

# Quelle playlist devrait jouer maintenant ?
func _target() -> String:
	if _context == "menu":
		return "menu"
	if weather != "" and weather != "normal" and _lists.has(weather) and not _lists[weather].is_empty():
		return weather
	# Hystérésis autour de 0.5 -> pas de clignotement jour/nuit au crépuscule.
	if _current == "day":
		return "night" if DayNight.day_factor < 0.45 else "day"
	if _current == "night":
		return "day" if DayNight.day_factor > 0.55 else "night"
	return "day" if DayNight.day_factor >= 0.5 else "night"

func _play_list(name: String) -> void:
	_current = name
	if not _lists.has(name) or _lists[name].is_empty():
		return  # playlist vide -> on garde ce qui joue (pas de coupure brutale)
	_order = _lists[name].duplicate()
	_order.shuffle()
	_i = 0
	_crossfade(_order[0])

# Fondu enchaîné : la piste démarre en sourdine sur le lecteur libre, on permute.
func _crossfade(stream: AudioStream) -> void:
	var nxt := _b if _active == _a else _a
	var prev := _active
	nxt.stream = stream
	nxt.volume_db = QUIET_DB
	nxt.play()
	_active = nxt
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(nxt, "volume_db", 0.0, FADE_TIME)
	_fade.tween_property(prev, "volume_db", QUIET_DB, FADE_TIME)
	_fade.chain().tween_callback(prev.stop)
	paused_changed.emit(false)
	_emit_track()

# Fin d'une piste -> piste suivante de la MÊME playlist.
func _on_finished(who: AudioStreamPlayer) -> void:
	if who != _active:
		return
	_advance()

# === CONTRÔLES (utilisés par la banderole MusicBanner) ===

# Piste suivante de la playlist courante (re-mélange à chaque tour).
func skip() -> void:
	_advance()

func _advance() -> void:
	if _order.is_empty():
		return
	_i += 1
	if _i >= _order.size():
		_i = 0
		_order.shuffle()
	_play_track(_order[_i])

# Joue une piste sur le lecteur actif (instantané, même playlist).
func _play_track(stream: AudioStream) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var other := _b if _active == _a else _a
	other.stop()
	_active.stream = stream
	_active.volume_db = 0.0
	_active.stream_paused = false
	_active.play()
	paused_changed.emit(false)
	_emit_track()

func toggle_pause() -> void:
	var p := not is_paused()
	if _a != null:
		_a.stream_paused = p
	if _b != null:
		_b.stream_paused = p
	paused_changed.emit(p)

func is_paused() -> bool:
	return _active != null and _active.stream_paused

# Nom de fichier de la piste active ("autumn.ogg"), "" si aucune.
func _active_file() -> String:
	if _active == null or _active.stream == null:
		return ""
	return _active.stream.resource_path.get_file()

# Titre (du manifeste credits.json sinon joli nom de fichier).
func current_title() -> String:
	var fn := _active_file()
	if fn == "":
		return ""
	var c: Dictionary = _credits.get(fn, {})
	if str(c.get("title", "")) != "":
		return str(c["title"])
	return _pretty(fn)

# Auteur (depuis credits.json), "" si inconnu.
func current_artist() -> String:
	return str(_credits.get(_active_file(), {}).get("artist", ""))

# "Titre — Artiste" (ou juste le titre si l'auteur est inconnu) -> affiché par la banderole.
func current_credit() -> String:
	var t := current_title()
	var a := current_artist()
	return "%s — %s" % [t, a] if a != "" else t

func _pretty(path: String) -> String:
	var base := path.get_file().get_basename()
	return base.capitalize() if base != "" else "♪"

func _emit_track() -> void:
	track_changed.emit(current_credit())

# Crédits des musiques (music/credits.json) : nom_fichier -> {title?, artist, source?}.
func _load_credits() -> void:
	_credits = {}
	var path := MUSIC_DIR + "/credits.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_credits = data

# === SCAN DES DOSSIERS (au démarrage) ===
func _scan() -> void:
	_lists.clear()
	var root := DirAccess.open(MUSIC_DIR)
	if root == null:
		push_warning("[Music] dossier %s introuvable" % MUSIC_DIR)
		return
	root.list_dir_begin()
	var n := root.get_next()
	while n != "":
		if root.current_is_dir() and not n.begins_with("."):
			_lists[n] = _load_folder("%s/%s" % [MUSIC_DIR, n])
		n = root.get_next()
	root.list_dir_end()

func _load_folder(path: String) -> Array:
	var out: Array = []
	var seen := {}
	var d := DirAccess.open(path)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir():
			var clean := f.trim_suffix(".import").trim_suffix(".remap")  # builds exportés
			if clean.get_extension().to_lower() in AUDIO_EXT:
				var full := "%s/%s" % [path, clean]
				if not seen.has(full) and ResourceLoader.exists(full):
					seen[full] = true
					var s = load(full)
					if s is AudioStream:
						out.append(s)
		f = d.get_next()
	d.list_dir_end()
	return out
