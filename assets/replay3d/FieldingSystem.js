// FieldingSystem.js — scorecard-driven fielding / wicketkeeping / running replay for three.js.
//
// Uses two GLBs built in this project:
//   batsman_with_bat_animated.glb  (batting shots + Bat_Run / Bat_Ground / Bat_Out_React / Bat_WalkOff)
//   fielder_keeper_animated.glb    (F_* fielder clips, K_* keeper clips, Palm_L / Palm_R sockets, CricketBall)
//
// Field frame (metres): +Y up, striker at the origin, bowler's end at +Z, off side -X (right-handed striker).
// Striker's stumps at z = -0.25, non-striker's at z = 19.87; popping creases at z = 0.97 and z = 18.65.
//
// Everything is planned up-front from one ball event into time segments, and `update(t)` evaluates them,
// so a replay can be scrubbed back and forth and every actor stays in sync with the ball.
//
//   const fs = new FieldingSystem({ scene, battingGltf, fieldingGltf, field: DEFAULT_FIELD });
//   const plan = fs.planBall(event);    // event: see README / planBall() below
//   fs.update(t)                        // t = seconds since the start of the delivery (bat contact at 1.0)
import * as THREE from 'three';
import { clone as cloneSkinned } from 'three/addons/utils/SkeletonUtils.js';

const G = -9.81, BALL_R = 0.036;
export const STUMPS = { striker: new THREE.Vector3(0, 0, -0.25), nonStriker: new THREE.Vector3(0, 0, 19.87) };
export const CREASE = { striker: 0.97, nonStriker: 18.65 };
const D2R = Math.PI / 180;

// Fielding positions for a right-handed striker: [angle deg (0 = straight, -90 = point/off, +90 = square leg), distance m]
export const POSITIONS = {
  'Wicketkeeper': null, 'Bowler': null,
  'Slip': [-158, 10], 'Gully': [-122, 13], 'Point': [-92, 19], 'Cover': [-62, 22], 'Extra Cover': [-45, 25],
  'Mid-Off': [-14, 25], 'Mid-On': [14, 25], 'Mid-Wicket': [55, 22], 'Square Leg': [92, 20], 'Fine Leg': [160, 55],
  'Third Man': [-160, 55], 'Long-On': [14, 64], 'Long-Off': [-14, 64], 'Deep Cover': [-55, 62], 'Deep Point': [-95, 60],
  'Deep Square Leg': [95, 60], 'Deep Mid-Wicket': [55, 63],
};
export const DEFAULT_FIELD = ['Slip', 'Point', 'Cover', 'Mid-Off', 'Mid-On', 'Mid-Wicket', 'Square Leg', 'Fine Leg', 'Deep Cover'];
export const BOUNDARY = 68;
export const UMPIRE_POS = new THREE.Vector3(-1.3, 0, 21.8);
// the striker stands this far in front of the stumps (his back foot is clear of them in every shot)
export const STRIKER_DZ = 0.7;
// the pavilion gate on the boundary behind the striker's leg side: players leave and enter the field through it
export const GATE_DIR = new THREE.Vector3(0.61, 0, -0.79).normalize();
export const GATE = GATE_DIR.clone().multiplyScalar(66);
export const GATE_IN = GATE_DIR.clone().multiplyScalar(72.4);
const WALK_SPEED = 1.8, ENTRY_SPEED = 2.1;
// stands start just outside the rope and climb: height of the seating at distance r from the pitch centre
export const STAND_IN = 74, STAND_OUT = 108, STAND_H = 24;
export const standHeight = (r) => 0.6 + THREE.MathUtils.clamp((r - STAND_IN) / (STAND_OUT - STAND_IN), 0, 1) * (STAND_H - 0.6);

export function positionOf(name, leftHanded = false) {
  if (name === 'Wicketkeeper') return new THREE.Vector3(0, 0, -1.7);
  if (name === 'Bowler') return new THREE.Vector3(0.8, 0, 17.5);
  const [a, d] = POSITIONS[name];
  return new THREE.Vector3((leftHanded ? -1 : 1) * Math.sin(a * D2R) * d, 0, Math.cos(a * D2R) * d);
}

const yawOf = (dir) => Math.atan2(dir.x, dir.z);
const rotY = (v, yaw) => new THREE.Vector3(v.x * Math.cos(yaw) + v.z * Math.sin(yaw), v.y, -v.x * Math.sin(yaw) + v.z * Math.cos(yaw));
const lerpAngle = (a, b, u) => { let d = ((b - a + Math.PI) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI) - Math.PI; return a + d * u; };
const smooth = (u) => u * u * (3 - 2 * u);
// smooth start/stop profile: e(u) = u - sin(2πu)/2π, speed ∝ 1 - cos(2πu) (peak = 2 × average)
const ease = (u) => u - Math.sin(2 * Math.PI * u) / (2 * Math.PI);
// accelerate over the first 15 %, then hold full speed to the end (batsmen sprint into the crease)
const sprint = (u) => { const a = 0.15, v = 1 / (1 - a / 2); return u < a ? v * u * u / (2 * a) : v * (a / 2 + (u - a)); };
const V3 = (a) => new THREE.Vector3(a[0], a[1], a[2]);

// time for a fielder to cover a distance from standing (accelerate at A to VMAX)
// fallback ground speeds for in-place locomotion clips (m/s at timeScale 1)
const CLIP_SPEED = { Bat_Run: 6.0, Bat_Jog: 3.2, Bat_WalkOff: 1.2, F_Run: 6.5, F_Jog: 3.5, F_Walk: 1.4 };
// running between the wickets: crease to crease, ground the bat, turn
const RUN_TIME = 17.7 / 5.2 + 0.25, RUN_CYCLE = RUN_TIME + 0.6 + 0.25;
const VMAX = 7.0, ACC = 6.0, REACT = 0.25;
const runTime = (d) => { const da = VMAX * VMAX / (2 * ACC); return d < da ? Math.sqrt(2 * d / ACC) : VMAX / ACC + (d - da) / VMAX; };

