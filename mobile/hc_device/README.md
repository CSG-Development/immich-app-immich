# homecloud_frontend

Home Cloud UI ^_^

One project to rule them all:
- Android Manager App
- iOS Manager App
- Webapp for Reset Password & Invite

## Set up

Offical guide: https://docs.flutter.dev/get-started/install

### iOS

Tips:
- Software requirements: macOS Sonoma (version 14) or later, Xcode 16
- You must have a Apple Developper account to download and use [Xcode](https://developer.apple.com/xcode)
- To avoid issues, use a tool to manage your Ruby environment, like [rbenv](https://github.com/rbenv/rbenv)
- Do not install CocoaPods with **sudo** to avoid issues with [fastlane](https://docs.fastlane.tools)

Major steps:
1. Download and install [Xcode](https://developer.apple.com/xcode)
    1. To configure the command-line tools to use the installed version of Xcode, use the following commands.
        > sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
    2. Sign the Xcode license agreement.
        > sudo xcodebuild -license
2. Use [rbenv](https://github.com/rbenv/rbenv) to install Ruby 3.x
3. Download and install [CocoaPods](https://guides.cocoapods.org/using/getting-started.html#getting-started)
    > gem install cocoapods
4. Download and install [Flutter SDK](https://docs.flutter.dev/get-started/install/macos/mobile-ios#install-the-flutter-sdk)
5. Add Flutter to your PATH
    > export PATH=$HOME/development/flutter/bin:$PATH


## CI

Official guide: https://docs.flutter.dev/deployment/cd

### iOS

Tips:
- You must have a Apple Developper account with the **App Manager** role to create, sign and deploy Apps on TestFlight
- Fastlane need and **app-specific password** to work 
    - Create one on your [Apple Account](http://appleid.apple.com), then go to the security section and use the Generate Password
    - Set the FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD env variable in your bash or in GitLab > *my_project* > Settings > CI/CD > Variables
- Create a GitLab Runner **Shell** executor on the machine host
- Copy all content of your .zshrc and .zshenv files to .bash_profile to have the same environment in the Runner and locally

Major steps:
1. Set up you host locally, and make sure that your project builds via:
    > flutter build ipa
3. Create an environment variable named **FLUTTER_ROOT**, and set it to the root directory of your Flutter SDK. (This is required for the scripts that deploy for iOS.)
4. Ensure Bundler is available using:
    > gem install bundler
5. To test CI, in [project]/ios run :
    > bundle install
    > 
    > bundle exec fastlane beta

## API

All yaml files must be saved in folder **\swaggers**

Then the SwaggerGenerator will generate the API files for you by running:
```shell
dart run build_runner build
```

## Next

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
