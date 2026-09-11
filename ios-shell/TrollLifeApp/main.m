//
//  main.m
//  TrollLifeApp —— 极简 WKWebView 壳（只做容器，不含任何业务逻辑）
//
//  这里在 UIApplicationMain 之前就写下第一行日志，
//  这样即使崩溃发生在启动早期，下次启动也能通过面包屑知道它走到哪一步。
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "TLDiagnostics.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        TLInstallCrashHandlers();     /* 越早装越好：未捕获异常 + 信号 */
        TLMarkLaunchStart();          /* 判断上次是否跑完 → 可能进入安全模式 */
        TLMarkStage(@"main() 进入");

        NSString *cls = NSStringFromClass([AppDelegate class]);
        TLMarkStage([NSString stringWithFormat:@"即将 UIApplicationMain(%@)", cls]);

        int ret = UIApplicationMain(argc, argv, nil, cls);

        TLMarkStage([NSString stringWithFormat:@"UIApplicationMain 返回 %d", ret]);
        return ret;
    }
}
