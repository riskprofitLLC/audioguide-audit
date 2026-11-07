class AppConstants {
  AppConstants._();


  static const String dbDirectory = 'db';


  static const String dbFileName = 'island_guide.db';


  // База для share-ссылок (deep-link на веб-версию). Прямой
  // адрес продакшена на Layero — без промежуточных редиректов
  // (прежде указывал на 308-редирект Vercel, и судьба ссылки
  // зависела от постороннего сервиса) (P1-5, 7-й проход).
  static const String webAppUrl = 'https://audioguide.layero.app';
}
