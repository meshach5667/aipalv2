import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../config.dart';
import '../services/api_client.dart';
import '../services/auth_storage.dart';
import '../services/live_session.dart';
import '../services/live_voice_loop.dart';
import '../services/live_voice_session.dart';
import '../services/notification_service.dart';
import '../services/wake_background_service.dart';
import '../services/wake_word_prefs.dart';
import '../services/wake_word_service.dart';

class AppState extends ChangeNotifier {
  AppState() {
    if (_isAndroid) {
      FlutterForegroundTask.addTaskDataCallback(_onBackgroundWakeData);
    }
  }

  final _authStorage = createAuthStorage();
  bool authReady = false;
  String? token;
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> tasks = [];
  Map<String, dynamic>? todayView;
  Map<String, dynamic>? eveningPayload;
  Map<String, dynamic>? pendingPlanDraft;
  List<Map<String, dynamic>> conversationSessions = [];
  String? companionMode;
  Map<String, dynamic>? companionEmotion;
  List<Map<String, dynamic>> memoriesUsed = [];
  List<Map<String, dynamic>> suggestedActions = [];
  String? confirmationPrompt;
  bool requiresConfirmation = false;
  String? companionConversationId;
  int selectedTab = 0;
  Map<String, dynamic>? focusTask;
  int focusSeconds = 25 * 60;
  final liveSession = LiveSession();
  LiveVoiceSession? _liveVoiceV2;
  LiveVoiceLoop? _voiceLoop;
  final _player = AudioPlayer();
  String? lastReply;
  String? lastTranscript;
  String? turnError;
  String? checkinBanner;
  String? suggestDayNotice;
  bool loading = false;
  bool _speaking = false;
  bool _processingTurn = false;
  int _turnGeneration = 0;
  WakeWordService? _wakeWord;
  bool wakeWordEnabled = false;
  bool wakeWordListening = false;
  bool wakeWordEngineReady = false;
  String? wakeWordError;
  bool wakeWordAvailable = true;
  final List<Timer> _nudgeTimers = [];
  Future<void> _wakeSyncTail = Future.value();

  ApiClient get api => ApiClient(token);

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String get _wakeName =>
      profile?['wake_name'] as String? ??
      profile?['display_name'] as String? ??
      'friend';

