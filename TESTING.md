# Quick manual test

Open `AVPLearn.xcodeproj`, choose **AVPLearn** and an **Apple Vision Pro simulator**, then run.

1. **Learn:** open the first circuit lesson. Inspect its labeled diagram and worked example. Save the lesson, add a note, and choose **I’ve read this · Start practice**.
2. **Practice:** submit one wrong answer, read the explanation, and finish all three. Check that the score is honest. Start a fresh run and answer all three correctly; the lesson should become complete. Close and reopen the lesson to check the saved result and note.
3. **Review:** after a wrong answer, use **Review now** in My progress. Check that a corrected answer leaves the due queue. Repeating a correct quiz immediately should not move its review date farther into the future.
4. **Circuit:** try connecting the battery before the procedure asks for it. The step should stay in place and explain the mistake. Complete the six steps in order. Leaving and returning to the lab should not record that same run twice.
5. **Experiment:** select 9 V and 470 Ω, close the switch, and leave the LED forward-facing. Expect about 14.89 mA, 7 V across the resistor, and 0.104 W. Opening the switch or reversing the LED should give zero current in the stated model. Try the prediction questions.
6. **CAD:** in the CAD studio choose **Starters** and open the pillow-block shaft drive. Drag the view compass to orbit; try 3D/Front/Top/Right and the fit button. Tap the shaft (or pick it in **Parts**) and, in **Edit**, change Width X and Depth Z to 37.5 mm, then **Apply changes**. The sleeves are bored 37 mm, so the shaft now interferes by 0.25 mm on the radius; the position must not move. Hide a pillow block to see the sleeve inside; lock a part and check that it resists editing. Change between mm/cm and confirm geometry stays the same. In **Files**, save a named snapshot, change the design, and load the snapshot; Undo should restore the prior workspace. Export OBJ and inspect it in another 3D tool.
7. **Mechanics:** with 12 input teeth and 36 output teeth at 90 RPM and 1 N·m, predict the output before checking. Expect 30 RPM and 3 N·m in the opposite direction. Move the turn control and compare the linked rotation.
8. **Spatial interaction:** open each assembly in 3D, explode it, inspect the detailed parts (piston rings, crank counterweights, meshing gear teeth), and complete its identification challenge by selecting objects. On a headset, test drag and two-hand resize in the CAD immersive space. Switch between CAD and lab spaces and check that only one opens at a time.
9. **Relaunch:** quit and reopen the app. Check lesson scores, notes, bookmarks, saved circuit settings, current CAD work, and named snapshots. Undo history and the unfinished guided procedure intentionally start fresh.

Useful feedback: the screen/activity you were using, what you expected, what happened, and whether it occurred in the simulator or on a headset. A screenshot helps with spacing or clipped controls.

## Additional CAD checks

- **Add part** lists six solids and five machine parts with pictures. Add a gear: Edit should show module 3 mm and pitch ⌀ 54 mm. Raise Teeth to 36 without changing the size and the module changes; set Width X and Depth Z to 114 mm and it returns to 3 mm.
- Type a Bore ⌀, Hole ⌀ or Shank ⌀ outside the allowed range: the inspector should state the range instead of applying it.
- With Snap on a 5 mm grid, type X = 54 mm for a part: the inspector should report that Snap rounded the position. Resizing a part must never move it onto the grid.
- Challenge 04: two new gears mesh when their centers are 54 mm apart at the same height (use the 1 mm grid). Challenge 05: stack a plate on a box, then place a bolt on a hole center with its head on the plate. The strip under the viewport should tick each check as it passes, and My progress should award **Spatial thinker**.
- Pick each finish: paints look matte, metals reflective, and the volume/mass line updates with the material.
- Test independent sizes with an unlocked box: 200 × 40 × 80 mm. Turn X by 90°; its rotated bounding height is 80 mm, so **Rest on workplane** should place its center at 40 mm. Compound rotations use a conservative bounding box for placement.
- Choose another part as the reference. Align X/Z centers and stack their bounding boxes. Y alignment should be unavailable with an explanation if it would push the selected part through the workplane.
- Open each of the four starters and try its investigation in **Learn**. Starter replacement is reversible through Undo, including the previous workspace’s locked parts.
- Reopen an older saved design. Its former uniform size should migrate to matching width/height/depth, without losing snapshots; its colours should be unchanged.
- Verify OBJ includes only visible parts, with names and rotations preserved. OBJ coordinates are in metres; materials, edit history, and solid-CAD features are not exported.
