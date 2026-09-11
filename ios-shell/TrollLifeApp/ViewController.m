//
//  ViewController.m
//  TrollLifeApp
//
//  壳的职责只有三件事：
//   1) 把本地 index.html 加载进 WKWebView；
//   2) 提供 nativeFetch / nativeHttp 原生取数通道（解决 file:// 页面的 CORS 问题）；
//   3) 崩溃/白屏兜底 + 自诊断。
//  业务逻辑 100% 在 index.html 里，这里一行业务都不写。
//
//  为了定位「打开闪退」，这里每个关键步骤都会写一条面包屑（TLMarkStage）：
//  崩溃后下次启动就能看到它停在哪个阶段，从而精确定位。
//

#import "ViewController.h"
#import "TLDiagnostics.h"

@interface ViewController ()
@property (nonatomic, assign) BOOL didLoadPage;
@property (nonatomic, weak) TLDiagnosticViewController *diagVC;
@property (nonatomic, assign) NSInteger testLevel;   /* 0=正常启动 1/2/3=分级测试 */
@property (nonatomic, assign) BOOL webViewCreatedInTest;
@end

@implementation ViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    TLMarkStage(@"ViewController.viewDidLoad 进入");

    self.view.backgroundColor = [UIColor colorWithRed:0.051 green:0.059 blue:0.071 alpha:1.0];

    /* 连续启动失败 → 安全模式：完全不碰 WebKit，先让用户看到诊断信息 */
    if (TLIsSafeMode()) {
        TLMarkStage(@"安全模式：跳过 WKWebView，显示诊断页");
        [self installDiagnosticScreenAsRoot];
        return;
    }

    @try {
        [self setupWebView];
    } @catch (NSException *e) {
        TLLog(@"‼️ 创建 WKWebView 抛异常: %@ / %@", e.name, e.reason);
        TLMarkStage(@"WKWebView 创建异常，转入诊断页");
        [self installDiagnosticScreenAsRoot];
    }
}

- (void)dealloc {
    @try {
        [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"nativeFetch"];
        [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"nativeHttp"];
        self.webView.navigationDelegate = nil;
    } @catch (NSException *e) { }
}

#pragma mark - WKWebView 搭建（每一步都留面包屑）

- (void)setupWebView {
    if ([self createWebViewWithTag:@"正常启动"]) {
        [self loadLocalIndexHTML];
    }
}

/* 只负责把 WKWebView 建出来（分级测试与正常启动共用）；返回是否成功 */
- (BOOL)createWebViewWithTag:(NSString *)tag {
    TLMarkStage([NSString stringWithFormat:@"%@：WKWebView 搭建开始", tag]);

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    TLMarkStage([NSString stringWithFormat:@"%@：WKWebViewConfiguration 创建完成", tag]);

    config.allowsInlineMediaPlayback = YES;
    if (@available(iOS 10.0, *)) {
        config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    }

    /* 原生通道：nativeFetch（GET）与 nativeHttp（POST，供 AI 接口用）。
       注意：绝不用私有 KVC 设置 allowFileAccessFromFileURLs，某些 iOS 会直接抛异常闪退。 */
    @try {
        [config.userContentController addScriptMessageHandler:self name:@"nativeFetch"];
        [config.userContentController addScriptMessageHandler:self name:@"nativeHttp"];
        TLMarkStage([NSString stringWithFormat:@"%@：原生通道注册完成", tag]);
    } @catch (NSException *e) {
        TLLog(@"‼️ 注册原生通道失败（不致命，继续）: %@", e.reason);
    }

    CGRect frame = self.view.bounds;
    self.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    TLMarkStage([NSString stringWithFormat:@"%@：WKWebView 实例创建完成", tag]);

    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.backgroundColor = self.view.backgroundColor;
    self.webView.opaque = NO;
    self.webView.allowsBackForwardNavigationGestures = NO;

    /* 安全区与缩放铁律 */
    @try {
        if (@available(iOS 11.0, *)) {
            self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        self.webView.scrollView.pinchGestureRecognizer.enabled = NO;
        self.webView.scrollView.maximumZoomScale = 1.0;
        self.webView.scrollView.minimumZoomScale = 1.0;
        self.webView.scrollView.showsHorizontalScrollIndicator = NO;
        TLMarkStage([NSString stringWithFormat:@"%@：scrollView 设置完成", tag]);
    } @catch (NSException *e) {
        TLLog(@"‼️ 设置 scrollView 属性失败（不致命）: %@", e.reason);
    }

    [self.view insertSubview:self.webView atIndex:0];
    TLMarkStage([NSString stringWithFormat:@"%@：WKWebView 已加入视图层级", tag]);

    return YES;
}

/* 诊断入口做成「不可见」的：摇一摇手机打开诊断页。
   不在界面上常驻任何按钮，避免遮挡页面内容。 */
- (BOOL)canBecomeFirstResponder { return YES; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    TLMarkStage(@"ViewController 已显示");
    [self becomeFirstResponder];
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        TLMarkStage(@"摇一摇：打开诊断页");
        [self showDiagnostics];
        return;
    }
    [super motionEnded:motion withEvent:event];
}

