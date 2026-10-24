extends SceneTree
func _init():
	for f in ["SM_Env_Tree_Palm_01", "SM_Env_Fern_01", "SM_Env_Grass_Tall_Clump_01", "SM_Env_Rock_01", "SM_Env_Tree_Banana_01"]:
		var r: Node = (load("res://assets/Synty/Nature/Jungle/FBX/%s.fbx" % f) as PackedScene).instantiate()
		for mi in r.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = mi.mesh
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				var col = a[Mesh.ARRAY_COLOR]; var uv2 = a[Mesh.ARRAY_TEX_UV2]; var uv = a[Mesh.ARRAY_TEX_UV]
				var cmin := Color(9,9,9,9); var cmax := Color(-9,-9,-9,-9)
				if col: 
					for c in col: cmin = Color(min(cmin.r,c.r),min(cmin.g,c.g),min(cmin.b,c.b),min(cmin.a,c.a)); cmax = Color(max(cmax.r,c.r),max(cmax.g,c.g),max(cmax.b,c.b),max(cmax.a,c.a))
				var umin := Vector2(9,9); var umax := Vector2(-9,-9)
				for u in uv: umin = umin.min(u); umax = umax.max(u)
				var mat := m.surface_get_material(s)
				print(f, " ", mi.name, " s", s, " mat=", mat.resource_name if mat else "-", " tex=", (mat as BaseMaterial3D).albedo_texture.resource_path.get_file() if mat is BaseMaterial3D and mat.albedo_texture else "none", " col=", col != null and col.size() > 0, " ", cmin, "..", cmax, " uv2=", uv2 != null and uv2.size() > 0, " uv=", umin, "..", umax)
		r.free()
	quit()
