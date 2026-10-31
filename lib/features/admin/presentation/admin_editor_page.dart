/// Экран редактирования текста точки: rich-редактор «как в Word»
/// (замечание владельца 28.10): в поле ЧИСТЫЙ текст без звёздочек,
/// жирный/курсив — отдельные диапазоны стилей (rich_text_model),
/// кнопки и Ctrl+B/I переключают стиль на выделении, в markdown
/// разметка собирается только при сохранении/просмотре. Слева —
/// оглавление всех текстов с поиском, справа — предпросмотр и
/// отправка правки на GitHub.
///
/// Режимы разделены по смыслу: «Текст» — правка ТОЛЬКО статьи
/// (блок :::quiz вырезан из поля и хранится отдельно в _quizRaw),
/// «Квиз» — правка ТОЛЬКО квиза, «Просмотр» — итоговая страница
/// читателя: статья И квиз вместе.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme.dart';
import '../../../core/widgets.dart';
import '../../content/models/region_catalog.dart';
import '../../content/presentation/widgets/quiz_card.dart';
import '../../content/providers/content_providers.dart';
import '../../content/services/markdown_blocks.dart';
import '../../poi/utils/poi_sort.dart';
import '../../settings/services/app_settings.dart';
import '../providers/admin_providers.dart';
import '../services/admin_blocks.dart';
import '../services/admin_edit_payload.dart';
import '../services/admin_text_paths.dart';
import '../services/github_content_service.dart';
import '../services/rich_text_model.dart';
import 'admin_crud_dialogs.dart';
import 'admin_outline.dart';

/// Горячие клавиши поля: Ctrl+B / Ctrl+I — разметка, Ctrl+S /
/// Cmd+S — сохранить, Ctrl+Z — отмена, Ctrl+Shift+Z / Ctrl+Y — возврат.
final Map<ShortcutActivator, Intent> _formatShortcuts = {
  const SingleActivator(LogicalKeyboardKey.keyB, control: true):
      const _StyleIntent(bold: true),
  const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
      const _StyleIntent(bold: true),
  const SingleActivator(LogicalKeyboardKey.keyI, control: true):
      const _StyleIntent(bold: false, red: true),
  const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
      const _StyleIntent(bold: false, red: true),
  const SingleActivator(LogicalKeyboardKey.keyS, control: true):
      const _SaveIntent(),
  const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
      const _SaveIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
      const _UndoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
      const _UndoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
      const _RedoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
      const _RedoIntent(),
  const SingleActivator(LogicalKeyboardKey.keyY, control: true):
      const _RedoIntent(),
};

/// Intent отмены правки (Ctrl+Z / Cmd+Z).
class _UndoIntent extends Intent {
  const _UndoIntent();
}

/// Intent возврата правки (Ctrl+Shift+Z / Ctrl+Y / Cmd+Shift+Z).
class _RedoIntent extends Intent {
  const _RedoIntent();
}

/// Intent сохранения правки (Ctrl+S / Cmd+S).
class _SaveIntent extends Intent {
  const _SaveIntent();
}

/// Intent переключения стиля выделения (Ctrl+B — жирный,
/// Ctrl+I — красное выделение; rich-редактор, маркеров в поле нет).
class _StyleIntent extends Intent {

  const _StyleIntent({required this.bold, this.red = false});

  final bool bold;

  final bool red;
}

enum _EditorMode { text, quiz, preview, diff }

class AdminEditorPage extends ConsumerStatefulWidget {

  const AdminEditorPage({
    super.key,
    required this.islandId,
    required this.poiId,
  });

  final String islandId;

  final String poiId;

  @override
  ConsumerState<AdminEditorPage> createState() => _AdminEditorPageState();
}

class _AdminEditorPageState extends ConsumerState<AdminEditorPage> {

  final _controller = RichEditingController();

  final _titleController = TextEditingController();

  _EditorMode _mode = _EditorMode.text;

  // --- поля квиза (режим «Квиз») ---
  // Единственный источник правды — сырой текст в _controller;
  // контроллеры квиза пересобираются из него при входе в режим.

  final _quizQuestion = TextEditingController();

  final _quizNote = TextEditingController();

  final _quizOptions = <TextEditingController>[];

  int _correctIndex = 0;

  // Защита от рекурсии: изменение квиза перезаписывает
  // _controller, но не должно снова перестраивать контроллеры.
  bool _quizSyncing = false;

  /// Сырой блок квиза (`:::quiz … :::`), ВЫРЕЗАННЫЙ из поля текста:
  /// «Текст» правит статью, «Квиз» — квиз; в файл они едут вместе.
  String? _quizRaw;

  String? _poiJsonRaw;

  String? _textPath;

  String? _poiJsonPath;

  bool _fromEdits = false;

  bool _loading = true;

  String? _error;

  bool _saving = false;

  /// Снимок после загрузки: грязный ли редактор (пункт 3, А2).
  String? _savedText;

  String? _savedTitle;

  /// Снимок квиза после загрузки (для dirty-флага).
  String? _savedQuiz;

  /// Сохранённые стили статьи (жирный/курсив по чистому тексту).
  List<RichSpan> _savedSpans = const [];