// ---------------------------------------------------------------------------------------------------------
// Umpire: the fielder model in white with a hat, signalling out / four / six by posing the arms after the animation
class UmpireRig {
  constructor(actor) {
    this.actor = actor; const m = actor.model;
    const mats = new Map();
    m.traverse(o => {
      if (!o.isMesh) return;
      const src = o.material;
      if (!mats.has(src)) {
        const c = src.clone(), n = src.name || '';
        if (n.includes('Outfit_Top')) { c.map = null; c.color.set(0xf4f4f0); }
        else if (n.includes('Outfit_Bottom')) { c.map = null; c.color.set(0x2c3038); }
        else if (n.includes('Footwear')) { c.map = null; c.color.set(0x15161a); }
        mats.set(src, c);
      }
      o.material = mats.get(src);
    });
    const bone = (n) => m.getObjectByName(n);
    this.b = { R: [bone('RightArm_034'), bone('RightForeArm_035'), bone('RightHand_036')], L: [bone('LeftArm_011'), bone('LeftForeArm_012'), bone('LeftHand_013')] };
    this.addHat(bone('Head_06'), bone('HeadTop_End_07'));
  }
  // a white wide-brimmed hat sized from the head bones
  addHat(head, top) {
    if (!head || !top) return;
    const ws = head.getWorldScale(new THREE.Vector3()).x || 1, up = top.position.clone();      // head top in head-bone space
    const headLen = up.length() * ws, k = 1 / ws;                                              // metres -> bone space
    const mat = new THREE.MeshStandardMaterial({ color: 0xf6f6f2, roughness: 0.8 });
    const hat = new THREE.Group();
    const crownR = Math.max(0.12, headLen * 0.57);
    const crown = new THREE.Mesh(new THREE.SphereGeometry(crownR, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2), mat); crown.scale.y = 0.95;
    const brim = new THREE.Mesh(new THREE.CylinderGeometry(crownR * 1.7, crownR * 1.7, 0.012, 32), mat);
    hat.add(crown, brim); hat.scale.setScalar(k);
    hat.position.copy(up.clone().multiplyScalar(0.64));
    hat.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), up.clone().normalize());
    hat.traverse(o => { if (o.isMesh) o.castShadow = true; });
    head.add(hat); this.hat = hat;
  }
  // signals: [{ t, signal: 'out' | 'four' | 'six' }]; the arm is up for ~1.8 s from t
  apply(t, signals) {
    for (const sg of signals ?? []) {
      const u = t - sg.t; if (u < 0 || u > 2.2) continue;
      const w = THREE.MathUtils.smoothstep(u, 0, 0.35) * (1 - THREE.MathUtils.smoothstep(u, 1.8, 2.2));
      if (sg.signal === 'out') this.aim('R', new THREE.Vector3(0.08, 1, -0.12), w);
      else if (sg.signal === 'six') { this.aim('R', new THREE.Vector3(0.12, 1, 0), w); this.aim('L', new THREE.Vector3(-0.12, 1, 0), w); }
      else if (sg.signal === 'four') { const a = Math.sin(u * 7) * 0.9; this.aim('R', new THREE.Vector3(Math.sin(a), 0.15, -0.55).normalize(), w); }
    }
  }
  aim(side, dir, w) {
    const [arm, fore, hand] = this.b[side]; if (!arm || !fore || !hand) return;
    this.rot(arm, fore, dir, w); this.rot(fore, hand, dir, w);
  }
  // swing `bone` (world space) so that the vector to `child` points along `dir`, blended by w
  rot(bone, child, dir, w) {
    bone.updateWorldMatrix(true, true);
    const p = bone.getWorldPosition(v1), c = child.getWorldPosition(v2), cur = c.sub(p).normalize();
    const delta = q1.setFromUnitVectors(cur, dir);
    const bq = bone.getWorldQuaternion(q2), pq = bone.parent.getWorldQuaternion(q3).invert();
    const local = pq.multiply(delta.multiply(bq));
    bone.quaternion.slerp(local, w); bone.updateMatrixWorld(true);
  }
}
const v1 = new THREE.Vector3(), v2 = new THREE.Vector3(), q1 = new THREE.Quaternion(), q2 = new THREE.Quaternion(), q3 = new THREE.Quaternion();

// ---------------------------------------------------------------------------------------------------------
// Actor: one skinned character driven by time segments
class Actor {
  constructor(name, gltf, manifest, scene) {
    this.name = name;
    this.root = new THREE.Group(); this.root.name = name;
    this.model = cloneSkinned(gltf.scene); this.root.add(this.model); scene.add(this.root);
    this.model.traverse(o => { if (o.isMesh) { o.castShadow = true; o.frustumCulled = false; } if (o.name === 'CricketBall') o.visible = false; });
    this.mixer = new THREE.AnimationMixer(this.model);
    this.clips = Object.fromEntries(gltf.animations.map(c => [c.name, c]));
    this.manifest = manifest;
    this.actions = {};
    this.palm = { L: this.model.getObjectByName('Palm_L'), R: this.model.getObjectByName('Palm_R') };
    this.segs = [];
  }
  action(name) { return this.actions[name] ??= this.mixer.clipAction(this.clips[name]); }
  clear(pos, yaw, clip) { this.segs = []; this.state = { t: 0, pos: pos.clone(), yaw }; if (clip) this.hold(clip, 0, 1e9); }
  get end() { return this.state.t; }
  push(seg) { seg.t0 ??= this.state.t; this.segs.push(seg); this.state.t = seg.t1; }
  // play a clip in place at the current position (optionally turning to `yaw` during the first `turn` s)
  play(clip, { t0 = this.state.t, rate = 1, from = 0, dur, yaw = this.state.yaw, turn = 0.2, fade = 0.15, loop } = {}) {
    const m = this.manifest[clip] || {};
    dur ??= ((m.duration ?? this.clips[clip].duration) - from) / rate;
    const p = this.state.pos.clone(), y0 = this.state.yaw;
    const spd = !(loop ?? m.loop) && m.speed ? m.speed : 0, ev = m.events ? Object.values(m.events)[0] : null;
    const travelT = spd && ev ? ev.t + 0.3 : 0, fwd = rotY(new THREE.Vector3(0, 0, 1), yaw);
    const travel = (t) => spd * Math.min(Math.max(0, t - t0), travelT);
    this.push({ t0, t1: t0 + dur, clip, from, rate, fade, loop: loop ?? m.loop, pos: (t) => p.clone().addScaledVector(fwd, travel(t)), yaw: (t) => lerpAngle(y0, yaw, smooth(Math.min(1, (t - t0) / Math.max(turn, 1e-3)))) });
    this.state.yaw = yaw;
    if (spd) this.state.pos.addScaledVector(fwd, spd * travelT);
    if (m.root && (m.root[0] || m.root[1])) this.state.pos.add(rotY(new THREE.Vector3(m.root[0], 0, m.root[1]), yaw)); // dives etc. end displaced
    return t0;
  }
  hold(clip, time, dur, opts = {}) { return this.play(clip, { from: time, rate: 1e-9, dur, ...opts }); } // freeze a pose
  idle(clip, until) { if (until > this.state.t) this.play(clip, { dur: until - this.state.t, loop: true, turn: 0.3 }); }
  // run from the current position to B, arriving at time t1 (smooth start/stop), then turn to faceYaw
  moveTo(B, t1, { faceYaw, clips = ['F_Walk', 'F_Jog', 'F_Run'], fade = 0.2, profile = ease } = {}) {
    const A = this.state.pos.clone(), t0 = this.state.t, d = A.distanceTo(B);
    if (d < 0.05 || t1 <= t0 + 0.05) { this.state.pos.copy(B); if (faceYaw !== undefined) this.state.yaw = faceYaw; return; }
    const peak = (profile === ease ? 2 : 1.1) * d / (t1 - t0);
    const clip = peak > 4.5 ? clips[2] : peak > 2.0 ? clips[1] : clips[0], cs = this.manifest[clip]?.speed || CLIP_SPEED[clip] || 1;
    const dir = B.clone().sub(A).normalize(), runYaw = yawOf(dir), y0 = this.state.yaw, endYaw = faceYaw ?? runYaw;
    const T = t1 - t0;
    this.push({ t0, t1, clip, loop: true, fade,
      clipTime: (t) => (d * profile((t - t0) / T)) / cs,        // feet stay in step with the ground speed
      pos: (t) => A.clone().lerp(B, profile(THREE.MathUtils.clamp((t - t0) / T, 0, 1))),
      yaw: (t) => { const u = (t - t0) / T, a = Math.min(0.15, 0.9 / T), b = Math.max(0.8, 1 - 0.9 / T); return u < a ? lerpAngle(y0, runYaw, smooth(u / a)) : u > b ? lerpAngle(runYaw, endYaw, smooth((u - b) / (1 - b))) : runYaw; } });
    this.state.pos.copy(B); this.state.yaw = endYaw;
  }
  // world position of a clip-frame point for a clip started at the actor's current state
  clipPointWorld(local, pos = this.state.pos, yaw = this.state.yaw) { return pos.clone().add(rotY(V3(local), yaw)); }
  palmWorld(hand) {
    if (hand === 'both') return this.palm.L.getWorldPosition(new THREE.Vector3()).add(this.palm.R.getWorldPosition(new THREE.Vector3())).multiplyScalar(0.5);
    return this.palm[hand].getWorldPosition(new THREE.Vector3());
  }
  // clips from another model that shares this skeleton (the batsmen dive using the fielder's dive clip)
  addClips(clips, manifest) { for (const c of clips) this.clips[c.name] ??= c; this.manifest = Object.assign({}, manifest, this.manifest); }
  yawAt(t) {
    let i = this.segs.findIndex(s => t < s.t1); if (i < 0) i = this.segs.length - 1;
    const s = this.segs[i]; return s ? s.yaw(THREE.MathUtils.clamp(t, s.t0, s.t1)) : 0;
  }
  // root position at plan time t (pure: does not touch the skeleton)
  posAt(t) {
    let i = this.segs.findIndex(s => t < s.t1); if (i < 0) i = this.segs.length - 1;
    const s = this.segs[i]; return s ? s.pos(THREE.MathUtils.clamp(t, s.t0, s.t1)) : this.root.position.clone();
  }
  evaluate(t) {
    let i = this.segs.findIndex(s => t < s.t1); if (i < 0) i = this.segs.length - 1;
    const s = this.segs[i], prev = this.segs[i - 1];
    for (const a of Object.values(this.actions)) { a.enabled = false; a.setEffectiveWeight(0); }
    const set = (seg, w, tt) => {
      const a = this.action(seg.clip), m = this.manifest[seg.clip], dur = this.clips[seg.clip].duration;
      let ct = seg.clipTime ? seg.clipTime(tt) : seg.from + (tt - seg.t0) * seg.rate;
      ct = seg.loop ? ((ct % dur) + dur) % dur : THREE.MathUtils.clamp(ct, 0, dur - 1e-4);
      a.enabled = true; a.setEffectiveWeight(w); a.play(); a.paused = true; a.time = ct;
    };
    const w = prev && s.fade > 0 ? THREE.MathUtils.clamp((t - s.t0) / s.fade, 0, 1) : 1;
    set(s, w, t); if (w < 1) set(prev, 1 - w, Math.min(t, prev.t1));
    this.mixer.update(0);
    const tc = THREE.MathUtils.clamp(t, s.t0, s.t1);
    this.root.position.copy(s.pos(tc)); this.root.rotation.y = s.yaw(tc);
    if (w < 1) { // blend root to hide the hand-over between segments
      const pp = prev.pos(prev.t1), py = prev.yaw(prev.t1);
      this.root.position.lerpVectors(pp, this.root.position, w); this.root.rotation.y = lerpAngle(py, this.root.rotation.y, w);
    }
    if (this.showFrom !== undefined || this.hideAfter !== undefined) this.root.visible = !(t < (this.showFrom ?? -1e9)) && !(t > (this.hideAfter ?? 1e9));
    this.root.updateMatrixWorld(true);
    if (this.after) this.after(t);
  }
}

