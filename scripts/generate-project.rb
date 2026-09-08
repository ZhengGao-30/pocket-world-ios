#!/usr/bin/env ruby
# Optional development tool; requires the xcodeproj Ruby gem.
# Run from any directory; source and resource membership is rebuilt on each run.
require 'pathname'
require 'xcodeproj'

root = Pathname.new(__dir__).parent.expand_path
project_path = root.join('PocketWorld.xcodeproj')
project = Xcodeproj::Project.new(project_path)
project.root_object.attributes['LastUpgradeCheck'] = '2660'
project.root_object.attributes['LastSwiftUpdateCheck'] = '2660'
project.root_object.attributes['BuildIndependentTargetsInParallel'] = 'YES'
project.root_object.compatibility_version = 'Xcode 14.0'

project.build_configurations.each do |config|
  config.build_settings.merge!(
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
    'SWIFT_VERSION' => '5.0',
    'CLANG_ENABLE_MODULES' => 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES'
  )
  if config.name == 'Debug'
    config.build_settings['ENABLE_TESTABILITY'] = 'YES'
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
  end
end

app = project.new_target(:application, 'PocketWorld', :ios, '17.0', nil, :swift)
app_group = project.main_group.new_group('PocketWorld', 'PocketWorld')
app_sources = root.join('PocketWorld').glob('*.swift').sort
app_sources.each { |path| app.source_build_phase.add_file_reference(app_group.new_file(path.basename.to_s)) }
app_group.new_file('Info.plist')
assets = root.join('PocketWorld/Assets.xcassets')
app.resources_build_phase.add_file_reference(app_group.new_file('Assets.xcassets')) if assets.directory?

app.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.pocketworld.demo',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_MODULE_NAME' => 'PocketWorld',
    'INFOPLIST_FILE' => 'PocketWorld/Info.plist',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'MARKETING_VERSION' => '1.0',
    'CURRENT_PROJECT_VERSION' => '1',
    'TARGETED_DEVICE_FAMILY' => '1',
    'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
    'SUPPORTS_MACCATALYST' => 'NO',
    'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'SWIFT_STRICT_CONCURRENCY' => 'targeted',
    'CODE_SIGN_STYLE' => 'Automatic',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks']
  )
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon' if assets.join('AppIcon.appiconset').directory?
end

tests = project.new_target(:unit_test_bundle, 'PocketWorldTests', :ios, '17.0', nil, :swift)
tests.add_dependency(app)
test_group = project.main_group.new_group('Tests', 'Tests')
test_sources = root.join('Tests').glob('*.swift').sort
test_sources.each { |path| tests.source_build_phase.add_file_reference(test_group.new_file(path.basename.to_s)) }
tests.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.pocketworld.demo.tests',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1',
    'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
    'SWIFT_VERSION' => '5.0',
    'SWIFT_STRICT_CONCURRENCY' => 'targeted',
    'CODE_SIGN_STYLE' => 'Automatic',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/PocketWorld.app/PocketWorld',
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'TEST_TARGET_NAME' => 'PocketWorld',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
  )
end
project.root_object.attributes['TargetAttributes'] = {
  app.uuid => { 'CreatedOnToolsVersion' => '26.6' },
  tests.uuid => { 'CreatedOnToolsVersion' => '26.6', 'TestTargetID' => app.uuid }
}

# Resolve Foundation against the selected SDK instead of the generator's SDK version.
project.files.select { |file| file.path&.end_with?('/Foundation.framework') }.each do |file|
  file.path = 'System/Library/Frameworks/Foundation.framework'
  file.source_tree = 'SDKROOT'
end

project.save
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, tests, launch_target: true)
scheme.test_action.build_configuration = 'Debug'
scheme.launch_action.build_configuration = 'Debug'
scheme.profile_action.build_configuration = 'Release'
scheme.analyze_action.build_configuration = 'Debug'
scheme.archive_action.build_configuration = 'Release'
scheme.save_as(project_path, 'PocketWorld', true)
puts "Generated #{project_path} (#{app_sources.length} app sources, #{test_sources.length} test sources)."
