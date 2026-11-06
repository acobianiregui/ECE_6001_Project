import Foundation

/// Ideal magnitudes for one pair of external gears with equal tooth size.
struct GearRatioResult {
    let inputTeeth: Int
    let outputTeeth: Int
    let inputRPM: Double
    let inputTorque: Double
    var ratio: Double { Double(outputTeeth) / Double(inputTeeth) }
    var outputRPM: Double { inputRPM / ratio }
    var outputTorque: Double { inputTorque * ratio }
    var speedPrediction: String {
        outputTeeth == inputTeeth ? "Same speed" : outputTeeth > inputTeeth ? "Slower" : "Faster"
    }
}

