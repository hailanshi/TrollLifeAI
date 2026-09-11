//
//  AppDelegate.m
//  TrollLifeApp —— 壳：启动窗口 + 崩溃日志（不写任何业务逻辑）
//

#import "AppDelegate.h"
#import "ViewController.h"
#import "TLDiagnostics.h"
#import <signal.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    TLMarkStage(@"AppDelegate didFinishLaunching 开始");
    TLInstallCrashHandlers();
    TLLog(@"===== App 启动 ===== 安全模式=%@ 连续失败=%ld",
          TLIsSafeMode() ? @"是" : @"否", (long)TLLaunchFailCount());

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    TLMarkStage(@"UIWindow 已创建");

    UIViewController *root = nil;
    @try {
        root = [[ViewController alloc] init];
        TLMarkStage(@"根控制器已创建");
    } @catch (NSException *e) {
        TLLog(@"‼️ 创建根控制器抛异常: %@", e.reason);
    }

    if (root == nil) {
        /* 兜底：连根控制器都建不出来时，直接上诊断页，别让用户看到闪退 */
        self.window.rootViewController = [TLDiagnosticViewController make];
        TLMarkStage(@"根控制器创建失败，直接显示诊断页");
    } else {
        self.window.rootViewController = root;
    }

    [self.window makeKeyAndVisible];
    TLMarkStage(@"窗口已显示");
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    TLMarkStage(@"进入后台");
    TLFlush();
}

- (void)applicationWillTerminate:(UIApplication *)application {
    TLMarkStage(@"进程即将结束");
    TLFlush();
}

@end
