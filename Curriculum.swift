import Foundation

/// Original short lessons and practice scenarios. Further reading is linked in the reference library.
enum Curriculum {
    static let lessons: [Lesson] = [
        ohmsLaw, circuitPaths, ledDesign,
        forcesAndMotion, turningForces, gearRatios,
        coordinates, solidsAndScale, designIntent
    ]

    private static let ohmsLaw = Lesson(
        id: "circuits-ohm", track: .circuits,
        title: "What makes current flow?",
        summary: "Connect voltage, current, and resistance without mixing them up.",
        minutes: 6,
        objective: "Predict how a resistor's current changes when voltage or resistance changes.",
        sections: [
            .init(title: "Three different quantities", text: "Voltage is energy transferred per unit of electric charge, measured in volts (V). Current is the rate at which charge passes a point, measured in amperes (A). Resistance describes how strongly a component opposes current, measured in ohms (Ω)."),
            .init(title: "Change one thing at a time", text: "For an ohmic resistor, doubling its voltage doubles its current if resistance stays fixed. Doubling resistance halves current at fixed voltage. An open switch breaks the conducting path, so this ideal circuit carries no current. An LED is not an ohmic resistor.")
        ],
        equation: .init(name: "Ohm's law", expression: "V = I × R", symbols: "V: voltage across the resistor in volts · I: current through it in amperes · R: resistance in ohms"),
        example: .init(title: "Diagnose a changed supply", prompt: "A 1,000 Ω resistor draws 6 mA from a 6 V ideal supply. The supply changes to 3 V.", steps: ["Keep resistance fixed: 1,000 Ω.", "Use Ohm's law in current form: I = V / R = 3 / 1,000 A = 3 mA."], takeaway: "Half the voltage gives half the current for the same ohmic resistor."),
        visual: .circuit,
        practice: [
            .init(id: "ohm-predict", prompt: "A resistor's voltage doubles while its resistance also doubles. What happens to its current?", options: ["It doubles.", "It stays the same.", "It halves."], correctIndex: 1, explanation: "The ratio V / R stays the same: the two changes cancel.", hint: "Write the new current as 2V / 2R."),
            .init(id: "ohm-diagnose", prompt: "Someone uses I = 9 / 470 to predict the current through a 470 Ω resistor in series with an LED on a 9 V supply. What is missing?", options: ["The LED's voltage drop must be subtracted first.", "The LED must be treated as another 470 Ω resistor.", "Resistance is irrelevant once an LED is present."], correctIndex: 0, explanation: "Ohm's law uses the voltage across the resistor. Some supply voltage is across the LED.", hint: "Does the resistor receive the entire supply voltage?"),
            .init(id: "ohm-open", prompt: "A battery has voltage across an open switch. Why can the loop current still be zero?", options: ["Voltage and current are the same quantity.", "The battery must be empty.", "Voltage can exist without a complete conducting path."], correctIndex: 2, explanation: "A potential difference can exist across a gap. A complete path is needed for steady current in this ideal circuit.", hint: "Think about what the switch changes: energy per charge, or the path?")
        ],
        activity: .init(activity: .circuit, task: "In Experiment mode, keep the LED forward-facing. Predict the effect of increasing resistance before moving the resistance control.")
    )

