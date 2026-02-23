import CameraDomain
import Foundation

public enum ProviderKind: String, CaseIterable, Sendable {
    case tapo
    case ring
}

public enum ProviderRegistry {
    public static func makeProvider(kind: ProviderKind = .tapo) -> any CameraProvider {
        switch kind {
        case .tapo:
            return TapoProvider()
        case .ring:
            return RingProviderAdapter()
        }
    }
}