// ---------------------------------------------------------------------------------------------------------
// Ball: piecewise trajectory (flight / roll / held / rest)
class BallPath {
  constructor() { this.segs = []; }
  flight(t0, p0, v, t1) { this.segs.push({ type: 'flight', t0, t1, p0: p0.clone(), v: v.clone() }); return this; }
  roll(t0, p0, dir, v0, decel, t1) { this.segs.push({ type: 'roll', t0, t1, p0: p0.clone(), dir: dir.clone().setY(0).normalize(), v0, decel }); return this; }
  held(t0, t1, actor, hand) { this.segs.push({ type: 'held', t0, t1, actor, hand }); return this; }
  rest(t0, p, t1 = 1e9) { this.segs.push({ type: 'rest', t0, t1, p: p.clone() }); return this; }
  at(t) {
    const s = this.segs.find(s => t >= s.t0 && t < s.t1) ?? (t < this.segs[0]?.t0 ? this.segs[0] : this.segs.at(-1));
    if (!s) return new THREE.Vector3(0, -10, 0);
    const u = THREE.MathUtils.clamp(t, s.t0, s.t1) - s.t0;
    if (s.type === 'flight') return s.p0.clone().addScaledVector(s.v, u).add(new THREE.Vector3(0, 0.5 * G * u * u, 0));
    if (s.type === 'roll') { const tt = Math.min(u, s.v0 / s.decel); return s.p0.clone().addScaledVector(s.dir, s.v0 * tt - 0.5 * s.decel * tt * tt).setY(BALL_R); }
    if (s.type === 'held') return s.actor.palmWorld(s.hand);
    return s.p.clone();
  }
}
// ballistic velocity from p0 to p1 in time T
export const ballistic = (p0, p1, T) => p1.clone().sub(p0).sub(new THREE.Vector3(0, 0.5 * G * T * T, 0)).divideScalar(T);
// rolling ball: position / time along the ground
const rollPos = (p0, dir, v0, a, t) => { const tt = Math.min(t, v0 / a); return p0.clone().addScaledVector(dir, v0 * tt - 0.5 * a * tt * tt).setY(BALL_R); };

// ---------------------------------------------------------------------------------------------------------
export class FieldingSystem {
  constructor({ scene, battingGltf, fieldingGltf, field = DEFAULT_FIELD, leftHanded = false, stumps }) {
    this.scene = scene; this.leftHanded = leftHanded; this.stumpsApi = stumps; // stumps: { break(end, t), reset() } optional
    this.bm = battingGltf.scene.userData.batting.clips; this.fm = fieldingGltf.scene.userData.fielding.clips;
    this.striker = new Actor('Striker', battingGltf, this.bm, scene);
    this.nonStriker = new Actor('NonStriker', battingGltf, this.bm, scene);
    this.newBat = new Actor('NewBatsman', battingGltf, this.bm, scene);
    for (const a of [this.striker, this.nonStriker, this.newBat]) a.addClips(fieldingGltf.animations.filter(c => c.name === 'F_Dive_Forward'), this.fm);
    if (leftHanded) for (const a of [this.striker, this.nonStriker, this.newBat]) a.model.scale.x = -1;
    this.keeper = new Actor('Wicketkeeper', fieldingGltf, this.fm, scene);
    this.bowler = new Actor('Bowler', fieldingGltf, this.fm, scene);
    this.fielders = Object.fromEntries(field.map(n => [n, new Actor(n, fieldingGltf, this.fm, scene)]));
    this.umpire = new Actor('Umpire', fieldingGltf, this.fm, scene); this.umpireRig = new UmpireRig(this.umpire);
    this.umpire.after = (t) => this.umpireRig.apply(t, this.umpireSignals);
    this.umpireSignals = [];
    // the ball mesh from the fielding GLB
    const src = fieldingGltf.scene.getObjectByName('CricketBall');
    this.ball = src.clone(true); this.ball.visible = true; this.ball.position.set(0, -10, 0); scene.add(this.ball);
    this.events = [];
    this.reset();
  }
  get all() { return [this.striker, this.nonStriker, this.newBat, this.keeper, this.bowler, this.umpire, ...Object.values(this.fielders)]; }
  home(name) { return positionOf(name, this.leftHanded); }
  reset() {
    for (const a of this.all) { a.showFrom = a.hideAfter = undefined; a.root.visible = true; }
    this.newBat.clear(GATE_IN, 0, null); this.newBat.hold('Bat_WalkOff', 0, 1e9); this.newBat.showFrom = 1e9;
    this.striker.clear(new THREE.Vector3(0, 0, STRIKER_DZ), 0, 'Stance_Idle');
    this.nonStriker.clear(new THREE.Vector3(this.leftHanded ? -0.7 : 0.7, 0, 18.9), Math.PI, null);
    this.nonStriker.hold('Bat_Out_React', 0, 1e9);
    this.keeper.clear(this.home('Wicketkeeper'), 0, null); this.keeper.idle('K_Stance', 1e9);
    this.bowler.clear(this.home('Bowler'), Math.PI, null); this.bowler.idle('F_Idle', 1e9);
    for (const [n, a] of Object.entries(this.fielders)) { const p = this.home(n); a.clear(p, yawOf(new THREE.Vector3().sub(p)), null); a.idle('F_Ready', 1e9); }
    this.umpire.clear(UMPIRE_POS, Math.PI, null); this.umpire.idle('F_Idle', 1e9); this.umpireSignals = [];
    if (this.stumpsApi) for (const end of ['striker', 'nonStriker']) this.stumpsApi.set(end, false, 0);
    this.path = new BallPath(); this.events = []; this.duration = 3; this.meta = {};
  }