    private static let circuitPaths = Lesson(
        id: "circuits-paths", track: .circuits,
        title: "One path or several?",
        summary: "Read the connections before choosing a series or parallel rule.",
        minutes: 7,
        objective: "Identify which quantities are shared in series and parallel resistor networks.",
        sections: [
            .init(title: "Follow the connections", text: "Components in series share one unbranched current path. Components in parallel connect across the same two connection points, called nodes. A drawing's appearance does not decide the connection; trace where each wire leads."),
            .init(title: "What stays the same?", text: "Series resistors carry the same current, while their voltage drops add. Parallel resistors share the same voltage, while their branch currents add. Adding a parallel branch gives current another route and reduces equivalent resistance: the single resistance that would draw the same total current.")
        ],
        equation: .init(name: "Series and parallel resistance rules", expression: "Series: Rₑq = R₁ + R₂     Parallel: 1/Rₑq = 1/R₁ + 1/R₂", symbols: "Rₑq: equivalent resistance · R₁ and R₂: individual resistances, all in ohms"),
        example: .init(title: "The same parts, a different network", prompt: "Connect two 1,000 Ω resistors to an ideal 6 V supply.", steps: ["In series, equivalent resistance is 2,000 Ω, giving 3 mA through each resistor.", "In parallel, each branch gets 6 V and carries 6 mA. The supply delivers 12 mA total."], takeaway: "The wiring changes the current even though the parts and supply are unchanged."),
        visual: .seriesParallel,
        practice: [
            .init(id: "paths-unequal", prompt: "A 1,000 Ω resistor and a 2,000 Ω resistor are in parallel across an ideal supply. Which statement is correct?", options: ["The larger resistor gets twice the voltage.", "Both resistors carry the same current.", "Both get the same voltage; the smaller resistor carries more current."], correctIndex: 2, explanation: "Both ends connect to the same two nodes, so voltage is shared. Current then follows I = V / R in each branch.", hint: "Start with the two shared nodes, then apply Ohm's law to each branch."),
            .init(id: "paths-open", prompt: "Two independent resistor branches are parallel across an ideal voltage source. One branch is disconnected. What happens in the remaining branch?", options: ["Its current doubles.", "Its current stays the same.", "Its current becomes zero."], correctIndex: 1, explanation: "The ideal source maintains the remaining branch's voltage and its resistance has not changed. Total supply current decreases.", hint: "Distinguish branch current from total supply current."),
            .init(id: "paths-used", prompt: "A learner says the second series resistor receives less current because the first resistor uses some up. What should you explain?", options: ["Charge is not consumed; the same steady current passes both.", "The first resistor stores all the incoming charge.", "This is true only when the resistors are equal."], correctIndex: 0, explanation: "Resistors transfer electrical energy to thermal energy. They do not consume charge, so one steady series path has one current.", hint: "Separate charge flow from energy transfer.")
        ],
        activity: .init(activity: .circuit, task: "Trace the lab's single loop and identify why the resistor and LED share current. The simulator models this series loop, not a parallel network.")
    )

    private static let ledDesign = Lesson(
        id: "circuits-led", track: .circuits,
        title: "Design an LED circuit",
        summary: "Choose a current-limiting resistor and measure the right voltage.",
        minutes: 8,
        objective: "Use a stated LED model to choose resistance and explain meter placement.",
        sections: [
            .init(title: "A component with a direction", text: "An LED is a light-emitting diode: it conducts mainly in one direction and emits light. In this lesson, a forward-facing LED has a fixed 2 V drop. That is a simplified model, not a universal LED property. We use 20 mA as an illustrative current limit."),
            .init(title: "Measure across, not through", text: "Kirchhoff's voltage law says voltage changes around a closed loop sum to zero. After the LED's drop, the remaining supply voltage is across the resistor. A voltmeter measures between two points, so connect it across the resistor. A current meter goes in series instead.")
        ],
        equation: .init(name: "LED series-resistor current model", expression: "I = (Vₛ − VLED) / R", symbols: "Vₛ: supply voltage · VLED: assumed forward drop (2 V) · R: series resistance · valid here for a closed, forward-facing circuit with Vₛ > 2 V"),
        example: .init(title: "Choose between two resistors", prompt: "An ideal 9 V supply powers the model LED. Which is below the illustrative 20 mA limit: 330 Ω or 470 Ω?", steps: ["The resistor receives 9 − 2 = 7 V.", "Current is about 21.2 mA with 330 Ω and 14.9 mA with 470 Ω.", "Choose 470 Ω for this model; real parts also require their actual ratings and tolerances."], takeaway: "Use the resistor's voltage, then compare predicted current with the stated design limit."),
        visual: .led,
        practice: [
            .init(id: "led-redesign", prompt: "You increase the supply from 9 V to 12 V but want roughly the same LED current in this model. What should change?", options: ["Decrease series resistance.", "Increase series resistance.", "Reverse the LED."], correctIndex: 1, explanation: "The resistor now drops 10 V instead of 7 V. More resistance is needed to keep I = V / R unchanged.", hint: "Which part must accommodate the additional voltage?"),
            .init(id: "led-meter", prompt: "To check the resistor's predicted 7 V drop, where should a voltmeter's probes go?", options: ["One at each end of the resistor.", "Both on the same end of the resistor.", "In place of the resistor, breaking its connection."], correctIndex: 0, explanation: "Voltage is a difference between two points. Probes across the resistor measure its drop.", hint: "A voltage measurement compares two locations without replacing the component."),
            .init(id: "led-dark", prompt: "The model LED is dark with the power switch closed. Which diagnosis should you investigate before lowering resistance?", options: ["The resistor must always be too large.", "The current meter has consumed the current.", "LED polarity and whether the supply exceeds its assumed forward drop."], correctIndex: 2, explanation: "A reversed LED or insufficient supply can prevent conduction in this model. Lowering resistance does not fix either cause.", hint: "Check whether a conducting path is possible before increasing predicted current.")
        ],
        activity: .init(activity: .circuit, task: "Complete Guided assembly, then predict and test the current at 9 V with 470 Ω. Reverse the LED and explain the change.")
    )

