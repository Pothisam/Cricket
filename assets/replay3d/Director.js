// Director.js — turns one planned ball into a broadcast-style sequence of camera cuts, slow-motion replays and umpire close-ups.
//
// A ball is a list of "cuts". Each cut plays a span of the plan's timeline [t0, t1] at some rate with one camera shot:
//   bowler run-up -> delivery -> ball chase -> batsman -> ball follow -> fielder / rope / crowd -> ... -> wide
// For a wicket, after the live action the key moment is replayed in slow motion from a close-up camera, then the umpire
// is shown giving the decision, then the normal view returns. Everything is a pure function of (plan time), so the
// replay can be scrubbed and the camera never depends on previous frames.
import * as THREE from 'three';
import { STUMPS, UMPIRE_POS, GATE_DIR } from './FieldingSystem.js';

const V = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
const smooth = (u) => { u = Math.min(1, Math.max(0, u)); return u * u * (3 - 2 * u); };
const hdir = (a, b) => { const d = b.clone().sub(a); d.y = 0; return d.lengthSq() > 1e-5 ? d.normalize() : null; };
const perp = (d) => V(d.z, 0, -d.x);

export class Director {
  constructor(fs, camera) { this.fs = fs; this.camera = camera; this.cuts = []; this.total = 0; this.reveal = 0; this.crowd = []; }

