//
//  AppDelegate.m
//  TrollLifeApp —— 壳：启动窗口 + 崩溃日志落盘（不写任何业务逻辑）
//

#import "AppDelegate.h"
#import "ViewController.h"
#import <signal.h>

@implementation AppDelegate

/* Documents/crash.log 路径（Info.plist 开了 UIFileSharingEnabled，手机「文件」App 里能看到） */
+ (NSString *)crashLogPath {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *doc = dirs.count > 0 ? dirs[0] : NSTemporaryDirectory();
    return [doc stringByAppendingPathComponent:@"crash.log"];
}

+ (void)appendCrashLog:(NSString *)text {
    if (text.length == 0) { return; }
    @try {
        NSString *path = [self crashLogPath];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], text];

        NSMutableString *all = [NSMutableString string];
        NSString *old = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        if (old.length > 0) { [all appendString:old]; }
        [all appendString:line];
        if (all.length > 200000) { /* 防止无限增长 */
            [all deleteCharactersInRange:NSMakeRange(0, all.length - 100000)];
        }
        [all writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    } @catch (NSException *e) {
        /* 日志本身失败绝不能再抛异常 */
    }
}

/* 未捕获异常 */
static void TrollUncaughtExceptionHandler(NSException *exception) {
    NSString *info = [NSString stringWithFormat:@"未捕获异常: %@\n原因: %@\n堆栈:\n%@",
                      exception.name, exception.reason,
                      [exception.callStackSymbols componentsJoinedByString:@"\n"]];
    [AppDelegate appendCrashLog:info];
}

/* 信号崩溃（越界、野指针等） */
static void TrollSignalHandler(int sig) {
    NSString *info = [NSString stringWithFormat:@"信号崩溃 signal=%d", sig];
    [AppDelegate appendCrashLog:info];
    signal(sig, SIG_DFL);
    raise(sig);
}

+ (void)installCrashHandlers {
    NSSetUncaughtExceptionHandler(&TrollUncaughtExceptionHandler);
    signal(SIGABRT, TrollSignalHandler);
    signal(SIGILL, TrollSignalHandler);
    signal(SIGSEGV, TrollSignalHandler);
    signal(SIGFPE, TrollSignalHandler);
    signal(SIGBUS, TrollSignalHandler);
    signal(SIGPIPE, TrollSignalHandler);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [AppDelegate installCrashHandlers];
    [AppDelegate appendCrashLog:@"=== App 启动 ==="];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    ViewController *vc = [[ViewController alloc] init];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    /* 页面会把状态存在 localStorage，这里不需要处理业务 */
}

@end
