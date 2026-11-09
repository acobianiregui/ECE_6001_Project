# Quick manual test

Open `AVPLearn.xcodeproj`, choose **AVPLearn** and an **Apple Vision Pro simulator**, then run.

1. **Learn:** open the first circuit lesson. Inspect its labeled diagram and worked example. Save the lesson, add a note, and choose **I’ve read this · Start practice**.
2. **Practice:** submit one wrong answer, read the explanation, and finish all three. Check that the score is honest. Start a fresh run and answer all three correctly; the lesson should become complete. Close and reopen the lesson to check the saved result and note.
3. **Review:** after a wrong answer, use **Review now** in My progress. Check that a corrected answer leaves the due queue. Repeating a correct quiz immediately should not move its review date farther into the future.
4. **Circuit:** try connecting the battery before the procedure asks for it. The step should stay in place and explain the mistake. Complete the six steps in order. Leaving and returning to the lab should not record that same run twice.
5. **Experiment:** select 9 V and 470 Ω, close the switch, and leave the LED forward-facing. Expect about 14.89 mA, 7 V across the resistor, and 0.104 W. Opening the switch or reversing the LED should give zero current in the stated model. Try the prediction questions.
6. **CAD:** load the shaft-support starter. Select the shaft and change Width X and Depth Z to 40 mm while keeping Height Y at 280 mm. Check that resizing stays visible; the unchanged 42 mm bores now give 1 mm radial clearance. Try front/top/right views and Fit. Hide and lock a part, then test that hidden parts disappear and locked parts resist editing. Change between mm/cm and confirm geometry stays the same. Save a named snapshot, change the design, and load the snapshot; Undo should restore the prior workspace. Export OBJ and inspect it in another 3D tool.
7. **Mechanics:** with 12 input teeth and 36 output teeth at 90 RPM and 1 N·m, predict the output before checking. Expect 30 RPM and 3 N·m in the opposite direction. Move the turn control and compare the linked rotation.
8. **Spatial interaction:** open each assembly in 3D, explode it, inspect parts, and complete its identification challenge by selecting objects. On a headset, test drag and two-hand resize in the CAD immersive space. Switch between CAD and lab spaces and check that only one opens at a time.
9. **Relaunch:** quit and reopen the app. Check lesson scores, notes, bookmarks, saved circuit settings, current CAD work, and named snapshots. Undo history and the unfinished guided procedure intentionally start fresh.

Useful feedback: the screen/activity you were using, what you expected, what happened, and whether it occurred in the simulator or on a headset. A screenshot helps with spacing or clipped controls.

## Additional CAD checks

- Test independent sizes with an unlocked box: 200 × 40 × 80 mm. Turn X by 90°; its rotated bounding height is 80 mm, so **Rest bounds on workplane** should place its center at 40 mm. Compound rotations use a conservative bounding box for placement.
- Choose another part as the reference. Align X/Z centers and stack their bounding boxes. Y alignment should be unavailable with an explanation if it would push the selected part through the workplane.
- Try 1 mm, 5 mm, 1 cm, and 5 cm snapping. Typed dimensions stay precise; position snapping affects position. The viewport separately labels drawn-grid spacing when fine lines are simplified.
- Load the reinforced bracket and try its design investigation. Starter replacement is reversible through Undo, including the previous workspace’s locked parts.
- Reopen an older saved design. Its former uniform size should migrate to matching width/height/depth, without losing snapshots.
- Verify OBJ includes only visible parts, with names and rotations preserved. OBJ coordinates are in metres; materials, edit history, and solid-CAD features are not exported.