    private static let forcesAndMotion = Lesson(
        id: "mechanics-forces", track: .mechanics,
        title: "Force changes motion",
        summary: "A force predicts acceleration, not simply which way an object moves.",
        minutes: 7,
        objective: "Distinguish velocity from acceleration and reason from net force.",
        sections: [
            .init(title: "Add the forces first", text: "A force is a push or pull, measured in newtons (N). Net force is the combined effect of all forces on one object, including their directions. A free-body diagram isolates that object and shows the external forces acting on it."),
            .init(title: "Motion versus change in motion", text: "Velocity describes speed and direction. Acceleration describes how velocity changes. For constant mass, net force determines acceleration. Zero net force means constant velocity, which can include being at rest. An object can move right while accelerating left and slowing down.")
        ],
        equation: .init(name: "Newton's second law", expression: "Fnet = m × a", symbols: "Fnet: net force in newtons · m: mass in kilograms · a: acceleration in metres per second squared; force and acceleration have the same direction"),
        example: .init(title: "Push against a resisting force", prompt: "A 2 kg cart moves right. A 6 N push acts right and a 2 N resisting force acts left.", steps: ["Choose right as positive. Net force is 6 − 2 = 4 N to the right.", "Use Newton's second law: a = Fnet / m = 4 / 2 = 2 m/s² to the right."], takeaway: "Use the net force, not the largest force by itself."),
        visual: .forces,
        practice: [
            .init(id: "force-coast", prompt: "A cart glides right at constant velocity. What can you infer about its net force?", options: ["It points right because the cart is moving right.", "It points left because all moving things slow down.", "It is zero in the inertial-frame model."], correctIndex: 2, explanation: "Constant velocity means zero acceleration. Newton's second law then requires zero net force.", hint: "Ask whether the velocity is changing, not whether it is nonzero."),
            .init(id: "force-brake", prompt: "A cart moves right while its net force points left. What happens immediately?", options: ["It slows while initially still moving right.", "It instantly moves left.", "It continues at unchanged velocity."], correctIndex: 0, explanation: "Leftward acceleration changes the rightward velocity toward zero. Reversal would take time if the force continues.", hint: "Force determines the change in velocity, not an instant replacement of velocity."),
            .init(id: "force-mass", prompt: "Two carts experience the same nonzero net force. One has twice the mass. How do their accelerations compare?", options: ["The heavier cart accelerates twice as much.", "The heavier cart accelerates half as much.", "Their accelerations are equal."], correctIndex: 1, explanation: "Acceleration is Fnet / m. With force unchanged, twice the mass gives half the acceleration.", hint: "Hold the numerator fixed and change the denominator.")
        ],
        activity: .init(activity: .piston, task: "Select the piston and connecting rod. Describe the path by which a force on the piston can be transmitted to the crank; the model is a schematic assembly.")
    )

