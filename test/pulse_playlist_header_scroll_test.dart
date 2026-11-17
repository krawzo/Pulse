import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/ui/pulse_collection_hero.dart';

void main() {
  testWidgets('desktop playlist header gives way to compact controls on scroll',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: PulseCollectionHero(
          title: 'Adoração',
          type: 'Playlist',
          metadata: 'Navidrome • 47 faixas',
          tracks: const [],
          onBack: () {},
          onPlay: () {},
          backTooltip: 'Voltar',
          playTooltip: 'Reproduzir',
          collapsibleHeader: true,
          content: ListView.builder(
            itemCount: 47,
            itemBuilder: (context, index) =>
                SizedBox(height: 64, child: Text('Faixa $index')),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    AnimatedOpacity compactTitle() => tester.widget<AnimatedOpacity>(
          find.byType(AnimatedOpacity).first,
        );
    expect(compactTitle().opacity, 0);

    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();

    expect(compactTitle().opacity, 1);
    expect(find.text('Faixa 0'), findsWidgets);
  });
}