  Map<String, dynamic>? get nextOpenTask {
    final up = todayView?['up_next'] as Map<String, dynamic>?;
    if (up != null) return up;
    final sections = todayView?['sections'] as Map<String, dynamic>?;
    final upcoming =
        (sections?['upcoming'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return upcoming.isNotEmpty ? upcoming.first : null;
  }

  List<Map<String, dynamic>> get openTasksForReview {
    final sections = todayView?['sections'] as Map<String, dynamic>?;
    final now = (sections?['now'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final upcoming =
        (sections?['upcoming'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return [...now, ...upcoming];
  }

  void goToTab(int index) {
    final leavingCompanion = selectedTab == 0 && index != 0;
    selectedTab = index;
    if (leavingCompanion && liveSession.state != LiveState.resting) {
      unawaited(_stopLiveModeForTabSwitch());
    } else {
      unawaited(syncWakeListener());
    }
    notifyListeners();
  }

  /// Fast path for app launch: read stored token only; never blocks on network or wake.
  Future<void> loadStoredAuth() async {
    try {
      token = await _authStorage.readToken();
    } finally {
      authReady = true;
      notifyListeners();
    }
  }

  /// Post-frame bootstrap: profile validation, today view, wake listener.
  Future<void> finishBootstrap() async {
    try {
      if (token != null) {
        try {
          profile = await api.getProfile();
          await _loadCheckinBanner();
          await refreshTodayView();
          await refreshConversationSessions();
        } catch (e) {
          final errorText = e.toString();
          if (errorText.contains('(401)') || errorText.contains('(403)')) {
            token = null;
            profile = null;
            await _authStorage.deleteToken();
          }
          // Keep the stored session on transient backend/network failures.
          // Explicit sign-out is the only place that should clear auth.
          profile = null;
        }
      }
      await _loadWakePrefs();
      try {
        await syncWakeListener();
      } catch (_) {}
    } finally {
      notifyListeners();
    }
  }

  Future<void> _loadWakePrefs() async {
    wakeWordEnabled = await WakeWordPrefs.isEnabled();
  }

  Future<void> setWakeWordEnabled(bool enabled) async {
    wakeWordEnabled = enabled;
    await WakeWordPrefs.setEnabled(enabled);
    await syncWakeListener();
    notifyListeners();
  }

  Future<void> syncWakeListener() async {
    final completer = Completer<void>();
    _wakeSyncTail = _wakeSyncTail.catchError((_) {}).then((_) async {
      try {
        await _syncWakeListenerImpl();
      } catch (_) {
        // Wake listener failures are non-fatal; the UI state should stay usable.
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    return completer.future;
  }

  Future<void> _syncWakeListenerImpl() async {
    if (!wakeWordAvailable || token == null) {
      await _stopAllWakeListening();
      notifyListeners();
      return;
    }

    if (kIsWeb) {
      await _stopWakeListener();
      wakeWordEngineReady = wakeWordEnabled;
      wakeWordListening =
          wakeWordEnabled &&
          selectedTab == 0 &&
          liveSession.state == LiveState.listening;
      wakeWordError = null;
      notifyListeners();
      return;
    }

    if (_isAndroid) {
      await _syncAndroidBackgroundWake();
      return;
    }

    final shouldListen =
        wakeWordEnabled &&
        selectedTab == 0 &&
        liveSession.state == LiveState.resting &&
        !_shouldSuppressWake();
    if (!shouldListen) {
      await _stopWakeListener();
      wakeWordListening = false;
      notifyListeners();
      return;
    }
    _wakeWord ??= WakeWordService(
      onWake: () => unawaited(_onWakeWordDetected()),
      shouldSuppress: _shouldSuppressWake,
    );
    if (!await _wakeWord!.init()) {
      wakeWordListening = false;
      notifyListeners();
      return;
    }
    await _wakeWord!.start();
    wakeWordListening = _wakeWord!.isListening;
    notifyListeners();
  }

  Future<void> _syncAndroidBackgroundWake() async {
    await _stopWakeListener();
    if (!wakeWordEnabled) {
      await WakeBackgroundService.stop();
      wakeWordListening = false;
      wakeWordEngineReady = false;
      wakeWordError = null;
      notifyListeners();
      return;
    }

    final suppressed =
        liveSession.state != LiveState.resting || _shouldSuppressWake();
    final running = await WakeBackgroundService.isRunning();

    if (suppressed) {
      if (running) {
        WakeBackgroundService.setSuppressed(true);
      }
      wakeWordListening = false;
      wakeWordEngineReady = false;
      wakeWordError = null;
      notifyListeners();
      return;
    }

    if (!running) {
      final started = await WakeBackgroundService.ensureRunning();
      if (!started) {
        wakeWordListening = false;
        wakeWordEngineReady = false;
        wakeWordError =
            'Could not start listening (grant microphone and notification permissions)';
        notifyListeners();
        return;
      }
    }

    WakeBackgroundService.setSuppressed(false);
    wakeWordEngineReady = false;
    wakeWordListening = true;
    wakeWordError = null;
    notifyListeners();
  }

  Future<void> _stopWakeListener() async {
    final svc = _wakeWord;
    if (svc != null) {
      await svc.stop();
    }
  }

  Future<void> _stopLiveModeForTabSwitch() async {
    _turnGeneration++;
    _speaking = false;
    _processingTurn = false;
    await _stopVoiceLoop();
    await _stopLiveV2();
    await liveSession.stop();
    await syncWakeListener();
    notifyListeners();
  }

  Future<void> _stopAllWakeListening() async {
    await _stopWakeListener();
    if (_isAndroid) {
      await WakeBackgroundService.stop();
    }
    wakeWordListening = false;
    wakeWordEngineReady = false;
    wakeWordError = null;
  }

  void _onBackgroundWakeData(Object data) {
    if (data is! Map) return;
    final event = data['event'];
    if (event == 'wake') {
      unawaited(handleBackgroundWake());
      return;
    }
    if (event == 'engine_ready') {
      wakeWordEngineReady = true;
      wakeWordError = null;
      if (wakeWordEnabled) {
        final suppressed =
            liveSession.state != LiveState.resting || _shouldSuppressWake();
        wakeWordListening = !suppressed;
      }
      notifyListeners();
      return;
    }
    if (event == 'engine_failed') {
      wakeWordEngineReady = false;
      wakeWordListening = false;
      wakeWordError =
          data['error']?.toString() ?? 'Wake word engine failed to start';
      notifyListeners();
    }
  }

  Future<void> handleBackgroundWake() async {
    if (liveSession.state != LiveState.resting) return;
    selectedTab = 0;
    WakeBackgroundService.setSuppressed(true);
    notifyListeners();
    await toggleLive();
  }

  Future<void> _onWakeWordDetected() async {
    if (liveSession.state != LiveState.resting) return;
    selectedTab = 0;
    await _stopWakeListener();
    await toggleLive();
  }

  Future<void> _loadCheckinBanner() async {
    try {
      final payload = await api.checkinPayload();
      checkinBanner = payload['prompt'] as String?;
    } catch (_) {
      checkinBanner = null;
    }
  }

  Future<void> login(String email) async {
    final reg = await api.register(email);
    final devToken = reg['dev_token'] as String?;
    if (devToken == null) {
      throw Exception(
        'Magic link email is not configured on this backend. For local development, set MAGIC_LINK_DEV_RETURN_TOKEN=true and restart the API.',
      );
    }
    final auth = await ApiClient(null).verify(devToken);
    final accessToken = auth['access_token'] as String;
    token = accessToken;
    await _authStorage.writeToken(accessToken);
    profile = await api.getProfile();
    await _loadCheckinBanner();
    await refreshTodayView();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _stopVoiceLoop();
    await _stopLiveV2();
    await liveSession.stop();
    await _stopAllWakeListening();
    await _authStorage.deleteToken();

    token = null;
    profile = null;
    tasks = [];
    todayView = null;
    eveningPayload = null;
    pendingPlanDraft = null;
    conversationSessions = [];
    companionMode = null;
    companionEmotion = null;
    memoriesUsed = [];
    suggestedActions = [];
    confirmationPrompt = null;
    requiresConfirmation = false;
    companionConversationId = null;
    focusTask = null;
    focusSeconds = 25 * 60;
    lastReply = null;
    lastTranscript = null;
    turnError = null;
    checkinBanner = null;
    suggestDayNotice = null;
    loading = false;
    selectedTab = 0;
    _processingTurn = false;
    _speaking = false;
    _turnGeneration++;
    _cancelNudgeTimers();
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    profile = await api.updateProfile(data);
    notifyListeners();
  }

  Future<void> refreshTasks() async {
    final list = await api.listTasks();
    tasks = list.cast<Map<String, dynamic>>();
    notifyListeners();
  }

  Future<void> refreshTodayView() async {
    if (token == null) return;
    try {
      final agenda = await api.getTodayAgenda();
      final today = DateTime.now();
      final range = await api.getTodayItemRange(
        startDate: _dateOnly(today),
        endDate: _dateOnly(today.add(const Duration(days: 7))),
      );
      Map<String, dynamic>? legacy;
      try {
        legacy = await api.fetchTaskTodayView();
      } catch (_) {
        legacy = null;
      }
      final todayItems = range
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      final agendaItems =
          (agenda['items'] as List?)
              ?.whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList() ??
          const <Map<String, dynamic>>[];
      final mergedItems = _mergeTodayItems([...agendaItems, ...todayItems]);
      final summary = Map<String, dynamic>.from(
        agenda['summary'] as Map? ?? const {},
      );
      summary['done'] = summary['done'] ?? summary['completed'] ?? 0;
      summary['streak_days'] = summary['streak_days'] ?? 0;
      final nextItem = _firstOpenTodayItem(mergedItems);
      todayView = {
        ...agenda,
        'summary': summary,
        'today_items': mergedItems,
        'up_next': nextItem,
        if (legacy?['sections'] != null) 'sections': legacy!['sections'],
      };
      tasks = [
        ...?((todayView?['sections'] as Map?)?['now'] as List?),
        ...?((todayView?['sections'] as Map?)?['upcoming'] as List?),
        ...?((todayView?['sections'] as Map?)?['completed'] as List?),
      ].cast<Map<String, dynamic>>();
      await _rescheduleTaskNudges();
    } catch (_) {}
    notifyListeners();
  }

  String _dateOnly(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  List<Map<String, dynamic>> _mergeTodayItems(
    List<Map<String, dynamic>> items,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) continue;
      byId[id] = item;
    }
    final merged = byId.values.toList();
    merged.sort((a, b) {
      final aTime = _todayItemSortTime(a);
      final bTime = _todayItemSortTime(b);
      return aTime.compareTo(bTime);
    });
    return merged;
  }

  DateTime _todayItemSortTime(Map<String, dynamic> item) {
    final raw =
        item['start_time']?.toString() ??
        item['due_at']?.toString() ??
        item['created_at']?.toString();
    if (raw == null || raw.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(8640000000000000);
    }
    return DateTime.tryParse(raw)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(8640000000000000);
  }

  Map<String, dynamic>? _firstOpenTodayItem(List<Map<String, dynamic>> items) {
    for (final item in items) {
      final status = item['status']?.toString();
      if (!{'completed', 'cancelled', 'dismissed'}.contains(status)) {
        return item;
      }
    }
    return null;
  }

  Future<void> refreshConversationSessions() async {
    if (token == null) return;
    try {
      final list = await api.listConversationSessions();
      conversationSessions = list.cast<Map<String, dynamic>>();
    } catch (_) {}
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> loadConversationHistory(
    String sessionId,
  ) async {
    if (token == null) return [];
    final turns = await api.getConversationTurns(sessionId);
    return turns.cast<Map<String, dynamic>>();
  }

  void _cancelNudgeTimers() {
    for (final t in _nudgeTimers) {
      t.cancel();
    }
    _nudgeTimers.clear();
  }

  Future<void> _rescheduleTaskNudges() async {
    if (kIsWeb || token == null) return;
    _cancelNudgeTimers();
    final open = openTasksForReview;
    try {
      await NotificationService.instance.rescheduleTaskNudges(
        tasks: open,
        wakeName: _wakeName,
      );
    } catch (_) {}
    final now = DateTime.now();
    for (final task in open) {
      final dueRaw = task['due_at'] as String?;
      final id = task['id'] as int?;
      if (dueRaw == null || id == null) continue;
      DateTime dueLocal;
      try {
        dueLocal = DateTime.parse(dueRaw).toLocal();
      } catch (_) {
        continue;
      }
      final fireAt = dueLocal.subtract(
        const Duration(minutes: NotificationService.nudgeLeadMinutes),
      );
      final delay = fireAt.difference(now);
      if (delay.isNegative || delay.inDays > 0) continue;
      final hour = dueLocal.hour;
      if (hour >= 22 || hour < 7) continue;
      _nudgeTimers.add(
        Timer(
          delay,
          () => unawaited(
            handleForegroundNudge(id, NotificationService.nudgeLeadMinutes),
          ),
        ),
      );
    }
  }

  Future<void> handleForegroundNudge(int taskId, int minutes) async {
    if (token == null) return;
    if (_speaking || _processingTurn) return;
    if (selectedTab != 0 && liveSession.state != LiveState.listening) return;
    try {
      final msg = await api.taskNudge(taskId: taskId, minutes: minutes);
      final text =
          (msg['assistantMessage'] as String?) ?? (msg['text'] as String?);
      if (text == null || text.isEmpty) return;
      lastReply = text;
      notifyListeners();
      if (msg['speak'] == true) {
        final tts = await api.tts(text);
        await _playAudioResponse(tts);
      }
    } catch (_) {}
  }

  Future<void> loadEveningPayload() async {
    eveningPayload = await api.eveningPayload();
    notifyListeners();
  }

  Future<void> loadPlanDraft() async {
    try {
      pendingPlanDraft = await api.fetchPlanDraft();
    } catch (_) {
      pendingPlanDraft = null;
    }
    notifyListeners();
  }

  Future<void> suggestDayPlan({String? template}) async {
    try {
      final res = await api.suggestDay(template: template);
      pendingPlanDraft = res['plan_draft'] as Map<String, dynamic>?;
      suggestDayNotice = res['notice'] as String?;
    } catch (_) {
      suggestDayNotice = null;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  void clearSuggestDayNotice() {
    suggestDayNotice = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> sendTextTurn(
    String text, {
    String? sessionId,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return {};

    _processingTurn = true;
    turnError = null;
    notifyListeners();

    try {
      final res = await api.companionTurn(
        cleanText,
        conversationId: sessionId ?? companionConversationId,
      );
      _applyCompanionTurnResponse(res);
      unawaited(refreshConversationSessions());
      return res;
    } catch (e) {
      turnError = _friendlyTurnError(e);
      rethrow;
    } finally {
      _processingTurn = false;
      notifyListeners();
    }
  }

  Future<void> confirmPlanDraft() async {
    await api.confirmPlanDraft();
    pendingPlanDraft = null;
    requiresConfirmation = false;
    confirmationPrompt = null;
    await refreshTodayView();
    notifyListeners();
  }

  Future<void> discardPlanDraft() async {
    await api.discardPlanDraft();
    pendingPlanDraft = null;
    requiresConfirmation = false;
    confirmationPrompt = null;
    notifyListeners();
  }

  void _applyCompanionTurnResponse(Map<String, dynamic> res) {
    lastReply =
        (res['assistantMessage'] as String?) ?? (res['reply'] as String?);
    companionMode = res['mode'] as String? ?? companionMode;
    companionEmotion =
        res['emotion'] as Map<String, dynamic>? ?? companionEmotion;
    memoriesUsed = (res['memories_used'] as List? ?? [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    suggestedActions = (res['suggested_actions'] as List? ?? [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    confirmationPrompt = res['confirmation_prompt'] as String?;
    requiresConfirmation = res['requires_confirmation'] as bool? ?? false;
    companionConversationId =
        res['conversation_id'] as String? ?? companionConversationId;
    if (res['draft_confirmed'] == true) {
      pendingPlanDraft = null;
      unawaited(refreshTodayView());
    } else {
      pendingPlanDraft = res['plan_draft'] as Map<String, dynamic>?;
      if (pendingPlanDraft == null) {
        unawaited(loadPlanDraft());
      }
      if (res['tool_actions'] is List &&
          (res['tool_actions'] as List).isNotEmpty) {
        unawaited(refreshTodayView());
      }
    }
  }

  Future<void> createTask(
    String title, {
    String? notes,
    String? goalId,
    DateTime? dueAt,
    int? priority,
    int? estimatedMinutes,
    String? category,
    int? parentTaskId,
  }) async {
    await api.createTask(
      title,
      notes: notes,
      goalId: goalId,
      dueAt: dueAt,
      priority: priority,
      estimatedMinutes: estimatedMinutes,
      category: category,
      parentTaskId: parentTaskId,
    );
    await refreshTodayView();
  }

  Future<void> updateTask(
    int id, {
    String? title,
    String? notes,
    String? status,
    DateTime? dueAt,
    String? goalId,
    int? priority,
  }) async {
    final body = <String, dynamic>{
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
      if (goalId != null) 'goal_id': goalId.isEmpty ? null : goalId,
      if (priority != null) 'priority': priority,
    };
    await api.patchTask(id, status: status, extra: body);
    await refreshTodayView();
  }

  Future<void> deleteTask(int id) async {
    await api.deleteTask(id);
    await refreshTodayView();
  }

  Future<void> deleteConversationSession(String sessionId) async {
    await api.deleteConversationSession(sessionId);
    await refreshConversationSessions();
  }

  Future<void> completeTask(int id) async {
    await api.patchTask(id, status: 'done');
    await refreshTodayView();
  }

  Future<void> completeTodayItem(String id) async {
    await api.completeTodayItem(id);
    await refreshTodayView();
  }

  Future<void> toggleItemComplete(String id, bool completed) async {
    if (completed) {
      await api.completeTodayItem(id);
    } else {
      await api.updateTodayItem(id, {'status': 'open'});
    }
    await refreshTodayView();
  }

  Future<void> cancelTodayItem(String id) async {
    await api.cancelTodayItem(id);
    await refreshTodayView();
  }

  Future<void> snoozeTodayItem(String id, {int minutes = 30}) async {
    await api.snoozeTodayItem(id, minutes: minutes);
    await refreshTodayView();
  }

  Future<void> rescheduleTodayItem(String id, DateTime newTime) async {
    await api.rescheduleTodayItem(id, newTime);
    await refreshTodayView();
  }

  Future<void> startFocusTodayItem(Map<String, dynamic> item) async {
    await api.startFocusTodayItem(item['id'].toString());
    final mins =
        item['estimated_minutes'] as int? ??
        item['duration_minutes'] as int? ??
        25;
    focusSeconds = mins * 60;
    focusTask = item;
    await refreshTodayView();
    notifyListeners();
  }

  Future<void> startFocusTask(Map<String, dynamic> item) async {
    final id = item['id'];
    if (id is int) {
      await startFocus(item);
      return;
    }
    await startFocusTodayItem(item);
  }

  Future<void> breakdownTask(int id) async {
    loading = true;
    notifyListeners();
    try {
      await api.breakdownTask(id);
      await refreshTodayView();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> deferOpenTasks() async {
    await api.deferOpenTasks();
    await refreshTodayView();
  }

  Future<void> reorderUpcoming(
    List<Map<String, dynamic>> upcoming,
    int oldIndex,
    int newIndex,
  ) async {
    final items = List<Map<String, dynamic>>.from(upcoming);
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    await api.reorderTasks(items.map((t) => t['id'] as int).toList());
    await refreshTodayView();
  }

  Future<void> reorderUpcomingLane(
    List<Map<String, dynamic>> upcoming,
    int priority,
    int oldIndex,
    int newIndex,
  ) async {
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final t in upcoming) {
      final p = (t['priority'] as int?) ?? 1;
      grouped.putIfAbsent(p, () => []).add(t);
    }
    final lane = List<Map<String, dynamic>>.from(grouped[priority] ?? []);
    final moved = lane.removeAt(oldIndex);
    lane.insert(newIndex, moved);
    grouped[priority] = lane;

    final ordered = <Map<String, dynamic>>[];
    for (final p in [2, 1, 0]) {
      ordered.addAll(grouped[p] ?? []);
    }
    await api.reorderTasks(ordered.map((t) => t['id'] as int).toList());
    await refreshTodayView();
  }

  Future<void> startFocus(Map<String, dynamic> task) async {
    final mins = task['estimated_minutes'] as int? ?? 25;
    focusSeconds = mins * 60;
    focusTask = task;
    await api.patchTask(task['id'] as int, status: 'in_progress');
    await refreshTodayView();
    notifyListeners();
  }

  Future<void> completeFocusTask() async {
    if (focusTask != null) {
      final id = focusTask!['id'];
      if (id is int) {
        await completeTask(id);
      } else if (id != null) {
        await completeTodayItem(id.toString());
      }
    }
    cancelFocus();
  }

  void cancelFocus() {
    focusTask = null;
    notifyListeners();
  }

  bool get _liveActive => _liveVoiceV2?.isActive ?? liveSession.isActive;

  bool _shouldSuppressLiveVad() =>
      _processingTurn && !_speaking && _liveVoiceV2 == null;

  bool _isSpeakingForVad() =>
      _speaking || (_liveVoiceV2?.isPlaybackActive ?? false);

  bool _shouldSuppressWake() => _speaking || _processingTurn || _liveActive;

  String _friendlyTurnError(Object error) {
    final text = error.toString();
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return 'AiPal is still taking too long to respond. Check that the local backend is running and the AI provider is responding, then try again.';
    }
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('XMLHttpRequest') ||
        text.contains('ERR_CONNECTION_REFUSED') ||
        text.contains('Failed to fetch')) {
      return 'The local API is not reachable. Make sure the backend is running on 127.0.0.1:8102, then try again.';
    }
    if (text.contains('Microphone permission')) {
      return 'Microphone permission is required for Live voice mode.';
    }
    return 'Something went wrong while sending that message. Please try again.';
  }

  Future<void> toggleLive() async {
    if (token == null) return;
    if (liveSession.state == LiveState.resting) {
      const useV2 = AppConfig.liveVoiceV2;
      if (useV2) {
        final session = LiveVoiceSession(
          onMessage: _handleLiveV2Message,
          isSpeakingForVad: _isSpeakingForVad,
          onSpeechStart: () {
            lastReply = null;
            lastTranscript = null;
            if (_speaking || (_liveVoiceV2?.isSpeaking ?? false)) {
              _turnGeneration++;
              _speaking = false;
              liveSession.state = LiveState.listening;
              notifyListeners();
            }
          },
        );
        try {
          if (!await session.ensureMicPermission()) {
            turnError =
                'Microphone permission is required for Live voice mode.';
            lastReply = null;
            notifyListeners();
            return;
          }
          turnError = null;
          await session.start(token!);
          _liveVoiceV2 = session;
          liveSession.state = LiveState.listening;
          liveSession.sessionId = session.sessionId;
          unawaited(_playLiveGreeting(useWsPath: true));
        } catch (e) {
          turnError = _friendlyTurnError(e);
          lastReply = null;
          await _stopLiveV2();
        }
      } else {
        final loop = LiveVoiceLoop(
          onSegment: _handleVoiceSegment,
          shouldSuppress: _shouldSuppressLiveVad,
          isSpeakingForVad: _isSpeakingForVad,
          onSpeechStart: () {
            if (_speaking) {
              _turnGeneration++;
              _speaking = false;
              if (liveSession.isActive) {
                liveSession.state = LiveState.listening;
              }
              unawaited(_player.stop());
              notifyListeners();
            }
          },
        );
        try {
          if (!await loop.ensureMicPermission()) {
            turnError =
                'Microphone permission is required for Live voice mode.';
            lastReply = null;
            notifyListeners();
            return;
          }
          turnError = null;
          await liveSession.start(token!, (msg) {
            if (msg['type'] == 'reply') {
              lastReply = msg['text'] as String?;
              notifyListeners();
            }
          });
          _voiceLoop = loop;
          await loop.start();
          unawaited(_playLiveGreeting());
        } catch (e) {
          turnError = _friendlyTurnError(e);
          lastReply = null;
          await _stopVoiceLoop();
          await liveSession.stop();
        }
      }
    } else {
      await _stopVoiceLoop();
      await _stopLiveV2();
      await liveSession.stop();
      _turnGeneration++;
    }
    await syncWakeListener();
    notifyListeners();
  }

  Future<void> _stopLiveV2() async {
    final session = _liveVoiceV2;
    _liveVoiceV2 = null;
    if (session != null) {
      await session.dispose();
    }
    liveSession.state = LiveState.resting;
    liveSession.sessionId = null;
  }

  @visibleForTesting
  void handleLiveV2MessageForTest(Map<String, dynamic> msg) =>
      _handleLiveV2Message(msg);

  void _handleLiveV2Message(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == 'session_started') {
      liveSession.sessionId = msg['session_id'] as String?;
    }
    if (type == 'state') {
      final s = msg['state'] as String?;
      if (s == 'thinking') {
        liveSession.state = LiveState.thinking;
        lastReply = null;
      }
      if (s == 'listening') {
        if (_liveVoiceV2?.isPlaybackActive ?? false) {
          liveSession.state = LiveState.speaking;
          _speaking = true;
        } else {
          liveSession.state = LiveState.listening;
          _speaking = false;
        }
      }
      if (s == 'speaking') {
        liveSession.state = LiveState.speaking;
        _speaking = true;
      }
    }
    if (type == 'transcript_partial') {
      if (AppConfig.showLiveTranscript) {
        lastTranscript = msg['text'] as String?;
      }
    }
    if (type == 'transcript_final') {
      if (AppConfig.showLiveTranscript) {
        lastTranscript = msg['text'] as String?;
      } else {
        lastTranscript = null;
      }
      lastReply = null;
    }
    if (type == 'reply_delta') {
      final delta = msg['text'] as String? ?? '';
      lastReply = '${lastReply ?? ''}$delta';
    }
    if (type == 'turn_complete') {
      _processingTurn = false;
      turnError = null;
      lastReply =
          (msg['assistantMessage'] as String?) ??
          (msg['reply'] as String?) ??
          lastReply;
      companionMode = msg['mode'] as String? ?? companionMode;
      companionEmotion =
          msg['emotion'] as Map<String, dynamic>? ?? companionEmotion;
      memoriesUsed = (msg['memories_used'] as List? ?? [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      suggestedActions = (msg['suggested_actions'] as List? ?? [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      confirmationPrompt = msg['confirmation_prompt'] as String?;
      requiresConfirmation = msg['requires_confirmation'] as bool? ?? false;
      if (msg['draft_confirmed'] == true) {
        pendingPlanDraft = null;
        unawaited(refreshTodayView());
      } else {
        pendingPlanDraft = msg['plan_draft'] as Map<String, dynamic>?;
        if (pendingPlanDraft == null) {
          unawaited(loadPlanDraft());
        }
        if (msg['tool_actions'] is List &&
            (msg['tool_actions'] as List).isNotEmpty) {
          unawaited(refreshTodayView());
        }
      }
      if (_liveVoiceV2?.isPlaybackActive ?? false) {
        _speaking = true;
        liveSession.state = LiveState.speaking;
      } else {
        _speaking = false;
        liveSession.state = LiveState.listening;
      }
    }
    if (type == 'turn_cancelled') {
      _speaking = false;
      liveSession.state = LiveState.listening;
    }
    notifyListeners();
  }

  Future<void> _stopVoiceLoop() async {
    final loop = _voiceLoop;
    _voiceLoop = null;
    if (loop != null) {
      await loop.stop();
      await loop.dispose();
    }
  }

  Future<void> _playLiveGreeting({bool useWsPath = false}) async {
    try {
      final showIntro = wakeWordEnabled && !await WakeWordPrefs.introShown();
      final greeting = await api.liveGreeting(
        inLive: true,
        wakeEnabled: wakeWordEnabled,
        showWakeIntro: showIntro,
      );
      if (showIntro) {
        await WakeWordPrefs.markIntroShown();
      }
      final text = greeting['assistantMessage'] as String?;
      if (text == null || text.isEmpty) return;
      lastReply = text;
      notifyListeners();
      if (greeting['speak'] != true) {
        await syncWakeListener();
        return;
      }
      if (useWsPath && (_liveVoiceV2?.isActive ?? false)) {
        final voice = greeting['voiceId'] as String?;
        final tts = await api.tts(text, voice: voice);
        final b64 = tts['audio_base64'] as String?;
        final mime = tts['audio_mime'] as String? ?? 'audio/mpeg';
        if (b64 != null && b64.isNotEmpty) {
          await _liveVoiceV2!.playGreeting(base64Decode(b64), mime);
        }
        await syncWakeListener();
        return;
      }
      final voice = greeting['voiceId'] as String?;
      final tts = await api.tts(text, voice: voice);
      await _playAudioResponse(tts);
      await syncWakeListener();
    } catch (_) {}
  }

  Future<void> _handleVoiceSegment(List<int> bytes) async {
    if (token == null) return;
    if (_processingTurn && !_speaking) return;
    if (_processingTurn && _speaking) {
      _turnGeneration++;
      _speaking = false;
      await _player.stop();
    }
    final turnGen = ++_turnGeneration;
    _processingTurn = true;
    liveSession.state = LiveState.thinking;
    notifyListeners();
    var shouldRefreshToday = false;
    try {
      turnError = null;
      const filename = 'turn.webm';
      final res = await api.audioTurn(
        bytes,
        filename: kIsWeb ? filename : 'turn.m4a',
        sessionId: liveSession.sessionId,
      );
      if (turnGen != _turnGeneration) return;
      final returnedSid = res['session_id'] as String?;
      if (returnedSid != null &&
          (liveSession.sessionId == null || liveSession.sessionId!.isEmpty)) {
        liveSession.sessionId = returnedSid;
      }
      lastTranscript = AppConfig.showLiveTranscript
          ? res['transcript'] as String?
          : null;
      lastReply =
          (res['assistantMessage'] as String?) ?? (res['reply'] as String?);
      companionMode = res['mode'] as String? ?? companionMode;
      companionEmotion =
          res['emotion'] as Map<String, dynamic>? ?? companionEmotion;
      memoriesUsed = (res['memories_used'] as List? ?? [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      suggestedActions = (res['suggested_actions'] as List? ?? [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      confirmationPrompt = res['confirmation_prompt'] as String?;
      requiresConfirmation = res['requires_confirmation'] as bool? ?? false;
      if (res['draft_confirmed'] == true) {
        pendingPlanDraft = null;
        shouldRefreshToday = true;
      } else {
        pendingPlanDraft = res['plan_draft'] as Map<String, dynamic>?;
        if (pendingPlanDraft == null) {
          await loadPlanDraft();
        }
        if (res['tool_actions'] is List &&
            (res['tool_actions'] as List).isNotEmpty) {
          shouldRefreshToday = true;
        }
      }
      if (turnGen != _turnGeneration) return;
      await _playAudioResponse(res, turnGen: turnGen);
      unawaited(refreshConversationSessions());
    } on TimeoutException {
      if (turnGen == _turnGeneration) {
        turnError =
            'AiPal is still taking too long to respond. Check that the local backend is running and the AI provider is responding, then try again.';
      }
    } catch (e) {
      if (turnGen == _turnGeneration) {
        turnError = _friendlyTurnError(e);
      }
    } finally {
      if (turnGen == _turnGeneration) {
        _processingTurn = false;
        if (liveSession.isActive && !_speaking) {
          liveSession.state = LiveState.listening;
        }
        notifyListeners();
      }
      if (shouldRefreshToday) {
        unawaited(refreshTodayView());
      }
    }
  }

  Future<void> _playAudioResponse(
    Map<String, dynamic> res, {
    int? turnGen,
  }) async {
    final b64 = res['audio_base64'] as String?;
    if (b64 == null || b64.isEmpty) return;
    final bytes = base64Decode(b64);
    final mime = res['audio_mime'] as String? ?? 'audio/mpeg';

    _speaking = true;
    if (liveSession.isActive) {
      liveSession.state = LiveState.speaking;
    }
    notifyListeners();

    try {
      await _player.stop();
      final completer = Completer<void>();
      late final StreamSubscription<void> sub;
      sub = _player.onPlayerComplete.listen(
        (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      try {
        await _player.play(BytesSource(bytes, mimeType: mime));
        await completer.future.timeout(
          const Duration(minutes: 2),
          onTimeout: () {},
        );
      } finally {
        await sub.cancel();
      }
    } catch (_) {
    } finally {
      if (turnGen == null || turnGen == _turnGeneration) {
        _speaking = false;
        if (liveSession.isActive) {
          liveSession.state = LiveState.listening;
        }
        notifyListeners();
      }
    }
  }
}
