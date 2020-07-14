#import "Sqlite3FlutterLibsPlugin.h"
#if __has_include(<sqlite3_flutter_libs/sqlite3_flutter_libs-Swift.h>)
#import <sqlite3_flutter_libs/sqlite3_flutter_libs-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "sqlite3_flutter_libs-Swift.h"
#endif

@implementation Sqlite3FlutterLibsPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftSqlite3FlutterLibsPlugin registerWithRegistrar:registrar];
}
@end