/* 诊断入口：只保留「摇一摇」，界面上不再常驻任何按钮（避免遮挡页面内容）。
   另外连续启动失败会自动进入安全模式，那时也会直接显示诊断页。 */
- (void)showDiagnostics {
    @try {
        TLDiagnosticViewController *vc = [TLDiagnosticViewController make];
        __weak typeof(self) weakSelf = self;
        vc.onRetryWebView = ^{
            [weakSelf dismissViewControllerAnimated:YES completion:^{
                TLSetSafeMode(NO);
                [weakSelf retryWebView];
            }];
        };
        [self presentViewController:vc animated:YES completion:nil];
    } @catch (NSException *e) {
        TLLog(@"‼️ 打开诊断页失败: %@", e.reason);
    }
}

/* 重试：把 WebView 拆掉重建（安全模式下的「重试打开网页」走这里） */
- (void)retryWebView {
    TLMarkStage(@"用户要求重试加载网页");
    @try {
        [self.webView removeFromSuperview];
        self.webView = nil;
        for (UIView *v in self.view.subviews) { [v removeFromSuperview]; }
        self.diagVC = nil;
        self.testLevel = 0;
        [self setupWebView];
    } @catch (NSException *e) {
        TLLog(@"‼️ 重试失败: %@", e.reason);
        [self installDiagnosticScreenAsRoot];
    }
}

/* 诊断页作为根视图（安全模式 / WebView 建不出来时） */
- (void)installDiagnosticScreenAsRoot {
    @try {
        for (UIView *v in self.view.subviews) { [v removeFromSuperview]; }
        TLDiagnosticViewController *vc = [TLDiagnosticViewController make];
        vc.showTestLadder = YES;              /* 安全模式下给出分级测试按钮 */
        __weak typeof(self) weakSelf = self;
        vc.onRetryWebView = ^{
            TLSetSafeMode(NO);
            [weakSelf retryWebView];
        };
        vc.onRunLevel = ^(NSInteger level) {
            [weakSelf runTestLevel:level];
        };
        self.diagVC = vc;
        [self addChildViewController:vc];
        vc.view.frame = self.view.bounds;
        vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:vc.view];
        [vc didMoveToParentViewController:self];
        TLMarkStage(@"诊断页已挂载为根视图（含分级测试）");
    } @catch (NSException *e) {
        TLLog(@"‼️ 挂载诊断页失败: %@", e.reason);
    }
}

#pragma mark - 分级测试（在手机上自己二分定位崩溃点）

/*  1 = 只创建 WKWebView，不加载任何页面
 *  2 = 创建并加载一个最小 HTML
 *  3 = 创建并加载正式的 index.html（成功后自动退出安全模式）
 *  哪一级崩了，下次打开日志里最后一条阶段就是「分级测试第 N 级：…」 */
