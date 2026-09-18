import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/expense_model.dart';
import '../models/expense_participant.dart';
import '../models/financial_analytics.dart';
import '../models/house_model.dart';
import 'house_service.dart';

/// Read-only analytics loader.
///
/// Loads a single [FinancialSnapshot] for a house from the existing financial
/// source of truth (house_expenses + participants subcollections + users +
/// houses). This service never writes to Firestore and never attaches
/// listeners; every load is a one-shot read pattern:
///
///   1 expense query + N parallel participant reads
///   + batched user-name resolution + 1 house read.
class AnalyticsService {
  static const Duration _networkTimeout = Duration(seconds: 15);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final HouseService _houseService = HouseService();

  /// Pure helper: collects the distinct user IDs that need name resolution
  /// for a snapshot (expense creators + all participant user IDs).
  static List<String> collectUserIdsForNameResolution(
    List<ExpenseModel> expenses,
    Map<String, List<ExpenseParticipant>> participantsByExpenseId,
  ) {
    final ids = <String>{};

    for (final expense in expenses) {
      final createdBy = expense.createdBy.trim();
      if (createdBy.isNotEmpty) {
        ids.add(createdBy);
      }
    }

    for (final participants in participantsByExpenseId.values) {
      for (final participant in participants) {
        final userId = participant.userId.trim();
        if (userId.isNotEmpty) {
          ids.add(userId);
        }
      }
    }

    return ids.toList(growable: false);
  }

  /// Loads all financial source data for a house in one pass and returns an
  /// immutable [FinancialSnapshot]. Throws if any participant read fails so
  /// that financial data is never silently incomplete.
  Future<FinancialSnapshot> loadFinancialSnapshot(String houseId) async {
    final trimmedHouseId = houseId.trim();
    if (trimmedHouseId.isEmpty) {
      throw ArgumentError('House ID cannot be empty');
    }

    try {
      final expenses = await _loadExpenses(trimmedHouseId);
      final participantsByExpenseId = await _loadAllParticipants(expenses);

      final userIdsToResolve = collectUserIdsForNameResolution(expenses, participantsByExpenseId);

      final namesFuture = _houseService.getUserNamesByIds(userIdsToResolve);
      final houseFuture = _loadHouseSafely(trimmedHouseId);
      final namesById = await namesFuture;
      final house = await houseFuture;

      return FinancialSnapshot(
        houseId: trimmedHouseId,
        expenses: expenses,
        participantsByExpenseId: participantsByExpenseId,
        namesById: namesById,
        house: house,
        loadedAt: DateTime.now(),
      );
    } on TimeoutException catch (e, stackTrace) {
      debugPrint('AnalyticsService.loadFinancialSnapshot timeout: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw StateError('Request timed out. Please check your network and try again.');
    } on FirebaseException catch (e, stackTrace) {
      debugPrint('AnalyticsService.loadFinancialSnapshot firebase error: ${e.code}');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  /// ONE query for all expenses of the house. Uses the same query shape as
  /// ExpenseService.streamExpenses but as a one-shot get().
  Future<List<ExpenseModel>> _loadExpenses(String houseId) async {
    final snapshot = await _db
        .collection('house_expenses')
        .where('houseId', isEqualTo: houseId)
        .get()
        .timeout(_networkTimeout);

    final expenses = snapshot.docs.map(ExpenseModel.fromFirestore).toList();
    expenses.sort((left, right) {
      final leftCreatedAt = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightCreatedAt = right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightCreatedAt.compareTo(leftCreatedAt);
    });
    return expenses;
  }

  /// Loads every expense's participants concurrently. A failure in any single
  /// read is surfaced with the offending expense ID in the error message; it
  /// is never converted into fabricated/zero participant data.
  Future<Map<String, List<ExpenseParticipant>>> _loadAllParticipants(
    List<ExpenseModel> expenses,
  ) async {
    if (expenses.isEmpty) {
      return const <String, List<ExpenseParticipant>>{};
    }

    final participantLists = await Future.wait(
      expenses.map((expense) => _loadParticipants(expense.id)),
    );

    return <String, List<ExpenseParticipant>>{
      for (var index = 0; index < expenses.length; index++)
        expenses[index].id: participantLists[index],
    };
  }

  Future<List<ExpenseParticipant>> _loadParticipants(String expenseId) async {
    try {
      final snapshot = await _db
          .collection('house_expenses')
          .doc(expenseId)
          .collection('participants')
          .get()
          .timeout(_networkTimeout);

      return snapshot.docs.map(ExpenseParticipant.fromFirestore).toList();
    } catch (error, stackTrace) {
      debugPrint('AnalyticsService._loadParticipants failed for expense $expenseId: $error');
      debugPrintStack(stackTrace: stackTrace);
      Error.throwWithStackTrace(
        StateError('Failed to load participants for expense $expenseId: $error'),
        stackTrace,
      );
    }
  }

  /// House doc is auxiliary context (roster only). A failed house read must
  /// not abort financial analytics, so it degrades to null.
  Future<House?> _loadHouseSafely(String houseId) async {
    try {
      return await _houseService.getHouseById(houseId);
    } catch (error) {
      debugPrint('AnalyticsService._loadHouseSafely failed for house $houseId: $error');
      return null;
    }
  }
}