    private static let turningForces = Lesson(
        id: "mechanics-torque", track: .mechanics,
        title: "Why a longer handle helps",
        summary: "Predict turning effect from the force and its line of action.",
        minutes: 7,
        objective: "Use perpendicular lever arm and force direction to compare torques.",
        sections: [
            .init(title: "Turning effect has a name", text: "Torque is the turning effect of a force about a chosen pivot, measured in newton-metres (N·m). The lever arm is the shortest, perpendicular distance from that pivot to the force's line of action."),
            .init(title: "Direction matters too", text: "A force applied farther from the pivot can produce more torque. The same force produces its largest torque when perpendicular to the handle. A force pointing directly toward the pivot has zero torque about it. Opposite turning directions oppose one another.")
        ],
        equation: .init(name: "Torque magnitude", expression: "τ = F × d⊥", symbols: "τ (tau): torque in N·m · F: force in newtons · d⊥: perpendicular lever arm in metres"),
        example: .init(title: "Compare two handle lengths", prompt: "You push perpendicular to a handle with 20 N. Compare 0.10 m and 0.25 m lever arms.", steps: ["At 0.10 m, torque magnitude is 20 × 0.10 = 2 N·m.", "At 0.25 m, torque magnitude is 20 × 0.25 = 5 N·m."], takeaway: "The longer perpendicular lever arm gives more turning effect with the same force."),
        visual: .lever,
        practice: [
            .init(id: "torque-direction", prompt: "A force is applied at the tip of a handle but points straight toward its pivot. Why is torque zero?", options: ["The applied force has no magnitude.", "The force's line of action passes through the pivot.", "Torque is always zero at the tip."], correctIndex: 1, explanation: "The perpendicular distance from the pivot to that force line is zero, even though the handle and force are nonzero.", hint: "Use the perpendicular lever arm, not just the handle length."),
            .init(id: "torque-choice", prompt: "You want the same torque with half as much perpendicular force. Which design change works?", options: ["Double the lever arm.", "Halve the lever arm.", "Move the force to the pivot."], correctIndex: 0, explanation: "The product F × d⊥ must stay fixed. Halving one factor requires doubling the other.", hint: "Which change preserves the product?"),
            .init(id: "torque-balance", prompt: "A beam has a 10 N downward force 0.20 m left of its pivot and a 5 N downward force 0.40 m right. What do these forces do to its net torque?", options: ["The 10 N force wins because it is larger.", "Both torques turn in the same direction.", "Their equal, opposite torques cancel."], correctIndex: 2, explanation: "Both torque magnitudes are 2 N·m, but the forces act on opposite sides and turn the beam in opposite directions.", hint: "Compare force times distance on each side, then compare turning directions.")
        ],
        activity: .init(activity: .piston, task: "Find the crankshaft. Explain why a connecting-rod force whose line passes through the crank's rotation axis produces no torque about that axis.")
    )

