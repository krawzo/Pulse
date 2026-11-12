/// Release builds supply these values from pubspec.yaml.
/// Defaults cover direct development runs of this source revision.
const pulseAppVersion = String.fromEnvironment(
  'PULSE_BUILD_NAME',
  defaultValue: '0.3.17',
);
const pulseAppBuildNumber = String.fromEnvironment(
  'PULSE_BUILD_NUMBER',
  defaultValue: '36',
);