- (void)runTestLevel:(NSInteger)level {
    self.testLevel = level;
    TLMarkStage([NSString stringWithFormat:@"分级测试第 %ld 级：开始", (long)level]);
    @try {
        [self.webView removeFromSuperview];
        self.webView = nil;
        [self createWebViewWithTag:[NSString stringWithFormat:@"分级测试第 %ld 级", (long)level]];

        if (level >= 3) {
            TLMarkStage(@"分级测试第 3 级：准备加载正式页面");
            [self loadLocalIndexHTML];
        } else if (level == 2) {
            TLMarkStage(@"分级测试第 2 级：加载最小 HTML");
            [self.webView loadHTMLString:
                @"<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
                @"<body style='background:#0D0F12;color:#7FD1AE;font-family:-apple-system;padding:28px'>"
                @"<h2>最小页面 OK</h2><p>能看到这行字说明 WKWebView 本身工作正常。</p></body></html>"
                                baseURL:nil];
        } else {
            TLMarkStage(@"分级测试第 1 级：WebView 创建成功，未加载页面");
            [self.diagVC appendNote:@"① 通过：WKWebView 创建成功，可以继续点 ②。"];
        }
    } @catch (NSException *e) {
        TLLog(@"‼️ 分级测试第 %ld 级抛异常: %@", (long)level, e.reason);
        [self.diagVC appendNote:[NSString stringWithFormat:@"第 %ld 级抛异常：%@", (long)level, e.reason]];
    }
}

/* 测试成功后回到正常界面 */
- (void)finishTestSuccess {
    TLSetSafeMode(NO);
    TLMarkReady();
    TLMarkStage(@"分级测试通过，退出安全模式并显示网页");
    @try {
        TLDiagnosticViewController *vc = self.diagVC;
        if (vc) {
            [vc willMoveToParentViewController:nil];
            [vc.view removeFromSuperview];
            [vc removeFromParentViewController];
            self.diagVC = nil;
        }
        self.testLevel = 0;
        [self.view bringSubviewToFront:self.webView];
    } @catch (NSException *e) {
        TLLog(@"退出诊断界面失败: %@", e.reason);
    }
}

#pragma mark - 加载本地页面（多候选路径）

- (void)loadLocalIndexHTML {
    TLMarkStage(@"开始查找 index.html");
    NSMutableArray *candidates = [NSMutableArray array];

    /* ⚠️ 历史踩坑（就是它导致「打开即闪退」）：
       pathForResource: 找不到资源时返回 nil，而 NSMutableArray 的 addObject: 传 nil 会抛
       NSInvalidArgumentException（-[__NSArrayM insertObject:atIndex:]: object cannot be nil）。
       所以每个候选路径都必须先判空再添加。 */
    NSString *p1 = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    NSString *p2 = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:@"www"];
    NSString *p3 = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:@"Resources"];
    if (p1.length > 0) { [candidates addObject:p1]; } else { TLLog(@"候选路径 index.html(bundle 根) 不存在，跳过"); }
    if (p2.length > 0) { [candidates addObject:p2]; } else { TLLog(@"候选路径 www/index.html 不存在，跳过"); }
    if (p3.length > 0) { [candidates addObject:p3]; } else { TLLog(@"候选路径 Resources/index.html 不存在，跳过"); }

    NSString *path = nil;
    for (NSString *p in candidates) {
        if (p.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:p]) { path = p; break; }
    }

    if (path.length == 0) {
        TLLog(@"‼️ bundle 里找不到 index.html");
        TLMarkStage(@"找不到 index.html（白屏）");
        [self showFatalMessage:@"缺少 index.html：打包时没有把页面拷进 .app，请检查构建流程。"];
        return;
    }

    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    TLLog(@"找到页面: %@ (%llu 字节)", path, [attr fileSize]);

    @try {
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        NSURL *dirURL = [fileURL URLByDeletingLastPathComponent];
        TLMarkStage(@"调用 loadFileURL 加载页面");
        [self.webView loadFileURL:fileURL allowingReadAccessToURL:dirURL];
        self.didLoadPage = YES;
    } @catch (NSException *e) {
        TLLog(@"‼️ loadFileURL 抛异常: %@", e.reason);
        TLMarkStage(@"loadFileURL 异常");
        [self showFatalMessage:[NSString stringWithFormat:@"加载页面失败：%@", e.reason]];
    }
}