  // ---------- planning ----------
  // event = {
  //   shot: 'Drive_Cover' (batting clip),  direction?: deg (defaults to the shot's), runs: 0..6, boundary?: 4|6,
  //   aerial?: bool, distance?: m (where the ball is fielded / caught), fielder?: position name,
  //   fieldingAction?: 'pickup'|'dive'|'dive-catch'|...,   result: 'runs'|'caught'|'runout'|'stumped'|'caught-behind'|'dot'
  //   runoutEnd?: 'striker'|'nonStriker',  outBatsman?: 'striker'|'nonStriker',  seed?: number
  // }
  planBall(ev) {
    const sum = this._plan(ev);
    if (this.meta.wicket && this.meta.outActor) this.planExitEntry(this.meta, ev.entry);
    this.preroll();
    sum.duration = this.duration; sum.events = this.events.slice().sort((a, b) => a.t - b.t);
    return sum;
  }
  // until its first segment starts, every actor waits in that segment's first pose (a clip is never run early)
  preroll() {
    for (const a of this.all) {
      const s = a.segs[0]; if (!s || s.t0 <= this.start) continue;
      if (s.loop) { s.t0 = this.start; continue; }
      a.segs.unshift({ ...s, t0: this.start, t1: s.t0, rate: 1e-9, fade: 0, clipTime: undefined, pos: () => s.pos(s.t0), yaw: () => s.yaw(s.t0) });
    }
  }
  _plan(ev) {
    this.reset();
    const shot = ev.shot ?? 'Drive_Straight', sm = this.bm[shot];
    // non-striker backs up; keeper rises; striker plays the shot
    this.striker.segs = []; this.striker.state.t = 0;
    this.striker.play(shot, { turn: 0 });
    this.keeper.segs = []; this.keeper.state.t = 0; this.keeper.idle('K_Stance', 0.55); this.keeper.play('K_Rise');
    this.nonStriker.segs = []; this.nonStriker.state.t = 0; this.nonStriker.hold('Bat_Out_React', 0, 0.6);
    this.nonStriker.moveTo(this.nonStriker.state.pos.clone().add(new THREE.Vector3(0, 0, -1.2)), 1.2, { clips: ['Bat_WalkOff', 'Bat_Jog', 'Bat_Run'], faceYaw: Math.PI });
    for (const a of Object.values(this.fielders)) { a.segs = []; a.state.t = 0; a.idle('F_Ready', 1.0); }
    const release = this.planDelivery(ev, sm);
    // ---- delivery ----
    const b = sm.ball, rel = release, bnc = V3(b.bounce), crs = V3(b.atCrease);
    bnc.z += STRIKER_DZ; crs.z += STRIKER_DZ;
    const result = ev.result ?? 'runs';
    if (ev.wide) { const dx = typeof ev.wide === 'number' ? ev.wide : -1.7; bnc.x += dx; crs.x += dx; }   // wide: well outside the line
    this.path.flight(b.releaseTime, rel, ballistic(rel, bnc, b.bounceTime - b.releaseTime), b.bounceTime);
    this.meta = { tStart: this.meta.tStart, tRel: b.releaseTime, tContact: 1.0, contact: sm.contact ? V3(sm.contact.point).add(new THREE.Vector3(0, 0, STRIKER_DZ)) : null, entry: ev.entry ?? null };
    if (result === 'bowled' || result === 'lbw') return this.planStumps(ev, sm, result, bnc, crs);
    this.path.flight(b.bounceTime, bnc, ballistic(bnc, crs, 1.0 - b.bounceTime), 1.0);
    if (!sm.contact || result === 'stumped' || result === 'caught-behind') return this.planKeeperTake(ev, sm, crs, bnc);
    // ---- hit ----
    const dirDeg = (ev.direction ?? sm.shotAzimuthDeg) * (this.leftHanded ? -1 : 1);
    const dir = new THREE.Vector3(Math.sin(dirDeg * D2R), 0, Math.cos(dirDeg * D2R));
    const p0 = V3(sm.contact.point).add(new THREE.Vector3(0, 0, STRIKER_DZ));
    if (ev.boundary === 6) return this.planSix(ev, p0, dir);
    if (result === 'caught') return this.planCatch(ev, p0, dir);
    return this.planGround(ev, p0, dir);
  }

  // ----- the bowler: run-up from his mark, delivery clip timed so the hand is at the release point at release time -----
  // ev.bowling: 'fast' (default) | 'spin' | 'fast-left' | 'spin-left'
  planDelivery(ev, sm) {
    const kind = ev.bowling ?? 'fast', spin = kind.startsWith('spin'), left = kind.endsWith('left');
    const clip = (spin ? 'Bowl_Spin' : 'Bowl_Fast') + (left ? '_LeftArm' : ''), approach = spin ? 'Bowl_Spin_Approach' : 'Bowl_RunUp';
    const m = this.fm[clip], e = m.events.release, hand = m.ball, h = V3(e['palm' + hand]);
    const b = sm.ball, tRel = b.releaseTime, yaw = Math.PI, relXZ = V3(b.release);
    const R0 = relXZ.clone().setY(0).sub(rotY(h.clone().setY(0), yaw)); // root at the start of the delivery clip
    const tStart = tRel - e.t, runLen = spin ? 7 : 15, v = m.speedIn || this.fm[approach].speed;
    const T = runLen / (v * 0.93), mark = R0.clone().add(rotY(new THREE.Vector3(0, 0, -runLen), yaw));
    this.start = Math.min(-1, tStart - T - 0.8);
    const bw = this.bowler; bw.segs = []; bw.state = { t: this.start, pos: mark.clone(), yaw };
    bw.idle('F_Idle', tStart - T);                                     // waits at the top of his mark
    bw.moveTo(R0, tStart, { clips: [approach, approach, approach], faceYaw: yaw, profile: sprint, fade: 0.25 });
    bw.play(clip, { t0: tStart, yaw, turn: 0, fade: 0.08 });
    const release = R0.clone().add(rotY(h, yaw));
    this.path.held(-1e9, tRel, bw, hand === 'both' ? 'both' : hand);
    this.events.push({ t: tRel, type: 'release', by: clip });
    this.meta = { tStart, tRel };
    return release;
  }

  pickFielder(ev, point) {
    if (ev.fielder && this.fielders[ev.fielder]) return [ev.fielder, this.fielders[ev.fielder]];
    let best = null, bd = 1e9;
    for (const [n, a] of Object.entries(this.fielders)) { const d = a.state.pos.distanceTo(point); if (d < bd) { bd = d; best = [n, a]; } }
    return best;
  }

