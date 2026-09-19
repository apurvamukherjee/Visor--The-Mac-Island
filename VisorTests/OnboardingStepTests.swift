import Testing
@testable import Visor

struct OnboardingStepTests {
    @Test func welcomeAdvancesToPermissions() {
        #expect(OnboardingStep.welcome.next == .permissions)
    }

    @Test func permissionsAdvancesToFinish() {
        #expect(OnboardingStep.permissions.next == .finish)
    }

    @Test func finishHasNoNextStep() {
        #expect(OnboardingStep.finish.next == nil)
    }
}
