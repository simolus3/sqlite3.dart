Pod::Spec.new do |s|
    s.name             = 'sqlite3_flutter_libs'
    s.version          = '0.0.1'
    s.summary          = 'A new flutter plugin project.'
    s.description      = <<-DESC
  A new flutter plugin project.
                         DESC
    s.homepage         = 'http://example.com'
    s.license          = { :file => '../LICENSE' }
    s.author           = { 'Your Company' => 'email@example.com' }
    s.source           = { :path => '.' }
    s.source_files = 'sqlite3_flutter_libs/Sources/sqlite3_flutter_libs/**/*.swift'
    s.ios.dependency 'Flutter'
    s.osx.dependency 'FlutterMacOS'
    s.ios.deployment_target = '12.0'
    s.osx.deployment_target = '10.14'
    s.ios.xcconfig = {
      'LIBRARY_SEARCH_PATHS' => '$(TOOLCHAIN_DIR)/usr/lib/swift/$(PLATFORM_NAME)/ $(SDKROOT)/usr/lib/swift',
      'LD_RUNPATH_SEARCH_PATHS' => '/usr/lib/swift',
    }
    s.swift_version = '5.0'

    s.dependency 'sqlite3', '~> 3.47.1'
    s.dependency 'sqlite3/fts5'
    s.dependency 'sqlite3/perf-threadsafe'
    s.dependency 'sqlite3/rtree'
    s.dependency 'sqlite3/dbstatvtab'
end
