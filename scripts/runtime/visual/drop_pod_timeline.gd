class_name DropPodTimeline
extends RefCounted
## The supply drop pod's hero sequence as pure functions of time (ms), D-056.
## Pose-to-pose, Disney's principles at ~50%: anticipation before every big move,
## fast actions, hits that accelerate into contact, damped follow-through. The
## web viewer (evidence/droppod/viewer) mirrors these numbers one to one.
## `short` is the reduced-motion version: no shake, squash, strain or overshoot.

# Full sequence beats (ms).
const ALT0 := 26.0         # start height (m)
const HOVER_H := 1.45      # anticipation hover height
const HOVER_RISE := 0.16   # the pod lifts a little before it drops (anticipation)
const TOUCH := 0.07        # body height at which the feet touch (strut stroke)
const DESC_END := 1750.0
const DEPLOY_A := 1150.0
const DEPLOY_B := 1750.0
const DROP_A := 2400.0
const IMPACT := 2720.0
const UNLOCK := 3500.0
const STRAIN_A := 3760.0
const SNAP := 4400.0
const SNAP_END := 4590.0
const CELL_A := 4470.0
const CELL_TOP := 5250.0
const DIP_A := 5900.0
const ZIP_A := 6150.0
const ARRIVE := 6530.0
const DIM_A := 6600.0
const DIM_B := 7700.0
const END := 7900.0
# Reduced motion.
const S_ALT0 := 3.0
const S_LAND := 650.0
const S_LID_A := 800.0
const S_LID_B := 1150.0
const S_CELL_A := 1000.0
const S_ZIP_A := 1500.0
const S_ARRIVE := 1950.0
const S_END := 2500.0

const CELL_Y0 := 0.66      # cell centre resting in the well (body space)
const CELL_Y1 := 1.82      # hover height above the pod
const ROLL_LAND := 0.045   # tilt in the last metre: one side's feet touch first
const PITCH_LAND := -0.022


static func duration(short: bool) -> float:
	return S_END if short else END


## Beat times for one-shot events (sound, camera bump, burst, delivery).
## "incoming", "strain" and "zip" are sound beats only (D-064).
static func events(short: bool) -> Dictionary:
	if short:
		return {"incoming": 0.0, "impact": S_LAND, "unlock": S_LID_A, "snap": S_LID_A, "burst": S_LID_A + 150.0,
			"zip": S_ZIP_A, "arrive": S_ARRIVE, "done": S_END}
	return {"incoming": 0.0, "impact": IMPACT, "unlock": UNLOCK, "strain": STRAIN_A, "snap": SNAP, "burst": SNAP + 20.0,
		"zip": ZIP_A, "arrive": ARRIVE, "done": END}


