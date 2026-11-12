## Dumps a circuit's frame table as JSON for tools/track_map.py.
##   godot --headless --path . -s tools/track_dump.gd -- <track_id> <out.json>
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0] if args.size() > 0 else "proving_ground"
	var out := args[1] if args.size() > 1 else "/tmp/track.json"
	var td := TrackLibrary.get_track(id)
	var pts := []
	for i in td.count:
		var p := td.pos[i]
		pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(td.half_l[i], 0.01), snappedf(td.half_r[i], 0.01),
			snappedf(rad_to_deg(td.bank[i]), 0.1), td.flags[i], snappedf(td.curv_h[i], 0.00001), snappedf(td.curv_v[i], 0.00001),
			snappedf(td.rgt[i].x, 0.001), snappedf(td.rgt[i].z, 0.001)])
	var data := {"name": td.name, "length": td.length, "step": td.step, "closure": td.closure_error, "closure_heading": td.closure_heading_deg,
		"flex": td.flex_lengths, "sections": td.sections, "pads": td.pads, "islands": td.islands, "pts": pts}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("%s: %.0f m, %d samples, closure %.2f m / %.2f deg, flex %s, %d sections" % [td.name, td.length, td.count, td.closure_error, td.closure_heading_deg, str(td.flex_lengths), td.sections.size()])
	for sc: Dictionary in td.sections:
		var i0 := int(float(sc["s0"]) / td.step)
		var i1 := mini(int(float(sc["s1"]) / td.step), td.count - 1)
		var kmax := 0.0
		for i in range(i0, i1):
			kmax = maxf(kmax, absf(td.curv_h[i]))
		print("  %-18s s=%5.0f..%5.0f  len %4.0f  y %6.1f..%6.1f  min radius %s" % [sc["name"], sc["s0"], sc["s1"], float(sc["s1"]) - float(sc["s0"]),
			td.pos[i0].y, td.pos[i1].y, ("%.0f m" % (1.0 / kmax)) if kmax > 1e-5 else "-"])
	quit()