  // ---- building the sequence ----------------------------------------------------------------------------------
  build(plan) {
    const fs = this.fs, m = this.m = plan.meta, end = plan.duration, tC = m.tContact ?? 1.0;
    const cuts = this.cuts = [];
    const signals = [], crowd = this.crowd = [];
    let cur = plan.start;
    const add = (t0, t1, shot, o = {}) => cuts.push({ t0, t1, shot, rate: o.rate ?? 1, mode: o.mode ?? 'live', blend: o.blend ?? 0.4, args: o.args ?? {} });
    const seq = (shot, until, o = {}) => { until = Math.min(until, end); if (until > cur + 0.05) { add(cur, until, shot, o); cur = until; } };
    const slow = (a, b, shot, o = {}) => add(a, b, shot, { rate: 0.25, mode: 'replay', blend: 0, ...o });
    const umpire = (tSignal, signal, until) => { signals.push({ t: tSignal, signal }); seq('umpire', until ?? tSignal + 1.7, { mode: 'umpire', blend: 0 }); };
    this.markers = {};
    let tailed = false;
    // after a wicket: the dismissed batsman reacts and leaves; the next batsman is introduced, walks on and takes guard
    const tail = () => {
      tailed = true;
      const tR = m.tReact, tW = m.tWalk0, tExitEnd = Math.min(tW + 5.8, m.tGone);
      add(tR - 0.3, tW + 0.3, 'reaction');
      add(tW + 0.3, tExitEnd, 'exit');
      let tLast = tExitEnd;
      if (m.entryName) {
        add(m.tIn0, m.tIn0 + 3.2, 'gate', { args: { lowerThird: true } });
        add(m.tArr - 6.0, m.tArr - 1.5, 'approach', { args: { lowerThird: true } });
        add(m.tArr - 1.5, m.tArr + 2.2, 'stance');
        tLast = m.tArr + 2.2;
      }
      add(tLast, tLast + 1.8, 'wide');
      cur = end;
    };

    // bowler takes position, runs in, delivers, the ball is released
    seq('runup', m.tStart + 0.3);
    seq('release', m.tRel + 0.12);
    const hits = !!m.contact && !['bowled', 'lbw', 'keeper', 'stumped', 'caught-behind'].includes(m.kind);
    const tFirst = hits ? tC : (m.kind === 'bowled' || m.kind === 'lbw' ? m.tKey : m.tTake);
    seq('chase', tFirst - (hits ? 0.12 : 0.3), { args: { back: 7, up: 1.4 } });

    const wicketTail = (tKey, shotLive, shotSlow, o = {}) => {       // live moment, slow-motion replay, umpire, back to normal
      seq(shotLive, tKey + 0.5);
      slow(tKey - (o.pre ?? 0.8), tKey + (o.post ?? 0.55), shotSlow);
      this.markers.reveal = { t: tKey };
      if (o.umpire !== false) { umpire(tKey + 1.1, 'out', tKey + 3.0); this.markers.reveal = { cutIndex: cuts.length - 1, t: tKey + 1.1 }; }
      tail();
      crowd.push({ a: tKey, b: tKey + 3, amp: 0.4 });
    };

    switch (m.kind) {
      case 'bowled': wicketTail(m.tKey, 'stumps', 'stumpsClose', { umpire: false }); break;
      case 'lbw': wicketTail(m.tKey, 'batsman', 'padClose', { pre: 0.9, post: 0.5 }); break;
      case 'keeper': seq('keeper', m.tTake + 1.4); seq('wide', end); this.markers.reveal = { t: m.tTake }; break;
      case 'caught-behind': wicketTail(m.tKey, 'keeper', 'keeperClose'); break;
      case 'stumped': wicketTail(m.tKey, 'keeper', 'stumpedClose', { pre: 1.0, post: 0.5 }); break;
      default: {
        seq('batsman', tC + 0.5);
        if (m.kind === 'six') {
          seq('follow', m.tLand, { args: { back: 11, up: 3.2 } });
          seq('crowd', m.tLand + 1.3);
          this.markers.reveal = { t: m.tRope };
          crowd.push({ a: m.tRope, b: m.tLand + 4.5, amp: 1 });
          umpire(m.tLand + 1.8, 'six', m.tLand + 3.8);
          seq('wide', end);
        } else if (m.kind === 'four') {
          seq('follow', m.tRope - 0.8);
          seq('rope', m.tRope + 1.2);
          this.markers.reveal = { t: m.tRope };
          crowd.push({ a: m.tRope, b: m.tRope + 3.5, amp: 0.6 });
          umpire(m.tRope + 1.6, 'four', m.tRope + 3.5);
          seq('wide', end);
        } else if (m.kind === 'caught') {
          seq('follow', m.tCatch - 0.35);
          wicketTail(m.tKey, 'fielder', 'catchClose', { pre: 0.9, post: 0.6 });
        } else {                                                    // ground ball: fielded, thrown, the batsmen run (maybe a dive, maybe a run-out)
          seq('follow', m.tPickup - 0.4);
          seq('fielder', m.tPickup + 1.0);
          seq('run', m.tThrow - 0.15);
          seq('throwArc', Math.min(m.tArrive + 0.5, m.dive ? m.dive.t - 0.4 : 1e9));
          const live = m.kind === 'runout' ? m.tKey + 0.5 : Math.max(cur, (m.tRunEnd || 0) + 0.5);
          if (m.dive) seq('diveCam', Math.max(live, m.dive.t + 1.9));
          seq('run', live);
          if (m.kind === 'runout') {
            slow(m.tKey - 0.9, m.tKey + 0.6, 'runoutClose');
            this.markers.reveal = { t: m.tKey };
            umpire(m.tKey + 1.1, 'out', m.tKey + 3.0);
            this.markers.reveal = { cutIndex: cuts.length - 1, t: m.tKey + 1.1 };
            tail();
            crowd.push({ a: m.tKey, b: m.tKey + 3, amp: 0.4 });
          } else {
            this.markers.reveal = { t: m.tPickup };
            seq('wide', end);
          }
        }
      }
    }
    if (!tailed && cur < end - 0.05) seq('wide', end);
    fs.umpireSignals = signals;

    let r = 0;
    for (const c of cuts) { c.real0 = r; r += (c.t1 - c.t0) / c.rate; c.real1 = r; }
    this.total = r;
    this.reveal = this.realOf(this.markers.reveal);
    return { total: this.total, reveal: this.reveal };
  }

  // real time at which plan time `t` is shown (in the cut given, else the first live cut that shows it)
  realOf(mk) {
    if (!mk) return this.total * 0.8;
    const cs = this.cuts;
    const inCut = (c) => mk.t >= c.t0 && mk.t <= c.t1;
    const c = mk.cutIndex != null ? cs[mk.cutIndex] : cs.find(c => c.mode === 'live' && inCut(c)) ?? cs.find(inCut);
    return c ? c.real0 + (mk.t - c.t0) / c.rate : this.total * 0.8;
  }

