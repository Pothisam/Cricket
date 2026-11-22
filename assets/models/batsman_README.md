# batsman_with_bat_animated.glb

The original rigged player with the cricket bat attached to the hands, plus 16 batting animations.

- **Bat:** a child of the top-hand bone (`LeftHand_013`), so it can never come loose or flip. The bottom hand is placed on the handle with IK in every frame.
- **Marker nodes on the bat:** `Bat_SweetSpot`, `Bat_Toe` and `Bat_HandleTop`. Use them for collision, ball effects or the replay camera.
- **Axes (metres):** +Y is up, the bowler is at +Z, the off side is −X. These are for a right-handed batsman. For a left-hander, set `scale.x = -1` on the model root.
- **Contact time:** every shot meets the ball at **t = 1.0 s**. The clips run at 60 fps.
- **Metadata:** everything is in `gltf.scene.userData.batting` (three.js) or `scenes[0].extras.batting`. For each clip it holds the duration, footwork, contact time, contact point, shot direction and the ball's release and bounce points.

| Clip | Footwork | Shot direction |
|---|---|---|
| Stance_Idle (loop) | – | – |
| Loft_Cover | front, full motion-capture swing | −35°, lofted |
| Leave | front | no contact |
| Defence_Forward / Defence_Back | front / back | straight, dead bat |
| Drive_Straight / Drive_Cover / Drive_On | front | 0° / −50° / +22° |
| Loft_Straight | front | 0°, 32° elevation |
| Flick | front | +48° (mid-wicket) |
| Sweep | front, back knee down | +95° (square leg) |
| Cut_Square / Cut_Late | back | −95° / −140° |
| Pull / Hook | back | +80° / +128° |
| Glance | back | +150° (fine leg) |

## Motion source
Every shot starts from real motion capture: the raised-bat stance, trigger and backlift are retargeted from a mocap batting animation. Each shot then blends into its own downswing and follow-through. `Loft_Cover` uses the full mocap swing. The hand grip on the handle is also measured from that mocap. The reference motion is "Virat Kohli Cricket Batting Animation – Low Poly" by bhagathartworks on Sketchfab (CC-BY-4.0), and it needs crediting alongside the models below.

## Hooking it to the replay
`BatsmanController.js` (three.js) does three things:

1. It maps the recorded shot name to a clip. Unknown names fall back to the clip with the nearest shot direction.
2. It time-warps the clip so that contact happens exactly when the replay ball arrives.
3. It shuffles the batsman into line, up to 0.35 m, so the bat meets the ball where it actually is.

```js
const bat = new BatsmanController(gltf, { leftHanded });
bat.idle();
bat.playShot(record.shotType, { timeToContact, contactPoint }); // contactPoint is in batsman-local space
// each frame: bat.update(dt)
```

## Adding shots
Shots are data in `tools/shots.mjs`, given as keyframes for the hips, chest, feet, the bat's swing plane and the gaze. Hand positions are written relative to the chest, so the hands move with the body. Running `node tools/build.mjs` regenerates the GLB. Existing clips and the replay code don't need any changes.

On every frame, the solver:
- keeps the bat face pointing in its direction of travel
- keeps both hands on the handle
- keeps the hands clear of the head and torso, and the bat blade out of the head, torso and legs
- turns the bat about its own handle away from contact so both wrists stay natural, with the face exact at contact
- points the elbows automatically, turning each elbow to the position where the wrist is least bent and twisted

The build log prints checks for every clip: wrist bend, clearance, IK reach, bat speed and face direction at contact. The hand-on-handle grip comes from the mocap (`tools/refgrip.mjs`).

Credits (CC-BY-4.0, Sketchfab): player by numaan.k99, bat by omkar.jawake, reference batting motion by bhagathartworks.
