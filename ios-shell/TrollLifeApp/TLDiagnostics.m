//
//  TLDiagnostics.m
//  TrollLifeApp —— 崩溃日志与自诊断（实现）
//

#import "TLDiagnostics.h"
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <execinfo.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdio.h>
#import <string.h>
#import <time.h>

/* ---------------- 全局状态 ---------------- */
static int gLogFd = -1;                       /* 预先打开的日志 fd，供信号处理器异步安全写入 */
static char gStageBuf[128] = "app-start";     /* 当前阶段（信号处理器里只能读 C 缓冲区） */
static NSString *const kKeyCrashCount = @"tl_crash_count";
static NSString *const kKeyLastStage = @"tl_last_stage";
static NSString *const kKeyLastReady = @"tl_last_ready";
static NSString *const kKeyBreadcrumbs = @"tl_breadcrumbs";
static BOOL gSafeMode = NO;

NSString *TLDocumentsPath(void) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return dirs.count > 0 ? dirs[0] : NSTemporaryDirectory();
}

NSString *TLLogPath(void) {
    return [TLDocumentsPath() stringByAppendingPathComponent:@"crash.log"];
}

void TLFlush(void) {
    @try { [[NSUserDefaults standardUserDefaults] synchronize]; } @catch (NSException *e) { }
}

/* ---------------- 日志写入 ---------------- */
void TLLog(NSString *format, ...) {
    if (format.length == 0) { return; }
    @try {
        va_list args;
        va_start(args, format);
        NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"HH:mm:ss.SSS";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], body];

        NSString *path = TLLogPath();
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        } else {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
            if (fh) {
                [fh seekToEndOfFile];
                [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [fh closeFile];
            }
        }
        /* 防止无限增长：超过 400KB 就只保留最后 200KB */
        NSDictionary *attr = [fm attributesOfItemAtPath:path error:NULL];
        if ([attr fileSize] > 400 * 1024) {
            NSString *all = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
            if (all.length > 200 * 1024) {
                NSString *tail = [all substringFromIndex:all.length - 200 * 1024];
                [tail writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
        }
    } @catch (NSException *e) { }
}

/* ---------------- 面包屑 ---------------- */
void TLMarkStage(NSString *stage) {
    if (stage.length == 0) { return; }
    @try {
        strncpy(gStageBuf, [stage UTF8String], sizeof(gStageBuf) - 1);
        gStageBuf[sizeof(gStageBuf) - 1] = 0;

        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSMutableArray *arr = [NSMutableArray arrayWithArray:([d arrayForKey:kKeyBreadcrumbs] ?: @[])];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"HH:mm:ss";
        [arr addObject:[NSString stringWithFormat:@"%@ %@", [df stringFromDate:[NSDate date]], stage]];
        while (arr.count > 40) { [arr removeObjectAtIndex:0]; }
        [d setObject:arr forKey:kKeyBreadcrumbs];
        [d setObject:stage forKey:kKeyLastStage];
        [d synchronize];

        TLLog(@"● 阶段: %@", stage);
        if (gLogFd >= 0) {
            char buf[192];
            int n = snprintf(buf, sizeof(buf), "[stage] %s\n", gStageBuf);
            if (n > 0) { write(gLogFd, buf, (size_t)n); }
        }
    } @catch (NSException *e) { }
}

NSArray<NSString *> *TLBreadcrumbs(void) {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:kKeyBreadcrumbs] ?: @[];
}

NSInteger TLLaunchFailCount(void) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kKeyCrashCount];
}

BOOL TLIsSafeMode(void) { return gSafeMode; }
void TLSetSafeMode(BOOL value) { gSafeMode = value; }

void TLMarkLaunchStart(void) {
    @try {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSInteger fails = [d integerForKey:kKeyCrashCount];
        NSString *lastStage = [d stringForKey:kKeyLastStage];
        BOOL lastReady = [d boolForKey:kKeyLastReady];

        if (!lastReady && lastStage.length > 0) {
            /* 上次启动没有走到 ready，说明它在 lastStage 之后崩了 */
            fails += 1;
            TLLog(@"‼️ 检测到上次启动未完成（停在阶段：%@），连续失败次数 = %ld", lastStage, (long)fails);
        }
        [d setInteger:fails forKey:kKeyCrashCount];
        [d setBool:NO forKey:kKeyLastReady];   /* 本次启动先标记「未完成」 */
        [d synchronize];

        /* 连续 2 次没跑完 → 直接进安全模式（不创建 WKWebView） */
        gSafeMode = (fails >= 2);
        if (gSafeMode) { TLLog(@"⚠️ 连续 %ld 次启动失败，进入安全模式（不加载 WKWebView）", (long)fails); }
    } @catch (NSException *e) { }
}