  // ----- aerial catch -----
  planCatch(ev, p0, dir) {
    const dist = ev.distance ?? 24, guess = p0.clone().addScaledVector(dir, dist);
    const [name, f] = this.pickFielder(ev, guess);
    const home = f.state.pos.clone(), toBat = new THREE.Vector3().sub(home).setY(0).normalize();
    // where the ball comes down relative to the fielder (deterministic from seed), and which catch that needs
    const rnd = mulberry(ev.seed ?? 7);
    const side = new THREE.Vector3(toBat.z, 0, -toBat.x);           // fielder's left
    const deep = home.length() > 50, act = ev.fieldingAction;
    let clip, offset;
    if (act === 'dive-catch' || (!act && rnd() < 0.25)) { const left = rnd() < 0.5; clip = left ? 'F_DiveCatch_Left' : 'F_DiveCatch_Right'; offset = side.clone().multiplyScalar((left ? 1 : -1) * 3.2); }
    else if (deep) { clip = 'F_Catch_Boundary'; offset = toBat.clone().multiplyScalar(-2 - 3 * rnd()); }
    else { const opts = ['F_Catch_Chest', 'F_Catch_High', 'F_Catch_Low', 'F_Catch_Overhead', 'F_Catch_Running', 'F_Catch_OneHand_Left', 'F_Catch_OneHand_Right'];
      clip = act && this.fm[act] ? act : opts[Math.floor(rnd() * opts.length)]; offset = side.clone().multiplyScalar((rnd() - 0.5) * 6).addScaledVector(toBat, (rnd() - 0.3) * 4); }
    const m = this.fm[clip], te = m.events.contact.t, h = m.ball === 'both' ? m.events.contact.between : m.ball === 'L' ? m.events.contact.palmL : m.events.contact.palmR;
    // catch point C: the fielder starts the clip at S facing the batsman, the clip's hand point lands on C
    const S = home.clone().add(offset); const yaw = yawOf(new THREE.Vector3().sub(S).setY(0));
    const speed = m.speed ?? 0, C = f.clipPointWorld(h, S, yaw).add(rotY(new THREE.Vector3(0, 0, speed * te), yaw));
    const T = THREE.MathUtils.clamp(1.0 + p0.distanceTo(C) / 16, 1.3, 4.2), tC = 1.0 + T;
    this.path.flight(1.0, p0, ballistic(p0, C, T), tC);
    // fielder: watch, move to S (arriving as the clip starts), catch, confirm
    f.idle('F_Ready', 1.0 + REACT);
    f.moveTo(S, tC - te, { faceYaw: yaw });
    if (speed) f.segs.at(-1).t1 -= 0; // running catch: the clip itself carries the run-in
    f.play(clip, { t0: tC - te, yaw });
    this.path.held(tC, 1e9, f, m.ball === 'both' ? 'both' : m.ball);
    f.play('F_Catch_Confirm', { turn: 0.3 });
    this.events.push({ t: tC, type: 'catch', by: name, clip });
    Object.assign(this.meta, { kind: 'caught', tCatch: tC, tKey: tC, keyPos: C.clone(), fielderActor: f, fielderName: name, wicket: true, outActor: this.striker, look: C.clone(), endName: 'striker' });
    this.keeper.idle('K_Stance', 1e9); this.bowler.idle('F_Idle', 1e9);
    for (const a of Object.values(this.fielders)) if (a !== f) a.idle('F_Ready', 1e9);
    this.duration = Math.max(tC + 4.5, 8);
    return this.summary(name, clip);
  }

  // ----- six: ball sails over, nearest deep fielder turns and watches -----
  planSix(ev, p0, dir) {
    const R = BOUNDARY + 22, land = p0.clone().addScaledVector(dir, R).setY(standHeight(R) + 0.3), T = 3.6;
    this.path.flight(1.0, p0, ballistic(p0, land, T), 1.0 + T).rest(1.0 + T, land);
    const tRope = 1.0 + T * (BOUNDARY - 0.5) / R;
    this.events.push({ t: tRope, type: 'boundary-six' });
    Object.assign(this.meta, { kind: 'six', tRope, tLand: 1.0 + T, landPos: land.clone(), ropePos: this.path.at(tRope), dir: dir.clone() });
    const [name, f] = this.pickFielder(ev, land);
    f.idle('F_Ready', 1.3); f.moveTo(f.state.pos.clone().addScaledVector(land.clone().sub(f.state.pos).setY(0).normalize(), 5), 3.6, { faceYaw: yawOf(land.clone().sub(f.state.pos)) });
    f.idle('F_Idle', 1e9); this.keeper.idle('K_Stance', 1e9); this.bowler.idle('F_Idle', 1e9);
    for (const a of Object.values(this.fielders)) if (a !== f) a.idle('F_Ready', 1e9);
    this.events.push({ t: 1.0 + T, type: 'six' });
    this.meta.fielderActor = f; this.meta.fielderName = name;
    this.duration = this.meta.tLand + 5; return this.summary(name, 'six');
  }

  // ----- four: the ball races to the rope and crosses it; the nearest fielder chases and pulls up -----
  planFour(ev, p0, dir) {
    const a = 5.0, dRope = BOUNDARY - 2, vRope = 9, v0 = Math.sqrt(vRope * vRope + 2 * a * dRope);
    const hitBounce = p0.clone().addScaledVector(dir, 2.0).setY(BALL_R), tb = 1.12;
    this.path.flight(1.0, p0, ballistic(p0, hitBounce, 0.12), tb);
    this.path.roll(tb, hitBounce, dir, v0, a, tb + v0 / a);
    const tRope = tb + (v0 - Math.sqrt(v0 * v0 - 2 * a * dRope)) / a, ropePos = rollPos(hitBounce, dir, v0, a, tRope - tb);
    const [name, f] = this.pickFielder(ev, ropePos);
    const stopAt = ropePos.clone().addScaledVector(dir, -1.5), yaw = yawOf(dir);
    f.idle('F_Ready', 1.0 + REACT); f.moveTo(stopAt, tRope + 0.5, { faceYaw: yaw }); f.play('F_Stop'); f.idle('F_Idle', 1e9);
    this.keeper.idle('K_Stance', 1e9); this.bowler.idle('F_Idle', 1e9);
    for (const o of Object.values(this.fielders)) if (o !== f) o.idle('F_Ready', 1e9);
    this.events.push({ t: tRope, type: 'four' });
    this.runBatsmen(0, null, 1.55, 1.2);
    Object.assign(this.meta, { kind: 'four', tRope, ropePos, dir: dir.clone(), fielderActor: f, fielderName: name });
    this.duration = tRope + 5; return this.summary(name, 'four');
  }

  // ----- ground ball: intercept, (dive/pickup), throw, batsmen run, maybe run-out -----
  planGround(ev, p0, dir) {
    const runs = ev.runs ?? 1, result = ev.result ?? 'runs', boundary = ev.boundary === 4;
    if (boundary) return this.planFour(ev, p0, dir);
    const decel = 2.4, D = ev.distance ?? (boundary ? 90 : 18 + 10 * runs);
    const v0 = Math.sqrt(2 * decel * (boundary ? 95 : D + 8));
    const hitBounce = p0.clone().addScaledVector(dir, 2.0).setY(BALL_R);  // squirts down off the bat first
    const tb = 1.0 + 0.12;
    this.path.flight(1.0, p0, ballistic(p0, hitBounce, 0.12), tb);
    const ballAt = (t) => rollPos(hitBounce, dir, v0, decel, t - tb);
    const [name, f] = this.pickFielder(ev, ballAt(tb + 1.5));
    const home = f.state.pos.clone();
    // choose the action: earliest point on the ball's path the fielder can reach (with each action's reach)
    const actions = boundary ? ['F_Pickup_Run'] : (ev.fieldingAction === 'dive' ? ['F_Dive_Left', 'F_Dive_Right'] : ['F_Pickup', 'F_Pickup_Run', 'F_Dive_Left', 'F_Dive_Right']);
    // earliest reachable point on the ball's path for each action; dive only if the ball would otherwise beat him
    const first = {};
    for (let t = tb + 0.3; t < tb + 12; t += 0.04) {
      const B = ballAt(t), yaw = yawOf(dir.clone().negate());
      for (const clip of actions) {
        if (first[clip]) continue;
        const m = this.fm[clip], e = m.events.contact ?? m.events.pickup, h = m.ball === 'both' ? e.between : e.palmR;
        const S = B.clone().sub(rotY(V3(h).setY(0), yaw)).sub(rotY(new THREE.Vector3(0, 0, (m.speed ?? 0) * e.t), yaw));
        const slack = (t - e.t) - (1.0 + REACT + runTime(home.distanceTo(S)));
        const ok = clip.startsWith('F_Dive') ? slack > -0.1 : slack > (clip === 'F_Pickup' ? 0.45 : 0.05);
        if (ok) first[clip] = { t, B, S, yaw, clip, e, m };
      }
    }
    const pick = (names) => names.map(n => first[n]).filter(Boolean).sort((x, y) => x.t - y.t)[0];
    const pickup = pick(['F_Pickup', 'F_Pickup_Run']), dive = pick(['F_Dive_Left', 'F_Dive_Right']);
    let plan = ev.fieldingAction === 'dive' ? (dive ?? pickup) : ev.fieldingAction === 'pickup' ? (pickup ?? dive)
      : (pickup && (!dive || pickup.t - dive.t < 0.7) ? pickup : dive ?? pickup);
    if (!plan) { const t = tb + 4, B = ballAt(t), yaw = yawOf(dir.clone().negate()), m = this.fm.F_Pickup, e = m.events.pickup; plan = { t, B, S: B.clone().sub(rotY(V3(e.between).setY(0), yaw)), yaw, clip: 'F_Pickup', e, m }; }
    const { t: tP, S, yaw, clip, e, m } = plan;
    // the ball rolls until it is gathered
    this.path.roll(tb, hitBounce, dir, v0, decel, tP);
    f.idle('F_Ready', 1.0 + REACT);
    f.moveTo(S, tP - e.t, { faceYaw: yaw });
    f.play(clip, { t0: tP - e.t, yaw });
    this.path.held(tP, 1e9, f, m.ball === 'both' ? 'both' : m.ball);
    this.events.push({ t: tP, type: clip.startsWith('F_Dive') ? 'dive-stop' : 'pickup', by: name, clip });

    return this.planRunsAndThrow(ev, { f, name, tP, clip, plan });
  }