  /// Правки текста/квиза перезаписывают _controller — тоже грязь.
  bool _dirty = false;

  /// Из загруженной версии восстановлен черновик (баннер об этом).
  bool _draftRestored = false;

  @override
  void initState() {

    super.initState();

    _controller.addListener(_markDirty);

    // Запоминаем последнее НЕсхлопнутое выделение: при тапе по кнопке
    // стиля фокус уходит из поля и selection схлопывается — тогда кнопка
    // должна применяться к запомненному выделению, а не к курсору.
    _controller.addListener(_rememberSelection);

    _titleController.addListener(_markDirty);

    _load();
  }

  @override
  void didUpdateWidget(covariant AdminEditorPage oldWidget) {

    super.didUpdateWidget(oldWidget);

    // Страховка поверх ValueKey в AdminGate (пункт 2 замечаний
    // Sonnet): смена точки без пересоздания State всё равно
    // перезагружает данные и снимает черновик прежней точки.
    if (oldWidget.islandId != widget.islandId ||
        oldWidget.poiId != widget.poiId) {
      _load();
    }
  }

  /// Ключ черновика точки в AppSettings.
  String get _draftKey => 'admin_draft:${widget.islandId}/${widget.poiId}';

  /// Черновик несохранённых правок: пишется при каждой правке,
  /// снимается при успешном сохранении и при «Отбросить».
  void _saveDraft() {

    if (_loading) {
      return;
    }

    AppSettings().write(_draftKey, _combinedText());
  }

  /// Последнее выделение пользователя (не схлопнутое).
  TextSelection? _lastSelection;

  void _rememberSelection() {
    final sel = _controller.selection;

    if (!sel.isValid) {
      return;
    }

    if (sel.end > sel.start) {
      // Новое выделение — запоминаем.
      _lastSelection = sel;
    }
  }

  void _markDirty() {

    if (_loading) {
      return;
    }

    // Черновик пишется при КАЖДОЙ правке, а не только при первой:
    // первое уведомление контроллера может прийти до смены текста.
    _saveDraft();

    if (_dirty) {
      return;
    }

    setState(() {
      _dirty = true;
    });
  }

  /// Есть ли несохранённые правки против загруженной версии.
  bool get _isDirty =>
      _savedText != null &&
      (_controller.text != _savedText ||
          _titleController.text != _savedTitle ||
          _quizRaw != _savedQuiz ||
          !_spansEqual(_controller.spans, _savedSpans));

  /// Полный текст файла СОВМЕСТНО с квизом: так файл лежит в
  /// репо и так его видит читатель (просмотр/дифф/сохранение).
  String _combinedText() => applyQuizToText(
        _controller.markdown,
        _quizRaw != null ? parseQuizBlock(_quizRaw!) : null,
      );

