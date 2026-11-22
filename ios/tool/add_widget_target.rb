# يضيف هدف الويدجت (WidgetKit) إلى مشروع Xcode — يُشغَّل في CI لبناء Favorites2-widget.ipa فقط
# (النسخة العادية Favorites2.ipa تُبنى قبله بلا ويدجت، كي لا يستهلك AltStore معرّف تطبيق إضافيًا لمن لا يريده).
# آمن للتكرار: لا يفعل شيئًا إن كان الهدف موجودًا.
require 'xcodeproj'

proj_path = File.expand_path('../Runner.xcodeproj', __dir__)
proj = Xcodeproj::Project.open(proj_path)
if proj.targets.any? { |t| t.name == 'FavWidget' }
  puts 'FavWidget موجود مسبقًا'
  exit 0
end

runner = proj.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')
build_name = ENV['BUILD_NAME'] || '1.0.0'
build_number = ENV['BUILD_NUMBER'] || '1'

ext = proj.new_target(:app_extension, 'FavWidget', :ios, '17.0', nil, :swift)
group = proj.main_group.new_group('FavWidget', 'FavWidget')
src = group.new_reference('FavWidget.swift')
group.new_reference('Info.plist')
group.new_reference('FavWidget.entitlements')
ext.add_file_references([src])
%w[WidgetKit SwiftUI].each do |fw|
  ref = proj.frameworks_group.new_reference("System/Library/Frameworks/#{fw}.framework", :sdk_root)
  ext.frameworks_build_phase.add_file_reference(ref, true)
end

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.favlib.favorites2.FavWidget'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'FavWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'FavWidget/FavWidget.entitlements'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['MARKETING_VERSION'] = build_name
  s['CURRENT_PROJECT_VERSION'] = build_number
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = ''
  s['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = ''
end

# تضمين الامتداد داخل التطبيق (PlugIns) — قبل مراحل السكربت لتجنب دورة البناء المعروفة مع Flutter
runner.add_dependency(ext)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.dst_subfolder_spec = '13'
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
first_script = runner.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) && p.name.to_s =~ /Thin Binary/i }
if first_script
  runner.build_phases.delete(embed)
  runner.build_phases.insert(first_script, embed)
end

# التطبيق يحتاج مجموعة التطبيق المشتركة ليكتب بيانات الويدجت
runner.build_configurations.each { |c| c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/RunnerWidget.entitlements' }

proj.save
puts "أُضيف FavWidget (#{build_name}+#{build_number})"
