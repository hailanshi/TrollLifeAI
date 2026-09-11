//
//  TLDiagnostics.h
//  TrollLifeApp —— 崩溃日志与自诊断
//
//  为什么需要它：
//    1) 有些崩溃发生在「我们的代码还没跑起来」的阶段（dyld / 系统），异常处理器抓不到；
//       所以用「面包屑 + 上次是否跑完」的方式在下次启动时反推崩溃点。
//    2) 有些崩溃会让 App 直接消失，用户看不到任何信息；所以日志要落盘到 Documents
//       （Info.plist 开了 UIFileSharingEnabled，「文件」App 里能直接看）。
//    3) 连续两次没跑完就自动进入「安全模式」：不创建 WKWebView，改用纯 UIKit 诊断页，
//       保证用户一定能在屏幕上看到原因。
//

#import <UIKit/UIKit.h>

/// 日志文件路径（Documents/crash.log，「文件」App → 我的 iPhone → TrollLifeAI 里可见）
NSString *TLDocumentsPath(void);
NSString *TLLogPath(void);

/// 写一行日志（带毫秒时间戳）
void TLLog(NSString *format, ...);

/// 记录启动阶段（同时写日志 + 存面包屑）
void TLMarkStage(NSString *stage);

/// 进程启动时调用：判断上次是否跑完，决定是否进入安全模式
void TLMarkLaunchStart(void);

/// 启动成功（页面已加载）时调用：清掉崩溃计数
void TLMarkReady(void);

BOOL TLIsSafeMode(void);
void TLSetSafeMode(BOOL value);
NSInteger TLLaunchFailCount(void);
NSArray<NSString *> *TLBreadcrumbs(void);

/// 安装未捕获异常 + 信号处理器（越早调用越好）
void TLInstallCrashHandlers(void);

/// 完整诊断报告（用于屏幕显示 / 复制 / 日志）
NSString *TLDiagnosticReport(void);

/// 清空日志文件
void TLClearLog(void);

/// 强制写出到磁盘
void TLFlush(void);

/// 诊断页（安全模式与「诊断」按钮共用）
@interface TLDiagnosticViewController : UIViewController
@property (nonatomic, copy) void (^onRetryWebView)(void);
/// 分级测试：1=只创建 WKWebView；2=创建并加载最小页面；3=创建并加载正式页面
@property (nonatomic, copy) void (^onRunLevel)(NSInteger level);
@property (nonatomic, assign) BOOL showTestLadder;
- (void)appendNote:(NSString *)note;
+ (instancetype)make;
@end
