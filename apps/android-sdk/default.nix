{ pkgs, homeDirectory, ... }:
let
  android = (pkgs.androidenv.override { licenseAccepted = true; }).composeAndroidPackages { };
  sdkLink = if pkgs.stdenv.isDarwin then "Library/Android/sdk" else "Android/Sdk";
  sdkRoot = "${homeDirectory}/${sdkLink}";
in
{
  home.packages = [ android.androidsdk ];
  home.file.${sdkLink}.source = "${android.androidsdk}/libexec/android-sdk";
  home.sessionVariables = {
    ANDROID_HOME = sdkRoot;
    ANDROID_SDK_ROOT = sdkRoot;
  };
}
