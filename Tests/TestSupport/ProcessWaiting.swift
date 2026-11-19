import Foundation

extension Process {
    /// Use instead of `waitUntilExit()`, which waits on the current run loop
    /// and can miss the exit on a thread without one, such as Swift
    /// concurrency's, hanging the test after the process has already ended.
    public func waitForExit(timeout: Duration = .seconds(30)) {
        let deadline = ContinuousClock.now + timeout
        while isRunning, ContinuousClock.now < deadline {
            usleep(10_000)
        }
    }
}
