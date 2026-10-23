import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("Audio Permission Helper & Status Test Suite")
struct AudioPermissionHelperTests {
    
    @Test("AudioPermissionStatus isGranted and needsRequest flags evaluate correctly")
    func testPermissionStatusFlags() {
        #expect(AudioPermissionStatus.authorized.isGranted == true)
        #expect(AudioPermissionStatus.authorized.needsRequest == false)
        
        #expect(AudioPermissionStatus.notDetermined.isGranted == false)
        #expect(AudioPermissionStatus.notDetermined.needsRequest == true)
        
        #expect(AudioPermissionStatus.denied.isGranted == false)
        #expect(AudioPermissionStatus.denied.needsRequest == false)
        
        #expect(AudioPermissionStatus.restricted.isGranted == false)
        #expect(AudioPermissionStatus.restricted.needsRequest == false)
    }
    
    @Test("AudioPermissionHelper checkMicrophoneStatus returns non-nil valid state")
    func testMicrophoneStatusInspection() {
        let status = AudioPermissionHelper.checkMicrophoneStatus()
        #expect([AudioPermissionStatus.authorized, .notDetermined, .denied, .restricted].contains(status))
    }
    
    @Test("AudioPermissionHelper checkSystemAudioStatus returns non-nil valid state")
    func testSystemAudioStatusInspection() {
        let status = AudioPermissionHelper.checkSystemAudioStatus()
        #expect([AudioPermissionStatus.authorized, .denied].contains(status))
    }
    
    @Test("Privacy Settings URL schemes are valid and correctly formatted")
    func testPrivacySettingsURLSchemes() {
        let micURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        let screenURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        
        #expect(micURL != nil)
        #expect(micURL?.scheme == "x-apple.systempreferences")
        #expect(micURL?.query == "Privacy_Microphone")
        
        #expect(screenURL != nil)
        #expect(screenURL?.scheme == "x-apple.systempreferences")
        #expect(screenURL?.query == "Privacy_ScreenCapture")
    }
}
