import Foundation

enum LearningTrack: String, CaseIterable, Codable, Identifiable {
    case circuits, mechanics, design
    var id: String { rawValue }
    var title: String {
        switch self {
        case .circuits: "Circuit foundations"
        case .mechanics: "Mechanics in motion"
        case .design: "Spatial design"
        }
    }
    var symbol: String {
        switch self {
        case .circuits: "bolt.fill"
        case .mechanics: "gearshape.2.fill"
        case .design: "cube.transparent.fill"
        }
    }
    var subtitle: String {
        switch self {
        case .circuits: "Predict, connect, and measure"
        case .mechanics: "Explain forces and motion"
        case .design: "Build with purpose in 3D"
        }
    }
}

enum LessonVisual: String, Codable {
    case circuit, seriesParallel, led, forces, lever, gears, coordinates, solids, constraints
}

enum LearningActivity: String, Codable {
    case circuit, cad, piston, gears
    var title: String {
        switch self {
        case .circuit: "Try the circuit lab"
        case .cad: "Try the CAD studio"
        case .piston: "Explore the piston assembly"
        case .gears: "Explore the gear train"
        }
    }
}

struct LessonSection: Hashable {
    let title: String
    let text: String
}

struct EquationCard: Hashable {
    let name: String
    let expression: String
    let symbols: String
}

struct WorkedExample: Hashable {
    let title: String
    let prompt: String
    let steps: [String]
    let takeaway: String
}

struct PracticeQuestion: Identifiable, Hashable {
    let id: String
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
    let hint: String
}

struct ActivityPrompt: Hashable {
    let activity: LearningActivity
    let task: String
}

struct Lesson: Identifiable, Hashable {
    let id: String
    let track: LearningTrack
    let title: String
    let summary: String
    let minutes: Int
    let objective: String
    let sections: [LessonSection]
    let equation: EquationCard?
    let example: WorkedExample
    let visual: LessonVisual
    let practice: [PracticeQuestion]
    let activity: ActivityPrompt
}

struct GlossaryTerm: Identifiable, Hashable {
    var id: String { term }
    let term: String
    let definition: String
    let track: LearningTrack
}

struct LearningReference: Identifiable, Hashable {
    var id: String { url }
    let title: String
    let url: String
}
