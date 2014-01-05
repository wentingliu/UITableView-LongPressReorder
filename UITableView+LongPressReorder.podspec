Pod::Spec.new do |s|
  s.name         = "UITableView+LongPressReorder"
  s.version      = "0.1.0"
  s.summary      = "Easy Long Press Reordering for UITableView."
  s.homepage     = "https://github.com/wentingliu/UITableView-LongPressReorder"
  s.license      = 'MIT'
  s.author       = { "Wenting Liu" => "wentingliu@live.com" }
  s.source       = { :git => "https://github.com/wentingliu/UITableView-LongPressReorder.git", :tag => "0.1.0" }
  s.platform     = :ios, '5.0'
  s.source_files = 'UITableView+LongPressReorder/**/*.{h,m}'
  s.frameworks   = 'UIKit', 'CoreGraphics', 'QuartzCore'
  s.requires_arc = true
end