void TLMarkReady(void) {
    @try {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setBool:YES forKey:kKeyLastReady];
        [d setInteger:0 forKey:kKeyCrashCount];
        [d synchronize];
        TLLog(@"✅ 启动完成（阶段 ready）");
    } @catch (NSException *e) { }
}

void TLClearLog(void) {
    @try {
        [[NSFileManager defaultManager] removeItemAtPath:TLLogPath() error:NULL];
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d removeObjectForKey:kKeyBreadcrumbs];
        [d removeObjectForKey:kKeyLastStage];
        [d setInteger:0 forKey:kKeyCrashCount];
        [d setBool:YES forKey:kKeyLastReady];
        [d synchronize];
        TLLog(@"日志已清空");
    } @catch (NSException *e) { }
}

/* ---------------- 崩溃捕获 ---------------- */
static void TLSignalHandler(int sig) {
    /* 信号处理器里只能用异步安全函数：write / backtrace_symbols_fd */
    if (gLogFd >= 0) {
        char head[256];
        int n = snprintf(head, sizeof(head),
                         "\n===== 信号崩溃 signal=%d (%s) 阶段=%s =====\n",
                         sig, strsignal(sig), gStageBuf);
        if (n > 0) { write(gLogFd, head, (size_t)n); }

        void *callstack[64];
        int frames = backtrace(callstack, 64);
        backtrace_symbols_fd(callstack, frames, gLogFd);
        const char *tail = "===== 信号崩溃结束 =====\n";
        write(gLogFd, tail, strlen(tail));
        fsync(gLogFd);
    }
    /* 记一次启动失败，下次启动会进安全模式 */
    @try {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setInteger:([d integerForKey:kKeyCrashCount] + 1) forKey:kKeyCrashCount];
        [d setBool:NO forKey:kKeyLastReady];
        [d synchronize];
    } @catch (NSException *e) { }

    signal(sig, SIG_DFL);
    raise(sig);
}

static void TLExceptionHandler(NSException *exception) {
    @try {
        NSString *info = [NSString stringWithFormat:
                          @"\n===== 未捕获异常 =====\n名称: %@\n原因: %@\n用户信息: %@\n调用栈:\n%@\n===== 异常结束 =====\n",
                          exception.name, exception.reason, exception.userInfo,
                          [exception.callStackSymbols componentsJoinedByString:@"\n"]];
        TLLog(@"%@", info);

        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setInteger:([d integerForKey:kKeyCrashCount] + 1) forKey:kKeyCrashCount];
        [d setBool:NO forKey:kKeyLastReady];
        [d synchronize];
    } @catch (NSException *e) { }
}

void TLInstallCrashHandlers(void) {
    /* 预先打开日志 fd，信号处理器里才能安全写入 */
    if (gLogFd < 0) {
        NSString *path = TLLogPath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        gLogFd = open([path fileSystemRepresentation], O_WRONLY | O_APPEND | O_CREAT, 0644);
    }
    NSSetUncaughtExceptionHandler(&TLExceptionHandler);
    signal(SIGABRT, TLSignalHandler);
    signal(SIGILL, TLSignalHandler);
    signal(SIGSEGV, TLSignalHandler);
    signal(SIGFPE, TLSignalHandler);
    signal(SIGBUS, TLSignalHandler);
    signal(SIGPIPE, TLSignalHandler);
    signal(SIGTRAP, TLSignalHandler);
}

/* ---------------- 诊断报告 ---------------- */
static NSString *TLDeviceModel(void) {
    struct utsname u;
    if (uname(&u) == 0) { return [NSString stringWithFormat:@"%s (%s)", u.machine, u.version]; }
    return @"未知";
}

