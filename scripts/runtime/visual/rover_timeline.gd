class_name RoverTimeline
extends RefCounted
## The colony rover's hero beats as pure functions of time (ms), D-065, mirrored one
## to one by the web viewer (evidence/rover/viewer). Pose-to-pose at Disney ~50 %:
## anticipation before each big move, fast actions, hits that accelerate into
## contact, damped follow-through and overlapping action (crates, tailgate).
## `reduced` = reduced motion: same beats, no dips, overshoots, hops or rattles.
## Driving itself is a small spring-damper sim (`spring_step`), deterministic at a
## fixed step so Godot and the viewer agree.

# --- Unload: tailgate drops, the bed tips up, the crates shuffle back and forth.
const U_GATE_A := 250.0
const U_GATE_B := 700.0
const U_LIFT_A := 450.0
const U_LIFT_B := 1800.0
const U_SLIDE_A := 1000.0     # first crate starts sliding (each next one +CRATE_STAGGER)
const U_DROP_A := 2900.0
const U_SEAT := 3900.0        # bed hits its seat (impact)
const U_BACK_A := 3980.0      # crates shuffle forward again
const U_GATE_C := 4100.0
const U_LATCH := 4500.0       # tailgate slams shut
const U_END := 5200.0
const BED_MAX := 0.40         # rad (23 deg)
const GATE_MAX := 1.62        # rad: the gate swings down to hang below the deck
const CRATE_STAGGER := 120.0
const CRATE_SLIDE := [0.16, 0.12, 0.2, 0.1]  # metres each crate shifts toward the tailgate

# --- Point turn: corner wheels swivel, the rover spins 180 deg about its middle axle.
const T_STEER_B := 550.0
const T_YAW_A := 700.0
const T_YAW_B := 3900.0
const T_UNSTEER_A := 3950.0
const T_UNSTEER_B := 4450.0
const T_END := 4700.0

# --- Driving.
const DEPART_MS := 380.0      # anticipation before the rover pulls away