- (void)showFatalMessage:(NSString *)msg {
    @try {
        [self.webView loadHTMLString:[NSString stringWithFormat:
            @"<html><body style='background:#0D0F12;color:#D8DEE9;font-family:-apple-system;padding:24px'>"
            @"<h2>无法打开页面</h2><p>%@</p><p style='color:#8899a6;font-size:13px'>右上角「诊断」按钮里可以看到完整日志。</p>"
            @"</body></html>", msg]
                            baseURL:nil];
    } @catch (NSException *e) { }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    TLMarkStage(@"页面加载完成 didFinishNavigation");

    /* 白屏检测：页面 DOM 是否真的有内容 */
    @try {
        [webView evaluateJavaScript:@"(function(){try{return (document.body&&document.body.innerHTML.length)||0;}catch(e){return -1;}})()"
                  completionHandler:^(id result, NSError *error) {
            if (error) {
                TLLog(@"页面脚本自检失败: %@", error.localizedDescription);
                return;
            }
            NSInteger len = [result respondsToSelector:@selector(integerValue)] ? [result integerValue] : -1;
            TLLog(@"页面 DOM 长度 = %ld", (long)len);
            if (len <= 0) {
                TLLog(@"⚠️ 页面渲染为空（白屏），请检查 index.html 是否被正确拷贝、以及 JS 是否报错");
                TLMarkStage(@"页面白屏：DOM 为空");
                [self.diagVC appendNote:[NSString stringWithFormat:@"第 %ld 级：页面加载完成但 DOM 为空（白屏）", (long)self.testLevel]];
            } else {
                TLMarkReady();   /* 到这里说明启动链路完全正常 */
                if (self.testLevel >= 2) {
                    [self.diagVC appendNote:[NSString stringWithFormat:@"第 %ld 级通过：页面已渲染，DOM 长度 %ld", (long)self.testLevel, (long)len]];
                }
                if (self.testLevel >= 3) {
                    [self finishTestSuccess];
                }
            }
        }];
    } @catch (NSException *e) {
        TLLog(@"白屏检测异常: %@", e.reason);
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    TLLog(@"‼️ 页面加载失败: %@ (%ld)", error.localizedDescription, (long)error.code);
    TLMarkStage([NSString stringWithFormat:@"页面加载失败 %ld", (long)error.code]);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    TLLog(@"‼️ 页面预加载失败: %@ (%ld)", error.localizedDescription, (long)error.code);
    TLMarkStage([NSString stringWithFormat:@"页面预加载失败 %ld", (long)error.code]);
}

/* WebContent 进程被杀（内存不足）时自动重载，避免长时间白屏 */
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    TLLog(@"⚠️ WebContent 进程被终止，重新加载页面");
    TLMarkStage(@"WebContent 进程被终止");
    [webView reload];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (url == nil || [url.scheme isEqualToString:@"file"] || [url.scheme isEqualToString:@"about"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated && url.scheme.length > 0) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - 原生取数通道（file:// 页面绕开 CORS）

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"nativeHttp"]) {
        [self handleNativeHttp:message.body];
        return;
    }
    if (![message.name isEqualToString:@"nativeFetch"]) { return; }

    NSString *urlString = nil;
    double timeout = 15.0;
    if ([message.body isKindOfClass:[NSDictionary class]]) {
        NSDictionary *body = (NSDictionary *)message.body;
        id u = body[@"url"];
        id t = body[@"timeout"];
        if ([u isKindOfClass:[NSString class]]) { urlString = (NSString *)u; }
        if ([t respondsToSelector:@selector(doubleValue)]) { timeout = [t doubleValue] / 1000.0; }
    } else if ([message.body isKindOfClass:[NSString class]]) {
        urlString = (NSString *)message.body;
    }
    if (urlString.length == 0) {
        [self callbackToJS:nil text:nil error:@"empty url"];
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        [self callbackToJS:nil text:nil error:@"bad url"];
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = timeout > 0 ? timeout : 15.0;
    req.HTTPMethod = @"GET";
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 TrollLifeApp/1.0"
        forHTTPHeaderField:@"User-Agent"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = req.timeoutInterval;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *text = nil;
        if (data.length > 0) {
            text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (text == nil) { text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding]; }
        }
        NSString *err = error ? error.localizedDescription : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf callbackToJS:nil text:text error:err];
        });
    }];
    [task resume];
}

