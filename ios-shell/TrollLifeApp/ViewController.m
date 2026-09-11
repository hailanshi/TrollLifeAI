//
//  ViewController.m
//  TrollLifeApp
//
//  壳的职责只有三件事：
//   1) 把本地 index.html 加载进 WKWebView；
//   2) 提供 nativeFetch 原生取数通道（解决 file:// 页面被 CORS 拦住的问题）；
//   3) 处理崩溃/白屏兜底。
//  业务逻辑 100% 在 index.html 里，这里一行业务都不写。
//

#import "ViewController.h"
#import "AppDelegate.h"

@interface ViewController ()
@property (nonatomic, assign) BOOL didLoadPage;
@end

@implementation ViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:0.051 green:0.059 blue:0.071 alpha:1.0]; /* #0D0F12 */

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    if (@available(iOS 10.0, *)) {
        config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    }
    /* 原生取数通道：
       - nativeFetch：简单 GET（window.webkit.messageHandlers.nativeFetch.postMessage({url,timeout})）
       - nativeHttp ：支持 GET/POST + 自定义请求头 + 请求体，供页面调用外部 API（绕开 file:// 的 CORS）
       壳只做传输，不解析、不判断业务。 */
    [config.userContentController addScriptMessageHandler:self name:@"nativeFetch"];
    [config.userContentController addScriptMessageHandler:self name:@"nativeHttp"];
    /* 注意：绝对不要用私有 KVC 给 WKPreferences 设 allowFileAccessFromFileURLs，不同 iOS 会抛异常闪退 */

    CGRect frame = self.view.bounds;
    self.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.backgroundColor = self.view.backgroundColor;
    self.webView.opaque = NO;
    self.webView.allowsBackForwardNavigationGestures = NO;

    /* 安全区 / 缩放铁律 */
    if (@available(iOS 11.0, *)) {
        self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    self.webView.scrollView.pinchGestureRecognizer.enabled = NO;      /* 禁掉双指缩放 */
    self.webView.scrollView.maximumZoomScale = 1.0;
    self.webView.scrollView.minimumZoomScale = 1.0;
    self.webView.scrollView.bounces = YES;
    self.webView.scrollView.alwaysBounceVertical = YES;
    self.webView.scrollView.showsHorizontalScrollIndicator = NO;

    [self.view addSubview:self.webView];

    /* 长按/双击缩放也一并关掉 */
    for (UIGestureRecognizer *g in self.webView.scrollView.gestureRecognizers) {
        if ([g isKindOfClass:[UIPinchGestureRecognizer class]]) { g.enabled = NO; }
    }
    for (UIGestureRecognizer *g in self.webView.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)g;
            if (tap.numberOfTapsRequired == 2) { g.enabled = NO; }
        }
    }

    [self loadLocalIndexHTML];
}

- (void)dealloc {
    @try {
        [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"nativeFetch"];
        [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"nativeHttp"];
        self.webView.navigationDelegate = nil;
    } @catch (NSException *e) { }
}

#pragma mark - 加载本地页面（多候选路径）

- (void)loadLocalIndexHTML {
    NSMutableArray *candidates = [NSMutableArray array];
    [candidates addObject:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"]];           /* .app/index.html */
    [candidates addObject:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:@"www"]]; /* .app/www/index.html */
    [candidates addObject:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:@"Resources"]];

    NSString *path = nil;
    for (NSString *p in candidates) {
        if (p.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:p]) { path = p; break; }
    }

    if (path.length == 0) {
        [AppDelegate appendCrashLog:@"致命错误：bundle 里找不到 index.html"];
        [self.webView loadHTMLString:
         @"<html><body style='background:#0D0F12;color:#D8DEE9;font-family:-apple-system;padding:24px'>"
         @"<h2>缺少 index.html</h2><p>打包时没有把 index.html 拷进 .app，请检查构建流程。</p></body></html>"
                            baseURL:nil];
        return;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    NSURL *dirURL = [fileURL URLByDeletingLastPathComponent];
    [AppDelegate appendCrashLog:[NSString stringWithFormat:@"加载页面: %@", path]];
    [self.webView loadFileURL:fileURL allowingReadAccessToURL:dirURL];
    self.didLoadPage = YES;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [AppDelegate appendCrashLog:@"页面加载完成"];
    /* 页面里没有业务需要的原生调用，这里不注入任何东西 */
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [AppDelegate appendCrashLog:[NSString stringWithFormat:@"页面加载失败: %@", error.localizedDescription]];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [AppDelegate appendCrashLog:[NSString stringWithFormat:@"页面预加载失败: %@", error.localizedDescription]];
}

/* WebContent 进程被杀（内存不足）时自动重载，避免长时间白屏 */
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [AppDelegate appendCrashLog:@"WebContent 进程被终止，重新加载页面"];
    [webView reload];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    /* 只允许本地 file:// 与 about:blank，外链交给系统浏览器 */
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

/* 把结果回传给页面：页面里定义了 window.__nativeResult(err, text) */
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
