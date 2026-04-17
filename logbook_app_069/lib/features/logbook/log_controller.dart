import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;

import 'models/log_model.dart';
import 'package:logbook_app_069/services/access_control_service.dart';
import 'package:logbook_app_069/services/mongo_service.dart';
import 'package:logbook_app_069/helpers/log_helper.dart';

class LogController {
  final ValueNotifier<List<LogModel>> logsNotifier = ValueNotifier([]);
  final ValueNotifier<List<LogModel>> filteredLogs = ValueNotifier([]);
  final Box<LogModel> _myBox = Hive.box<LogModel>('offline_logs');

  String _currentQuery = '';

  final String userId;
  final String userRole;
  final String teamId;

  List<LogModel> get logs => logsNotifier.value;

  LogController({
    required this.userId,
    required this.userRole,
    required this.teamId,
  });

  List<LogModel> _localTeamLogs() {
    return _myBox.values.where((log) => log.teamId == teamId).toList();
  }

  dynamic _findBoxKeyForLog(LogModel target) {
    for (final key in _myBox.keys) {
      final stored = _myBox.get(key);
      if (stored == null) {
        continue;
      }

      final sameId = target.idHex != null && stored.idHex == target.idHex;
      final sameFallback =
          stored.authorId == target.authorId &&
          stored.teamId == target.teamId &&
          stored.date == target.date &&
          stored.title == target.title;

      if (sameId || sameFallback) {
        return key;
      }
    }

    return null;
  }

  Future<void> _replaceLocalTeamLogs(List<LogModel> cloudAndMergedData) async {
    final keysToDelete = <dynamic>[];

    final newFingerprints = cloudAndMergedData
        .map(
          (log) =>
              '${log.authorId}-${log.teamId}-${log.date.toIso8601String()}-${log.title}',
        )
        .toSet();

    for (final key in _myBox.keys) {
      final stored = _myBox.get(key);
      if (stored != null) {
        final storedFingerprint =
            '${stored.authorId}-${stored.teamId}-${stored.date.toIso8601String()}-${stored.title}';

        if (stored.teamId == teamId ||
            newFingerprints.contains(storedFingerprint)) {
          keysToDelete.add(key);
        }
      }
    }

    if (keysToDelete.isNotEmpty) {
      await _myBox.deleteAll(keysToDelete);
    }

    if (cloudAndMergedData.isNotEmpty) {
      await _myBox.addAll(cloudAndMergedData);
    }
  }

