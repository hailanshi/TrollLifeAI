//
//  AppDelegate.h
//  TrollLifeApp
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

+ (void)installCrashHandlers;
+ (void)appendCrashLog:(NSString *)text;

@end
