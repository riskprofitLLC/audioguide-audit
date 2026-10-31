// B2 (11-й проход): единый баннер-уведомление NoticeBanner —
// три варианта окраски, футер, компактный режим для карты.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/app/theme.dart';
import 'package:island_guide/core/widgets/notice_banner.dart';

void main() {
  Future<void> pumpBanner(
    WidgetTester tester,
    NoticeBanner banner,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: banner,
          ),
        ),
      ),
    );
  }

  testWidgets('варианты info/warning/error несут свои цвета и тексты',
      (tester) async {
    await pumpBanner(
      tester,
      const NoticeBanner(
        variant: NoticeBannerVariant.info,
        icon: LucideIcons.construction,
        title: 'В разработке',
        message: 'Остров находится в разработке',
      ),
    );

    expect(find.text('В разработке'), findsOneWidget);
    expect(find.byIcon(LucideIcons.construction), findsOneWidget);

    await pumpBanner(
      tester,
      const NoticeBanner(
        variant: NoticeBannerVariant.warning,
        icon: LucideIcons.ban,
        title: 'Пешие маршруты запрещены',
        message: 'Осмотр только с воды.',
      ),
    );

    expect(find.text('Пешие маршруты запрещены'), findsOneWidget);

    // Глиф предупреждения — жжёный терракотовый на тёплом тинте.
    final icon = tester.widget<Icon>(find.byIcon(LucideIcons.ban));

    expect(icon.color, AppColors.alertInk);

    await pumpBanner(
      tester,
      const NoticeBanner(
        variant: NoticeBannerVariant.error,
        icon: LucideIcons.alertTriangle,
        title: 'Ошибка инициализации',
        message: 'Не удалось открыть базу данных контента.',
        footer: Text('Повторить'),
      ),
    );

    expect(find.text('Ошибка инициализации'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    // Error-вариант живёт на semantic-плашке ошибки.
    final errorIcon = tester.widget<Icon>(
      find.byIcon(LucideIcons.alertTriangle),
    );

    final context = tester.element(find.byIcon(LucideIcons.alertTriangle));

    expect(errorIcon.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('компактный режим — меньший квадрат глифа', (tester) async {
    await pumpBanner(
      tester,
      const NoticeBanner(
        variant: NoticeBannerVariant.warning,
        icon: LucideIcons.ban,
        title: 'Пешие маршруты запрещены',
        message: 'Осмотр только с воды.',
        compact: true,
        floating: true,
      ),
    );

    // Квадрат глифа компактного баннера — 28×28 (обычный — 32).
    final square = tester.widget<Container>(
      find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ).first,
    );

    expect(square.constraints, BoxConstraints.tight(const Size(28, 28)));
  });
}