static func k(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


static func bump(t: float, a: float, b: float) -> float:
	return 0.0 if t < a or t > b else sin(PI * (t - a) / (b - a))


static func ease_out3(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func ease_io(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


static func smoother(x: float) -> float:
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## Ease out with a small overshoot (`o` = overshoot fraction at ~70 % of the way).
static func ease_back(x: float, o: float) -> float:
	var c := 1.70158 * o / 0.1
	var u := x - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u


## Unload pose: bed (rad, + = front up), gate (rad, + = open down), crate shifts
## (metres toward the tail, 4 crates), crate hop (m), beacon 0..1, chassis jolt (m,
## + = down) and the seat/latch hit flags for sound.
static func unload(t: float, reduced: bool = false) -> Dictionary:
	var bed := 0.0
	var gate := 0.0
	var jolt := 0.0
	var hop := 0.0
	# Bed: dips (anticipation), rises with a little overshoot, holds, then drops and
	# accelerates into its seat (no ease-out on contact).
	if not reduced:
		bed -= 0.012 * bump(t, 0.0, 420.0)
	if t >= U_LIFT_A and t < U_DROP_A:
		var x := k(t, U_LIFT_A, U_LIFT_B)
		bed += BED_MAX * (ease_io(x) if reduced else ease_back(x, 0.03))
		if not reduced:
			bed += 0.004 * sin(t * 0.07) * bump(t, U_LIFT_A, U_LIFT_A + 500.0)  # hydraulic shudder
	elif t >= U_DROP_A and t < U_SEAT:
		var x := k(t, U_DROP_A, U_SEAT)
		bed = BED_MAX * (1.0 - (ease_io(x) if reduced else pow(x, 2.4)))
	elif t >= U_SEAT and not reduced:
		var u := t - U_SEAT
		bed = 0.012 * exp(-u / 70.0) * absf(sin(PI * u / 90.0))  # bounces on its stops
		jolt = 0.025 * exp(-u / 110.0) * cos(TAU * u / 240.0) * k(u, 0.0, 30.0)
		hop = 0.015 * exp(-u / 60.0) * absf(sin(PI * u / 120.0))
	# Tailgate: drops open first (overlapping the lift), slams shut after the seat.
	if t >= U_GATE_A and t < U_GATE_C:
		var x := k(t, U_GATE_A, U_GATE_B)
		gate = GATE_MAX * (ease_io(x) if reduced else ease_back(x, 0.06))
		if not reduced and t > U_GATE_B:
			var u := t - U_GATE_B
			gate += 0.05 * exp(-u / 150.0) * sin(TAU * u / 320.0)  # swings on its hinge
	elif t >= U_GATE_C and t < U_LATCH:
		var x := k(t, U_GATE_C, U_LATCH)
		gate = GATE_MAX * (1.0 - (ease_io(x) if reduced else pow(x, 2.8)))
	elif t >= U_LATCH and not reduced:
		var u := t - U_LATCH
		gate = 0.035 * exp(-u / 60.0) * absf(sin(PI * u / 55.0))  # rattles on the latch
	# Crates: slide toward the open tail one after another, knock against the stop
	# bar, then shuffle forward again after the bed seats (overlapping action).
	var crates: Array[float] = []
	for i: int in 4:
		var slide := float(CRATE_SLIDE[i])
		var a := U_SLIDE_A + CRATE_STAGGER * i
		var off := 0.0
		if t >= a and t < U_BACK_A + 100.0 * i:
			var x := k(t, a, a + 450.0)
			off = slide * (ease_io(x) if reduced else pow(x, 2.0))
			if not reduced and t > a + 450.0:
				var u := t - a - 450.0
				off -= slide * 0.12 * exp(-u / 80.0) * absf(sin(PI * u / 110.0))  # knock
		elif t >= U_BACK_A + 100.0 * i:
			var x := k(t, U_BACK_A + 100.0 * i, U_BACK_A + 100.0 * i + 380.0)
			off = slide * (1.0 - (ease_io(x) if reduced else ease_back(x, 0.05)))
		crates.append(off)
	var beacon := 0.0
	if t < U_END - 300.0:
		beacon = (0.5 + 0.5 * sin(t * TAU * 2.2 / 1000.0)) * k(t, 0.0, 120.0)
	return {"bed": bed, "gate": gate, "crates": crates, "hop": hop, "jolt": jolt, "beacon": beacon}


static func unload_events() -> Dictionary:
	return {"hiss": 0.0, "seat": U_SEAT, "latch": U_LATCH, "done": U_END}


## Point-turn pose: steer 0..1 (corner wheels to their pivot angles), yaw (rad, 0..PI
## times dir), yaw rate (rad/s) for the wheel spin and the beacon.
static func turn(t: float, reduced: bool = false) -> Dictionary:
	var steer := 0.0
	if t < T_UNSTEER_A:
		var x := k(t, 0.0, T_STEER_B)
		steer = ease_io(x) if reduced else ease_back(x, 0.06)
	else:
		var x := k(t, T_UNSTEER_A, T_UNSTEER_B)
		steer = 1.0 - (ease_io(x) if reduced else ease_back(x, 0.06))
	var x2 := k(t, T_YAW_A, T_YAW_B)
	var yaw := PI * smoother(x2)
	var rate := PI * 30.0 * x2 * x2 * (x2 * (x2 - 2.0) + 1.0) / ((T_YAW_B - T_YAW_A) / 1000.0)
	if not reduced:
		yaw -= 0.03 * bump(t, 420.0, 820.0)  # leans back against the turn first
		if t > T_YAW_B:
			var u := t - T_YAW_B
			yaw += 0.018 * exp(-u / 180.0) * sin(TAU * u / 480.0)  # overshoots and settles
	var beacon := (0.5 + 0.5 * sin(t * TAU * 2.2 / 1000.0)) * (1.0 - k(t, T_END - 300.0, T_END))
	return {"steer": steer, "yaw": yaw, "rate": rate, "beacon": beacon}


## Pull-away anticipation (0..DEPART_MS): the body rocks forward on its springs as
## the brakes release, before the rover squats back and moves off. Nose-down rad.
static func depart_dip(t: float, reduced: bool = false) -> float:
	if reduced:
		return 0.0
	return 0.009 * bump(t, 0.0, DEPART_MS)


## One semi-implicit spring-damper step toward `target` (frequency hz, damping zeta).
## state = [x, v]; returns the new [x, v]. Used at a fixed 1/120 s step.
static func spring_step(x: float, v: float, target: float, hz: float, zeta: float, dt: float) -> Vector2:
	var w := TAU * hz
	v += (-w * w * (x - target) - 2.0 * zeta * w * v) * dt
	x += v * dt
	return Vector2(x, v)
