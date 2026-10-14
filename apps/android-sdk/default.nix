{ pkgs, ... }:
let
  android = (pkgs.androidenv.override { licenseAccepted = true; }).composeAndroidPackages { };
  sdkRoot = "${android.androidsdk}/libexec/android-sdk";
in
{
  home.packages = [ android.androidsdk ];
  home.sessionVariables = {
    ANDROID_HOME = sdkRoot;
    ANDROID_SDK_ROOT = sdkRoot;
  };
}
