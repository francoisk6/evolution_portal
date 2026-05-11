import '../data/models/workspace_ops.dart';
import '../data/models/workspace_transaction_cleanup.dart';
import 'api_service.dart';

class WorkspaceOpsService {
  WorkspaceOpsService._();
  static final WorkspaceOpsService instance = WorkspaceOpsService._();

  Future<WorkspaceStatusResponse> getStatus() async {
    final m = await ApiService.instance.getWorkspaceStatus();
    return WorkspaceStatusResponse.fromJson(m);
  }

  Future<WorkspaceListResponse> getWorkspaces() async {
    final m = await ApiService.instance.getWorkspaces();
    return WorkspaceListResponse.fromJson(m);
  }

  Future<WorkspaceAuditSummaryResponse> getAuditSummary({
    bool verifyRemote = false,
    int limit = 200,
    int sampleLimit = 20,
  }) async {
    final m = await ApiService.instance.getWorkspaceAuditSummary(
      verifyRemote: verifyRemote,
      limit: limit,
      sampleLimit: sampleLimit,
    );
    return WorkspaceAuditSummaryResponse.fromJson(m);
  }

  Future<WorkspaceTransactionCleanupResponse> cleanupTransaction({
    required String workspaceSlug,
    required int localTransactionId,
    required bool dryRun,
  }) async {
    final m = await ApiService.instance.workspaceTransactionCleanup(
      workspaceSlug: workspaceSlug,
      localTransactionId: localTransactionId,
      dryRun: dryRun,
    );
    return WorkspaceTransactionCleanupResponse.fromJson(m);
  }
}
