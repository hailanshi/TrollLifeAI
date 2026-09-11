//
//  ViewController.h
//  TrollLifeApp —— WKWebView 容器
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface ViewController : UIViewController <WKScriptMessageHandler, WKNavigationDelegate>

@property (strong, nonatomic) WKWebView *webView;

@end