    private static let gearRatios = Lesson(
        id: "mechanics-gears", track: .mechanics,
        title: "Trade speed for torque",
        summary: "Use gear teeth to predict output speed and turning force.",
        minutes: 8,
        objective: "Predict speed, direction, and ideal torque in one external gear pair.",
        sections: [
            .init(title: "Count teeth, identify roles", text: "The driver is the input gear; the driven gear receives its motion. For one meshing pair with compatible teeth, more teeth on the driven gear means a slower output. Two external gears turn in opposite directions when viewed from the same side."),
            .init(title: "A trade, not free power", text: "Here the gear ratio means driven teeth divided by driver teeth. A 3:1 reduction gives one output turn per three input turns. Ignoring losses, output torque rises by the same factor that speed falls. Real friction reduces the available output power.")
        ],
        equation: .init(name: "Ideal gear-pair relationships", expression: "g = Nout / Nin     nout = nin / g     τout = τin × g", symbols: "g: reduction ratio · N: tooth count · n: rotational speed · τ: torque; these expressions compare magnitudes and assume no power loss"),
        example: .init(title: "A 12-tooth driver meets a 36-tooth gear", prompt: "The input runs at 90 revolutions per minute (rpm) with 0.4 N·m torque.", steps: ["The ratio is 36 / 12 = 3, so the ideal output speed is 90 / 3 = 30 rpm.", "Ideal output torque is 0.4 × 3 = 1.2 N·m. The external pair reverses rotation direction."], takeaway: "Slower output and greater torque are linked; both do not increase together."),
        visual: .gears,
        practice: [
            .init(id: "gear-reverse", prompt: "You swap the driver and driven gears in the 12T–36T pair. The 36T gear now drives. What changes?", options: ["The 12T output turns three times faster with one-third the ideal input torque.", "The output turns three times slower with three times the torque.", "The ratio stays 3:1 because the same parts are used."], correctIndex: 0, explanation: "The roles matter: g = 12 / 36 = 1/3. This is a speed increase, with a corresponding ideal torque decrease.", hint: "Write the output tooth count above the input tooth count."),
            .init(id: "gear-power", prompt: "A proposed passive gear pair promises twice the output speed and twice the output torque at unchanged input power. What is wrong?", options: ["Nothing; any gear pair multiplies both.", "The driver must have an odd number of teeth.", "It would require four times the output power in the ideal model."], correctIndex: 2, explanation: "Rotational power is torque times angular speed. Doubling both would quadruple power; passive gears cannot supply the extra energy.", hint: "Compare the product of torque and speed before and after."),
            .init(id: "gear-design", prompt: "A motor is too fast and provides too little torque for a load. Which single-pair change fits that goal?", options: ["Make the driven gear smaller than the driver.", "Make the driven gear larger than the driver.", "Use equal tooth counts to multiply torque."], correctIndex: 1, explanation: "A larger driven gear produces a reduction: lower output speed and greater ideal output torque.", hint: "The gear needing more teeth to complete a turn rotates more slowly.")
        ],
        activity: .init(activity: .gears, task: "Inspect the 12T and 36T parts. Identify the input and output, then predict how many input turns correspond to one output turn.")
    )

    private static let coordinates = Lesson(
        id: "design-coordinates", track: .design,
        title: "Place parts with coordinates",
        summary: "Use axes, units, and object centres to position shapes deliberately.",
        minutes: 6,
        objective: "Translate a placement goal into coordinates and a unit conversion.",
        sections: [
            .init(title: "A location needs a reference", text: "Coordinates are numbers describing a location relative to an origin, the reference point (0, 0, 0). This studio uses X for left–right, Y for height, and Z for depth. Positive Y is upward. Each shape's position describes its centre, not its bottom surface."),
            .init(title: "Units prevent surprises", text: "The scene uses metres internally; the studio displays dimensions in your choice of millimetres or centimetres. One metre is 100 centimetres. A 10 cm-high shape resting on the workplane therefore needs its centre 5 cm above the plane. Moving a part changes position; scaling it changes dimensions.")
        ],
        equation: .init(name: "Centimetre-to-metre conversion", expression: "length in metres = length in centimetres / 100", symbols: "Use one consistent unit before combining dimensions and positions."),
        example: .init(title: "Place a box on a surface", prompt: "A box is 20 cm high and should rest on the workplane, with its centre 15 cm to the right of the origin.", steps: ["Its centre height must be half its height: Y = 10 cm.", "The centre coordinates are X = 15 cm, Y = 10 cm, Z = 0 cm, or (0.15, 0.10, 0) m."], takeaway: "Account for where the object's reference point is located."),
        visual: .coordinates,
        practice: [
            .init(id: "coord-stack", prompt: "A 20 cm-high box rests on the plane. A 10 cm-high cylinder should rest directly on its top. What centre height should the cylinder have?", options: ["10 cm.", "20 cm.", "25 cm."], correctIndex: 2, explanation: "The box's top is 20 cm high. Add half the cylinder's height, 5 cm, to place its centre at 25 cm.", hint: "Centre height equals supporting-surface height plus half the new part's height."),
            .init(id: "coord-units", prompt: "A design specifies a 50 mm gap. A learner enters 50 in a field labeled cm. What is the problem?", options: ["The entered gap is ten times too large.", "The entered gap is ten times too small.", "Millimetres and centimetres are interchangeable."], correctIndex: 0, explanation: "50 mm equals 5 cm. Entering 50 cm makes the intended gap ten times larger.", hint: "There are 10 millimetres in one centimetre."),
            .init(id: "coord-move", prompt: "You want to shift a part right while keeping its height, depth, and size unchanged. Which control should change?", options: ["Uniform scale.", "X position only.", "Y position only."], correctIndex: 1, explanation: "In this studio X controls left–right position. Scale changes size, while Y changes height.", hint: "Choose the axis aligned with the requested movement.")
        ],
        activity: .init(activity: .cad, task: "Create a box and use the labelled position controls to move it along X only. Check the centre height when you change its size.")
    )

