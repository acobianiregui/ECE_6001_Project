# AVP Learn

A native Apple Vision Pro learning studio for introductory engineering. Built with SwiftUI, RealityKit, and Observation for visionOS 2.0 or newer. No external packages, account, or network connection is required for the learning activities.

## Learning experience

- **Today:** opens on the CAD studio card, with a picture of your current design or a starter to open, then resumes a lesson, offers the three learning paths (design first), and shows practice and review progress.
- **Learning paths:** nine lessons covering circuits, mechanics, and spatial design. Each includes a clear goal, a labeled visual, two short explanations, a named equation, a worked example, three reasoning questions, hints, and a practical activity.
- **Practice and review:** 27 questions with explanations, saved in-progress quiz answers, best scores, and reviews scheduled after 1, 3, 7, and 14 days of successful recall when due. Immediate repeats retain the scheduled date; mistakes return to the review queue. A lesson is complete after reading and a three-of-three quiz run.
- **Study journal:** saved lessons, automatic notes, a searchable 19-term glossary, primary reference links, and sharing notes/results as text.
- **CAD studio:** a large 3D viewport with one side panel (Edit, Parts, Learn, Files), inside the main window or at life size. **Add part** offers six solids (box, sphere, cylinder, cone, tube, wedge) and five machine parts with real features: a mounting plate with four bolt holes, a spur gear with a keyed bore, a threaded hex bolt, a hex nut, and a pillow-block bearing housing. **Starters** opens four true-size assemblies: a pillow-block shaft drive, a 3:1 gear reducer, a bolted angle bracket, and a bolted plate joint. Drag the view compass to orbit, or pick 3D/Front/Top/Right. The inspector shows size, position and rotation together, takes bore, hole and shank diameters in millimetres, reports gear module and pitch diameter, and estimates volume and mass for twelve finishes (six paints, six metals). Also: millimetre/centimetre readouts; four snap grids; lock/hide; alignment and stacking; undo/redo; autosaved work; six named snapshots with thumbnails; OBJ mesh export; and five build challenges whose checks update live.
- **Circuit lab:** a six-step guided procedure with explanations and a window-based bench. Experiment with supply voltage, resistance, power switch, and LED direction; inspect current, resistor voltage, and power; answer prediction questions. The schematic animates conventional current (carrier speed scales with current), LED glow follows current, and the resistor glows as it nears its power rating. A draggable current-vs-resistance chart shades unsafe resistor values, and four live design challenges check targets such as "5 mA from 5 V". An optional immersive bench uses the same procedure state.
- **3D explorer:** inspect and explode piston and gear assemblies modelled part by part (finned cylinder, ringed piston, connecting rod, counterweighted crankshaft, flywheel, ribbed spark plug, meshing 12- and 36-tooth gears), identify parts by selecting the actual 3D objects, and explore ideal gear speed, torque, and direction using an adjustable gear-pair playground. **Run mechanism** animates the 3D piston with slider-crank kinematics (spark plug fires every second revolution) and spins the 3D gear pair at 3:1; the 2D playground has a motor with meshing teeth, playback speed, and live input/output revolution counters.
- **My progress:** track completed lessons, distinct questions practiced, active study days, earned milestones, activity results, and upcoming review. Progress can be reset independently of CAD designs.

All learning records and designs are stored locally using UserDefaults. There is no cloud synchronization. Guided assembly state and current model selections are session state; circuit experiment settings and completed activity results persist. Undo history is session-only, while the current CAD design and named snapshots persist.

## Open and run

1. Open `AVPLearn.xcodeproj` in Xcode 16 or newer with the visionOS SDK installed.
2. Select the **AVPLearn** scheme and an **Apple Vision Pro simulator**. Install a visionOS simulator runtime through Xcode Settings if needed.
3. Press **⌘R**.

The main window opens at 1180 × 820 points. Lessons, quizzes, notes, CAD controls, circuit controls, and the gear playground are usable in a regular window. 3D assembly selection uses a volumetric window. Life-size CAD and the lab bench use mixed immersive spaces.

For a physical Apple Vision Pro, select your development team in **Signing & Capabilities** and choose an available bundle identifier. The default is `edu.ece6001.AVPLearn`. This development project does not include a custom app icon.

### Build from Terminal

```sh
xcodebuild -project AVPLearn.xcodeproj \
  -scheme AVPLearn \
  -configuration Debug \
  -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

Use `generic/platform=visionOS` for a device-targeted compile. The shared scheme also includes Release and archive configurations.

### Model checks

On a Mac with Xcode and Python 3 installed:

```sh
bash Tests/run_checks.sh
```

These executable checks exercise actual application models with isolated storage: curriculum integrity, scoring, persistence, completion rules, review scheduling, study-day streaks, circuit calculations and procedure ordering, CAD constraints and history, machine-part features, the contacts and fits inside each starter assembly, the build challenges, gear relationships, and exported mesh topology (every part, including 55 awkward-proportion stress cases, must be a closed, consistently wound solid), normals, transforms, and hidden-part exclusion. They do not replace simulator or headset interaction testing. See `TESTING.md` for a short manual walkthrough.

## Model boundaries

The circuit model assumes ideal wires/battery and a fixed 2 V forward LED drop, with an illustrative 20 mA LED limit and 0.25 W resistor. It does not model component tolerances, temperature, leakage, or reverse breakdown. Gear relationships assume an ideal, lossless external pair with equal tooth size. The 3D assemblies are teaching models: proportions are simplified, gear teeth approximate an involute with straight segments, and bolt threads are rings, not a helix. CAD parts are parametric meshes built at true size from their bounding dimensions; an assembly is separate parts placed in contact, including rotation and proportional gesture resizing. Holes, bores and keyways are real openings in the mesh. Mass estimates use mesh volume and a nominal density for the chosen finish. Alignment/stacking use conservative rotated bounding boxes, without persistent mates or a collision solver. OBJ exports visible triangle meshes in metres; it does not export STEP solids or a manufacturing-ready part. Boolean operations and arbitrary model import are not included. Practice scores describe performance within this app.

Primary educational references are linked in the glossary and activity views. Learning content and questions are original explanations; the app has no external content download requirement.