  /// Диалог ухода с несохранёнными правками (пункт 3, А2):
  /// «Сохранить / Отбросить / Остаться».
  Future<void> _confirmDiscard() async {

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Несохранённые изменения'),
        content: const Text(
          'Текст правлен, но не сохранён. Сохранить перед уходом?',
        ),
        actions: [
          TextButton(
            key: const Key('admin-discard'),
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Отбросить'),
          ),
          TextButton(
            key: const Key('admin-stay'),
            onPressed: () => Navigator.of(context).pop('stay'),
            child: const Text('Остаться'),
          ),
          FilledButton(
            key: const Key('admin-save-and-pop'),
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (!mounted || choice == 'stay' || choice == null) {
      return;
    }

    if (choice == 'save') {
      // Поп только при УСПЕШНОМ сохранении: неудачный коммит не
      // должен молча терять правки (аудит прохода).
      final saved = await _save();

      if (!saved || !mounted) {
        return;
      }
    } else {
      // «Отбросить» — черновик тоже уходит.
      AppSettings().remove(_draftKey);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {

    _controller.dispose();

    _titleController.dispose();

    _quizQuestion.dispose();

    _quizNote.dispose();

    for (final c in _quizOptions) {
      c.dispose();
    }

    super.dispose();
  }

  void _setMode(_EditorMode mode) {

    if (mode == _EditorMode.quiz) {
      _enterQuizMode();
    }

    setState(() {
      _mode = mode;
    });
  }

  /// Пересобирает контроллеры квиза из сырого блока квиза
  /// (поле «Текст» его не содержит — квиз правится отдельно).
  void _enterQuizMode() {

    for (final c in _quizOptions) {
      c.dispose();
    }

    _quizOptions.clear();

    final quiz = _quizRaw != null ? parseQuizBlock(_quizRaw!) : null;

    _quizQuestion.text = quiz?.question ?? '';

    _quizNote.text = quiz?.note ?? '';

    _correctIndex = -1;

    if (quiz == null) {
      _quizOptions.add(TextEditingController());
      _quizOptions.add(TextEditingController());
      _correctIndex = 0;
      return;
    }

    for (var i = 0; i < quiz.options.length; i++) {
      _quizOptions.add(TextEditingController(text: quiz.options[i].text));
      if (quiz.options[i].correct) {
        _correctIndex = i;
      }
    }

    // Минимум два поля вариантов — пустые добавляются под новый ввод.
    while (_quizOptions.length < 2) {
      _quizOptions.add(TextEditingController());
    }

    if (_correctIndex < 0) {
      _correctIndex = 0;
    }
  }

  /// Строит AdminQuiz из полей и обновляет ОТДЕЛЬНЫЙ блок квиза:
  /// поле «Текст» квизом не занимается (замечание владельца).
  void _applyQuiz() {

    if (_quizSyncing) {
      return;
    }

    _quizSyncing = true;

    try {
      final quiz = AdminQuiz(
        question: _quizQuestion.text.trim(),
        options: [
          for (var i = 0; i < _quizOptions.length; i++)
            AdminQuizOption(
              text: _quizOptions[i].text.trim(),
              correct: i == _correctIndex,
            ),
        ],
        note: _quizNote.text.trim().isEmpty ? null : _quizNote.text.trim(),
      );

      // Незаполненный квиз — квиза нет (удаляется при сохранении).
      _quizRaw = isQuizFilled(quiz) ? serializeQuiz(quiz) : null;

      if (!_loading) {
        setState(() {});

        _saveDraft();
      }
    } finally {
      _quizSyncing = false;
    }
  }

  Future<void> _load() async {

    setState(() {
      _loading = true;
      _error = null;
    });

    try {

      final service = ref.read(githubContentServiceProvider);

      final pois = await ref.read(poisFamily(widget.islandId).future);

      final folderNumber = folderNumberFor(widget.poiId, pois);

      final textPath = await resolveTextAssetPath(
        locationAssetBase(widget.islandId),
        folderNumber,
      );

      if (textPath == null) {
        throw const GitHubException('Текстовый файл точки не найден в бандле');
      }

      _textPath = textPath;

      _poiJsonPath = '${locationAssetBase(widget.islandId)}/poi.json';

      // Правка, если есть, перекрывает опубликованную версию.
      final text = await service.fetchFile(_textPath!);

      final poiJson = await service.fetchFile(_poiJsonPath!);

      final textRaw = text?.content ??
          await rootBundle.loadString(_textPath!);

      _fromEdits = text?.fromEditsBranch ?? false;

      _poiJsonRaw = poiJson?.content ??
          await rootBundle.loadString(_poiJsonPath!);

      // Черновик: несохранённые правки этой точки восстанавливаются
      // поверх загруженной версии; редактор сразу помечается грязным.
      final draft = AppSettings().read(_draftKey);

      _draftRestored = draft != null && draft != textRaw;

      final effectiveText = _draftRestored ? draft! : textRaw;

      // Разделение режимов (замечание владельца): в поле «Текст» —
      // ТОЛЬКО статья; блок квиза живёт отдельно в _quizRaw.
      final blocks = splitAdminBlocks(effectiveText);

      final quizBlock = blocks
          .where((b) => b.type == AdminBlockType.quiz)
          .firstOrNull;

      _quizRaw = quizBlock?.text;

      // Rich-редактор: разметка уходит в диапазоны, в поле —
      // чистый текст (звёздочек не видно, правка как в Word).
      // Новый документ — сбрасываем запомненное выделение: его позиции
      // относятся к прежнему тексту и при тапе по кнопке стиля без
      // свежего выделения стиль «улетал» в конец нового текста.
      _lastSelection = null;

      _controller.setMarkdown(
        joinAdminBlocks(
          blocks.where((b) => b.type != AdminBlockType.quiz).toList(),
        ),
      );

      _titleController.text =
          poiTitleFromJson(_poiJsonRaw!, widget.poiId) ?? '';

      // Снимок для dirty-флага — из ЗАГРУЖЕННОЙ версии (без
      // черновика): восстановленный черновик должен считаться
      // несохранённой правкой. До этого — загрузка, не правка.
      final loadedBlocks = splitAdminBlocks(textRaw);

      final loadedDoc = parseRich(
        joinAdminBlocks(
          loadedBlocks.where((b) => b.type != AdminBlockType.quiz).toList(),
        ),
      );

      _savedText = loadedDoc.plain;

      _savedSpans = loadedDoc.spans;

      _savedTitle = _titleController.text;

      _savedQuiz = loadedBlocks
          .where((b) => b.type == AdminBlockType.quiz)
          .firstOrNull
          ?.text;

      _dirty = false;

      // Память «с чего продолжить»: /admin без параметров
      // откроет эту точку в следующий раз (успешная загрузка —
      // осознанное условие: битая точка не запоминается).
      ref
          .read(adminLastPoiProvider.notifier)
          .remember(widget.islandId, widget.poiId);

      if (mounted) {
        setState(() {
          _loading = false;
        });

        if (_draftRestored) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              showAppSnackBar(
                context,
                'Восстановлен несохранённый черновик этой точки',
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  // --- правки ---

  /// Переключает стиль на выделении (кнопки и Ctrl+B/I).
  /// Берём текущее непустое выделение; если при тапе по кнопке оно уже
  /// схлопнулось — последнее запомненное (_lastSelection).
  void _applyStyle({required bool bold, bool red = false}) {

    final current = _controller.selection;

    final raw = (current.isValid && current.end > current.start)
        ? current
        : (_lastSelection ?? current);

    // Кламп к длине ТЕКУЩЕГО текста: _lastSelection мог пережить смену
    // документа (другая точка/режим), и тогда стиль применился бы к
    // чужим позициям (в конец текста) либо падал с RangeError.
    final len = _controller.text.length;

    final sel = TextSelection(
      baseOffset: raw.start.clamp(0, len),
      extentOffset: raw.end.clamp(0, len),
    );

    if (sel.end <= sel.start) {
      return;
    }

    // Стиль меняет только spans — снимок в историю вручную.
    _controller.pushHistory();

    setState(() {
      _controller.spans = toggleStyle(
        _controller.spans,
        _controller.text,
        sel.start,
        sel.end,
        bold: bold,
        red: red,
      );
      // Возвращаем выделение в поле — иначе следующий тап по кнопке
      // применится к схлопнутому курсору.
      _controller.selection = sel;
    });
  }

  /// Сброс всего оформления: текст остаётся, все диапазоны
  /// (жирный/красный/курсив) снимаются — «чистый» текст.
  void _clearStyles() {
    if (_controller.spans.isEmpty) {
      return;
    }

    _controller.pushHistory();

    setState(() {
      _controller.spans = const [];
      _lastSelection = null;
    });
  }

  /// Отмена последней правки (кнопка / Ctrl+Z).
  void _undo() {
    if (!_controller.canUndo) {
      return;
    }

    setState(() {
      _controller.undo();
      // Undo меняет текст и selection программно: запомненное
      // выделение (_lastSelection) могло относиться к прежней длине
      // текста — без сброса стиль при следующем тапе улетал бы на
      // чужие позиции.
      _lastSelection = null;
    });
  }

  /// Возврат отменённой правки (кнопка / Ctrl+Shift+Z, Ctrl+Y).
  void _redo() {
    if (!_controller.canRedo) {
      return;
    }

    setState(() {
      _controller.redo();

      _lastSelection = null;
    });
  }

  bool _spansEqual(List<RichSpan> a, List<RichSpan> b) {
    if (a.length != b.length) {
      return false;
    }

    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start ||
          a[i].end != b[i].end ||
          a[i].bold != b[i].bold ||
          a[i].italic != b[i].italic ||
          a[i].red != b[i].red) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _save() async {

    // Полный текст файла = статья (rich-текст с собранной
    // разметкой) + квиз (из формы «Квиз») — в репо они едут
    // одним файлом, как у читателя.
    final newText = _combinedText();

    final description = shortDescriptionFromMarkdown(newText);

    final newTitle = _titleController.text.trim();

    var newPoiJson = updatePoiJsonDescription(
      _poiJsonRaw!,
      widget.poiId,
      description,
    );

    if (newTitle.isNotEmpty) {
      newPoiJson = updatePoiJsonTitle(newPoiJson, widget.poiId, newTitle);
    }

    final titleChanged = newTitle !=
        (poiTitleFromJson(_poiJsonRaw!, widget.poiId) ?? '');

    setState(() {
      _saving = true;
    });

    try {

      // Очередь правок имён (манифесты) сохраняется тем же коммитом.
      final pending = ref.read(pendingRenamesProvider);

      final files = [
        GhCommitFile(path: _textPath!, content: newText),
        GhCommitFile(path: _poiJsonPath!, content: newPoiJson),
        ...pending.entries.map(
          (e) => GhCommitFile(path: e.key, content: e.value),
        ),
      ];

      await ref.read(githubContentServiceProvider).commitFiles(
        files,
        'Правка ${titleChanged ? 'названия и текста ' : 'текста '}${widget.poiId} (${widget.islandId}) '
        'из админ-панели',
      );

      if (mounted) {
        showAppSnackBar(
          context,
          'Правка сохранена — будет опубликована после проверки',
        );
      }

      ref.read(pendingRenamesProvider.notifier).clear();

      // Сохранено — черновик больше не нужен.
      AppSettings().remove(_draftKey);

      _draftRestored = false;

      // Успех — новая загруженная версия, правок больше нет.
      _savedText = _controller.text;

      _savedSpans = _controller.spans;

      _savedTitle = newTitle;

      _savedQuiz = _quizRaw;

      _dirty = false;

      if (mounted) {
        setState(() {
          _fromEdits = true;
        });
      }
    } catch (e) {

      if (mounted) {
        showAppSnackBar(context, 'Не удалось сохранить: $e');
      }

      return false;
    } finally {

      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: StatePlaceholder(
            icon: LucideIcons.cloudOff,
            title: 'Ошибка загрузки',
            description: _error,
          ),
        ),
      );
    }

    final poi = ref
        .watch(poisFamily(widget.islandId))
        .value
        ?.where((p) => p.id == widget.poiId)
        .firstOrNull;

    final width = MediaQuery.sizeOf(context).width;

    final wide = width >= 900;

    // На узких экранах сегменты без текста — только иконки,
    // иначе три подписи не влезают в AppBar рядом с заголовком.
    final segmentLabels = width >= 600;

    return PopScope(
      // Несохранённые правки: системный «Назад»/уход со страницы
      // спрашивает, что делать (пункт 3 замечаний Sonnet).
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_isDirty) {
          return;
        }

        _confirmDiscard();
      },
      child: Scaffold(
      backgroundColor: palette.surface,
      drawer: wide
          ? null
          : Drawer(
              // На очень узких телефонах 340 шире экрана — дефолт (304).
              width: width < 400 ? null : 340,
              child: AdminOutline(
                currentIslandId: widget.islandId,
                currentPoiId: widget.poiId,
              ),
            ),
      appBar: AppBar(
        title: Text(poi?.title ?? widget.poiId),
        // На телефоне переключатель режимов не влезает в AppBar
        // рядом с бейджем очереди и заголовком — отдельная полоса
        // под шапкой (режимы — с подписями, скролл по горизонтали).
        bottom: wide
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildModeSwitcher(withLabels: true),
                  ),
                ),
              ),
        actions: [

          // Метаданные текущей точки (название, координаты, категория).
          IconButton(
            tooltip: 'Свойства точки',
            icon: const Icon(LucideIcons.settings2),
            onPressed: () => showEditPoiMetaDialog(
              context,
              ref,
              widget.islandId,
              widget.poiId,
            ),
          ),

          // Очередь переименований видима: бейдж-счётчик в AppBar,
          // тап — панель «Изменения» (A3 замечаний Sonnet).
          const _PendingQueueButton(),

          // Узкий экран: бейдж и режимы ушли из AppBar (не влезают).
          if (wide) ...[
            const SizedBox(width: 8),

            if (_fromEdits)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(child: _UnpublishedBadge()),
              ),

            _buildModeSwitcher(withLabels: segmentLabels),

            const SizedBox(width: 12),
          ],
        ],
      ),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                SizedBox(
                  width: 320,
                  child: AdminOutline(
                    currentIslandId: widget.islandId,
                    currentPoiId: widget.poiId,
                  ),
                ),

                const VerticalDivider(width: 1),

                Expanded(child: _buildBody()),
              ],
            )
          : _buildBody(),
      ),
    );
  }

  /// Переключатель режимов редактора: на широких — в actions
  /// AppBar, на телефоне — в полосу под шапкой.
  Widget _buildModeSwitcher({required bool withLabels}) {

    return SegmentedButton<_EditorMode>(
      segments: [
        ButtonSegment(
          value: _EditorMode.text,
          icon: const Icon(LucideIcons.pencil),
          label: withLabels ? const Text('Текст') : null,
        ),
        ButtonSegment(
          value: _EditorMode.quiz,
          icon: const Icon(LucideIcons.circleHelp),
          label: withLabels ? const Text('Квиз') : null,
        ),
        ButtonSegment(
          value: _EditorMode.preview,
          icon: const Icon(LucideIcons.eye),
          label: withLabels ? const Text('Просмотр') : null,
        ),
        ButtonSegment(
          value: _EditorMode.diff,
          icon: const Icon(LucideIcons.gitCompareArrows),
          label: withLabels ? const Text('Дифф') : null,
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (selection) {
        _setMode(selection.first);
      },
    );
  }

  Widget _buildBody() {

    final narrow = MediaQuery.sizeOf(context).width < 900;

    return Column(
      children: [

        // Телефон: бейдж «Не опубликовано» — не в AppBar (тесно),
        // а плашкой над редактором.
        if (narrow && _fromEdits)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _UnpublishedBadge(),
            ),
          ),

        Expanded(
          child: switch (_mode) {
            _EditorMode.text => _buildTextEditor(),
            _EditorMode.quiz => _buildQuizEditor(),
            _EditorMode.preview => _buildPreview(),
            _EditorMode.diff => _buildDiff(),
          },
        ),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            // Телефон: Row с Spacer переполняется — кнопки стилей
            // без подписей (иконки 48), ряд собирается Wrap'ом и
            // переносится на вторую строку, а не наезжает.
            child: !narrow
                ? Row(
                    children: [

                      if (_mode == _EditorMode.text) ...[

                        ExcludeFocus(
                          child: OutlinedButton.icon(
                            onPressed: () => _applyStyle(bold: true),
                            icon: const Icon(LucideIcons.bold),
                            label: const Text('Жирный'),
                          ),
                        ),

                        const SizedBox(width: 8),

                        ExcludeFocus(
                          child: OutlinedButton.icon(
                            onPressed: () => _applyStyle(bold: false, red: true),
                            icon: Icon(
                              LucideIcons.highlighter,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            label: const Text('Красный'),
                          ),
                        ),

                        const SizedBox(width: 8),

                        ExcludeFocus(
                          child: OutlinedButton.icon(
                            onPressed: _controller.spans.isEmpty ? null : _clearStyles,
                            icon: const Icon(LucideIcons.eraser),
                            label: const Text('Сбросить'),
                          ),
                        ),

                        const SizedBox(width: 8),

                        ExcludeFocus(
                          child: IconButton(
                            tooltip: 'Отменить (Ctrl+Z)',
                            onPressed:
                                _controller.canUndo ? () => _undo() : null,
                            icon: const Icon(LucideIcons.undo2),
                          ),
                        ),

                        ExcludeFocus(
                          child: IconButton(
                            tooltip: 'Вернуть (Ctrl+Shift+Z)',
                            onPressed:
                                _controller.canRedo ? () => _redo() : null,
                            icon: const Icon(LucideIcons.redo2),
                          ),
                        ),

                        const SizedBox(width: 8),
                      ],

                      const Spacer(),

                      _buildSaveButton(),
                    ],
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [

                      if (_mode == _EditorMode.text) ...[
                        ExcludeFocus(
                          child: IconButton(
                            tooltip: 'Жирный',
                            onPressed: () => _applyStyle(bold: true),
                            icon: const Icon(LucideIcons.bold),
                          ),
                        ),

                        ExcludeFocus(
                          child: IconButton(
                            tooltip: 'Красный текст',
                            onPressed: () => _applyStyle(bold: false, red: true),
                            icon: Icon(
                              LucideIcons.highlighter,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),

                        ExcludeFocus(
                          child: IconButton(
                            tooltip: 'Сбросить оформление',
                            onPressed: _controller.spans.isEmpty ? null : _clearStyles,
                            icon: const Icon(LucideIcons.eraser),
                          ),
                        ),

                        ExcludeFocus(
                          child: IconButton(
                            tooltip: 'Отменить (Ctrl+Z)',
                            onPressed:
                                _controller.canUndo ? () => _undo() : null,
                            icon: const Icon(LucideIcons.undo2),
                          ),
                        ),

                        ExcludeFocus(
                          child: IconButton(
                            tooltip: 'Вернуть (Ctrl+Shift+Z)',
                            onPressed:
                                _controller.canRedo ? () => _redo() : null,
                            icon: const Icon(LucideIcons.redo2),
                          ),
                        ),
                      ],

                      _buildSaveButton(),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {

    return FilledButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
          : const Icon(LucideIcons.upload),
      label: const Text('Сохранить'),
    );
  }

  Widget _buildTextEditor() {

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // Название точки — правится вместе с текстом.
          TextField(
            controller: _titleController,
            style: AppText.h3,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Название точки',
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: Shortcuts(
              shortcuts: _formatShortcuts,
              child: Actions(
                actions: {
                  _StyleIntent: CallbackAction<_StyleIntent>(
                    onInvoke: (intent) {
                      _applyStyle(bold: intent.bold, red: intent.red);
                      return null;
                    },
                  ),
                  // Ctrl+S / Cmd+S — сохранить правку (A3).
                  _SaveIntent: CallbackAction<_SaveIntent>(
                    onInvoke: (intent) {
                      if (!_saving) {
                        _save();
                      }
                      return null;
                    },
                  ),
                  _UndoIntent: CallbackAction<_UndoIntent>(
                    onInvoke: (intent) {
                      _undo();
                      return null;
                    },
                  ),
                  _RedoIntent: CallbackAction<_RedoIntent>(
                    onInvoke: (intent) {
                      _redo();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  style: AppText.body.copyWith(
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Текст точки (markdown)',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Строка варианта ответа: радио «верный» + поле текста + удаление.
  ///
  /// Радио живёт внутри [RadioGroup] из редактора квиза
  /// (Flutter 3.32+: groupValue/onChanged у [Radio] устарели).
  Widget _quizOptionRow(int i) {
    return Padding(
      key: Key('quiz-option-row-$i'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(
            message: 'Верный ответ',
            child: Radio<int>(
              key: Key('quiz-correct-$i'),
              value: i,
            ),
          ),
          Expanded(
            child: TextField(
              key: Key('quiz-option-$i'),
              controller: _quizOptions[i],
              onChanged: (_) => _applyQuiz(),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: 'Вариант ${i + 1}',
              ),
            ),
          ),
          IconButton(
            key: Key('quiz-remove-option-$i'),
            onPressed: _quizOptions.length <= 2
                ? null
                : () {
                    setState(() {
                      _quizOptions[i].dispose();
                      _quizOptions.removeAt(i);
                      if (_correctIndex == i) {
                        _correctIndex = 0;
                      } else if (_correctIndex > i) {
                        _correctIndex--;
                      }
                    });

                    _applyQuiz();
                  },
            icon: const Icon(LucideIcons.x),
            tooltip: 'Удалить вариант',
          ),
        ],
      ),
    );
  }

  Widget _buildQuizEditor() {

    final palette = AppPalette.of(context);

    return ListView(
      key: const ValueKey('quiz-editor'),
      padding: const EdgeInsets.all(12),
      children: [

        TextField(
          key: const Key('quiz-question'),
          controller: _quizQuestion,
          style: AppText.h3,
          onChanged: (_) => _applyQuiz(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Вопрос',
          ),
        ),

        const SizedBox(height: 16),

        const Text(
          'Варианты ответа (отметьте верный)',
          style: AppText.eyebrowMuted,
        ),

        const SizedBox(height: 8),

        RadioGroup<int>(
          groupValue: _correctIndex,
          onChanged: (value) {
            // Повторный тап по выбранному Radio шлёт null — выбор не снимаем.
            if (value == null) {
              return;
            }

            setState(() {
              _correctIndex = value;
            });

            _applyQuiz();
          },
          child: Column(
            children: [
              for (var i = 0; i < _quizOptions.length; i++) _quizOptionRow(i),
            ],
          ),
        ),

        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('quiz-add-option'),
            onPressed: () {
              setState(() {
                _quizOptions.add(TextEditingController());
              });
            },
            icon: const Icon(LucideIcons.plus),
            label: const Text('Добавить вариант'),
          ),
        ),

        const SizedBox(height: 16),

        TextField(
          key: const Key('quiz-note'),
          controller: _quizNote,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => _applyQuiz(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Пояснение после ответа',
            alignLabelWithHint: true,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Квиз показывается читателю карточкой «Проверьте себя» в конце статьи. '
          'Пустой вопрос или меньше двух заполненных вариантов — квиз не сохранится.',
          style: AppText.caption.copyWith(color: palette.onSurfaceMuted),
        ),
      ],
    );
  }

  /// Просмотр = итоговая страница читателя (замечание владельца):
  /// статья И квиз вместе — ровно те же виджеты, что на странице
  /// POI (ExpandableText-абзацы + интерактивная QuizCard).
  Widget _buildPreview() {

    final blocks = parseMarkdownBlocks(_combinedText());

    return ListView(
      key: const ValueKey('admin-preview'),
      padding: const EdgeInsets.all(16),
      children: [
        for (final block in blocks)
          if (block is MdQuiz)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: QuizCard(quiz: block),
            )
          else
            SelectableText.rich(
              mdBlockTextSpan(block),
            ),
      ],
    );
  }

  /// Дифф «Было / Стало» (A3 замечаний Sonnet): сравнение с
  /// ЗАГРУЖЕННОЙ версией по абзацам. Изменённый абзац читается
  /// парой «− старый / + новый».
  Widget _buildDiff() {

    final palette = AppPalette.of(context);

    final oldText = _savedText;

    if (oldText == null) {
      return const Center(child: Text('Старая версия ещё не загружена'));
    }

    if (!_isDirty) {
      return const Center(child: Text('Нет изменений'));
    }

    // Дифф — по ПОЛНОМУ тексту: статья и квиз вместе.
    final oldFull = applyQuizToText(
      oldText,
      _savedQuiz != null ? parseQuizBlock(_savedQuiz!) : null,
    );

    final rows = diffParagraphs(oldFull, _combinedText());

    return ListView(
      key: const ValueKey('admin-diff'),
      padding: const EdgeInsets.all(16),
      children: [
        for (final row in rows)
          if (row.kind != ParagraphDiffKind.same)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.kind == ParagraphDiffKind.added ? '+' : '−',
                    style: AppText.h3.copyWith(
                      color: row.kind == ParagraphDiffKind.added
                          ? palette.success
                          : palette.error,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      row.text,
                      style: AppText.body.copyWith(
                        color: row.kind == ParagraphDiffKind.added
                            ? palette.onSurface
                            : palette.onSurfaceMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Бейдж «правка ещё не опубликована» — текст взят из ветки правок.
class _UnpublishedBadge extends StatelessWidget {

  const _UnpublishedBadge();

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
      color: palette.warning.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        'Не опубликовано',
        style: AppText.eyebrowMuted.copyWith(
          color: palette.warning,
        ),
      ),
    );
  }
}

class _PendingQueueButton extends ConsumerWidget {

  const _PendingQueueButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final pending = ref.watch(pendingRenamesProvider);

    final palette = AppPalette.of(context);

    return IconButton(
      tooltip: 'Очередь изменений',
      onPressed: () => _openPendingQueueSheet(context, ref),
      icon: Badge(
        isLabelVisible: pending.isNotEmpty,
        label: Text('${pending.length}'),
        backgroundColor: palette.accent,
        textColor: palette.accentOn,
        child: const Icon(LucideIcons.listTodo),
      ),
    );
  }
}

/// Панель «Изменения»: список поставленных в очередь правок
/// манифестов с кнопкой «Убрать» — публикуются кнопкой
/// «Сохранить» в редакторе единым коммитом.
Future<void> _openPendingQueueSheet(BuildContext context, WidgetRef ref) {
  return showAppBottomSheet(
    context,
    title: 'Изменения',
    maxHeightFactor: 0.6,
    builder: (sheetContext) {
      return Consumer(
        builder: (context, ref, _) {
          final palette = AppPalette.of(context);

          final entries = ref.watch(pendingRenamesProvider).entries.toList();

          if (entries.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                'Очередь пуста. Переименуй регион или локацию в оглавлении — '
                'правка встанет сюда и опубликуется кнопкой «Сохранить».',
                style: AppText.body.copyWith(color: palette.onSurfaceMuted),
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in entries)
                Padding(
                  key: ValueKey('pending-queue-${entry.key}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              manifestName(entry.value) ?? entry.key,
                              style: AppText.body,
                            ),
                            Text(
                              entry.key,
                              style: AppText.caption.copyWith(
                                color: palette.onSurfaceMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: ValueKey('pending-remove-${entry.key}'),
                        tooltip: 'Убрать из очереди',
                        onPressed: () {
                          ref
                              .read(pendingRenamesProvider.notifier)
                              .remove(entry.key);
                        },
                        icon: const Icon(LucideIcons.trash2),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

/// Контроллер rich-редактора: в text — ЧИСТЫЙ текст (без
/// звёздочек разметки), стили — отдельные диапазоны [spans],
/// рендерятся через buildTextSpan (замечание владельца 28.10:
/// «звёздочек вообще не должно быть», правка как в MS Word).
///
/// Правка текста сдвигает диапазоны по дельте вставки/удаления
/// (adjustSpans) — разметка «прилипает» к словам, как в текстовом
/// процессоре. В markdown собирается только [markdown] (сохранение,
/// просмотр, дифф).
/// Контроллер с живой разметкой: **жирный** и *курсив* рисуются
/// стилями, как в обычном редакторе; символы разметки остаются в
/// тексте (приглушены) — правка и сохранение markdown не ломаются.
/// Снимок состояния rich-поля для истории undo/redo:
/// чистый текст + стили + выделение.
typedef RichHistoryEntry = ({
  String text,
  List<RichSpan> spans,
  TextSelection selection,
});

class RichEditingController extends TextEditingController {

  RichEditingController({super.text});

  /// Стили текущего текста; меняются кнопками/Ctrl+B/I.
  List<RichSpan> spans = <RichSpan>[];

  // --- история правок (undo/redo) ---

  final List<RichHistoryEntry> _undoStack = [];

  final List<RichHistoryEntry> _redoStack = [];

  DateTime? _lastHistoryPush;

  /// Быстрый ввод (пауза < 700 мс между правками) склеивается
  /// в одну точку undo — отменяется «пачкой», а не по букве.
  static const _burstWindow = Duration(milliseconds: 700);

  static const _maxHistory = 200;

  RichHistoryEntry get _snapshot => (
        text: text,
        spans: List<RichSpan>.of(spans),
        selection: selection,
      );

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  /// Явный снимок перед дискретной правкой (кнопка стиля,
  /// т.к. она меняет только spans, не текст).
  void pushHistory() {
    _undoStack.add(_snapshot);

    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }

    _redoStack.clear();

    _lastHistoryPush = DateTime.now();
  }

  void undo() {
    if (_undoStack.isEmpty) {
      return;
    }

    _redoStack.add(_snapshot);

    _restore(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) {
      return;
    }

    _undoStack.add(_snapshot);

    _restore(_redoStack.removeLast());
  }

  /// Только для тестов: «состарить» последнюю запись истории,
  /// чтобы следующая правка не склеилась в ту же пачку.
  void debugExpireBurst() {
    _lastHistoryPush = DateTime.now().subtract(const Duration(seconds: 5));
  }

  void _restore(RichHistoryEntry entry) {
    _lastHistoryPush = null;

    // super.value — чтобы не зайти в наш set value и не пушить историю.
    super.value = TextEditingValue(
      text: entry.text,
      selection: entry.selection,
    );

    spans = List<RichSpan>.of(entry.spans);
  }

  @override
  set value(TextEditingValue newValue) {
    final old = text;

    final oldSpans = List<RichSpan>.of(spans);

    final oldSelection = selection;

    super.value = newValue;

    if (old != text) {
      // Редактирование текста: диапазоны сдвигаются за правкой.
      spans = adjustSpans(spans, old, text);

      // Снимок ДО правки — в undo; серию быстрых правок склеиваем.
      final now = DateTime.now();

      final inBurst = _lastHistoryPush != null &&
          now.difference(_lastHistoryPush!) < _burstWindow;

      if (!inBurst) {
        _undoStack.add(
          (text: old, spans: oldSpans, selection: oldSelection),
        );

        if (_undoStack.length > _maxHistory) {
          _undoStack.removeAt(0);
        }

        _redoStack.clear();

        _lastHistoryPush = now;
      }
    }
  }

  /// Markdown-текст файла: чистый текст + звёздочки из стилей.
  String get markdown => serializeRich(text, spans);

  /// Загружает статью из markdown: снимает разметку в диапазоны.
  void setMarkdown(String raw) {
    final doc = parseRich(raw);

    text = doc.plain;

    spans = doc.spans;

    // Новый документ — новая история.
    _undoStack.clear();

    _redoStack.clear();

    _lastHistoryPush = null;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();

    final children = <TextSpan>[];

    var cursor = 0;

    // Рендер предполагает отсортированный порядок: идём по списку
    // подряд и выводим текст между курсором и началом span.
    // Неотсортированный span (старое сохранение, undo) рисовал бы
    // фрагмент не на своём месте — сортируем defensively.
    final ordered = [...spans]..sort((a, b) => a.start.compareTo(b.start));

    for (final span in ordered) {
      if (span.start > cursor) {
        children.add(
          TextSpan(text: text.substring(cursor, span.start), style: base),
        );
      }

      children.add(
        TextSpan(
          text: text.substring(
            span.start.clamp(0, text.length),
            span.end.clamp(0, text.length),
          ),
          style: base.copyWith(
            fontWeight: (span.bold || span.red) ? FontWeight.w700 : null,
            fontStyle: span.italic ? FontStyle.italic : null,
            color: span.red ? AppColors.redText : null,
          ),
        ),
      );

      cursor = span.end > cursor ? span.end : cursor;
    }

    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: base));
    }

    return TextSpan(
      style: base,
      children: children.isEmpty ? [TextSpan(text: text)] : children,
    );
  }
}
