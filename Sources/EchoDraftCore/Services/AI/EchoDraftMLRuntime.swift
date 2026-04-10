import Foundation

/// Selects stub vs MLX implementations (CI/dev vs local inference).
public enum EchoDraftMLRuntime: Sendable {
    public static var useStubML: Bool {
        if ProcessInfo.processInfo.environment["ECHODRAFT_USE_STUB_ML"] == "1" {
            return true
        }
        if UserDefaults.standard.bool(forKey: "EchoDraftUseStubML") {
            return true
        }
        return false
    }
}
