# Uncomment the next line to define a global platform for your project
platform :ios, '12.0'
install! 'cocoapods', :deterministic_uuids => false

target 'MaplySample' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for MaplySample
pod 'WhirlyGlobe', :git => 'https://github.com/mousebird/WhirlyGlobe.git', :branch => 'develop'

end

post_install do |installer|
    installer.generated_projects.each do |project|
          project.targets.each do |target|
              target.build_configurations.each do |config|
                  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
               end
          end
   end
end
