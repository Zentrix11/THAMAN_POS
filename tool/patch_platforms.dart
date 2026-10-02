import 'dart:convert';
import 'dart:io';

const appName = 'THAMAN POS';
const bundleId = 'com.zentrix.thamanpos';

void main() {
  _patchWindows();
  _patchAndroid();
  _patchIos();
  _patchMacos();
  _patchWeb();
  stdout.writeln('THAMAN POS platform branding/configuration patched.');
}

void _patchWindows() {
  final main = File('windows/runner/main.cpp');
  if (main.existsSync()) {
    var text = main.readAsStringSync();
    text = text.replaceAll('L"thaman_pos"', 'L"$appName"');
    text = text.replaceAll('L"Thaman Pos"', 'L"$appName"');
    main.writeAsStringSync(text);
  }

  final sourceIcon = File('assets/app_icon_windows.ico');
  final targetIcon = File('windows/runner/resources/app_icon.ico');
  if (sourceIcon.existsSync() && targetIcon.parent.existsSync()) {
    targetIcon.writeAsBytesSync(sourceIcon.readAsBytesSync(), flush: true);
  }
}

void _patchAndroid() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var text = manifest.readAsStringSync();
    text = text.replaceFirst(
      RegExp(r'android:label="[^"]*"'),
      'android:label="$appName"',
    );
    manifest.writeAsStringSync(text);
  }

  for (final path in [
    'android/app/build.gradle.kts',
    'android/app/build.gradle',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    text = text
        .replaceAll('com.zentrix.thaman_pos', bundleId)
        .replaceAll('com.zentrix.thamanPos', bundleId);
    if (path.endsWith('.kts')) {
      if (!text.contains('id("org.jetbrains.kotlin.android")')) {
        text = text.replaceFirst(
          'id("com.android.application")',
          'id("com.android.application")\n    id("org.jetbrains.kotlin.android")',
        );
      }
      text = text.replaceAll(
        'ndkVersion = flutter.ndkVersion',
        'ndkVersion = "28.2.13676358"',
      );
    }
    file.writeAsStringSync(text);
  }

  final gradleProperties = File('android/gradle.properties');
  if (gradleProperties.existsSync()) {
    var text = gradleProperties.readAsStringSync();
    if (!text.contains('kotlin.incremental=false')) {
      text += '\nkotlin.incremental=false\n';
    }
    if (!text.contains('kotlin.incremental.useClasspathSnapshot=false')) {
      text += 'kotlin.incremental.useClasspathSnapshot=false\n';
    }
    gradleProperties.writeAsStringSync(text);
  }

  final proguard = File('android/app/proguard-rules.pro');
  if (!proguard.existsSync()) {
    proguard.createSync(recursive: true);
    proguard.writeAsStringSync('# THAMAN POS - custom ProGuard rules\n');
  }

  final wrapper = File('android/gradle/wrapper/gradle-wrapper.properties');
  if (wrapper.existsSync()) {
    var text = wrapper.readAsStringSync();
    text = text.replaceFirst(
      RegExp(r'distributionUrl=.*'),
      r'distributionUrl=https\://services.gradle.org/distributions/gradle-9.3.1-bin.zip',
    );
    wrapper.writeAsStringSync(text);
  }
}

void _patchIos() {
  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync()) {
    var text = plist.readAsStringSync();
    text = _replacePlistString(text, 'CFBundleDisplayName', appName);
    text = _replacePlistString(text, 'CFBundleName', 'THAMAN POS');
    plist.writeAsStringSync(text);
  }

  final podfile = File('ios/Podfile');
  if (podfile.existsSync()) {
    var text = podfile.readAsStringSync();
    if (!text.contains('use_frameworks!')) {
      text = text.replaceFirst(
        "target 'Runner' do\n",
        "target 'Runner' do\n  use_frameworks!\n",
      );
      podfile.writeAsStringSync(text);
    }
  }

  _replaceGeneratedBundleIds('ios/Runner.xcodeproj/project.pbxproj');
}

void _patchMacos() {
  final config = File('macos/Runner/Configs/AppInfo.xcconfig');
  if (config.existsSync()) {
    var text = config.readAsStringSync();
    text = text.replaceFirst(
      RegExp(r'PRODUCT_NAME\s*=.*'),
      'PRODUCT_NAME = $appName',
    );
    config.writeAsStringSync(text);
  }

  for (final path in [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    text = _ensureEntitlement(text, 'com.apple.security.print');
    // Needed by the preferred searchable Arabic PDF font loader. The app also
    // has an offline raster fallback, but enabling client networking keeps the
    // best-quality vector path available in sandboxed macOS builds.
    text = _ensureEntitlement(text, 'com.apple.security.network.client');
    file.writeAsStringSync(text);
  }

  _replaceGeneratedBundleIds('macos/Runner.xcodeproj/project.pbxproj');
}

void _patchWeb() {
  final index = File('web/index.html');
  if (index.existsSync()) {
    var text = index.readAsStringSync();
    text = text.replaceFirst(
      RegExp(r'<title>.*?</title>', dotAll: true),
      '<title>$appName</title>',
    );
    index.writeAsStringSync(text);
  }

  final manifest = File('web/manifest.json');
  if (manifest.existsSync()) {
    try {
      final data = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      data['name'] = appName;
      data['short_name'] = 'THAMAN';
      data['description'] = 'THAMAN POS - bilingual retail point of sale and management';
      manifest.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    } catch (_) {
      // Keep a hand-edited manifest unchanged if it is not valid JSON.
    }
  }
}

String _replacePlistString(String input, String key, String value) {
  final pattern = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*<string>.*?</string>',
    dotAll: true,
  );
  return input.replaceFirst(pattern, '<key>$key</key>\n\t<string>$value</string>');
}

String _ensureEntitlement(String input, String key) {
  if (input.contains('<key>$key</key>')) return input;
  return input.replaceFirst(
    '</dict>',
    '\t<key>$key</key>\n\t<true/>\n</dict>',
  );
}

void _replaceGeneratedBundleIds(String path) {
  final file = File(path);
  if (!file.existsSync()) return;
  var text = file.readAsStringSync();
  text = text
      .replaceAll('com.zentrix.thaman_pos', bundleId)
      .replaceAll('com.zentrix.thamanPos', bundleId);
  file.writeAsStringSync(text);
}
