// Stands.js — a simple stadium bowl: tiered concrete rings, a crowd that can celebrate, advertising boards and floodlights.
import * as THREE from 'three';
import { BOUNDARY, STAND_IN, STAND_OUT, standHeight, GATE_DIR } from './FieldingSystem.js';

const PALETTE = [0x1f5fbf, 0xf2f2f2, 0xff8a1f, 0xd62839, 0x2a9d8f, 0xf4d35e, 0x264653, 0xe9c46a];

export function buildStands(scene) {
  const group = new THREE.Group(); scene.add(group);
  // seating bowl: three bands that climb away from the field
  const tiers = [[STAND_IN, 86, 0x8d949c], [86, 98, 0x7a828b], [98, STAND_OUT, 0x6a727b]];
  for (const [r0, r1, color] of tiers) {
    const h0 = standHeight(r0), h1 = standHeight(r1);
    const geo = new THREE.CylinderGeometry(r1, r0, h1 - h0, 96, 1, true);
    const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ color, side: THREE.DoubleSide, roughness: 0.95 }));
    mesh.position.y = (h0 + h1) / 2; mesh.receiveShadow = true; group.add(mesh);
  }
  // back wall + advertising boards at the front
  const wall = new THREE.Mesh(new THREE.CylinderGeometry(STAND_OUT + 0.5, STAND_OUT + 0.5, 12, 96, 1, true), new THREE.MeshStandardMaterial({ color: 0x555b63, side: THREE.DoubleSide }));
  wall.position.y = standHeight(STAND_OUT) + 5; group.add(wall);
  const gateTheta = Math.atan2(GATE_DIR.x, GATE_DIR.z), gap = 0.075;       // the boards stop short of the pavilion gate
  const boards = new THREE.Mesh(new THREE.CylinderGeometry(BOUNDARY + 4, BOUNDARY + 4, 1.0, 96, 1, true, gateTheta + gap, Math.PI * 2 - gap * 2), new THREE.MeshBasicMaterial({ color: 0x103a7a, side: THREE.DoubleSide }));
  boards.position.y = 0.5; group.add(boards);
  // the pavilion gate: a small block with a dark doorway where players leave and enter the field
  const gate = new THREE.Group(); gate.position.copy(GATE_DIR).multiplyScalar(76.2); gate.position.y = 1.9; gate.rotation.y = gateTheta; group.add(gate);
  const block = new THREE.Mesh(new THREE.BoxGeometry(5.6, 3.8, 6.4), new THREE.MeshStandardMaterial({ color: 0x4b525a })); gate.add(block);
  const door = new THREE.Mesh(new THREE.PlaneGeometry(2.3, 2.7), new THREE.MeshBasicMaterial({ color: 0x050505 })); door.position.set(0, -0.55, -3.22); door.rotation.y = Math.PI; gate.add(door);
  const cv = document.createElement('canvas'); cv.width = 256; cv.height = 64; const cx = cv.getContext('2d');
  cx.fillStyle = '#0b2d6b'; cx.fillRect(0, 0, 256, 64); cx.fillStyle = '#f2b705'; cx.font = 'bold 34px system-ui, sans-serif'; cx.textAlign = 'center'; cx.textBaseline = 'middle'; cx.fillText('PAVILION', 128, 34);
  const sign = new THREE.Mesh(new THREE.PlaneGeometry(3.4, 0.85), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(cv) })); sign.position.set(0, 1.45, -3.23); sign.rotation.y = Math.PI; gate.add(sign);
  // floodlight towers
  const poleMat = new THREE.MeshStandardMaterial({ color: 0x8a8f96 }), lampMat = new THREE.MeshBasicMaterial({ color: 0xfff6d8 });
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2 + 0.5, x = Math.sin(a) * (STAND_OUT + 6), z = Math.cos(a) * (STAND_OUT + 6);
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.7, 1.1, 46, 8), poleMat); pole.position.set(x, 23, z); group.add(pole);
    const lamp = new THREE.Mesh(new THREE.BoxGeometry(10, 5, 1.2), lampMat); lamp.position.set(x, 47, z); lamp.lookAt(0, 30, 0); group.add(lamp);
  }
  // crowd: one instanced box per spectator, in rows following the slope
  const spots = [];
  for (let r = STAND_IN + 3; r < STAND_OUT - 1; r += 2.1) {
    const n = Math.floor((2 * Math.PI * r) / 1.35);
    for (let i = 0; i < n; i++) spots.push({ a: (i / n) * Math.PI * 2 + (r * 7.13 % 1) * 0.2, r, y: standHeight(r) + 0.55, ph: Math.random() * 6.28, sp: 6 + Math.random() * 5 });
  }
  const crowd = new THREE.InstancedMesh(new THREE.BoxGeometry(0.5, 0.9, 0.4), new THREE.MeshLambertMaterial({ color: 0xffffff }), spots.length);
  const tmp = new THREE.Object3D(), col = new THREE.Color();
  spots.forEach((s, i) => {
    s.x = Math.sin(s.a) * s.r; s.z = Math.cos(s.a) * s.r;
    tmp.position.set(s.x, s.y, s.z); tmp.rotation.set(0, s.a + Math.PI, 0); tmp.updateMatrix(); crowd.setMatrixAt(i, tmp.matrix);
    crowd.setColorAt(i, col.setHex(PALETTE[Math.floor(Math.random() * PALETTE.length)]).multiplyScalar(0.7 + Math.random() * 0.4));
  });
  crowd.instanceColor.needsUpdate = true; group.add(crowd);
  let lastAmp = 0;
  return {
    group,
    // amp 0..1: how hard the crowd is celebrating (jumping); clock in seconds
    update(clock, amp) {
      if (amp <= 0 && lastAmp <= 0) return;
      lastAmp = amp;
      for (let i = 0; i < spots.length; i++) {
        const s = spots[i], hop = amp > 0 ? Math.abs(Math.sin(clock * s.sp + s.ph)) * 0.55 * amp : 0;
        tmp.position.set(s.x, s.y + hop, s.z); tmp.rotation.set(0, s.a + Math.PI, 0); tmp.updateMatrix(); crowd.setMatrixAt(i, tmp.matrix);
      }
      crowd.instanceMatrix.needsUpdate = true;
    },
  };
}