    private static let solidsAndScale = Lesson(
        id: "design-scale", track: .design,
        title: "Build from simple solids",
        summary: "Choose useful primitives and predict what resizing really changes.",
        minutes: 7,
        objective: "Choose a primitive for a role and distinguish length scaling from volume scaling.",
        sections: [
            .init(title: "Simple shapes, useful roles", text: "A primitive is a basic 3D solid such as a box, sphere, cylinder, or cone. A cylinder is a useful first approximation of a shaft; a box can represent a support. Combining visible shapes makes an assembly here; it does not automatically join their geometry into one manufactured part."),
            .init(title: "Uniform scale changes every axis", text: "Uniform scaling multiplies width, height, and depth by the same factor. Doubling each dimension multiplies volume by eight, not two. Scaling a hole and its surrounding part together would also change the hole size, which may violate a design requirement.")
        ],
        equation: .init(name: "Uniform length and volume scaling", expression: "Lnew = s × Lold     Vnew = s³ × Vold", symbols: "s: uniform scale factor · L: any corresponding length · V: volume; the shape's proportions stay fixed"),
        example: .init(title: "Make a larger demonstration model", prompt: "A 10 cm cube becomes a 20 cm cube by uniform scaling.", steps: ["The length scale factor is 20 / 10 = 2.", "The cube's volume changes from 1,000 cm³ to 8,000 cm³: a factor of 2³ = 8."], takeaway: "A length multiplier is not a volume multiplier."),
        visual: .solids,
        practice: [
            .init(id: "scale-role", prompt: "You need a first approximation of a round shaft with a constant circular cross-section. Which primitive fits best?", options: ["Sphere.", "Cylinder.", "Cone."], correctIndex: 1, explanation: "A cylinder has circular cross-sections of constant radius along its axis. A cone narrows, and a sphere has no straight shaft section.", hint: "Look for the shape whose radius stays constant along its length."),
            .init(id: "scale-volume", prompt: "A solid is uniformly scaled by 0.5. What fraction of its original volume remains?", options: ["One half.", "One quarter.", "One eighth."], correctIndex: 2, explanation: "All three length dimensions halve, so volume is multiplied by 0.5 × 0.5 × 0.5 = 1/8.", hint: "Volume involves three length dimensions."),
            .init(id: "scale-intent", prompt: "A bracket needs to be taller, but its width must remain exactly 10 cm. Why is uniform scaling the wrong edit?", options: ["It changes the width as well as the height.", "Uniform scaling changes only position.", "A bracket cannot be represented using solids."], correctIndex: 0, explanation: "Uniform scale changes every dimension together. Use the Size controls to change Height while preserving Width. The two-hand resize gesture changes all dimensions proportionally.", hint: "Compare what must change with what must stay fixed.")
        ],
        activity: .init(activity: .cad, task: "Add a box and a cylinder. Scale one from 10 cm to 20 cm, and predict the change in its volume before comparing their sizes.")
    )