NSString *TLDiagnosticReport(void) {
    NSMutableString *r = [NSMutableString string];
    @try {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        [r appendString:@"===== TrollLifeAI 诊断报告 =====\n"];
        [r appendFormat:@"生成时间     : %@\n", [NSDate date]];
        [r appendFormat:@"设备型号     : %@\n", TLDeviceModel()];
        [r appendFormat:@"系统版本     : %@ %@\n", [[UIDevice currentDevice] systemName], [[UIDevice currentDevice] systemVersion]];
        [r appendFormat:@"机型标识     : %@\n", [[UIDevice currentDevice] model]];
        [r appendFormat:@"App 版本     : %@ (%@)\n", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]];
        [r appendFormat:@"Bundle ID    : %@\n", info[@"CFBundleIdentifier"]];
        [r appendFormat:@"可执行文件   : %@\n", info[@"CFBundleExecutable"]];
        [r appendFormat:@"Bundle 路径  : %@\n", [[NSBundle mainBundle] bundlePath]];
        [r appendFormat:@"安全模式     : %@\n", gSafeMode ? @"是（上次连续启动失败）" : @"否"];
        [r appendFormat:@"连续失败次数 : %ld\n", (long)TLLaunchFailCount()];
        [r appendString:@"\n----- 启动面包屑（从早到晚）-----\n"];

        NSArray *crumbs = TLBreadcrumbs();
        if (crumbs.count == 0) { [r appendString:@"(无)\n"]; }
        for (NSString *c in crumbs) { [r appendFormat:@"  %@\n", c]; }

        /* 资源检查：这是「白屏」类问题最常见的根因 */
        [r appendString:@"\n----- 内置资源检查 -----\n"];
        NSArray *cands = @[@"index.html", @"www/index.html", @"Resources/index.html"];
        for (NSString *c in cands) {
            NSString *p = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:c];
            BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:p];
            unsigned long long size = 0;
            if (exists) {
                NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:p error:NULL];
                size = [a fileSize];
            }
            [r appendFormat:@"  %-22s %@  %llu 字节\n", [c UTF8String], exists ? @"存在" : @"缺失", size];
        }

        [r appendString:@"\n----- 日志文件 -----\n"];
        [r appendFormat:@"路径: %@\n", TLLogPath()];
        NSString *log = [NSString stringWithContentsOfFile:TLLogPath() encoding:NSUTF8StringEncoding error:NULL];
        if (log.length > 12000) { log = [log substringFromIndex:log.length - 12000]; }
        [r appendString:(log.length ? log : @"(空)\n")];
    } @catch (NSException *e) {
        [r appendFormat:@"生成报告时出错: %@\n", e.reason];
    }
    return r;
}

/* ---------------- 诊断页（纯 UIKit，不依赖 WebKit） ---------------- */
@interface TLDiagnosticViewController ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation TLDiagnosticViewController

+ (instancetype)make {
    TLDiagnosticViewController *vc = [[TLDiagnosticViewController alloc] init];
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.06 blue:0.07 alpha:1.0];

    UILabel *title = [[UILabel alloc] init];
    title.text = TLIsSafeMode() ? @"安全模式 · 启动诊断" : @"运行诊断";
    title.textColor = [UIColor colorWithWhite:0.92 alpha:1];
    title.font = [UIFont boldSystemFontOfSize:17];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *hint = [[UILabel alloc] init];
    hint.numberOfLines = 0;
    hint.text = @"如果 App 一打开就闪退，请把下面这份报告截图发给开发者；\n"
                @"也可以到「文件」App → 我的 iPhone → TrollLifeAI → crash.log 取完整日志。";
    hint.textColor = [UIColor colorWithWhite:0.62 alpha:1];
    hint.font = [UIFont systemFontOfSize:12];
    hint.translatesAutoresizingMaskIntoConstraints = NO;

    self.textView = [[UITextView alloc] init];
    self.textView.editable = NO;
    self.textView.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.11 alpha:1];
    self.textView.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.textView.text = TLDiagnosticReport();
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *buttons = [[UIStackView alloc] init];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.spacing = 8;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray *titles = @[@"重试打开网页", @"复制报告", @"清空日志"];
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:14];
        b.backgroundColor = [UIColor colorWithRed:0.11 green:0.13 blue:0.17 alpha:1];
        b.layer.cornerRadius = 10;
        b.tag = i;
        [b addTarget:self action:@selector(onButton:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addArrangedSubview:b];
    }

    [self.view addSubview:title];
    [self.view addSubview:hint];
    [self.view addSubview:self.textView];
    [self.view addSubview:buttons];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [title.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [hint.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [hint.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],

        [self.textView.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:10],
        [self.textView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [self.textView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [self.textView.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-10],

        [buttons.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [buttons.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [buttons.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
        [buttons.heightAnchor constraintEqualToConstant:44]
    ]];
}

- (void)onButton:(UIButton *)sender {
    if (sender.tag == 0) {
        TLLog(@"用户在诊断页点了「重试打开网页」");
        if (self.onRetryWebView) { self.onRetryWebView(); }
    } else if (sender.tag == 1) {
        [UIPasteboard generalPasteboard].string = TLDiagnosticReport();
        [self toast:@"报告已复制到剪贴板"];
    } else {
        TLClearLog();
        self.textView.text = TLDiagnosticReport();
        [self toast:@"日志已清空"];
    }
}

- (void)toast:(NSString *)msg {
    UILabel *l = [[UILabel alloc] init];
    l.text = msg;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:13];
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
    l.layer.cornerRadius = 8;
    l.clipsToBounds = YES;
    l.frame = CGRectMake(20, self.view.bounds.size.height - 130, self.view.bounds.size.width - 40, 36);
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:l];
    [UIView animateWithDuration:0.3 delay:1.6 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) { [l removeFromSuperview]; }];
}

@end