  // ----- a thrown ball: a gravity arc from the hand to the target (optionally with one bounce) -----
  solveArc(p0, p1, speed, high) {
    const g = -G, d = p1.clone().sub(p0), dh = Math.max(Math.hypot(d.x, d.z), 0.3), dy = d.y;
    const vmin = Math.sqrt(g * (dy + Math.sqrt(dy * dy + dh * dh)));
    const v = Math.max(speed, vmin * 1.04);
    const disc = Math.max(0, v ** 4 - g * (g * dh * dh + 2 * dy * v * v)), tan = (v * v + (high ? 1 : -1) * Math.sqrt(disc)) / (g * dh);
    return { T: dh / (v * Math.cos(Math.atan(tan))), angle: Math.atan(tan) / D2R };
  }
  throwFlight(p0, p1, speed, { high = false, bounce = false } = {}) {
    if (!bounce) { const { T, angle } = this.solveArc(p0, p1, speed, high); return { segs: [{ p0, v: ballistic(p0, p1, T), T }], T, angle }; }
    const pb = p0.clone().lerp(p1, 0.55).setY(BALL_R), a1 = this.solveArc(p0, pb, speed, false);
    const hs = Math.hypot(...[p1.x - pb.x, p1.z - pb.z]), T2 = hs / (speed * Math.cos(a1.angle * D2R) * 0.85);
    return { segs: [{ p0, v: ballistic(p0, pb, a1.T), T: a1.T }, { p0: pb, v: ballistic(pb, p1, T2), T: T2 }], T: a1.T + T2, angle: a1.angle };
  }

  // The fielder's pick-up, the throw and the batsmen's running are planned together:
  // the number of runs is the scorecard's; their pace and any dive come from when the throw reaches the stumps.
  planRunsAndThrow(ev, c) {
    const { f, name, tP, clip } = c;
    const result = ev.result ?? 'runs', runout = result === 'runout', runs = ev.runs ?? 1;
    const N = runout ? runs + 1 : runs, odd = N % 2 === 1;
    const strikerEnd = odd ? 'nonStriker' : 'striker', nonStrikerEnd = odd ? 'striker' : 'nonStriker';
    const outBat = ev.outBatsman ?? (ev.runoutEnd ? (ev.runoutEnd === strikerEnd ? 'striker' : 'nonStriker') : 'striker');
    const outEnd = runout ? (outBat === 'striker' ? strikerEnd : nonStrikerEnd) : null;
    const target = outEnd ?? strikerEnd;                               // the end the ball is thrown to
    const receiver = target === 'striker' ? this.keeper : this.bowler, stumps = STUMPS[target];
    const thrower = f.state.pos.clone(), dThrow = Math.hypot(thrower.x - stumps.x, thrower.z - stumps.z);
    const direct = runout && dThrow < 24 && (ev.seed ?? 1) % 2 === 1;  // a direct hit at the stumps
    const rm = this.fm[runout ? 'K_Break_Stumps' : 'K_Collect'], rc = rm.events.contact;
    // the throw from a given spot: style from the distance and the situation, release point, curved flight to the receiver's hands
    const setup = (pos) => {
      const d = Math.hypot(pos.x - stumps.x, pos.z - stumps.z);
      let style, throwClip, speed, high = false, bounce = false;
      if (direct) { style = 'direct-hit'; throwClip = d < 9 ? 'F_Throw_Underarm' : 'F_Throw_Flat'; speed = 25; }
      else if (d < 10) { style = 'underarm'; throwClip = 'F_Throw_Underarm'; speed = 11; }
      else if (d < 28) { style = 'flat'; throwClip = 'F_Throw_Flat'; speed = 22; }
      else if (d < 52) { style = 'overarm'; throwClip = 'F_Throw_Overarm'; speed = 30; }
      else if (d < 66) { style = 'long-bounce'; throwClip = 'F_Throw_Overarm'; speed = 34; bounce = true; }
      else { style = 'high'; throwClip = 'F_Throw_Overarm'; speed = 31; high = true; }
      const tr = this.fm[throwClip].events.release, tYaw = yawOf(stumps.clone().sub(pos).setY(0));
      const towardThrower = pos.clone().sub(stumps).setY(0).normalize();
      const recvSpot = stumps.clone().addScaledVector(towardThrower, -0.55), recvYaw = yawOf(towardThrower);
      const relP = f.clipPointWorld(tr.palmR, pos, tYaw);
      const catchP = direct ? stumps.clone().setY(0.45) : receiver.clipPointWorld(rc.between, recvSpot, recvYaw);
      return { style, throwClip, tr, tYaw, towardThrower, recvSpot, recvYaw, relP, catchP, flight: this.throwFlight(relP, catchP, speed, { high, bounce }) };
    };
    let T = setup(thrower), tThrowStart = f.end;
    const arriveOf = (ts) => ts + 0.15 + T.tr.t + T.flight.T;
    const breakOf = (ts) => direct ? arriveOf(ts) : arriveOf(ts) - rc.t + (runout ? rm.events.break.t : 0);

    // ---- how fast the batsmen run, and whether anyone dives ----
    const TURN = 0.5, t0s = 1.4, t0n = 1.15, RUN_LEN = 17.7 - 2.99, clamp = THREE.MathUtils.clamp;
    let leg = 4.0, shortBy = () => 0;                                   // shortBy(ts): how much later than ts the throw has to start
    const dive = { striker: false, nonStriker: false };
    if (N > 0 && !runout) {
      const arr = arriveOf(tThrowStart);
      leg = clamp((arr - 1.3 - t0s - (N - 1) * TURN) / N, 2.6, 4.6);       // comfortable when the ball is far, a sprint when it is back quickly
      let A = t0s + N * leg + (N - 1) * TURN;
      if (arr - A < 0.3) { dive.striker = true; A -= 0.12; }               // a close finish: he dives for the line
      shortBy = (ts) => A + 0.3 - arriveOf(ts);                           // never beaten: a throw that would beat him is held back
    } else if (runout) {
      const brk = breakOf(tThrowStart);
      leg = clamp((brk - t0s - (N - 1) * TURN + 0.4) / N, 2.6, 5.0);
      const want = t0s + (N - 1) * (leg + TURN) + RUN_LEN / 7.5 + 0.45;    // the stumps can't go down before the deciding run is under way
      shortBy = (ts) => want - breakOf(ts);
    }
    let extra = shortBy(tThrowStart);
    let thrownFrom = thrower;
    if (extra > 0.3) {                                                  // the fielder walks the ball in meanwhile (a shorter throw, later)
      const dir = stumps.clone().sub(thrower).setY(0).normalize();
      thrownFrom = thrower.clone().addScaledVector(dir, Math.min(extra * 2.6, 0.4 * dThrow));
      f.moveTo(thrownFrom, f.end + extra, { faceYaw: yawOf(dir), clips: ['F_Walk', 'F_Jog', 'F_Run'], fade: 0.25 });
      tThrowStart = f.end; T = setup(thrownFrom); extra = shortBy(tThrowStart);
    }
    if (extra > 0.02) { const last = f.segs.at(-1); f.hold(last.clip, last.clipTime ? last.clipTime(last.t1) : last.from + (last.t1 - last.t0) * last.rate, extra, { fade: 0.1 }); tThrowStart = f.end; }
    const { style, throwClip, tr, tYaw, towardThrower, recvSpot, recvYaw, relP, catchP, flight } = T;

    // ---- the throw ----
    const tRel = tThrowStart + 0.15 + tr.t, tArrive = tRel + flight.T, tBreak = breakOf(tThrowStart);
    f.play(throwClip, { t0: tThrowStart + 0.15, yaw: tYaw, turn: 0.25 });
    f.idle('F_Idle', 1e9);
    this.path.segs.at(-1).t1 = tRel;                                    // released
    let t = tRel; for (const sg of flight.segs) { this.path.flight(t, sg.p0, sg.v, t + sg.T); t += sg.T; }
    if (direct) {
      const away = catchP.clone().addScaledVector(towardThrower, -4).setY(BALL_R);
      this.path.flight(tArrive, catchP, ballistic(catchP, away, 0.8), tArrive + 0.8).rest(tArrive + 0.8, away);
      this.events.push({ t: tBreak, type: 'stumps-broken', end: outEnd });
    } else {
      // the receiver gets behind the stumps in time, gathers (and breaks the stumps on a run-out)
      receiver.idle(target === 'striker' ? 'K_Stance' : 'F_Idle', Math.min(1.4, tArrive - rc.t - 1.2));
      receiver.moveTo(recvSpot, Math.max(receiver.end + 0.3, tArrive - rc.t - 0.05), { faceYaw: recvYaw });
      receiver.idle('F_Ready', tArrive - rc.t);
      receiver.play(runout ? 'K_Break_Stumps' : 'K_Collect', { t0: tArrive - rc.t, yaw: recvYaw });
      this.path.held(tArrive, 1e9, receiver, 'both');
      if (runout) { this.events.push({ t: tBreak, type: 'stumps-broken', end: outEnd }); receiver.play('K_Appeal'); }
      receiver.idle(target === 'striker' ? 'K_Stance' : 'F_Idle', 1e9);
    }
    this.events.push({ t: tRel, type: 'throw', style, clip: throwClip, angle: Math.round(flight.angle) });
    this.events.push({ t: tArrive, type: 'throw-received', by: direct ? 'stumps' : receiver.name });
    for (const a of Object.values(this.fielders)) if (a !== f) a.idle('F_Ready', 1e9);
    if (receiver !== this.keeper) this.keeper.idle('K_Stance', 1e9);
    if (receiver !== this.bowler) this.bowler.idle('F_Idle', 1e9);

    // ---- the batsmen ----
    this.runBatsmen({ N, leg, t0s, t0n, TURN, dive, runout: runout ? { tBreak, outBat } : null });
    const outActor = outBat === 'striker' ? this.striker : this.nonStriker;
    Object.assign(this.meta, { kind: runout ? 'runout' : 'ground', tPickup: tP, pickPos: c.plan?.B ?? thrower.clone(), fielderActor: f, fielderName: name, tThrow: tRel, tArrive,
      throwFrom: relP.clone(), throwTo: catchP.clone(), throwStyle: style, runsRun: N, tRunEnd: this.lastRunT,
      ...(runout ? { tKey: tBreak, keyPos: STUMPS[outEnd].clone().setY(0.4), stumpEnd: outEnd, wicket: true, outActor, endName: outEnd, look: STUMPS[outEnd].clone().setY(0.3) } : {}) });
    this.duration = Math.max(tArrive + 1.5, runout ? tBreak + 3 : 0, this.lastRunT + 1.5);
    return this.summary(name, clip);
  }