    private static let designIntent = Lesson(
        id: "design-constraints", track: .design,
        title: "Design with rules, not guesses",
        summary: "Separate convenient placement from a requirement that must stay true.",
        minutes: 8,
        objective: "Explain constraints, grid snapping, and basic dimensional tolerances.",
        sections: [
            .init(title: "Preserve the reason for a dimension", text: "Design intent describes what a part must accomplish. A constraint is a rule that preserves a relationship, such as equal lengths or a fixed distance. Snapping rounds placement to a grid; it helps alignment but does not create a lasting connection between parts. Check placement again after resizing."),
            .init(title: "A dimension can allow variation", text: "A dimensional tolerance states an allowed size range. A width of 10.0 ± 0.2 mm allows 9.8–10.2 mm. Fit depends on the ranges of both mating parts. A larger-looking hole in a model is not enough evidence that every manufactured part will fit.")
        ],
        equation: .init(name: "Symmetric dimensional tolerance limits", expression: "minimum = nominal − tolerance     maximum = nominal + tolerance", symbols: "Nominal: target dimension · tolerance: permitted variation in either direction; use matching units"),
        example: .init(title: "Check the tightest possible fit", prompt: "A pin is 10.0 ± 0.1 mm in diameter. A hole is 10.3 ± 0.1 mm in diameter.", steps: ["The largest pin is 10.1 mm; the smallest hole is 10.2 mm.", "The minimum diametral clearance, the hole diameter minus pin diameter, is 0.1 mm."], takeaway: "Compare the limiting cases, not just the nominal dimensions."),
        visual: .constraints,
        practice: [
            .init(id: "intent-snap", prompt: "Two parts touch after snapping to the grid. You enlarge the lower part. Why might you need to reposition the upper part?", options: ["The grid permanently links every touching surface.", "Snapping set positions but did not preserve their contact relationship.", "Scaling always moves all other objects automatically."], correctIndex: 1, explanation: "The studio stores each shape's position and scale independently. A grid is a placement aid rather than a contact constraint.", hint: "What rule, if any, tells the upper part to follow the lower surface?"),
            .init(id: "intent-fit", prompt: "A pin is 10.0 ± 0.2 mm. A hole is 10.2 ± 0.1 mm. Is clearance guaranteed for every allowed pair?", options: ["Yes, because the nominal hole is larger.", "Yes, because both values have tolerances.", "No: a 10.2 mm pin can meet a 10.1 mm hole."], correctIndex: 2, explanation: "The largest allowed pin exceeds the smallest allowed hole. Nominal clearance does not guarantee clearance at the limits.", hint: "Try pairing the largest pin with the smallest hole."),
            .init(id: "intent-grid", prompt: "Your placement requires X = 12 cm, but a 5 cm grid rounds positions. What is the appropriate action?", options: ["Disable snapping and enter 12 cm, then verify the position.", "Enter 12 cm repeatedly until the grid changes.", "Scale the shape to change the grid spacing."], correctIndex: 0, explanation: "A 5 cm grid does not include 12 cm. Disable snapping or choose a finer grid when a specific off-grid coordinate is required.", hint: "A placement aid should support the requirement, not silently replace it.")
        ],
        activity: .init(activity: .cad, task: "Build a stacked pair with snapping enabled. Resize the lower part, inspect the contact, and reposition the upper part if needed. Explain which relationship the grid did not preserve.")
    )

