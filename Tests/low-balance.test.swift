import Foundation

@main
struct LowBalanceTests {
    static func main() throws {
        precondition(!LowBalancePolicy.isLow(100, threshold: 100))
        precondition(LowBalancePolicy.isLow(99, threshold: 100))
        precondition(LowBalancePolicy.isLow(0, threshold: 100))
        precondition(!LowBalancePolicy.isLow(nil, threshold: 100))
        precondition(!LowBalancePolicy.isLow(0, threshold: nil))
        precondition(!LowBalancePolicy.isLow(-1, threshold: 100))
        precondition(!LowBalancePolicy.isLow(.nan, threshold: 100))
        precondition(!LowBalancePolicy.isValidThreshold(0))
        precondition(!LowBalancePolicy.isValidThreshold(-1))
        precondition(!LowBalancePolicy.isValidThreshold(.infinity))
        precondition(!LowBalancePolicy.isValidThreshold(1.5))
        let first = LowBalancePolicy.transition(previous: nil, remaining: 99, threshold: 100)
        precondition(first.notify && first.latch == LowBalanceLatch(threshold: 100))
        let repeatLow = LowBalancePolicy.transition(previous: first.latch, remaining: 98, threshold: 100)
        precondition(!repeatLow.notify && repeatLow.latch == first.latch)
        let persisted = try JSONDecoder().decode(LowBalanceLatch.self, from: JSONEncoder().encode(first.latch!))
        precondition(!LowBalancePolicy.transition(previous: persisted, remaining: 97, threshold: 100).notify)
        let recovery = LowBalancePolicy.transition(previous: first.latch, remaining: 100, threshold: 100)
        precondition(!recovery.notify && recovery.latch == nil)
        precondition(LowBalancePolicy.transition(previous: recovery.latch, remaining: 99, threshold: 100).notify)
        let errorSample = LowBalancePolicy.transition(previous: first.latch, remaining: .nan, threshold: 100)
        precondition(!errorSample.notify && errorSample.latch == first.latch)
        precondition(!LowBalancePolicy.transition(previous: errorSample.latch, remaining: 98, threshold: 100).notify)
        precondition(LowBalancePolicy.transition(previous: first.latch, remaining: 99, threshold: nil).latch == nil)
        precondition(LowBalancePolicy.transition(previous: first.latch, remaining: 99, threshold: 200).notify)
        let parsed = try ["10000000", " 100 ", "", "   "].map(LowBalancePolicy.parseThreshold)
        precondition(parsed[0] == 10000000 && parsed[1] == 100 && parsed[2] == nil && parsed[3] == nil)
        for text in ["0", "-1", "1M", "1.5", "1e7", "NaN", "9007199254740992"] {
            do { _ = try LowBalancePolicy.parseThreshold(text); fatalError("Expected invalid threshold: \(text)") }
            catch { }
        }
        print("Low balance policy checks passed: strict boundary, repeat suppression, recovery, persistence, invalid inputs.")
    }
}
