# AVP Learn

An Apple Vision Pro app for engineering students (visionOS 2+, SwiftUI + RealityKit).

## What's in the app

| Feature | Where | What it does |
|---|---|---|
| **3D system explorer** | `SystemExplorerView.swift` | Volumetric window with an exploded-view piston/crank assembly and a gear train. Slider explodes the model; tap a part to read what it does. |
| **Beginner CAD studio** | `CADSpaceView.swift`, `CADPanel` in `HomeView.swift` | Immersive workplane. Add primitives, pinch-drag to move, two-hand pinch to resize, snap-to-grid, undo, duplicate, live size readout, and a coach that explains next steps in plain language. |
| **Virtual lab** | `LabSpaceView.swift`, `LabModel` in `Models.swift` | Guided LED-circuit lab on a virtual bench. Steps must be done in a safe order; mistakes cost points and trigger explanations; ends with a readiness score. |

## Set up in Xcode

1. Xcode 16+ → **File ▸ New ▸ Project ▸ visionOS ▸ App**. Name it `AVPLearn`, Initial Scene: **Window**, Immersive Space Renderer: **None**.
2. Delete the generated `*App.swift`, `ContentView.swift`, and any generated immersive files.
3. Drag all `.swift` files from this folder into the project.
4. In the target's Info tab, set **Preferred Default Scene Session Role** to *Application Session Role* (the default) and add `UIApplicationSupportsMultipleScenes = YES`.
5. Run on the Apple Vision Pro simulator or a device.

I wrote this without access to Xcode, so it hasn't been compiled. Expect a few small API-signature fixes on first build.

## Business case: why students pay a higher technology fee

- **Replaces physical lab time and consumables.** Students can rehearse before entering a real lab, which reduces damaged equipment, repeat sessions, and safety incidents.
- **Lowers the barrier to CAD.** Beginners learn spatial reasoning with their hands instead of a mouse and menus.
- **Makes abstract systems tangible.** Exploded views and cutaways teach assemblies faster than 2D diagrams.
- **Access without scheduling.** Labs can be practiced off-hours and off-campus (with a headset checkout program).

Suggested pricing model to test: a per-student campus license added to the technology fee (e.g., $40–$90/semester), plus a department tier for lab-content packs. Validate willingness to pay with a pilot in one intro course (Statics, Circuits, or Engineering Graphics) and measure lab pass rates, lab-session reschedules, and CAD-course grades against a control section.

## Roadmap

- Boolean operations (union/subtract/intersect), sketch-and-extrude, and STEP/USDZ export
- Instructor dashboard: assign labs, view scores and common mistakes
- More lab packs: multimeter measurements, tensile testing, fluid flow, soldering
- Real USDZ part models and physics-based simulation of the systems
- SharePlay for team design and TA-led lab sessions
- LMS integration (Canvas, Blackboard) and campus SSO