    static let glossary: [GlossaryTerm] = [
        .init(term: "Voltage", definition: "Electrical energy transferred per unit charge between two points, measured in volts (V).", track: .circuits),
        .init(term: "Current", definition: "The rate at which electric charge passes a point, measured in amperes (A).", track: .circuits),
        .init(term: "Resistance", definition: "Opposition to current, measured in ohms (Ω).", track: .circuits),
        .init(term: "Node", definition: "A connection point shared by circuit elements connected by ideal conducting wires.", track: .circuits),
        .init(term: "Series", definition: "A connection in which components carry one shared current along an unbranched path.", track: .circuits),
        .init(term: "Parallel", definition: "A connection in which components share the same two nodes and therefore the same voltage.", track: .circuits),
        .init(term: "Forward voltage", definition: "The voltage across a conducting diode in its forward direction; the lab approximates it as 2 V for its LED.", track: .circuits),
        .init(term: "Net force", definition: "The vector sum of all external forces acting on the chosen object.", track: .mechanics),
        .init(term: "Velocity", definition: "Speed together with direction.", track: .mechanics),
        .init(term: "Acceleration", definition: "The rate at which velocity changes, including changes in direction.", track: .mechanics),
        .init(term: "Torque", definition: "A force's turning effect about a chosen pivot or axis, measured in newton-metres.", track: .mechanics),
        .init(term: "Lever arm", definition: "The perpendicular distance from a pivot to a force's line of action.", track: .mechanics),
        .init(term: "Gear ratio", definition: "In this course, driven tooth count divided by driver tooth count for a gear pair.", track: .mechanics),
        .init(term: "Origin", definition: "The reference location with coordinates (0, 0, 0).", track: .design),
        .init(term: "Primitive", definition: "A basic solid used as a building block, such as a box, sphere, cylinder, or cone.", track: .design),
        .init(term: "Uniform scale", definition: "A resize operation that multiplies all length dimensions by the same factor.", track: .design),
        .init(term: "Constraint", definition: "A rule that keeps a geometric or dimensional relationship true when a design changes.", track: .design),
        .init(term: "Tolerance", definition: "The permitted variation in a dimension or geometric property.", track: .design),
        .init(term: "Clearance", definition: "The gap between mating features; diametral clearance compares a hole's diameter with a pin's diameter.", track: .design)
    ]

    static let references: [LearningReference] = [
        .init(title: "OpenStax · Electrical current", url: "https://openstax.org/books/university-physics-volume-2/pages/9-1-electrical-current"),
        .init(title: "OpenStax · Ohm's law", url: "https://openstax.org/books/university-physics-volume-2/pages/9-4-ohms-law"),
        .init(title: "OpenStax · Series and parallel resistors", url: "https://openstax.org/books/university-physics-volume-2/pages/10-2-resistors-in-series-and-parallel"),
        .init(title: "OpenStax · Electrical measuring instruments", url: "https://openstax.org/books/university-physics-volume-2/pages/10-4-electrical-measuring-instruments"),
        .init(title: "Adafruit · LED forward voltage and Kirchhoff's voltage law", url: "https://learn.adafruit.com/all-about-leds/forward-voltage-and-kvl"),
        .init(title: "OpenStax · Newton's first law", url: "https://openstax.org/books/university-physics-volume-1/pages/5-2-newtons-first-law"),
        .init(title: "OpenStax · Newton's second law", url: "https://openstax.org/books/university-physics-volume-1/pages/5-3-newtons-second-law"),
        .init(title: "OpenStax · Torque", url: "https://openstax.org/books/university-physics-volume-1/pages/10-6-torque"),
        .init(title: "UC San Diego · Engineering gear ratios", url: "https://mae3.eng.ucsd.edu/machine-design/gear-ratios"),
        .init(title: "Autodesk · 3D Cartesian coordinates", url: "https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-Core/files/GUID-AABA8FE7-0E86-4046-96D5-CF5464D5FAC6.htm"),
        .init(title: "Autodesk · Uniform and nonuniform scaling", url: "https://help.autodesk.com/cloudhelp/ENU/Fusion-Mesh/files/MESH-SCALE-MESH.htm"),
        .init(title: "NASA Glenn · Volumes of basic solids", url: "https://www.grc.nasa.gov/www/k-12/airplane/volume.html"),
        .init(title: "Autodesk · Dimensional constraints", url: "https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-Core/files/GUID-F7ED2587-8F25-4770-BD13-C7C95456E707.htm"),
        .init(title: "Autodesk · Dimensional tolerance limits", url: "https://help.autodesk.com/cloudhelp/2020/ENU/AutoCAD-Core/files/GUID-03B368E2-A8C6-4885-A6EC-AEBD9BD3B540.htm")
    ]
}
