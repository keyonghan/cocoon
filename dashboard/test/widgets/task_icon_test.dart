// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dashboard/logic/qualified_task.dart';
import 'package:flutter_dashboard/widgets/task_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../utils/fake_url_launcher.dart';

void main() {
  testWidgets('TaskIcon tooltip shows task name', (WidgetTester tester) async {
    const String taskName = 'tasky task';
    const String expectedLabel = 'tasky task';

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: taskName),
          ),
        ),
      ),
    );

    expect(find.text(expectedLabel), findsNothing);

    final Finder taskIcon = find.byType(TaskIcon);
    final TestGesture gesture = await tester.startGesture(tester.getCenter(taskIcon));
    await tester.pump(kLongPressTimeout);

    expect(find.text(expectedLabel), findsOneWidget);

    await gesture.up();
  });

  testWidgets('TaskIcon tooltip shows task name and dart-internal stage', (WidgetTester tester) async {
    const String taskName = 'Linux engine_release_builder';
    const String expectedLabel = 'Linux engine_release_builder (dart-internal)';

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: taskName),
          ),
        ),
      ),
    );

    expect(find.text(expectedLabel), findsNothing);

    final Finder taskIcon = find.byType(TaskIcon);
    final TestGesture gesture = await tester.startGesture(tester.getCenter(taskIcon));
    await tester.pump(kLongPressTimeout);

    expect(find.text(expectedLabel), findsOneWidget);

    await gesture.up();
  });

  testWidgets('Tapping TaskIcon opens source configuration url', (WidgetTester tester) async {
    final FakeUrlLauncher urlLauncher = FakeUrlLauncher();
    UrlLauncherPlatform.instance = urlLauncher;

    const QualifiedTask luciTask = QualifiedTask(task: 'test');

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: luciTask,
          ),
        ),
      ),
    );

    // Tap to open the source configuration
    await tester.tap(find.byType(TaskIcon));
    await tester.pump();

    expect(urlLauncher.launches, isNotEmpty);
    expect(urlLauncher.launches.single, luciTask.sourceConfigurationUrl);
  });

  testWidgets('TaskIcon shows the right icon for web', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Windows_web test', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect((tester.widget(find.byType(Image)) as Image).image, isInstanceOf<AssetImage>());
    expect(((tester.widget(find.byType(Image)) as Image).image as AssetImage).assetName, 'assets/chromium.png');
  });

  testWidgets('TaskIcon shows the right icon for LUCI windows', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Windows something', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect((tester.widget(find.byType(Image)) as Image).image, isInstanceOf<AssetImage>());
    expect(((tester.widget(find.byType(Image)) as Image).image as AssetImage).assetName, 'assets/windows.png');
  });

  testWidgets('TaskIcon shows the right icon for fuchsia', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Windows_fuchsia something', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect((tester.widget(find.byType(Image)) as Image).image, isInstanceOf<AssetImage>());
    expect(((tester.widget(find.byType(Image)) as Image).image as AssetImage).assetName, 'assets/fuchsia.png');
  });

  testWidgets('TaskIcon shows the right icon for LUCI android', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Windows_android test', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect(tester.widget(find.byType(Icon)) as Icon, isInstanceOf<Icon>());
    expect((tester.widget(find.byType(Icon)) as Icon).icon!.codePoint, const Icon(Icons.android).icon!.codePoint);
  });

  testWidgets('TaskIcon shows the right icon for LUCI mac', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Mac test', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect((tester.widget(find.byType(Image)) as Image).image, isInstanceOf<AssetImage>());
    expect(((tester.widget(find.byType(Image)) as Image).image as AssetImage).assetName, 'assets/apple.png');
  });

  testWidgets('TaskIcon shows the right icon for LUCI mac/iphone', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Mac_ios test', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect(tester.widget(find.byType(Icon)) as Icon, isInstanceOf<Icon>());
    expect((tester.widget(find.byType(Icon)) as Icon).icon!.codePoint, const Icon(Icons.phone_iphone).icon!.codePoint);
  });

  testWidgets('TaskIcon shows the right icon for LUCI linux', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Linux test', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect((tester.widget(find.byType(Image)) as Image).image, isInstanceOf<AssetImage>());
    expect(((tester.widget(find.byType(Image)) as Image).image as AssetImage).assetName, 'assets/linux.png');
  });

  testWidgets('TaskIcon shows the right icon for unknown', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Unknown', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect(tester.widget(find.byType(Icon)) as Icon, isInstanceOf<Icon>());
    expect((tester.widget(find.byType(Icon)) as Icon).icon!.codePoint, const Icon(Icons.help).icon!.codePoint);
  });

  testWidgets('TaskIcon shows the right icon for dart-internal linux', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: TaskIcon(
            qualifiedTask: QualifiedTask(task: 'Linux dart-internal test', pool: 'luci.flutter.prod'),
          ),
        ),
      ),
    );

    expect((tester.widget(find.byType(Image)) as Image).image, isInstanceOf<AssetImage>());
    expect(((tester.widget(find.byType(Image)) as Image).image as AssetImage).assetName, 'assets/linux.png');
  });
}
