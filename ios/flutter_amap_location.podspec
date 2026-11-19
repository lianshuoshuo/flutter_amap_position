Pod::Spec.new do |s|
  s.name             = 'flutter_amap_location'
  s.version          = '0.0.1'
  s.summary          = 'Foreground positioning via the native AMap Location SDK.'
  s.homepage         = 'https://github.com/lianshuoshuo/flutter_amap_location'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'flutter_amap_position contributors'
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_amap_location/Sources/flutter_amap_location/**/*.swift'
  s.static_framework = true
  s.dependency 'Flutter'
  s.dependency 'AMapLocation', '2.12.2'
  s.dependency 'AMapFoundation', '1.9.1'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
