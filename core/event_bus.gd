class_name EventBus
extends RefCounted

# event_id -> Array de {callable, priority, mod_id}
var _subscribers: Dictionary = {}

# Abonne un callback à un événement.
# priority: plus haut = exécuté plus tôt
# mod_id: identifiant du mod qui s'abonne (pour debug et désabonnement)
func subscribe(event_id: String, callback: Callable, priority: int = 0, mod_id: String = "unknown") -> void:
	if not _subscribers.has(event_id):
		_subscribers[event_id] = []
	_subscribers[event_id].append({
		"callback": callback,
		"priority": priority,
		"mod_id": mod_id,
	})
	# Tri stable par priorité décroissante
	_subscribers[event_id].sort_custom(func(a, b): return a["priority"] > b["priority"])

# Désabonne tous les callbacks d'un mod sur tous les événements
func unsubscribe_mod(mod_id: String) -> void:
	for event_id in _subscribers.keys():
		_subscribers[event_id] = _subscribers[event_id].filter(
			func(sub): return sub["mod_id"] != mod_id
		)

# Émet un événement. Le contexte est passé à chaque abonné, dans l'ordre de priorité.
# Le contexte est modifiable: les abonnés successifs voient les modifs des précédents.
func emit(event_id: String, context = null) -> void:
	if not _subscribers.has(event_id):
		return
	# Copie de la liste pour permettre des subscribe/unsubscribe pendant l'émission
	var subs: Array = _subscribers[event_id].duplicate()
	for sub in subs:
		sub["callback"].call(context)

# Pour debug: liste des abonnés à un événement
func get_subscribers(event_id: String) -> Array:
	return _subscribers.get(event_id, []).duplicate()

# Pour debug: tous les événements ayant au moins un abonné
func get_all_events() -> Array:
	return _subscribers.keys()
