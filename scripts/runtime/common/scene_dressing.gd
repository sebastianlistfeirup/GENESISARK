class_name SceneDressing
extends RefCounted
## Loads hand-placed set dressing for a landing site:
## res://scenes/biomes/dressing_<site_id>.tscn (site-local coordinates,
## y = 0 means "on the terrain": each top-level child is snapped to the
## ground at its x/z). Purely visual; gameplay never depends on it.

static func attach(parent: Node3D, site_id: String, terrain: TerrainBuilder) -> Node3D:
	var path := "res://scenes/biomes/dressing_%s.tscn" % site_id
	if site_id.is_empty() or not ResourceLoader.exists(path):
		return null
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	parent.add_child(inst)
	if terrain:
		for c: Node in inst.get_children():
			if c is Node3D and not c.has_meta("keep_height"):
				var n := c as Node3D
				n.position.y += terrain.height_at(n.position.x, n.position.z)
	return inst
