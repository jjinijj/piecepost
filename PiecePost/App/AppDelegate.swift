import UIKit

/// 앱 실행 같은 시스템 이벤트를 받는다.
/// 원격 알림을 등록해 두면 다른 기기에서 바뀐 내용을 iCloud가 푸시로 알려 주고, CKSyncEngine이 가져간다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
}