  List<LogModel> _mergeLogs(
    List<LogModel> localLogs,
    List<LogModel> cloudLogs,
  ) {
    final merged = <String, LogModel>{};

    for (final log in cloudLogs) {
      final fingerprint =
          '${log.authorId}-${log.teamId}-${log.date.toIso8601String()}-${log.title}';
      merged[fingerprint] = log;
    }

    for (final log in localLogs) {
      final fingerprint =
          '${log.authorId}-${log.teamId}-${log.date.toIso8601String()}-${log.title}';

      if (!merged.containsKey(fingerprint) || !log.isSynced) {
        merged[fingerprint] = log;
      }
    }

    final result = merged.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  Future<void> _syncPendingLocalLogs(List<LogModel> localLogs) async {
    for (int i = 0; i < localLogs.length; i++) {
      final log = localLogs[i];
      if (!log.isSynced) {
        try {
          await MongoService().updateLog(log);
          final syncedLog = log.copyWith(isSynced: true);
          localLogs[i] = syncedLog;

          final boxKey = _findBoxKeyForLog(log);
          if (boxKey != null) {
            await _myBox.put(boxKey, syncedLog);
          }
        } catch (_) {}
      }
    }
  }

  void searchLog(String query) {
    _currentQuery = query;
    if (query.isEmpty) {
      filteredLogs.value = logsNotifier.value;
    } else {
      filteredLogs.value = logsNotifier.value
          .where(
            (log) =>
                log.title.toLowerCase().contains(query.toLowerCase()) ||
                log.description.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    }
  }

  void _syncFilteredLogs() {
    searchLog(_currentQuery);
  }

  /// CREATE: Simpan lokal dulu, lalu sync ke Cloud di background.
  Future<bool> addLog(
    String title,
    String desc,
    String category,
    bool isPublic,
    [String? imagePath]
  ) async {
    final newLog = LogModel(
      id: ObjectId(),
      title: title,
      description: desc,
      date: DateTime.now(),
      category: category,
      authorId: userId,
      teamId: teamId,
      isSynced: false, // Awalnya selalu false
      isPublic: isPublic,
      imagePath: imagePath,
    );

    try {
      final boxKey = await _myBox.add(newLog);

      final currentLogs = List<LogModel>.from(logsNotifier.value);
      currentLogs.add(newLog);
      logsNotifier.value = currentLogs;
      _syncFilteredLogs();

      try {
        await MongoService().insertLog(newLog);

        final syncedLog = newLog.copyWith(isSynced: true);
        await _myBox.put(boxKey, syncedLog);

        final logIndex = logsNotifier.value.indexWhere(
          (log) => log.id == newLog.id,
        );
        if (logIndex != -1) {
          final currentLogs = List<LogModel>.from(logsNotifier.value);
          currentLogs[logIndex] = syncedLog;
          logsNotifier.value = currentLogs;
          _syncFilteredLogs();
        }

        await LogHelper.writeLog(
          "SUCCESS: Data '${newLog.title}' tersinkron ke Cloud",
          source: "log_controller.dart",
          level: 2,
        );
      } catch (e) {
        await LogHelper.writeLog(
          "WARNING: Data tersimpan lokal, akan sinkron saat online - $e",
          source: "log_controller.dart",
          level: 1,
        );
      }

      await LogHelper.writeLog(
        "SUCCESS: Tambah data '${newLog.title}' ke Hive & UI",
        source: "log_controller.dart",
        level: 2,
      );
      return true;
    } catch (e) {
      await LogHelper.writeLog(
        "ERROR: Gagal menyimpan data lokal - $e",
        source: "log_controller.dart",
        level: 1,
      );
      return false;
    }
  }

  /// UPDATE: Simpan perubahan ke Hive dulu, lalu sync ke Cloud.
  Future<bool> updateLog(
    int index,
    String title,
    String desc,
    String category,
    bool isPublic,
    [String? imagePath]
  ) async {
    final currentLogs = List<LogModel>.from(logsNotifier.value);
    final oldLog = currentLogs[index];

    final bool canUpdate = AccessControlService.canPerform(
      userRole,
      AccessControlService.actionUpdate,
      isOwner: oldLog.authorId == userId,
    );

    if (!canUpdate) {
      await LogHelper.writeLog(
        "SECURITY BREACH: Unauthorized update attempt by $userId",
        source: "log_controller.dart",
        level: 1,
      );
      return false;
    }

    final updatedLog = LogModel(
      id: oldLog.id, // ID harus tetap sama
      title: title,
      description: desc,
      date: DateTime.now(),
      category: category,
      authorId: oldLog.authorId,
      teamId: oldLog.teamId,
      isSynced: false, // Tandai sebagai belum sinkron saat diedit
      isPublic: isPublic,
      imagePath: imagePath,
    );

    try {
      final boxKey = _findBoxKeyForLog(oldLog);
      if (boxKey != null) {
        await _myBox.put(boxKey, updatedLog);
      } else {
        await _myBox.add(updatedLog);
      }

      currentLogs[index] = updatedLog;
      logsNotifier.value = currentLogs;
      _syncFilteredLogs();

      try {
        await MongoService().updateLog(updatedLog);

        final syncedLog = updatedLog.copyWith(isSynced: true);
        if (boxKey != null) {
          await _myBox.put(boxKey, syncedLog);
        }

        final logIndex = logsNotifier.value.indexWhere(
          (log) => log.id == updatedLog.id,
        );
        if (logIndex != -1) {
          final currentLogs = List<LogModel>.from(logsNotifier.value);
          currentLogs[logIndex] = syncedLog;
          logsNotifier.value = currentLogs;
          _syncFilteredLogs();
        }

        await LogHelper.writeLog(
          "SUCCESS: Sinkronisasi Update '${oldLog.title}' Berhasil",
          source: "log_controller.dart",
          level: 2,
        );
      } catch (e) {
        await LogHelper.writeLog(
          "WARNING: Perubahan tersimpan lokal, sync Cloud ditunda - $e",
          source: "log_controller.dart",
          level: 1,
        );
      }

      await LogHelper.writeLog(
        "SUCCESS: Update lokal '${oldLog.title}' Berhasil",
        source: "log_controller.dart",
        level: 2,
      );
      return true;
    } catch (e) {
      await LogHelper.writeLog(
        "ERROR: Gagal menyimpan perubahan lokal - $e",
        source: "log_controller.dart",
        level: 1,
      );
      return false;
    }
  }

  /// DELETE: Hapus lokal dulu, lalu coba hapus di Cloud.
  Future<void> removeLog(int index) async {
    final currentLogs = List<LogModel>.from(logsNotifier.value);
    final targetLog = currentLogs[index];

    final bool canDelete = AccessControlService.canPerform(
      userRole,
      AccessControlService.actionDelete,
      isOwner: targetLog.authorId == userId,
    );

    if (!canDelete) {
      await LogHelper.writeLog(
        "SECURITY BREACH: Unauthorized delete attempt by $userId",
        source: "log_controller.dart",
        level: 1,
      );
      return;
    }

    try {
      final boxKey = _findBoxKeyForLog(targetLog);
      if (boxKey != null) {
        await _myBox.delete(boxKey);
      }

      currentLogs.removeAt(index);
      logsNotifier.value = currentLogs;
      _syncFilteredLogs();

      if (targetLog.id != null) {
        try {
          await MongoService().deleteLog(targetLog.id!);
          await LogHelper.writeLog(
            "SUCCESS: Sinkronisasi Hapus '${targetLog.title}' Berhasil",
            source: "log_controller.dart",
            level: 2,
          );
        } catch (e) {
          await LogHelper.writeLog(
            "WARNING: Data dihapus lokal, sinkronisasi hapus Cloud gagal - $e",
            source: "log_controller.dart",
            level: 1,
          );
        }
      }

      await LogHelper.writeLog(
        "SUCCESS: Hapus lokal '${targetLog.title}' Berhasil",
        source: "log_controller.dart",
        level: 2,
      );
    } catch (e) {
      await LogHelper.writeLog(
        "ERROR: Gagal menghapus data lokal - $e",
        source: "log_controller.dart",
        level: 1,
      );
    }
  }

  Future<void> saveToDisk() async {
    await _replaceLocalTeamLogs(logsNotifier.value);
  }

  /// LOAD: Ambil dari Hive dulu, lalu sync dari Cloud di background.
  Future<List<LogModel>> loadLogs() async {
    final localLogs = _localTeamLogs();
    logsNotifier.value = localLogs;
    _syncFilteredLogs();

    try {
      if (localLogs.isNotEmpty) {
        await _syncPendingLocalLogs(localLogs);
      }

      final cloudData = await MongoService().getLogs(teamId);
      final mergedLogs = _mergeLogs(localLogs, cloudData);

      await _replaceLocalTeamLogs(mergedLogs);
      logsNotifier.value = mergedLogs;
      _syncFilteredLogs();

      await LogHelper.writeLog(
        "SYNC: Data lokal dan Atlas berhasil disejajarkan",
        source: "log_controller.dart",
        level: 2,
      );

      return mergedLogs;
    } catch (e) {
      await LogHelper.writeLog(
        "OFFLINE: Menggunakan data cache lokal - $e",
        source: "log_controller.dart",
        level: 2,
      );
      return localLogs;
    }
  }

  Future<List<LogModel>> loadFromDisk() async {
    return loadLogs();
  }
}
