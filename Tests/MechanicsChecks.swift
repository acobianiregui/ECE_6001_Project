import Foundation
@main struct MechanicsModelTests {
    static func main() {
        let reduction = GearRatioResult(inputTeeth: 12, outputTeeth: 36, inputRPM: 90, inputTorque: 1)
        assert(reduction.ratio == 3 && reduction.outputRPM == 30 && reduction.outputTorque == 3)
        assert(reduction.speedPrediction == "Slower")
        let increase = GearRatioResult(inputTeeth: 36, outputTeeth: 12, inputRPM: 90, inputTorque: 1)
        assert(abs(increase.outputRPM - 270) < 0.00001)
        assert(abs(increase.outputTorque - 1.0 / 3) < 0.00001)
        assert(increase.speedPrediction == "Faster")
        let equal = GearRatioResult(inputTeeth: 24, outputTeeth: 24, inputRPM: 120, inputTorque: 2)
        assert(equal.outputRPM == 120 && equal.outputTorque == 2 && equal.speedPrediction == "Same speed")
        for input in stride(from: 12, through: 60, by: 6) {
            for output in stride(from: 12, through: 60, by: 6) {
                let pair = GearRatioResult(inputTeeth: input, outputTeeth: output, inputRPM: 90, inputTorque: 2)
                assert(abs(pair.outputRPM * pair.outputTorque - 180) < 0.00001, "Ideal power must be conserved")
            }
        }
        print("Gear model checks passed: reduction, speed increase, equal ratio, predictions, and power conservation across all 81 tooth combinations.")
    }
}