static func k(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func bump(t: float, a: float, b: float) -> float:
	return 0.0 if t < a or t > b else sin(PI * (t - a) / (b - a))


static func ease_out3(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func ease_io(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Back-out ease with a ~5% overshoot (50% of a cartoon's 10%).
static func back_out(x: float, s: float = 1.1) -> float:
	var p := x - 1.0
	return 1.0 + p * p * ((s + 1.0) * p + s)


static func pose(t: float, short: bool = false) -> Dictionary:
	return _short(t) if short else _full(t)


static func _full(t: float) -> Dictionary:
	var p := {"alt": 0.0, "drift": Vector2.ZERO, "yaw": 0.0, "roll": 0.0, "pitch": 0.0, "squash": 1.0,
		"thrust": 0.0, "deploy": 1.0, "lid": 0.0, "hiss": 0.0, "glow": 1.0, "scorch": 0.0, "ring": 0.0,
		"cell_y": CELL_Y0, "cell_zip": -1.0, "cell_vis": 1.0, "cell_scale": 1.0, "cell_spin": 0.0,
		"tremble": 0.0, "dust_t": -1.0, "burst_t": -1.0, "arrive_t": -1.0, "contact": 0.0}
	# Landing marker: fades in at the call, pulses, fades once the pod has landed.
	p["ring"] = ease_io(k(t, 0.0, 450.0)) * (1.0 - ease_io(k(t, IMPACT, IMPACT + 600.0)))
	# 1. Descent on retro thrusters: decelerating (slow in), curving in from the side (arc).
	if t < DESC_END:
		var kd := k(t, 0.0, DESC_END)
		p["alt"] = HOVER_H + (ALT0 - HOVER_H) * pow(1.0 - kd, 2.4)
		var dr := pow(1.0 - kd, 1.7)
		p["drift"] = Vector2(-3.2, 1.4) * dr
		# Lean into the sideways motion (velocity of the drift), two axes.
		var dv := 1.7 * pow(1.0 - kd, 0.7)
		p["roll"] = 0.11 * dv * (1.0 - kd)
		p["pitch"] = -0.05 * dv * (1.0 - kd)
		p["yaw"] = 0.85 * pow(1.0 - kd, 2.0)
		p["thrust"] = 0.65 + 0.35 * kd
	elif t < DROP_A:
		# 2. Anticipation: hover, rise a little, small two-axis corrections, thruster charge.
		var kh := k(t, DESC_END, DROP_A)
		var u := t - DESC_END
		var settle := (1.0 - ease_io(kh)) * ease_io(k(t, DESC_END, DESC_END + 260.0))
		p["alt"] = HOVER_H + HOVER_RISE * ease_io(k(t, DESC_END + 80.0, DROP_A - 60.0)) + 0.022 * sin(TAU * u / 330.0) * settle
		p["roll"] = 0.022 * sin(TAU * u / 520.0) * settle + ROLL_LAND * 0.4 * kh
		p["pitch"] = -0.014 * sin(TAU * u / 410.0 + 0.9) * settle + PITCH_LAND * 0.4 * kh
		p["thrust"] = 1.0 + 0.3 * bump(t, DROP_A - 260.0, DROP_A + 40.0)
	elif t < IMPACT:
		# 3. Thrusters cut, fast drop accelerating into contact (no ease-out).
		var kf := k(t, DROP_A, IMPACT)
		var top := HOVER_H + HOVER_RISE
		p["alt"] = top + (TOUCH - top) * pow(kf, 2.6)
		p["roll"] = ROLL_LAND * (0.4 + 0.6 * kf)
		p["pitch"] = PITCH_LAND * (0.4 + 0.6 * kf)
		p["thrust"] = 1.3 * (1.0 - ease_out3(k(t, DROP_A, DROP_A + 70.0)))
	else:
		# 4. Impact: struts compress then rebound, rock across the feet, squash.
		var u := t - IMPACT
		if u < 70.0:
			p["alt"] = TOUCH - 0.12 * ease_out3(u / 70.0)
		else:
			p["alt"] = -0.05 * exp(-(u - 70.0) / 120.0) * cos(TAU * (u - 70.0) / 280.0)
		p["roll"] = ROLL_LAND * exp(-u / 150.0) * cos(TAU * u / 170.0)
		p["pitch"] = PITCH_LAND * exp(-u / 140.0) * (cos(TAU * u / 150.0) + 0.5 * sin(TAU * u / 150.0))
		p["squash"] = 1.0 - 0.03 * exp(-u / 45.0) * cos(TAU * u / 130.0)
		p["dust_t"] = u / 1000.0
		p["contact"] = 1.0
	# Legs swing out during the descent with a small overshoot (secondary action).
	p["deploy"] = back_out(k(t, DEPLOY_A, DEPLOY_B), 1.2)
	p["scorch"] = 0.85 * ease_io(k(t, DESC_END - 400.0, IMPACT))
	# 5. Hatch: unlock pop + hiss, two strains, snap open with overshoot, settle.
	var lid := 0.0
	if t >= UNLOCK and t < STRAIN_A:
		var u := t - UNLOCK
		lid = 0.016 * exp(-u / 90.0) * absf(cos(TAU * u / 120.0)) + 0.008 * k(t, UNLOCK, UNLOCK + 60.0)
	elif t >= STRAIN_A and t < SNAP:
		var strain := 0.026 * bump(t, STRAIN_A, STRAIN_A + 260.0) + 0.045 * bump(t, STRAIN_A + 360.0, SNAP)
		lid = 0.008 + strain * (0.75 + 0.25 * sin(TAU * (t - STRAIN_A) / 55.0))
		p["tremble"] = 0.6 * bump(t, STRAIN_A, STRAIN_A + 260.0) + bump(t, STRAIN_A + 360.0, SNAP)
	elif t >= SNAP and t < SNAP_END:
		lid = 0.008 + (1.075 - 0.008) * ease_out3(k(t, SNAP, SNAP_END))
	elif t >= SNAP_END:
		var u := t - SNAP_END
		lid = 1.0 + 0.075 * exp(-u / 120.0) * cos(TAU * 4.2 * u / 1000.0)
	p["lid"] = lid
	p["hiss"] = (1.0 - exp(-maxf(t - UNLOCK, 0.0) / 60.0)) * (1.0 - ease_io(k(t, UNLOCK + 200.0, SNAP + 300.0))) if t >= UNLOCK else 0.0
	if t >= SNAP:
		var u := t - SNAP
		# The flung lid kicks the body back a touch (overlapping action).
		p["pitch"] = float(p["pitch"]) + 0.012 * exp(-u / 130.0) * sin(TAU * u / 260.0)
		p["burst_t"] = (t - SNAP - 20.0) / 1000.0
	# 6. Cell: rises out with a small overshoot, hovers, dips (anticipation), zips in.
	if t >= CELL_A:
		if t < CELL_TOP + 400.0:
			p["cell_y"] = CELL_Y0 + (CELL_Y1 - CELL_Y0) * back_out(k(t, CELL_A, CELL_TOP), 1.0)
		else:
			p["cell_y"] = CELL_Y1
		p["cell_y"] = float(p["cell_y"]) + 0.02 * sin(TAU * (t - CELL_TOP) / 900.0) * k(t, CELL_TOP - 200.0, CELL_TOP + 200.0) * (1.0 - k(t, DIP_A, DIP_A + 80.0))
		p["cell_y"] = float(p["cell_y"]) - 0.07 * bump(t, DIP_A, ZIP_A + 60.0)
		p["cell_scale"] = 1.0 - 0.03 * bump(t, DIP_A + 80.0, ZIP_A + 40.0)
		p["cell_spin"] = (t - CELL_A) / 1000.0 * 1.3 + 2.0 * ease_out3(k(t, CELL_A, CELL_TOP))
	if t >= ZIP_A:
		var kz := k(t, ZIP_A, ARRIVE)
		p["cell_zip"] = pow(kz, 2.2)
		p["cell_scale"] = lerpf(1.0, 0.35, pow(kz, 3.0))
	if t >= ARRIVE:
		p["cell_vis"] = 0.0
		p["arrive_t"] = (t - ARRIVE) / 1000.0
	# 7. Delivered: the pod's lights dim (it stays as a prop).
	p["glow"] = lerpf(1.0, 0.12, ease_io(k(t, DIM_A, DIM_B))) * (1.0 + 0.25 * float(p["tremble"]) * sin(t * 0.09))
	return p


static func _short(t: float) -> Dictionary:
	var p := {"alt": 0.0, "drift": Vector2.ZERO, "yaw": 0.0, "roll": 0.0, "pitch": 0.0, "squash": 1.0,
		"thrust": 0.0, "deploy": 1.0, "lid": 0.0, "hiss": 0.0, "glow": 1.0, "scorch": 0.0, "ring": 0.0,
		"cell_y": CELL_Y0, "cell_zip": -1.0, "cell_vis": 1.0, "cell_scale": 1.0, "cell_spin": 0.0,
		"tremble": 0.0, "dust_t": -1.0, "burst_t": -1.0, "arrive_t": -1.0, "contact": 0.0}
	var kl := k(t, 0.0, S_LAND)
	p["alt"] = TOUCH + (S_ALT0 - TOUCH) * (1.0 - ease_out3(kl)) if t < S_LAND else 0.0
	p["contact"] = 1.0 if t >= S_LAND else 0.0
	p["thrust"] = 0.6 * (1.0 - kl)
	p["ring"] = (1.0 - k(t, S_LAND, S_LAND + 300.0)) * k(t, 0.0, 150.0)
	p["scorch"] = 0.5 * kl
	p["dust_t"] = (t - S_LAND) / 1000.0 if t >= S_LAND else -1.0
	p["lid"] = ease_io(k(t, S_LID_A, S_LID_B))
	if t >= S_CELL_A:
		p["cell_y"] = CELL_Y0 + (1.6 - CELL_Y0) * ease_io(k(t, S_CELL_A, S_ZIP_A - 100.0))
		p["cell_spin"] = (t - S_CELL_A) / 1000.0
	if t >= S_ZIP_A:
		p["cell_zip"] = ease_io(k(t, S_ZIP_A, S_ARRIVE))
		p["cell_scale"] = lerpf(1.0, 0.4, k(t, S_ZIP_A, S_ARRIVE))
	if t >= S_ARRIVE:
		p["cell_vis"] = 0.0
		p["arrive_t"] = (t - S_ARRIVE) / 1000.0
	p["glow"] = lerpf(1.0, 0.12, ease_io(k(t, S_ARRIVE, S_END)))
	return p