  // batsmen running between the wickets: exactly N runs, at the pace `leg`; the last run may be a dive
  runBatsmen(o) {
    const { N, leg, t0s, t0n, TURN, runout, dive } = o;
    this.lastRunT = 0;
    if (N <= 0) return;
    const zS = CREASE.striker, zN = CREASE.nonStriker, X = 0.5 * (this.leftHanded ? -1 : 1), RUN_LEN = 17.7 - 2.99;
    const legs = (actor, startZ, t0, isStriker) => {
      const key = isStriker ? 'striker' : 'nonStriker', x = X * (isStriker ? 1 : -1);
      actor.segs = actor.segs.filter(s => s.t0 < t0); actor.state.t = t0;
      let z = startZ, t = t0;
      for (let r = 1; r <= N; r++) {
        const toZ = z === zS ? zN : zS, dir = toZ > z ? 1 : -1, yaw = dir > 0 ? 0 : Math.PI, last = r === N;
        const isOut = !!runout && last && runout.outBat === key;
        let arrive = t + leg;
        if (runout && last && !isOut) arrive = Math.max(t + 2.5, Math.min(arrive, runout.tBreak - 0.5));
        actor.state.yaw = yaw;
        if (isOut || (last && dive[key])) {
          // sprint to the take-off point, dive (the hands cross the line when the clip lands), get up
          const short = isOut ? 0.9 : 0;
          const tD = isOut ? Math.max(runout.tBreak - 0.4, t + RUN_LEN / 7.5) : Math.max(arrive - 0.6, t + RUN_LEN / 7.5);
          const S = new THREE.Vector3(x, 0, toZ - dir * (2.09 + short));
          actor.moveTo(S, tD, { clips: ['Bat_Jog', 'Bat_Jog', 'Bat_Run'], faceYaw: yaw, fade: 0.25, profile: sprint });
          actor.play('F_Dive_Forward', { yaw, turn: 0.1, fade: 0.1 });
          arrive = tD + 0.6;
          this.events.push({ t: arrive, type: isOut ? 'dive-short' : 'dive', batsman: key });
          this.meta.dive = { t: tD, pos: S.clone(), batsman: key, out: isOut, dir };
          if (!isOut) actor.moveTo(new THREE.Vector3(x, 0, toZ + dir * 0.1), actor.end + 0.8, { clips: ['Bat_WalkOff', 'Bat_WalkOff', 'Bat_Jog'], faceYaw: yaw, fade: 0.2 });
        } else {
          const target = new THREE.Vector3(x, 0, toZ + (dir > 0 ? -0.6 : 0.6));
          actor.moveTo(target, arrive - 0.35, { clips: ['Bat_Jog', 'Bat_Jog', 'Bat_Run'], faceYaw: yaw, fade: 0.25, profile: sprint });
          actor.play('Bat_Ground', { yaw, turn: 0.1, dur: 0.6, fade: 0.1 });
        }
        this.lastRunT = Math.max(this.lastRunT, arrive + 0.6);
        z = toZ; t = actor.end;
        if (!last) { actor.play('Bat_Jog', { dur: 0.25, yaw: yaw + Math.PI, turn: 0.25 }); t = actor.end; }
      }
      if (!(runout && runout.outBat === key)) actor.hold('Bat_Out_React', 0, 1e9, { turn: 0.4 });
    };
    // the striker finishes his shot first
    const shotEnd = Math.min(this.striker.segs[0].t1, t0s);
    this.striker.segs[0].t1 = shotEnd; this.striker.state.t = shotEnd;
    legs(this.striker, zS, shotEnd, true); legs(this.nonStriker, zN - 1.2, t0n, false);
  }

