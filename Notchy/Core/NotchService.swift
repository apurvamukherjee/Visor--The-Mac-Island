/// A feature's data source. `start()`/`stop()` must be idempotent and
/// `stop()` must release every process, observer, and run-loop source —
/// nothing may keep running once `stop()` returns.
@MainActor
protocol NotchService: AnyObject {
    func start()
    func stop()
}