  // ---- playback -----------------------------------------------------------------------------------------------
  cutAt(u) {
    const cs = this.cuts; let i = cs.findIndex(c => u < c.real1); if (i < 0) i = cs.length - 1;
    return i;
  }
  timeAt(u) { const i = this.cutAt(u), c = this.cuts[i]; return { i, cut: c, tp: c.t0 + Math.min(Math.max(0, u - c.real0), c.real1 - c.real0) * c.rate }; }
  crowdAmp(tp) { let a = 0; for (const c of this.crowd) if (tp >= c.a && tp <= c.b) a = Math.max(a, c.amp * smooth((tp - c.a) / 0.4)); return a; }

  // position the camera for real time u (call after fs.update(tp))
  apply(u, { i, cut, tp }) {
    const pose = this.shot(cut.shot, tp, cut);
    const since = u - cut.real0;
    if (cut.blend > 0 && i > 0 && since < cut.blend) {
      const pc = this.cuts[i - 1], prev = this.shot(pc.shot, pc.t1, pc), k = smooth(since / cut.blend);
      pose.pos.lerpVectors(prev.pos, pose.pos, k); pose.look.lerpVectors(prev.look, pose.look, k); pose.fov = prev.fov + (pose.fov - prev.fov) * k;
    }
    const cam = this.camera;
    cam.position.copy(pose.pos); cam.lookAt(pose.look);
    if (Math.abs(cam.fov - pose.fov) > 1e-3) { cam.fov = pose.fov; cam.updateProjectionMatrix(); }
  }