  // ----- a dismissed batsman reacts, turns and walks off through the pavilion gate; the next one walks on -----
  planExitEntry(m, entry) {
    const out = m.outActor, kind = m.kind, tKey = m.tKey;
    const holdPose = (a, until) => {                              // keep the last pose (the actor may still be mid-clip) until `until`
      if (until <= a.end + 0.02) return;
      const l = a.segs.at(-1), ct = l.clipTime ? l.clipTime(l.t1) : l.from + (l.t1 - l.t0) * l.rate;
      a.hold(l.clip, ct, until - a.end, { fade: 0.1 });
    };
    const P0 = out.state.pos.clone();
    const tReact = Math.max(out.end, tKey + (kind === 'lbw' ? 1.3 : kind === 'bowled' ? 0.45 : kind === 'runout' ? 0.3 : 0.6));
    holdPose(out, tReact);
    out.play('Bat_Out_React', { t0: tReact, yaw: m.look ? yawOf(m.look.clone().sub(P0).setY(0)) : out.state.yaw, turn: 0.5 });
    const walk = (a, pts, speed) => {
      for (const w of pts) a.moveTo(w, a.end + Math.max(0.2, a.state.pos.distanceTo(w) / speed), { clips: ['Bat_WalkOff', 'Bat_WalkOff', 'Bat_WalkOff'], profile: (u) => u, fade: 0.35, faceYaw: w.faceYaw });
    };
    const tWalk0 = out.end, way = [];
    if (P0.z > 10) way.push(new THREE.Vector3(P0.x + 5, 0, P0.z - 1));   // clear of the pitch first
    way.push(GATE_IN.clone());
    walk(out, way, WALK_SPEED);
    out.hideAfter = out.end;
    const info = { tReact, tWalk0, tGone: out.end };
    let tEnd = out.end;
    if (entry?.name) {                                             // the next batsman: from the gate, round the pitch, takes guard
      const nb = this.newBat, end = m.endName ?? 'striker', tIn0 = tWalk0 + 12;
      const spot = end === 'striker' ? new THREE.Vector3(0, 0, STRIKER_DZ) : new THREE.Vector3(0.7 * (this.leftHanded ? -1 : 1), 0, 18.9), yawEnd = end === 'striker' ? 0 : Math.PI;
      const via = end === 'striker' ? new THREE.Vector3(3.2, 0, -1.6) : new THREE.Vector3(4.5, 0, 19.2);
      nb.segs = []; nb.state = { t: tIn0, pos: GATE_IN.clone(), yaw: yawOf(GATE_IN.clone().negate()) }; nb.showFrom = tIn0; nb.hideAfter = undefined;
      spot.faceYaw = yawEnd;
      walk(nb, [via, spot], ENTRY_SPEED);
      const tArr = nb.end;
      end === 'striker' ? nb.idle('Stance_Idle', 1e9) : nb.hold('Bat_Out_React', 0, 1e9);
      Object.assign(info, { tIn0, tArr, entryName: entry.name, entryEnd: end, entrySpot: spot.clone(), entryVia: via.clone() });
      tEnd = tArr;
    }
    Object.assign(m, info);
    for (const e of this.events) if (e.type === 'stumps-broken') e.tReset = (info.tIn0 ?? out.end) - 1;   // the umpire resets the stumps
    this.duration = Math.max(this.duration, tEnd + 4);
  }

  // ----- keeper takes: leave/dot, edge (caught behind), stumping -----
  planKeeperTake(ev, sm, crs, bnc = V3(sm.ball.bounce)) {
    const result = ev.result ?? 'dot', b = sm.ball;
    const dir = crs.clone().sub(bnc).normalize(), vz = dir.z * 30;
    const k = this.keeper; k.segs = []; k.state.t = 0;
    let clip = result === 'stumped' ? 'K_Stumping' : result === 'caught-behind' ? 'K_Catch_Edge' : 'K_Collect';
    const m = this.fm[clip], ce = m.events.contact;
    if (ev.wide) { // a wide: the keeper moves across to gather it
      k.idle('K_Stance', 0.1);
      k.moveTo(k.state.pos.clone().add(new THREE.Vector3(THREE.MathUtils.clamp(crs.x - ce.between[0], -2.2, 2.2), 0, 0)), 0.85, { faceYaw: 0 });
    } else k.idle('K_Stance', 0.55);
    const kPos = k.state.pos.clone();
    const take = k.clipPointWorld(ce.between, kPos, 0);
    // ball continues from the crease to the gloves
    const T = Math.max(0.12, (crs.z - take.z) / Math.max(10, -vz || 25));
    this.path.flight(1.0, crs, ballistic(crs, take, T), 1.0 + T);
    k.play('K_Rise', { dur: Math.max(0.1, 1.0 + T - ce.t - k.end) });
    k.play(clip, { t0: 1.0 + T - ce.t });
    this.path.held(1.0 + T, 1e9, k, 'both');
    if (result === 'stumped') this.events.push({ t: 1.0 + T - ce.t + m.events.break.t, type: 'stumps-broken', end: 'striker' });
    if (result !== 'dot') k.play('K_Appeal');
    k.idle('K_Stance', 1e9); this.bowler.idle('F_Idle', 1e9);
    for (const a of Object.values(this.fielders)) a.idle('F_Ready', 1e9);
    this.events.push({ t: 1.0 + T, type: result === 'dot' ? 'keeper-take' : result });
    const tTake = 1.0 + T, tKey = result === 'stumped' ? tTake - ce.t + m.events.break.t : tTake;
    Object.assign(this.meta, { kind: result === 'dot' ? 'keeper' : result, tTake, tKey, keyPos: take.clone(), wicket: result !== 'dot', stumpEnd: 'striker', outActor: this.striker, look: take.clone(), endName: 'striker' });
    this.duration = 5.5; return this.summary('Wicketkeeper', clip);
  }

  // ----- bowled / lbw: the delivery beats the bat and the ball ends at the stumps / the front pad -----
  planStumps(ev, sm, result, bnc, crs) {
    const b = sm.ball, bt = b.bounceTime, vz = (crs.z - bnc.z) / (1.0 - bt);
    const target = new THREE.Vector3(0.02, 0.42, STUMPS.striker.z);
    let tHit, from;
    if (result === 'lbw') {                        // where the front shin is when the ball arrives
      this.striker.evaluate(0.9);
      const leg = this.striker.model.getObjectByName('LeftLeg_058'), foot = this.striker.model.getObjectByName('LeftFoot_059');
      const pad = leg.getWorldPosition(new THREE.Vector3()).lerp(foot.getWorldPosition(new THREE.Vector3()), 0.25);
      target.set(pad.x + 0.02, THREE.MathUtils.clamp(pad.y, 0.25, 0.5), pad.z + 0.1);
    }
    tHit = bt + (target.z - bnc.z) / vz;
    this.path.flight(bt, bnc, ballistic(bnc, target, tHit - bt), tHit);
    const away = result === 'lbw' ? new THREE.Vector3(target.x + 0.5, BALL_R, target.z + 1.3) : new THREE.Vector3(0.6, BALL_R, STUMPS.striker.z - 5);
    this.path.flight(tHit, target, ballistic(target, away, 0.7), tHit + 0.7).rest(tHit + 0.7, away);
    this.events.push({ t: tHit, type: result === 'lbw' ? 'pad-hit' : 'stumps-broken', end: 'striker', style: 'bowled' });
    // the bowler and keeper appeal
    const k = this.keeper; k.segs = []; k.state.t = 0; k.idle('K_Stance', 0.55); k.play('K_Rise'); k.idle('K_Stance', tHit + 0.15); k.play('K_Appeal'); k.idle('K_Stance', 1e9);
    this.bowler.idle('F_Idle', tHit + 0.3); this.bowler.play('K_Appeal'); this.bowler.idle('F_Idle', 1e9);
    for (const a of Object.values(this.fielders)) a.idle('F_Ready', 1e9);
    Object.assign(this.meta, { kind: result, tKey: tHit, keyPos: target.clone(), wicket: true, stumpEnd: 'striker', outActor: this.striker, endName: 'striker',
      look: result === 'lbw' ? UMPIRE_POS.clone().setY(1.5) : new THREE.Vector3(0, 0.3, STUMPS.striker.z) });
    this.duration = tHit + 6;
    return this.summary('Wicketkeeper', result);
  }

  summary(fielder, action) { return { fielder, action, start: this.start ?? 0, events: this.events.slice().sort((a, b) => a.t - b.t), duration: this.duration, meta: this.meta }; }

  // ---------- evaluation ----------
  update(t) {
    for (const a of this.all) { if (!a.segs.length) continue; a.evaluate(t); }
    this.ball.position.copy(this.path.at(t));
    if (this.stumpsApi) for (const e of this.events) if (e.type === 'stumps-broken') this.stumpsApi.set(e.end, t >= e.t && t < (e.tReset ?? 1e9), t - e.t, e);
  }
}

function mulberry(a) { return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