/* 通用 HTTP 通道：POST/GET + 自定义请求头 + 请求体（只负责传输，不解析业务） */
- (void)handleNativeHttp:(id)body {
    if (![body isKindOfClass:[NSDictionary class]]) {
        [self callbackHttpToJS:@"bad payload" text:nil status:0];
        return;
    }
    NSDictionary *req = (NSDictionary *)body;
    NSString *urlString = [req[@"url"] isKindOfClass:[NSString class]] ? req[@"url"] : nil;
    NSString *method = [req[@"method"] isKindOfClass:[NSString class]] ? [req[@"method"] uppercaseString] : @"POST";
    NSString *bodyText = [req[@"body"] isKindOfClass:[NSString class]] ? req[@"body"] : nil;
    NSDictionary *headers = [req[@"headers"] isKindOfClass:[NSDictionary class]] ? req[@"headers"] : nil;
    double timeout = [req[@"timeout"] respondsToSelector:@selector(doubleValue)] ? [req[@"timeout"] doubleValue] / 1000.0 : 45.0;
    if (timeout < 3.0) { timeout = 3.0; }
    if (timeout > 180.0) { timeout = 180.0; }

    if (urlString.length == 0) {
        [self callbackHttpToJS:@"empty url" text:nil status:0];
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        [self callbackHttpToJS:@"bad url" text:nil status:0];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.timeoutInterval = timeout;
    if (bodyText.length > 0 && ![method isEqualToString:@"GET"]) {
        request.HTTPBody = [bodyText dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (headers.count > 0) {
        for (NSString *key in headers) {
            id v = headers[key];
            if ([v isKindOfClass:[NSString class]]) { [request setValue:(NSString *)v forHTTPHeaderField:key]; }
        }
    }
    if ([request valueForHTTPHeaderField:@"User-Agent"].length == 0) {
        [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 TrollLifeApp/1.0"
       forHTTPHeaderField:@"User-Agent"];
    }

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = timeout;
    cfg.timeoutIntervalForResource = timeout + 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *text = nil;
        long status = 0;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            status = (long)[(NSHTTPURLResponse *)response statusCode];
        }
        if (data.length > 0) {
            text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (text == nil) { text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding]; }
        }
        NSString *err = error ? error.localizedDescription : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf callbackHttpToJS:err text:text status:status];
        });
    }];
    [task resume];
}

/* 回传给页面：页面里定义了 window.__nativeHttpResult(err, text, status) */
- (void)callbackHttpToJS:(NSString *)err text:(NSString *)text status:(long)status {
    NSString *js = nil;
    if (err.length > 0) {
        js = [NSString stringWithFormat:@"window.__nativeHttpResult(%@, null, %ld);", [self jsString:err], status];
    } else {
        js = [NSString stringWithFormat:@"window.__nativeHttpResult(null, %@, %ld);",
              [self jsString:(text ? text : @"")], status];
    }
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

/* 回传给页面：页面里定义了 window.__nativeResult(err, text) */
- (void)callbackToJS:(id)req text:(NSString *)text error:(NSString *)error {
    NSString *js = nil;
    if (error.length > 0) {
        js = [NSString stringWithFormat:@"window.__nativeResult(%@, null);", [self jsString:error]];
    } else {
        js = [NSString stringWithFormat:@"window.__nativeResult(null, %@);", [self jsString:(text ? text : @"")]];
    }
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

/* 把字符串安全地转成 JS 字面量（不依赖 JSON 库，手写转义） */
- (NSString *)jsString:(NSString *)s {
    if (s == nil) { return @"''"; }
    NSMutableString *out = [NSMutableString stringWithString:@"'"];
    NSUInteger len = s.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
            case '\\': [out appendString:@"\\\\"]; break;
            case '\'': [out appendString:@"\\'"]; break;
            case '\n': [out appendString:@"\\n"]; break;
            case '\r': [out appendString:@"\\r"]; break;
            case '\t': [out appendString:@"\\t"]; break;
            case 0x2028: [out appendString:@"\\u2028"]; break;
            case 0x2029: [out appendString:@"\\u2029"]; break;
            default:
                if (c < 0x20) { [out appendFormat:@"\\u%04x", c]; }
                else { [out appendFormat:@"%C", c]; }
                break;
        }
    }
    [out appendString:@"'"];
    return out;
}

#pragma mark - 安全区与状态栏

- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (BOOL)shouldAutorotate { return NO; }

@end