  // ---- the shots (each a pure function of plan time) ----------------------------------------------------------
  shot(name, tp, cut) {
    const fs = this.fs, m = this.m, ball = () => fs.path.at(tp);
    const P = (pos, look, fov = 40) => ({ pos, look, fov });
    switch (name) {
      case 'runup': {                                 // behind the bowler, following him in
        const b = fs.bowler.posAt(tp);
        return P(V(b.x + 2.6, 2.0, b.z + 6.0), V(b.x, 1.1, b.z - 2.0), 42);
      }
      case 'release': {                               // in front of the delivery stride, tracking the hand and the ball
        const b = fs.bowler.posAt(m.tRel), hand = ball();
        return P(V(b.x - 3.4, 1.5, b.z - 5.0), hand.lerp(V(b.x, 1.5, b.z), 0.15), 36);
      }
      case 'chase': case 'follow': {                  // behind the ball, looking where it is going
        const a = cut.args, b = ball(), d = hdir(fs.path.at(tp - 0.15), fs.path.at(tp + 0.2)) ?? V(0, 0, -1);
        const back = a.back ?? 9, up = a.up ?? 2.4;
        const pos = b.clone().addScaledVector(d, -back).addScaledVector(perp(d), a.side ?? 2.6); pos.y = up + b.y * 0.45;
        return P(pos, b.clone().addScaledVector(d, 3), name === 'chase' ? 36 : 42);
      }
      case 'batsman': {                               // close on the batsman as the bat meets the ball
        const c = m.contact ?? m.keyPos ?? V(0, 0.6, 0.5), t0 = (m.tContact ?? 1) - 0.12;
        const k = smooth((tp - t0) / 0.8);
        return P(V(2.9, 1.25, 3.3), V(c.x * 0.6, 0.9, 0.5), 40 - 6 * k);
      }
      case 'fielder': {                               // in front of the fielder, looking back at him
        const f = (m.fielderActor ?? fs.keeper).posAt(tp), toBat = hdir(f, V()) ?? V(0, 0, -1);
        const look = V(f.x, 1.0, f.z).lerp(ball(), 0.25);
        return P(f.clone().addScaledVector(toBat, 5.5).addScaledVector(perp(toBat), 2.4).setY(1.5), look, 42);
      }
      case 'rope': {                                  // static beside the rope, the ball crosses the frame
        const d = m.dir, r = m.ropePos;
        return P(r.clone().addScaledVector(d, -9).addScaledVector(perp(d), 8).setY(1.4), ball(), 44);
      }
      case 'crowd': {                                 // from the stands, the ball landing in the crowd
        const d = m.dir, l = m.landPos;
        return P(l.clone().addScaledVector(d, -34).addScaledVector(perp(d), 10).add(V(0, 12, 0)), l, 44);
      }
      case 'umpire': {                                // close on the umpire's upper body and hat
        const U = UMPIRE_POS;
        return P(V(U.x + 1.9, 1.7, U.z - 2.7), V(U.x, 1.35, U.z), 36);
      }
      case 'keeper': {
        const look = V(0, 0.95, -1.6).lerp(ball(), 0.3);
        return P(V(1.7, 1.15, -4.4), look, 40);
      }
      case 'stumps': {                                // low, off side and just behind the striker's stumps, looking back down the pitch
        return P(V(-1.9, 0.45, -2.7), V(0, 0.45, 0.1).lerp(ball(), 0.1), 42);
      }
      case 'stumpsClose': return P(V(-1.5, 0.4, -2.2), V(0, 0.4, -0.15), 36);
      case 'padClose': { const p = m.keyPos; return P(p.clone().add(V(-1.7, 0.3, 1.8)), p.clone().add(V(0, 0.1, 0)), 36); }
      case 'catchClose': {
        const C = m.keyPos, toBat = hdir(C, V()) ?? V(0, 0, -1);
        return P(C.clone().addScaledVector(toBat, 3.6).addScaledVector(perp(toBat), 2.0).add(V(0, 0.5, 0)), C.clone().lerp(ball(), 0.12), 44);
      }
      case 'keeperClose': { const K = m.keyPos; return P(K.clone().add(V(-1.7, 0.35, 1.3)), K.clone(), 36); }
      case 'stumpedClose': return P(V(-2.0, 0.8, 0.5), V(0, 0.55, -1.0), 38);
      case 'runoutClose': {
        const E = STUMPS[m.stumpEnd], s = m.stumpEnd === 'striker' ? 1 : -1;
        return P(V(E.x - 2.4, 0.8, E.z + s * 2.6), V(E.x, 0.3, E.z + s * 1.0), 42);
      }
      case 'run': return P(V(-17, 4.5, 10), V(0, 1.1, 10), 55);
      case 'throwArc': {                              // from the side, so the arc of the throw is clear
        const a = m.throwFrom, b = m.throwTo, mid = a.clone().lerp(b, 0.5), len = Math.hypot(b.x - a.x, b.z - a.z), d = hdir(a, b) ?? V(0, 0, 1);
        return P(mid.clone().addScaledVector(perp(d), Math.max(10, len * 0.55)).add(V(0, 2.5 + len * 0.07, 0)), ball().lerp(mid, 0.25), 44);
      }
      case 'diveCam': {                               // low, beside the crease where the dive ends
        const d = m.dive, z = d.pos.z + d.dir * 2.2;
        return P(V(-3.4, 0.9, z), V(d.pos.x, 0.3, z), 42);
      }
      case 'reaction': {                              // in front of the dismissed batsman as he reacts
        const a = m.outActor, P0 = a.posAt(tp), yaw = a.yawAt(tp), f = V(Math.sin(yaw), 0, Math.cos(yaw));
        return P(P0.clone().addScaledVector(f, 3.6).addScaledVector(perp(f), 1.0).setY(1.5), P0.clone().add(V(0, 1.2, 0)), 36);
      }
      case 'exit': case 'approach': {                 // ahead of the walking batsman, looking back at him
        const a = name === 'exit' ? m.outActor : fs.newBat, P0 = a.posAt(tp), h = hdir(a.posAt(tp - 0.4), a.posAt(tp + 0.4)) ?? V(Math.sin(a.yawAt(tp)), 0, Math.cos(a.yawAt(tp)));
        return P(P0.clone().addScaledVector(h, 6.5).addScaledVector(perp(h), 2.2).setY(1.6), P0.clone().add(V(0, 1.1, 0)), 40);
      }
      case 'gate': {                                  // inside the boundary, the new batsman coming out of the pavilion gate
        const P0 = fs.newBat.posAt(tp);
        return P(GATE_DIR.clone().multiplyScalar(52).addScaledVector(perp(GATE_DIR), 5).setY(1.6), P0.clone().add(V(0, 1.1, 0)), 40);
      }
      case 'stance': {                                // the new batsman taking guard
        const sp = m.entrySpot, back = sp.z > 10 ? -1 : 1;
        return P(V(sp.x + 2.6, 1.3, sp.z + back * 3.0), V(sp.x, 1.0, sp.z), 38);
      }
      case 'wide': default: return P(V(-5 + tp * 0.3, 9, 31), V(0, 0.8, 6), 46);
    }
  }
}
