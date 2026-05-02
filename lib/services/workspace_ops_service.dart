import '../data/models/workspace_ops.dart';
import 'api_service.dart';

class WorkspaceOpsService {
  WorkspaceOpsService._();
  static final WorkspaceOpsService instance = WorkspaceOpsService._();

  Future<WorkspaceStatusResponse> getStatus() async {
    final m = await ApiService.instance.getWorkspaceStatus();
    return WorkspaceStatusResponse.fromJson(m);
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
}
